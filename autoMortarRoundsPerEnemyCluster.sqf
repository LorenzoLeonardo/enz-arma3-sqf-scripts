// Usage: [this, 1000, 8, 50, 8, 60, true, 0] execVM "autoMortarRoundsPerEnemyCluster.sqf";

private _mortar = _this select 0;
private _detection_distance = if (count _this > 1) then {
	_this select 1
} else {
	800
};
private _rounds = if (count _this > 2) then {
	_this select 2
} else {
	8
};
private _cluster_radius = if (count _this > 3) then {
	_this select 3
} else {
	50
};
private _number_enemy_clusters = if (count _this > 4) then {
	_this select 4
} else {
	8
};
private _cool_down_for_effect = if (count _this > 5) then {
	_this select 5
} else {
	60
};
private _unlimited_ammo = if (count _this > 6) then {
	_this select 6
} else {
	false
};
// Optional: Accuracy radius for mortar fire, if not specified, defaults to 0 (no scatter)
// This can be used to add some randomness to the mortar fire.
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

fnc_handleMortarDepletion = {
	params ["_mortar"];
	if (isNull _mortar) exitWith {};

	private _crew = crew _mortar;
	if (count _crew == 0) exitWith {};

	private _crewgroup = group (_crew select 0);
	{
		unassignVehicle _x;
		_x action ["GetOut", _mortar];
	} forEach _crew;
	sleep 3;

	// Optional: Destroy the mortar (comment out if not needed)
	_mortar setDamage 1;

	private _guardPos = (getPos _mortar) getPos [30 + random 20, random 360];
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

fnc_fireMortar = {
	params ["_mortar", "_targetPos", "_accuracy_radius", "_ammoType", "_rounds"];
	if (!canFire _mortar) exitWith {
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

	_mortar doArtilleryFire [_finalPos, _ammoType, _rounds];
	true
};

// =========================
// Main Loop
// =========================
[_mortar, _detection_distance, _rounds, _cluster_radius, _number_enemy_clusters, _cool_down_for_effect, _unlimited_ammo, _accuracy_radius]
spawn {
	params ["_mortar", "_detection_distance", "_rounds", "_cluster_radius", "_number_enemy_clusters", "_cool_down_for_effect", "_unlimited_ammo", "_accuracy_radius"];

	private _ammoType = "8Rnd_82mm_Mo_shells";
	_mortar setVehicleAmmo 1;

	while { alive _mortar } do {
		sleep 3;

		private _ammoLeft = [_mortar, _ammoType] call fnc_getAmmoCount;
		if (_ammoLeft <= 0) then {
			if (_unlimited_ammo) then {
				_mortar setVehicleAmmo 1;
			} else {
				[_mortar] call fnc_handleMortarDepletion;
				break;
			};
		};

		private _enemies = [getPos _mortar, _detection_distance] call fnc_getEnemies;
		if (count _enemies == 0) then {
			continue
		};

		private _fired_once = false;
		{
			private _cluster = [_x, _cluster_radius] call fnc_getCluster;
			if (count _cluster >= _number_enemy_clusters && !_fired_once) exitWith {
				private _centerPos = [_cluster] call fnc_getClusterCenter;
				private _fired = [_mortar, _centerPos, _accuracy_radius, _ammoType, _rounds] call fnc_fireMortar;
				if (_fired) then {
					_fired_once = true;
					sleep _cool_down_for_effect;
				};
			};
		} forEach _enemies;
	};
};