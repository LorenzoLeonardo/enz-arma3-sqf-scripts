// Script: autoMortarRounds.sqf
// Usage: [mortar1, 600, 8] execVM "autoMortarRounds.sqf";

private _mortar = _this select 0;
private _detection_distance = _this select 1;
private _rounds = _this select 2;

[_mortar, _detection_distance, _rounds] spawn {
    params ["_mortar", "_detection_distance", "_rounds"];
    private _radiusCheck = _detection_distance; // How close enemy must be
    private _targetRadius = 50;               // Spread of fire around target
    private _ammoType = "8Rnd_82mm_Mo_shells"; // Default 82mm HE rounds

    // Refill ammo to 100%
    _mortar setVehicleAmmo 1;

    while {alive _mortar} do {
        sleep 3;

        // Check if mortar still has ammo
        private _ammoLeft = 0;
        {
            if (_x select 0 == _ammoType) then {
                _ammoLeft = _x select 1;
            };
        } forEach magazinesAmmo _mortar;

        if (_ammoLeft <= 0) then {
            // Dismount crew when out of ammo
            {
                unassignVehicle _x;
                _x action ["GetOut", _mortar];
            } forEach crew _mortar;
            break; // stop script since no ammo left
        };

        // Find all enemy infantry (OPFOR) within 300m of the mortar
        private _enemies = (getPos _mortar) nearEntities ["Man", _radiusCheck];
        _enemies = _enemies select {side _x == east};

        if (count _enemies > 0) then {
            private _enemy = _enemies select 0;  // Take the first enemy found

            if (!isNull _enemy && {_mortar distance _enemy < _radiusCheck}) then {
                private _targetPos = getPos _enemy;

                // Add random scatter for realism
                private _angle = random 360;
                private _dist = random _targetRadius;
                private _scatterPos = [
                    (_targetPos select 0) + (sin _angle * _dist),
                    (_targetPos select 1) + (cos _angle * _dist),
                    0
                ];

                // Only fire if mortar can actually shoot
                if (canFire _mortar) then {
                    _mortar doArtilleryFire [_scatterPos, _ammoType, _rounds];
                };
            };
        };
    };
};