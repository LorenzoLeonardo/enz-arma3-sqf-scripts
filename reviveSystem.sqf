/*
	    reviveSystem.sqf
	    Usage: [group this] execVM "reviveSystem.sqf";
*/

#define BLEEDOUT_TIME 300 // 5 minutes
#define REVIVE_RANGE 3 // 3 meters
#define CACHE_LIFETIME 10 // seconds

params ["_group"];

// ===============================
// FUNCTION: get Best Medic
// ===============================
fnc_getBestMedic = {
	params ["_injured"];
	private _groupUnits = units group _injured;

	// step 1: Check same group first for medics
	private _candidates = _groupUnits select {
		(_x != _injured) &&
		alive _x &&
		!(_x getVariable ["reviving", false])
		&& (_x getUnitTrait "Medic") &&
		(lifeState _x != "INCAPACITATED") &&
		(isNull objectParent _x)
	};

	// step 2: Fallback to any same group unit
	if (_candidates isEqualTo []) then {
		_candidates = _groupUnits select {
			(_x != _injured) &&
			alive _x &&
			!(_x getVariable ["reviving", false]) &&
			(lifeState _x != "INCAPACITATED") &&
			(isNull objectParent _x)
		};
	};

	// step 3: if still empty, use other side units
	if (_candidates isEqualTo []) then {
		_candidates = allUnits select {
			(_x != _injured) &&
			alive _x &&
			!(_x getVariable ["reviving", false]) &&
			(lifeState _x != "INCAPACITATED") &&
			(side _x == side(group _injured)) &&
			(isNull objectParent _x)
		};
	};

	// step 4: if still empty, use all units
	if (_candidates isEqualTo []) then {
		_candidates = allUnits select {
			(_x != _injured) &&
			alive _x &&
			!(_x getVariable ["reviving", false]) &&
			(lifeState _x != "INCAPACITATED") &&
			(isNull objectParent _x)
		};
	};

	if (_candidates isEqualTo []) exitWith {
		objNull
	};

	// sort by distance
	_candidates = [_candidates, [], {
		_x distance _injured
	}, "ASCEND"] call BIS_fnc_sortBy;
	_candidates select 0
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
		_injured setVariable ["isInReviveProcess", false, true];
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
	params ["_medic", "_injured", "_timeout"];

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
			continue
		};

		// find best medic
		_medic = [_injured] call fnc_getBestMedic;
		if (isNull _medic || !alive _medic) then {
			continue
		};

		// lock injured and medic
		_injured setVariable ["beingRevived", true, true];
		_medic setVariable ["reviving", true, true];

		// Disable combat distractions
		{
			_medic disableAI _x
		} forEach ["AUTOCOMBAT", "TARGET", "SUPPRESSION"];

		_medic doMove (position _injured);

		private _timeout = [_medic, _injured] call fnc_getDynamicTimeout;
		 // Wait for medic arrival
		private _arrived = [_medic, _injured, _timeout] call fnc_waitForMedicArrival;
		// If medic didn't arrive in time or died or incapacitated
		if (!_arrived) then {
			[_medic, _injured] call fnc_resetReviveState;
			continue;
		};
		if (alive _medic && alive _injured && (lifeState _medic != "INCAPACITATED")) then {
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
			if (!alive _medic || lifeState _medic == "INCAPACITATED") then {
				[_medic, _injured] call fnc_resetReviveState;
				continue;
			};

			// SUCCESS: Revive and heal
			_injured setUnconscious false;
			{
				_injured enableAI _x
			} forEach ["MOVE", "ANIM"];
			_injured setCaptive false;
			_injured setDamage 0; // FULL heal
			_injured setUnitPos "AUTO";
			_injured playMoveNow "AmovPknlMstpSrasWrflDnon";

			_injured setVariable ["revived", true, true];
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

// ===============================
// FUNCTION: Handle damage
// ===============================
fnc_handleDamage = {
	params ["_unit", "_selection", "_damage", "_source", "_projectile"];
	private _newDamage = (_damage + damage _unit);

	// if already unconscious, allow lethal hits to finish them
	if (lifeState _unit == "INCAPACITATED") exitWith {
		if ((_selection == "head" && _damage > 0.5) || _damage > 2) then {
			_unit setDamage 1;
		};
		0
	};

	// Overkill or lethal headshot before incapacitation
	if (_damage > 2) exitWith {
		_unit setDamage 1;
		0
	};

	// if the head is hit and damage is lethal, kill instantly
	if (_selection == "head" && _damage > 0.5) exitWith {
		_unit setDamage 1;  // Immediate death
		0                   // Prevent further damage handling
	};

	if (_newDamage >= 1) then {
		// if the injured is in a vehicle or static weapon, remove them
		if (!isNull objectParent _unit) then {
			moveOut _unit;
		};
		// Make unit unconscious
		_unit setDamage 0.9;
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
		if (!(_unit getVariable ["isInReviveProcess", false])) then {
			_unit setVariable ["isInReviveProcess", true, true];

			// Bleeding out timer
			[_unit] spawn fnc_bleedoutTimer;

			// AI revive logic
			[_unit] spawn {
				params ["_injured"];
				[_injured] call fnc_reviveLoop;

				// Reset the process flag after loop ends
				_injured setVariable ["isInReviveProcess", false, true];
			};
		};

		0
	} else {
		_damage
	};
};

// ===============================
// FUNCTION: Handle Heal
// ===============================
fnc_handleHeal = {
	params ["_healer", "_patient", "_amount"];

	_patient setDamage 0;
	_patient setUnconscious false;
	{
		_patient enableAI _x
	} forEach ["MOVE", "ANIM"];
	_patient setCaptive false;
	_patient setVariable ["revived", true, true];
	_patient setUnitPos "AUTO";
	_patient playMoveNow "AmovPknlMstpSrasWrflDnon";
};

// ===============================
// apply EVENT HANDLERS to group
// ===============================
{
	_x addEventHandler ["HandleDamage", {
		_this call fnc_handleDamage
	}];
	_x addEventHandler ["HandleHeal", {
		_this call fnc_handleHeal
	}];
	_x addEventHandler ["Killed", {
		params ["_unit"];
		_unit setVariable ["isInReviveProcess", false];
		_unit setVariable ["beingRevived", false];
		_unit setVariable ["reviving", false];
	}]
} forEach units _group;