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

test_ETCS_fnc_isHostile = {
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
		[_westGrp, east, true, "West group vs East side hostile"],
		[_eastGrp, west, true, "East group vs West side hostile"],
		[_westGrp, _eastUnit, true, "West group vs East unit hostile"],

		// --- Expected false
		[west, west, false, "West vs West not hostile"],
		[civilian, civilian, false, "Civ vs Civ not hostile"],
		[_westUnit, west, false, "West unit vs West side not hostile"],
		[_westUnit, _civUnit, false, "West unit vs Civ unit not hostile"],
		[player, player, false, "Player vs self not hostile"],
		[_veh, west, false, "West vehicle vs West side not hostile"],
		[objNull, east, false, "objNull vs East safe"],
		[objNull, objNull, false, "objNull vs objNull safe"],
		[_civGrp, west, false, "Civilian group vs West not hostile"],
		[_westGrp, _civGrp, false, "West group vs Civilian group not hostile"]
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
		hint format ["[FAILED] ETCS_fnc_isHostile: %1 test(s)", _fails];
		sleep 5;
		endMission "LOSER";   // use built-in ending
	} else {
		systemChat "[PASSED] ETCS_fnc_isHostile"
	};
};
/*
test_ETCS_fnc_getAllEnemies = {
	// 1. Create groups
	private _westGrp1 = createGroup west;
	private _westGrp2 = createGroup west;
	private _eastGrp = createGroup east;
	private _civGrp = createGroup civilian;

	// 2. spawn units with offsets
	private _unitWest1 = _westGrp1 createUnit ["B_Soldier_F", [0, 0, 0], [], 0, "NONE"];
	private _unitWest2 = _westGrp2 createUnit ["B_Soldier_F", [2, 0, 0], [], 0, "NONE"];
	private _unitEast1 = _eastGrp createUnit ["O_Soldier_F", [4, 0, 0], [], 0, "NONE"];
	private _unitCiv1 = _civGrp createUnit ["C_man_1", [6, 0, 0], [], 0, "NONE"];

	// 2.1 Activate AI
	{
		_x enableAI "ALL"
	} forEach [_unitWest1, _unitWest2, _unitEast1, _unitCiv1];

	sleep 1.5; // allow AI to initialize

	    // 3. Define expected enemies
	private _expectedWest1Enemies = [_unitEast1];
	private _expectedEast1Enemies = [_unitWest1, _unitWest2];

	    // 4. Run function under test
	private _actualWest1Enemies = [_unitWest1] call ETCS_fnc_getAllEnemies;
	private _actualEast1Enemies = [_unitEast1] call ETCS_fnc_getAllEnemies;

	    // 5. Compare arrays (ignores order)
	private _compareArrays = {
		params ["_arr1", "_arr2"];
		count (_arr1 - _arr2) == 0 && count (_arr2 - _arr1) == 0
	};

	private _testWest = [_actualWest1Enemies, _expectedWest1Enemies] call _compareArrays;
	private _testEast = [_actualEast1Enemies, _expectedEast1Enemies] call _compareArrays;

	    // 6. Cleanup function
	private _cleanup = {
		params ["_unitWest1", "_unitWest2", "_unitEast1", "_unitCiv1", "_westGrp1", "_westGrp2", "_eastGrp", "_civGrp" ];
		{
			if (!isNull _x) then {
				deleteVehicle _x
			}
		} forEach [_unitWest1, _unitWest2, _unitEast1, _unitCiv1];
		{
			if (!isNull _x) then {
				deleteGroup _x
			}
		} forEach [_westGrp1, _westGrp2, _eastGrp, _civGrp];
	};

	    // 7. Fail if test fails
	if (!_testWest) exitWith {
		hint "FAIL: West Unit enemies incorrect";
		sleep 5;
		[_unitWest1, _unitWest2, _unitEast1, _unitCiv1, _westGrp1, _westGrp2, _eastGrp, _civGrp] call _cleanup;
		endMission "LOSER";
	};

	if (!_testEast) exitWith {
		hint "FAIL: East Unit enemies incorrect";
		sleep 5;
		[_unitWest1, _unitWest2, _unitEast1, _unitCiv1, _westGrp1, _westGrp2, _eastGrp, _civGrp] call _cleanup;
		endMission "LOSER";
	};

	    // 8. Test passed
	systemChat "[PASSED] ETCS_fnc_getAllEnemies";
	[_unitWest1, _unitWest2, _unitEast1, _unitCiv1, _westGrp1, _westGrp2, _eastGrp, _civGrp] call _cleanup;
};
*/
// --- Run tests
fnc_runTests = {
	[] call test_ETCS_fnc_isHostile;
	//[] call test_ETCS_fnc_getAllEnemies;

	hint "All tests passed!";
};