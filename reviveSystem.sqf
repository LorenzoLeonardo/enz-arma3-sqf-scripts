/*
	    reviveSystem.sqf
	    Usage: [group this] execVM "reviveSystem.sqf";
*/
#define BLEEDOUT_TIME 300 // 5 minutes
#define REVIVE_RANGE 3 // 3 meters

params ["_group"];

if (isNil "GVAR_medicCache") then {
	GVAR_medicCache = createHashMap;
};

// Function to refresh medic cache every X seconds
fnc_refreshMedicCache = {
	private _cacheLifetime = 10; // seconds
	private _now = time;

	{
		private _side = _x;
		private _cacheData = GVAR_medicCache getOrDefault [_side, [[], 0]]; // [units, lastUpdate]
		private _lastUpdate = _cacheData select 1;

		if ((_now - _lastUpdate) > _cacheLifetime) then {
			private _sideUnits = allUnits select {
				side _x == _side && alive _x
			};
			GVAR_medicCache set [_side, [_sideUnits, _now]];
		};
	} forEach [west, east, independent, civilian];
};

// Function to find the best medic candidate, fallback to other groups if needed
fnc_getBestMedic = {
	params ["_injured"];
	private _groupUnits = units group _injured;

	// step 1: Check same group first for medics
	private _candidates = _groupUnits select {
		(_x != _injured) && alive _x && !(_x getVariable ["reviving", false]) && (_x getUnitTrait "Medic") && (lifeState _x != "INCAPACITATED")
	};

	// step 2: Fallback to any same group unit
	if (_candidates isEqualTo []) then {
		_candidates = _groupUnits select {
			(_x != _injured) && alive _x && !(_x getVariable ["reviving", false]) && (lifeState _x != "INCAPACITATED")
		};
	};

	// step 3: if still empty, use cached side units
	if (_candidates isEqualTo []) then {
		call fnc_refreshMedicCache;

		private _sideCache = GVAR_medicCache get (side _injured);
		private _sideUnits = if (!isNil "_sideCache") then {
			_sideCache select 0
		} else {
			[]
		};

		// Prioritize medics in side cache
		_candidates = _sideUnits select {
			(_x != _injured) && alive _x && !(_x getVariable ["reviving", false]) && (_x getUnitTrait "Medic") && (lifeState _x != "INCAPACITATED")
		};

		// Fallback to any alive unit from same side
		if (_candidates isEqualTo []) then {
			_candidates = _sideUnits select {
				(_x != _injured) && alive _x && !(_x getVariable ["reviving", false]) && (lifeState _x != "INCAPACITATED")
			};
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

{
	// Handle damage (unconscious system)
	_x addEventHandler ["HandleDamage", {
		params ["_unit", "_selection", "_damage", "_source", "_projectile"];
		private _newDamage = (_damage + damage _unit);

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
			_unit disableAI "MOVE";
			_unit disableAI "ANIM";
			_unit setCaptive true;
			// Reset revive state for NEW incapacitation
			_unit setVariable ["revived", false, true];
			_unit setVariable ["beingRevived", false, true];
			_unit playMoveNow "AinjPpneMstpSnonWrflDnon"; // Flat injured

			// Bleeding out timer
			[_unit] spawn {
				params ["_injured"];
				private _elapsed = 0;
				private _startTime = time;
				waitUntil {
					sleep 1;
					!alive _injured                                    // Dead
					|| (_injured getVariable ["revived", false])       // Revived
					|| (lifeState _injured != "INCAPACITATED")         // No longer incapacitated
					|| ((time - _startTime) >= BLEEDOUT_TIME)          // Timer expired
				};
				if ((alive _injured) && !(_injured getVariable ["revived", false]) && ((lifeState _injured) == "INCAPACITATED")) then {
					_injured setDamage 1; // Bleed out
				};
			};

			// AI revive logic
			[_unit] spawn {
				params ["_injured"];
				private _loopTimeout = time + BLEEDOUT_TIME; // max 5 minutes to try reviving
				private _medic = objNull;
				private _attempts = 0;
				private _MAX_ATTEMPTS = 3;
				while { (alive _injured) && !( _injured getVariable ["revived", false]) && (time < _loopTimeout) && (_attempts < _MAX_ATTEMPTS) } do {
					sleep 3;

					// Skip if already being revived
					if (_injured getVariable ["beingRevived", false]) then {
						continue
					};

					// find best medic
					_medic = [_injured] call fnc_getBestMedic;
					if (isNull _medic) then {
						continue
					};

					_attempts = _attempts + 1;

					if (!isNull _medic) then {
						// lock injured and medic
						_injured setVariable ["beingRevived", true, true];
						_medic setVariable ["reviving", true, true];

						// Disable combat distractions
						_medic disableAI "AUTOCOMBAT";
						_medic disableAI "TARGET";
						_medic disableAI "SUPPRESSION";

						_medic commandMove (position _injured);

						private _timeout = time + 30; // 30 sec to reach injured
						waitUntil {
							sleep 1;
							((_medic distance _injured) < REVIVE_RANGE)
							|| (!alive _medic)
							|| (lifeState _medic == "INCAPACITATED")
							|| (time > _timeout)
						};

						if (alive _medic && alive _injured && ((_medic distance _injured) < REVIVE_RANGE) && (lifeState _medic != "INCAPACITATED")) then {
							// stop and animate revive
							doStop _medic;
							_medic disableAI "MOVE";
							_medic disableAI "PATH";

							_medic playMoveNow "AinvPknlMstpSnonWnonDnon_medic1";

							// Wait until anim starts or timeout
							private _animStartTime = time;
							waitUntil {
								sleep 0.1;
								(animationState _medic == "AinvPknlMstpSnonWnonDnon_medic1")
								|| ((time - _animStartTime) > 2)
							};

							sleep 5; // Allow time for animation

							// SUCCESS: Revive and heal
							_injured setUnconscious false;
							_injured enableAI "MOVE";
							_injured enableAI "ANIM";
							_injured setCaptive false;
							_injured setDamage 0; // FULL heal
							_injured setUnitPos "AUTO";
							_injured playMoveNow "AmovPknlMstpSrasWrflDnon";

							_injured setVariable ["revived", true, true];
						};

						// Restore medic state
						_medic enableAI "MOVE";
						_medic enableAI "PATH";
						_medic enableAI "AUTOCOMBAT";
						_medic enableAI "TARGET";
						_medic enableAI "SUPPRESSION";
						_medic doFollow (leader _medic);

						// Unlock medic
						_medic setVariable ["reviving", false, true];

						// Unlock injured ONLY if not revived
						if (!(_injured getVariable ["revived", false])) then {
							_injured setVariable ["beingRevived", false, true];
						};
					};
				};

				// if time runs out and still not revived, unlock
				if (!(_injured getVariable ["revived", false])) then {
					_injured setVariable ["beingRevived", false, true];
				};
			};
			0
		} else {
			_damage
		};
	}];

	// HandleHeal: player or AI healing action
	_x addEventHandler ["HandleHeal", {
		params ["_healer", "_patient", "_amount"];

		_patient setDamage 0;
		_patient setUnconscious false;
		_patient enableAI "MOVE";
		_patient enableAI "ANIM";
		_patient setCaptive false;
		_patient setVariable ["revived", true, true];
		_patient setUnitPos "AUTO";
		_patient playMoveNow "AmovPknlMstpSrasWrflDnon";

		diag_log format ["%1 healed %2 completely and revived them.", name _healer, name _patient];
	}];
} forEach units _group;