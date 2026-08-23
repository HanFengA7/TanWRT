#!/usr/bin/ucode

'use strict';

import { readfile, writefile, stat, mkdir, lsdir } from 'fs';
import { cursor } from 'uci';

const HIST_DIR = '/tmp/tanwrt_temp';
const HIST_FILE = HIST_DIR + '/history.json';
const MAX_POINTS = 20000;

function basename(path) {
	const parts = split(path, '/');
	return parts[length(parts) - 1];
}

function load_cfg() {
	const u = cursor();
	const result = {
		sample_interval: 5,
		history_hours: 24,
		page_refresh: 3,
		warn_temp: 70,
		crit_temp: 85,
		sensors: []
	};

	const all = u.get_all('tanwrt_temp');

	if (all != null) {
		const g = all.settings != null ? all.settings : null;

		if (g != null) {
			if (g.warn_temp != null)
				result.warn_temp = int(g.warn_temp);
			if (g.crit_temp != null)
				result.crit_temp = int(g.crit_temp);
			if (g.sample_interval != null)
				result.sample_interval = int(g.sample_interval);
			if (g.history_hours != null)
				result.history_hours = int(g.history_hours);
			if (g.page_refresh != null)
				result.page_refresh = int(g.page_refresh);
		}

		for (let name in all) {
			const s = all[name];

			if (s.chip == null)
				continue;

			push(result.sensors, {
				chip: s.chip != null ? s.chip : '',
				label: s.label != null ? s.label : '',
				alias: s.alias != null ? s.alias : '',
				warn: s.warn != null ? int(s.warn) : 0,
				crit: s.crit != null ? int(s.crit) : 0
			});
		}
	}

	return result;
}

function scan_sensors() {
	const sensors = [];
	let idx = 0;

	for (let hname in lsdir('/sys/class/hwmon')) {
		const h = '/sys/class/hwmon/' + hname;
		let name = readfile(h + '/name');

		if (name == null)
			continue;

		name = trim(name);

		for (let fname in lsdir(h)) {
			if (substr(fname, length(fname) - length('_input')) != '_input')
				continue;

			const tpath = h + '/' + fname;
			const raw = readfile(tpath);

			if (raw == null)
				continue;

			const temp = +trim(raw) / 1000.0;
			const base = substr(tpath, 0, length(tpath) - length('_input'));
			let label = readfile(base + '_label');

			if (label != null)
				label = trim(label);

			idx++;
			push(sensors, {
				id: name + '_' + idx,
				chip: name,
				label: label != null ? label : '',
				temp: temp
			});
		}
	}

	for (let zname in lsdir('/sys/class/thermal')) {
		if (substr(zname, 0, length('thermal_zone')) != 'thermal_zone')
			continue;

		const z = '/sys/class/thermal/' + zname;
		const type = readfile(z + '/type');
		const raw = readfile(z + '/temp');

		if (type == null || raw == null)
			continue;

		idx++;
		push(sensors, {
			id: 'thermal_' + zname,
			chip: trim(type),
			label: trim(type),
			temp: +trim(raw) / 1000.0
		});
	}

	return sensors;
}

function apply_cfg(sensors, cfg) {
	const result = [];

	for (let i = 0; i < length(sensors); i++) {
		const s = sensors[i];
		let warn = cfg.warn_temp;
		let crit = cfg.crit_temp;
		let alias = s.label != '' ? s.label : s.chip;

		for (let j = 0; j < length(cfg.sensors); j++) {
			const sc = cfg.sensors[j];

			if (sc.chip == s.chip && (sc.label == '' || sc.label == s.label)) {
				if (sc.alias != '')
					alias = sc.alias;
				if (sc.warn > 0)
					warn = sc.warn;
				if (sc.crit > 0)
					crit = sc.crit;
			}
		}

		s.warn = warn;
		s.crit = crit;
		s.alias = alias;
		s.status = (s.temp >= crit) ? 'crit' : ((s.temp >= warn) ? 'warn' : 'ok');

		push(result, s);
	}

	return result;
}

function record_history(sensors, cfg) {
	try {
		if (stat(HIST_DIR) == null)
			mkdir(HIST_DIR, 0o755);

		const content = readfile(HIST_FILE);
		let hist = (content != null) ? json(content) : null;

		if (hist == null || hist.sensors == null)
			hist = { sensors: {} };

		const ts = time();
		const cutoff = ts - cfg.history_hours * 3600;

		for (let i = 0; i < length(sensors); i++) {
			const s = sensors[i];
			let arr = hist.sensors[s.id];

			if (arr == null)
				arr = hist.sensors[s.id] = [];

			const n = length(arr);

			if (n > 0 && arr[n - 1][0] == ts) {
				arr[n - 1][1] = s.temp;
				continue;
			}

			push(arr, [ ts, s.temp ]);

			while (length(arr) > MAX_POINTS || arr[0][0] < cutoff)
				shift(arr);
		}

		writefile(HIST_FILE, serialize(hist));
	}
	catch (err) {
		/* history is best-effort; never break the status query */
	}
}

function read_history(sensor, hours) {
	const content = readfile(HIST_FILE);

	if (content == null)
		return [];

	const hist = json(content);

	if (hist == null || hist.sensors == null)
		return [];

	const arr = hist.sensors[sensor];

	if (arr == null)
		return [];

	const cutoff = time() - hours * 3600;
	const points = [];

	for (let i = 0; i < length(arr); i++) {
		if (arr[i][0] >= cutoff)
			push(points, arr[i]);
	}

	return points;
}

const methods = {
	get_sensors: {
		call: function(request) {
			try {
				const cfg = load_cfg();
				const sensors = apply_cfg(scan_sensors(), cfg);

				record_history(sensors, cfg);

				return {
					sensors: sensors,
					ts: time()
				};
			}
			catch (err) {
				return { error: err };
			}
		}
	},

	get_history: {
		args: {
			sensor: 'string',
			range: 'string'
		},
		call: function(request) {
			try {
				let hours = 24;

				if (request.args.range == '1h')
					hours = 1;
				else if (request.args.range == '6h')
					hours = 6;

				return {
					points: read_history(request.args.sensor, hours)
				};
			}
			catch (err) {
				return { error: err };
			}
		}
	},

	get_config: {
		call: function(request) {
			try {
				return load_cfg();
			}
			catch (err) {
				return { error: err };
			}
		}
	},

	set_config: {
		args: {
			warn_temp: 'int',
			crit_temp: 'int',
			sensors: 'array'
		},
		call: function(request) {
			try {
				const u = cursor();
				const all = u.get_all('tanwrt_temp');

				if (all == null)
					return { error: 'config not found' };

				if (request.args.warn_temp != null && request.args.warn_temp > 0)
					u.set('tanwrt_temp', 'settings', 'warn_temp', string(request.args.warn_temp));
				if (request.args.crit_temp != null && request.args.crit_temp > 0)
					u.set('tanwrt_temp', 'settings', 'crit_temp', string(request.args.crit_temp));

				if (request.args.sensors != null) {
					for (let name in all) {
						const s = all[name];

						if (s.chip == null)
							continue;

						for (let i = 0; i < length(request.args.sensors); i++) {
							const sc = request.args.sensors[i];

							if (sc.chip == null)
								continue;

							if (sc.chip == s.chip && (sc.label == null || sc.label == '' || s.label == null || s.label == sc.label)) {
								if (sc.alias != null && sc.alias != '')
									u.set('tanwrt_temp', name, 'alias', sc.alias);
								if (sc.warn != null && sc.warn > 0)
									u.set('tanwrt_temp', name, 'warn', string(sc.warn));
								if (sc.crit != null && sc.crit > 0)
									u.set('tanwrt_temp', name, 'crit', string(sc.crit));
							}
						}
					}
				}

				u.save('tanwrt_temp');
				u.commit('tanwrt_temp');

				return { ok: true };
			}
			catch (err) {
				return { error: err };
			}
		}
	}
};

return { "tanwrt.temp": methods };
