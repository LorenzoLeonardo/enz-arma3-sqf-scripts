#include "commonFunctions.sqf"

params ["_group", "_grpName"];
_group setGroupId [_grpName];

wait_until_group_on_ground = {
	params ["_grp"];
	waitUntil {
		sleep 1;
		private _onGround = {
			alive _x && (getPosATL _x select 2) < 3
		} count units _grp;
		_onGround >= (count units _grp * 0.7)
	};
};

fnc_callSupportTeam = {
	params ["_caller", "_planeAltitude", "_planeSpeed", "_yDistance", "_yDroppingRadius", "_seizeMarkerName"];

	private _groupCaller = group _caller;
	private _callerPosition = getMarkerPos _seizeMarkerName;
	private _planeGroupName = [groupId _groupCaller] call get_assigned_plane;
	private _initLocation = [_callerPosition select 0, (_callerPosition select 1) - _yDistance, _planeAltitude];
	private _plane = ["CUP_B_C47_USA", _callerPosition, _initLocation, _planeSpeed, _planeGroupName] call initialize_plane;
	private _groupPlatoon = ["Support", _initLocation, _plane] call initialize_group_to_plane;
	private _backPack = [_groupPlatoon] call set_parachute_backpack;
	private _groupBeforeJoin = units _groupPlatoon;
	private _groupCallerID = groupId _groupCaller;

	hint format ["Requesting Reinforcements: %1", groupId _groupCaller];
	((crew _plane) select 0) sideRadio "SupportOnWayStandBy";

	_groupPlatoon copyWaypoints _groupCaller;

	// Wait until plane reaches drop zone
	[_plane, _callerPosition, _yDroppingRadius, _planeAltitude] call wait_until_reach_dropzone;

	// drop troops
	((crew _plane) select 0) sideRadio "RadioAirbaseDropPackage";
	[_groupPlatoon, _plane, _backPack, 0.5] call eject_from_plane;

	// join or rename support group
	if (({
		alive _x
	} count units _groupCaller) == 0) then {
		_groupPlatoon setGroupId [_groupCallerID];
	} else {
		(units _groupPlatoon) join _groupCaller;
		switch (toLower _groupCallerID) do {
			case "alpha": {
				(leader _groupCaller) sideRadio "WeLinkedUpWithTheReinforcementsThanksForTheSupportAlpha";
			};
			case "bravo": {
				(leader _groupCaller) sideRadio "WeLinkedUpWithTheReinforcementsThanksForTheSupportBravo";
			};
			case "charlie": {
				(leader _groupCaller) sideRadio "WeLinkedUpWithTheReinforcementsThanksForTheSupportCharlie";
			};
			case "delta": {
				(leader _groupCaller) sideRadio "WeLinkedUpWithTheReinforcementsThanksForTheSupportDelta";
			};
			default {
				(leader _groupCaller) sideRadio "Reinforcements have linked up.";
			};
		};
	};

	deleteMarkerLocal _seizeMarkerName;

	// Wait until most units are on ground (alt < 3 meters)
	[_groupPlatoon] call wait_until_group_on_ground;
};

while {
	{
		alive _x
	} count units _group > 0
} do {
	private _totalUnits = count units _group;
	if (_totalUnits == 0) exitWith {};

	// Wait until only 1/3 remain
	waitUntil {
		sleep 2;
		private _aliveCount = {
			alive _x
		} count units _group;
		_aliveCount <= (_totalUnits / 3)
	};

	private _aliveUnits = units _group select {
		alive _x
	};
	if (count _aliveUnits == 0) exitWith {};

	private _radioUnit = _aliveUnits select 0;

	// Create marker
	private _callerMarkerName = format ["marker_%1", toLower _grpName];
	private _callerMarkerText = format ["Requesting Paradrop Support (%1)", _grpName];
	deleteMarkerLocal _callerMarkerName;
	private _callerMarker = createMarkerLocal [_callerMarkerName, position _radioUnit];
	_callerMarker setMarkerSizeLocal [1, 1];
	_callerMarker setMarkerShapeLocal "ICON";
	_callerMarker setMarkerTypeLocal "mil_objective";
	_callerMarker setMarkerDirLocal 0;
	_callerMarker setMarkerTextLocal _callerMarkerText;

	// Radio messages and color
	switch (toLower _grpName) do {
		case "alpha": {
			_callerMarker setMarkerColorLocal "ColorBlue";
			_radioUnit sideRadio "RadioAlphaWipedOut";
		};
		case "bravo": {
			_callerMarker setMarkerColorLocal "ColorRed";
			_radioUnit sideRadio "RadioBravoWipedOut";
		};
		case "charlie": {
			_callerMarker setMarkerColorLocal "ColorYellow";
			_radioUnit sideRadio "RadioCharlieWipedOut";
		};
		case "delta": {
			_callerMarker setMarkerColorLocal "ColorOrange";
			_radioUnit sideRadio "RadioDeltaWipedOut";
		};
		default {
			_callerMarker setMarkerColorLocal "ColorWhite";
			_radioUnit sideRadio "RadioUnknownGroupWipedOut";
		};
	};

	// Signal: Flare & Smoke
	private _flrObj = "F_40mm_Red" createVehicle (_radioUnit modelToWorld [0, 0, 200]);
	_flrObj setVelocity [0, 0, -1];
	"SmokeShellRed" createVehicle (position _radioUnit);

	// call support
	[_radioUnit, 350, 300, 8000, 400, _callerMarkerName] call fnc_callSupportTeam;

	sleep 60;  // Delay before next monitoring cycle (ensures no stacking of requests)
};