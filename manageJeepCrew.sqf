// ==============================================================================================================
// AI crew Management Script
// Author: Lorenzo Leonardo
// Contact: enzotechcomputersolutions@gmail.com
// ==============================================================================================================
// 
// Description:
// This script automatically manages vehicle crew composition by replacing incapacitated or dead crew members 
// (driver and turret operators) with the nearest available AI unit from the same group. It ensures that vehicles 
// remain operational in combat by dynamically reassigning idle AI to critical crew positions. The replacement 
// process uses `assignAs...` and `orderGetIn` commands so units physically move to the vehicle instead of 
// instantly teleporting, providing more immersive and realistic behavior.
// 
// Features:
// - Automatically replaces incapacitated or dead drivers.
// - Automatically replaces turret crew for any number of turret seats (supports multi-seat turrets).
// - Selects nearest available AI from the same group to minimize downtime.
// - Uses AI movement (`orderGetIn`) for realistic crew changes (no instant teleport).
// - Avoids assigning player units to vehicle seats.
// - Works continuously until the vehicle is destroyed.
// - Efficient `waitUntil`-based monitoring to avoid unnecessary CPU usage.
// 
// Parameters:
//   _vehicle                       - The vehicle to monitor and manage crew for.
// 
// Functions:
//   fnc_isUnitGood                 - Checks if a unit is alive, not incapacitated, and exists.
//   fnc_getReplacement             - Finds the nearest available AI from the vehicle's group.
// 
// Usage Example:
//   [myVehicle] execVM "manageJeepCrew.sqf";
// 
// Notes:
// - Designed for AI-only crew management; player seats are excluded from replacement.
// - Works with land vehicles, boats, and aircraft that have defined turret paths.
// - Can be expanded with event handlers (`Killed`, `GetOut`) for even faster reaction times.
// - Intended for server-side execution to ensure consistent behavior for all clients.
// ==================================================================================================

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
				_replacement assignAsDriver _vehicle;
				[_replacement] orderGetIn true;
			};
		};

		// 2. Check each turret
		{
			private _unit = _vehicle turretUnit _x;
			if (!([_unit] call fnc_isUnitGood)) then {
				private _replacement = [_vehicle] call fnc_getReplacement;
				if (([_replacement] call fnc_isUnitGood)) then {
					_replacement assignAsTurret [_vehicle, _x];
					[_replacement] orderGetIn true;
				};
			};
		} forEach _turrets;

		sleep 1; // Check every second
	};
};