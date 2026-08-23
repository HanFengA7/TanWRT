'use strict';
'require baseclass';
'require rpc';

var callGetSensors = rpc.declare({
	object: 'tanwrt.temp',
	method: 'get_sensors',
	expect: { sensors: [] }
});

var callGetHistory = rpc.declare({
	object: 'tanwrt.temp',
	method: 'get_history',
	params: [ 'sensor', 'range' ],
	expect: { points: [] }
});

var callGetConfig = rpc.declare({
	object: 'tanwrt.temp',
	method: 'get_config',
	expect: { warn_temp: 0 }
});

var callSetConfig = rpc.declare({
	object: 'tanwrt.temp',
	method: 'set_config',
	params: [ 'warn_temp', 'crit_temp', 'sensors' ],
	expect: { ok: true }
});

return baseclass.extend({
	getSensors: function() {
		return callGetSensors();
	},

	getHistory: function(sensor, range) {
		return callGetHistory(sensor, range);
	},

	getConfig: function() {
		return callGetConfig();
	},

	setConfig: function(warn, crit, sensors) {
		return callSetConfig(warn, crit, sensors || []);
	},

	statusOf: function(temp, warn, crit) {
		if (temp >= crit)
			return 'crit';
		if (temp >= warn)
			return 'warn';
		return 'ok';
	},

	formatTemp: function(temp) {
		return '%s °C'.format(temp.toFixed(1));
	}
});
