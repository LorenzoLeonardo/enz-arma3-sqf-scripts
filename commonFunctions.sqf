/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will create dynamic way points for your units/groups
	 *
	 * Arguments:
	 * 0: _group this is a group or unit object <OBJECT>
	 * 1: _destinationPosition is a [x, y, z] coordinates of the destination <ARRAY>
	 * 2: _wayPointSpeed this could be "FULL" "LIMITED" "NORMAL" <STRING>
	 * 3: _wayPointType this is a waypont type "MOVE" "SAD" <STRING>
	 * 4: _wayPointFormation this is a waypoint formation "LINE "DIAMOND" <STRING>
	 * 5: _wayPointBehaviour this is a behaviour of the units "AWARE" "CARELESS" "DANGER" <STRING>
	 * 6: _wayPointNumber this is the waypoint number, you can set from 0 to n waypoints <INTEGER>
	 * Return Value:
	 * The return value Array format Waypoint - [group, index]
	 *
	 * Example:
	 * _wayPoint = [_group, [0, 0, 0], "LIMITED", "MOVE", "DIAMOND", "AWARE", 0] call create_waypoint;
	 *
	 * Public: [Yes/No]
 */
create_waypoint =
{
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

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will delete the plane and its crew members.
	 *
	 * Arguments:
	 * 0: _plane is the plane's object <OBJECT>
	 * Return Value:
	 * The return value None
	 *
	 * Example:
	 * [_plane] call uninitialize_plane;
	 *
	 * Public: [Yes/No]
 */
uninitialize_plane =
{
	private _plane = _this select 0;
	// Delete plane and pilots
	{
		deleteVehicle _x;
	} forEach crew _plane;
	deleteVehicle _plane;
};

set_plane_way_points =
{
	private _plane = _this select 0;
	private _group = _this select 1;
	private _initLocation = _this select 2;
	private _dropPosition = _this select 3;
	private _planeSpeed = _this select 4;

	private _slowDownPlaneAtDistance = 3000;
	private _planeAltitude = _initLocation select 2;
	// initialize plane in the right altitude
	_plane flyInHeightASL [(_initLocation select 2), (_initLocation select 2), (_initLocation select 2)];
	_plane setVelocity [(sin (direction _plane) * _planeSpeed), ( cos (direction _plane) * _planeSpeed), 0];
	// set plane waypoint yDistance ahead of the dropzone position.
	_planeWPPos = [ _dropPosition select 0, (_dropPosition select 1) - _slowDownPlaneAtDistance, _planeAltitude];
	[_group, _planeWPPos, "FULL", "MOVE", "DIAMOND", "CARELESS", 0] call create_waypoint;
	// [_plane, _destinationPos, _distanceFromDestination] call wait_until_reach_dropzone;

	_planeWPPos = [ _dropPosition select 0, (_dropPosition select 1) + 1000, _dropPosition select 2];
	[_group, _planeWPPos, "LIMITED", "MOVE", "DIAMOND", "CARELESS", 1] call create_waypoint;
	// _plane setVelocity [(sin (direction _plane) * _planeSpeed), ( cos (direction _plane) * _planeSpeed), 0];

	// Change plane course back to the starting location
	_planeWPPos = [_group, _initLocation, "FULL", "MOVE", "DIAMOND", "CARELESS", 2] call create_waypoint;

	waitUntil {
		sleep 1;
		_distance = sqrt(abs((_initLocation select 1) - (getPos _plane select 1))^2 + abs ((_initLocation select 0) - (getPos _plane select 0))^2);
		_distance <= 100
	};
	[_plane] call uninitialize_plane;
};
/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will initialize the plane to use for paradrop.
	 *
	 * Arguments:
	 * 0: _planeModel mode of the plane. Example: "CUP_B_C47_USA" <STRING>
	 * 1: _dropPosition is a [x, y, z] coordinates of the paradrop destination <ARRAY>
	 * 2: _initLocation is a [x, y, z] coordinates of the plane's initial position <ARRAY>
	 * 3: _planeSpeed is the speed of the plan <INTEGER>
	 * 4: _planeGroupName is the name of the plane group <STRING>
	 * Return Value:
	 * The return value Object
	 *
	 * Example:
	 * _plane = ["CUP_B_C47_USA", [0, 0, 0], [0, 0, 0], 100, "November"] call initialize_plane;
	 *
	 * Public: [Yes/No]
 */
initialize_plane =
{
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
	[_returnPlane, _groupC130J, _initLocation, _dropPosition, _planeSpeed] spawn set_plane_way_points;
	_returnPlane
};

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will initialize the group/troops inside the plane for paradrop.
	 *
	 * Arguments:
	 * 0: _groupName is a group or platoon name assignment <OBJECT>
	 * 1: _initLocation is a [x, y, z] initial location of the group/unit <ARRAY>
	 * 2: _plane is a plane object where the group/platoon will be loaded <OBJECT>
	 * Return Value:
	 * The return value group object
	 *
	 * Example:
	 * _groupPlatoon = [_groupName, _initLocation, _plane] call initialize_group_to_plane;
	 *
	 * Public: [Yes/No]
 */
initialize_group_to_plane =
{
	private _groupName = _this select 0;
	private _initLocation = _this select 1;
	private _plane = _this select 2;
	private _groupPlatoon = createGroup west;
	private _initializeMen = "this moveInCargo _plane;
	";

	_groupPlatoon setGroupId [_groupName];
	"CUP_B_US_Soldier_TL_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "LIEUTENANT"];
	"CUP_B_US_Soldier_Marksman_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "SERGEANT"];
	"CUP_B_US_Soldier_MG_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "SERGEANT"];
	"CUP_B_US_Soldier_GL_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_US_Soldier_GL_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_US_Soldier_AT_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_US_Soldier_AT_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_US_Soldier_AT_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_US_Soldier_AT_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_US_Medic_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_US_Soldier_Backpack_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_US_Soldier_Backpack_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_US_Soldier_Backpack_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_US_Medic_OCP" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];

	addSwitchableUnit ((units _groupPlatoon) select ((count (units _groupPlatoon)) - 1));
	_groupPlatoon
};

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will initialize the player to join the group for paradrop missions.
	 *
	 * Arguments:
	 * 0: _plane is a plane object where the group/platoon will be loaded <OBJECT>
	 * 1: _groupPlatoon is a group where player will join. <OBJECT>
	 * Return Value:
	 * The return value none
	 *
	 * Example:
	 * [_plane, _groupPlatoon] call initialize_player;
	 *
	 * Public: [Yes/No]
 */
initialize_player =
{
	private _plane = _this select 0;
	private _groupPlatoon = _this select 1;

	player moveInCargo _plane;
	[player] joinSilent _groupPlatoon;
};

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will give each units of the group with parachute bag and save its
	 * default bag so that we could switch it back later after paradrop.
	 *
	 * Arguments:
	 * 0: _groupPlatoon is a group object where we add a parachute bag. <OBJECT>
	 * Return Value:
	 * The return value ARRAY of unit object and its corresponding loadout to save
	 * so that we could switch back later after using the parachute.
	 *
	 * Example:
	 * _defaultBackpacks = [_groupPlatoon] call set_parachute_backpack;
	 *
	 * Public: [Yes/No]
 */
set_parachute_backpack =
{
	private _groupPlatoon = _this select 0;
	private _oldbackPack = [];
	{
		_oldbackPack pushBack [_x, getUnitLoadout _x];
		_x addBackpack "B_parachute";
	} forEach units _groupPlatoon;

	_oldbackPack
};

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will retrieve the default back pack of the units after paradrop.
	 *
	 * Arguments:
	 * 0: _unit is a unit of the group to be given by their default back pack. <OBJECT>
	 * 1: _backPack is an array of units and corresponding backpack return by set_parachute_backpack. <ARRAY>
	 * Return Value:
	 * The return value None.
	 *
	 * Example:
	 * _defaultBackpacks = [_groupPlatoon] call set_parachute_backpack;
	 *
	 * Public: [Yes/No]
 */
get_backpack =
{
	private _unit = _this select 0;
	private _backPack = _this select 1;
	{
		if (_x select 0 == _unit) then {
			_unit setUnitLoadout (_x select 1);
		};
	} forEach _backPack;
};

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will reload back the original backpack of the unit after paradrop and hitting the ground.
	 *
	 * Arguments:
	 * 0: _paraPlayer is a unit of the group to be given by their default back pack. <OBJECT>
	 * 1: _backPack is an array of units and corresponding backpack return by set_parachute_backpack. <ARRAY>
	 * Return Value:
	 * The return value None.
	 *
	 * Example:
	 * [_paraPlayer, _backPack] spawn reload_inventory_when_hit_Ground;
	 *
	 * Public: [Yes/No]
 */
reload_inventory_when_hit_Ground =
{
	private _paraPlayer = _this select 0;
	private _backPack = _this select 1;

	waitUntil {
		sleep 1;
		isTouchingGround _paraPlayer
	};
	unassignVehicle _paraPlayer;
	[_paraPlayer, _backPack] call get_backpack;
	sleep 5;
	_paraPlayer allowDamage true;
};

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will eject the group/platoon from the assigned plane.
	 *
	 * Arguments:
	 * 0: _groupPlatoon is a unit of the group to be given by their default back pack. <OBJECT>
	 * 1: _plane is a plane object where the group/platoon will be ejected <OBJECT>
	 * 2: _backPack is an array of units and corresponding backpack return by set_parachute_backpack. <ARRAY>
	 * 3: _jumpIntervalTime is the delay in seconds between each unit when jumping from the plane. <FLOAT>
	 * Return Value:
	 * The return value None.
	 *
	 * Example:
	 * [_groupPlatoon, _plane, _defaultBackpacks] call eject_from_plane;
	 *
	 * Public: [Yes/No]
 */
eject_from_plane =
{
	private _groupPlatoon = _this select 0;
	private _plane = _this select 1;
	private _backPack = _this select 2;
	private _jumpIntervalTime = _this select 3;
	private _groupArray = units _groupPlatoon;

	{
		_x allowDamage false;
		unassignVehicle _x;
		moveOut _x;
		[_x, _backPack] spawn reload_inventory_when_hit_Ground;
		sleep _jumpIntervalTime;
	} forEach _groupArray;
};

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will be used when naming for specific plane name of a specific group that needs
	 * reinforcements.
	 *
	 * Arguments:
	 * 0: _teamName is a team name of the group that need support/reinforcements <STRING>
	 * Return Value:
	 * The return value <STRING> name of the plane group.
	 *
	 * Example:
	 * ["ALPHA"] call get_assigned_plane;
	 *
	 * Public: [Yes/No]
 */
get_assigned_plane =
{
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
		default {
			hint format["%1 is not a valid squad name. Please use Alpha, Bravo, Charlie, Delta", _teamName];
		};
	};
	_planeAssigned
};

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will wait before executing eject_from_plane function to eject the units
	 * at the target dropzone location.
	 *
	 * Arguments:
	 * 0: _plane is a plane object where the group/platoon will be ejected <OBJECT>
	 * 1: _dropPosition is a [x, y, z] coordinates of the marker where the units will be paradropped <ARRAY>
	 * 2: _droppingRadius is a distance between _dropPosition center to the horizontal position of the plane. <NUMBER>
	 *
	 * Return Value:
	 * The return value <STRING> name of the plane group.
	 *
	 * Example:
	 * [_plane, [0, 0, 0], 300] call wait_until_reach_dropzone;
	 *
	 * Public: [Yes/No]
 */
wait_until_reach_dropzone =
{
	private _plane = _this select 0;
	private _dropPosition = _this select 1;
	private _droppingRadius = _this select 2;

	waitUntil {
		sleep 1;
		_distance = sqrt(abs((_dropPosition select 1) - (getPos _plane select 1))^2 + abs ((_dropPosition select 0) - (getPos _plane select 0))^2);
		_distance <= _droppingRadius
	};
};

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will help the AI artillery/mortar fire at the specified destination.
	
	 *
	 * Arguments:
	 * 0: _gun is a unit/mortar/artillery object <OBJECT>
	 * 1: _targetPos is a marker target position in [x, y, z] cooridnates <ARRAY>
	 * 2: _ammoIndex is a index of the muzzle used <INTEGER>
	 * 3: _rounds is the number of rounds per call <INTEGER>
	 *
	 * Return Value:
	 * The return value None
	 *
	 * Example:
	 * [_gun, [0, 0, 0], 0, 10] call fire_artillery;
	 *
	 * Public: [Yes/No]
 */
fire_artillery =
{
	private _gun = _this select 0;
	private _targetPos = _this select 1;
	private _ammoIndex = _this select 2;
	private _rounds = _this select 3;

	if (alive _gun) then {
		private _ammo = getArtilleryAmmo [_gun] select _ammoIndex;
		_gun doArtilleryFire[ _targetPos, _ammo, _rounds];
		_gun setVehicleAmmo 1;
	};
};

/*
	 * Author: Lorenzo Leonardo
	 * Email: enzotechcomputersolutions@gmail.com
	 * This will check if artillery target is in range.
	
	 *
	 * Arguments:
	 * 0: _group is a group of mortar/artillery object <OBJECT>
	 * 1: _targetPos is a marker target position in [x, y, z] cooridnates <ARRAY>
	 * 2: _ammoIndex is a index of the muzzle used <INTEGER>
	*
	 * Return Value:
	 * The return value true/false if can hit the target or not
	 *
	 * Example:
	 * [group gun, [0, 0, 0], 0, 10] call is_artillery_target_in_range;
	 *
	 * Public: [Yes/No]
 */
is_artillery_target_in_range =
{
	private _group = _this select 0;
	private _targetPos = _this select 1;
	private _ammoIndex = _this select 2;
	private _isInRange = true;
	private _maxArtilleryRange = 12000;
	private _minArtilleryRange = 500;
	{
		if ((leader _group) != _x) then {
			private _gun = vehicle _x;
			private _thisGunPos = getPos _gun;
			private _distance = sqrt(abs((_targetPos select 0) - (_thisGunPos select 0))^2 +
			abs((_targetPos select 1) - (_thisGunPos select 1))^2);
			if ((_maxArtilleryRange < _distance) || (_minArtilleryRange > _distance)) then {
				_isInRange = false;
				break;
			};
		}
	} forEach units _group;

	_isInRange
};

is_artillery_available =
{
	private _group = _this select 0;
	private _isReady = true;

	{
		if ((unitReady _x) == false) then {
			_isReady = false;
			break;
		};
	} forEach units _group;

	_isReady
};

call_artillery_fire_mission =
{
	private _caller = _this select 0;
	private _group = _this select 1;
	private _pos = _this select 2;
	private _ammoIndex = _this select 3;
	private _callerTexMarker = str format["Requesting Artillery Fire Mission: %1", groupId (group _caller)];
	private _callerMarker = createMarkerLocal[_callerTexMarker, _pos];
	_callerMarker setMarkerSizeLocal[1, 1];
	_callerMarker setMarkerShapeLocal "ICON";
	_callerMarker setMarkerTypeLocal "mil_destroy";
	_callerMarker setMarkerDirLocal 45;
	_callerMarker setMarkerTextLocal _callerTexMarker;
	_callerMarker setMarkerColorLocal "ColorBlue";
	_caller sideRadio "RequestingFireSupportAtTheTargetLocationWilliePeteInEffectHowCopyQ";
	hint _callerTexMarker;
	private _theLeader = leader _group;
	private _rounds = 10;
	private _fireInterval = 1;
	private _isInRange = [_group, _pos, _ammoIndex] call is_artillery_target_in_range;
	private _isReady = true;
	private _ammoIndex = 0;

	_isReady = [_group] call is_artillery_available;

	if (_isReady) then {
		if (_isInRange == true) then {
			[west, "Base"] sideRadio "WeCopyYouLoudAndClear";
			sleep 1;
			[west, "Base"] sideRadio "FiringAtTargetLocation";
			{
				if (_theLeader != _x) then {
					[vehicle _x, _pos, _ammoIndex, _rounds] call fire_artillery;
				};
				sleep _fireInterval;
			} forEach units _group;
			{
				waitUntil {
					sleep 1;
					unitReady _x;
				};
			} forEach units _group;
			[west, "Base"] sideRadio "RoundsComplete";
		} else {
			[west, "Base"] sideRadio "CannotExecuteThatsOutsideOurFiringEnvelope";
		};
	} else {
		[west, "Base"] sideRadio "BeAdvisedArtilleryIsUnavailableAtThisTimeOut";
	};
	deleteMarkerLocal _callerMarker;
};

start_monitoring_mission_status =
{
	private _caseoption = _this select 0;
	[_caseoption] spawn {
		params ["_caseoption"];
		switch (_caseoption) do	{
			case "lose1": {
				waitUntil {
					sleep 10;
					({
						(side _x) == west
					} count allUnits) <= 1
				};
				["lose1", false, true] call BIS_fnc_endMission;
			};
			case "lose2": {
				waitUntil {
					sleep 10;
					(alive player) == false
				};
				["lose2", false, true] call BIS_fnc_endMission;
			};
			case "end1": {
				waitUntil {
					sleep 10;
					({
						(side _x) == east
					} count allUnits) == 0
				};
				(leader (group player)) sideRadio "RadioGroundToPapaBearVictory";
				sleep 10;
				[west, "Base"] sideRadio "RadioPapaBearVictory";
				sleep 10;
				["end1", false, true] call BIS_fnc_endMission;
			};
			default {
				hint "default"
			};
		};
	};
};

start_monitoring_killed_units =
{
	{
		_x setSkill 1;
		_x addEventHandler ["Killed", {
			_killed = _this select 0;
			_killer = _this select 1;
			systemChat format["(%1) %2 %3 ======> (%4) %5 %6", side (group _killer), rank _killer, name _killer, side (group _killed), rank _killed, name _killed];
			[_killed] spawn {
				sleep 900;
				deleteVehicle (_this select 0);
			};
		}];
	} forEach allUnits;
};

start_monitoring_killed_units_group =
{
	private _group = _this select 0;
	{
		_x setSkill 1;
		_x addEventHandler ["Killed", {
			_killed = _this select 0;
			_killer = _this select 1;
			systemChat format["(%1) %2 %3 ======> (%4) %5 %6", side (group _killer), rank _killer, name _killer, side (group _killed), rank _killed, name _killed];
			[_killed] spawn {
				sleep 900;
				deleteVehicle (_this select 0);
			};
		}];
	} forEach units _group;
};

turn_off_city_lights=
{
	private _types = ["Lamps_Base_F",
		"Land_LampAirport_F",
		"Land_LampSolar_F",
		"Land_LampStreet_F",
		"Land_LampStreet_small_F",
		"PowerLines_base_F",
		"Land_LampDecor_F",
		"Land_LampHalogen_F",
		"Land_LampHarbour_F",
		"Land_LampShabby_F",
		"Land_PowerPoleWooden_L_F",
		"Land_NavigLight",
		"Land_runway_edgelight",
		"Land_runway_edgelight_blue_F",
		"Land_Flush_Light_green_F",
		"Land_Flush_Light_red_F",
		"Land_Flush_Light_yellow_F",
		"Land_Runway_PAPI",
		"Land_Runway_PAPI_2",
		"Land_Runway_PAPI_3",
		"Land_Runway_PAPI_4",
		"Land_fs_roof_F",
	"Land_fs_sign_F"];

	private _onoff = 0.95;
	private _markerPos = getMarkerPos (_this select 0);
	private _radiusFromMarker = _this select 1;

	for [{
		_i=0
	}, {
		_i < (count _types)
	}, {
		_i=_i+1
	}] do
	{
		private _lamps = _markerPos nearObjects [_types select _i, _radiusFromMarker];
		{
			_x setDamage _onoff;
		} forEach _lamps;
	}
};

attach_unlimited_fire=
{
	private _vehicle = _this select 0;

	waitUntil {
		sleep 60;
		!(alive _vehicle)
	};

	_smoker = "test_EmptyObjectForFireBig" createVehicle position _vehicle;
	_smoker attachTo [_vehicle, [0, 1.5, 0]];
};

initialize_landing_craft =
{
	// CUP_B_LCU1600_USMC
	private _vehicleModel = _this select 0;
	private _initLocation = _this select 1;
	private _dropPosition = _this select 2;
	private _craftSpeed = _this select 3;
	private _craftGroupName = _this select 4;
	// create a group of the boat
	private _groupLandingCraft = createGroup west;
	// create C130
	private _returnLandingCraft = createVehicle [_vehicleModel, _initLocation, [], 0, "CARGO"];
	// create Pilot
	private _driver = _groupLandingCraft createUnit ["CUP_B_USMC_Crew", _initLocation, [], 0, "CARGO"];
	_returnLandingCraft setPosASL [(_initLocation select 0), (_initLocation select 1), (_initLocation select 2)];
	// move crew as boat driver
	_driver moveInDriver _returnLandingCraft;// move pilot as driver of the plane

	_groupLandingCraft setGroupId [_craftGroupName];

	// _returnLandingCraft setVelocity [(sin (direction _returnLandingCraft) * _craftSpeed), ( cos (direction _returnLandingCraft) * _craftSpeed), 0];

	[_groupLandingCraft, _dropPosition, "FULL", "TR UNLOAD", "DIAMOND", "AWARE", 0] call create_waypoint;

	_returnLandingCraft
};

initialize_group_to_landing_craft =
{
	private _groupName = _this select 0;
	private _initLocation = _this select 1;
	private _boat = _this select 2;
	private _groupPlatoon = createGroup west;
	private _initializeMen = "this moveInCargo _boat;
	";

	_groupPlatoon setGroupId [_groupName];
	"CUP_B_USMC_Officer_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "MAJOR"];
	// "CUP_B_USMC_Soldier_TL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "LIEUTENANT"];
	// "CUP_B_USMC_Soldier_TL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "LIEUTENANT"];
	"CUP_B_USMC_Soldier_TL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "LIEUTENANT"];
	// "CUP_B_USMC_Soldier_SL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "SERGEANT"];
	// "CUP_B_USMC_Soldier_SL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "SERGEANT"];
	"CUP_B_USMC_Soldier_SL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "SERGEANT"];
	"CUP_B_USMC_Soldier_MG_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Soldier_MG_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Soldier_MG_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	// "CUP_B_USMC_Soldier_MG_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	// "CUP_B_USMC_Soldier_MG_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Soldier_GL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	// "CUP_B_USMC_Soldier_GL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	// "CUP_B_USMC_Soldier_GL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	// "CUP_B_USMC_Soldier_GL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	// "CUP_B_USMC_Soldier_GL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	// "CUP_B_USMC_Soldier_GL_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	// "CUP_B_USMC_Medic_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	// "CUP_B_USMC_Medic_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Medic_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Medic_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "CORPORAL"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	"CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	"CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	"CUP_B_USMC_Soldier_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];
	// "CUP_B_USMC_Soldier_AT_des" createUnit [_initLocation, _groupPlatoon, _initializeMen, 1, "PRIVATE"];

	addSwitchableUnit ((units _groupPlatoon) select ((count (units _groupPlatoon)) - 1));
	_groupPlatoon
};

get_assigned_landing_craft =
{
	private _teamName = _this select 0;
	private _craftAssigned="";
	switch (_teamName) do {
		case "Alpha": {
			_craftAssigned = "Golf 1";
		};
		case "Bravo": {
			_craftAssigned = "Golf 2";
		};
		case "Charlie": {
			_craftAssigned = "Golf 3";
		};
		case "Delta": {
			_craftAssigned = "Golf 4";
		};
		default {
			hint format["%1 is not a valid squad name. Please use Alpha, Bravo, Charlie, Delta", _teamName];
		};
	};
	_craftAssigned
};

monitor_group_status =
{
	private _group = _this select 0;
	private _groupID = groupId _group;
	waitUntil {
		sleep 1;
		{
			alive _x
		} count units _group == 0
	};

	switch (toLower _groupID) do {
		case "alpha": {
			[west, "Base"] sideRadio "LostContactWithAlphaTeam";
		};
		case "bravo": {
			[west, "Base"] sideRadio "LostContactWithBravoTeam";
		};
		case "charlie": {
			[west, "Base"] sideRadio "LostContactWithCharlieTeam";
		};
		case "delta": {
			[west, "Base"] sideRadio "LostContactWithDeltaTeam";
		};
		default {
			hint format["%1 is not a valid squad name. Please use Alpha, Bravo, Charlie, Delta", _groupID];
		};
	};
};

save_original_loadouts = {
	params ["_group"];

	private _originalLoadouts = [];

	{
		_originalLoadouts pushBack [typeOf _x, getUnitLoadout _x];
	} forEach units _group;

	_originalLoadouts
};

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
		default {
			_marker setMarkerColorLocal "ColorWhite";
			_unit sideRadio "RadioUnknownGroupWipedOut";
		};
	};
	_markerName
};

call_support_team = {
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

	[_groupPlatoon] call wait_until_group_on_ground;
	deleteMarkerLocal _seizeMarkerName;
};

get_quiet_unit = {
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