#include "commonFunctions.sqf"

params ["_group"];

// Save original unit types and loadouts
private _originalLoadouts = [_group] call save_original_loadouts;
private _totalUnits = count units _group;

while { true } do {
	waitUntil {
		sleep 2;
		private _aliveCount = {
			alive _x && (lifeState _x != "INCAPACITATED")
		} count units _group;
		_aliveCount <= (_totalUnits / 3)
	};

	private _radioUnit = [_group] call get_quiet_unit;
	private _markerName = [_radioUnit, groupId _group] call set_support_marker_and_radio;

	// Signal: Flare & Smoke
	private _flrObj = "F_40mm_Red" createVehicle (_radioUnit modelToWorld [0, 0, 200]);
	_flrObj setVelocity [0, 0, -1];
	"SmokeShellRed" createVehicle (position _radioUnit);

	// call support
	[_radioUnit, 200, 300, 8000, 400, _markerName, _originalLoadouts] call call_support_team;
};