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
// Check if two units are hostile
// =======================================================================
ETCS_fnc_isUnitsHostile = {
	params ["_unit1", "_unit2"];

	([_unit1] call ETCS_fnc_isUnitGood) &&
	([_unit2] call ETCS_fnc_isUnitGood) &&
	(((side _unit1) getFriend (side _unit2)) < 0.6 ||
	((side _unit2) getFriend (side _unit1)) < 0.6)
};

// =======================================================================
// get all enemies of a unit
// =======================================================================
ETCS_fnc_allEnemies = {
	params ["_unit"];

	allUnits select {
		([_x] call ETCS_fnc_isUnitGood) &&
		[_unit, _x] call ETCS_fnc_isUnitsHostile
	}
};

// =======================================================================
// get all friends of a unit
// =======================================================================
ETCS_fnc_allFriendlies = {
	params ["_unit"];
	allUnits select {
		([_x] call ETCS_fnc_isUnitGood) &&
		!([_unit, _x] call ETCS_fnc_isUnitsHostile)
	}
};

// =======================================================================
// find the nearest valid unit from a candidate list
// =======================================================================
ETCS_fnc_findNearestUnit = {
	params ["_unit", "_candidates"];

	if !([_unit] call ETCS_fnc_isUnitGood) exitWith {
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

ETCS_fnc_setUnitRadioBusy = {
	params ["_unit"];

	_unit setVariable [ETCS_VAR_IS_RADIO_BUSY, true, true];
};

ETCS_fnc_setUnitRadioAvailable = {
	params ["_unit"];

	_unit setVariable [ETCS_VAR_IS_RADIO_BUSY, false, true];
};

ETCS_fnc_isUnitRadioBusy = {
	_x getVariable [ETCS_VAR_IS_RADIO_BUSY, false]
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
	if (isNull _radioMan) then {
		_radioMan = player;
	};
	{
		if ([_x] call ETCS_fnc_isUnitGood && !isPlayer _x &&
		(_x != _radioMan) && !([_x] call ETCS_fnc_isUnitRadioBusy)) exitWith {
			_radioMan = _x;
		};
	} forEach (units _group);

	_radioMan
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
	private _marker = [_caller, _finalPos] call (missionNamespace getVariable ETCS_ARTILLERY_MAP_MARKER_CALLBACK);

	if (_accuracyRadius > 0) then {
		private _angle = random 360;
		private _dist = random _accuracyRadius;
		_finalPos = _targetPos vectorAdd [(sin _angle * _dist), (cos _angle * _dist), 0];
	};
	// Choose a responder (gunner or commander)
	private _base = [group _gun] call ETCS_fnc_getQuietUnit;
	private _grid = mapGridPosition _finalPos;

	// --- 1. Standby call ---
	[_caller, _base, ETCS_GUN_BARRAGE_PHASE_REQUEST, _grid] call (missionNamespace getVariable ETCS_ARTILLERY_FIRE_STATUS_CALLBACK);

	// --- 2. fire the artillery ---
	private _canReach = _finalPos inRangeOfArtillery [[_gun], _ammoType];
	if (!_canReach) exitWith {
		[_caller, _base, ETCS_GUN_BARRAGE_PHASE_INVALID_RANGE] call (missionNamespace getVariable ETCS_ARTILLERY_FIRE_STATUS_CALLBACK);
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
	[_caller, _base, ETCS_GUN_BARRAGE_PHASE_SHOT] call (missionNamespace getVariable ETCS_ARTILLERY_FIRE_STATUS_CALLBACK);

	// call splash after the first shell hits the ground.
	waitUntil {
		_gun getVariable ["ETCS_splashed", false]
	};
	[_caller, _base, ETCS_GUN_BARRAGE_PHASE_SPLASH] call (missionNamespace getVariable ETCS_ARTILLERY_FIRE_STATUS_CALLBACK);

	// call rounds complete until all projectiles hit the ground.
	waitUntil {
		private _shells = _gun getVariable ["ETCS_firedShells", []];
		(count _shells == _rounds)
	};
	[_caller, _base, ETCS_GUN_BARRAGE_PHASE_DONE] call (missionNamespace getVariable ETCS_ARTILLERY_FIRE_STATUS_CALLBACK);

	deleteMarker _marker;

	_gun removeEventHandler["Fired", _eventIndex];
	true
};