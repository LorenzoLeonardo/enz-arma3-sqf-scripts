/*
	    File: huntRemainingEnemies.sqf
	    Usage:
	        [mySquad] execVM "huntRemainingEnemies.sqf";
*/

params ["_squad"];

// Detect enemy side automatically
private _mySide = side _squad;
private _enemySide = if (_mySide == west) then {
	east
} else {
	if (_mySide == east) then {
		west
	} else {
		independent
	};
};

// Record original enemy count
private _initialEnemies = allUnits select {
	side _x == _enemySide && alive _x
};
private _initialCount = count _initialEnemies;
if (_initialCount <= 0) exitWith {};

// Wait until enemy count drops to 50% or less
waitUntil {
	sleep 5;
	private _aliveCount = {
		side _x == _enemySide && alive _x
	} count allUnits;
	(_aliveCount > 0 && _aliveCount <= (_initialCount / 2)) || (_aliveCount == 0)
};

// exit early if no enemies left
if ({
	side _x == _enemySide && alive _x
} count allUnits == 0) exitWith {};

[west, "Base"] sideRadio "RadioPapaBearToAllUnitsClearArea";

// Dynamic hunt loop
while {
	({
		side _x == _enemySide && alive _x
	} count allUnits) > 0
} do {
	private _aliveEnemies = allUnits select {
		side _x == _enemySide && alive _x
	};
	private _target = _aliveEnemies param [0, objNull];

	if (!isNull _target) then {
		// Clear waypoints
		while { (count waypoints _squad) > 0 } do {
			deleteWaypoint [_squad, 0];
		};

		// Add new waypoint to target
		private _wp = _squad addWaypoint [getPos _target, 0];
		_wp setWaypointType "DESTROY"; // could also use "SAD"
		_wp setWaypointBehaviour "AWARE";
		_wp setWaypointCombatMode "RED";
		_wp setWaypointSpeed "FULL";

		_aliveEnemies = allUnits select {
			side _x == _enemySide && alive _x
		};
		hint format ["Objective Updated: Hunt %1 remaining enemies.", count _aliveEnemies];
		// Wait until that specific target is dead before moving on
		waitUntil {
			sleep 2;
			!alive _target ||
			(lifeState _target == "INCAPACITATED") ||
			(({
				alive _x && side _x == _enemySide
			} count allUnits) == 0)
		};
	};
};