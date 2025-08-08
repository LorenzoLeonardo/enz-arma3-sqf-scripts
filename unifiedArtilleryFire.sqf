// ==============================================================================================================
// Unified Artillery fire Script
// Author: Lorenzo Leonardo
// Contact: enzotechcomputersolutions@gmail.com
// ==============================================================================================================
// 
// Description:
// This script provides flexible AI-controlled mortar and artillery fire support in two modes:
//     SCOUT - Fires only when a designated scout group's leader detects and identifies enemies.
//     AUTO  - Automatically scans for enemy unit clusters within a set detection range of the gun.
// It unifies both functionalities into one configurable system.
// 
// Features:
// - SCOUT mode: Fires based on a scout leader's spotted enemies.
// - AUTO mode: Continuously scans for enemy clusters within detection range.
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
// [this, 10000, 8, 50, 8, 60, true, 25, 50] execVM "unifiedArtilleryFire.sqf"; (AUTO mode)
// [this, group, 8, 50, 8, 60, true, 25, 50] execVM "unifiedArtilleryFire.sqf"; (SCOUT mode)
// 
// ==============================================================================================================

// =====================
// Parameters
// =====================

// _gun = the artillery or mortar gun object
private _gun = _this param [0];
// _genericParam = either a number for AUTO mode or an object for SCOUT mode
private _genericParam = _this select 1;
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
// _accuracyRadius = Optional accuracy radius for mortar fire, if not specified, defaults to 0 (no scatter)
private _accuracyRadius = _this param [7, 0];
// _claimRadius = distance to avoid firing if target is claimed by another gun (default: 50 meters)
private _claimRadius = _this param [8, 50];

// =====================
// Initialization either AUTO Mode or SCOUT Mode
// =====================
// _mode = "SCOUT" or "AUTO"
private _mode = "AUTO";
// _detectionRange = Radial distance from the gun used to detect enemy units in AUTO mode (default: 800 meters). Applicable in AUTO mode only.
private _detectionRange = 800;
// _scoutGroup = group doing the spotting. Applicable in SCOUT mode only.
private _scoutGroup = objNull;

switch (typeName _genericParam) do {
	case "SCALAR": {
		sleep 3; // Allow time for the gun to initialize
		_mode = "AUTO";
		_detectionRange = _genericParam;
		_scoutGroup = objNull; // No scout group in AUTO mode
		hint format ["Artillery AUTO mode activated with detection range: %1 meters", _detectionRange];
	};
	case "GROUP": {
		sleep 3; // Allow time for the gun to initialize
		_mode = "SCOUT";
		_detectionRange = 0; // No detection range in SCOUT mode
		_scoutGroup = _genericParam; // Use the provided object as the scout group
		hint format ["Artillery SCOUT mode activated with scout group: %1", groupId _scoutGroup];
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
// Get the ammo count for a specific ammo type in a vehicle
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
// Get the side of the gun based on its crew or default side
// =========================
fnc_getGunSide = {
	params ["_gun"];
	if (crew _gun isNotEqualTo []) exitWith {
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
// Get enemies near a position within a specified distance
// =========================
fnc_getEnemies = {
	params ["_origin", "_distance", "_gun"];
	private _gunSide = [_gun] call fnc_getGunSide;
	(_origin nearEntities ["Man", _distance]) select {
		[_x, _gunSide] call fnc_isHostile
	}
};

// =========================
// Get a cluster of hostile units around a unit within a specified radius
// =========================
fnc_getCluster = {
	params ["_unit", "_radius", "_gun"];
	private _gunSide = [_gun] call fnc_getGunSide;
	(getPos _unit nearEntities ["Man", _radius]) select {
		[_x, _gunSide] call fnc_isHostile
	}
};

// =========================
// Get the center position of a cluster of units
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
// Fire the gun at a target position with optional accuracy radius
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
	private _markerId = format ["artilleryMarker_%1", diag_tickTime];
	private _marker = createMarker [_markerId, _finalPos];
	_marker setMarkerShape "ICON";
	_marker setMarkerType "mil_warning";
	_marker setMarkerColor "ColorRed";
	_marker setMarkerText format["Fire Mission %1!!!", groupId (group _caller)];

	// --- 1. Standby call ---
	_caller sideRadio "RadioArtilleryRequest"; // plays sound
	_caller sideChat format ["Requesting immediate artillery at the designated coordinates [%1]. Over!", _grid];
	sleep 3;  // small delay before firing

	// --- 2. fire the artillery ---
	_gun doArtilleryFire [_finalPos, _ammoType, _rounds];

	// --- 3. Shot call ---
	sleep 2;
	_base sideRadio "RadioArtilleryResponse";

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
	_base sideRadio "RadioArtillerySplash";

	// --- 5. Rounds Complete (after impact) ---
	sleep (_flightTime + 2);
	_base sideRadio "RadioArtilleryRoundsComplete";

	deleteMarker _marker;
	true
};

// =========================
// Get the artillery ammo type based on gun type
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
	_clustersChecked findIf {
		private _pos = _x;
		_centerPos distance2D _pos < _mergeRadius
	} > -1
};

// =========================
// Get a quiet unit from the group
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

	switch (toLower _mode) do {
		case "scout": {
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
		case "auto": {
			_enemies = [getPos _gun, _detectionRange, _gun] call fnc_getEnemies;
			if (_enemies isEqualTo []) exitWith {
				[[], objNull]
			};
			_group = group _gun;
		};
		default {
			hint format["Invalid mode specified. Use 'SCOUT' or 'AUTO'."];
			[[], objNull]
		};
	};

	[_enemies, _group]
};

// =========================
// Main Loop (spawned)
// =========================
[_mode, _gun, _detectionRange, _scoutGroup, _rounds, _clusterRadius, _minUnitsPerCluster, _coolDownForEffect, _unlimitedAmmo, _accuracyRadius, _claimRadius] spawn {
	params ["_mode", "_gun", "_detectionRange", "_scoutGroup", "_rounds", "_clusterRadius", "_minUnitsPerCluster", "_coolDownForEffect", "_unlimitedAmmo", "_accuracyRadius", "_claimRadius"];

	private _ammoType = [_gun] call fnc_getArtilleryAmmoType;
	private _clusterMergeRadius = 10;   // minimum separation to treat clusters as unique

	_gun setVehicleAmmo 1;

	while { !isNull _gun && alive _gun } do {
		sleep 2;

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
					private _fired = [_quietUnit, _gun, _centerPos, _accuracyRadius, _ammoType, _rounds] call fnc_fireGun;
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