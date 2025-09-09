#include "common.sqf"

params ["_gun", "_group"];

// =====================================================================
// Function to find a suitable gunner
// =====================================================================
fnc_findReplacementGunner = {
	params ["_group", "_gun"];

	private _leader = leader _group;

	// Healthy candidates first
	private _candidatesHealthy = (units _group) select {
		_x != player &&
		_x != _leader &&
		([ _x ] call ETCS_fnc_isUnitGood) &&
		isNull objectParent _x &&
		isNull assignedVehicle _x
	};

	if (!(_candidatesHealthy isEqualTo [])) exitWith {
		[_gun, _candidatesHealthy] call ETCS_fnc_findNearestUnit
	};

	objNull
};

// =====================================================================
// Auto-refill ammo loop
// =====================================================================
[_gun] spawn {
	params ["_gun"];
	while { alive _gun } do {
		_gun setVehicleAmmo 1;
		sleep 3;
	};
};

// =====================================================================
// Function to assign a candidate to the gun safely
// =====================================================================
fnc_assignGunner = {
	params ["_group", "_gun"];

	private _candidate = [_group, _gun] call fnc_findReplacementGunner;

	if (count crew _gun > 0) exitWith {};

	if (!isNull _candidate) then {
		_candidate assignAsGunner _gun;
		[_candidate] orderGetIn true;

		[_candidate, _gun] spawn {
			params ["_candidate", "_gun"];
			while { ([_candidate] call ETCS_fnc_isUnitGood) && (gunner _gun != _candidate) } do {
				sleep 0.5;
			};
		};
	};
};

// =====================================================================
// Immediate assignment if gun starts empty
// =====================================================================
if ((count crew _gun) == 0) then {
	[ _group, _gun ] call fnc_assignGunner;
};

// =====================================================================
// Event handler for gunner death
// =====================================================================
_gun addEventHandler ["Killed", {
	params ["_gun", "_killer", "_instigator", "_useEffects"];
	private _group = group _gun;

	[ _group, _gun ] call fnc_assignGunner;
}];

// =====================================================================
// Event handler for gunner injury (Option A)
// =====================================================================
_gun addEventHandler ["GetOut", {
	params ["_vehicle", "_role", "_unit", "_turret", "_isEject"];
	private _group = group _unit;

	[ _group, _vehicle ] call fnc_assignGunner;
}];