// Usage: [enemyGrp1] execVM "monitorGroupRespawn.sqf";

params ["_group"];

private _groupVarName = "enemyGrp1"; // Must match the editor variable
private _spawnPos = getPos leader _group;
private _side = side _group;
private _minSurvivors = 1;
private _respawnDelay = 15;

// Backup unit types
private _unitTypes = [];
{
	_unitTypes pushBack (typeOf _x);
} forEach units _group;

// Backup group callsign
private _groupId = groupId _group;  // e.g., "Alpha 1-4"
private _prefix = _groupId splitString " ";  // ["Alpha", "1-4"]
private _groupName = _prefix select 0;       // "Alpha"

// Backup waypoints
private _waypoints = [];
for "_i" from 0 to (count waypoints _group - 1) do {
	private _wpPos = waypointPosition [_group, _i];
	private _wpType = waypointType [_group, _i];
	private _wpBeh = waypointBehaviour [_group, _i];
	private _wpCombat = waypointCombatMode [_group, _i];
	private _wpSpeed = waypointSpeed [_group, _i];
	private _wpFormation = waypointFormation [_group, _i];
	private _wpTimeout = waypointTimeout [_group, _i];
	private _wpStatements = waypointStatements [_group, _i];

	_waypoints pushBack [
		_wpPos,
		_wpType,
		_wpBeh,
		_wpCombat,
		_wpSpeed,
		_wpFormation,
		_wpTimeout,
		_wpStatements
	];
};

while { true } do {
	private _aliveUnits = units _group select {
		alive _x
	};

	if (count _aliveUnits <= _minSurvivors) then {
		hint format ["Group '%1' mostly dead. Respawning in %2 seconds...", _groupName, _respawnDelay];

		sleep _respawnDelay;

		// Delete remaining units
		{
			deleteVehicle _x;
		} forEach units _group;
		deleteGroup _group;

		// Respawn group
		private _newGroup = createGroup _side;
		_newGroup setGroupId [_groupName];

		{
			_newGroup createUnit [_x, _spawnPos, [], 3, "FORM"];
		} forEach _unitTypes;

		// Restore waypoints
		{
			_x params ["_pos", "_type", "_beh", "_combat", "_speed", "_formation", "_timeout", "_statements"];
			private _wp = _newGroup addWaypoint [_pos, 0];
			_wp setWaypointType _type;
			_wp setWaypointBehaviour _beh;
			_wp setWaypointCombatMode _combat;
			_wp setWaypointSpeed _speed;
			_wp setWaypointFormation _formation;
			_wp setWaypointTimeout _timeout;
			_wp setWaypointStatements [_statements select 0, _statements select 1];
		} forEach _waypoints;

		// Reassign global var
		missionNamespace setVariable [_groupVarName, _newGroup];

		// continue loop with new group
		_group = _newGroup;
	};

	sleep 5;
};