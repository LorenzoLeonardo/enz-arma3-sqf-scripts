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
#include "common.sqf"

params ["_vehicle"];

// =============================
// Helper: get nearest available AI from same group
// =============================
ETCS_fnc_getReplacement = {
	params ["_vehicle"];

	private _assignedUnits = _vehicle getVariable ["assignedUnits", []];

	private _grp = if (!isNull driver _vehicle) then {
		group driver _vehicle
	} else {
		group effectiveCommander _vehicle
	};
	private _candidates = (units _grp) select {
		([_x] call ETCS_fnc_isUnitGood) &&
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
ETCS_fnc_assignReplacement = {
	params ["_vehicle", "_role", "_turretPath"];

	private _assignedUnits = _vehicle getVariable ["assignedUnits", []];
	private _replacement = [_vehicle] call ETCS_fnc_getReplacement;

	if (isNull _replacement) exitWith {};

	switch (true) do {
		case (_role == "driver"): {
			_replacement moveInDriver _vehicle;
		};
		case (_role == "gunner"): {
			_replacement moveInTurret [_vehicle, _turretPath];
		};
		case (_role == "turret"): {
			_replacement moveInTurret [_vehicle, _turretPath];
		};
		case (_role == "commander"): {
			_replacement moveInCommander _vehicle;
		};
		default {};
	};

	_assignedUnits pushBackUnique _replacement;
	_vehicle setVariable ["assignedUnits", _assignedUnits, true]; // public so MP safe
};

ETCS_fnc_startMonitoringVehicle = {
	params ["_vehicle"];
	private _group = (group _vehicle);
	private _groupID = groupId _group;
	waitUntil {
		!(alive _vehicle) || !(canMove _vehicle)
	};
	{
		if (alive _x) then {
			unassignVehicle _x;
			_x action ["Eject", _vehicle];
		}
	} forEach (units _group);
	_vehicle setDamage 1;

	// Attached unlimited fire
	private _smoker = "test_EmptyObjectForFireBig" createVehicle (position _vehicle);
	_smoker attachTo [_vehicle, [0, 1.5, 0]];

	private _markerName = [
		getPosATL _vehicle,
		format["APC Destroyed Here: %1", _groupID],
		"mil_unknown",
		"ColorWEST"
	] call ETCS_fnc_createMarker;
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
				[_veh, "driver", _turretPath] call ETCS_fnc_assignReplacement;
			};
			case (_role == "gunner"): {
				[_veh, "gunner", _turretPath] call ETCS_fnc_assignReplacement;
			};
			case (_role == "turret"): {
				[_veh, "turret", _turretPath] call ETCS_fnc_assignReplacement;
			};
			case (_role == "commander"): {
				[_veh, "commander", _turretPath] call ETCS_fnc_assignReplacement;
			};
			default {
				[_veh, _role, _turretPath] call ETCS_fnc_assignReplacement;
			};
		};
	};
}];

// Handle vehicle destroyed
_vehicle addEventHandler ["Killed", {
	params ["_veh"];
	_veh setVariable ["assignedUnits", [], true];
}];

[_vehicle] spawn ETCS_fnc_startMonitoringVehicle;