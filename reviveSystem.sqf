/*
	    reviveSystem.sqf
	    Usage: [group this] execVM "reviveSystem.sqf";
*/

params ["_group"];

// Function to find the best medic candidate, fallback to other groups if needed
fnc_getBestMedic = {
	params ["_injured"];
	private _groupUnits = units group _injured;

	// step 1: Check same group first (prioritize real medics)
	private _candidates = _groupUnits select {
		(_x != _injured)
		&& (alive _x)
		&& !(_x getVariable ["reviving", false])
		&& (_x getUnitTrait "Medic")
	};

	// if no medics in the same group, allow any soldier in the same group
	if (count _candidates == 0) then {
		_candidates = _groupUnits select {
			(_x != _injured)
			&& (alive _x)
			&& !(_x getVariable ["reviving", false])
		};
	};

	// step 2: if no one in the same group, search ALL units of the same side
	if (count _candidates == 0) then {
		private _allUnits = allUnits select {
			side _x == side _injured
		};
		_candidates = _allUnits select {
			(_x != _injured)
			&& (alive _x)
			&& !(_x getVariable ["reviving", false])
			&& (_x getUnitTrait "Medic")
		};

		// if still no medic, fallback to any alive unit from the same side
		if (count _candidates == 0) then {
			_candidates = _allUnits select {
				(_x != _injured)
				&& (alive _x)
				&& !(_x getVariable ["reviving", false])
			};
		};
	};

	// if none at all, return objNull
	if (count _candidates == 0) exitWith {
		objNull
	};

	// sort by distance from injured (closest first)
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
			1                   // Prevent further damage handling
		};

		if (_newDamage >= 1) then {
			// Make unit unconscious
			_unit setDamage 0.9;
			_unit setUnconscious true;
			_unit disableAI "MOVE";
			_unit disableAI "ANIM";
			_unit setCaptive true;
			_unit setVariable ["revived", false, true];
			_unit playMoveNow "AinjPpneMstpSnonWrflDnon"; // Flat injured

			// Bleeding out timer
			[_unit] spawn {
				params ["_injured"];
				private _elapsed = 0;
				private _bleedOutTime = 120;
				private _startTime = time;
				waitUntil {
					sleep 1;
					!alive _injured                                    // Dead
					|| (_injured getVariable ["revived", false])       // Revived
					|| (lifeState _injured != "INCAPACITATED")         // No longer incapacitated
					|| ((time - _startTime) >= _bleedOutTime)          // Timer expired
				};
				if ((alive _injured) && !(_injured getVariable ["revived", false]) && ((lifeState _injured) == "INCAPACITATED")) then {
					_injured setDamage 1; // Bleed out
				};
			};

			// AI revive logic
			[_unit] spawn {
				params ["_injured"];
				private _loopTimeout = time + 180; // max 3 minutes to try reviving

				while { (alive _injured) && !(_injured getVariable ["revived", false]) && (time < _loopTimeout) } do {
					sleep 3;
					private _medic = [_injured] call fnc_getBestMedic;

					if (!isNull _medic) then {
						doStop _medic;

						// Disable combat distractions during revive
						_medic disableAI "AUTOCOMBAT";
						_medic disableAI "TARGET";
						_medic disableAI "SUPPRESSION";

						// Optional: Set safe behavior while reviving
						_medic setBehaviour "AWARE";
						_medic setUnitPos "MIDDLE";

						_medic setVariable ["reviving", true];
						_medic commandMove (position _injured);

						private _timeout = time + 120; // 120 sec to reach
						waitUntil {
							sleep 1;
							((_medic distance _injured) < 3) || (!alive _medic) || (time > _timeout)
						};

						// Re-enable AI capabilities after move attempt
						_medic enableAI "AUTOCOMBAT";
						_medic enableAI "TARGET";
						_medic enableAI "SUPPRESSION";
						_medic setBehaviour "AWARE";
						_medic setUnitPos "AUTO";

						if (alive _medic && alive _injured && (_medic distance _injured) < 3) then {
							// Ensure medic stops moving before animation
							waitUntil {
								sleep 0.5;
								speed _medic < 0.5
							};

							// try playing animation reliably
							_medic playMoveNow "AinvPknlMstpSnonWnonDnon_medic1";
							// Ensure animation starts (check current anim)
							private _animStartTime = time;
							waitUntil {
								sleep 0.1;
								(animationState _medic == "AinvPknlMstpSnonWnonDnon_medic1")
								|| (time - _animStartTime > 2)
							};
							// Give extra time for anim to complete
							sleep 5;

							// Revive and FULL heal
							_injured setUnconscious false;
							_injured enableAI "MOVE";
							_injured enableAI "ANIM";
							_injured setCaptive false;
							_injured setDamage 0; // FULL heal
							_injured setVariable ["revived", true, true];
							_injured setUnitPos "AUTO"; // Reset stance
							_injured playMoveNow "AmovPknlMstpSrasWrflDnon"; // Kneel briefly
						};

						_medic setVariable ["reviving", false];
					};
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