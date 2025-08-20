#define CALLBACK_PARA_DROP_STATUS "Callback_ParaDrop"
#define PARA_DROP_PHASE_ACKNOWLEDGED "Acknowledged"
#define PARA_DROP_PHASE_DROPPING "Dropping"
#define PARA_DROP_PHASE_DONE "Done"

fnc_callBackParaDropStatus = {
	params ["_requestor", "_responder", "_paraDropGroup", "_phase"];

	private _callBack = missionNamespace getVariable [CALLBACK_PARA_DROP_STATUS, nil];
	if (! isNil "_callBack") then {
		[_requestor, _responder, _paraDropGroup, _phase] call (missionNamespace getVariable CALLBACK_PARA_DROP_STATUS);
	};
};

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

	// ejecting from plane done
	[_caller, driver _plane, _groupToBeDropped, PARA_DROP_PHASE_DONE] call fnc_callBackParaDropStatus;

	[_groupToBeDropped] call fnc_waitUntilGroupOnGround;
};

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

fnc_setParachuteBackpack = {
	private _groupPlatoon = _this select 0;
	private _oldbackPack = [];
	{
		_oldbackPack pushBack [_x, getUnitLoadout _x];
		_x addBackpack "B_parachute";
	} forEach units _groupPlatoon;

	_oldbackPack
};

fnc_getOriginalBackPack = {
	private _unit = _this select 0;
	private _backPack = _this select 1;
	{
		if (_x select 0 == _unit) then {
			_unit setUnitLoadout (_x select 1);
		};
	} forEach _backPack;
};

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

fnc_uninitializePlane = {
	private _plane = _this select 0;
	// Delete plane and pilots
	{
		deleteVehicle _x;
	} forEach crew _plane;
	deleteVehicle _plane;
};

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
	[_group, _planeWPPos, "FULL", "MOVE", "DIAMOND", "CARELESS", 0] call fnc_createWaypoint;

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

fnc_waitUntilReachDropzone = {
	private _plane = _this select 0;
	private _dropPosition = _this select 1;
	private _droppingRadius = _this select 2;

	waitUntil {
		sleep 1;
		(_dropPosition distance2D (getPos _plane)) <= _droppingRadius
	};
};

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