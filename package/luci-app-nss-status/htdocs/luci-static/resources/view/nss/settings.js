'use strict';
'require view';
'require rpc';
'require ui';

var callNssStatus = rpc.declare({
	object: 'luci.nss',
	method: 'status',
	expect: {}
});

var callSetWifiOffload = rpc.declare({
	object: 'luci.nss',
	method: 'set_wifi_offload',
	expect: { ok: true }
});

return view.extend({
	load: function() {
		return callNssStatus();
	},

	render: function(data) {
		var cb = E('input', { 'type': 'checkbox', 'id': 'nss-wifi-offload' });
		cb.checked = (Number(data.wifi_offload) === 1);

		cb.addEventListener('change', function() {
			var enable = this.checked ? 1 : 0;
			callSetWifiOffload({ enable: enable }).then(function(r) {
				if (r && r.ok)
					ui.addNotification(null, E('p', {},
						_('WiFi 硬件卸载已') + (enable ? _('开启') : _('关闭')) + _('，重启 WiFi 或系统后完全生效。')), 'info');
				else
					ui.addNotification(null, E('p', {}, _('设置失败，请查看系统日志。')), 'danger');
			}).catch(function(e) {
				ui.addNotification(null, E('p', {}, _('设置失败: ') + e), 'danger');
			});
		});

		return E('div', {}, [
			E('h2', {}, _('NSS 硬件卸载设置')),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('WiFi 卸载 (ath11k)')),
				E('label', { 'for': 'nss-wifi-offload' }, [ cb, ' ' + _('启用 ath11k WiFi 硬件卸载') ]),
				E('p', { 'class': 'cbi-value-help' },
					_('开启后 WiFi 数据转发交由 NSS 硬件加速。默认关闭以保证稳定性（部分 Apple 设备 WPA 握手、AP_VLAN/mesh 存在已知问题）。设置会写入 /etc/modules.d/ath11k 以在重启后保留。'))
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('其他 NSS 功能')),
				E('p', { 'class': 'cbi-value-help' },
					_('桥接、VLAN、PPPoE、L2TP、PPTP、GRE、VXLAN、Qdisc、IPsec 加密与 SQM QoS 硬件卸载，均由编译进内核的 NSS 模块自动提供，无需单独配置。可在「状态 → NSS 加速」查看各模块加载状态。'))
			])
		]);
	}
});
