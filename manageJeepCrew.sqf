// ==============================================================================================================
// AI crew Management Script (Event Handler Version)
// Author: Lorenzo Leonardo
// Contact: enzotechcomputersolutions@gmail.com
// ==============================================================================================================
// 
// Description:
// This script manages AI crew in vehicles by replacing incapacitated or dead crew members with the nearest
// available AI from the same group. It now uses event handlers (`GetIn`, `GetOut`, `Killed`) to detect seat
// changes instantly, removing the timing issues with `turretUnit` returning objNull.
// 
// Features:
// - Automatically replaces incapacitated or dead drivers/turret operators
// - Supports any number of turret seats
// - Uses `orderGetIn` for realism (can switch to `moveIn...` for instant assignment)
// - Avoids assigning player units
// - Refreshes turret list dynamically
// - Event handler driven (no delay from polling)
// 
// Parameters:
//   _vehicle - The vehicle to monitor and manage crew for
// 
// Usage:
//   [myVehicle] execVM "manageJeepCrew.sqf";
// ==============================================================================================================

params ["_vehicle"];

// =============================
// Helper: Check if unit is valid
// =============================
fnc_isUnitGood = {
	params ["_unit"];
	!(isNull _unit) && {
		alive _unit
	} && {
		lifeState _unit != "INCAPACITATED"
	}
};

// =============================
// Helper: get nearest available AI from same group
// =============================
fnc_getReplacement = {
	params ["_vehicle"];

	private _assignedUnits = _vehicle getVariable ["assignedUnits", []];

	private _grp = if (!isNull driver _vehicle) then {
		group driver _vehicle
	} else {
		group effectiveCommander _vehicle
	};
	private _candidates = (units _grp) select {
		([_x] call fnc_isUnitGood) &&
		isNull objectParent _x &&
		!isPlayer _x &&
		!(_x in _assignedUnits)
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

// ===========================================
// Function: Assign replacement to given seat
// ===========================================
fnc_assignReplacement = {
	params ["_vehicle", "_role", "_turretPath"];

	private _assignedUnits = _vehicle getVariable ["assignedUnits", []];
	private _replacement = [_vehicle] call fnc_getReplacement;

	if (isNull _replacement) exitWith {
		systemChat "No AI available to replace!";
	};

	systemChat format ["Assigning %1 to seat: %2", name _replacement, _role];

	switch (true) do {
		case (_role == "driver"): {
			systemChat format ["DRIVER: %1", _replacement];
			_replacement moveInDriver _vehicle;
		};
		case (_role == "gunner"): {
			systemChat format ["GUNNER: %1 PATH: %2", _replacement, _turretPath];
			_replacement moveInTurret [_vehicle, _turretPath];
		};
		case (_role == "turret"): {
			systemChat format ["TURRET: %1 PATH: %2", _replacement, _turretPath];
			_replacement moveInTurret [_vehicle, _turretPath];
		};
		case (_role == "commander"): {
			systemChat format ["COMMANDER: %1", _replacement];
			_replacement moveInCommander _vehicle;
		};
		default {
			systemChat format ["UNDEFINED ROLE: %1", _role];
		};
	};

	_assignedUnits pushBackUnique _replacement;
	_vehicle setVariable ["assignedUnits", _assignedUnits, true]; // public so MP safe
};

// =============================
// EVENT HANDLERS
// =============================

// Prepare global variable for this vehicle
_vehicle setVariable ["assignedUnits", [], true];

// Handle GetOut event
_vehicle addEventHandler ["GetOut", {
	params ["_veh", "_role", "_unit", "_turretPath"];
	if (isPlayer _unit) exitWith {};
	if (alive _veh) then {
		switch (true) do {
			case (_role == "driver"): {
				[_veh, "driver", _turretPath] call fnc_assignReplacement;
			};
			case (_role == "gunner"): {
				[_veh, "gunner", _turretPath] call fnc_assignReplacement;
			};
			case (_role == "turret"): {
				[_veh, "turret", _turretPath] call fnc_assignReplacement;
			};
			case (_role == "commander"): {
				[_veh, "commander", _turretPath] call fnc_assignReplacement;
			};
			default {
				[_veh, _role, _turretPath] call fnc_assignReplacement;
			};
		};
	};
}];

// Handle vehicle destroyed
_vehicle addEventHandler ["Killed", {
	params ["_veh"];
	_veh setVariable ["assignedUnits", [], true];
	systemChat format ["Vehicle %1 destroyed - crew list cleared", _veh];
}];