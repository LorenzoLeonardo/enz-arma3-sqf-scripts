/*
	    reviveSystem.sqf
	    Usage: [group this] execVM "reviveSystem.sqf";
*/

params ["_group"];

// Add unconscious handling for all units in the group
{
	_x addEventHandler ["HandleDamage", {
		params ["_unit", "_selection", "_damage", "_source", "_projectile"];

		if ((_damage + damage _unit) >= 1) then {
			// Prevent death
			_unit setDamage 0.9;
			_unit setVariable ["isUnconscious", true, true];

			// Disable all AI behavior
			_unit disableAI "MOVE";
			_unit disableAI "ANIM";
			_unit disableAI "TARGET";
			_unit disableAI "AUTOTARGET";
			_unit setCaptive true;

			// Force injured prone animation (looping)
			[_unit] spawn {
				params ["_injuredUnit"];
				while { _injuredUnit getVariable ["isUnconscious", false] && alive _injuredUnit } do {
					_injuredUnit playMoveNow "AinjPpneMstpSnonWnonDnon"; // Injured prone
					sleep 5; // refresh to keep animation
				};
			};

			// Prevent further damage
			0.9
		} else {
			_damage
		}
	}];
} forEach units _group;

// Main revive loop
while { true } do {
	{
		if (_x getVariable ["isUnconscious", false]) then {
			private _reviver = objNull;
			private _dist = 9999;

			// find nearest alive teammate
			{
				if (alive _x && {
					!(_x getVariable ["isUnconscious", false])
				}) then {
					private _d = _x distance _x;
					if (_d < _dist) then {
						_dist = _d;
						_reviver = _x;
					};
				};
			} forEach units _group;

			if (!isNull _reviver) then {
				_reviver doMove (getPosATL _x);

				waitUntil {
					sleep 1;
					(_reviver distance _x) < 3 || !alive _reviver
				};

				if (alive _reviver) then {
					_reviver playMove "AinvPknlMstpSnonWnonDnon_medic";
					sleep 6;

					// Revive
					_x setDamage 0.3;
					_x setVariable ["isUnconscious", false, true];
					_x enableAI "MOVE";
					_x enableAI "ANIM";
					_x enableAI "TARGET";
					_x enableAI "AUTOTARGET";
					_x setCaptive false;
					                    _x playMoveNow "AmovPpneMstpSnonWnonDnon"; // prone idle
				};
			};
		};
	} forEach units _group;

	sleep 1;
};