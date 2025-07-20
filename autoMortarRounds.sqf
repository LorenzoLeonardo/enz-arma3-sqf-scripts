// Script: autoMortar.sqf
// Usage: [mortar1] execVM "autoMortar.sqf";  // pass your mortar as param

private _mortar = _this select 0;
private _detection_distance = _this select 1;
private _rounds = _this select 2;

[_mortar, _detection_distance, _rounds] spawn {
    params ["_mortar", "_detection_distance", "_rounds"];
    private _radiusCheck = _detection_distance; // How close enemy must be
    private _targetRadius = 50;               // Spread of fire around target
    private _ammoType = "8Rnd_82mm_Mo_shells"; // Default 82mm HE rounds

    while {alive _mortar} do {
        sleep 3;

        // Find all enemy infantry (OPFOR) within 300m of the mortar
        private _enemies = (getPos _mortar) nearEntities ["Man", _radiusCheck];
        _enemies = _enemies select {side _x == east};

        if (count _enemies > 0) then {
            private _enemy = _enemies select 0;  // Take the first enemy found

            // Refill ammo so it never runs out
            _mortar setVehicleAmmo 1;

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