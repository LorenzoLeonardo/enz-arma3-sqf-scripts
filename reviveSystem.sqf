// ==============================================================================================================
// AI Revive System Script
// Author: Lorenzo Leonardo
// Contact: enzotechcomputersolutions@gmail.com
// ==============================================================================================================
// 
// Description:
// This script implements a fully AI-driven revive system for incapacitated units, allowing friendly (and in some
// cases enemy) AI to revive downed soldiers under combat conditions. It includes intelligent medic selection,  
// realistic bleedout timers, headshot and explosive damage handling, and dynamic prioritization of medics
// based on proximity, threat levels, and availability.
// 
// Features:
// - Automatic AI revive for incapacitated units within a group.
// - Prioritizes medics from the same group, then other friendlies, then any available AI (including enemies if friendlies are too far).
// - Intelligent medic assignment that avoids multiple units trying to revive the same target.
// - Configurable bleedout time before the unit dies if not revived.
// - Handles headshot lethality with helmet-based survival chances.
// - Handles explosive damage with distance-based lethality scaling.
// - Revived units are fully restored and can become captives if revived by enemies.
// - Prevents revive loops, duplicate revives, and AI getting stuck.
// - Dynamic movement timeout based on medic-to-target distance.
// - AI revives use animations for realism.
// - units drop weapons and surrender when revived by enemies.
// - Fully configurable constants for range, timers, and thresholds.
// 
// Parameters:
//   _group                        - The group whose units will have the revive system enabled.
// 
// Constants (modifiable in script):
//   BLEEDOUT_TIME                 - time in seconds before incapacitated unit dies if not revived (default: 300).
//   REVIVE_RANGE                  - distance in meters a medic must reach to start revive (default: 3).
//   FRIENDLY_MEDIC_FAR_THRESHOLD  - distance threshold in meters beyond which enemies may revive the unit (default: 200).
// 
// Usage Example:
//   [group this] execVM "reviveSystem.sqf";
// 
// Notes:
// - Works entirely server-side for AI logic, but event handlers are applied to units in the group.
// - Can be adapted for player revive logic by adding custom event handling.
// - Revive animations and states can be replaced with mod-specific actions for better integration.
// ==============================================================================================================
#include "common.sqf"

#define BLEEDOUT_TIME 300 // 5 minutes
#define REVIVE_RANGE 3 // 3 meters
#define FRIENDLY_MEDIC_FAR_THRESHOLD 120 // 120 meters

params ["_group"];

// ===============================
// FUNCTION: get Best Medic
// ===============================
ETCS_fnc_getBestMedic = {
	params ["_injured"];
	private _injuredSide = side _injured;
	private _groupUnits = units group _injured;

	// Gather all valid units once
	private _allValidUnits = allUnits select {
		(_x != _injured) &&
		([_x] call ETCS_fnc_isUnitGood) &&
		!([_x] call ETCS_fnc_isReviving) &&
		(isNull objectParent _x) &&
		!(captive _x)
	};

	private _candidates = [];

	// 1️⃣ Same group medics
	_candidates = _groupUnits select {
		_x in _allValidUnits && (_x getUnitTrait "Medic")
	};

	// 2️⃣ Same group non-medics
	if (_candidates isEqualTo []) then {
		_candidates = _groupUnits select {
			_x in _allValidUnits
		};
	};

	// 3️⃣ Other friendly units
	if (_candidates isEqualTo []) then {
		_candidates = _allValidUnits select {
			side _x == _injuredSide
		};
	};

	// 4️⃣ Fallback to *anyone* (already in _allValidUnits)
	if (_candidates isEqualTo []) then {
		_candidates = _allValidUnits;
	};

	if (_candidates isEqualTo []) exitWith {
		objNull
	};

	// find nearest friendly medic or fallback unit
	private _nearestMedic = [_injured, _candidates] call ETCS_fnc_findNearestUnit;
	private _nearestMedicDist = if (isNull _nearestMedic) then {
		1e10
	} else {
		_injured distance _nearestMedic
	};

	// find nearest enemy
	private _enemies = _allValidUnits select {
		side _x != _injuredSide
	};
	private _nearestEnemy = [_injured, _enemies] call ETCS_fnc_findNearestUnit;
	private _nearestEnemyDist = if (isNull _nearestEnemy) then {
		1e10
	} else {
		_injured distance _nearestEnemy
	};

	// Enemy revival logic if friendlies too far
	if ((_nearestEnemyDist < _nearestMedicDist) && (_nearestMedicDist > FRIENDLY_MEDIC_FAR_THRESHOLD)) exitWith {
		_nearestEnemy
	};

	_nearestMedic
};

// ===============================
// FUNCTION: Bleedout Timer
// ===============================
ETCS_fnc_bleedoutTimer = {
	params ["_injured"];
	private _startTime = time;
	_injured setVariable ["bleedoutTime", time + BLEEDOUT_TIME, true];
	// Wait until unit dies, is revived, or bleedout time expires
	waitUntil {
		sleep 1;
		!alive _injured
		|| !([_injured] call ETCS_fnc_isInjured)
		|| ((time - _startTime) >= BLEEDOUT_TIME);
	};

	// Determine what happened
	if (alive _injured && ([_injured] call ETCS_fnc_isInjured) && ((time - _startTime) >= BLEEDOUT_TIME)) then {
		// Bleedout expired → kill the unit
		[_injured, false] call ETCS_fnc_setReviveProcess;
		_injured setDamage 1;
	} else {
		// Unit was revived or died naturally → just stop revive process
		[_injured, false] call ETCS_fnc_setReviveProcess;
	};
	_injured setVariable ["bleedoutTime", -1, true];
};

// ===============================
// FUNCTION: Calculate Timeout for Medic Movement
// ===============================
ETCS_fnc_getDynamicTimeout = {
	params ["_medic", "_injured"];

	private _pathDist = _medic distance _injured;

	// 10 sec base + (distance / 3 m/s), capped at 90 sec
	time + ((10 max (_pathDist / 3)) min 90)
};

// ===============================
// FUNCTION: Reset Revive State
// ===============================
ETCS_fnc_unlockReviveState = {
	params ["_medic", "_injured"];

	if (!isNull _medic) then {
		{
			_medic enableAI _x;
		} forEach ["MOVE", "PATH", "AUTOCOMBAT", "TARGET", "SUPPRESSION"];
		private _ldr = leader _medic;
		if (!isNull _ldr && alive _ldr) then {
			_medic doFollow _ldr;
		};
		[_medic, false] call ETCS_fnc_setReviving;
		if (_medic == player) then {
			player setVariable ["injuredToRevive", objNull, true];
		};
	};

	if (!isNull _injured) then {
		[_injured, false] call ETCS_fnc_setBeingRevived;
		if (_injured == player) then {
			player setVariable ["reviverAssigned", objNull, true];
		};
	};
};

// ===============================
// FUNCTION: Start Revive State
// ===============================
ETCS_fnc_lockReviveState = {
	params ["_medic", "_injured"];
	// lock injured and medic
	if (!isNull _medic) then {
		[_medic, true] call ETCS_fnc_setReviving;
		if (_medic == player) then {
			player setVariable ["injuredToRevive", _injured, true];
		};
	};

	if (!isNull _injured) then {
		[_injured, true] call ETCS_fnc_setBeingRevived;
		if (_injured == player) then {
			player setVariable ["reviverAssigned", _medic, true];
		};
	};

	doStop _medic;
	// Disable combat distractions
	{
		_medic disableAI _x
	} forEach ["AUTOCOMBAT", "TARGET", "SUPPRESSION"];
	// Allow AI to choose stance for movement
	_medic setUnitPos "AUTO";
};

// ===============================
// FUNCTION: Wait for Medic Arrival
// ===============================
ETCS_fnc_waitForMedicArrival = {
	params ["_medic", "_injured"];

	// Wait for medic to arrive within range or timeout
	private _timeout = [_medic, _injured] call ETCS_fnc_getDynamicTimeout;
	waitUntil {
		sleep 1;
		(!alive _injured)
		|| ([_injured] call ETCS_fnc_isRevived)
		|| (_medic distance _injured < REVIVE_RANGE)
		|| (!alive _medic)
		|| ([_medic] call ETCS_fnc_isInjured)
		|| (time > _timeout)
	};

	(_medic distance _injured) < REVIVE_RANGE
};

// ===============================
// FUNCTION: Make Unconscious
// ===============================
ETCS_fnc_makeUnconscious = {
	params ["_unit"];

	[_unit, true] call ETCS_fnc_setReviveProcess;
	// Reset revive state for NEW incapacitation
	[_unit, false] call ETCS_fnc_setRevived;
	[_unit, false] call ETCS_fnc_setBeingRevived;

	// if the injured is in a vehicle or static weapon, remove them
	private _vehicle = objectParent _unit;
	if (!(isNull _vehicle) && isTouchingGround (_vehicle)) then {
		moveOut _unit;
	};
	// Make unit unconscious
	_unit setUnconscious true;
	{
		_unit disableAI _x
	} forEach ["MOVE"];
	_unit setCaptive true;
	// animate injury
	_unit playMoveNow "AinjPpneMstpSnonWrflDnon";

	// Bleeding out timer
	[_unit] spawn ETCS_fnc_bleedoutTimer;

	// AI revive logic
	[_unit] spawn {
		params ["_injured"];
		[_injured] call ETCS_fnc_reviveLoop;

		// Reset the process flag after loop ends
		[_injured, false] call ETCS_fnc_setReviveProcess;
	};
};

// ===============================
// FUNCTION: Headshot damage Handling
// ===============================
ETCS_fnc_headshotDamageHandling = {
	params ["_unit", "_damage"];

	// ----- CONFIG -----
	// default survival chance without helmet
	private _baseSurviveChance = 0.2;
	// threshold for instant-kill
	private _minDamageToAlwaysKill = 0.85;
	// helmet protection bonus
	private _helmetBonus = 0.3;

	// ----- HELMET CHECK -----
	private _headgearClass = toLower (headgear _unit);
	private _isHelmet = (
	// vanilla helmets
	(_headgearClass find "helmet" != -1) ||
	// CUP helmets
	(_headgearClass find "cup_h" == 0) ||
	// Russian 6b series
	(_headgearClass find "6b" != -1) ||
	// Russian patterns
	(_headgearClass find "rus" != -1) ||
	// Special forces
	(_headgearClass find "spetsnaz" != -1));

	private _adjustedSurviveChance = if (_isHelmet) then {
		_baseSurviveChance + _helmetBonus
	} else {
		_baseSurviveChance
	};

	// Clamp survival chance between 0 and 0.95 (avoid immortals)
	_adjustedSurviveChance = _adjustedSurviveChance min 0.95 max 0;

	// ----- damage OUTCOME -----
	if (_damage >= _minDamageToAlwaysKill) exitWith {
		// lethal
		1
	};

	// Roll survival
	private _roll = random 1;
	if (_roll < _adjustedSurviveChance) then {
		[_unit] call ETCS_fnc_makeUnconscious;
		// heavily injured, unconscious
		0.9
	} else {
		// failed survival roll = lethal
		1
	};
};

// ===============================
// FUNCTION: Torso damage Handling
// ===============================
ETCS_fnc_torsoDamageHandling = {
	params ["_unit", "_damage"];

	// ----- CONFIG -----
	// default survival chance without vest
	private _baseSurviveChance = 0.3;
	// torso shots are a bit more survivable than head
	private _minDamageToAlwaysKill = 0.9;
	// ballistic vest bonus
	private _vestBonus = 0.4;

	// ----- vest CHECK -----
	private _vestClass = toLower (vest _unit);
	private _isVest = ((_vestClass find "vest" != -1) ||
	(_vestClass find "plate" != -1) ||
	(_vestClass find "armor" != -1) ||
	(_vestClass find "carrier" != -1) ||
	(_vestClass find "6b" != -1) ||
	(_vestClass find "spetsnaz" != -1) ||
	(_vestClass find "cup_v" == 0) ||
	(_vestClass find "v_" == 0));

	private _adjustedSurviveChance = if (_isVest) then {
		_baseSurviveChance + _vestBonus
	} else {
		_baseSurviveChance
	};

	// Clamp survival chance
	_adjustedSurviveChance = _adjustedSurviveChance min 0.95 max 0;

	// ----- damage OUTCOME -----
	if (_damage >= _minDamageToAlwaysKill) exitWith {
		// lethal torso hit
		1
	};

	    // Roll survival
	private _roll = random 1;
	if (_roll < _adjustedSurviveChance) then {
		[_unit] call ETCS_fnc_makeUnconscious;
		// very injured, unconscious
		0.85
	} else {
		// failed survival roll = lethal
		1
	};
};

// ================================
// FUNCTION: Arms damage Handling
// ================================
ETCS_fnc_armDamageHandling = {
	params ["_unit", "_damage"];

	if (_damage >= 0.8) then {
		// 20% chance to get knocked out from shock
		if (random 1 < 0.2) then {
			[_unit] call ETCS_fnc_makeUnconscious;
			// not dead, but badly hurt
			0.7
		} else {
			// normal severe arm injury
			0.8
		};
	} else {
		_damage
	};
};

// ================================
// FUNCTION: Legs damage Handling
// ================================
ETCS_fnc_legDamageHandling = {
	params ["_unit", "_damage"];

	if (_damage >= 0.8) then {
		// 15% chance to get knocked out from shock
		if (random 1 < 0.15) then {
			[_unit] call ETCS_fnc_makeUnconscious;
			0.75
		} else {
			// serious leg injury, but still alive
			0.8
		};
	} else {
		_damage
	};
};

// ===============================
// FUNCTION: Handle Heal
// ===============================
ETCS_fnc_handleHeal = {
	params ["_medic", "_injured"];

	_injured setUnconscious false;
	{
		_injured enableAI _x
	} forEach ["MOVE"];
	_injured setCaptive false;
	_injured setDamage 0.25; // 75% health
	_injured setUnitPos "AUTO";
	_injured playMoveNow "AmovPknlMstpSrasWrflDnon";

	// if revived by an enemy, drop the weapon become a captive
	if (((side _medic) getFriend (side _injured)) < 0.6) then {
		[_injured, _medic] call ETCS_fnc_surrender;
		[_injured] call ETCS_fnc_dropAllWeapons;
	} else {
		if (rating _injured <= -2000) then {
			[_injured, _medic] call ETCS_fnc_surrender;
			[_injured] call ETCS_fnc_dropAllWeapons;
		};
	};

	[_injured, true] call ETCS_fnc_setRevived;
};

// ===============================
// FUNCTION: drop All weapons
// ===============================
ETCS_fnc_dropAllWeapons = {
	params ["_unit"];
	private _pos = getPosATL _unit;
	private _holder = createVehicle ["GroundWeaponHolder", _pos, [], 0, "CAN_COLLIDE"];

	// drop weapons
	{
		_unit removeWeapon _x;
		_holder addWeaponCargoGlobal [_x, 1];
	} forEach weapons _unit;

	// drop magazines
	{
		_unit removeMagazine _x;
		_holder addMagazineCargoGlobal [_x, 1];
	} forEach magazines _unit;

	// drop assigned items (map, compass, NVG, etc.)
	{
		_unit unlinkItem _x;
		_holder addItemCargoGlobal [_x, 1];
	} forEach assignedItems _unit;

	// drop general items
	{
		_unit removeItem _x;
		_holder addItemCargoGlobal [_x, 1];
	} forEach items _unit;

	// drop vest items
	{
		_unit removeItemFromVest _x;
		_holder addItemCargoGlobal [_x, 1];
	} forEach vestItems _unit;

	// drop backpack items
	{
		_unit removeItemFromBackpack _x;
		_holder addItemCargoGlobal [_x, 1];
	} forEach backpackItems _unit;

	// drop uniform items
	{
		_unit removeItemFromUniform _x;
		_holder addItemCargoGlobal [_x, 1];
	} forEach uniformItems _unit;

	// Finally strip containers/clothes
	removeBackpack _unit;
	removeVest _unit;
	removeUniform _unit;
	removeHeadgear _unit;
	removeGoggles _unit;
};

// ===============================
// FUNCTION: Surrender
// ===============================
ETCS_fnc_surrender = {
	params ["_unit", "_medic"];
	// AI won’t target them
	_unit setCaptive true;
	// Add to player's group silently
	[_unit] joinSilent (group _medic);
	_unit doFollow (leader (group _medic));
};

// ===============================
// FUNCTION: Revive Loop (AI logic)
// ===============================
ETCS_fnc_reviveLoop = {
	params ["_injured"];
	private _loopTimeout = time + BLEEDOUT_TIME; // max 5 minutes to try reviving
	private _medic = objNull;

	while { (alive _injured) && !([_injured] call ETCS_fnc_isRevived) && (time < _loopTimeout) } do {
		sleep 0.5;
		if (!alive _injured || ([_injured] call ETCS_fnc_isRevived)) exitWith {
			if (!isNull _medic) then {
				[_medic, _injured] call ETCS_fnc_unlockReviveState;
			};
		};
		// Skip if already being revived
		if ([_injured] call ETCS_fnc_isBeingRevived) then {
			continue
		};

		// find best medic
		_medic = [_injured] call ETCS_fnc_getBestMedic;
		if (isNull _medic || !alive _medic) then {
			continue
		};

		// lock injured and medic
		[_medic, _injured] call ETCS_fnc_lockReviveState;

		_medic doMove (getPosATL _injured);

		 // Wait for medic arrival
		private _arrived = [_medic, _injured] call ETCS_fnc_waitForMedicArrival;
		// If medic didn't arrive in time or died or incapacitated
		if (!_arrived) then {
			[_medic, _injured] call ETCS_fnc_unlockReviveState;
			continue;
		};
		if (([_medic] call ETCS_fnc_isUnitGood) && alive _injured) then {
			// stop and animate revive
			doStop _medic;
			{
				_medic disableAI _x
			} forEach ["MOVE", "PATH"];

			_medic playMoveNow "AinvPknlMstpSnonWnonDnon_medic1";

			// Wait until anim starts or timeout
			private _animStartTime = time;
			waitUntil {
				sleep 0.1;
				(animationState _medic == "AinvPknlMstpSnonWnonDnon_medic1")
				|| ((time - _animStartTime) > 3)
			};

			private _animTime = time + 5;
			waitUntil {
				sleep 0.5;
				(!alive _medic)
				|| ([_medic] call ETCS_fnc_isInjured)
				|| (time > _animTime)
			};
			if (!([_medic] call ETCS_fnc_isUnitGood)) then {
				[_medic, _injured] call ETCS_fnc_unlockReviveState;
				continue;
			};

			// SUCCESS: Revive and heal
			[_medic, _injured] call ETCS_fnc_handleHeal;
		};
		// Always reset states after attempt
		[_medic, _injured] call ETCS_fnc_unlockReviveState;
	};
	[_medic, _injured] call ETCS_fnc_unlockReviveState;
};

// =======================================================
// START: Getter/Setters for Revive States
// =======================================================
ETCS_fnc_isInReviveProcess = {
	params ["_unit"];
	_unit getVariable ["isInReviveProcess", false]
};

ETCS_fnc_setReviveProcess = {
	params ["_unit", "_state"];
	_unit setVariable ["isInReviveProcess", _state, true];
};

ETCS_fnc_isBeingRevived = {
	params ["_unit"];
	_unit getVariable ["beingRevived", false]
};

ETCS_fnc_setBeingRevived = {
	params ["_unit", "_state"];
	_unit setVariable ["beingRevived", _state, true];
};

ETCS_fnc_isRevived = {
	params ["_unit"];
	_unit getVariable ["revived", false]
};

ETCS_fnc_setRevived = {
	params ["_unit", "_state"];
	_unit setVariable ["revived", _state, true];
};

ETCS_fnc_isReviving = {
	params ["_unit"];
	_unit getVariable ["reviving", false]
};

ETCS_fnc_setReviving = {
	params ["_unit", "_state"];
	_unit setVariable ["reviving", _state, true];
};
// =======================================================
// END: Getter/Setters for Revive States
// =======================================================

// ===============================
// FUNCTION: Handle damage
// ===============================
ETCS_fnc_handleDamage = {
	params ["_unit", "_selection", "_damage", "_source", "_projectile"];
	private _result = _damage;

	// Allow lethal finishers if already down
	if ([_unit] call ETCS_fnc_isInjured) exitWith {
		_damage
	};

	switch (true) do {
		// ----- HEAD -----
		case (_selection == "head" && !([_unit] call ETCS_fnc_isInReviveProcess)): {
			_result = [_unit, _damage] call ETCS_fnc_headshotDamageHandling;
		};

		// ----- TORSO -----
		case (_selection == "body" && !([_unit] call ETCS_fnc_isInReviveProcess)): {
			_result = [_unit, _damage] call ETCS_fnc_torsoDamageHandling;
		};

		// ----- ARMS -----
		case ((_selection in ["hand_l", "hand_r", "arm_l", "arm_r"]) && !([_unit] call ETCS_fnc_isInReviveProcess)): {
			_result = [_unit, _damage] call ETCS_fnc_armDamageHandling;
		};

		// ----- LEGS -----
		case ((_selection in ["leg_l", "leg_r", "foot_l", "foot_r"]) && !([_unit] call ETCS_fnc_isInReviveProcess)): {
			_result = [_unit, _damage] call ETCS_fnc_legDamageHandling;
		};

		// ----- GLOBAL NEAR-LETHAL CHECK -----
		case ((_damage >= 0.95) && !([_unit] call ETCS_fnc_isInReviveProcess)): {
			[_unit] call ETCS_fnc_makeUnconscious;
			_result = 0.9;
		};
	};
	_result
};

// ===============================
// apply EVENT HANDLERS to group
// ===============================
ETCS_fnc_registerReviveSystem = {
	params["_group"];
	{
		_x addEventHandler ["HandleDamage", {
			_this call ETCS_fnc_handleDamage
		}];
		_x addEventHandler ["Killed", {
			params ["_unit"];
			[_unit, false] call ETCS_fnc_setReviveProcess;
			[_unit, false] call ETCS_fnc_setBeingRevived;
			[_unit, false] call ETCS_fnc_setReviving;
			[_unit, false] call ETCS_fnc_setRevived;
		}];
	} forEach units _group;
};

ETCS_fnc_drawBleedOutTime = {
	params ["_injured"];
	private _wpPos = getPosATL _injured;

	// Read bleedout time
	private _deadline = _injured getVariable ["bleedoutTime", -1];
	private _timeLeft = if (_deadline > 0) then {
		(_deadline - time) max 0
	} else {
		-1
	};

	// format minutes:seconds
	private _timeText = "";
	if (_timeLeft >= 0) then {
		private _mins = floor (_timeLeft / 60);
		private _secs = floor (_timeLeft % 60);
		_timeText = format ["%1:%2", _mins, if (_secs < 10) then {
			format ["0%1", _secs]
		} else {
			str _secs
		}];
	};
	// 1 meter above the unit
	_wpPos set [2, (_wpPos select 2) + 0.5];
	// Draw (red color)
	drawIcon3D [
		"\A3\ui_f\data\map\markers\military\arrow2_CA.paa",
		[1, 0, 0, 1], // <-- RED
		_wpPos,
		0.5, 0.5,
		180,
		_timeText,
		2,
		0.035,
		"PuristaSemiBold",
		"center",
		true,
		0,
		-0.04
	];
};

ETCS_fnc_draw3DText = {
	addMissionEventHandler ["Draw3D", {
		// --- case 1: player is reviver
		private _injured = player getVariable ["injuredToRevive", objNull];
		if (!isNull _injured && alive _injured) then {
			private _wpPos = getPosATL _injured;
			private _wpText = format ["Revive Injured (%1 m)", round (player distance _wpPos)];

			drawIcon3D [
				"\A3\ui_f\data\map\markers\military\arrow2_CA.paa",
				[0, 1, 1, 1],
				_wpPos,
				0.5, 0.5,
				180,
				_wpText,
				2,
				0.035,
				"PuristaBold",
				"center",
				true,
				0,
				-0.04
			];
		};

		// --- case 2: player is injured
		private _reviver = player getVariable ["reviverAssigned", objNull];
		if (!isNull _reviver && alive _reviver) then {
			private _revPos = getPosATL _reviver;
			// +2 meters above head
			_revPos set [2, (_revPos select 2) + 2];

			private _revText = format [
				"Medic (%1 m)",
				round (player distance _reviver)
			];

			drawIcon3D [
				"\A3\ui_f\data\map\markers\military\arrow2_CA.paa",
				[0, 1, 1, 1],
				_revPos,
				0.6, 0.6,
				180,
				_revText,
				2,
				0.035,
				"PuristaBold",
				"center",
				true,
				0,
				-0.04
			];
		};

		private _incap = allUnits select {
			([_x] call ETCS_fnc_isInjured) &&
			side (group _x) == side (group player)
		};
		{
			[_x] call ETCS_fnc_drawBleedOutTime;
		} forEach _incap;
	}];
};

// Main triggers
[_group] call ETCS_fnc_registerReviveSystem;
[] call ETCS_fnc_draw3DText;