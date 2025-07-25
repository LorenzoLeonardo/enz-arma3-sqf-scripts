// Script: autoMortarrounds.sqf
// Usage: [mortar1, 600, 8, "Alpha"] execVM "autoMortarrounds.sqf";

private _mortar = _this select 0;
private _detection_distance = _this select 1;
private _rounds = _this select 2;
private _enemy_group_name = _this select 3;

[_mortar, _detection_distance, _rounds, _enemy_group_name] spawn {
	params ["_mortar", "_detection_distance", "_rounds", "_enemy_group_name"];

	// Spread of fire around target
	private _targetradius = 50;
	// default 82mm HE rounds
	private _ammotype = "8Rnd_82mm_Mo_shells";

	// Refill ammo to 100%
	_mortar setVehicleAmmo 1;

	while { alive _mortar } do {
		sleep 3;

		// Check if mortar still has ammo
		private _ammoLeft = 0;
		{
			// Only check for the specified ammo type
			if (_x select 0 == _ammotype) then {
				// get the amount of ammo left
				_ammoLeft = _x select 1;
			};
		} forEach magazinesAmmo _mortar;

		if (_ammoLeft <= 0) then {
			private _crewgroup = group (crew _mortar select 0);

			// Dismount crew when out of ammo
			{
				unassignVehicle _x;
				_x action ["Getout", _mortar];
			} forEach crew _mortar;
			// Wait for them to actually exit before moving
			sleep 3;

			// Destroy the mortar
			_mortar setDamage 1;

			// find a position 30–50m away for them to guard
			private _guardPos = (getPos _mortar) getPos [30 + random 20, random 360];
			// Create a waypoint for the group
			private _wp = _crewgroup addWaypoint [_guardPos, 0];

			_wp setwaypointType "GUARD";
			_wp setwaypointBehaviour "STEALTH";
			_wp setwaypointSpeed "LIMITED";
			_wp setwaypointCombatMode "GREEN";

			// stop script since no ammo left
			break;
		};

		// find all enemy infantry (opfor) within _detection_distance of the mortar
		private _enemies = (getPos _mortar) nearEntities ["Man", _detection_distance];

		_enemies = _enemies select {
			// Only target this mortar to a specified enemy group
			side _x == east && groupId (group _x) == _enemy_group_name
		};

		if (count _enemies > 0) then {
			// Take the first enemy found
			private _enemy = _enemies select 0;

			if (!isNull _enemy && {
				_mortar distance _enemy < _detection_distance
			}) then {
				private _targetPos = getPos _enemy;
				// Add random scatter for realism
				private _angle = random 360;
				private _dist = random _targetradius;
				private _scatterPos = [
					(_targetPos select 0) + (sin _angle * _dist),
					(_targetPos select 1) + (cos _angle * _dist),
					0
				];

				// Only fire if mortar can actually shoot
				if (canFire _mortar) then {
					_mortar doArtilleryFire [_scatterPos, _ammotype, _rounds];
				};
			};
		};
	};
};