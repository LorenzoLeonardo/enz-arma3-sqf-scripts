// ==============================================================================================================
// Enzo Tech Computer Solutions SQF Library
// Author: Lorenzo Leonardo
// Contact: enzotechcomputersolutions@gmail.com
// ==============================================================================================================

#define ETCS_VAR_IS_RADIO_BUSY "ETCS_isRadioBusy"

// =======================================================================
// custom assign group name. if same name exist the format will be
// incrementing number inside a parenthesis.
// =======================================================================
ETCS_fnc_assignUniqueGroupId = {
	params ["_baseId"];

	private _counter = 1;
	private _newId = _baseId;
	// Loop until we find an unused ID
	while {
		{
			groupId _x == _newId
		} count allGroups > 0
	} do {
		_newId = format["%1 (%2)", _baseId, _counter];
		_counter = _counter + 1;
	};
	_newId
};

// =======================================================================
// attached big fire to destroyed vehicles.
// =======================================================================
ETCS_fnc_attachBigFire = {
	params ["_vehicle"];

	private _smoker = "test_EmptyObjectForFireBig" createVehicle (position _vehicle);
	_smoker attachTo [_vehicle, [0, 1.5, 0]];
};

// =======================================================================
// custom call radio with busy flags
// =======================================================================
ETCS_fnc_callSideRadio = {
	params["_unit", "_radioClass", ["_delay", 0]];

	[_unit] call ETCS_fnc_setUnitRadioBusy;
	_unit sideRadio _radioClass;
	sleep _delay;
	[_unit] call ETCS_fnc_setUnitRadioAvailable;
};

// =======================================================================
// clear waypoints of the group
// =======================================================================
ETCS_fnc_clearWaypoints = {
	params ["_group"];
	{
		deleteWaypoint _x
	} forEach waypoints _group;
};

// =======================================================================
// create waypoints for a group
// private _waypoint = [_group, [1000, 2000, 0], "NORMAL", "MOVE", "DIAMOND", "AWARE", 0] call ETCS_fnc_createWaypoint;
// =======================================================================
ETCS_fnc_createWaypoint = {
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

// =========================
// Dynamic Accuracy Radius Calculation
// =========================
ETCS_fnc_dynamicAccuracyRadius = {
	params ["_gun", "_accuracyRadius"];
	private _dynamicAccuracyRadius = 0;

	if (_accuracyRadius <= 0) then {
		// only auto-scale if not manually specified
		private _gunner = gunner _gun;
		private _skill = if (!isNull _gunner) then {
			skill _gunner
		} else {
			0.5 // default if unmanned
		};

		// Weapon-type specific scatter ranges
		private _maxScatter = 200;  // worst accuracy
		private _minScatter = 5;    // best accuracy
		if (_gun isKindOf "StaticMortar") then {
			_minScatter = 8;   // skilled mortar team
			_maxScatter = 80;  // poorly trained / max range
		} else {
			_minScatter = 15;  // skilled artillery crew
			_maxScatter = 150; // poor crew / max range
		};

		// skill reduces scatter (linear mapping)
		private _baseScatter = _maxScatter - (_skill * (_maxScatter - _minScatter));

		// Add random human imperfection (±20%)
		private _variation = random [0.8, 1, 1.2];
		_dynamicAccuracy = _baseScatter * _variation;
	} else {
		_dynamicAccuracyRadius = _accuracyRadius; // use specified radius
	};
	_dynamicAccuracyRadius
};

// =======================================================================
// find the nearest valid unit from a candidate list
// =======================================================================
ETCS_fnc_findNearestUnit = {
	params ["_unit", "_candidates"];

	if (!([_unit] call ETCS_fnc_isUnitGood)) exitWith {
		objNull
	};

	private _nearestUnit = objNull;
	private _nearestDist = 1e10;
	{
		if ([_x] call ETCS_fnc_isUnitGood) then {
			private _dist = _unit distance _x;
			if (_dist < _nearestDist) then {
				_nearestDist = _dist;
				_nearestUnit = _x;
			};
		};
	} forEach _candidates;

	_nearestUnit
};

// =======================================================================
// get all enemies of a unit
// =======================================================================
ETCS_fnc_getAllEnemies = {
	params ["_unit"];

	allUnits select {
		([_x] call ETCS_fnc_isUnitGood) &&
		[_unit, _x] call ETCS_fnc_isHostile
	}
};

// =======================================================================
// get all friends of a unit
// =======================================================================
ETCS_fnc_getAllFriendlies = {
	params ["_unit"];
	allUnits select {
		([_x] call ETCS_fnc_isUnitGood) &&
		!([_unit, _x] call ETCS_fnc_isHostile)
	}
};

// =======================================================================
// get remaining ammo count of a given type from a vehicle
// =======================================================================
ETCS_fnc_getAmmoCount = {
	params ["_vehicle", "_ammoType"];

	if (isNull _vehicle || {
		_ammoType isEqualTo ""
	}) exitWith {
		0
	};

	private _count = 0;
	{
		// _x = [magazineClass, ammoLeft]
		if ((_x select 0) isEqualTo _ammoType) exitWith {
			_count = _x select 1;
		};
	} forEach (magazinesAmmo _vehicle);

	_count
};

// =======================================================================
// get the artillery ammo type based on gun type
// =======================================================================
ETCS_fnc_getArtilleryAmmoType = {
	params ["_gun"];

	private _mags = magazines _gun;
	private _ammoType = "";

	// Prefer HE rounds specifically
	private _preferredKeywords = ["HE", "155mm", "105mm", "82mm", "shell", "Mo_shells"];

	// Look for HE first
	{
		private _mag = _x;
		{
			private _keyword = _x;
			if (_mag find _keyword > -1) exitWith {
				_ammoType = _mag;
			};
		} forEach _preferredKeywords;

		if (_ammoType != "") exitWith {};
	} forEach _mags;

	// Fallback to first mag if no HE found
	if (_ammoType == "" && {
		count _mags > 0
	}) then {
		_ammoType = _mags select 0;
	};

	// Final fallback if gun has no mags at all
	if (_ammoType == "") then {
		if (_gun isKindOf "StaticMortar") then {
			_ammoType = "8Rnd_82mm_Mo_shells";
		} else {
			_ammoType = "CUP_30Rnd_105mmHE_M119_M";  // default cannon HE
		};
	};

	_ammoType
};

// =======================================================================
// get a cluster of hostile units around a unit within a specified radius
// =======================================================================
ETCS_fnc_getCluster = {
	params ["_target", "_radius", "_observer"];

	(getPos _target nearEntities ["Man", _radius]) select {
		[_x, _observer] call ETCS_fnc_isHostile
	}
};

// =======================================================================
// get the center position of a cluster of units
// =======================================================================
ETCS_fnc_getClusterCenter = {
	params ["_cluster"];

	if (_cluster isEqualTo []) exitWith {
		[0, 0, 0]
	};

	private _sumX = 0;
	private _sumY = 0;
	private _sumZ = 0;
	{
		private _pos = getPosASL _x;
		_sumX = _sumX + (_pos select 0);
		_sumY = _sumY + (_pos select 1);
		_sumZ = _sumZ + (_pos select 2);
	} forEach _cluster;

	[
		_sumX / (count _cluster),
		_sumY / (count _cluster),
		_sumZ / (count _cluster)
	]
};

// =======================================================================
// count all enemies
// =======================================================================
ETCS_fnc_getEnemyCount = {
	params ["_unit"];

	count([_unit] call ETCS_fnc_getAllEnemies)
};

// =======================================================================
// get the side enemy of the given unit
// =======================================================================
ETCS_fnc_getEnemySide = {
	params ["_chopper"];

	private _side = side (driver _chopper);

	switch (_side) do {
		case east: {
			west
		};
		case west: {
			east
		};
		case independent: {
			west
		};
		case civilian: {
			east
		};
		default {
			independent
		};
	};
};

// =======================================================================
// count all friends
// =======================================================================
ETCS_fnc_getFriendliesCount = {
	params ["_unit"];

	count([_unit] call ETCS_fnc_getAllFriendlies)
};

// =======================================================================
// get enemies near the observer given the distance from observer to
// the enemies.
// =======================================================================
ETCS_fnc_getNearEnemies = {
	params ["_observer", "_distance"];

	((getPos _observer) nearEntities ["Man", _distance]) select {
		[_x, _observer] call ETCS_fnc_isHostile
	}
};

// =======================================================================
// get friendlies near the observer given the distance from observer to
// the enemies.
// =======================================================================
ETCS_fnc_getNearFriendlies = {
	params ["_observer", "_distance"];

	((getPos _observer) nearEntities ["Man", _distance]) select {
		!([_x, _observer] call ETCS_fnc_isHostile)
	};
};

// =======================================================================
// get the side of the observer, preferring its crew if it is inside
// a vehicle, fallback to object side
// =======================================================================
ETCS_fnc_getObserverSide = {
	params ["_observer"];

	if (isNull _observer) exitWith {
		sideLogic
	}; // default safe return

	if ((count crew _observer) > 0) exitWith {
		side (effectiveCommander _observer)
	};

	side _observer
};

// =======================================================================
// get a quiet unit from the group
// =======================================================================
ETCS_fnc_getQuietUnit = {
	params ["_group"];
	private _radioMan = objNull;
	if (isNull _group) exitWith {
		_radioMan
	};

	_radioMan = leader _group;
	{
		if ([_x] call ETCS_fnc_isUnitGood && !isPlayer _x &&
		(_x != _radioMan) && !([_x] call ETCS_fnc_isUnitRadioBusy)) exitWith {
			_radioMan = _x;
		};
	} forEach (units _group);

	_radioMan
};

// =========================
// Check if a cluster is a duplicate based on proximity
// =========================
ETCS_fnc_isClusterDuplicate = {
	params ["_centerPos", "_clustersChecked", "_mergeRadius"];

	private _foundIndex = _clustersChecked findIf {
		(_centerPos distance2D _x) < _mergeRadius
	};

	_foundIndex > -1
};

// =======================================================================
// Check if two units are hostile
// =======================================================================
ETCS_fnc_isHostile = {
	params ["_unit1", "_unit2"];

	([_unit1] call ETCS_fnc_isUnitGood) &&
	([_unit2] call ETCS_fnc_isUnitGood) &&
	(((side _unit1) getFriend (side _unit2)) < 0.6 ||
	((side _unit2) getFriend (side _unit1)) < 0.6)
};

// =======================================================================
// Check if a unit is valid/usable
// =======================================================================
ETCS_fnc_isUnitGood = {
	params ["_unit"];
	!isNull _unit &&
	{
		alive _unit
	} &&
	{
		lifeState _unit != "INCAPACITATED"
	}
};

// =======================================================================
// check if unit radio is still busy.
// =======================================================================
ETCS_fnc_isUnitRadioBusy = {
	_x getVariable [ETCS_VAR_IS_RADIO_BUSY, false]
};

// =======================================================================
// set the ETCS_VAR_IS_RADIO_BUSY to false signifying unit is done calling
// on the radio. call this function after calling sideRadio.
// =======================================================================
ETCS_fnc_setUnitRadioAvailable = {
	params ["_unit"];

	_unit setVariable [ETCS_VAR_IS_RADIO_BUSY, false, true];
};

// =======================================================================
// set the ETCS_VAR_IS_RADIO_BUSY to true signifying unit is still
// on radio. call this function before calling sideRadio.
// =======================================================================
ETCS_fnc_setUnitRadioBusy = {
	params ["_unit"];

	_unit setVariable [ETCS_VAR_IS_RADIO_BUSY, true, true];
};

// =======================================================================
// spawn smoke to target location. ammo could be any of the following:
// SmokeShell, SmokeShellRed, SmokeShellBlue, SmokeShellYellow,
//  SmokeShellOrange, SmokeShellPurple, SmokeShellGreen,
// Smoke_120mm_AMOS_White
// =======================================================================
ETCS_fnc_spawnSmoke = {
	params [
		["_ammo", "SmokeShell"],
		["_centerPos", [0, 0, 0], [[]]],
		["_radius", 0, [0]],
		["_count", 1, [0]]
	];

	for "_i" from 1 to _count do {
		private _angle = random 360;
		private _dist = random _radius;

		private _offsetX = _dist * cos _angle;
		private _offsetY = _dist * sin _angle;

		private _pos = [
			(_centerPos select 0) + _offsetX,
			(_centerPos select 1) + _offsetY,
			(_centerPos select 2)
		];

		private _posSmoke = _centerPos vectorAdd [0, 0, 150];
		private _proj = _ammo createVehicle _posSmoke;

		_proj setVelocity [0, 0, -100];
	};
};