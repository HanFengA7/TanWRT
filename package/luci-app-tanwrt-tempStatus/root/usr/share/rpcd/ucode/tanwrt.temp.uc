// TanWRT temperature status RPC backend
// Collects temperatures from /sys/class/hwmon and /sys/class/thermal,
// keeps a ring-buffer history in /tmp/tanwrt_temp/history.json and
// exposes read/write config via uci.
//
// Exposed methods (ubus object "tanwrt.temp"):
//   get_sensors           -> { sensors: [...], ts: <epoch> }
//   get_history(sensor, range) -> { points: [[ts, temp], ...] }
//   get_config            -> { warn_temp, crit_temp, sample_interval, history_hours, page_refresh, sensors: [...] }
//   set_config(warn_temp, crit_temp, sensors) -> { ok: true }

'use strict';

import * as rpcd;
import * as fs;
import * as uci;

const HIST_DIR = '/tmp/tanwrt_temp';
const HIST_FILE = HIST_DIR + '/history.json';
const MAX_POINTS = 20000;

function basename(path) {
	var parts = split(path, '/');
	return parts[len(parts) - 1];
}

function load_cfg() {
	var cfg = {
		sample_interval: 5,
		history_hours: 24,
		page_refresh: 3,
		warn_temp: 70,
		crit_temp: 85,
		sensors: []
	};

	var c = uci.load('tanwrt_temp');

	if (c != null && c.globals != null && c.globals.settings != null) {
		var g = c.globals.settings;

		if (g.sample_interval != null)
			cfg.sample_interval = int(g.sample_interval);
		if (g.history_hours != null)
			cfg.history_hours = int(g.history_hours);
		if (g.page_refresh != null)
			cfg.page_refresh = int(g.page_refresh);
		if (g.warn_temp != null)
			cfg.warn_temp = int(g.warn_temp);
		if (g.crit_temp != null)
			cfg.crit_temp = int(g.crit_temp);
	}

	if (c != null && c.sensor != null) {
		for (var name in c.sensor) {
			var s = c.sensor[name];

			cfg.sensors.push({
				chip: s.chip != null ? s.chip : '',
				label: s.label != null ? s.label : '',
				alias: s.alias != null ? s.alias : '',
				warn: s.warn != null ? int(s.warn) : 0,
				crit: s.crit != null ? int(s.crit) : 0
			});
		}
	}

	return cfg;
}

function scan_sensors() {
	var sensors = [];
	var idx = 0;
	var hwmons = fs.glob('/sys/class/hwmon/hwmon*');
	hwmons.sort();

	for (var i = 0; i < len(hwmons); i++) {
		var h = hwmons[i];
		var name = fs.readfile(h + '/name');

		if (name == null)
			continue;

		name = trim(name);

		var temps = fs.glob(h + '/temp*_input');
		temps.sort();

		for (var j = 0; j < len(temps); j++) {
			var tpath = temps[j];
			var raw = fs.readfile(tpath);

			if (raw == null)
				continue;

			var temp = float(trim(raw)) / 1000.0;
			var base = substr(tpath, 0, len(tpath) - len('_input'));
			var label = fs.readfile(base + '_label');

			if (label != null)
				label = trim(label);

			idx++;
			sensors.push({
				id: name + '_' + idx,
				chip: name,
				label: label != null ? label : '',
				temp: temp
			});
		}
	}

	// Fall back to ACPI thermal zones for anything hwmon did not cover
	var zones = fs.glob('/sys/class/thermal/thermal_zone*');
	zones.sort();

	for (var i = 0; i < len(zones); i++) {
		var z = zones[i];
		var type = fs.readfile(z + '/type');
		var raw = fs.readfile(z + '/temp');

		if (type == null || raw == null)
			continue;

		idx++;
		sensors.push({
			id: 'thermal_' + basename(z),
			chip: trim(type),
			label: trim(type),
			temp: float(trim(raw)) / 1000.0
		});
	}

	return sensors;
}

function apply_cfg(sensors, cfg) {
	var result = [];

	for (var i = 0; i < len(sensors); i++) {
		var s = sensors[i];
		var warn = cfg.warn_temp;
		var crit = cfg.crit_temp;
		var alias = s.label != '' ? s.label : s.chip;

		for (var j = 0; j < len(cfg.sensors); j++) {
			var sc = cfg.sensors[j];

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

		result.push(s);
	}

	return result;
}

function ensure_dir() {
	if (fs.stat(HIST_DIR) == null)
		fs.mkdir(HIST_DIR, 0o755);
}

function record_history(sensors, cfg) {
	ensure_dir();

	var content = fs.readfile(HIST_FILE);
	var hist = (content != null) ? json(content) : null;

	if (hist == null || hist.sensors == null)
		hist = { sensors: {} };

	var ts = time();
	var cutoff = ts - cfg.history_hours * 3600;

	for (var i = 0; i < len(sensors); i++) {
		var s = sensors[i];
		var arr = hist.sensors[s.id];

		if (arr == null)
			arr = hist.sensors[s.id] = [];

		var n = len(arr);

		// Deduplicate: multiple pollers within the same second overwrite instead of appending
		if (n > 0 && arr[n - 1][0] == ts) {
			arr[n - 1][1] = s.temp;
			continue;
		}

		arr.push([ ts, s.temp ]);

		while (len(arr) > MAX_POINTS || arr[0][0] < cutoff)
			arr.shift();
	}

	fs.writefile(HIST_FILE, serialize(hist));
}

function read_history(sensor, hours) {
	var content = fs.readfile(HIST_FILE);

	if (content == null)
		return [];

	var hist = json(content);

	if (hist == null || hist.sensors == null)
		return [];

	var arr = hist.sensors[sensor];

	if (arr == null)
		return [];

	var cutoff = time() - hours * 3600;
	var points = [];

	for (var i = 0; i < len(arr); i++) {
		if (arr[i][0] >= cutoff)
			points.push(arr[i]);
	}

	return points;
}

rpcd.declare({
	'get_sensors': {
		'call': function() {
			var cfg = load_cfg();
			var sensors = apply_cfg(scan_sensors(), cfg);

			record_history(sensors, cfg);

			return {
				sensors: sensors,
				ts: time()
			};
		}
	},

	'get_history': {
		'args': {
			'sensor': 'string',
			'range': 'string'
		},
		'call': function(args) {
			var hours = 24;

			if (args.range == '1h')
				hours = 1;
			else if (args.range == '6h')
				hours = 6;

			return {
				points: read_history(args.sensor, hours)
			};
		}
	},

	'get_config': {
		'call': function() {
			var cfg = load_cfg();

			return {
				sample_interval: cfg.sample_interval,
				history_hours: cfg.history_hours,
				page_refresh: cfg.page_refresh,
				warn_temp: cfg.warn_temp,
				crit_temp: cfg.crit_temp,
				sensors: cfg.sensors
			};
		}
	},

	'set_config': {
		'args': {
			'warn_temp': 'int',
			'crit_temp': 'int',
			'sensors': 'array'
		},
		'call': function(args) {
			var c = uci.cfg('tanwrt_temp');

			if (args.warn_temp != null && args.warn_temp > 0)
				c.globals.settings.warn_temp = string(args.warn_temp);
			if (args.crit_temp != null && args.crit_temp > 0)
				c.globals.settings.crit_temp = string(args.crit_temp);

			if (args.sensors != null) {
				for (var i = 0; i < len(args.sensors); i++) {
					var sc = args.sensors[i];

					if (sc.chip == null)
						continue;

					for (var name in c.sensor) {
						var s = c.sensor[name];

						if (s.chip == sc.chip && (s.label == null || s.label == '' || sc.label == null || s.label == sc.label)) {
							if (sc.alias != null && sc.alias != '')
								s.alias = sc.alias;
							if (sc.warn != null && sc.warn > 0)
								s.warn = string(sc.warn);
							if (sc.crit != null && sc.crit > 0)
								s.crit = string(sc.crit);
						}
					}
				}
			}

			uci.save('tanwrt_temp');
			uci.commit('tanwrt_temp');

			return { ok: true };
		}
	}
});
