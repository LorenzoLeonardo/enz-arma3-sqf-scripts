/*
	    manageJeepCrew.sqf
	    Usage: [vehicle] execVM "manageJeepCrew.sqf";

	    Automatically replaces dead driver or turret crew with nearest available
	    group member not in a vehicle.

	    Works for:
	    - driver
	    - Any turret seat (supports multi-seat turrets)
*/

params ["_vehicle"];

fnc_isUnitGood = {
	!(isNull _x) && alive _x && lifeState _x != "INCAPACITATED"
};

// Helper function: get nearest available unit from the same group
fnc_getReplacement = {
	params ["_vehicle"];
	private _grp = group _vehicle;
	private _candidates = (units _grp) select {
		([_x] call fnc_isUnitGood) &&
		isNull objectParent _x &&
		!isPlayer _x
	};

	if (_candidates isEqualTo []) exitWith {
		objNull
	};

	private _nearest = objNull;
	private _nearestDist = 1e10;

	{
		private _dist = _x distance _vehicle;
		if (_dist < _nearestDist) then {
			_nearestDist = _dist;
			_nearest = _x;
		};
	} forEach _candidates;

	_nearest
};

// get all turret paths except driver

// Periodic replacement check (driver + turrets)
[_vehicle] spawn {
	params ["_vehicle", "_turrets"];
	private _turrets = allTurrets [_vehicle, false];

	while { alive _vehicle } do {
		// Wait until either driver or any turret seat becomes invalid
		waitUntil {
			sleep 0.1; // Small delay to avoid CPU spam
			private _driverBad = !([driver _vehicle] call fnc_isUnitGood);
			private _turretBad = _turrets findIf {
				!([_vehicle turretUnit _x] call fnc_isUnitGood)
			} != -1;
			_driverBad || _turretBad || {
				!alive _vehicle
			}
		};
		if (!alive _vehicle) exitWith {};

		// 1. Check driver
		private _driver = driver _vehicle;
		if (!([_driver] call fnc_isUnitGood)) then {
			private _replacement = [_vehicle] call fnc_getReplacement;
			if (([_replacement] call fnc_isUnitGood)) then {
				_replacement moveInDriver _vehicle;
			};
		};

		// 2. Check each turret
		{
			private _unit = _vehicle turretUnit _x;
			if (!([_unit] call fnc_isUnitGood)) then {
				private _replacement = [_vehicle] call fnc_getReplacement;
				if (([_replacement] call fnc_isUnitGood)) then {
					_replacement moveInTurret [_vehicle, _x];
				};
			};
		} forEach _turrets;

		sleep 1; // Check every second
	};
};