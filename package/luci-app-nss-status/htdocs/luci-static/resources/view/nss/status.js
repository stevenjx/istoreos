'use strict';
'require view';
'require rpc';
'require poll';

var callNssStatus = rpc.declare({
	object: 'luci.nss',
	method: 'status',
	expect: {}
});

function badge(ok, on, off) {
	return E('span', {
		'style': 'font-weight:bold;color:' + (ok ? '#2e7d32' : '#c62828')
	}, (ok ? '● ' : '○ ') + (ok ? (on || _('正常')) : (off || _('未就绪'))));
}

return view.extend({
	load: function() {
		return callNssStatus();
	},

	render: function(data) {
		var self = this;

		var grid = E('div', {
			'id': 'nss-overview',
			'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:12px;margin-bottom:18px'
		});
		var modules = E('div', { 'id': 'nss-modules' });
		var cpu = E('div', { 'id': 'nss-cpu' });
		var info = E('div', { 'id': 'nss-info' });

		var root = E('div', {}, [
			E('h2', {}, _('NSS 硬件卸载状态')),
			E('p', { 'class': 'cbi-value-help' }, _('数据来自内核 debugfs 与 /proc/modules，每 5 秒自动刷新。')),
			grid, modules, cpu, info
		]);

		self.renderOverview(grid, data);
		self.renderModules(modules, data);
		self.renderCpu(cpu, data);
		self.renderInfo(info, data);

		poll.add(function() {
			return callNssStatus().then(function(d) {
				self.renderOverview(grid, d);
				self.renderModules(modules, d);
				self.renderCpu(cpu, d);
				self.renderInfo(info, d);
			});
		}, 5);

		return root;
	},

	renderOverview: function(node, d) {
		node.innerHTML = '';
		var items = [
			[ _('NSS 固件'), badge(!!d.firmware_loaded, _('已加载'), _('未加载')) ],
			[ _('Debugfs'), badge(!!d.debugfs_ready, _('可用'), _('不可用')) ],
			[ _('ECM 引擎'), badge(!!d.ecm_ready, _('就绪'), _('未就绪')) ],
			[ _('WiFi 卸载'), badge(Number(d.wifi_offload) === 1, _('已开启'), _('已关闭')) ]
		];
		items.forEach(function(it) {
			node.appendChild(E('div', { 'class': 'cbi-section', 'style': 'margin:0' }, [
				E('div', { 'style': 'font-size:13px;color:#888' }, it[0]),
				E('div', { 'style': 'font-size:17px;margin-top:6px' }, it[1])
			]));
		});
	},

	renderModules: function(node, d) {
		node.innerHTML = '';
		var tbody = E('tbody');
		var mods = d.modules || {};
		Object.keys(mods).sort().forEach(function(name) {
			var loaded = (mods[name] === true || mods[name] == 'true');
			tbody.appendChild(E('tr', {}, [
				E('td', {}, name),
				E('td', {}, badge(loaded, _('已加载'), _('未加载')))
			]));
		});
		node.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('内核模块加载状态')),
			E('table', { 'class': 'table cbi-section-table' }, [
				E('thead', {}, E('tr', {}, [
					E('th', {}, _('模块')),
					E('th', {}, _('状态'))
				])),
				tbody
			])
		]));
	},

	renderCpu: function(node, d) {
		node.innerHTML = '';
		var load = d.cpu_load || {};
		var rows = Object.keys(load);
		var tbody = E('tbody');
		if (!rows.length) {
			tbody.appendChild(E('tr', {},
				E('td', { 'colspan': '2' }, _('暂无 CPU 负载数据（NSS firmware 未运行？）'))));
		} else {
			rows.sort().forEach(function(k) {
				tbody.appendChild(E('tr', {}, [ E('td', {}, k), E('td', {}, load[k]) ]));
			});
		}
		node.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('NSS 核心负载 (ubi)')),
			E('table', { 'class': 'table cbi-section-table' }, [
				E('thead', {}, E('tr', {}, [
					E('th', {}, _('核心')),
					E('th', {}, _('负载'))
				])),
				tbody
			])
		]));
	},

	renderInfo: function(node, d) {
		node.innerHTML = '';
		var items = [
			[ _('固件版本'), d.fw_version || _('未知') ],
			[ _('ECM 会话数'), String(d.ecm_connections || 0) ],
			[ _('机型标识'), d.ipq_release || _('未知') ]
		];
		node.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('固件与会话信息')),
			E('table', { 'class': 'table cbi-section-table' },
				E('tbody', {}, items.map(function(it) {
					return E('tr', {}, [ E('td', {}, it[0]), E('td', {}, it[1]) ]);
				})))
		]));
	}
});
