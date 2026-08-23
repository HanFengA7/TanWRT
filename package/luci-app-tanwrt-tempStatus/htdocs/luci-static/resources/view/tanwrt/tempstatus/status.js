'use strict';
'require view';
'require dom';
'require poll';
'require ui';
'require tanwrt.tempstatus as tempstatus';

return view.extend({
	refreshInterval: 3,

	load: function() {
		return Promise.all([
			L.resolveDefault(tempstatus.getSensors(), { sensors: [] }),
			L.resolveDefault(tempstatus.getConfig(), { warn_temp: 70, crit_temp: 85, page_refresh: 3, sensors: [] })
		]);
	},

	render: function(data) {
		var sensors = (data && data[0] && data[0].sensors) ? data[0].sensors : [];
		var cfg = (data && data[1]) ? data[1] : { warn_temp: 70, crit_temp: 85, page_refresh: 3, sensors: [] };

		if (cfg.page_refresh > 0)
			this.refreshInterval = cfg.page_refresh;

		var self = this;

		var alertsEl = E('div');
		var cardsEl = E('div', { 'class': 'tanwrt-cards', 'style': 'display:flex;flex-wrap:wrap;gap:10px;margin-bottom:16px' });

		this.updateAlerts(alertsEl, sensors);
		this.updateCards(cardsEl, sensors);

		poll.add(function() {
			return tempstatus.getSensors().then(function(res) {
				var s = (res && res.sensors) ? res.sensors : [];
				self.updateAlerts(alertsEl, s);
				self.updateCards(cardsEl, s);
			}).catch(function() {});
		}, this.refreshInterval * 1000);

		return E('div', { 'class': 'cbi-map' }, [
			alertsEl,
			cardsEl,
			this.buildConfigSection(cfg)
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

	updateAlerts: function(el, sensors) {
		var items = [];

		for (var i = 0; i < sensors.length; i++) {
			var s = sensors[i];

			if (s.status != 'ok')
				items.push(E('li', {}, [ '%s: %s'.format(s.alias || s.chip, tempstatus.formatTemp(s.temp)) ]));
		}

		if (items.length)
			dom.content(el, E('div', { 'class': 'alert-message alert-danger', 'style': 'margin-bottom:16px' }, [
				E('strong', {}, [ _('Temperature alert') ]),
				E('ul', { 'style': 'margin:6px 0 0 18px' }, items)
			]));
		else
			dom.content(el, E([]));
	},

	updateCards: function(el, sensors) {
		var cards = [];

		for (var i = 0; i < sensors.length; i++) {
			var s = sensors[i];
			var color = this.statusColor(s.status);

			cards.push(E('div', {
				'class': 'cbi-section',
				'style': 'flex:1;min-width:160px;max-width:220px;padding:12px;border-left:4px solid ' + color
			}, [
				E('div', { 'class': 'cbi-value-title', 'style': 'font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis' },
					[ s.alias || s.label || s.chip ]),
				E('div', { 'style': 'font-size:28px;font-weight:500;color:' + color },
					[ s.temp.toFixed(1) ]),
				E('div', { 'class': 'cbi-value-description', 'style': 'font-size:12px;color:var(--color-text-secondary, #888)' },
					[ '%s%s · %s'.format(s.chip, s.label ? ' / ' + s.label : '', this.statusText(s.status)) ])
			]));
		}

		dom.content(el, cards);
	},

	buildConfigSection: function(cfg) {
		var self = this;

		var warnInput = E('input', { 'type': 'number', 'min': '0', 'max': '150', 'step': '1',
			'value': cfg.warn_temp, 'class': 'cbi-input-text', 'style': 'width:7em' });
		var critInput = E('input', { 'type': 'number', 'min': '0', 'max': '150', 'step': '1',
			'value': cfg.crit_temp, 'class': 'cbi-input-text', 'style': 'width:7em' });

		var saveBtn = E('button', { 'class': 'btn cbi-button-action important', 'click': function() {
			var warn = parseFloat(warnInput.value);
			var crit = parseFloat(critInput.value);

			if (!(warn > 0) || !(crit > 0)) {
				ui.addNotification(null, E('p', {}, [ _('Invalid threshold value') ]), 'error');
				return;
			}

			saveBtn.disabled = true;

			return tempstatus.setConfig(warn, crit, []).then(function() {
				ui.addNotification(null, E('p', {}, [ _('Settings saved') ]), 'info');
				location.reload();
			}).catch(function() {
				saveBtn.disabled = false;
				ui.addNotification(null, E('p', {}, [ _('Failed to save settings') ]), 'error');
			});
		} }, [ _('Save') ]);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Thresholds') ]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, [ _('Warning threshold (°C)') ]),
				E('div', { 'class': 'cbi-value-field' }, [ warnInput ]),
				E('div', { 'class': 'cbi-value-description' }, [ _('Sensors above this value are shown in yellow') ])
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, [ _('Critical threshold (°C)') ]),
				E('div', { 'class': 'cbi-value-field' }, [ critInput ]),
				E('div', { 'class': 'cbi-value-description' }, [ _('Sensors above this value are shown in red and trigger the alert banner') ])
			]),
			E('div', { 'class': 'cbi-page-actions' }, [ saveBtn ])
		]);
	}
});
