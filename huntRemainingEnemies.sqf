/*
	    File: huntRemainingEnemies.sqf
	    Usage:
	        [mySquad] execVM "huntRemainingEnemies.sqf";
*/

params ["_squad", ["_tolerance", 0.75]];

ETCS_fnc_enemySide = {
	params ["_group"];
	private _mySide = side _group;

	if (_mySide == west) then {
		east
	} else {
		if (_mySide == east) then {
			west
		} else {
			independent
		};
	};
};

ETCS_fnc_enemyCount = {
	params ["_sideEnemy"];
	count (allUnits select {
		(side _x == _sideEnemy) && (alive _x) && (lifeState _x != "INCAPACITATED")
	})
};

ETCS_fnc_clearWP = {
	params ["_group"];
	{
		deleteWaypoint _x
	} forEachReversed waypoints _group;
};

ETCS_fnc_allEnemies = {
	params ["_enemySide"];
	allUnits select {
		(side _x == _enemySide) && (alive _x) && (lifeState _x != "INCAPACITATED")
	}
};

ETCS_fnc_waitUntilTargetDead = {
	params ["_target", "_enemySide"];
	private _timeNow = time;
	waitUntil {
		sleep 2;
		!alive _target ||
		(lifeState _target == "INCAPACITATED") ||
		(([_enemySide] call ETCS_fnc_enemyCount) == 0) ||
		(time > (_timeNow + 60))
	};
};

ETCS_fnc_mainLogicHuntRemainingEnemies = {
	params ["_squad", "_tolerance"];

	private _enemySide = [_squad] call ETCS_fnc_enemySide;
	private _initialEnemies = [_enemySide] call ETCS_fnc_allEnemies;
	private _initialCount = count _initialEnemies;

	if (_initialCount <= 0) exitWith {};

	// Wait until enemy count drops to 75% or less
	private _threshHoldCount = floor (_initialCount * _tolerance);
	waitUntil {
		([_enemySide] call ETCS_fnc_enemyCount) <= _threshHoldCount
	};

	// exit early if no enemies left
	if (([_enemySide] call ETCS_fnc_enemyCount) == 0) exitWith {};

	// Radio only once
	if (!(missionNamespace getVariable["DoneRadioRadioPapaBearToAllUnitsClearArea", false])) then {
		["TaskUpdated", ["Enemy Hunt", "Eliminate all hostile forces in the area."]] call BIS_fnc_showNotification;
		[west, "Base"] sideRadio "RadioPapaBearToAllUnitsClearArea";
		missionNamespace setVariable["DoneRadioRadioPapaBearToAllUnitsClearArea", true, true];
	};

	// Dynamic hunt loop
	while { ([_enemySide] call ETCS_fnc_enemyCount) > 0 } do {
		private _aliveEnemies = [_enemySide] call ETCS_fnc_allEnemies;
		private _target = _aliveEnemies param [0, objNull];

		hint format ["Objective Updated: Hunt %1 remaining enemies.", count _aliveEnemies];
		if (!(isNull _target) && alive _target) then {
			private _targetPos = getPos _target;
			// Clear waypoints
			[_squad] call ETCS_fnc_clearWP;

			// Add new waypoint to target
			private _wp = _squad addWaypoint [getPos _target, 0];
			_wp setWaypointType "DESTROY"; // could also use "SAD"
			_wp setWaypointBehaviour "AWARE";
			_wp setWaypointCombatMode "RED";
			_wp setWaypointSpeed "FULL";

			[_target, _enemySide] call ETCS_fnc_waitUntilTargetDead;
		} else {
			// Target is invalid, just wait a moment
			systemChat "Target invalid, waiting...";
			sleep 1;
		};
	};
};

addMissionEventHandler ["Draw3D", {
	private _grp = group player;
	private _wpIndex = currentWaypoint _grp;
	private _wpPos = waypointPosition [_grp, _wpIndex];

	// Build label
	private _wpType = waypointType [_grp, _wpIndex];
	if (_wpType isEqualTo "") exitWith {};
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

[_squad, _tolerance] spawn ETCS_fnc_mainLogicHuntRemainingEnemies;