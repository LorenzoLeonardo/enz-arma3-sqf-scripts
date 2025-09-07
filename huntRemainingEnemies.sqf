/*
	    File: huntRemainingEnemies.sqf
	    Usage:
	        [mySquad] execVM "huntRemainingEnemies.sqf";
*/
#include "common.sqf"

params ["_squad", ["_tolerance", 0.75]];

ETCS_fnc_waitUntilTargetDead = {
	params ["_target", "_squad"];
	private _timeNow = time;
	while {
		alive _target &&
		(lifeState _target != "INCAPACITATED") &&
		(([_squad] call ETCS_fnc_getEnemyCount) > 0) &&
		(time <= (_timeNow + 60))
	} do {
		sleep 0.5;
	};
};

ETCS_fnc_mainLogicHuntRemainingEnemies = {
	params ["_squad", "_tolerance"];

	private _initialCount = [_squad] call ETCS_fnc_getEnemyCount;

	if (_initialCount <= 0) exitWith {};

	// Wait until enemy count drops to 75% or less
	private _threshHoldCount = floor (_initialCount * _tolerance);
	while { ([_squad] call ETCS_fnc_getEnemyCount) > _threshHoldCount } do {
		sleep 0.5;
	};

	// exit early if no enemies left
	if (([_squad] call ETCS_fnc_getEnemyCount) == 0) exitWith {};

	// Radio only once
	if (!(missionNamespace getVariable["DoneRadioRadioPapaBearToAllUnitsClearArea", false])) then {
		["TaskUpdated", ["Enemy Hunt", "Eliminate all hostile forces in the area."]] call BIS_fnc_showNotification;
		[west, "Base"] sideRadio "RadioPapaBearToAllUnitsClearArea";
		missionNamespace setVariable["DoneRadioRadioPapaBearToAllUnitsClearArea", true, true];
	};

	// Dynamic hunt loop
	while { ([_squad] call ETCS_fnc_getEnemyCount) > 0 } do {
		private _aliveEnemies = [_squad] call ETCS_fnc_getAllEnemies;
		private _target = _aliveEnemies param [0, objNull];

		hint format ["Objective Updated: Hunt %1 remaining enemies.", count _aliveEnemies];
		if (!(isNull _target) && alive _target) then {
			private _targetPos = getPos _target;
			// Clear waypoints
			[_squad] call ETCS_fnc_clearWaypoints;

			// Add new waypoint to target
			private _wp = _squad addWaypoint [getPos _target, 0];
			_wp setWaypointType "DESTROY"; // could also use "SAD"
			_wp setWaypointBehaviour "AWARE";
			_wp setWaypointCombatMode "RED";
			_wp setWaypointSpeed "FULL";

			[_target, _squad] call ETCS_fnc_waitUntilTargetDead;
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

    // Build multi-line label
    private _wpType = waypointType [_grp, _wpIndex];
    if (_wpType isEqualTo "") exitWith {};

    private _lines = [
        format ["Type: %1", _wpType],
        format ["Distance: %1 m", round (player distance _wpPos)],
        format ["WP Index: %1", _wpIndex]
    ];

    private _lineOffset = 0.03; // vertical spacing between lines

    {
        private _i = _forEachIndex;
        private _linePos = _wpPos vectorAdd [0, 0, _i * _lineOffset];
        drawIcon3D [
            "\A3\ui_f\data\map\markers\military\arrow2_CA.paa",
            [0, 1, 0, 1],
            _linePos,
            0.5, 0.5,
            180,
            _x,
            2,
            0.035,
            "PuristaBold",
            "center",
            true,
            0,
            -0.04
        ];
    } forEach _lines;
}];

[_squad, _tolerance] spawn ETCS_fnc_mainLogicHuntRemainingEnemies;