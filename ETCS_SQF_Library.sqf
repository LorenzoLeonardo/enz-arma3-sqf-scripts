// ==============================================================================================================
// Enzo Tech Computer Solutions SQF Library
// Author: Lorenzo Leonardo
// Contact: enzotechcomputersolutions@gmail.com
// ==============================================================================================================

// ================================================================================
// Callback name for artillery fire status
#define ETCS_ARTILLERY_FIRE_STATUS_CALLBACK "ETCS_Callback_artilleryFireStatus"
// Callback name for artillery fire marker
#define ETCS_ARTILLERY_MAP_MARKER_CALLBACK "ETCS_Callback_artilleryFireMapMarker"

// Global variable to set/get if Unit is still on radio
#define ETCS_VAR_IS_RADIO_BUSY "ETCS_isUnitRadioBusy"
// Artillery Request Phase
#define ETCS_GUN_BARRAGE_PHASE_REQUEST 1
// Artillery Shot Phase
#define ETCS_GUN_BARRAGE_PHASE_SHOT 2
// Artillery Splash Phase
#define ETCS_GUN_BARRAGE_PHASE_SPLASH 3
// Artillery Done Phase
#define ETCS_GUN_BARRAGE_PHASE_DONE 4
// Artillery Invalid Range
#define ETCS_GUN_BARRAGE_PHASE_INVALID_RANGE 5
// ================================================================================

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
// clear waypoints of the group
// =======================================================================
ETCS_fnc_clearWaypoints = {
	params ["_group"];
	{
		deleteWaypoint _x
	} forEachReversed waypoints _group;
};

// =======================================================================
// compute the dyanamic accuracy radius
// =======================================================================
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
// find a valid replacement matching any of the allowed role types
// =======================================================================
ETCS_fnc_findReplacement = {
	params ["_unit", "_veh", "_allowedRoles"]; // e.g., ["cargo", "turret"]

	private _r = objNull;
	{
		if (([_x] call ETCS_fnc_isUnitGood) && _x != _unit &&
		(toLower ((assignedVehicleRole _x) select 0)) in _allowedRoles) exitWith {
			_r = _x
		};
	} forEach (crew _veh);

	_r
};

// =======================================================================
// fire the gun at a target position with optional accuracy radius
// =======================================================================
ETCS_fnc_fireArtillery = {
	params ["_caller", "_gun", "_targetPos", "_ammoType", ["_rounds", 3], ["_accuracyRadius", 0]];

	private _ammoLeft = [_gun, _ammoType] call ETCS_fnc_getAmmoCount;
	if (!canFire _gun || (_ammoLeft == 0)) exitWith {
		false
	};

	if (_ammoLeft < _rounds) then {
		_rounds = _ammoLeft;
	};

	private _finalPos = _targetPos;
	// Create temporary "X" marker
	private _marker = [_caller, _finalPos] call (_gun getVariable ETCS_ARTILLERY_MAP_MARKER_CALLBACK);

	if (_accuracyRadius > 0) then {
		private _angle = random 360;
		private _dist = random _accuracyRadius;
		_finalPos = _targetPos vectorAdd [(sin _angle * _dist), (cos _angle * _dist), 0];
	};
	// Choose a responder (gunner or commander)
	private _base = [group _gun] call ETCS_fnc_getQuietUnit;
	private _grid = mapGridPosition _finalPos;

	// --- 1. Standby call ---
	[_caller, _base, ETCS_GUN_BARRAGE_PHASE_REQUEST, _grid] call (_gun getVariable ETCS_ARTILLERY_FIRE_STATUS_CALLBACK);

	// --- 2. fire the artillery ---
	private _canReach = _finalPos inRangeOfArtillery [[_gun], _ammoType];
	if (!_canReach) exitWith {
		[_caller, _base, ETCS_GUN_BARRAGE_PHASE_INVALID_RANGE] call (_gun getVariable ETCS_ARTILLERY_FIRE_STATUS_CALLBACK);
		deleteMarker _marker;
		false
	};

	// Variable to track for first projectile to hit the ground
	// to sync when calling "Splash out"
	_gun setVariable ["ETCS_splashed", false, true];
	// list of number of shells to hit the ground to sync when
	// when calling Rounds complete
	_gun setVariable ["ETCS_firedShells", [], true];

	private _eventIndex = _gun addEventHandler ["Fired", {
		params ["_unit", "_weapon", "_muzzle", "_mode", "_ammo", "_mag", "_projectile"];

		[_projectile, _unit] spawn {
			params ["_proj", "_unit"];

			waitUntil {
				(isNull _proj) || !(alive _proj)
			};
			if !(_unit getVariable ["ETCS_splashed", false]) then {
				_unit setVariable ["ETCS_splashed", true, true];
			};

			private _shells = _unit getVariable ["ETCS_firedShells", []];
			_shells pushBack _proj;
			_unit setVariable ["ETCS_firedShells", _shells];
		};
	}];
	_gun doArtilleryFire [_finalPos, _ammoType, _rounds];

	// --- 3. Shot call ---
	[_caller, _base, ETCS_GUN_BARRAGE_PHASE_SHOT] call (_gun getVariable ETCS_ARTILLERY_FIRE_STATUS_CALLBACK);

	// call splash after the first shell hits the ground.
	waitUntil {
		_gun getVariable ["ETCS_splashed", false]
	};
	[_caller, _base, ETCS_GUN_BARRAGE_PHASE_SPLASH] call (_gun getVariable ETCS_ARTILLERY_FIRE_STATUS_CALLBACK);

	// call rounds complete until all projectiles hit the ground.
	waitUntil {
		private _shells = _gun getVariable ["ETCS_firedShells", []];
		(count _shells == _rounds)
	};
	[_caller, _base, ETCS_GUN_BARRAGE_PHASE_DONE] call (_gun getVariable ETCS_ARTILLERY_FIRE_STATUS_CALLBACK);

	deleteMarker _marker;

	_gun removeEventHandler["Fired", _eventIndex];
	true
};

// =======================================================================
// get all enemies of a unit
// =======================================================================
ETCS_fnc_getAllEnemies = {
	params ["_unit"];

	allUnits select {
		([_x] call ETCS_fnc_isUnitGood) &&
		[_unit, _x] call ETCS_fnc_isUnitsHostile
	}
};

// =======================================================================
// get all friends of a unit
// =======================================================================
ETCS_fnc_getAllFriendlies = {
	params ["_unit"];
	allUnits select {
		([_x] call ETCS_fnc_isUnitGood) &&
		!([_unit, _x] call ETCS_fnc_isUnitsHostile)
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

	private _observerSide = [_observer] call ETCS_fnc_getObserverSide;
	(getPos _target nearEntities ["Man", _radius]) select {
		[_x, _observerSide] call ETCS_fnc_isHostile
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
	private _observerSide = [_observer] call ETCS_fnc_getObserverSide;
	((getPos _observer) nearEntities ["Man", _distance]) select {
		[_x, _observerSide] call ETCS_fnc_isHostile
	}
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

// =======================================================================
// get average enemy positions
// =======================================================================
ETCS_fnc_getAverageEnemyPos = {
	params ["_sideEnemy"];
	private _enemies = allUnits select {
		side _x == _sideEnemy && alive _x
	};
	private _enemyPos = [0, 0, 0];
	{
		_enemyPos = _enemyPos vectorAdd (getPosATL _x)
	} forEach _enemies;

	if ((count _enemies) > 0) then {
		_enemyPos vectorMultiply (1 / (count _enemies))
	} else {
		[0, 0, 0]
	}
};

// =======================================================================
// generate a random position near average
// =======================================================================
ETCS_fnc_getRandomPosNearEnemy = {
	params ["_sideEnemy", ["_radius", 0]]; // default radius = 0

	private _avgPos = [_sideEnemy] call ETCS_fnc_getAverageEnemyPos;

	if (_avgPos isEqualTo [0, 0, 0]) exitWith {
		[0, 0, 0]
	}; // no enemies

	private _angle = random 360;
	private _dist = random _radius;

	private _offset = [
		_dist * cos _angle,
		_dist * sin _angle,
		0
	];

	_avgPos vectorAdd _offset
};

// =======================================================================
// driver down → try turret first (keep guns manned), then cargo
// =======================================================================
ETCS_fnc_handleDriverDown = {
	params ["_unit", "_veh"];

	private _replacement = [_unit, _veh, ["turret", "cargo"]] call ETCS_fnc_findReplacement;
	if (isNull _replacement) exitWith {};

	private _repRole = toLower ((assignedVehicleRole _replacement) select 0);

	switch (_repRole) do {
		case "turret": {
			// Turret path comes from the REPLACEMENT (they vacate that seat)
			private _turretPath = (assignedVehicleRole _replacement) select 1;
			// New positions: UNIT → that turret seat, REPLACEMENT → driver
			[_unit, _replacement, _veh, "turret", "driver", _turretPath, []] call ETCS_fnc_swapPositions;
		};
		case "cargo": {
			// New positions: UNIT → cargo, REPLACEMENT → driver
			[_unit, _replacement, _veh, "cargo", "driver", [], []] call ETCS_fnc_swapPositions;
		};
	};
};

// =======================================================================
// Turret down → pull from cargo into THIS unit's turret seat
// =======================================================================
ETCS_fnc_handleTurretDown = {
	params ["_unit", "_veh"];

	private _replacement = [_unit, _veh, ["cargo"]] call ETCS_fnc_findReplacement;
	if (isNull _replacement) exitWith {};

	// Turret path from the UNIT (the seat that just got vacated)
	private _unitTurretPath = (assignedVehicleRole _unit) select 1;

	// New positions: UNIT → cargo, REPLACEMENT → that turret seat
	[_unit, _replacement, _veh, "cargo", "turret", [], _unitTurretPath] call ETCS_fnc_swapPositions;
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
// move a unit to a specific role (optionally a turret seat path)
// =======================================================================
ETCS_fnc_moveToRole = {
	params ["_man", "_veh", "_role", "_seatPath"];

	switch (toLower _role) do {
		case "driver": {
			_man moveInDriver _veh
		};
		case "cargo": {
			_man moveInCargo _veh
		};
		case "turret": {
			_man moveInTurret [_veh, _seatPath]
		};
		default {};
	};
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
// spawn smoke to target location.
// ammo could be any of the following:
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

// =======================================================================
// Generic swap: define BOTH new roles (and seats if turret)
// =======================================================================
ETCS_fnc_swapPositions = {
	// _unit = the one going down; _replacement = the one taking over
	params ["_unit", "_replacement", "_veh", "_unitNewRole", "_replacementNewRole", "_unitTurretSeat", "_replacementTurretSeat"];

	// Evict both, then place them in target seats
	{
		unassignVehicle _x;
		moveOut _x;
	} forEach [_unit, _replacement];

	// Keep team cohesion
	[_replacement] joinSilent (group _unit);
	// Place them
	[_unit, _veh, _unitNewRole, _unitTurretSeat] call ETCS_fnc_moveToRole;
	[_replacement, _veh, _replacementNewRole, _replacementTurretSeat] call ETCS_fnc_moveToRole;
};