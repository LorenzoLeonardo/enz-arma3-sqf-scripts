// [this] execVM "trackProjectile.sqf";

params ["_artillery"];

_artillery addEventHandler ["Fired", {
	params ["_unit", "_weapon", "_muzzle", "_mode", "_ammo", "_mag", "_projectile"];

	// Example: track until impact
	[_projectile, _unit] spawn {
		params ["_proj", "_unit"];
		// create a unique marker name for this shell
		private _markerName = format ["artyShell_%1", diag_tickTime];
		private _marker = createMarker [_markerName, getPosASL _proj];
		_marker setMarkerShape "ICON";
		_marker setMarkerType "mil_dot";
		_marker setMarkerColor "ColorRed";
		_marker setMarkerText "Shell";

		private _lastPos = getPosASL _proj;

		while { alive _proj } do {
			_lastPos = getPosASL _proj;
			_marker setMarkerPos _lastPos;
			sleep 0.01;
		};
		_marker setMarkerPos _lastPos;
		sleep 1;
		deleteMarker _markerName;
	};
}];