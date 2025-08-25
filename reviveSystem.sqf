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

#define BLEEDOUT_TIME 300 // 5 minutes
#define REVIVE_RANGE 3 // 3 meters
#define FRIENDLY_MEDIC_FAR_THRESHOLD 120 // 120 meters

params ["_group"];

// ===============================
// FUNCTION: Check if unit is ok
// ===============================
fnc_isUnitGood = {
	params ["_unit"];
	!isNull _unit && {
		alive _unit && {
			lifeState _unit != "INCAPACITATED"
		}
	}
};

// ===============================
// FUNCTION: find Nearest Unit
// ===============================
fnc_findNearestUnit = {
	params ["_pos", "_candidates"];

	private _nearestUnit = objNull;
	private _nearestDist = 1e10;  // a very large distance

	{
		private _dist = _pos distance2D _x;
		if (_dist < _nearestDist) then {
			_nearestDist = _dist;
			_nearestUnit = _x;
		};
	} forEach _candidates;

	_nearestUnit
};

// ===============================
// FUNCTION: get Best Medic
// ===============================
fnc_getBestMedic = {
	params ["_injured"];
	private _injuredSide = side _injured;
	private _groupUnits = units group _injured;

	// Gather all valid units once
	private _allValidUnits = allUnits select {
		(_x != _injured) &&
		([_x] call fnc_isUnitGood) &&
		!([_x] call fnc_isReviving) &&
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
	private _nearestMedic = [_injured, _candidates] call fnc_findNearestUnit;
	private _nearestMedicDist = if (isNull _nearestMedic) then {
		1e10
	} else {
		_injured distance2D _nearestMedic
	};

	// find nearest enemy
	private _enemies = _allValidUnits select {
		side _x != _injuredSide
	};
	private _nearestEnemy = [_injured, _enemies] call fnc_findNearestUnit;
	private _nearestEnemyDist = if (isNull _nearestEnemy) then {
		1e10
	} else {
		_injured distance2D _nearestEnemy
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
fnc_bleedoutTimer = {
	params ["_injured"];
	private _startTime = time;

	waitUntil {
		sleep 1;
		!alive _injured                                    // Dead
		|| ([_injured] call fnc_isRevived)       // Revived
		|| (lifeState _injured != "INCAPACITATED")         // No longer incapacitated
		|| ((time - _startTime) >= BLEEDOUT_TIME)          // Timer expired
	};

	// exit if revived or dead
	if (!alive _injured || ([_injured] call fnc_isRevived)) exitWith {};

	// if still incapacitated after bleedout time, kill them
	if (lifeState _injured == "INCAPACITATED" && !([_injured] call fnc_isBeingRevived)) then {
		[_injured, false] call fnc_setReviveProcess;
		_injured setDamage 1; // Bleed out
	};
};

// ===============================
// FUNCTION: Calculate Timeout for Medic Movement
// ===============================
fnc_getDynamicTimeout = {
	params ["_medic", "_injured"];

	private _pathDist = _medic distance2D _injured;

	// 10 sec base + (distance / 3 m/s), capped at 90 sec
	time + ((10 max (_pathDist / 3)) min 90)
};

// ===============================
// FUNCTION: Reset Revive State
// ===============================
fnc_unlockReviveState = {
	params ["_medic", "_injured"];

	if (!isNull _medic) then {
		{
			_medic enableAI _x;
		} forEach ["MOVE", "PATH", "AUTOCOMBAT", "TARGET", "SUPPRESSION"];
		private _ldr = leader _medic;
		if (!isNull _ldr && alive _ldr) then {
			_medic doFollow _ldr;
		};
		[_medic, false] call fnc_setReviving;
		if (_medic == player) then {
			player setVariable ["injuredToRevive", objNull, true];
		};
	};

	if (!isNull _injured) then {
		[_injured, false] call fnc_setBeingRevived;
	};
};

// ===============================
// FUNCTION: Start Revive State
// ===============================
fnc_lockReviveState = {
	params ["_medic", "_injured"];
	// lock injured and medic
	if (!isNull _medic) then {
		[_medic, true] call fnc_setReviving;
		if (_medic == player) then {
			player setVariable ["injuredToRevive", _injured, true];
		};
	};

	if (!isNull _injured) then {
		[_injured, true] call fnc_setBeingRevived;
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
fnc_waitForMedicArrival = {
	params ["_medic", "_injured"];

	// Wait for medic to arrive within range or timeout
	private _timeout = [_medic, _injured] call fnc_getDynamicTimeout;
	waitUntil {
		sleep 1;
		(!alive _injured)
		|| ([_injured] call fnc_isRevived)
		|| (_medic distance2D _injured < REVIVE_RANGE)
		|| (!alive _medic)
		|| (lifeState _medic == "INCAPACITATED")
		|| (time > _timeout)
	};

	(_medic distance2D _injured) < REVIVE_RANGE
};

// ===============================
// FUNCTION: Check if projectile is heavy explosive
// ===============================
fnc_isHeavyExplosive = {
	params ["_projectile"];

	if (_projectile isEqualTo "") exitWith {
		false
	};

	private _projLower = toLower _projectile;

	private _explosiveKeywords = [
		"_he", "_shell", "_bomb", "_satchel", "_mine", "_rocket",
		"gbu", "mk82", "mo_", "rpg", "at_", "_missile", "_howitzer",
		"_mortar", "_demolition"
	];

	private _ignoreKeywords = [
		"chemlight", "helmet", "wheel", "cheese" // safety words
	];

	{
		if ((_projLower find _x) > -1) exitWith {
			false
		}; // Ignore takes priority
	} forEach _ignoreKeywords;

	{
		if ((_projLower find _x) > -1) exitWith {
			true
		};
	} forEach _explosiveKeywords;

	false
};

// ===============================
// FUNCTION: Headshot damage Handling
// ===============================
fnc_headshotDamageHandling = {
	params ["_unit", "_damage"];

	// Base chance to survive headshot
	private _baseSurviveChance = 0.3;
	// Minimum damage to always kill
	private _minDamageToAlwaysKill = 0.85;
	// Check if unit has a helmet
	private _headgearClass = toLower (headgear _unit);
	private _isHelmet = ((_headgearClass find "helmet" != -1) ||   // generic helmets
	(_headgearClass find "cup_h" == 0) ||     // CUP helmets
	(_headgearClass find "6b" != -1) ||       // Russian 6b helmets
	(_headgearClass find "rus" != -1) ||      // Russian related helmets
	(_headgearClass find "spetsnaz" != -1));    // Special forces helmets);

	// if no headgear, no protection
	private _helmetProtection = if (_isHelmet) then {
		0.2
	} else {
		0
	};
	private _adjustedSurviveChance = _baseSurviveChance + _helmetProtection;

	if (_damage >= _minDamageToAlwaysKill) then {
		1
	} else {
		private _roll = random 1;
		if (_roll < _adjustedSurviveChance) then {
			_damage
		} else {
			1
		};
	};
};

// ===============================
// FUNCTION: Handle Heal
// ===============================
fnc_handleHeal = {
	params ["_medic", "_injured"];

	_injured setUnconscious false;
	{
		_injured enableAI _x
	} forEach ["MOVE", "ANIM"];
	_injured setCaptive false;
	_injured setDamage 0; // FULL heal
	_injured setUnitPos "AUTO";
	_injured playMoveNow "AmovPknlMstpSrasWrflDnon";

	// if revived by an enemy, drop the weapon become a captive
	if (((side _medic) getFriend (side _injured)) < 0.6) then {
		[_injured, _medic] call fnc_surrender;
		[_injured] call fnc_dropAllWeapons;
	};

	[_injured, true] call fnc_setRevived;
};

// ===============================
// FUNCTION: drop All weapons
// ===============================
fnc_dropAllWeapons = {
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
fnc_surrender = {
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
fnc_reviveLoop = {
	params ["_injured"];
	private _loopTimeout = time + BLEEDOUT_TIME; // max 5 minutes to try reviving
	private _medic = objNull;

	while { (alive _injured) && !([_injured] call fnc_isRevived) && (time < _loopTimeout) } do {
		sleep 3;
		if (!alive _injured || ([_injured] call fnc_isRevived)) exitWith {
			if (!isNull _medic) then {
				[_medic, _injured] call fnc_unlockReviveState;
			};
		};
		// Skip if already being revived
		if ([_injured] call fnc_isBeingRevived) then {
			continue
		};

		// find best medic
		_medic = [_injured] call fnc_getBestMedic;
		if (isNull _medic || !alive _medic) then {
			continue
		};

		// lock injured and medic
		[_medic, _injured] call fnc_lockReviveState;

		_medic doMove (position _injured);

		 // Wait for medic arrival
		private _arrived = [_medic, _injured] call fnc_waitForMedicArrival;
		// If medic didn't arrive in time or died or incapacitated
		if (!_arrived) then {
			[_medic, _injured] call fnc_unlockReviveState;
			continue;
		};
		if (([_medic] call fnc_isUnitGood) && alive _injured) then {
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
				|| (lifeState _medic == "INCAPACITATED")
				|| (time > _animTime)
			};
			if (!([_medic] call fnc_isUnitGood)) then {
				[_medic, _injured] call fnc_unlockReviveState;
				continue;
			};

			// SUCCESS: Revive and heal
			[_medic, _injured] call fnc_handleHeal;
		};
		// Always reset states after attempt
		[_medic, _injured] call fnc_unlockReviveState;
	};
	[_medic, _injured] call fnc_unlockReviveState;
};

// =======================================================
// START: Getter/Setters for Revive States
// =======================================================
fnc_isInReviveProcess = {
	params ["_unit"];
	_unit getVariable ["isInReviveProcess", false]
};

fnc_setReviveProcess = {
	params ["_unit", "_state"];
	_unit setVariable ["isInReviveProcess", _state, true];
};

fnc_isBeingRevived = {
	params ["_unit"];
	_unit getVariable ["beingRevived", false]
};

fnc_setBeingRevived = {
	params ["_unit", "_state"];
	_unit setVariable ["beingRevived", _state, true];
};

fnc_isRevived = {
	params ["_unit"];
	_unit getVariable ["revived", false]
};

fnc_setRevived = {
	params ["_unit", "_state"];
	_unit setVariable ["revived", _state, true];
};

fnc_isReviving = {
	params ["_unit"];
	_unit getVariable ["reviving", false]
};

fnc_setReviving = {
	params ["_unit", "_state"];
	_unit setVariable ["reviving", _state, true];
};
// =======================================================
// END: Getter/Setters for Revive States
// =======================================================

// ===============================
// FUNCTION: Handle damage
// ===============================
fnc_handleDamage = {
	params ["_unit", "_selection", "_damage", "_source", "_projectile"];
	private _currentDamage = damage _unit;
	private _newDamage = _currentDamage + _damage;

	// Allow lethal finishers if already down
	if (lifeState _unit == "INCAPACITATED") exitWith {
		_damage
	};

	// Compute probability of chance to survive if hit in the head
	if (_selection == "head") exitWith {
		[_unit, _damage] call fnc_headshotDamageHandling
	};

	private _isHeavyExplosive = [_projectile] call fnc_isHeavyExplosive;

	if (_isHeavyExplosive) then {
		private _dist = _unit distance2D _source;

		if (_dist <= 3) exitWith {
			1
		}; // lethal
		if (_dist <= 6) exitWith {
			0.95 max _damage
		}; // near-lethal
	};

	// Incapacitate on near-lethal total damage
	if (_newDamage >= 0.95) then {
		// if the injured is in a vehicle or static weapon, remove them
		private _vehicle = objectParent _unit;
		if (!(isNull _vehicle) && isTouchingGround (_vehicle)) then {
			moveOut _unit;
		};
		// Make unit unconscious
		_unit setUnconscious true;
		{
			_unit disableAI _x
		} forEach ["MOVE", "ANIM"];
		_unit setCaptive true;
		// Reset revive state for NEW incapacitation
		[_unit, false] call fnc_setRevived;
		[_unit, false] call fnc_setBeingRevived;
		_unit playMoveNow "AinjPpneMstpSnonWrflDnon"; // Flat injured

		// Prevent multiple revive loops from stacking
		if (!([_unit] call fnc_isInReviveProcess)) then {
			[_unit, true] call fnc_setReviveProcess;

			// Bleeding out timer
			[_unit] spawn fnc_bleedoutTimer;

			// AI revive logic
			[_unit] spawn {
				params ["_injured"];
				[_injured] call fnc_reviveLoop;

				// Reset the process flag after loop ends
				[_injured, false] call fnc_setReviveProcess;
			};
		};

		0.9
	} else {
		_damage
	};
};

// ===============================
// apply EVENT HANDLERS to group
// ===============================
{
	_x addEventHandler ["HandleDamage", {
		_this call fnc_handleDamage
	}];
	_x addEventHandler ["Killed", {
		params ["_unit"];
		[_unit, false] call fnc_setReviveProcess;
		[_unit, false] call fnc_setBeingRevived;
		[_unit, false] call fnc_setReviving;
		[_unit, false] call fnc_setRevived;
	}];
} forEach units _group;

addMissionEventHandler ["Draw3D", {
	private _injured = player getVariable ["injuredToRevive", objNull];

	if (isNull _injured || !alive _injured) exitWith {};

	private _wpPos = getPos _injured;

	// Build label
	private _wpText = format ["Revive Injured (%1 m)", round (player distance _wpPos)];

	// Draw icon + text
	drawIcon3D [
		"\A3\ui_f\data\map\markers\military\arrow2_CA.paa",
		[0, 1, 1, 1],
		_wpPos, // position
		0.5, 0.5, // icon size
		180, // icon angle
		_wpText, // text
		2, // shadow
		0.035, // text size
		"PuristaBold", // font
		"center", // align
		true, // drawThrough
		0, // textShiftX
		-0.04 // textShiftY (lift text above icon)
	];
}];