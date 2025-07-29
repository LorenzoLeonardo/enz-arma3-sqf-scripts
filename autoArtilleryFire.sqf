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

	_gun doArtilleryFire [_finalPos, _ammoType, _rounds];
	true
};

fnc_getArtilleryAmmoType = {
	params ["_gun"];
	private _ammoMap = [
		["B_gun_01_F", "8Rnd_82mm_Mo_shells"],
		["B_G_gun_01_F", "8Rnd_82mm_Mo_shells"],
		["B_G_Offroad_01_AT_F", "8Rnd_82mm_Mo_shells"],
		["CUP_B_M252_US", "8Rnd_82mm_Mo_shells"],
		["CUP_O_2b14_82mm_RU", "8Rnd_82mm_Mo_shells"],
		["CUP_B_M119_US", "32Rnd_155mm_Mo_shells"],
		["CUP_O_D30_RU", "32Rnd_155mm_Mo_shells"],
		["CUP_O_D30_TK", "32Rnd_155mm_Mo_shells"],
		["CUP_B_L119_US", "32Rnd_155mm_Mo_shells"]
	];

	private _ammoType = "8Rnd_82mm_Mo_shells";
	private _index = _ammoMap findIf {
		_gun isKindOf (_x select 0)
	};
	if (_index > -1) then {
		_ammoType = _ammoMap select _index select 1;
	} else {
		if (_gun isKindOf "StaticMortar") then {
			_ammoType = "8Rnd_82mm_Mo_shells";
		} else {
			if (_gun isKindOf "StaticCannon") then {
				_ammoType = "CUP_30Rnd_105mmHE_M119_M";
			};
		};
	};
	_ammoType
};

// =========================
// Main Loop (spawned)
// =========================
[_gun, _detection_distance, _rounds, _cluster_radius, _min_units_per_cluster, _cool_down_for_effect, _unlimited_ammo, _accuracy_radius] spawn {
	params ["_gun", "_detection_distance", "_rounds", "_cluster_radius", "_min_units_per_cluster", "_cool_down_for_effect", "_unlimited_ammo", "_accuracy_radius"];

	private _ammoType = [_gun] call fnc_getArtilleryAmmoType;
	_gun setVehicleAmmo 1;

	while { alive _gun } do {
		sleep 1;

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
				if (_centerPos in _clustersChecked) exitWith {};
				_clustersChecked pushBack _centerPos;

				if (!([_centerPos, 200] call fnc_isTargetClaimed)) then {
					[_centerPos, _gun] call fnc_claimTarget;

					private _fired = [_gun, _centerPos, _accuracy_radius, _ammoType, _rounds] call fnc_fireGun;
					if (_fired) then {
						sleep _cool_down_for_effect
					};

					[_gun] call fnc_releaseTarget;
					// one cluster per loop
					break;
				};
			};
		} forEach _enemies;
	};
};