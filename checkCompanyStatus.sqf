#include "common.sqf"
#include "paraDropHelpers.sqf"
#include "reviveSystem.sqf"

private _group = _this param [0];
private _papaBear = _this param [1];
private _callRetries = _this param [2, 3];
// Save original unit types and loadouts
private _originalGroupTemplate = [_group] call ETCS_fnc_saveOriginalGroupTemplates;
private _totalUnits = count units _group;

missionNamespace setVariable [CALLBACK_PARA_DROP_STATUS, {
	params ["_requestor", "_responder", "_groupToBeDropped", "_phase"];

	switch (_phase) do {
		case PARA_DROP_PHASE_ACKNOWLEDGED: {
			private _groupCallerID = groupId (group _requestor);
			hint format ["Requesting Reinforcements: %1", _groupCallerID];
			[_responder, "SupportOnWayStandBy", 2] call ETCS_fnc_callSideRadio;
			_groupToBeDropped copyWaypoints (group _requestor);
		};
		case PARA_DROP_PHASE_DROPPING: {
			[_responder, "RadioAirbaseDropPackage", 3] call ETCS_fnc_callSideRadio;
		};
		case PARA_DROP_PHASE_DONE: {};
		default {
			hint "Unsupported phase!";
		};
	};
}];

ETCS_fnc_getAssignedPlane = {
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

ETCS_fnc_setSupportMarkerAndRadio = {
	params ["_unit", "_grpName", "_papaBear"];
	private _responder = [_papaBear] call ETCS_fnc_getQuietUnit;
	private _markerName = format ["paraDropMarker_%1", diag_tickTime];
	private _markerText = format ["Requesting Paradrop Support (%1)", _grpName];
	private _marker = createMarkerLocal [_markerName, position _unit];
	_marker setMarkerSizeLocal [1, 1];
	_marker setMarkerShapeLocal "ICON";
	_marker setMarkerTypeLocal "respawn_para";
	_marker setMarkerDirLocal 0;
	_marker setMarkerTextLocal _markerText;

	_unit setVariable ["isRadioBusy", true];
	_responder setVariable ["isRadioBusy", true];

	switch (toLower _grpName) do {
		case "alpha": {
			_marker setMarkerColorLocal "ColorBlue";
			[_unit, "RadioAlphaWipedOut", 15] call ETCS_fnc_callSideRadio;
		};
		case "bravo": {
			_marker setMarkerColorLocal "ColorRed";
			[_unit, "RadioBravoWipedOut", 15] call ETCS_fnc_callSideRadio;
		};
		case "charlie":{
			_marker setMarkerColorLocal "ColorGreen";
			[_unit, "RadioCharlieWipedOut", 15] call ETCS_fnc_callSideRadio;
		};
		case "delta": {
			_marker setMarkerColorLocal "ColorYellow";
			[_unit, "RadioDeltaWipedOut", 15] call ETCS_fnc_callSideRadio;
		};
		case "echo": {
			_marker setMarkerColorLocal "ColorOrange";
			[_unit, "RadioEchoWipedOut", 15] call ETCS_fnc_callSideRadio;
		};
		default {
			_marker setMarkerColorLocal "ColorWhite";
			[_unit, "RadioUnknownGroupWipedOut", 15] call ETCS_fnc_callSideRadio;
		};
	};
	[_responder, "RadioPapaBearReplyWipedOut", 8] call ETCS_fnc_callSideRadio;
	_markerName
};

ETCS_fnc_joinReinforcementToGroup = {
	params ["_group", "_groupCallerID", "_reinforcements"];
	private _quietUnit = [_group] call ETCS_fnc_getQuietUnit;
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
			[_quietUnit, "WeLinkedUpWithTheReinforcementsThanksForTheSupportAlpha", 5] call ETCS_fnc_callSideRadio;
		};
		case "bravo": {
			[_quietUnit, "WeLinkedUpWithTheReinforcementsThanksForTheSupportBravo", 5] call ETCS_fnc_callSideRadio;
		};
		case "charlie": {
			[_quietUnit, "WeLinkedUpWithTheReinforcementsThanksForTheSupportCharlie", 5] call ETCS_fnc_callSideRadio;
		};
		case "delta": {
			[_quietUnit, "WeLinkedUpWithTheReinforcementsThanksForTheSupportDelta", 5] call ETCS_fnc_callSideRadio;
		};
		case "echo": {
			[_quietUnit, "WeLinkedUpWithTheReinforcementsThanksForTheSupportEcho", 5] call ETCS_fnc_callSideRadio;
		};
		default {};
	};
	_group
};

ETCS_fnc_spawnDistressSmokeSignal = {
	params ["_radioUnit"];
	private _pos = position _radioUnit;
	private _posFlare = _pos vectorAdd [0, 0, 150];
	private _posSmoke = _pos vectorAdd [0, 0, 150];
	{
		private _flrObj = "F_40mm_red" createVehicle _posFlare;
		_flrObj setVelocity [0, 0, -1];

		private _proj = "SmokeShellBlue" createVehicle _posSmoke;
		_proj setVelocity [0, 0, -5];
		sleep 30;
	} forEach [1, 2, 3];
};

ETCS_fnc_isGroupAlive = {
	params ["_group"];
	private _aliveCount = {
		alive _x && {
			lifeState _x != "INCAPACITATED"
		}
	} count (units _group);
	_aliveCount > 0
};

[_group, _originalGroupTemplate, _totalUnits, _papaBear, _callRetries] spawn {
	params ["_group", "_originalGroupTemplate", "_totalUnits", "_papaBear", "_callRetries"];
	private _groupCallerID = groupId _group;

	for "_i" from 0 to _callRetries do {
		while {
			private _aliveCount = {
				alive _x && (lifeState _x != "INCAPACITATED")
			} count units _group;
			_aliveCount > (_totalUnits / 4)
		} do {
			sleep 2;
		};

		if (!([_group] call ETCS_fnc_isGroupAlive)) exitWith {
			["TaskFailed", ["Team Wipedout", ["Lost contact with %1 team!", _groupCallerID]]] call BIS_fnc_showNotification;
		};

		["TaskAssigned", ["Request Reinforcements", format ["Requesting reinforcements for %1", _groupCallerID]]] call BIS_fnc_showNotification;

		private _radioUnit = [_group] call ETCS_fnc_getQuietUnit;
		// Signal: Flare & Smoke
		[_radioUnit] spawn ETCS_fnc_spawnDistressSmokeSignal;

		private _paraDropMarkerName = [_radioUnit, groupId _group, _papaBear] call ETCS_fnc_setSupportMarkerAndRadio;
		// Plane's cruising altitude
		private _planeAltitude = 200;
		// Plan starts at 5, 000 meters south of the drop zone
		private _yDistance = 5000;
		// Plane's speed
		private _planeSpeed = 150;
		// Radius of from the center of the drop where to start dropping troops.
		private _yDroppingRadius = 400;
		// Get Assigned plane's name
		private _planeGroupName = [groupId _group] call ETCS_fnc_getAssignedPlane;
		private _paraDropLocation = getMarkerPos _paraDropMarkerName;
		// Initial location of the plane
		private _initLocation = [_paraDropLocation select 0, (_paraDropLocation select 1) - _yDistance, _planeAltitude];
		// Create the plane
		private _plane = [west, "CUP_B_US_Pilot", "CUP_B_C130J_USMC", _paraDropLocation, _initLocation, _planeSpeed, _planeGroupName] call ETCS_fnc_initializePlane;
		// Always Turn off lights
		_plane setCollisionLight false;
		_plane disableAI "LIGHTS";
		// Create group to be drop from Template or original group. This can be an arbitrary group too.
		private _groupToBeDropped = [west, _initLocation, _plane, _originalGroupTemplate] call ETCS_fnc_createGroupFromTemplate;
		private _groupToBeDroppedID = [_groupCallerID] call ETCS_fnc_assignUniqueGroupId;
		_groupToBeDropped setGroupId [_groupToBeDroppedID];
		// Add reviving characteristic of the newly created group.
		[_groupToBeDropped] call ETCS_fnc_registerReviveSystem;
		// Start executing the paradrop system.
		[_radioUnit, _plane, _planeAltitude, _yDroppingRadius, _paraDropLocation, _groupToBeDropped] call ETCS_fnc_executeParaDrop;
		[(driver _plane), "RadioAirbasePackageOnGround", 3] call ETCS_fnc_callSideRadio;
		[([_papaBear] call ETCS_fnc_getQuietUnit), "RadioAirbasePackageOnGroundReply", 3] call ETCS_fnc_callSideRadio;
		_group = [_group, _groupCallerID, _groupToBeDropped] call ETCS_fnc_joinReinforcementToGroup;

		_groupCallerID = groupId (_group);

		["TaskSucceeded", ["Task Completed", format ["Reinforcements has arrived for %1.", _groupCallerID]]] call BIS_fnc_showNotification;
		deleteMarkerLocal _paraDropMarkerName;
	};
};

[_group, _papaBear] spawn {
	params ["_group", "_papaBear"];
	private _groupCallerID = groupId _group;
	while { [_group] call ETCS_fnc_isGroupAlive } do {
		sleep 1;
	};
	private _hqUnit = [_papaBear] call ETCS_fnc_getQuietUnit;

	switch (toLower _groupCallerID) do {
		case "alpha": {
			[_hqUnit, "LostContactWithAlphaTeam", 5] call ETCS_fnc_callSideRadio;
		};
		case "bravo": {
			[_hqUnit, "LostContactWithBravoTeam", 5] call ETCS_fnc_callSideRadio;
		};
		case "charlie": {
			[_hqUnit, "LostContactWithCharlieTeam", 5] call ETCS_fnc_callSideRadio;
		};
		case "delta": {
			[_hqUnit, "LostContactWithDeltaTeam", 5] call ETCS_fnc_callSideRadio;
		};
		default {
			[_hqUnit, "LostContactWithUnknownTeam", 5] call ETCS_fnc_callSideRadio;
		};
	};
};