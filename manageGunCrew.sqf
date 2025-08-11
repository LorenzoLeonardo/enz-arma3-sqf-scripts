params ["_gun", "_group"];

// Auto-refill ammo loop
[_gun] spawn {
	params ["_gun"];
	while { alive _gun } do {
		_gun setVehicleAmmo 1;
		sleep 3;
	};
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

	private _sorted = [_candidates, [], {
		params ["_x"];
		_x distance _gun
	}] call BIS_fnc_sortBy;

	_sorted select 0
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