'use strict';
'require view';
'require dom';
'require ui';
'require tanwrt.tempstatus as tempstatus';

var PALETTE = [ '#185fa5', '#1d9e75', '#d85a30', '#993556', '#854f0b', '#534ab7', '#0f6e56', '#a32d2d' ];

function pad2(n) {
	return (n < 10 ? '0' : '') + n;
}

return view.extend({
	ranges: [
		[ '1h', '1h' ],
		[ '6h', '6h' ],
		[ '24h', '24h' ]
	],

	currentRange: '1h',

	load: function() {
		return L.resolveDefault(tempstatus.getSensors(), { sensors: [] });
	},

	render: function(data) {
		var sensors = (data && data.sensors) ? data.sensors : [];

		this.sensors = sensors;
		this.hoverData = null;

		var self = this;

		var rangeBtns = E('div', { 'class': 'btn-group', 'style': 'margin-bottom:10px' });

		for (var i = 0; i < this.ranges.length; i++) {
			(function(range, label) {
				var btn = E('button', { 'class': 'btn', 'click': function() {
					self.currentRange = range;
					self.hoverData = null;
					self.loadChart(chartEl, range);
				} }, [ label ]);

				rangeBtns.appendChild(btn);
			})(this.ranges[i][0], this.ranges[i][1]);
		}

		var chartEl = E('div', { 'style': 'width:100%;height:360px;position:relative' });

		this.loadChart(chartEl, this.currentRange);

		return E('div', { 'class': 'cbi-map' }, [ rangeBtns, chartEl ]);
	},

	loadChart: function(el, range) {
		var self = this;
		var sensors = this.sensors || [];

		if (!sensors.length) {
			dom.content(el, E('em', {}, [ _('No temperature sensors found') ]));
			return;
		}

		var tasks = sensors.map(function(s) {
			return tempstatus.getHistory(s.id, range).then(function(res) {
				return { sensor: s, points: (res && res.points) ? res.points : [] };
			});
		});

		Promise.all(tasks).then(function(series) {
			self.renderChart(el, series, range);
		}).catch(function() {
			dom.content(el, E('em', {}, [ _('Failed to load history') ]));
		});
	},

	formatTime: function(ts, range) {
		var d = new Date(ts * 1000);

		if (range == '24h')
			return '%s-%s %s:00'.format(pad2(d.getMonth() + 1), pad2(d.getDate()), pad2(d.getHours()));

		return '%s:%s'.format(pad2(d.getHours()), pad2(d.getMinutes()));
	},

	nearestPoint: function(pts, ts) {
		var lo = 0, hi = pts.length - 1;

		while (lo < hi) {
			var mid = (lo + hi) >> 1;

			if (pts[mid][0] < ts)
				lo = mid + 1;
			else
				hi = mid;
		}

		if (lo > 0 && Math.abs(pts[lo - 1][0] - ts) < Math.abs(pts[lo][0] - ts))
			lo--;

		return pts[lo];
	},

	renderChart: function(el, series, range) {
		var W = 900, H = 320, PL = 46, PR = 14, PT = 10, PB = 26;
		var iw = W - PL - PR, ih = H - PT - PB;

		var valid = [];
		var minT = Infinity, maxT = -Infinity, minTs = Infinity, maxTs = -Infinity;

		for (var i = 0; i < series.length; i++) {
			var pts = series[i].points;

			if (!pts.length)
				continue;

			valid.push(series[i]);

			for (var j = 0; j < pts.length; j++) {
				if (pts[j][1] < minT) minT = pts[j][1];
				if (pts[j][1] > maxT) maxT = pts[j][1];
				if (pts[j][0] < minTs) minTs = pts[j][0];
				if (pts[j][0] > maxTs) maxTs = pts[j][0];
			}
		}

		if (!valid.length) {
			dom.content(el, E('em', {}, [ _('No temperature history yet. Keep a status page open to collect samples.') ]));
			return;
		}

		if (!(maxT > minT)) {
			minT -= 1;
			maxT += 1;
		}

		var pad = (maxT - minT) * 0.1 || 1;
		minT -= pad;
		maxT += pad;

		if (!(maxTs > minTs))
			maxTs = minTs + 3600;

		function x(ts) { return PL + (ts - minTs) / (maxTs - minTs) * iw; }
		function y(t) { return PT + (maxT - t) / (maxT - minT) * ih; }

		var svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + W + ' ' + H +
			'" style="width:100%;height:100%;display:block">';

		svg += '<g fill="none" stroke="rgba(128,128,128,0.25)" stroke-width="0.5">';

		for (var g = 0; g <= 4; g++) {
			var gy = PT + ih * g / 4;
			var gt = maxT - (maxT - minT) * g / 4;

			svg += '<line x1="' + PL + '" y1="' + gy.toFixed(1) + '" x2="' + (W - PR) +
				'" y2="' + gy.toFixed(1) + '"/>';
			svg += '<text x="' + (PL - 6) + '" y="' + (gy + 4).toFixed(1) +
				'" text-anchor="end" font-size="11" fill="currentColor">' + gt.toFixed(1) + '</text>';
		}

		svg += '</g>';

		for (var ti = 0; ti <= 3; ti++) {
			var tts = minTs + (maxTs - minTs) * ti / 3;

			svg += '<text x="' + x(tts).toFixed(1) + '" y="' + (H - 8) +
				'" text-anchor="middle" font-size="11" fill="currentColor">' +
				this.formatTime(tts, range) + '</text>';
		}

		for (var k = 0; k < valid.length; k++) {
			var pts = valid[k].points;
			var step = Math.max(1, Math.floor(pts.length / (iw * 2)));
			var d = '';

			if (pts.length == 1) {
				d = 'M' + x(pts[0][0]).toFixed(1) + ' ' + y(pts[0][1]).toFixed(1) + ' l0.1 0';
			}
			else {
				for (var p = 0; p < pts.length; p += step)
					d += (p == 0 ? 'M' : 'L') + x(pts[p][0]).toFixed(1) + ' ' + y(pts[p][1]).toFixed(1);
			}

			var color = PALETTE[k % PALETTE.length];

			svg += '<path d="' + d + '" fill="none" stroke="' + color +
				'" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>';
		}

		svg += '</svg>';

		var box = E('div', { 'style': 'width:100%;height:100%;position:relative' }, []);
		box.innerHTML = svg;

		var vline = E('div', {
			'style': 'position:absolute;top:0;bottom:0;width:1px;background:rgba(128,128,128,0.6);display:none;pointer-events:none'
		});
		var tip = E('div', {
			'style': 'position:absolute;display:none;background:var(--color-background-secondary,#f5f5f5);' +
				'border:1px solid var(--color-border-secondary,rgba(0,0,0,0.3));padding:4px 8px;' +
				'border-radius:6px;font-size:12px;pointer-events:none;z-index:5;white-space:nowrap'
		});

		box.appendChild(vline);
		box.appendChild(tip);

		this.hoverData = {
			series: valid, minTs: minTs, maxTs: maxTs, minT: minT, maxT: maxT,
			iw: iw, ih: ih, PL: PL, PT: PT, PR: PR
		};

		var self = this;

		box.addEventListener('mousemove', function(ev) {
			var rect = box.getBoundingClientRect();
			var ratio = (ev.clientX - rect.left) / rect.width;
			var hd = self.hoverData;

			if (!hd || !hd.series.length)
				return;

			var ts = hd.minTs + (hd.maxTs - hd.minTs) * ratio;
			var px = hd.PL + ratio * hd.iw;

			vline.style.display = 'block';
			vline.style.left = px.toFixed(1) + 'px';

			var lines = [];
			var color;

			for (var k2 = 0; k2 < hd.series.length; k2++) {
				var s = hd.series[k2];
				var np = self.nearestPoint(s.points, ts);

				color = PALETTE[k2 % PALETTE.length];
				lines.push(E('div', { 'style': 'color:' + color }, [
					'%s: %s'.format(s.sensor.alias || s.sensor.label || s.sensor.chip, np[1].toFixed(1) + ' °C')
				]));
			}

			var t = new Date(ts * 1000);

			dom.content(tip, E('div', {}, [
				E('div', { 'style': 'font-weight:500;margin-bottom:2px' },
					[ '%s:%s:%s'.format(pad2(t.getHours()), pad2(t.getMinutes()), pad2(t.getSeconds())) ]),
				lines
			]));

			tip.style.display = 'block';
			tip.style.left = (px + 12) + 'px';
			tip.style.top = '8px';
		});

		box.addEventListener('mouseleave', function() {
			vline.style.display = 'none';
			tip.style.display = 'none';
		});

		var legend = E('div', { 'style': 'margin-top:6px;font-size:12px' },
			valid.map(function(v, k) {
				var color = PALETTE[k % PALETTE.length];

				return E('span', { 'style': 'margin-right:14px;display:inline-flex;align-items:center;gap:5px' }, [
					E('span', { 'style': 'display:inline-block;width:10px;height:10px;border-radius:50%;background:' + color }),
					v.sensor.alias || v.sensor.label || v.sensor.chip
				]);
			}));

		dom.content(el, E('div', {}, [ box, legend ]));
	}
});
