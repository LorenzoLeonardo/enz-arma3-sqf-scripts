// [this] execVM "trackProjectile.sqf";

params [
	"_artillery",
	["_withProjectileMonitoring", false],
	["_withProjectileSound", true]
];

missionNamespace setVariable["withProjectileMonitoring", _withProjectileMonitoring, true];
missionNamespace setVariable["withProjectileSound", _withProjectileSound, true];

_artillery addEventHandler ["Fired", {
	params ["_unit", "_weapon", "_muzzle", "_mode", "_ammo", "_mag", "_projectile"];

	if ((missionNamespace getVariable["withProjectileMonitoring", false])) then {
		[_projectile, _unit] spawn {
			params ["_proj", "_unit"];

			private _lastPos = getPosASL _proj;
			private _markerName = format ["artyShell_%1", diag_tickTime];
			private _marker = createMarker [_markerName, _lastPos];
			_marker setMarkerShape "ICON";
			_marker setMarkerType "mil_dot";
			_marker setMarkerColor "ColorRed";
			_marker setMarkerText "Shell";

			while { alive _proj } do {
				_lastPos = getPosASL _proj;
				_marker setMarkerPos _lastPos;
				sleep 0.1;
			};
			_marker setMarkerPos _lastPos;
			sleep 2;
			deleteMarker _markerName;
		};
	};

	if ((missionNamespace getVariable["withProjectileSound", false])) then {
		[_projectile, _unit] spawn {
			params ["_proj", "_unit"];

			private _lastPos = getPosASL _proj;
			private _soundList = [
				"a3\sounds_f\weapons\falling_bomb\fall_01.wss",
				"a3\sounds_f\weapons\falling_bomb\fall_02.wss",
				"a3\sounds_f\weapons\falling_bomb\fall_03.wss",
				"a3\sounds_f\weapons\falling_bomb\fall_04.wss"
			];
			private _pitch = selectRandom [0.9, 1.0, 1.1];
			private _impactSoundPlayed = false;

			while { alive _proj } do {
				_lastPos = getPosASL _proj;
				private _sound = selectRandom _soundList;
				private _vel = velocity _proj;
				private _alt = _lastPos select 2;

				// Impact whistle (only once, when descending + low enough)
				if (!_impactSoundPlayed && {
					_alt < 1000 && {
						_vel select 2 < 0
					}
				}) then {
					playSound3D [_sound, _proj, false, _lastPos, 3, _pitch, 6000];
					_impactSoundPlayed = true;
				};
				sleep 0.1;
			};
		};
	};
}];