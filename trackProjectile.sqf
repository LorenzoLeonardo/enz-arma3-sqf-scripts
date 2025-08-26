// [this] execVM "trackProjectile.sqf";

params [
	"_artillery",
	["_withProjectileMonitoring", false],
	["_withProjectileSound", true]
];

missionNamespace setVariable["withProjectileMonitoring", _withProjectileMonitoring, true];
missionNamespace setVariable["withProjectileSound", _withProjectileSound, true];

if (isNil {
	missionNamespace getVariable "trackedProjectiles"
}) then {
	missionNamespace setVariable ["trackedProjectiles", []];
};

_artillery addEventHandler ["Fired", {
	params ["_unit", "_weapon", "_muzzle", "_mode", "_ammo", "_mag", "_projectile"];

	if ((missionNamespace getVariable["withProjectileMonitoring", false])) then {
		[_projectile, _unit] spawn {
			params ["_proj", "_unit"];
			if (isNull (player getVariable["projectileToMonitor", objNull])) then {
				player setVariable ["projectileToMonitor", _proj, true];
			};

			private _lastPos = getPosASL _proj;
			private _markerName = format ["artyShell_%1", diag_tickTime];
			private _marker = createMarker [_markerName, _lastPos];
			_marker setMarkerShape "ICON";
			_marker setMarkerType "mil_dot";
			_marker setMarkerColor "ColorRed";
			_marker setMarkerText "Shell";

			private _tracked = missionNamespace getVariable ["trackedProjectiles", []];
			_tracked pushBack [_proj, _markerName];
			missionNamespace setVariable ["trackedProjectiles", _tracked];
			while { alive _proj } do {
				_lastPos = getPosASL _proj;
				_marker setMarkerPos _lastPos;
				sleep 0.1;
			};
			_marker setMarkerPos _lastPos;
			sleep 2;
			deleteMarker _markerName;
			private _tracked2 = missionNamespace getVariable ["trackedProjectiles", []];
			_tracked2 = _tracked2 select {
				(_x select 0) != _proj
			};
			missionNamespace setVariable ["trackedProjectiles", _tracked2];
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
				"a3\sounds_f\weapons\falling_bomb\fall_04.wss",
				"a3\sounds_f\arsenal\sfx\falling_bomb\fall_01.wss",
				"a3\sounds_f\arsenal\sfx\falling_bomb\fall_02.wss",
				"a3\sounds_f\arsenal\sfx\falling_bomb\fall_03.wss",
				"a3\sounds_f\arsenal\sfx\falling_bomb\fall_04.wss"
			];
			private _pitch = selectRandom [0.8, 0.9, 1.0];
			private _impactSoundPlayed = false;

			while { alive _proj } do {
				_lastPos = getPosASL _proj;
				private _sound = selectRandom _soundList;
				private _vel = velocity _proj;
				private _alt = _lastPos select 2;

				// Impact whistle (only once, when descending + low enough)
				if (!_impactSoundPlayed && {
					_alt < 1500 && {
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

addMissionEventHandler ["Draw3D", {
	private _tracked = missionNamespace getVariable ["trackedProjectiles", []];

	{
		private _proj = _x select 0;
		if (!isNull _proj && alive _proj) then {
			private _wpPos = getPosASL _proj;
			private _wpText = format ["Shell (%1 m)", round (player distance _wpPos)];

			drawIcon3D [
				"\A3\ui_f\data\map\markers\military\dot_CA.paa",
				[0, 1, 1, 1],
				_wpPos,
				0.5, 0.5,
				180,
				_wpText,
				2,
				0.030,
				"PuristaBold",
				"center",
				true,
				0,
				-0.03
			];
		};
	} forEach _tracked;
}];