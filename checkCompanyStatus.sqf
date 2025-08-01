#include "commonFunctions.sqf"

params ["_group", "_grpName"];

// Save original unit types and loadouts
private _originalLoadouts = [];
{
	_originalLoadouts pushBack [typeOf _x, getUnitLoadout _x];
} forEach units _group;

_group setGroupId [_grpName];
private _totalUnits = count units _group;
private _supportCalled = false;

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

create_group_from_template = {
	params ["_side", "_spawnPos", "_plane", "_template"];
	private _group = createGroup _side;
	{
		private _type = _x select 0;
		private _loadout = _x select 1;
		private _unit = _group createUnit [_type, _spawnPos, [], 0, "NONE"];
		_unit setUnitLoadout _loadout;
		_unit moveInCargo _plane;
	} forEach _template;
	_group
};

// Helper: set marker and radio message
set_support_marker_and_radio = {
	params ["_unit", "_grpName"];
	private _markerName = format ["marker_%1", toLower _grpName];
	private _markerText = format ["Requesting Paradrop Support (%1)", _grpName];
	deleteMarkerLocal _markerName;
	private _marker = createMarkerLocal [_markerName, position _unit];
	_marker setMarkerSizeLocal [1, 1];
	_marker setMarkerShapeLocal "ICON";
	_marker setMarkerTypeLocal "mil_objective";
	_marker setMarkerDirLocal 0;
	_marker setMarkerTextLocal _markerText;

	switch (toLower _grpName) do {
		case "alpha": {
			_marker setMarkerColorLocal "ColorBlue";
			_unit sideRadio "RadioAlphaWipedOut";
		};
		case "bravo": {
			_marker setMarkerColorLocal "ColorRed";
			_unit sideRadio "RadioBravoWipedOut";
		};
		case "charlie":{
			_marker setMarkerColorLocal "ColorYellow";
			_unit sideRadio "RadioCharlieWipedOut";
		};
		case "delta": {
			_marker setMarkerColorLocal "ColorOrange";
			_unit sideRadio "RadioDeltaWipedOut";
		};
		default {
			_marker setMarkerColorLocal "ColorWhite";
			_unit sideRadio "RadioUnknownGroupWipedOut";
		};
	};
	_markerName
};

fnc_callSupportTeam = {
	params ["_caller", "_planeAltitude", "_planeSpeed", "_yDistance", "_yDroppingRadius", "_seizeMarkerName", "_savedLoadouts"];

	private _groupCaller = group _caller;
	private _callerPosition = getMarkerPos _seizeMarkerName;
	private _planeGroupName = [groupId _groupCaller] call get_assigned_plane;
	private _initLocation = [_callerPosition select 0, (_callerPosition select 1) - _yDistance, _planeAltitude];
	private _plane = ["CUP_B_C47_USA", _callerPosition, _initLocation, _planeSpeed, _planeGroupName] call initialize_plane;
	private _groupPlatoon = [west, _initLocation, _plane, _savedLoadouts] call create_group_from_template;
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

	// Optional: Add timeout here to verify drop success

	// join or rename group
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
	[_groupPlatoon] call wait_until_group_on_ground;
};

while { true } do {
	waitUntil {
		sleep 2;
		private _aliveCount = {
			alive _x
		} count units _group;
		_aliveCount <= (_totalUnits / 3)
	};

	if (_supportCalled) then {
		continue;
	};

	private _aliveUnits = units _group select {
		alive _x
	};

	if (count _aliveUnits == 0) then {
		continue;
	};

	private _radioUnit = _aliveUnits select 0;
	private _markerName = [_radioUnit, _grpName] call set_support_marker_and_radio;

	// Signal: Flare & Smoke
	private _flrObj = "F_40mm_Red" createVehicle (_radioUnit modelToWorld [0, 0, 200]);
	_flrObj setVelocity [0, 0, -1];
	"SmokeShellRed" createVehicle (position _radioUnit);

	// call support
	[_radioUnit, 350, 300, 8000, 400, _markerName, _originalLoadouts] call fnc_callSupportTeam;

	_supportCalled = true;
};