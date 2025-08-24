#include "paraDropHelpers.sqf"
#include "reviveSystem.sqf"

params ["_group", "_papaBear"];

// Save original unit types and loadouts
private _originalGroupTemplate = [_group] call fnc_saveOriginalGroupTemplates;
private _totalUnits = count units _group;

fnc_getQuietUnit = {
	params ["_group"];

	private _leader = leader _group;
	private _quietUnit = objNull;

	{
		if ((alive _x) && (_x != _leader) && !(_x getVariable ["isRadioBusy", false])) exitWith {
			_quietUnit = _x;
		};
	} forEach (units _group);

	if (isNull _quietUnit) then {
		_quietUnit = leader _group;
	};
	_quietUnit
};

missionNamespace setVariable [CALLBACK_PARA_DROP_STATUS, {
	params ["_requestor", "_responder", "_groupToBeDropped", "_phase"];
	private _groupCallerID = groupId (group _requestor);
	_requestor setVariable ["isRadioBusy", true];
	_responder setVariable ["isRadioBusy", true];
	switch (_phase) do {
		case PARA_DROP_PHASE_ACKNOWLEDGED: {
			hint format ["Requesting Reinforcements: %1", _groupCallerID];
			_responder sideRadio "SupportOnWayStandBy";
			_groupToBeDropped copyWaypoints (group _requestor);
		};
		case PARA_DROP_PHASE_DROPPING: {
			_responder sideRadio "RadioAirbaseDropPackage";
		};
		case PARA_DROP_PHASE_DONE: {
			hint format ["Reinforcements has arrived for %1.", _groupCallerID];
		};
		default {
			hint "Unsupported phase!";
		};
	};
	_requestor setVariable ["isRadioBusy", false];
	_responder setVariable ["isRadioBusy", false];
}];

fnc_getAssignedPlane = {
	private _teamName = _this select 0;
	private _planeAssigned="";
	switch (toLower _teamName) do {
		case "alpha": {
			_planeAssigned = "November (Alpha)";
		};
		case "bravo": {
			_planeAssigned = "November (Bravo)";
		};
		case "charlie": {
			_planeAssigned = "November (Charlie)";
		};
		case "delta": {
			_planeAssigned = "November (Delta)";
		};
		case "echo": {
			_planeAssigned = "November (Echo)";
		};
		default {
			hint format["%1 is not a valid squad name. Please use Alpha, Bravo, Charlie, Delta", _teamName];
		};
	};
	_planeAssigned
};

fnc_setSupportMarkerAndRadio = {
	params ["_unit", "_grpName", "_papaBear"];
	private _responder = [_papaBear] call fnc_getQuietUnit;
	private _markerName = format ["paraDropMarker_%1", diag_tickTime];
	private _markerText = format ["Requesting Paradrop Support (%1)", _grpName];
	private _marker = createMarkerLocal [_markerName, position _unit];
	_marker setMarkerSizeLocal [1, 1];
	_marker setMarkerShapeLocal "ICON";
	_marker setMarkerTypeLocal "mil_objective";
	_marker setMarkerDirLocal 0;
	_marker setMarkerTextLocal _markerText;

	_unit setVariable ["isRadioBusy", true];
	_responder setVariable ["isRadioBusy", true];

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
			_marker setMarkerColorLocal "ColorGreen";
			_unit sideRadio "RadioCharlieWipedOut";
		};
		case "delta": {
			_marker setMarkerColorLocal "ColorYellow";
			_unit sideRadio "RadioDeltaWipedOut";
		};
		case "echo": {
			_marker setMarkerColorLocal "ColorOrange";
			_unit sideRadio "RadioEchoWipedOut";
		};
		default {
			_marker setMarkerColorLocal "ColorWhite";
			_unit sideRadio "RadioUnknownGroupWipedOut";
		};
	};
	sleep 15;
	_responder sideRadio "RadioPapaBearReplyWipedOut";
	sleep 8;
	_unit setVariable ["isRadioBusy", false];
	_responder setVariable ["isRadioBusy", false];
	_markerName
};

fnc_joinReinforcementToGroup = {
	params ["_group", "_groupCallerID", "_reinforcements"];
	private _quietUnit = [_group] call fnc_getQuietUnit;
	if (({
		alive _x
	} count units _group) == 0) then {
		deleteGroup _group;
		_reinforcements setGroupId [_groupCallerID];
		_group = _reinforcements;
	} else {
		(units _reinforcements) join _group;
	};
	switch (toLower _groupCallerID) do {
		case "alpha": {
			_quietUnit sideRadio "WeLinkedUpWithTheReinforcementsThanksForTheSupportAlpha";
		};
		case "bravo": {
			_quietUnit sideRadio "WeLinkedUpWithTheReinforcementsThanksForTheSupportBravo";
		};
		case "charlie": {
			_quietUnit sideRadio "WeLinkedUpWithTheReinforcementsThanksForTheSupportCharlie";
		};
		case "delta": {
			_quietUnit sideRadio "WeLinkedUpWithTheReinforcementsThanksForTheSupportDelta";
		};
		case "echo": {
			_quietUnit sideRadio "WeLinkedUpWithTheReinforcementsThanksForTheSupportEcho";
		};
		default {
			_quietUnit sideRadio "Reinforcements have linked up.";
		};
	};
	_group
};

[_group, _originalGroupTemplate, _totalUnits, _papaBear] spawn {
	params ["_group", "_originalGroupTemplate", "_totalUnits", "_papaBear"];
	sleep 5;

	while { true } do {
		waitUntil {
			sleep 2;
			private _aliveCount = {
				alive _x && (lifeState _x != "INCAPACITATED")
			} count units _group;
			_aliveCount <= (_totalUnits / 3)
		};

		private _radioUnit = [_group] call fnc_getQuietUnit;
		private _groupCallerID = groupId _group;
		// Signal: Flare & Smoke
		private _flrObj = "F_40mm_Red" createVehicle (_radioUnit modelToWorld [0, 0, 200]);

		_flrObj setVelocity [0, 0, -1];
		"SmokeShellRed" createVehicle (position _radioUnit);

		private _paraDropMarkerName = [_radioUnit, groupId _group, _papaBear] call fnc_setSupportMarkerAndRadio;
		// Plane's cruising altitude
		private _planeAltitude = 200;
		// Plan starts at 5, 000 meters south of the drop zone
		private _yDistance = 5000;
		// Plane's speed
		private _planeSpeed = 150;
		// Radius of from the center of the drop where to start dropping troops.
		private _yDroppingRadius = 400;
		// Get Assigned plane's name
		private _planeGroupName = [groupId _group] call fnc_getAssignedPlane;
		private _paraDropLocation = getMarkerPos _paraDropMarkerName;
		// Initial location of the plane
		private _initLocation = [_paraDropLocation select 0, (_paraDropLocation select 1) - _yDistance, _planeAltitude];
		// Create the plane
		private _plane = [west, "CUP_B_US_Pilot", "CUP_B_C130J_USMC", _paraDropLocation, _initLocation, _planeSpeed, _planeGroupName] call fnc_initializePlane;
		// Always Turn off lights
		_plane setCollisionLight false;
		_plane disableAI "LIGHTS";
		// Create group to be drop from Template or original group. This can be an arbitrary group too.
		private _groupToBeDropped = [west, _initLocation, _plane, _originalGroupTemplate] call fnc_createGroupFromTemplate;
		// Add reviving characteristic of the newly created group.
		[_groupToBeDropped] execVM "reviveSystem.sqf";
		// Start executing the paradrop system.
		[_radioUnit, _plane, _planeAltitude, _yDroppingRadius, _paraDropLocation, _groupToBeDropped] call fnc_executeParaDrop;
		(driver _plane) sideRadio "RadioAirbasePackageOnGround";
		sleep 3;
		([_papaBear] call fnc_getQuietUnit) sideRadio "RadioAirbasePackageOnGroundReply";
		_group = [_group, _groupCallerID, _groupToBeDropped] call fnc_joinReinforcementToGroup;

		deleteMarkerLocal _paraDropMarkerName;
	};
};