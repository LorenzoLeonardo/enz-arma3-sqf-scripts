/*
	    reviveSystem.sqf
	    Usage: [group this] execVM "reviveSystem.sqf";
*/

#define BLEEDOUT_TIME 300 // 5 minutes
#define REVIVE_RANGE 3 // 3 meters

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
// FUNCTION: get Best Medic
// ===============================
fnc_getBestMedic = {
	params ["_injured"];
	private _groupUnits = units group _injured;

	// step 1: Check same group first for medics
	private _candidates = _groupUnits select {
		(_x != _injured) &&
		([_x] call fnc_isUnitGood) &&
		!(_x getVariable ["reviving", false]) &&
		(_x getUnitTrait "Medic") &&
		(isNull objectParent _x) &&
		!(captive _x)
	};

	// step 2: Fallback to any same group unit
	if (_candidates isEqualTo []) then {
		_candidates = _groupUnits select {
			(_x != _injured) &&
			([_x] call fnc_isUnitGood) &&
			!(_x getVariable ["reviving", false]) &&
			(isNull objectParent _x) &&
			!(captive _x)
		};
	};

	// step 3: if still empty, use other side units
	if (_candidates isEqualTo []) then {
		_candidates = allUnits select {
			(_x != _injured) &&
			([_x] call fnc_isUnitGood) &&
			!(_x getVariable ["reviving", false]) &&
			(side _x == side(group _injured)) &&
			(isNull objectParent _x) &&
			!(captive _x)
		};
	};

	// step 4: if still empty, use all units
	if (_candidates isEqualTo []) then {
		_candidates = allUnits select {
			(_x != _injured) &&
			([_x] call fnc_isUnitGood) &&
			!(_x getVariable ["reviving", false]) &&
			(isNull objectParent _x) &&
			!(captive _x)
		};
	};

	if (_candidates isEqualTo []) exitWith {
		objNull
	};

	// sort by distance
	_candidates = [_candidates, [], {
		_x distance _injured
	}, "ASCEND"] call BIS_fnc_sortBy;
	private _medic = _candidates select 0;
	if (!isNull _medic) then {
		_medic globalChat format ["%1 will revive %2", name _medic, name _injured];
	};
	_medic
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
		|| (_injured getVariable ["revived", false])       // Revived
		|| (lifeState _injured != "INCAPACITATED")         // No longer incapacitated
		|| ((time - _startTime) >= BLEEDOUT_TIME)          // Timer expired
	};

	// exit if revived or dead
	if (!alive _injured || (_injured getVariable ["revived", false])) exitWith {};

	// if still incapacitated after bleedout time, kill them
	if (lifeState _injured == "INCAPACITATED" && !(_injured getVariable ["beingRevived", false])) then {
		[_injured, false] call fnc_setReviveProcess;
		_injured setDamage 1; // Bleed out
	};
};

// ===============================
// FUNCTION: Calculate Timeout for Medic Movement
// ===============================
fnc_getDynamicTimeout = {
	params ["_medic", "_injured"];

	private _pathDist = _medic distance _injured;

	// 10 sec base + (distance / 3 m/s), capped at 90 sec
	time + ((10 max (_pathDist / 3)) min 90)
};

// ===============================
// FUNCTION: Reset Revive State
// ===============================
fnc_resetReviveState = {
	params ["_medic", "_injured"];

	if (!isNull _medic) then {
		{
			_medic enableAI _x;
		} forEach ["MOVE", "PATH", "AUTOCOMBAT", "TARGET", "SUPPRESSION"];
		private _ldr = leader _medic;
		if (!isNull _ldr && alive _ldr) then {
			_medic doFollow _ldr;
		};
		_medic setVariable ["reviving", false, true];
	};

	if (!isNull _injured && !(_injured getVariable ["revived", false])) then {
		_injured setVariable ["beingRevived", false, true];
	};
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
		|| (_injured getVariable ["revived", false])
		|| (_medic distance _injured < REVIVE_RANGE)
		|| (!alive _medic)
		|| (lifeState _medic == "INCAPACITATED")
		|| (time > _timeout)
	};

	(_medic distance _injured) < REVIVE_RANGE
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
		_medic globalChat format ["%1 has become captive", name _injured];
		[_injured, _medic] call fnc_surrender;
		[_injured] call fnc_dropAllWeapons;
	};

	_injured setVariable ["revived", true, true];
	if (!isNull _medic) then {
		_medic globalChat format ["%1 has successfully revive %2", name _medic, name _injured];
	};
};

// ===============================
// FUNCTION: drop All weapons
// ===============================
fnc_dropAllWeapons = {
	params ["_unit"];
	private _pos = getPosATL _unit;
	private _holder = createVehicle ["GroundWeaponHolder", _pos, [], 0, "CAN_COLLIDE"];

	// move all weapons to the ground
	{
		_unit removeWeapon _x;
		_holder addWeaponCargoGlobal [_x, 1];
	} forEach weapons _unit;

	// move all magazines for those weapons
	{
		_unit removeMagazine _x;
		_holder addMagazineCargoGlobal [_x, 1];
	} forEach magazines _unit;

	removeBackpack _unit; // remove backpack too
	removeAllItems _unit;
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

	while { (alive _injured) && !( _injured getVariable ["revived", false]) && (time < _loopTimeout) } do {
		sleep 3;
		if (!alive _injured || (_injured getVariable ["revived", false])) exitWith {
			if (!isNull _medic) then {
				[_medic, _injured] call fnc_resetReviveState;
			};
		};
		// Skip if already being revived
		if (_injured getVariable ["beingRevived", false]) then {
			if (!isNull _medic) then {
				_medic globalChat format ["%1 is being revived.", name _injured];
			};
			continue
		};

		// find best medic
		_medic = [_injured] call fnc_getBestMedic;
		if (isNull _medic || !alive _medic) then {
			if (!isNull _medic) then {
				_medic globalChat format ["%1, a chosen medic to revive %2 has died.", name _medic, name _injured];
			};
			continue
		};

		// lock injured and medic
		_injured setVariable ["beingRevived", true, true];
		_medic setVariable ["reviving", true, true];

		doStop _medic;
		_medic stop false;
		// Make sure no custom animation is locking movement
		_medic switchMove "";
		// Disable combat distractions
		{
			_medic disableAI _x
		} forEach ["AUTOCOMBAT", "TARGET", "SUPPRESSION"];
		// Allow AI to choose stance for movement
		_medic setUnitPos "AUTO";
		_medic doMove (position _injured);

		 // Wait for medic arrival
		private _arrived = [_medic, _injured] call fnc_waitForMedicArrival;
		// If medic didn't arrive in time or died or incapacitated
		if (!_arrived) then {
			if (!isNull _medic) then {
				_medic globalChat format ["%1 has failed to come to revive %2.", name _medic, name _injured];
			};
			[_medic, _injured] call fnc_resetReviveState;
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
				_medic globalChat format ["%1 was incapacitated or died while reviving %2.", name _medic, name _injured];
				[_medic, _injured] call fnc_resetReviveState;
				continue;
			};

			// SUCCESS: Revive and heal
			[_medic, _injured] call fnc_handleHeal;
		};
		// Always reset states after attempt
		[_medic, _injured] call fnc_resetReviveState;
	};
	// if time runs out and still not revived, unlock
	if (!(_injured getVariable ["revived", false])) then {
		_injured setVariable ["beingRevived", false, true];
	};

	// Reset medic in case loop ended unexpectedly
	if (!isNull _medic) then {
		[_medic, _injured] call fnc_resetReviveState;
	};
};

fnc_isInReviveProcess = {
	params ["_unit"];
	_unit getVariable ["isInReviveProcess", false]
};

fnc_setReviveProcess = {
	params ["_unit", "_state"];
	_unit setVariable ["isInReviveProcess", _state, true];
};

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
		private _dist = _unit distance _source;

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
		if (!isNull objectParent _unit) then {
			moveOut _unit;
		};
		// Make unit unconscious
		_unit setUnconscious true;
		{
			_unit disableAI _x
		} forEach ["MOVE", "ANIM"];
		_unit setCaptive true;
		// Reset revive state for NEW incapacitation
		_unit setVariable ["revived", false, true];
		_unit setVariable ["beingRevived", false, true];
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
		_unit setVariable ["beingRevived", false];
		_unit setVariable ["reviving", false];
		_unit setVariable ["revived", false];
	}];
} forEach units _group;