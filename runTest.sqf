#include "common.sqf"

// --- Define test helper
fnc_testCase_ETCS_fnc_isHostile = {
	params ["_a", "_b", "_expected", "_label"];
	systemChat format ["[PASSED] %1=%2 %3=%4", typeName _a, _a, typeName _b, _b];
	private _result = [_a, _b] call ETCS_fnc_isHostile;

	if (_result isEqualTo _expected) exitWith {
		systemChat format ["[PASS] %1", _label];
		true
	};

	// Fail
	systemChat format [
		"[FAIL] %1 | got %2 expected %3",
		_label, _result, _expected
	];

	false
};

// --- Run tests
fnc_runTests = {
	private _pos = [0, 0, 0] findEmptyPosition [5, 50, "B_Soldier_F"];

	private _westGrp = createGroup west;
	private _eastGrp = createGroup east;
	private _civGrp = createGroup civilian;

	private _westUnit = _westGrp createUnit ["B_Soldier_F", _pos, [], 0, "NONE"];
	private _eastUnit = _eastGrp createUnit ["O_Soldier_F", _pos, [], 0, "NONE"];
	private _civUnit = _civGrp createUnit ["C_man_1", _pos, [], 0, "NONE"];

	private _veh = createVehicle ["B_MRAP_01_F", _pos, [], 0, "NONE"];
	private _vehCrewGrp = createGroup west;
	private _vehCrew = _vehCrewGrp createUnit ["B_Soldier_F", _pos, [], 0, "NONE"];
	_vehCrew moveInDriver _veh;

	private _deadUnit = _eastGrp createUnit ["O_Soldier_F", _pos, [], 0, "NONE"];
	_deadUnit setDamage 1;

	// --- Tests
	private _tests = [
		// --- Expected true
		[east, west, true, "East vs West hostile"],
		[_westUnit, east, true, "West unit vs East side hostile"],
		[_westUnit, _eastUnit, true, "West unit vs East unit hostile"],
		[_veh, east, true, "West vehicle vs East side hostile"],
		[_deadUnit, west, true, "Dead East vs West still hostile (side check only)"],

		// --- Expected false
		[west, west, false, "West vs West not hostile"],
		[civilian, civilian, false, "Civ vs Civ not hostile"],
		[_westUnit, west, false, "West unit vs West side not hostile"],
		[_westUnit, _civUnit, false, "West unit vs Civ unit not hostile"],
		[player, player, false, "Player vs self not hostile"],
		[_veh, west, false, "West vehicle vs West side not hostile"],
		[objNull, east, false, "objNull vs East safe"],
		[objNull, objNull, false, "objNull vs objNull safe"]
	];

	// --- Evaluate all
	private _fails = 0;
	{
		if !((_x call fnc_testCase_ETCS_fnc_isHostile)) then {
			_fails = _fails + 1;
		};
	} forEach _tests;

	// --- Cleanup
	{
		if (!isNull _x) then {
			deleteVehicle _x
		};
	} forEach [_westUnit, _eastUnit, _civUnit, _veh, _vehCrew, _deadUnit];

	{
		if (!isNull _x) then {
			deleteGroup _x
		};
	} forEach [_westGrp, _eastGrp, _civGrp, _vehCrewGrp];

	// --- End game on errors
	if (_fails > 0) then {
		hint format ["ETCS_fnc_isHostile: %1 test(s) failed!", _fails];
		sleep 5;
		endMission "LOSER";   // use built-in ending
	} else {
		hint "All tests passed!";
	};
};