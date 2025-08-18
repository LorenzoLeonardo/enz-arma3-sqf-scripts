params[
	"_caller",
	"_planeAltitude",
	"_planeSpeed",
	"_yDistance",
	"_yDroppingRadius",
	"_dropZoneMarkerName",
	"_groupTemplate"
];

fnc_executeParaDrop = {
	params ["_caller", "_plane", "_planeAltitude", "_yDroppingRadius", "_paraDropMarkerName", "_groupToBeDropped"];

	private _groupCaller = group _caller;
	private _callerPosition = getMarkerPos _paraDropMarkerName;
	private _groupBeforeJoin = units _groupToBeDropped;
	private _groupCallerID = groupId _groupCaller;
	hint format ["Requesting Reinforcements: %1", groupId _groupCaller];
	((crew _plane) select 0) sideRadio "SupportOnWayStandBy";
	_groupToBeDropped copyWaypoints _groupCaller;

	// Wait until plane reaches drop zone
	[_plane, _callerPosition, _yDroppingRadius, _planeAltitude] call fnc_waitUntilReachDropzone;
	private _backPack = [_groupToBeDropped] call fnc_setParachuteBackpack;

	// drop troops
	((crew _plane) select 0) sideRadio "RadioAirbaseDropPackage";
	[_groupToBeDropped, _plane, _backPack, 0.5] call fnc_ejectFromPlane;

	// join or rename group
	if (({
		alive _x
	} count units _groupCaller) == 0) then {
		_groupToBeDropped setGroupId [_groupCallerID];
	} else {
		(units _groupToBeDropped) join _groupCaller;
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
			case "echo": {
				(leader _groupCaller) sideRadio "WeLinkedUpWithTheReinforcementsThanksForTheSupportEcho";
			};
			default {
				(leader _groupCaller) sideRadio "Reinforcements have linked up.";
			};
		};
	};

	[_groupToBeDropped] call fnc_waitUntilGroupOnGround;
	deleteMarkerLocal _paraDropMarkerName;
};

fnc_saveOriginalGroupTemplates = {
	params ["_group"];

	private _originalLoadouts = [];

	{
		private _type = typeOf _x;
		private _loadout = getUnitLoadout _x;
		private _rank = rank _x;

		_originalLoadouts pushBack [_type, _loadout, _rank];
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
		private _unit = _group createUnit [_type, _spawnPos, [], 0, "NONE"];
		_unit setUnitLoadout _loadout;
		_unit setRank _rank;
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

fnc_setSupportMarkerAndRadio = {
	params ["_unit", "_grpName"];
	private _markerName = format ["paraDropMarker_%1", diag_tickTime];
	private _markerText = format ["Requesting Paradrop Support (%1)", _grpName];
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
	_markerName
};

fnc_getAssignedPlane = {
	private _teamName = _this select 0;
	private _planeAssigned="";
	switch (toLower _teamName) do {
		case "alpha": {
			_planeAssigned = "November 1";
		};
		case "bravo": {
			_planeAssigned = "November 2";
		};
		case "charlie": {
			_planeAssigned = "November 3";
		};
		case "delta": {
			_planeAssigned = "November 4";
		};
		case "echo": {
			_planeAssigned = "November 5";
		};
		default {
			hint format["%1 is not a valid squad name. Please use Alpha, Bravo, Charlie, Delta", _teamName];
		};
	};
	_planeAssigned
};

fnc_initializePlane = {
	private _planeModel = _this select 0;
	private _dropPosition = _this select 1;
	private _initLocation = _this select 2;
	private _planeSpeed = _this select 3;
	private _planeGroupName = _this select 4;

	// create a group of the plane
	private _groupC130J = createGroup west;
	// create C130
	private _returnPlane = createVehicle [_planeModel, _initLocation, [], 0, "FLY"];
	// create Pilot
	private _pilot = _groupC130J createUnit ["CUP_B_US_Pilot", _initLocation, [], 0, "CARGO"];
	private _copilot = _groupC130J createUnit ["CUP_B_US_Pilot", _initLocation, [], 0, "CARGO"];
	_returnPlane setPosASL [(_initLocation select 0), (_initLocation select 1), (_initLocation select 2)];
	// move Pilot as plane driver
	_pilot moveInDriver _returnPlane;// move pilot as driver of the plane
	_copilot moveInAny _returnPlane;
	addSwitchableUnit _copilot;
	_groupC130J setGroupId [_planeGroupName];

	// change speed when almost reach drop zone
	[_returnPlane, _groupC130J, _initLocation, _dropPosition, _planeSpeed] spawn fnc_setPlaneWayPoints;
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