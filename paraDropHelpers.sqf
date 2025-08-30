// paraDropHelpers.sqf
// Helper functions for para drop operations
// Author: Lorenzo Leonardo
// Email: enzotechcomputersolutions@gmail.com
// date: August 2025
// Version: 1.0

// Define constants for para drop phases
#define CALLBACK_PARA_DROP_STATUS "Callback_ParaDrop"
// Phase when the para drop request has been acknowledged
#define PARA_DROP_PHASE_ACKNOWLEDGED "Acknowledged"
// Phase when the para drop request has been acknowledged
#define PARA_DROP_PHASE_DROPPING "Dropping"
// Phase when the troops are being dropped
#define PARA_DROP_PHASE_DONE "Done"

// Callback function to notify the status of the para drop operation
// This function checks if a callback function is defined in the mission namespace and calls it with the provided parameters.
// 
// Parameters:
// _requestor: The entity requesting the para drop (e.g., a commander unit).
// _responder: The entity responding to the para drop request (e.g., the pilot).
// _paraDropGroup: The group of units being dropped.
// _phase: The current phase of the para drop operation (e.g., acknowledged, dropping, done).
// 
// Returns: None
// 
// Example usage:
// [_caller, driver _plane, _groupToBeDropped, PARA_DROP_PHASE_ACKNOWLEDGED] call fnc_callBackParaDropStatus
// 
// Note: Ensure that the callback function is set in the mission namespace before calling this function.
// 
// Example of setting a callback function:
/*
	missionNamespace setVariable [CALLBACK_PARA_DROP_STATUS, {
		params ["_requestor", "_responder", "_paraDropGroup", "_phase"];
		systemChat format ["Para drop status: %1", _phase];
	}];
*/
fnc_callBackParaDropStatus = {
	params ["_requestor", "_responder", "_paraDropGroup", "_phase"];

	private _callBack = missionNamespace getVariable [CALLBACK_PARA_DROP_STATUS, nil];
	if (! isNil "_callBack") then {
		[_requestor, _responder, _paraDropGroup, _phase] call (missionNamespace getVariable CALLBACK_PARA_DROP_STATUS);
	};
};

// Execute a para drop operation
// This function manages the entire para drop process, from acknowledging the request to dropping the troops and confirming completion.
// It handles parachute backpack assignment, waiting for the plane to reach the drop zone, and ensuring the troops land safely.

// Parameters:
// _caller: The entity requesting the para drop (e.g., a commander unit).
// _plane: The aircraft from which the troops will be dropped.
// _planeAltitude: The altitude at which the plane will fly during the drop.
// _yDroppingRadius: The radius around the drop location within which the plane must be to initiate the drop.
// _dropDropLocation: The exact location where the troops will be dropped.
// _groupToBeDropped: The group of units to be dropped.
// 
// Returns: None
// 
// Example usage:
// [_caller, _plane, 3000, 500, [1000, 2000, 0], _groupToBeDropped] call fnc_executeParaDrop
// 
// Note: Ensure that the plane is properly initialized and has enough seats for the group to be dropped before calling this function.
// 
// Example of initializing a plane:
// private _plane = [_side, _pilotType, _planeModel, _dropPosition, _initLocation, _planeSpeed, _planeGroupName] call fnc_initializePlane;
// 
// Example of loading a group into the plane:
// [_plane, _groupToBeDropped] call fnc_loadGroupToPlane;
// 
// Ensure that the group to be dropped has parachute backpacks assigned before calling this function.
// Example of assigning parachute backpacks:
// private _backPack = [_groupToBeDropped] call fnc_setParachuteBackpack;
// 
// The original backpacks can be restored after the drop using fnc_getOriginalBackPack.
// Example of restoring original backpacks:
// [_paraPlayer, _backPack] call fnc_getOriginalBackPack;
fnc_executeParaDrop = {
	params ["_caller", "_plane", "_planeAltitude", "_yDroppingRadius", "_dropDropLocation", "_groupToBeDropped"];

	// save the original backpack after swapping for a parachute backpack.
	private _backPack = [_groupToBeDropped] call fnc_setParachuteBackpack;

	// acknowledge the request for para drop.
	[_caller, driver _plane, _groupToBeDropped, PARA_DROP_PHASE_ACKNOWLEDGED] call fnc_callBackParaDropStatus;

	// wait until plane reaches drop zone
	[_plane, _dropDropLocation, _yDroppingRadius, _planeAltitude] call fnc_waitUntilReachDropzone;

	// drop troops
	[_caller, driver _plane, _groupToBeDropped, PARA_DROP_PHASE_DROPPING] call fnc_callBackParaDropStatus;
	[_groupToBeDropped, _plane, _backPack, 0.5] call fnc_ejectFromPlane;
	[_groupToBeDropped] call fnc_waitUntilGroupOnGround;
	// ejecting from plane done
	[_caller, driver _plane, _groupToBeDropped, PARA_DROP_PHASE_DONE] call fnc_callBackParaDropStatus;
};

// Save the original loadouts of a group template
// This function saves the original loadouts, ranks, and skills of each unit in the provided group.
// 
// Parameters:
// _group: The group whose loadouts are to be saved.
// 
// Returns: An array containing the original loadouts, ranks, and skills of each unit in the group.
// 
// Example usage:
// private _originalLoadouts = [_group] call fnc_saveOriginalGroupTemplates;
// 
// Note: This function is useful for creating templates of groups that can be recreated later with their original loadouts.
// 
// Example of using the saved template to create a new group:
// private _newGroup = [_side, _spawnPos, _plane, _originalLoadouts] call fnc_createGroupFromTemplate;
fnc_saveOriginalGroupTemplates = {
	params ["_group"];

	private _originalLoadouts = [];

	{
		private _type = typeOf _x;
		private _loadout = getUnitLoadout _x;
		private _rank = rank _x;
		private _skill = skill _x;

		_originalLoadouts pushBack [_type, _loadout, _rank, _skill];
	} forEach units _group;

	_originalLoadouts
};

// Create a group from a saved template and load them into the plane
// This function creates a new group on the specified side at the given spawn position using the provided group template.
// Each unit in the new group is assigned the loadout, rank, and skill from the template and is moved into the specified plane.
// 
//  Parameters:
// _side: The side (e.g., "WEST", "EAST", "GUER") for the new group.
// _spawnPos: The position where the new group will be spawned.
// _plane: The aircraft into which the new group will be loaded.
// _groupTemplate: An array containing the loadouts, ranks, and skills for each unit in the group.
// 
// Returns: The newly created group.
// 
// Example usage:
// private _newGroup = [_side, _spawnPos, _plane, _groupTemplate] call fnc_createGroupFromTemplate;
// 
// Note: Ensure that the plane has enough seats for the group to be loaded before calling this function.
fnc_createGroupFromTemplate = {
	params ["_side", "_spawnPos", "_plane", "_groupTemplate"];
	private _group = createGroup _side;
	{
		private _type = _x select 0;
		private _loadout = _x select 1;
		private _rank = _x select 2;
		private _skill = _x select 3;
		private _unit = _group createUnit [_type, _spawnPos, [], 0, "NONE"];
		_unit setUnitLoadout _loadout;
		_unit setRank _rank;
		_unit setSkill _skill;
		_unit moveInCargo _plane;
	} forEach _groupTemplate;
	_group
};

// Create a waypoint for a group with specified parameters
// This function adds a waypoint to the specified group at the given destination position.
// The waypoint is configured with the provided speed, type, formation, behaviour, and waypoint number.
// 
// Parameters:
// _group: The group to which the waypoint will be added.
// _destinationPosition: The position where the waypoint will be set.
// _wayPointSpeed: The speed setting for the waypoint (e.g., "SLOW", "NORMAL", "FAST", "FULL").
// _wayPointType: The type of waypoint (e.g., "MOVE", "SAD", "CYCLE", "LOOP").
// _wayPointFormation: The formation to be used at the waypoint (e.g., "DIAMOND", "LINE", "COLUMN").
// _wayPointBehaviour: The behaviour of the group at the waypoint (e.g., "AWARE", "SAFE", "CARELESS").
// _wayPointNumber: The index number for the waypoint (e.g., 0 for the first waypoint).
// 
// Returns: The created waypoint object.
// 
// Example usage:
// private _waypoint = [_group, _destinationPosition, _wayPointSpeed, _wayPointType, _wayPointFormation, _wayPointBehaviour, _wayPointNumber] call fnc_createWaypoint;
// 
// Note: This function is useful for dynamically setting waypoints for groups during missions.
// 
// Example of setting a waypoint:
// private _waypoint = [_group, [1000, 2000, 0], "NORMAL", "MOVE", "DIAMOND", "AWARE", 0] call fnc_createWaypoint;
// 
// The waypoint can then be modified further if needed using waypoint commands.
fnc_createWaypoint = {
	private _group = _this select 0;
	private _destinationPosition = _this select 1;
	private _wayPointSpeed = _this select 2;
	private _wayPointType = _this select 3;
	private _wayPointFormation = _this select 4;
	private _wayPointBehaviour = _this select 5;
	private _wayPointNumber = _this select 6;
	private _teamWP = _group addWaypoint [_destinationPosition, _wayPointNumber];
	_teamWP setWaypointSpeed _wayPointSpeed;
	_teamWP setWaypointType _wayPointType;
	_teamWP setWaypointFormation _wayPointFormation;
	_teamWP setWaypointBehaviour _wayPointBehaviour;

	_teamWP
};

// Swap the backpack of each unit in the group to a parachute backpack and return the original backpacks.
// This function iterates through each unit in the provided group, saves their current loadout (including backpack), and then assigns them a parachute backpack.
// 
// Parameters:
// _groupPlatoon: The group of units whose backpacks will be swapped.
// 
// Returns: An array containing the original backpacks of each unit in the group.
// 
// Example usage:
// private _originalBackpacks = [_groupPlatoon] call fnc_setParachuteBackpack;
// 
// Note: This function is useful for preparing units for a parachute drop by ensuring they have parachute backpacks.
// The original backpacks can be restored later using fnc_getOriginalBackPack.
fnc_setParachuteBackpack = {
	private _groupPlatoon = _this select 0;
	private _oldbackPack = [];
	{
		_oldbackPack pushBack [_x, getUnitLoadout _x];
		_x addBackpack "B_parachute";
	} forEach units _groupPlatoon;

	_oldbackPack
};

// Restore the original backpack for a unit from the saved backpacks.\
// This function checks the provided array of original backpacks and restores the backpack for the specified unit.
// 
// Parameters:
// _unit: The unit whose backpack will be restored.
// _backPack: An array containing the original backpacks of units, as returned by fnc_setParachuteBackpack.
// 
// Returns: None
// 
// Example usage:
// [_paraPlayer, _backPack] call fnc_getOriginalBackPack;
// 
// Note: This function should be called after the unit has landed from a parachute drop to restore their original equipment.
// 
// Example of restoring original backpacks:
// private _backPack = [_groupToBeDropped] call fnc_setParachuteBackpack;
// [_paraPlayer, _backPack] call fnc_getOriginalBackPack;
fnc_getOriginalBackPack = {
	private _unit = _this select 0;
	private _backPack = _this select 1;
	{
		if (_x select 0 == _unit) then {
			_unit setUnitLoadout (_x select 1);
		};
	} forEach _backPack;
};

// Initialize a plane with pilot and copilot, set its waypoints to the drop location and return the plane object.
// This function creates a plane on the specified side, assigns a pilot and copilot, and sets up waypoints for the plane to approach the drop zone, drop troops, and return to base.
// 
// Parameters:
// _side: The side (e.g., "WEST", "EAST", "GUER") for the plane.
// _pilotType: The type of unit to be used as the pilot and copilot.
// _planeModel: The model of the plane to be created.
// _dropPosition: The position where the troops will be dropped.
// _initLocation: The initial location where the plane will be spawned.
// _planeSpeed: The speed at which the plane will fly.
// _planeGroupName: The name to be assigned to the plane's group.
// 
// Returns: The created plane object.
// 
// Example usage:
// private _plane = [_side, _pilotType, _planeModel, _dropPosition, _initLocation, _planeSpeed, _planeGroupName] call fnc_initializePlane;
// 
// Note: Ensure that the plane is properly initialized before using it for para drop operations.
fnc_initializePlane = {
	params ["_side", "_pilotType", "_planeModel", "_dropPosition", "_initLocation", "_planeSpeed", "_planeGroupName"];

	// create a group of the plane
	private _groupPlane = createGroup _side;
	// create Airplane
	private _returnPlane = createVehicle [_planeModel, _initLocation, [], 0, "FLY"];
	// create Pilot
	private _pilot = _groupPlane createUnit [_pilotType, _initLocation, [], 0, "CARGO"];
	private _copilot = _groupPlane createUnit [_pilotType, _initLocation, [], 0, "CARGO"];
	_returnPlane setPosASL [(_initLocation select 0), (_initLocation select 1), (_initLocation select 2)];
	// move Pilot as plane driver
	_pilot moveInDriver _returnPlane;
	_copilot moveInAny _returnPlane;
	addSwitchableUnit _copilot;
	_groupPlane setGroupId [_planeGroupName];

	// change speed when almost reach drop zone
	[_returnPlane, _groupPlane, _initLocation, _dropPosition, _planeSpeed] spawn fnc_setPlaneWayPoints;
	_returnPlane
};

// Uninitialize the plane by deleting it and its crew.
// This function deletes the specified plane and all its crew members, effectively cleaning up the resources used by the plane.
// 
// Parameters:
// _plane: The plane object to be deleted.
// 
// Returns: None
// 
// Example usage:
// [_plane] call fnc_uninitializePlane;
// 
// Note: This function should be called after the para drop operation is complete and the plane is no longer needed.
fnc_uninitializePlane = {
	private _plane = _this select 0;
	// Delete plane and pilots
	{
		deleteVehicle _x;
	} forEach crew _plane;
	deleteVehicle _plane;
};

// set the waypoints for the plane to approach the drop zone, drop troops, and return to base.
// This function configures the waypoints for the specified plane and its group to fly to the drop zone, drop troops, and then return to its initial location.
// 
// Parameters:
// _plane: The plane object whose waypoints will be set.
// _group: The group associated with the plane.
// _initLocation: The initial location where the plane was spawned.
// _dropPosition: The position where the troops will be dropped.
// _planeSpeed: The speed at which the plane will fly.
// 
// Returns: None
// 
// Example usage:
// [_plane, _group, _initLocation, _dropPosition, _planeSpeed] call fnc_setPlaneWayPoints;
// 
// Note: This function is typically called during the initialization of the plane for a para drop operation
fnc_setPlaneWayPoints = {
	private _plane = _this select 0;
	private _group = _this select 1;
	private _initLocation = _this select 2;
	private _dropPosition = _this select 3;
	private _planeSpeed = _this select 4;
	private _distanceBeforeAndAfterDroplocation = 3000;
	private _planeAltitude = _initLocation select 2;

	// initialize plane in the right altitude
	_plane flyInHeightASL [(_initLocation select 2), (_initLocation select 2), (_initLocation select 2)];
	_plane setVelocity [(sin (direction _plane) * _planeSpeed), ( cos (direction _plane) * _planeSpeed), 0];

	// set plane waypoint yDistance ahead of the dropzone position.
	_planeWPPos = [ _dropPosition select 0, (_dropPosition select 1) - _distanceBeforeAndAfterDroplocation, _planeAltitude];
	[_group, _planeWPPos, "LIMITED", "MOVE", "DIAMOND", "CARELESS", 0] call fnc_createWaypoint;

	// set plane waypoint at exact location of the drop zone.
	_planeWPPos = [ _dropPosition select 0, (_dropPosition select 1), _dropPosition select 2];
	[_group, _planeWPPos, "LIMITED", "MOVE", "DIAMOND", "CARELESS", 1] call fnc_createWaypoint;

	// set plane waypoint at beyond the drop location before going RTB.
	_planeWPPos = [ _dropPosition select 0, (_dropPosition select 1) + _distanceBeforeAndAfterDroplocation, _dropPosition select 2];
	[_group, _planeWPPos, "LIMITED", "MOVE", "DIAMOND", "CARELESS", 2] call fnc_createWaypoint;

	// Change plane course back to the starting location. RTB
	_planeWPPos = [_group, _initLocation, "FULL", "MOVE", "DIAMOND", "CARELESS", 3] call fnc_createWaypoint;

	waitUntil {
		sleep 1;
		(_initLocation distance2D (getPos _plane)) <= 100
	};
	[_plane] call fnc_uninitializePlane;
};

// Wait until the plane reaches the drop zone within a specified radius.
// This function pauses execution until the specified plane is within a certain distance of the drop position.
// 
// Parameters:
// _plane: The plane object to be monitored.
// _dropPosition: The target drop position.
// _droppingRadius: The radius within which the plane must be to consider it has reached the drop zone.
// 
// Returns: None
// 
// Example usage:
// [_plane, _dropPosition, _droppingRadius] call fnc_waitUntilReachDropzone;
// 
// Note: This function is typically used to ensure that the plane is in the correct position before initiating the troop drop.
fnc_waitUntilReachDropzone = {
	private _plane = _this select 0;
	private _dropPosition = _this select 1;
	private _droppingRadius = _this select 2;

	waitUntil {
		sleep 1;
		(_dropPosition distance2D (getPos _plane)) <= _droppingRadius
	};
};

// reload the original backpack for a paratrooper after they hit the ground.
// This function waits until the specified paratrooper touches the ground, then restores their original backpack and allows them to take damage again.
// 
// Parameters:
// _paraPlayer: The paratrooper unit whose backpack will be restored.
// _backPack: An array containing the original backpacks of units, as returned by fnc_setParachuteBackpack.
// Returns: None
// 
// Example usage:
// [_paraPlayer, _backPack] call func_reloadInventoryWhenHitGround;
// 
// Note: This function should be called after the paratrooper has been ejected from the plane and is expected to land safely.
func_reloadInventoryWhenHitGround = {
	private _paraPlayer = _this select 0;
	private _backPack = _this select 1;

	waitUntil {
		sleep 1;
		isTouchingGround _paraPlayer
	};
	unassignVehicle _paraPlayer;
	[_paraPlayer, _backPack] call fnc_getOriginalBackPack;
	sleep 5;
	_paraPlayer allowDamage true;
};

// Eject paratroopers from the plane at specified intervals.
// This function iterates through each unit in the specified group, makes them exit the plane, and starts the process of restoring their original backpacks once they land.
// 
// Parameters:
// _groupPlatoon: The group of paratroopers to be ejected.
// _plane: The plane from which the paratroopers will be ejected.
// _backPack: An array containing the original backpacks of units, as returned by fnc_setParachuteBackpack.
// _jumpIntervalTime: The time interval (in seconds) between each paratrooper's ejection.
// 
// Returns: None
// Example usage:
// [_groupPlatoon, _plane, _backPack, _jumpIntervalTime] call fnc_ejectFromPlane;
// 
// Note: This function should be called when the plane is in the correct position for the para drop.
fnc_ejectFromPlane = {
	private _groupPlatoon = _this select 0;
	private _plane = _this select 1;
	private _backPack = _this select 2;
	private _jumpIntervalTime = _this select 3;
	private _groupArray = units _groupPlatoon;

	{
		_x allowDamage false;
		unassignVehicle _x;
		moveOut _x;
		[_x, _backPack] spawn func_reloadInventoryWhenHitGround;
		sleep _jumpIntervalTime;
	} forEach _groupArray;
};

// Wait until a specified percentage of the group is on the ground.
// This function continuously checks the altitude of each unit in the group and waits until a certain percentage of them are below a specified height, indicating they have landed.
// 
// Parameters:
// _grp: The group of units to be monitored.
// 
// Returns: None
// 
// Example usage:
// [_group] call fnc_waitUntilGroupOnGround;
// 
// Note: This function is useful for ensuring that a majority of the group has safely landed before proceeding with further actions.
// The function considers a unit to be on the ground if its altitude is less than 3 meters above sea level.
fnc_waitUntilGroupOnGround = {
	params ["_grp"];
	waitUntil {
		sleep 1;
		private _onGround = {
			alive _x && (getPosATL _x select 2) < 3
		} count units _grp;
		_onGround >= (count units _grp * 0.7)
	};
};

// load a group into the plane if there are enough free seats.
// This function checks if the specified plane has enough free seats to accommodate the entire group. if there are enough seats, it moves each unit in the group into the plane.
// 
// Parameters:
// _plane: The plane into which the group will be loaded.
// _group: The group of units to be loaded into the plane.
// 
// Returns: true if the group was successfully loaded into the plane, false otherwise.
// 
// Example usage:
// [_plane, _group] call fnc_loadGroupToPlane;
// 
// Note: Ensure that the plane is alive and has enough free seats before calling this function.
fnc_loadGroupToPlane = {
	params ["_plane", "_group"];
	if (isNull _plane || isNull _group || !alive _plane) exitWith {
		false
	};

	private _freeSeatCount = {
		isNull (_x select 0)
	} count (fullCrew [_plane, "cargo", true]);

	private _groupCount = count (units _group);

	if (_groupCount > _freeSeatCount) exitWith {
		false
	};

	{
		_x moveInCargo _plane;
	} forEach (units _group);

	true
};