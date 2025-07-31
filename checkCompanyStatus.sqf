#include "commonFunctions.sqf"

params ["_group", "_grpName"];

_group setGroupId [_grpName];

fnc_callSupportTeam = {
	params["_caller", "_planeAltitude", "_planeSpeed", "_yDistance", "_yDroppingRadius", "_seizeMarkerName"];

	private _groupCaller = (group _caller);
	private _callerPosition = getMarkerPos _seizeMarkerName;
	private _planeGroupName = [groupId _groupCaller] call get_assigned_plane;
	private _initLocation = [_callerPosition select 0, (_callerPosition select 1) - _yDistance, _planeAltitude];
	private _plane = ["CUP_B_C47_USA", _callerPosition, _initLocation, _planeSpeed, _planeGroupName] call initialize_plane;
	private _groupPlatoon = ["Support", _initLocation, _plane] call initialize_group_to_plane;
	private _backPack = [_groupPlatoon] call set_parachute_backpack;
	private _groupArrayBeforeJoin = units _groupPlatoon;
	private _groupCallerID = groupId _groupCaller;
	hint format ["Requesting Reinforcements: %1", groupId _groupCaller];
	((crew _plane) select 0) sideRadio "SupportOnWayStandBy";

	_groupPlatoon copyWaypoints _groupCaller;

	// Wait and Check the plane distance to the marker before starting unloading troops
	[_plane, _callerPosition, _yDroppingRadius, _planeAltitude] call wait_until_reach_dropzone;

	// hint format ["Paratroopers are now jumping from the air"];
	((crew _plane) select 0) sideRadio "RadioAirbaseDropPackage";
	[_groupPlatoon, _plane, _backPack, 0.5] call eject_from_plane;

	if ({
		alive _x
	} count units _groupCaller == 0) then {
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
			case "charlie":	{
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
};

while {
	{
		alive _x
	} count units _group > 0
} do {
	private _totalUnits = count units _group;
	if (_totalUnits == 0) exitWith {};  // Just in case

	// Wait until group loses more than 2/3 of its members
	waitUntil {
		sleep 2;
		private _aliveCount = {
			alive _x
		} count units _group;
		(_aliveCount <= (_totalUnits / 3))
	};

	private _aliveUnits = units _group select {
		alive _x
	};
	if (count _aliveUnits == 0) exitWith {};

	private _radioUnit = _aliveUnits select 0;

	// --- Begin Reaction ---
	private _callerMarkerName = format ["marker_%1", toLower _grpName];
	private _callerMarkerText = format ["Requesting Paradrop Support (%1)", _grpName];

	// Remove old marker if any
	deleteMarkerLocal _callerMarkerName;
	private _callerMarker = createMarkerLocal [_callerMarkerName, position _radioUnit];
	_callerMarker setMarkerSizeLocal [1, 1];
	_callerMarker setMarkerShapeLocal "ICON";
	_callerMarker setMarkerTypeLocal "mil_objective";
	_callerMarker setMarkerDirLocal 0;
	_callerMarker setMarkerTextLocal _callerMarkerText;

	// Radio messages and marker color
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

	// Flare signal
	private _flrObj = "F_40mm_Red" createVehicle (_radioUnit modelToWorld [0, 0, 200]);
	_flrObj setVelocity [0, 0, -1];

	// Smoke signal
	"SmokeShellRed" createVehicle (position _radioUnit);

	// call drop support if group has survivors
	if (count _aliveUnits > 0) then {
		private _supportCaller = _aliveUnits select 0;
		[_supportCaller, 350, 300, 8000, 400, _callerMarkerName] call fnc_callSupportTeam;
	};
};