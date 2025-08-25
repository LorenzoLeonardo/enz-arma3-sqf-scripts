/*
	    File: huntRemainingEnemies.sqf
	    Usage:
	        [mySquad] execVM "huntRemainingEnemies.sqf";
*/

params ["_squad"];

addMissionEventHandler ["Draw3D", {
	private _grp = group player;
	private _wpIndex = currentWaypoint _grp;
	private _wpPos = waypointPosition [_grp, _wpIndex];

	// Build label
	private _wpType = waypointType [_grp, _wpIndex];
	if (_wpType isEqualTo "") then {
		_wpType = "Waypoint"
	};
	private _wpText = format ["%1 (%2 m)", _wpType, round (player distance _wpPos)];

	// Draw icon + text
	drawIcon3D [
		"\A3\ui_f\data\map\markers\military\arrow2_CA.paa",
		[0, 1, 0, 1],
		_wpPos, // position
		0.5, 0.5, // icon size
		180, // icon angle
		_wpText, // text
		2, // shadow
		0.035, // text size
		"PuristaBold", // font
		"center", // align
		true, // drawThrough
		0, // textShiftX
		-0.04 // textShiftY (lift text above icon)
	];
}];

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

fnc_getEnemyCount = {
	params ["_sideEnemy"];
	count (allUnits select {
		side _x == _sideEnemy && alive _x
	})
};

// Wait until enemy count drops to 75% or less
private _threshHoldCount = floor (([_enemySide] call fnc_getEnemyCount) * 0.75);
waitUntil {
	([_enemySide] call fnc_getEnemyCount) <= _threshHoldCount
};

// exit early if no enemies left
if ({
	side _x == _enemySide && alive _x
} count allUnits == 0) exitWith {};

// Radio only once
if (!(missionNamespace getVariable["DoneRadioRadioPapaBearToAllUnitsClearArea", false])) then {
	[west, "Base"] sideRadio "RadioPapaBearToAllUnitsClearArea";
	missionNamespace setVariable["DoneRadioRadioPapaBearToAllUnitsClearArea", true, true];
};

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

		_squad setFormation "WEDGE";
		_squad setCombatMode "YELLOW";
		// Add new waypoint to target
		private _wp = _squad addWaypoint [getPos _target, 0];
		_wp setWaypointType "DESTROY"; // could also use "SAD"
		_wp setWaypointBehaviour "AWARE";
		_wp setWaypointCombatMode "RED";
		_wp setWaypointSpeed "FULL";
		_wp setWaypointDescription "DESTROY";

		_aliveEnemies = allUnits select {
			side _x == _enemySide && alive _x
		};
		hint format ["Objective Updated: Hunt %1 remaining enemies.", count _aliveEnemies];
		// Wait until that specific target is dead before moving on
		private _timeNow = time;
		waitUntil {
			sleep 2;
			!alive _target ||
			(lifeState _target == "INCAPACITATED") ||
			(({
				alive _x && side _x == _enemySide
			} count allUnits) == 0) ||
			(time > (_timeNow + 60))
		};
	};
};