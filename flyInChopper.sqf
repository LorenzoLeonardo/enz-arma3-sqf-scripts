/*
	    flyInChopper.sqf
	    Usage: [this] execVM "flyInChopper.sqf";
*/

params ["_chopper"];

private _heliPilot = driver _chopper;
private _aiPilotGroup = group _heliPilot;
private _sideEnemy = east;
private _basePos = getMarkerPos "airbase";
private _rtbAltitude = 80;

[_chopper, _heliPilot, _aiPilotGroup, _sideEnemy, _basePos, _rtbAltitude] spawn {
	params ["_chopper", "_heliPilot", "_aiPilotGroup", "_sideEnemy", "_basePos", "_rtbAltitude"];
	// Calculate 75% of current enemy count
	private _threshHoldCount = floor ((count (allUnits select {
		side _x == _sideEnemy && alive _x
	})) * 0.75);

	// Remove all men in cargo from group, so that the pilot cannot command them later to disembark.
	{
		if (tolower((assignedVehicleRole _x) select 0) == "cargo") then {
			[_x] joinSilent grpNull;
		}
	} forEach (crew _chopper);

	// Wait until enemy count is below half and chopper is alive
	waitUntil {
		((count (allUnits select {
			side _x == _sideEnemy && alive _x
		})) < _threshHoldCount) && alive _chopper
	};

	if (alive _chopper) then {
		hint "Tactical airstrike is coming your location.";
		// Send radio message to ground units
		_heliPilot sideRadio "RadioHeliTacticalStrike";

		// Force AI to engage
		_chopper engineOn true;
		_chopper flyInHeight _rtbAltitude;
		_aiPilotGroup setBehaviour "AWARE";
		_aiPilotGroup setCombatMode "RED";  // Engage enemies
		{
			_x enableAI "MOVE"
		} forEach units _aiPilotGroup;

		private _enemies = allUnits select {
			side _x == _sideEnemy && alive _x
		};
		// Calculate average enemy position
		private _enemyPos = [0, 0, 0];
		{
			_enemyPos = _enemyPos vectorAdd (getPosATL _x)
		} forEach _enemies;

		if ((count _enemies) > 0) then {
			_enemyPos = _enemyPos vectorMultiply (1 / (count _enemies));
			// Add TAKEOFF move waypoint first (forces liftoff)
			private _wp0 = _aiPilotGroup addWaypoint [getPos _chopper, 0];
			_wp0 setWaypointType "MOVE";

			// Add SAD waypoint to enemy position
			private _wp1 = _aiPilotGroup addWaypoint [_enemyPos, 0];
			_wp1 setWaypointType "SAD";

			// Backup: Force movement if AI stuck
			_heliPilot doMove _enemyPos;

			// Monitor and RTB when all enemies are dead
			while {
				(({
					side _x == _sideEnemy && alive _x
				} count allUnits) > 0) && (alive _chopper)
			} do {
				_chopper setVehicleAmmo 1;
				private _aliveEnemies = allUnits select {
					side _x == _sideEnemy && alive _x
				};
				private _target = _aliveEnemies param [0, objNull];

				if (!isNull _target) then {
					// Clear waypoints
					while { (count waypoints _aiPilotGroup) > 0 } do {
						deleteWaypoint [_aiPilotGroup, 0];
					};

					// Add new waypoint to target
					private _wp = _aiPilotGroup addWaypoint [getPos _target, 0];
					_wp setWaypointType "SAD"; // could also use "SAD"
					_wp setWaypointBehaviour "AWARE";
					_wp setWaypointCombatMode "RED";
					_wp setWaypointSpeed "FULL";

					waitUntil {
						!(alive _target) || (lifeState _target == "INCAPACITATED")
					};
				};
				sleep 1;
			};

			if (alive _chopper) then {
				// Clear waypoints
				while { (count waypoints _aiPilotGroup) > 0 } do {
					deleteWaypoint [_aiPilotGroup, 0];
				};
				// Return to base when all enemy unit are dead.
				private _rtbWP = _aiPilotGroup addWaypoint [_basePos, 0];
				_rtbWP setWaypointType "GETOUT";
			};
		};
	};
};

// Auto-replace dead pilot
{
	_x addEventHandler ["HandleDamage", {
		params ["_unit", "_selection", "_damage", "_source", "_projectile", "_hitIndex"];
		private _currentDamage = damage _unit;
		private _newDamage = _currentDamage + _damage;

		// if incoming damage will result in death
		if (((_newDamage >= 1) && {
			alive _unit
		}) || (lifeState _unit == "INCAPACITATED")) then {
			private _veh = vehicle _unit;
			private _roleInfo = assignedVehicleRole _unit;
			private _roleType = toLower (_roleInfo select 0);

			switch (_roleType) do {
				case "driver": {
					// Move to cargo if they're in the heli
					private _replacement = objNull;
					{
						if (_x != _unit && alive _x && {
							lifeState _x != "INCAPACITATED"
						}) exitWith {
							_replacement = _x;
						};
					} forEach (crew _veh);

					if (!isNull _replacement) then {
						private _replacementRole = assignedVehicleRole _replacement select 0;
						switch (toLower _replacementRole) do {
							case "turret": {
								private _seat = assignedVehicleRole _replacement select 1;
								unassignVehicle _unit;
								moveOut _unit;
								unassignVehicle _replacement;
								moveOut _replacement;
								_unit moveInTurret[_veh, _seat];
								_replacement moveInDriver _veh;
							};
							case "cargo": {
								unassignVehicle _unit;
								moveOut _unit;
								unassignVehicle _replacement;
								moveOut _replacement;
								// join the replacement from cargo to the group of the vehicle
								[_replacement] joinSilent (group _unit);
								_unit moveInCargo _veh;
								_replacement moveInDriver _veh;
							};
						};
					};
				};
				case "turret": {
					private _replacement = objNull;
					{
						if (_x != _unit && alive _x &&
						(lifeState _x != "INCAPACITATED") &&
						(tolower((assignedVehicleRole _x) select 0) == "cargo")) exitWith {
							_replacement = _x;
						};
					} forEach (crew _veh);

					if (!isNull _replacement) then {
						private _replacementRole = assignedVehicleRole _replacement select 0;
						switch (toLower _replacementRole) do {
							case "cargo": {
								private _seat = assignedVehicleRole _unit select 1;
								unassignVehicle _unit;
								moveOut _unit;
								unassignVehicle _replacement;
								moveOut _replacement;
								// join the replacement from cargo to the group of the vehicle
								[_replacement] joinSilent (group _unit);
								_unit moveInCargo _veh;
								_replacement moveInTurret[_veh, _seat];
							};
						};
					};
				};
			};
		};
		_newDamage
	}];
} forEach crew _chopper;

// When all units are dead, destroy the heli
[_chopper] spawn {
	params["_chopper"];

	waitUntil {
		({
			alive _x
		} count crew _chopper == 0) || !(alive _chopper)
	};
	_chopper setDamage 1;

	private _grp = createGroup west;
	private _unit = _grp createUnit ["B_Soldier_F", [0,0,0], [], 0, "NONE"];

	// set group callsign
	_grp setGroupIdGlobal ["November"];

	_unit sideRadio "RadioHeliMayday";
	sleep 3;
	player sideRadio "RadioHeliHeloDown";
	sleep 5;
	[west, "Base"] sideRadio "RadioHeliHeloSearchAndRescue";
	sleep 3;

	{
		deleteVehicle _x;
	} forEach units _grp;
	deleteGroup _grp;
};