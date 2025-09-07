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
#include "common.sqf"

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
		_mode = MODE_AUTO;
		_detectionRange = _genericParam;
		_scoutGroup = objNull; // No scout group in AUTO mode
		hint format ["Artillery AUTO mode activated with detection range: %1 meters", _detectionRange];
	};
	case "GROUP": {
		_mode = MODE_SCOUT;
		_detectionRange = 0; // No detection range in SCOUT mode
		_scoutGroup = _genericParam; // Use the provided object as the scout group
		hint format ["Artillery SCOUT mode activated with scout group: %1", groupId _scoutGroup];
	};
	case "OBJECT": {
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
// Claim a target position for the gun
// =========================
ETCS_fnc_claimTarget = {
	params ["_pos", "_gun"];
	private _targets = missionNamespace getVariable ["GVAR_activeTargets", []];
	_targets pushBack [_pos, _gun];
	missionNamespace setVariable ["GVAR_activeTargets", _targets];
};

// =========================
// Release a target from the gun's claim
// =========================
ETCS_fnc_releaseTarget = {
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
ETCS_fnc_isTargetClaimed = {
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
// Handle gun depletion (unassign crew, move to guard position, optionally disable gun)
// =========================
ETCS_fnc_handleGunDepletion = {
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

ETCS_fnc_getIndexOfGroup = {
	params ["_group"];

	switch (toLower(groupId _group)) do {
		case "alpha" : {
			[1, 6]
		};
		case "bravo" : {
			[2, 7]
		};
		case "charlie" : {
			[3, 8]
		};
		case "delta" : {
			[4, 9]
		};
		case "echo" : {
			[5, 10]
		};
		default {
			[11, 12]
		};
	};
};

// fire the gun at a target position with optional accuracy radius
// =========================
ETCS_fnc_fireGun = {
	params ["_caller", "_gun", "_targetPos", "_accuracyRadius", "_ammoType", "_rounds"];
	private _ammoLeft = [_gun, _ammoType] call ETCS_fnc_getAmmoCount;
	if (!canFire _gun || (_ammoLeft == 0)) exitWith {
		false
	};

	if (_ammoLeft < _rounds) then {
		_rounds = _ammoLeft;
	};

	private _finalPos = _targetPos;
	// Create temporary "X" marker
	private _marker = [_caller, _finalPos] call (_gun getVariable GUN_MARKER_CALLBACK);

	if (_accuracyRadius > 0) then {
		private _angle = random 360;
		private _dist = random _accuracyRadius;
		_finalPos = _targetPos vectorAdd [(sin _angle * _dist), (cos _angle * _dist), 0];
	};
	// Choose a responder (gunner or commander)
	private _base = [group _gun] call ETCS_fnc_getQuietUnit;
	private _grid = mapGridPosition _finalPos;

	// --- 1. Standby call ---
	[_caller, _base, GUN_BARRAGE_PHASE_REQUEST, _grid] call (_gun getVariable GUN_FIRE_CALLBACK);

	// --- 2. fire the artillery ---
	private _canReach = _finalPos inRangeOfArtillery [[_gun], _ammoType];
	if (!_canReach) exitWith {
		[_caller, _base, GUN_BARRAGE_PHASE_INVALID_RANGE] call (_gun getVariable GUN_FIRE_CALLBACK);
		deleteMarker _marker;
		false
	};

	// Variable to track for first projectile to hit the ground
	// to sync when calling "Splash out"
	_gun setVariable ["splashed", false, true];
	// list of number of shells to hit the ground to sync when
	// when calling Rounds complete
	_gun setVariable ["firedShells", [], true];

	private _eventIndex = _gun addEventHandler ["Fired", {
		params ["_unit", "_weapon", "_muzzle", "_mode", "_ammo", "_mag", "_projectile"];

		[_projectile, _unit] spawn {
			params ["_proj", "_unit"];

			while { !isNull _proj && alive _proj } do {
				sleep 0.1;
			};
			if !(_unit getVariable ["splashed", false]) then {
				_unit setVariable ["splashed", true, true];
			};

			private _shells = _unit getVariable ["firedShells", []];
			_shells pushBack _proj;
			_unit setVariable ["firedShells", _shells];
		};
	}];
	_gun doArtilleryFire [_finalPos, _ammoType, _rounds];

	// --- 3. Shot call ---
	[_caller, _base, GUN_BARRAGE_PHASE_SHOT] call (_gun getVariable GUN_FIRE_CALLBACK);

	// call splash after the first shell hits the ground.
	while { !(_gun getVariable ["splashed", false]) } do {
		sleep 0.1;
	};
	[_caller, _base, GUN_BARRAGE_PHASE_SPLASH] call (_gun getVariable GUN_FIRE_CALLBACK);

	// call rounds complete until all projectiles hit the ground.
	while { (count (_gun getVariable ["firedShells", []])) < _rounds } do {
		sleep 0.1;
	};
	[_caller, _base, GUN_BARRAGE_PHASE_DONE] call (_gun getVariable GUN_FIRE_CALLBACK);

	deleteMarker _marker;

	_gun removeEventHandler["Fired", _eventIndex];
	true
};

// =========================
// Enemy Selection Logic
// =========================
ETCS_fnc_selectEnemiesByMode = {
	params ["_mode", "_scoutGroup", "_gun", "_detectionRange"];

	private _enemies = [];
	private _group = grpNull;

	switch (_mode) do {
		case MODE_SCOUT: {
			private _gunSide = [_gun] call ETCS_fnc_getObserverSide;
			private _scoutLeader = leader _scoutGroup;
			if (isNull _scoutLeader || !alive _scoutLeader) exitWith {
				[[], grpNull]
			};

			private _allUnits = [_gun] call ETCS_fnc_getAllEnemies;
			_enemies = _allUnits select {
				_scoutLeader knowsAbout _x > 1.5
			};
			if (_enemies isEqualTo []) exitWith {
				[[], grpNull]
			};
			_group = group _scoutLeader;
		};
		case MODE_AUTO: {
			_enemies = [_gun, _detectionRange] call ETCS_fnc_getNearEnemies;
			if (_enemies isEqualTo []) exitWith {
				[[], grpNull]
			};
			_group = group _gun;
		};
		default {
			hint format["Invalid mode specified. Use MODE_SCOUT, MODE_AUTO or MODE_MAP."];
			[[], grpNull]
		};
	};

	[_enemies, _group]
};

// =========================
// lock / Unlock System
// =========================
ETCS_fnc_lockOnGoingFire = {
	missionNamespace setVariable ["onGoingGunFire", true, true];
};

ETCS_fnc_unlockOnGoingFire = {
	missionNamespace setVariable ["onGoingGunFire", false, true];
};

ETCS_fnc_isOnGoingFire = {
	missionNamespace getVariable ["onGoingGunFire", false]
};

// =========================
// Gun Index Assignment
// =========================
ETCS_fnc_assignGunIndex = {
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
ETCS_fnc_handleAutoOrScoutMode = {
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

		private _ammoType = [_gun] call ETCS_fnc_getArtilleryAmmoType;
		private _clusterMergeRadius = 10;   // minimum separation to treat clusters as unique

		_gun setVehicleAmmo 1;

		while { !isNull _gun && alive _gun } do {
			sleep 2;

			private _dynamicAccuracyRadius = [_gun, _accuracyRadius] call ETCS_fnc_dynamicAccuracyRadius;
			private _ammoLeft = [_gun, _ammoType] call ETCS_fnc_getAmmoCount;
			if (_ammoLeft <= 0) then {
				if (_unlimitedAmmo) then {
					_gun setVehicleAmmo 1
				} else {
					[_gun] call ETCS_fnc_handleGunDepletion;
					break
				};
			};

			private _enemiesAndGroup = [_mode, _scoutGroup, _gun, _detectionRange] call ETCS_fnc_selectEnemiesByMode;
			if (_enemiesAndGroup isEqualTo [[], grpNull]) then {
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
				private _cluster = [_x, _clusterRadius, _gun] call ETCS_fnc_getCluster;
				if (count _cluster >= _minUnitsPerCluster) then {
					private _centerPos = [_cluster] call ETCS_fnc_getClusterCenter;
					private _isDuplicate = [_centerPos, _clustersChecked, _clusterMergeRadius] call ETCS_fnc_isClusterDuplicate;

					if (_isDuplicate) then {
						continue
					};

					_clustersChecked pushBack _centerPos;

					if (!([_centerPos, _claimRadius] call ETCS_fnc_isTargetClaimed)) then {
						[_centerPos, _gun] call ETCS_fnc_claimTarget;

						private _quietUnit = [_group] call ETCS_fnc_getQuietUnit;
						private _fired = [_quietUnit, _gun, _centerPos, _dynamicAccuracyRadius, _ammoType, _rounds] call ETCS_fnc_fireGun;
						if (_fired) then {
							sleep _coolDownForEffect;
						};

						[_gun] call ETCS_fnc_releaseTarget;
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
ETCS_fnc_handleMapMode = {
	params [
		"_gun",
		"_rounds",
		"_unlimitedAmmo",
		"_accuracyRadius"
	];

	missionNamespace setVariable ["onGoingGunFire", false, true];
	[_gun] call ETCS_fnc_assignGunIndex;
	addMissionEventHandler [
		"MapSingleClick",
		{
			params ["_units", "_pos", "_alt", "_shift", "_thisArgs"];
			_thisArgs params ["_gun", "_rounds", "_unlimitedAmmo", "_accuracyRadius"];

			if (!([] call ETCS_fnc_isOnGoingFire)) then {
				[_gun, _rounds, _unlimitedAmmo, _accuracyRadius, _pos] spawn {
					params ["_gun", "_rounds", "_unlimitedAmmo", "_accuracyRadius", "_pos"];

					[] call ETCS_fnc_lockOnGoingFire;
					[_pos, _gun] call ETCS_fnc_claimTarget;

					private _dynamicAccuracyRadius = [_gun, _accuracyRadius] call ETCS_fnc_dynamicAccuracyRadius;
					private _ammoType = [_gun] call ETCS_fnc_getArtilleryAmmoType;

					if (_unlimitedAmmo) then {
						_gun setVehicleAmmo 1;
					};
					// We use the gun's index as a delay so that they won't fire at the same time.
					// This is needed since this script can be attached into multiple guns.
					private _thisDelay = _gun getVariable["gunIndex", 0];
					sleep _thisDelay;
					private _fired = [player, _gun, _pos, _dynamicAccuracyRadius, _ammoType, _rounds] call ETCS_fnc_fireGun;

					if (!_fired) then {
						hint "Gun fire failed!";
					};

					[_gun] call ETCS_fnc_releaseTarget;
					[] call ETCS_fnc_unlockOnGoingFire;
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
// Callbacks
// =========================
ETCS_fnc_registerArtilleryCallBacks = {
	params ["_unit"];
	// if this callback is not defined, there will be no radio sounds.
	// The artillery/mortar will continue to do its job
	_unit setVariable [GUN_FIRE_CALLBACK, {
		params ["_requestor", "_responder", "_phase", "_grid"];
		private _index = [group _requestor] call ETCS_fnc_getIndexOfGroup;

		switch (_phase) do {
			case GUN_BARRAGE_PHASE_REQUEST: {
				private _request = selectRandom [
					format ["ArtyRequest%1", _index select 0],
					format ["CUPArtyRequestHE%1", _index select 0],
					format ["CUPArtyRequestWP%1", _index select 0]
				];
				[_requestor, _request, 3] call ETCS_fnc_callSideRadio;
			};
			case GUN_BARRAGE_PHASE_SHOT : {
				private _response = selectRandom [
					format["ArtyResponse%1", _index select 1],
					format["ArtyResponse%1_%1", _index select 1, _index select 1],
					format["ArtyResponse%1_%1_%1", _index select 1, _index select 1, _index select 1],
					format["ArtyResponse%1_%1_%1_%1", _index select 1, _index select 1, _index select 1, _index select 1]
				];
				[_responder, _response, 2] call ETCS_fnc_callSideRadio;
			};
			case GUN_BARRAGE_PHASE_SPLASH : {
				[_responder, format["ArtySplash%1", _index select 1], 1] call ETCS_fnc_callSideRadio;
			};
			case GUN_BARRAGE_PHASE_DONE : {
				[_responder, format["ArtyComplete%1", _index select 1], 1] call ETCS_fnc_callSideRadio;
			};
			case GUN_BARRAGE_PHASE_INVALID_RANGE :{
				[_responder, format["ArtyRangeError%1", _index select 1], 3] call ETCS_fnc_callSideRadio;
			};
			default {
				systemChat format ["Invalid artillery call phase: %1", _phase];
			};
		};
	}];

	_unit setVariable [GUN_MARKER_CALLBACK, {
		params ["_requestor", "_targetPos"];

		private _markerId = format ["artilleryMarker_%1", diag_tickTime];
		private _marker = createMarker [_markerId, _targetPos];
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
			case "echo": {
				_marker setMarkerColor "ColorOrange";
			};
			default {
				_marker setMarkerColor "ColorWhite";
			};
		};
		_marker setMarkerText format["Fire Mission %1 [%2]", groupId (group _requestor), mapGridPosition _targetPos];
		["SmokeShellOrange", _targetPos, 50, 3] call ETCS_fnc_spawnSmoke;

		_marker
	}];
};

// =========================
// Main Script Entry
// =========================
switch (_mode) do {
	case MODE_AUTO;
	case MODE_SCOUT: {
		[_gun] call ETCS_fnc_registerArtilleryCallBacks;
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
		] call ETCS_fnc_handleAutoOrScoutMode;
	};

	case MODE_MAP: {
		[_gun] call ETCS_fnc_registerArtilleryCallBacks;
		[
			_gun,
			_rounds,
			_unlimitedAmmo,
			_accuracyRadius
		] call ETCS_fnc_handleMapMode;
	};

	default {
		hint format ["Invalid Mode used: %1", _mode];
	};
};