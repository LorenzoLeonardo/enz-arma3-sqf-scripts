// ==============================================================================================================
// Auto Artillery fire Script
// Author: Lorenzo Leonardo
// Contact: enzotechcomputersolutions@gmail.com
// ==============================================================================================================
// 
// Description:
// This script automates mortar and artillery fire support by detecting enemy unit clusters
// within a configurable range and engaging them with indirect fire. It is designed to handle
// multiple guns, prevent redundant targeting, and support both mortars and heavy artillery.
// 
// Features:
// - Automatically scans for enemy clusters within a specified detection distance.
// - Identifies and prioritizes clusters based on unit density.
// - Fires a customizable number of rounds with optional accuracy dispersion.
// - Avoids duplicate strikes by coordinating with other active guns.
// - Supports both limited and unlimited ammunition modes.
// - Can automatically disable and redeploy gun crews when ammunition is depleted.
// 
// Parameters:
//   [ _gun, _detection_distance, _rounds, _cluster_radius, _min_units_per_cluster,
//     _cooldown_time, _unlimited_ammo, _accuracy_radius ]
// 
//   _gun                 - The mortar or artillery object to control.
//   _detection_distance  - max distance (in meters) to detect enemy units (default: 800).
//   _rounds              - Number of rounds to fire per cluster (default: 8).
//   _cluster_radius      - Radius (in meters) to group nearby enemies into a cluster (default: 50).
//   _min_units_per_cluster - Minimum number of units in a cluster before engaging (default: 8).
//   _cooldown_time       - Delay (in seconds) between volleys (default: 60).
//   _unlimited_ammo      - Boolean; true to allow infinite resupply (default: false).
//   _accuracy_radius     - Scatter radius (in meters) for shot inaccuracy (default: 0 = perfect aim).
// 
// Usage Example:
//     [this, 1000, 8, 50, 8, 60, true, 25] execVM "autoArtilleryFire.sqf";
// 
// This will make the assigned artillery gun:
// - Scan for enemies within 1000m,
// - Engage clusters of 8+ units within a 50m radius,
// - fire 8 rounds per strike with a 25m accuracy dispersion,
// - Pause 60 seconds between strikes,
// - and automatically resupply its ammunition.
// 
// ==============================================================================================================

// =====================
// Parameters
// =====================

// _gun = the artillery or mortar gun object
private _gun = _this param [0];
// _detection_distance = distance to detect enemy units (default: 800 meters)
private _detection_distance = _this param [1, 800];
// _rounds = number of rounds to fire at each cluster (default: 8)
private _rounds = _this param [2, 8];
// _cluster_radius = radius to consider a cluster of enemies (default: 50 meters)
private _cluster_radius = _this param [3, 50];
// _min_units_per_cluster = number of enemy units in a cluster to fire at (default: 8)
private _min_units_per_cluster = _this param [4, 8];
// _cool_down_for_effect = cooldown time between firing rounds (default: 60 seconds)
private _cool_down_for_effect = _this param [5, 60];
// _unlimited_ammo = whether to use unlimited ammo (default: qfalse)
private _unlimited_ammo = _this param [6, false];
// _accuracy_radius = Optional accuracy radius for mortar fire, if not specified, defaults to 0 (no scatter)
private _accuracy_radius = _this param [7, 0];

// =========================
// Global Target Registry
// =========================
if (isNil {
	missionNamespace getVariable "GVAR_activeTargets"
}) then {
	missionNamespace setVariable ["GVAR_activeTargets", []];
};

// Helper for adding/removing targets (MP-safe if needed)
fnc_claimTarget = {
	params ["_pos", "_gun"];
	private _targets = missionNamespace getVariable ["GVAR_activeTargets", []];
	_targets pushBack [_pos, _gun];
	missionNamespace setVariable ["GVAR_activeTargets", _targets];
};

fnc_releaseTarget = {
	params ["_gun"];
	private _targets = missionNamespace getVariable ["GVAR_activeTargets", []];
	_targets = _targets select {
		(_x select 1) != _gun
	};
	missionNamespace setVariable ["GVAR_activeTargets", _targets];
};

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
// Utility Functions
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

fnc_getGunSide = {
	params ["_gun"];
	if (crew _gun isNotEqualTo []) exitWith {
		side (gunner _gun)
	};
	side _gun
};

fnc_isHostile = {
	params ["_unit", "_gunSide"];
	alive _unit && ((side _unit getFriend _gunSide) < 0.6 || (_gunSide getFriend side _unit) < 0.6)
};

fnc_getEnemies = {
	params ["_origin", "_distance", "_gun"];
	private _gunSide = [_gun] call fnc_getGunSide;
	(_origin nearEntities ["Man", _distance]) select {
		[_x, _gunSide] call fnc_isHostile
	}
};

fnc_getCluster = {
	params ["_unit", "_radius", "_gun"];
	private _gunSide = [_gun] call fnc_getGunSide;
	(getPos _unit nearEntities ["Man", _radius]) select {
		[_x, _gunSide] call fnc_isHostile
	}
};

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

fnc_fireGun = {
	params ["_gun", "_targetPos", "_accuracy_radius", "_ammoType", "_rounds"];
	if (!canFire _gun) exitWith {
		false
	};

	private _finalPos = _targetPos;
	if (_accuracy_radius > 0) then {
		private _angle = random 360;
		private _dist = random _accuracy_radius;
		_finalPos = [
			(_targetPos select 0) + (sin _angle * _dist),
			(_targetPos select 1) + (cos _angle * _dist),
			0
		];
	};
	// Choose a caller (gunner or commander)
	private _caller = if (!isNull (gunner _gun)) then {
		gunner _gun
	} else {
		commander _gun
	};
	if (isNull _caller) exitWith {
		false
	};
	private _grid = mapGridPosition _finalPos;

	// Create temporary "X" marker
	private _markerId = format ["artilleryMarker_%1", diag_tickTime];
	private _marker = createMarker [_markerId, _centerPos];
	_marker setMarkerShape "ICON";
	_marker setMarkerType "mil_end";
	_marker setMarkerColor "ColorBlue";
	_marker setMarkerText "FIRE MISSION";

	// --- 1. Standby call ---
	playSound "ReadoutClick";
	_caller sideChat format [
		"%1: Alpha Battery, fire mission, grid %2, standby, over.",
		name _caller, _grid
	];

	sleep 3;  // small delay before firing

	// --- 2. fire the artillery ---
	_gun doArtilleryFire [_finalPos, _ammoType, _rounds];

	// --- 3. Shot call ---
	playSound "ReadoutClick";
	_caller sideChat format ["%1: Shot, over!", name _caller];

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
	playSound "ReadoutClick";
	_caller sideChat format ["%1: Splash, out!", name _caller];

	// --- 5. Rounds Complete (after impact) ---
	sleep 5;
	playSound "ReadoutClick";
	_caller sideChat format ["%1: Rounds complete!", name _caller];

	deleteMarker _marker;
	true
};

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

fnc_isClusterDuplicate = {
	params ["_centerPos", "_clustersChecked", "_mergeRadius"];
	_clustersChecked findIf {
		private _pos = _x;
		_centerPos distance2D _pos < _mergeRadius
	} > -1
};

// =========================
// Main Loop (spawned)
// =========================
[_gun, _detection_distance, _rounds, _cluster_radius, _min_units_per_cluster, _cool_down_for_effect, _unlimited_ammo, _accuracy_radius] spawn {
	params ["_gun", "_detection_distance", "_rounds", "_cluster_radius", "_min_units_per_cluster", "_cool_down_for_effect", "_unlimited_ammo", "_accuracy_radius"];

	private _ammoType = [_gun] call fnc_getArtilleryAmmoType;
	private _claimRadius = 200;         // distance to avoid firing if target is claimed (other guns)
	private _clusterMergeRadius = 10;   // minimum separation to treat clusters as unique

	_gun setVehicleAmmo 1;

	while { !isNull _gun && alive _gun } do {
		sleep 2;

		private _ammoLeft = [_gun, _ammoType] call fnc_getAmmoCount;
		if (_ammoLeft <= 0) then {
			if (_unlimited_ammo) then {
				_gun setVehicleAmmo 1
			} else {
				[_gun] call fnc_handleGunDepletion;
				break
			};
		};

		private _enemies = [getPos _gun, _detection_distance, _gun] call fnc_getEnemies;
		if (_enemies isEqualTo []) then {
			continue
		};

		private _clustersChecked = [];
		{
			private _cluster = [_x, _cluster_radius, _gun] call fnc_getCluster;
			if (count _cluster >= _min_units_per_cluster) then {
				private _centerPos = [_cluster] call fnc_getClusterCenter;
				private _isDuplicate = [_centerPos, _clustersChecked, _clusterMergeRadius] call fnc_isClusterDuplicate;

				if (_isDuplicate) then {
					continue
				};

				_clustersChecked pushBack _centerPos;

				if (!([_centerPos, _claimRadius] call fnc_isTargetClaimed)) then {
					[_centerPos, _gun] call fnc_claimTarget;

					private _fired = [_gun, _centerPos, _accuracy_radius, _ammoType, _rounds] call fnc_fireGun;
					if (_fired) then {
						sleep _cool_down_for_effect;
					};

					[_gun] call fnc_releaseTarget;
					// one cluster per loop
					break;
				};
			};
		} forEach _enemies;
	};
};