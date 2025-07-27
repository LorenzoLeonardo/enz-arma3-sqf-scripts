// ============================================
// Created by Lorenzo Leonardo
// Email: enzotechcomputersolutions@gmail.com
// ============================================

// ==============================================================================================================
// This script automatically fires artillery/mortar rounds at enemy clusters.
// It detects enemy clusters within a specified radius and fires a specified number of rounds at each cluster.
// The script can be customized with parameters such as detection distance, number of rounds, cluster radius,
// number of enemy clusters, cooldown time, and whether to use unlimited ammo.
// ==============================================================================================================

// ======================================================================
// Usage: [this, 1000, 8, 50, 8, 60, true, 0] execVM "autoArtilleryFire.sqf";
// ======================================================================

// _gun = the artillery or mortar gun object
private _gun = _this select 0;

// _detection_distance = distance to detect enemy units (default: 800 meters)
private _detection_distance = if (count _this > 1) then {
	_this select 1
} else {
	800
};

// _rounds = number of rounds to fire at each cluster (default: 8)
private _rounds = if (count _this > 2) then {
	_this select 2
} else {
	8
};

// _cluster_radius = radius to consider a cluster of enemies (default: 50 meters)
private _cluster_radius = if (count _this > 3) then {
	_this select 3
} else {
	50
};

// _number_enemy_clusters = number of enemy clusters to fire at (default: 8)
private _number_enemy_clusters = if (count _this > 4) then {
	_this select 4
} else {
	8
};

// _cool_down_for_effect = cooldown time between firing rounds (default: 60 seconds)
private _cool_down_for_effect = if (count _this > 5) then {
	_this select 5
} else {
	60
};

// _unlimited_ammo = whether to use unlimited ammo (default: false)
private _unlimited_ammo = if (count _this > 6) then {
	_this select 6
} else {
	false
};

// _accuracy_radius = Optional accuracy radius for mortar fire, if not specified, defaults to 0 (no scatter)
private _accuracy_radius = if (count _this > 7) then {
	_this select 7
} else {
	0
};

// =========================
// Helper Functions (GLOBAL)
// =========================
fnc_getAmmoCount = {
	params ["_vehicle", "_ammoType"];
	private _count = 0;
	{
		if (_x select 0 == _ammoType) exitWith {
			_count = _x select 1
		}
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

	// Optional: Destroy the gun (comment out if not needed)
	_gun setDamage 1;

	private _guardPos = (getPos _gun) getPos [30 + random 20, random 360];
	_crewgroup move _guardPos;
	private _wp = _crewgroup addWaypoint [_guardPos, 0];
	_wp setWaypointType "GUARD";
	_wp setWaypointBehaviour "AWARE";
	_wp setWaypointSpeed "FULL";
	_wp setWaypointCombatMode "GREEN";
};

fnc_getEnemies = {
	params ["_origin", "_distance"];
	private _enemies = (_origin) nearEntities ["Man", _distance];
	_enemies select {
		alive _x && {
			side _x == east
		}
	}
};

fnc_getCluster = {
	params ["_unit", "_radius"];
	private _cluster = (getPos _unit) nearEntities ["Man", _radius];
	_cluster select {
		alive _x && {
			side _x == east
		}
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
		_sumY = _sumY + (_pos select 1);
	} forEach _cluster;
	[_sumX / (count _cluster), _sumY / (count _cluster), 0]
};

fnc_fireGun = {
	params ["_gun", "_targetPos", "_accuracy_radius", "_ammoType", "_rounds"];
	if (!canFire _gun) exitWith {
		false
	};

	private _finalPos = _targetPos;

	// Only add scatter if the radius is greater than zero
	if (_accuracy_radius > 0) then {
		private _angle = random 360;
		        private _dist = random _accuracy_radius;  // Scatter range
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

	// Mapping of specific weapons to ammo types
	private _ammoMap = [
		        // Vanilla
		        ["B_gun_01_F", "8Rnd_82mm_Mo_shells"], // NATO mortar
		        ["B_G_gun_01_F", "8Rnd_82mm_Mo_shells"], // Guerrilla mortar
		        ["B_G_Offroad_01_AT_F", "8Rnd_82mm_Mo_shells"], // Improvised/Light

		        // CUP Mortars
		        ["CUP_B_M252_US", "8Rnd_82mm_Mo_shells"], // CUP US M252 mortar
		        ["CUP_O_2b14_82mm_RU", "8Rnd_82mm_Mo_shells"], // CUP RU 82mm mortar

		        // CUP Artillery (M119, D30, etc.)
		        ["CUP_B_M119_US", "32Rnd_155mm_Mo_shells"], // CUP M119 howitzer
		        ["CUP_O_D30_RU", "32Rnd_155mm_Mo_shells"], // CUP D-30 howitzer
		        ["CUP_O_D30_TK", "32Rnd_155mm_Mo_shells"], // CUP D-30 (Takistan)
		        ["CUP_B_L119_US", "32Rnd_155mm_Mo_shells"]  // CUP L119 (UK variant)
	];

	    // default ammo type
	private _ammoType = "8Rnd_82mm_Mo_shells";

	    // Look up specific match
	private _index = _ammoMap findIf {
		_gun isKindOf (_x select 0)
	};
	if (_index > -1) then {
		_ammoType = _ammoMap select _index select 1;
	} else {
		// Fallback for any unlisted static weapons
		if (_gun isKindOf "StaticMortar") then {
			_ammoType = "8Rnd_82mm_Mo_shells";
		} else {
			if (_gun isKindOf "StaticCannon") then {
				_ammoType = "CUP_30Rnd_105mmHE_M119_M"; // default for static cannons
			} else {
				// if no specific match, use a generic artillery ammo type
				_ammoType = "8Rnd_82mm_Mo_shells";
			};
		};
	};

	_ammoType
};

// =========================
// Main Loop
// =========================
[_gun, _detection_distance, _rounds, _cluster_radius, _number_enemy_clusters, _cool_down_for_effect, _unlimited_ammo, _accuracy_radius]
spawn {
	params ["_gun", "_detection_distance", "_rounds", "_cluster_radius", "_number_enemy_clusters", "_cool_down_for_effect", "_unlimited_ammo", "_accuracy_radius"];

	// Auto find the ammo type based on the mortar or cannon
	private _ammoType = [_gun] call fnc_getArtilleryAmmoType;

	_gun setVehicleAmmo 1;

	while { alive _gun } do {
		sleep 1;

		private _ammoLeft = [_gun, _ammoType] call fnc_getAmmoCount;
		if (_ammoLeft <= 0) then {
			if (_unlimited_ammo) then {
				_gun setVehicleAmmo 1;
			} else {
				[_gun] call fnc_handleGunDepletion;
				break;
			};
		};

		private _enemies = [getPos _gun, _detection_distance] call fnc_getEnemies;
		if (count _enemies == 0) then {
			continue
		};

		private _fired_once = false;
		{
			private _cluster = [_x, _cluster_radius] call fnc_getCluster;
			if (count _cluster >= _number_enemy_clusters && !_fired_once) exitWith {
				private _centerPos = [_cluster] call fnc_getClusterCenter;
				private _fired = [_gun, _centerPos, _accuracy_radius, _ammoType, _rounds] call fnc_fireGun;
				if (_fired) then {
					_fired_once = true;
					sleep _cool_down_for_effect;
				};
			};
		} forEach _enemies;
	};
};