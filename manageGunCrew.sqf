params ["_gun", "_group"];

_gun allowDamage false;

[_gun] spawn {
	params ["_gun"];
	while { alive _gun } do {
		_gun setVehicleAmmo 1;
		sleep 1;
	};
};

private _newStartIndex = 1;

// Monitor group and reassign gunner if necessary
while {
	({
		alive _x
	} count units _group) > 1
} do {
	// Check if gun is unmanned
	if ({
		alive _x
	} count crew _gun <= 0) then {
		private _groupArray = units _group;
		private _index = _newStartIndex;
		private _groupmember = objNull;

		// find suitable replacement
		while { _index < count _groupArray } do {
			private _candidate = _groupArray select _index;
			private _isUnassigned = isNull assignedVehicle _candidate;

			if ((alive _candidate) && (_candidate != player) &&	_isUnassigned && !(_candidate in _gun)) then {
				_groupmember = _candidate;
				break;
			};

			_index = _index + 1;
		};

		// Assign to gun if a valid unit was found
		if (!isNull _groupmember) then {
			_groupmember assignAsGunner _gun;
			[_groupmember] orderGetIn true;
			waitUntil {
				({
					alive _x
				} count crew _gun) > 0
			};
		} else {
			// No valid member found, increment starting index to avoid retrying dead/unavailable units
			_newStartIndex = _newStartIndex + 1;
		};
	} else {
		sleep 1;
	};
};