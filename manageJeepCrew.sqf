params ["_vehicle"];

private _group = group _vehicle;

while { alive _vehicle } do {
	// === driver MANAGEMENT ===
	private _currentDriver = driver _vehicle;
	private _leader = leader _group;

	if (isNull _currentDriver || {
		!alive _currentDriver
	}) then {
		if (!isNull _currentDriver && {
			!alive _currentDriver && _currentDriver in _vehicle
		}) then {
			moveOut _currentDriver;
			unassignVehicle _currentDriver;
		};

		private _crewInVehicle = crew _vehicle;
		private _replacementDriver = objNull;

		{
			if (
			alive _x &&
			!isPlayer _x &&
			_x in _vehicle &&
			_x != _leader &&
			assignedVehicleRole _x isNotEqualTo ["driver"]
			) exitWith {
				_replacementDriver = _x;
			};
		} forEach _crewInVehicle;

		if (!isNull _replacementDriver) then {
			_replacementDriver assignAsDriver _vehicle;
			[_replacementDriver] orderGetIn true;
			waitUntil {
				driver _vehicle == _replacementDriver || {
					!alive _replacementDriver
				}
			};
		};
	};

	// === gunner MANAGEMENT ===
	private _gunnerSeats = fullCrew [_vehicle, "gunner", true];

	{
		private _seatInfo = _x;
		private _currentGunner = _seatInfo select 0;

		if (isNull _currentGunner || {
			!alive _currentGunner
		}) then {
			if (!isNull _currentGunner && {
				!alive _currentGunner && _currentGunner in _vehicle
			}) then {
				moveOut _currentGunner;
				unassignVehicle _currentGunner;
			};

			private _replacementGunner = objNull;
			private _groupUnits = units _group;

			{
				if (
				alive _x &&
				!isPlayer _x &&
				_x != _leader &&
				!(_x in _vehicle) &&
				isNull assignedVehicle _x
				) exitWith {
					_replacementGunner = _x;
				};
			} forEach _groupUnits;

			if (!isNull _replacementGunner) then {
				_replacementGunner assignAsGunner _vehicle;
				[_replacementGunner] orderGetIn true;
				waitUntil {
					(_replacementGunner in _vehicle) || {
						!alive _replacementGunner
					}
				};
			};
		};
	} forEach _gunnerSeats;

	sleep 1;
};