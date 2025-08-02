/*
	    reviveSystem.sqf
	    Usage: [group this] execVM "reviveSystem.sqf";
*/

params ["_group"];

{
	_x addEventHandler ["HandleDamage", {
		params ["_unit", "_selection", "_damage", "_source", "_projectile"];

		private _newDamage = (_damage + damage _unit);
		private _deathChance = 0.1;      // 10% chance unit dies instantly

		if (_newDamage >= 1) then {
			// Roll for instant death
			if (random 1 < _deathChance) exitWith {
				_unit setDamage 1;   // Dead instantly
			};
			    // Make unit unconscious
			_unit setDamage 0.9;
			_unit setUnconscious true;
			_unit disableAI "MOVE";
			_unit disableAI "ANIM";
			_unit playMoveNow "AinjPpneMstpSnonWrflDnon"; // Flat injured
			_unit setCaptive true;

			// Revive logic
			[_unit] spawn {
				private _injured = _this select 0;
				private _chance = 1;

				while { alive _injured && (_injured getVariable ["revived", false]) isEqualTo false } do {
					sleep 3;
					// find a nearby friendly (not unconscious)
					private _medic = objNull;
					{
						if (_x != _injured && alive _x && !(_x getVariable ["reviving", false])) exitWith {
							_medic = _x;
						};
					} forEach allUnits;
					if (!isNull _medic) then {
						_medic setVariable ["reviving", true];
						// move to injured
						_medic doMove (position _injured);
						waitUntil {
							sleep 1;
							(_medic distance _injured) < 3 || !alive _medic
						};
						if (alive _medic && alive _injured) then {
							// Roll revive chance
							if (random 1 < _chance) then {
								_injured setUnconscious false;
								_injured enableAI "MOVE";
								_injured enableAI "ANIM";
								_injured setCaptive false;
								_injured setDamage 0.5;
								_injured setVariable ["revived", true, true];
								_injured playMoveNow "AmovPknlMstpSrasWrflDnon"; // Kneeling with rifle
							};
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
} forEach units _group;