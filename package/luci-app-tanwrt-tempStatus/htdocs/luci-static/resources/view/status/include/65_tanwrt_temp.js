'use strict';
'require baseclass';
'require rpc';
'require uci';

var callGetSensors = rpc.declare({
	object: 'tanwrt.temp',
	method: 'get_sensors',
	expect: {}
});

return baseclass.extend({
	title: _('Temperature'),

	load: function() {
		return Promise.all([
			L.resolveDefault(callGetSensors(), { sensors: [] }),
			uci.load('tanwrt_temp').then(function() {
				return uci.get('tanwrt_temp', 'settings', 'enable_homepage');
			})
		]);
	},

	statusColor: function(status) {
		if (status == 'crit')
			return '#e24b4a';
		if (status == 'warn')
			return '#ef9f27';
		return '#3b6d11';
	},

	statusText: function(status) {
		if (status == 'crit')
			return _('Critical');
		if (status == 'warn')
			return _('Warning');
		return _('OK');
	},

	render: function(data) {
		if (data == null || data[1] == '0')
			return null;

		var sensors = (data[0] && data[0].sensors) ? data[0].sensors : [];

		if (!sensors.length)
			return E('em', {}, [ _('No temperature sensors found') ]);

		var rows = [];

		for (var i = 0; i < sensors.length; i++) {
			var s = sensors[i];
			var color = this.statusColor(s.status);

			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, [ s.alias || s.label || s.chip ]),
				E('td', { 'class': 'td left', 'style': 'font-weight:500;color:' + color },
					[ s.temp.toFixed(1) + ' °C' ]),
				E('td', { 'class': 'td left' }, [
					E('span', { 'style': 'display:inline-block;width:8px;height:8px;border-radius:50%;background:' + color + ';margin-right:6px' }),
					E('span', { 'style': 'color:' + color }, [ this.statusText(s.status) ])
				])
			]));
		}

		return E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr' }, [
				E('th', { 'class': 'th left' }, [ _('Sensor') ]),
				E('th', { 'class': 'th left' }, [ _('Temperature') ]),
				E('th', { 'class': 'th left' }, [ _('Status') ])
			]),
			rows
		]);
	}
});
