#include "paraDrop.sqf"
#include "reviveSystem.sqf"

params ["_group"];

// Save original unit types and loadouts
private _originalGroupTemplate = [_group] call fnc_saveOriginalGroupTemplates;
private _totalUnits = count units _group;

fnc_getQuietUnit = {
	params ["_group"];

	private _leader = leader _group;
	private _quietUnit = objNull;

	{
		if ((alive _x) && !isPlayer _x && (_x != _leader) && !(_x getVariable ["isRadioBusy", false])) exitWith {
			_quietUnit = _x;
		};
	} forEach (units _group);

	_quietUnit
};

[_group, _originalGroupTemplate, _totalUnits] spawn {
	params ["_group", "_originalGroupTemplate", "_totalUnits"];
	sleep 2;

	while { true } do {
		waitUntil {
			sleep 2;
			private _aliveCount = {
				alive _x && (lifeState _x != "INCAPACITATED")
			} count units _group;
			_aliveCount <= (_totalUnits / 3)
		};

		private _radioUnit = [_group] call fnc_getQuietUnit;
		private _paraDropMarkerName = [_radioUnit, groupId _group] call fnc_setSupportMarkerAndRadio;

		// Signal: Flare & Smoke
		private _flrObj = "F_40mm_Red" createVehicle (_radioUnit modelToWorld [0, 0, 200]);
		_flrObj setVelocity [0, 0, -1];
		"SmokeShellRed" createVehicle (position _radioUnit);

		// Plane's cruising altitude
		private _planeAltitude = 200;
		// Plan starts at 8, 000 meters south of the drop zone
		private _yDistance = 8000;
		// Plane's speed
		private _planeSpeed = 300;
		// Radius of from the center of the drop where to start dropping troops.
		private _yDroppingRadius = 400;
		// Get Assigned plane's name
		private _planeGroupName = [groupId _group] call fnc_getAssignedPlane;
		private _callerPosition = getMarkerPos _paraDropMarkerName;
		// Initial location of the plane
		private _initLocation = [_callerPosition select 0, (_callerPosition select 1) - _yDistance, _planeAltitude];
		// Create the plane
		private _plane = ["CUP_B_C47_USA", _callerPosition, _initLocation, _planeSpeed, _planeGroupName] call fnc_initializePlane;
		// Create group to be drop from Template or original group. This can be an arbitrary group too.
		private _groupToBeDropped = [west, _initLocation, _plane, _originalGroupTemplate] call fnc_createGroupFromTemplate;
		// Add reviving characteristic of the newly created group.
		[_groupToBeDropped] execVM "reviveSystem.sqf";
		// Start executing the paradrop system.
		[_radioUnit, _plane, _planeAltitude, _yDroppingRadius, _paraDropMarkerName, _groupToBeDropped] call fnc_executeParaDrop;
	};
};