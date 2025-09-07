/*
	    moveCaptives.sqf
	    Usage: [getMarkerPos "prison_area", 180] execVM "moveCaptives.sqf";
*/

params ["_prisonLocation", "_rotation"];

[_prisonLocation, _rotation] spawn {
	params ["_prisonLocation", "_rotation"];
	private _handled = [];
	private _seatIndex = 0;
	while { true } do {
		{
			if (captive _x && !(_x in _handled) && (lifeState _x != "INCAPACITATED")) then {
				_handled pushBack _x;

				// assign seating slot
				private _col = _seatIndex mod 5;
				private _row = floor (_seatIndex / 5);
				private _offset = [(_col * 1.5), (_row * 1.5), 0];
				private _seatPos = _prisonLocation vectorAdd _offset;
				_seatIndex = _seatIndex + 1;

				// disarm + remove from group
				[_x] joinSilent grpNull;

				// order to move to seat position
				_x doMove _seatPos;

				// keep them moving until they arrive
				[_x, _seatPos, _rotation] spawn {
					params ["_unit", "_loc", "_rotation"];
					while { alive _unit && (_unit distance _loc) >= 4 } do {
						sleep 3;
					};
					if (alive _unit) then {
						_unit disableAI "PATH";
						_unit setPosATL _loc;
						_unit setDir _rotation;
						_unit switchMove "AmovPercMstpSsurWnonDnon";
					};
				};
			};
		} forEach allUnits;
		sleep 5;
	};
};