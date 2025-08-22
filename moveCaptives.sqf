/*
	    moveCaptives.sqf
	    Usage: [getMarkerPos "prison_area"] execVM "moveCaptives_poll.sqf";
*/

params ["_prisonLocation"];

[_prisonLocation] spawn {
	params ["_prisonLocation"];
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
				[_x, _seatPos] spawn {
					params ["_unit", "_loc"];
					waitUntil {
						sleep 3;
						(_unit distance _loc) < 4 || !alive _unit
					};
					if (alive _unit) then {
						_unit disableAI "PATH";
						_unit setPosATL _loc;
						_unit setDir 180;
						_unit switchMove "Acts_AidlPsitMstpSsurWnonDnon_loop";
					};
				};
			};
		} forEach allUnits;
		sleep 5;
	};
};