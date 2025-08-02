/*
	    reviveSystem.sqf
	    Usage: [group this] execVM "reviveSystem.sqf";
*/

params ["_group"];

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

				while { (alive _injured) && !(_injured getVariable ["revived", false]) && ((lifeState _injured) == "INCAPACITATED") && (_elapsed < _bleedOutTime) } do {
					sleep 1;
					_elapsed = _elapsed + 1;
				};

				if ((alive _injured) && !(_injured getVariable ["revived", false]) && ((lifeState _injured) == "INCAPACITATED")) then {
					_injured setDamage 1; // Bleed out
				};
			};

			// AI revive logic
			[_unit] spawn {
				params ["_injured"];

				while { (alive _injured) && !(_injured getVariable ["revived", false]) } do {
					sleep 3;
					private _medic = objNull;

					{
						if ((_x != _injured) && (alive _x) && !(_x getVariable ["reviving", false])) exitWith {
							_medic = _x;
						};
					} forEach units group _injured;

					if (!isNull _medic) then {
						doStop _medic;
						_medic disableAI "AUTOCOMBAT";
						_medic disableAI "TARGET";
						_medic disableAI "SUPPRESSION";

						_medic setVariable ["reviving", true];
						_medic doMove (position _injured);

						private _timeout = time + 120; // 120 sec to reach
						waitUntil {
							sleep 1;
							((_medic distance _injured) < 3) || (!alive _medic) || (time > _timeout)
						};

						_medic enableAI "AUTOCOMBAT";
						_medic enableAI "TARGET";
						_medic enableAI "SUPPRESSION";
						if (alive _medic && alive _injured && (_medic distance _injured) < 3) then {
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