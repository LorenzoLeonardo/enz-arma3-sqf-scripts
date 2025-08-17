/*
	    flyInChopper.sqf
	    Usage: [this] execVM "flyInChopper.sqf";
*/

params ["_chopper"];

fnc_getEnemySide = {
	params ["_chopper"];

	private _side = side (driver _chopper);

	switch (_side) do {
		case east: {
			west
		};
		case west: {
			east
		};
		case independent: {
			west
		};   // often fight blufor
		case civilian: {
			east
		};      // optional: treat civilians as hostile to opfor
		default {
			independent
		};
	};
};

private _heliPilot = driver _chopper;
private _aiPilotGroup = group _heliPilot;
private _sideEnemy = [_chopper] call fnc_getEnemySide;
private _basePos = getPos _chopper;
private _rtbAltitude = 80;

_chopper setVariable["basePosition", _basePos, true];

fnc_getEnemyCount = {
	params ["_sideEnemy"];
	count (allUnits select {
		side _x == _sideEnemy && alive _x
	})
};

fnc_removeCargoFromGroup = {
	params ["_chopper"];
	{
		if (tolower((assignedVehicleRole _x) select 0) == "cargo") then {
			[_x] joinSilent grpNull;
		};
	} forEach (crew _chopper);
};

fnc_getAverageEnemyPos = {
	params ["_sideEnemy"];
	private _enemies = allUnits select {
		side _x == _sideEnemy && alive _x
	};
	private _enemyPos = [0, 0, 0];
	{
		_enemyPos = _enemyPos vectorAdd (getPosATL _x)
	} forEach _enemies;

	if ((count _enemies) > 0) then {
		_enemyPos vectorMultiply (1 / (count _enemies))
	} else {
		[0, 0, 0]
	}
};

fnc_clearWaypoints = {
	params ["_group"];
	while { (count waypoints _group) > 0 } do {
		deleteWaypoint [_group, 0];
	};
};

fnc_createMarker = {
	params ["_target", "_text", "_type", "_color"];
	private _markerName = format ["airstrikeMarker_%1", diag_tickTime];

	private _marker = createMarker [_markerName, _target];
	_marker setMarkerShape "ICON";
	_marker setMarkerType _type;
	_marker setMarkerColor _color;
	_marker setMarkerText _text;

	_markerName
};

fnc_engageEnemies = {
	params ["_chopper", "_sideEnemy"];

	private _heliPilot = driver _chopper;
	private _aiPilotGroup = group _heliPilot;

	while {
		(([_sideEnemy] call fnc_getEnemyCount) > 0) &&
		alive _chopper &&
		(({
			alive _x
		} count crew _chopper) > 1)
	} do {
		_heliPilot = driver _chopper;
		_aiPilotGroup = group _heliPilot;

		hint format ["Remaining enemies: %1", ([_sideEnemy] call fnc_getEnemyCount)];
		_chopper setVehicleAmmo 1;

		private _aliveEnemies = allUnits select {
			(side _x == _sideEnemy) && (alive _x) && (lifeState _x != "INCAPACITATED")
		};
		private _target = _aliveEnemies param [0, objNull];

		if (!isNull _target) then {
			[_aiPilotGroup] call fnc_clearWaypoints;

			private _wp = _aiPilotGroup addWaypoint [getPos _target, 0];
			_wp setWaypointType "SAD";
			_wp setWaypointBehaviour "AWARE";
			_wp setWaypointCombatMode "RED";
			_wp setWaypointSpeed "FULL";
			private _markerName = [
				getPos _target,
				"Air Strike Here!",
				"mil_objective",
				"ColorBlack"
			] call fnc_createMarker;

			waitUntil {
				(!alive _target) || (lifeState _target == "INCAPACITATED")
			};
			deleteMarker _markerName;
		};
		sleep 1;
	};
};

fnc_flyInChopper = {
	params ["_chopper", "_heliPilot", "_aiPilotGroup", "_sideEnemy", "_basePos", "_rtbAltitude"];

	private _threshHoldCount = floor (([_sideEnemy] call fnc_getEnemyCount) * 0.75);

	// Remove cargo from group
	[_chopper] call fnc_removeCargoFromGroup;

	// Wait until enemy count drops
	waitUntil {
		([_sideEnemy] call fnc_getEnemyCount) <= _threshHoldCount && alive _chopper
	};

	if (alive _chopper) then {
		hint "Tactical airstrike is coming your location.";
		_heliPilot sideRadio "RadioHeliTacticalStrike";

		_chopper engineOn true;
		_chopper flyInHeight _rtbAltitude;
		_aiPilotGroup setBehaviour "AWARE";
		_aiPilotGroup setCombatMode "RED";

		{
			_x enableAI "MOVE"
		} forEach units _aiPilotGroup;

		private _enemyPos = [_sideEnemy] call fnc_getAverageEnemyPos;

		if (_enemyPos isNotEqualTo [0, 0, 0]) then {
			// Add TAKEOFF move waypoint
			private _wp0 = _aiPilotGroup addWaypoint [getPos _chopper, 0];
			_wp0 setWaypointType "MOVE";

			// SAD waypoint to enemy cluster
			private _wp1 = _aiPilotGroup addWaypoint [_enemyPos, 0];
			_wp1 setWaypointType "SAD";

			_heliPilot doMove _enemyPos;

			// Engage loop
			[_chopper, _sideEnemy] call fnc_engageEnemies;

			if (alive _chopper) then {
				_heliPilot = driver _chopper;
				_aiPilotGroup = group _heliPilot;
				[_aiPilotGroup] call fnc_clearWaypoints;
				private _markerName = [
					_basePos,
					"mil_end",
					"mil_objective",
					"ColorBlack"
				] call fnc_createMarker;
				private _rtbWP = _aiPilotGroup addWaypoint [_basePos, 0];
				_rtbWP setWaypointType "GETOUT";
				sleep 60;
			};
		};
	};
};

// move a unit to a specific role (optionally a turret seat path)
fnc_moveToRole = {
	params ["_man", "_veh", "_role", "_seatPath"];

	switch (toLower _role) do {
		case "driver": {
			_man moveInDriver _veh
		};
		case "cargo": {
			_man moveInCargo _veh
		};
		case "turret": {
			_man moveInTurret [_veh, _seatPath]
		};
		default {};
	};
};

// Generic swap: define BOTH new roles (and seats if turret)
fnc_swapPositions = {
	// _unit = the one going down; _replacement = the one taking over
	params ["_unit", "_replacement", "_veh", "_unitNewRole", "_replacementNewRole", "_unitTurretSeat", "_replacementTurretSeat"];

	// Evict both, then place them in target seats
	{
		unassignVehicle _x;
		moveOut _x;
	} forEach [_unit, _replacement];

	// Keep team cohesion
	[_replacement] joinSilent (group _unit);

	// Place them
	[_unit, _veh, _unitNewRole, _unitTurretSeat] call fnc_moveToRole;
	[_replacement, _veh, _replacementNewRole, _replacementTurretSeat] call fnc_moveToRole;
};

// find a valid replacement matching any of the allowed role types
fnc_findReplacement = {
	params ["_unit", "_veh", "_allowedRoles"]; // e.g., ["cargo", "turret"]

	private _r = objNull;
	{
		if (
		_x != _unit &&
		alive _x &&
		lifeState _x != "INCAPACITATED" &&
		(toLower ((assignedVehicleRole _x) select 0)) in _allowedRoles) exitWith {
			_r = _x
		};
	} forEach (crew _veh);

	_r
};

// driver down → try turret first (keep guns manned), then cargo
fnc_handleDriverDown = {
	params ["_unit", "_veh"];

	private _replacement = [_unit, _veh, ["turret", "cargo"]] call fnc_findReplacement;
	if (isNull _replacement) exitWith {};

	private _repRole = toLower ((assignedVehicleRole _replacement) select 0);

	switch (_repRole) do {
		case "turret": {
			// Turret path comes from the REPLACEMENT (they vacate that seat)
			private _turretPath = (assignedVehicleRole _replacement) select 1;
			// New positions: UNIT → that turret seat, REPLACEMENT → driver
			[_unit, _replacement, _veh, "turret", "driver", _turretPath, []] call fnc_swapPositions;
		};
		case "cargo": {
			// New positions: UNIT → cargo, REPLACEMENT → driver
			[_unit, _replacement, _veh, "cargo", "driver", [], []] call fnc_swapPositions;
		};
	};
};

// Turret down → pull from cargo into THIS unit's turret seat
fnc_handleTurretDown = {
	params ["_unit", "_veh"];

	private _replacement = [_unit, _veh, ["cargo"]] call fnc_findReplacement;
	if (isNull _replacement) exitWith {};

	// Turret path from the UNIT (the seat that just got vacated)
	private _unitTurretPath = (assignedVehicleRole _unit) select 1;

	// New positions: UNIT → cargo, REPLACEMENT → that turret seat
	[_unit, _replacement, _veh, "cargo", "turret", [], _unitTurretPath] call fnc_swapPositions;
};

// HandleDamage event: trigger replacement on kill/incapacitation
fnc_startDamageHandlers = {
	params ["_chopper"];
	{
		_x addEventHandler ["HandleDamage", {
			params ["_unit", "_selection", "_damage"];
			private _currentDamage = damage _unit;
			private _newDamage = _currentDamage + _damage;

			if ((_newDamage >= 1 && alive _unit) ||
			{
				lifeState _unit == "INCAPACITATED"
			}
			) then {
				private _veh = vehicle _unit;
				private _roleType = toLower ((assignedVehicleRole _unit) select 0);

				switch (_roleType) do {
					case "driver": {
						[_unit, _veh] call fnc_handleDriverDown
					};
					case "turret": {
						[_unit, _veh] call fnc_handleTurretDown
					};
				};
			};
			_newDamage
		}];
	} forEach crew _chopper;
};

// When all units are dead, destroy the heli
fnc_startMonitoringHeliStatus = {
	params ["_chopper"];

	waitUntil {
		({
			alive _x
		} count crew _chopper == 0) || !(alive _chopper)
	};
	_chopper setDamage 1;

	private _markerName = [
		getPosATL _chopper,
		"Heli Crash Site",
		"mil_destroy",
		"ColorRed"
	] call fnc_createMarker;

	private _grp = createGroup west;
	private _unit = _grp createUnit ["B_Soldier_F", [0, 0, 0], [], 0, "NONE"];

	// set group callsign
	_grp setGroupIdGlobal ["November"];

	_unit sideRadio "RadioHeliMayday";
	sleep 3;
	player sideRadio "RadioHeliHeloDown";
	sleep 5;
	[west, "Base"] sideRadio "RadioHeliHeloSearchAndRescue";
	sleep 3;

	{
		deleteVehicle _x;
	} forEach units _grp;
	deleteGroup _grp;
};

// Main entry 
[_chopper] call fnc_startDamageHandlers;
[_chopper] spawn fnc_startMonitoringHeliStatus;
[
	_chopper,
	_heliPilot,
	_aiPilotGroup,
	_sideEnemy,
	_basePos,
	_rtbAltitude
] spawn fnc_flyInChopper;