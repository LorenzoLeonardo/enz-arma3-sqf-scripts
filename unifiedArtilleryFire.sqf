// ==============================================================================================================
// Unified Artillery fire Script
// Author: Lorenzo Leonardo
// Contact: enzotechcomputersolutions@gmail.com
// ==============================================================================================================
// 
// Description:
// This script provides flexible player or AI-controlled mortar and artillery fire support in three modes:
//     SCOUT - Fires only when a designated scout group's leader detects and identifies enemies.
//     AUTO  - Automatically scans for enemy unit clusters within a set detection range of the gun.
//    MAP   - Fires only when a player opens tha map and click on a target location.
// It unifies both functionalities into one configurable system.
// 
// Features:
// - SCOUT mode: Fires based on a scout leader's spotted enemies.
// - AUTO mode: Continuously scans for enemy clusters within detection range.
// - MAP mode: Fires when player clicks on the desired location on the map.
// - Groups enemies into clusters before engagement.
// - Prevents redundant targeting by tracking claimed zones.
// - Configurable rounds per strike, cluster size, accuracy, and cooldown.
// - Supports both limited and unlimited ammunition.
// - Works with multiple guns, mortars, or heavy artillery.
// 
// Parameters:
//   _gun                   - The mortar or artillery object to control.
//   _genericParam          - Either a number for AUTO mode (detection range) or an object for SCOUT mode (scout group).
//   _rounds                - Number of rounds to fire per cluster (default: 8).
//   _clusterRadius         - Radius (in meters) to group nearby enemies into a cluster (default: 50).
//   _minUnitsPerCluster    - Minimum number of units in a cluster before engaging (default: 8).
//   _coolDownForEffect     - Delay (in seconds) between volleys (default: 60).
//   _unlimitedAmmo         - Boolean; true to allow infinite resupply (default: false).
//   _accuracyRadius        - Scatter radius (in meters) for shot inaccuracy (default: 0 = perfect aim).
//   _claimRadius           - distance to avoid firing if target is claimed by another gun (default: 50).

// 
// Usage Example:
// [this, 10000, 8, 50, 8, 60, true, 50, 25] execVM "unifiedArtilleryFire.sqf"; (AUTO mode with specified accuracy radius)
// [this, group, 8, 50, 8, 60, true, 50, 25] execVM "unifiedArtilleryFire.sqf"; (SCOUT mode with specified accuracy radius)
// [this, player, 8, 50, 8, 60, true, 50, 25] execVM "unifiedArtilleryFire.sqf"; (MAP mode with specified accuracy radius)
// 
// [this, 10000, 8, 50, 8, 60, true, 50] execVM "unifiedArtilleryFire.sqf"; (AUTO mode without specified accuracy radius, used gunner's skill to determine scatter)
// [this, group, 8, 50, 8, 60, true, 50] execVM "unifiedArtilleryFire.sqf"; (SCOUT mode without specified accuracy radius, used gunner's skill to determine scatter)
// [this, player, 8, 50, 8, 60, true, 50] execVM "unifiedArtilleryFire.sqf"; (MAP mode without specified accuracy radius, used gunner's skill to determine scatter)
// ==============================================================================================================

// =====================
// Definitions
// =====================

// Callback name for artillery fire radio routines
#define GUN_FIRE_CALLBACK "Callback_gunFireRadio"
// Artillery Request Phase
#define GUN_BARRAGE_PHASE_REQUEST 1
// Artillery Shot Phase
#define GUN_BARRAGE_PHASE_SHOT 2
// Artillery Splash Phase
#define GUN_BARRAGE_PHASE_SPLASH 3
// Artillery Done Phase
#define GUN_BARRAGE_PHASE_DONE 4
// Artillery Invalid Range
#define GUN_BARRAGE_PHASE_INVALID_RANGE 5

// Callback name for artillery fire marker
#define GUN_MARKER_CALLBACK "Callback_gunFireMarker"

// Artillery Mode
#define MODE_AUTO 0
#define MODE_SCOUT 1
#define MODE_MAP 2

// =====================
// Parameters
// =====================

// _gun = the artillery or mortar gun object
private _gun = _this param [0];
// _genericParam = either a number for AUTO mode or an object for SCOUT mode or player for MAP mode
private _genericParam = _this param [1];
// _rounds = number of rounds to fire at each cluster (default: 8)
private _rounds = _this param [2, 8];
// _clusterRadius = radius to consider a cluster of enemies (default: 50 meters)
private _clusterRadius = _this param [3, 50];
// _minUnitsPerCluster = number of enemy units in a cluster to fire at (default: 8)
private _minUnitsPerCluster = _this param [4, 8];
// _coolDownForEffect = cooldown time between firing rounds (default: 60 seconds)
private _coolDownForEffect = _this param [5, 60];
// _unlimitedAmmo = whether to use unlimited ammo (default: false)
private _unlimitedAmmo = _this param [6, false];
// _claimRadius = distance to avoid firing if target is claimed by another gun (default: 50 meters)
private _claimRadius = _this param [7, 50];
// _accuracyRadius = Optional accuracy radius for mortar fire, if not specified, defaults to 0 (Rely on gunner's skill)
private _accuracyRadius = _this param [8, 0];

// =====================
// Initialization either AUTO Mode or SCOUT Mode
// =====================
// _mode = MODE_AUTO, MODE_SCOUT or MODE_MAP
private _mode = MODE_AUTO;
// _detectionRange = Radial distance from the gun used to detect enemy units in AUTO mode (default: 800 meters). Applicable in AUTO mode only.
private _detectionRange = 800;
// _scoutGroup = group doing the spotting. Applicable in SCOUT mode only.
private _scoutGroup = objNull;

switch (typeName _genericParam) do {
	case "SCALAR": {
		sleep 3; // Allow time for the gun to initialize
		_mode = MODE_AUTO;
		_detectionRange = _genericParam;
		_scoutGroup = objNull; // No scout group in AUTO mode
		hint format ["Artillery AUTO mode activated with detection range: %1 meters", _detectionRange];
	};
	case "GROUP": {
		sleep 3; // Allow time for the gun to initialize
		_mode = MODE_SCOUT;
		_detectionRange = 0; // No detection range in SCOUT mode
		_scoutGroup = _genericParam; // Use the provided object as the scout group
		hint format ["Artillery SCOUT mode activated with scout group: %1", groupId _scoutGroup];
	};
	case "OBJECT": {
		sleep 3; // Allow time for the gun to initialize
		_mode = MODE_MAP;
		_detectionRange = 0; // No detection range in SCOUT mode
		_scoutGroup = objNull; // Use the provided object as the scout group
		hint "Artillery MAP mode activated";
	};
	default {
		// Unsupported type
		hint format ["Unsupported cluster type: %1", typeName _genericParam];
	};
};

// =========================
// Global Target Registry
// =========================
if (isNil {
	missionNamespace getVariable "GVAR_activeTargets"
}) then {
	missionNamespace setVariable ["GVAR_activeTargets", []];
};

// =========================
// Dynamic Accuracy Radius Calculation
// =========================
fnc_dynamicAccuracyRadius = {
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
			_maxScatter = 100;
			_minScatter = 3;
		} else {
			_maxScatter = 200;
			_minScatter = 10;
		};

		// Map skill to scatter (higher skill → smaller radius)
		_dynamicAccuracyRadius = _maxScatter - (_skill * (_maxScatter - _minScatter));
	} else {
		_dynamicAccuracyRadius = _accuracyRadius; // use specified radius
	};
	_dynamicAccuracyRadius
};

// =========================
// Claim a target position for the gun
// =========================
fnc_claimTarget = {
	params ["_pos", "_gun"];
	private _targets = missionNamespace getVariable ["GVAR_activeTargets", []];
	_targets pushBack [_pos, _gun];
	missionNamespace setVariable ["GVAR_activeTargets", _targets];
};

// =========================
// Release a target from the gun's claim
// =========================
fnc_releaseTarget = {
	params ["_gun"];
	private _targets = missionNamespace getVariable ["GVAR_activeTargets", []];
	_targets = _targets select {
		(_x select 1) != _gun
	};
	missionNamespace setVariable ["GVAR_activeTargets", _targets];
};

// =========================
// Check if a target position is already claimed by another gun
// =========================
fnc_isTargetClaimed = {
	params ["_pos", "_radius"];
	private _targets = missionNamespace getVariable ["GVAR_activeTargets", []];
	private _claimed = false;
	{
		if (_pos distance2D (_x select 0) < _radius) exitWith {
			_claimed = true
		};
	} forEach _targets;
	_claimed
};

// =========================
// get the ammo count for a specific ammo type in a vehicle
// =========================
fnc_getAmmoCount = {
	params ["_vehicle", "_ammoType"];
	private _count = 0;
	{
		if (_x select 0 == _ammoType) exitWith {
			_count = _x select 1
		};
	} forEach magazinesAmmo _vehicle;
	_count
};

// =========================
// Handle gun depletion (unassign crew, move to guard position, optionally disable gun)
// =========================
fnc_handleGunDepletion = {
	params ["_gun"];
	if (isNull _gun) exitWith {};

	private _crew = crew _gun;
	if (count _crew == 0) exitWith {};

	private _crewgroup = group (_crew select 0);
	{
		unassignVehicle _x;
		_x action ["GetOut", _gun];
	} forEach _crew;

	sleep 3;
	// Optional (disable gun)
	_gun setDamage 1;

	private _guardPos = (getPos _gun) getPos [30 + random 20, random 360];
	_crewgroup move _guardPos;
	private _wp = _crewgroup addWaypoint [_guardPos, 0];
	_wp setWaypointType "GUARD";
	_wp setWaypointBehaviour "AWARE";
	_wp setWaypointSpeed "FULL";
	_wp setWaypointCombatMode "GREEN";
};

// =========================
// get the side of the gun based on its crew or default side
// =========================
fnc_getGunSide = {
	params ["_gun"];
	if ((count crew _gun) > 0) exitWith {
		side (gunner _gun)
	};
	side _gun
};

// =========================
// Check if a unit is hostile to the gun's side
// =========================
fnc_isHostile = {
	params ["_unit", "_gunSide"];
	alive _unit && ((side _unit getFriend _gunSide) < 0.6 || (_gunSide getFriend side _unit) < 0.6)
};

// =========================
// get enemies near a position within a specified distance
// =========================
fnc_getEnemies = {
	params ["_origin", "_distance", "_gun"];
	private _gunSide = [_gun] call fnc_getGunSide;
	(_origin nearEntities ["Man", _distance]) select {
		[_x, _gunSide] call fnc_isHostile
	}
};

// =========================
// get a cluster of hostile units around a unit within a specified radius
// =========================
fnc_getCluster = {
	params ["_unit", "_radius", "_gun"];
	private _gunSide = [_gun] call fnc_getGunSide;
	(getPos _unit nearEntities ["Man", _radius]) select {
		[_x, _gunSide] call fnc_isHostile
	}
};

// =========================
// get the center position of a cluster of units
// =========================
fnc_getClusterCenter = {
	params ["_cluster"];
	if ((count _cluster) == 0) exitWith {
		[0, 0, 0]
	};
	private _sumX = 0;
	private _sumY = 0;
	{
		private _pos = getPos _x;
		_sumX = _sumX + (_pos select 0);
		_sumY = _sumY + (_pos select 1)
	} forEach _cluster;
	[_sumX / (count _cluster), _sumY / (count _cluster), 0]
};

// =========================
// Callbacks
// =========================

// if this callback is not defined, there will be no radio sounds, 
// The artillery/mortar will continue to do its job
missionNamespace setVariable [GUN_FIRE_CALLBACK, {
	params ["_requestor", "_responder", "_phase", "_grid"];

	switch (_phase) do {
		case GUN_BARRAGE_PHASE_REQUEST: {
			_requestor sideRadio "RadioArtilleryRequest"; // plays sound
			_requestor sideChat format ["Requesting immediate artillery at the designated coordinates [%1]. Over!", _grid];
		};
		case GUN_BARRAGE_PHASE_SHOT : {
			_responder sideRadio "RadioArtilleryResponse";
			_responder sideChat "Target location received, order is inbound. Out!";
		};
		case GUN_BARRAGE_PHASE_SPLASH : {
			_responder sideRadio "RadioArtillerySplash";
			_responder sideChat "Splash. Out!";
		};
		case GUN_BARRAGE_PHASE_DONE : {
			_responder sideRadio "RadioArtilleryRoundsComplete";
			_responder sideChat "Rounds complete. Out!";
		};
		case GUN_BARRAGE_PHASE_INVALID_RANGE :{
			_responder sideRadio "CannotExecuteThatsOutsideOurFiringEnvelope";
			_responder sideChat "Cannot execute. That's outside our firing envelope!";
		};
		default {
			systemChat format ["Invalid artillery call phase: %1", _phase];
		};
	};
}];

missionNamespace setVariable [GUN_MARKER_CALLBACK, {
	params ["_requestor", "_targetPost"];

	private _markerId = format ["artilleryMarker_%1", diag_tickTime];
	private _marker = createMarker [_markerId, _targetPost];
	_marker setMarkerShape "ICON";
	_marker setMarkerType "mil_warning";

	switch (toLower groupId (group _requestor)) do {
		case "alpha": {
			_marker setMarkerColor "ColorBlue";
		};
		case "bravo": {
			_marker setMarkerColor "ColorRed";
		};
		case "charlie": {
			_marker setMarkerColor "ColorGreen";
		};
		case "delta": {
			_marker setMarkerColor "ColorYellow";
		};
		default {
			_marker setMarkerColor "ColorBlack";
		};
	};
	_marker setMarkerText format["Fire Mission %1!!!", groupId (group _requestor)];

	_marker
}];

// =========================
// fire the gun at a target position with optional accuracy radius
// =========================
fnc_fireGun = {
	params ["_caller", "_gun", "_targetPos", "_accuracyRadius", "_ammoType", "_rounds"];
	if (!canFire _gun) exitWith {
		false
	};

	private _finalPos = _targetPos;
	if (_accuracyRadius > 0) then {
		private _angle = random 360;
		private _dist = random _accuracyRadius;
		_finalPos = [
			(_targetPos select 0) + (sin _angle * _dist),
			(_targetPos select 1) + (cos _angle * _dist),
			0
		];
	};
	// Choose a responder (gunner or commander)
	private _base = if (!isNull (gunner _gun)) then {
		gunner _gun
	} else {
		commander _gun
	};
	if (isNull _base) exitWith {
		false
	};
	private _grid = mapGridPosition _finalPos;

	// Create temporary "X" marker
	private _marker = [_caller, _finalPos] call (missionNamespace getVariable GUN_MARKER_CALLBACK);
	// --- 1. Standby call ---
	[_caller, _base, GUN_BARRAGE_PHASE_REQUEST, _grid] call (missionNamespace getVariable GUN_FIRE_CALLBACK);
	sleep 3;  // small delay before firing

	// --- 2. fire the artillery ---
	private _canReach = _finalPos inRangeOfArtillery [[_gun], _ammoType];
	if (!_canReach) exitWith {
		[_caller, _base, GUN_BARRAGE_PHASE_INVALID_RANGE] call (missionNamespace getVariable GUN_FIRE_CALLBACK);
		sleep 2;
		deleteMarker _marker;
		false
	};
	_gun doArtilleryFire [_finalPos, _ammoType, _rounds];

	// --- 3. Shot call ---
	sleep 2;
	[_caller, _base, GUN_BARRAGE_PHASE_SHOT] call (missionNamespace getVariable GUN_FIRE_CALLBACK);

	// --- Wait until the gun finishes firing ---
	waitUntil {
		sleep 1;
		(currentCommand _gun) == ""
	};

	// Estimate shell flight time based on distance
	private _distance = _gun distance2D _finalPos;
	private _shellSpeed = 300;  // Average for mortars; use ~400 for howitzers
	private _flightTime = _distance / _shellSpeed;

	 // --- 4. Splash call (always) ---
	private _wait = 0.5;
	if (_flightTime > 5) then {
		_wait = _flightTime - 5;
	};
	sleep _wait;
	[_caller, _base, GUN_BARRAGE_PHASE_SPLASH] call (missionNamespace getVariable GUN_FIRE_CALLBACK);

	// --- 5. Rounds Complete (after impact) ---
	sleep (_flightTime + 2);
	[_caller, _base, GUN_BARRAGE_PHASE_DONE] call (missionNamespace getVariable GUN_FIRE_CALLBACK);

	deleteMarker _marker;
	true
};

// =========================
// get the artillery ammo type based on gun type
// =========================
fnc_getArtilleryAmmoType = {
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

// =========================
// Check if a cluster is a duplicate based on proximity
// =========================
fnc_isClusterDuplicate = {
	params ["_centerPos", "_clustersChecked", "_mergeRadius"];

	private _foundIndex = _clustersChecked findIf {
		(_centerPos distance2D _x) < _mergeRadius
	};

	_foundIndex > -1
};

// =========================
// get a quiet unit from the group
// =========================
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

// =========================
// Enemy Selection Logic
// =========================
fnc_selectEnemiesByMode = {
	params ["_mode", "_scoutGroup", "_gun", "_detectionRange"];

	private _enemies = [];
	private _group = objNull;

	switch (_mode) do {
		case MODE_SCOUT: {
			private _gunSide = [_gun] call fnc_getGunSide;
			private _scoutLeader = leader _scoutGroup;
			if (isNull _scoutLeader || !alive _scoutLeader) exitWith {
				[[], objNull]
			};

			private _allUnits = allUnits select {
				[_x, _gunSide] call fnc_isHostile && alive _x
			};
			_enemies = _allUnits select {
				_scoutLeader knowsAbout _x > 1.5
			};
			if (_enemies isEqualTo []) exitWith {
				[[], objNull]
			};
			_group = group _scoutLeader;
		};
		case MODE_AUTO: {
			_enemies = [getPos _gun, _detectionRange, _gun] call fnc_getEnemies;
			if (_enemies isEqualTo []) exitWith {
				[[], objNull]
			};
			_group = group _gun;
		};
		default {
			hint format["Invalid mode specified. Use MODE_SCOUT, MODE_AUTO or MODE_MAP."];
			[[], objNull]
		};
	};

	[_enemies, _group]
};

// =========================
// lock / Unlock System
// =========================
fnc_lockOnGoingFire = {
	missionNamespace setVariable ["onGoingGunFire", true, true];
};

fnc_unlockOnGoingFire = {
	missionNamespace setVariable ["onGoingGunFire", false, true];
};

fnc_isOnGoingFire = {
	missionNamespace getVariable ["onGoingGunFire", false]
};

// =========================
// Gun Index Assignment
// =========================
fnc_assignGunIndex = {
	params ["_gun"];
	// The purpose of these lines if this script is attached to multiple guns.
	// Thus we don't need to let them fire at the same time.
	// We stored each index and make it as a delay.
	private _current = 0;
	if (isNil "gunCount") then {
		missionNamespace setVariable ["gunCount", 0, true];
	} else {
		_current = missionNamespace getVariable ["gunCount", 0];
		missionNamespace setVariable ["gunCount", _current + 1, true];
	};
	_gun setVariable["gunIndex", missionNamespace getVariable["gunCount", 0], true];
};

// =========================
// Handler for AUTO or SCOUT Mode
// =========================
fnc_handleAutoOrScoutMode = {
	params [
		"_mode",
		"_gun",
		"_detectionRange",
		"_scoutGroup",
		"_rounds",
		"_clusterRadius",
		"_minUnitsPerCluster",
		"_coolDownForEffect",
		"_unlimitedAmmo",
		"_accuracyRadius",
		"_claimRadius"
	];

	[
		_mode,
		_gun,
		_detectionRange,
		_scoutGroup,
		_rounds,
		_clusterRadius,
		_minUnitsPerCluster,
		_coolDownForEffect,
		_unlimitedAmmo,
		_accuracyRadius,
		_claimRadius
	]
	spawn {
		params [
			"_mode",
			"_gun",
			"_detectionRange",
			"_scoutGroup",
			"_rounds",
			"_clusterRadius",
			"_minUnitsPerCluster",
			"_coolDownForEffect",
			"_unlimitedAmmo",
			"_accuracyRadius",
			"_claimRadius"
		];

		private _ammoType = [_gun] call fnc_getArtilleryAmmoType;
		private _clusterMergeRadius = 10;   // minimum separation to treat clusters as unique

		_gun setVehicleAmmo 1;

		while { !isNull _gun && alive _gun } do {
			sleep 2;

			private _dynamicAccuracyRadius = [_gun, _accuracyRadius] call fnc_dynamicAccuracyRadius;
			private _ammoLeft = [_gun, _ammoType] call fnc_getAmmoCount;
			if (_ammoLeft <= 0) then {
				if (_unlimitedAmmo) then {
					_gun setVehicleAmmo 1
				} else {
					[_gun] call fnc_handleGunDepletion;
					break
				};
			};

			private _enemiesAndGroup = [_mode, _scoutGroup, _gun, _detectionRange] call fnc_selectEnemiesByMode;
			if (_enemiesAndGroup isEqualTo [[], objNull]) then {
				continue
			};
			private _enemies = _enemiesAndGroup select 0;
			if (_enemies isEqualTo []) then {
				continue
			};
			private _group = _enemiesAndGroup select 1;
			if (isNull _group) then {
				continue
			};

			private _clustersChecked = [];
			{
				private _cluster = [_x, _clusterRadius, _gun] call fnc_getCluster;
				if (count _cluster >= _minUnitsPerCluster) then {
					private _centerPos = [_cluster] call fnc_getClusterCenter;
					private _isDuplicate = [_centerPos, _clustersChecked, _clusterMergeRadius] call fnc_isClusterDuplicate;

					if (_isDuplicate) then {
						continue
					};

					_clustersChecked pushBack _centerPos;

					if (!([_centerPos, _claimRadius] call fnc_isTargetClaimed)) then {
						[_centerPos, _gun] call fnc_claimTarget;

						private _quietUnit = [_group] call fnc_getQuietUnit;
						private _fired = [_quietUnit, _gun, _centerPos, _dynamicAccuracyRadius, _ammoType, _rounds] call fnc_fireGun;
						if (_fired) then {
							sleep _coolDownForEffect;
						};

						[_gun] call fnc_releaseTarget;
						// one cluster per loop
						break;
					};
				};
			} forEach _enemies;
		};
	};
};

// =========================
// Handler for MAP Mode
// =========================
fnc_handleMapMode = {
	params [
		"_gun",
		"_rounds",
		"_unlimitedAmmo",
		"_accuracyRadius"
	];

	missionNamespace setVariable ["onGoingGunFire", false, true];
	[_gun] call fnc_assignGunIndex;
	addMissionEventHandler [
		"MapSingleClick",
		{
			params ["_units", "_pos", "_alt", "_shift", "_thisArgs"];
			_thisArgs params ["_gun", "_rounds", "_unlimitedAmmo", "_accuracyRadius"];

			if (!([] call fnc_isOnGoingFire)) then {
				[_gun, _rounds, _unlimitedAmmo, _accuracyRadius, _pos] spawn {
					params ["_gun", "_rounds", "_unlimitedAmmo", "_accuracyRadius", "_pos"];

					[] call fnc_lockOnGoingFire;
					[_pos, _gun] call fnc_claimTarget;

					private _dynamicAccuracyRadius = [_gun, _accuracyRadius] call fnc_dynamicAccuracyRadius;
					private _ammoType = [_gun] call fnc_getArtilleryAmmoType;

					if (_unlimitedAmmo) then {
						_gun setVehicleAmmo 1;
					};
					// We use the gun's index as a delay so that they won't fire at the same time.
					// This is needed since this script can be attached into multiple guns.
					private _thisDelay = _gun getVariable["gunIndex", 0];
					sleep _thisDelay;
					private _fired = [player, _gun, _pos, _dynamicAccuracyRadius, _ammoType, _rounds] call fnc_fireGun;

					if (!_fired) then {
						hint "Gun fire failed!";
					};

					[_gun] call fnc_releaseTarget;
					[] call fnc_unlockOnGoingFire;
				};
			} else {
				hint "Guns are busy at the moment!";
			};
		},
		// Custom parameters passed to this event handler
		[_gun, _rounds, _unlimitedAmmo, _accuracyRadius]
	];
};

// =========================
// Main Script Entry
// =========================
switch (_mode) do {
	case MODE_AUTO;
	case MODE_SCOUT: {
		[
			_mode,
			_gun,
			_detectionRange,
			_scoutGroup,
			_rounds,
			_clusterRadius,
			_minUnitsPerCluster,
			_coolDownForEffect,
			_unlimitedAmmo,
			_accuracyRadius,
			_claimRadius
		] call fnc_handleAutoOrScoutMode;
	};

	case MODE_MAP: {
		[
			_gun,
			_rounds,
			_unlimitedAmmo,
			_accuracyRadius
		] call fnc_handleMapMode;
	};

	default {
		hint format ["Invalid Mode used: %1", _mode];
	};
};