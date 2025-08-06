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
private _checkInterval = 30;

[_chopper, _heliPilot, _aiPilotGroup, _sideEnemy, _basePos, _rtbAltitude, _checkInterval] spawn {
	params ["_chopper", "_heliPilot", "_aiPilotGroup", "_sideEnemy", "_basePos", "_rtbAltitude", "_checkInterval"];
	private _hasSentRadio = false;
	private _halfEnemyCount = floor ((count (allUnits select {
		side _x == _sideEnemy && alive _x
	})) / 2);
	while { true } do {
		private _enemies = allUnits select {
			side _x == _sideEnemy && alive _x
		};
		if ((count _enemies) > 0 && (count _enemies) < _halfEnemyCount && {
			alive _chopper
		}) then {
			if (!_hasSentRadio) then {
				// Send radio message to ground units
				_heliPilot sideRadio "RadioFalconToGroundUnits";
				_hasSentRadio = true;
			};

			// Force AI to engage
			_chopper engineOn true;
			_chopper flyInHeight _rtbAltitude;
			_aiPilotGroup setBehaviourStrong "AWARE";
			_aiPilotGroup setCombatMode "RED";  // Engage enemies
			{
				_x enableAI "MOVE"
			} forEach units _aiPilotGroup;

			// Calculate average enemy position
			private _enemyPos = [0, 0, 0];
			{
				_enemyPos = _enemyPos vectorAdd (getPosATL _x)
			} forEach _enemies;
			_enemyPos = _enemyPos vectorMultiply (1 / (count _enemies));

			// Clear old waypoints
			while { (count (waypoints _aiPilotGroup)) > 0 } do {
				deleteWaypoint ((waypoints _aiPilotGroup) select 0);
			};

			// Add TAKEOFF move waypoint first (forces liftoff)
			private _wp0 = _aiPilotGroup addWaypoint [getPos _chopper, 0];
			_wp0 setWaypointType "MOVE";

			// Add SAD waypoint to enemy position
			private _wp1 = _aiPilotGroup addWaypoint [_enemyPos, 0];
			_wp1 setWaypointType "SAD";
			_wp1 setWaypointStatements ["true", "hint 'Chopper en route to enemies';
			"];

			// Backup: Force movement if AI stuck
			_heliPilot doMove _enemyPos;

			// Monitor and RTB when all enemies are dead
			[_chopper, _aiPilotGroup, _basePos, _sideEnemy] spawn {
				params ["_chopper", "_grp", "_basePos", "_sideEnemy"];

				while { true } do {
					sleep 10;
					private _remainingEnemies = allUnits select {
						side _x == _sideEnemy && alive _x
					};
					if ((count _remainingEnemies) == 0) exitWith {
						// Clear old waypoints
						while { (count (waypoints _grp)) > 0 } do {
							deleteWaypoint ((waypoints _grp) select 0);
						};

						// RTB waypoint
						private _rtbWP = _grp addWaypoint [_basePos, 0];
						_rtbWP setWaypointType "MOVE";
						_rtbWP setWaypointStatements [
							"true",
							"
							hint 'All enemies dead - RTB';
							_chopper land 'LAND';
							{
								unassignVehicle _x;
								_x action ['GetOut', _chopper]
							} forEach units _grp;
							"
						];
					};
				};
			};
		};
		sleep _checkInterval;
	};
};