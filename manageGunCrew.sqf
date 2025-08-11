params ["_gun", "_group"];

// Auto-refill ammo loop
[_gun] spawn {
	params ["_gun"];
	while { alive _gun } do {
		_gun setVehicleAmmo 1;
		sleep 3;
	};
};

// ===============================
// FUNCTION: find Nearest Unit
// ===============================
fnc_findNearestUnit = {
	params ["_pos", "_candidates"];

	private _nearestUnit = objNull;
	private _nearestDist = 1e10;  // a very large distance

	{
		private _dist = _pos distance _x;
		if (_dist < _nearestDist) then {
			_nearestDist = _dist;
			_nearestUnit = _x;
		};
	} forEach _candidates;

	_nearestUnit
};

// Function to find a suitable gunner
private _findReplacementGunner = {
	params ["_group", "_gun"];

	private _leader = leader _group;

	private _candidates = (units _group) select {
		alive _x &&
		_x != player &&
		_x != _leader &&
		lifeState _x != "INCAPACITATED" &&
		isNull objectParent _x &&
		isNull assignedVehicle _x
	};

	if (_candidates isEqualTo []) exitWith {
		objNull
	};

	private _gunner = [_gun, _candidates] call fnc_findNearestUnit;
	_gunner
};

// Monitor gun and assign AI if unmanned
while {
	!isNull _gun &&
	alive _gun &&
	{
		alive _x
	} count units _group > 1
} do {
	if ((count crew _gun) == 0 || {
		lifeState (gunner _gun) == "INCAPACITATED"
	}) then {
		private _candidate = [_group, _gun] call _findReplacementGunner;

		if (!isNull _candidate) then {
			_candidate assignAsGunner _gun;
			[_candidate] orderGetIn true;

			// Wait until the unit becomes the gunner or dies/incapacitated
			waitUntil {
				sleep 0.5;
				!alive _candidate ||
				lifeState _candidate == "INCAPACITATED" ||
				gunner _gun == _candidate
			};
		};
	};

	sleep 1;
};