/*
	    fn_manageGunCrew.sqf
	    Parameters:
	        0: OBJECT - The .50 cal weapon (turret/gun vehicle)
	        1: group - The AI group that can crew the weapon
	        2: (Optional) NUMBER - max retries when no crew can be found (default: 10)
	
	    Description:
	        Assigns an AI gunner to the specified weapon if the current one is killed.
	        Ensures infinite ammo. Skips players and already-assigned units.
	
	Example:
	[this, group this, 10, false] execVM "manageGunCrew.sqf";
*/

params [
	["_gun", objNull, [objNull]],
	["_group", grpNull, [grpNull]],
	["_maxRetries", 10, [0]],
	["_makeInvincible", false, [true]]
];

if (isNull _gun || isNull _group) exitWith {
	diag_log "[manageGunCrew] Invalid parameters.";
};

_gun allowDamage !_makeInvincible;

// Refill ammo continuously
[_gun] spawn {
	params ["_gun"];
	while { alive _gun } do {
		_gun setVehicleAmmo 1;
		sleep 10;
	};
};

private _retryCount = 0;
private _startIndex = 1;  // <-- Skip team leader

while {
	({
		alive _x
	} count units _group) > 1 &&
	_retryCount < _maxRetries &&
	alive _gun
} do {
	if ({
		alive _x
	} count crew _gun == 0) then {
		private _units = units _group;
		private _index = _startIndex;
		private _candidate = objNull;

		while { _index < count _units } do {
			private _unit = _units select _index;
			private _alreadyAssigned = vehicle _unit != _unit;  // true if unit is in any vehicle

			if (alive _unit && !_alreadyAssigned && !(_unit in _gun) && !isPlayer _unit) exitWith {
				_candidate = _unit;
			};

			_index = _index + 1;
		};

		if (!isNull _candidate) then {
			_candidate assignAsGunner _gun;
			[_candidate] orderGetIn true;

			waitUntil {
				sleep 0.5;
				({
					alive _x
				} count crew _gun) > 0 || !alive _candidate
			};

			if (!alive _candidate) then {
				_retryCount = _retryCount + 1;
			};
		} else {
			_retryCount = _retryCount + 1;
			_startIndex = _startIndex + 1;
		};
	};

	sleep 1;
};

if (_retryCount >= _maxRetries) then {
	diag_log format ["[manageGunCrew] Max retries reached for gun: %1", _gun];
};