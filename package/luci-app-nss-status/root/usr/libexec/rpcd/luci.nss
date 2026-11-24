#!/usr/bin/env lua

-- rpcd backend for luci-app-nss-status
-- Exposes NSS driver / firmware / ECM runtime state over ubus as "luci.nss"

local jsonc = require "luci.jsonc"
local fs = require "nixio.fs"

-- Read first line of a file, trimmed. Return nil if unavailable.
local function readline(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local line = f:read("*l")
	f:close()
	if line then line = line:gsub("^%s+", ""):gsub("%s+$", "") end
	return line
end

local function file_exists(path)
	return fs.stat(path) ~= nil
end

-- Check whether a kernel module is currently loaded (from /proc/modules).
local function module_loaded(name)
	local f = io.open("/proc/modules", "r")
	if not f then return false end
	for line in f:lines() do
		if line:match("^" .. name:gsub("%-", "_") .. "%s") then
			f:close()
			return true
		end
	end
	f:close()
	return false
end

-- Collect all key/value pairs from a debugfs stats file into a table.
local function read_stats_file(path)
	local out = {}
	local f = io.open(path, "r")
	if not f then return out end
	for line in f:lines() do
		local k, v = line:match("([^=]+)=%s*(.*)")
		if k and v then
			k = k:gsub("^%s+", ""):gsub("%s+$", "")
			v = v:gsub("^%s+", ""):gsub("%s+$", "")
			out[k] = v
		end
	end
	f:close()
	return out
end

-- Sum selected counters from cpu_load_ubi to give a quick "is NSS doing work" number.
local function nss_cpu_load()
	local root = "/sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi"
	local load = {}
	local dir = fs.dir(root)
	if dir then
		for entry in dir do
			if entry ~= "." and entry ~= ".." then
				local v = readline(root .. "/" .. entry)
				if v then load[entry] = v end
			end
		end
		dir:close()
	end
	return load
end

local function gather_status()
	local s = {}

	-- Overall state
	s.debugfs_ready = file_exists("/sys/kernel/debug/qca-nss-drv/stats")
	s.firmware_loaded = module_loaded("qca_nss_drv") and s.debugfs_ready

	-- Module load states (what the user most wants to see at a glance)
	local modules = {
		"qca_nss_dp", "qca_ssdk", "qca_nss_drv", "qca_nss_ecm",
		"qca_nss_bridge_mgr", "qca_nss_vlan_mgr", "qca_nss_crypto",
		"qca_nss_cfi_cryptoapi", "qca_nss_macsec", "nss_ifb",
		"qca_nss_pppoe", "qca_nss_l2tpv2", "qca_nss_pptp", "qca_nss_gre",
		"qca_nss_vxlanmgr", "qca_nss_qdisc", "qca_nss_mcs", "ath11k",
	}
	s.modules = {}
	for _, m in ipairs(modules) do
		s.modules[m] = module_loaded(m)
	end

	-- Firmware version hint from the NSS debugfs project node (if present)
	local project = readline("/sys/kernel/debug/qca-nss-drv/project/version")
	   or readline("/sys/kernel/debug/qca-nss-drv/stats/project/version")
	s.fw_version = project or "unknown"

	-- ECM readiness and connection count
	s.ecm_ready = file_exists("/sys/kernel/debug/ecm/ecm_state/state_dev_major")
	s.ecm_connections = 0
	if s.ecm_ready then
		local f = io.open("/sys/kernel/debug/ecm/ecm_state/ecm_state", "r")
		if f then
			local content = f:read("*a")
			f:close()
			-- ECM state file lists entries; count non-empty lines as a rough proxy
			local n = 0
			for line in (content or ""):gmatch("[^\n]+") do
				if #line > 0 then n = n + 1 end
			end
			s.ecm_connections = n
		end
	end

	-- CPU offload load
	s.cpu_load = nss_cpu_load()

	-- WiFi offload state (0 = off, 1 = on)
	-- Prefer the live kernel parameter; if ath11k is not loaded (or on a
	-- non-NSS test machine), fall back to the persisted modules.d setting so
	-- the UI still reflects the configured value after a toggle.
	local offload = readline("/sys/module/ath11k/parameters/nss_offload")
	if offload == nil then
		local modfile = io.open("/etc/modules.d/ath11k", "r")
		if modfile then
			local content = modfile:read("*a") or ""
			modfile:close()
			offload = content:match("nss_offload=(%d+)")
		end
	end
	s.wifi_offload = tonumber(offload or "0") or 0

	-- Kernel / NSS firmware build info (written by mac80211 install hook)
	s.ipq_release = readline("/etc/ipq_release") or ""

	return s
end

local methods = {
	status = {
		call = function()
			return { code = 0, result = jsonc.stringify(gather_status()) }
		end
	},

	set_wifi_offload = {
		args = { enable = 0 },
		call = function(args)
			local want = (args.enable and tonumber(args.enable) == 1) and 1 or 0
			-- Runtime toggle (takes effect immediately if ath11k loaded)
			local param = "/sys/module/ath11k/parameters/nss_offload"
			if file_exists(param) then
				local f = io.open(param, "w")
				if f then
					f:write(tostring(want))
					f:close()
				end
			end
			-- Persist across reboot
			local modfile = "/etc/modules.d/ath11k"
			local content = ""
			local f = io.open(modfile, "r")
			if f then content = f:read("*a") or ""; f:close() end
			if content:match("nss_offload") then
				content = content:gsub("nss_offload=%d+", "nss_offload=" .. want)
			else
				content = "ath11k nss_offload=" .. want .. " frame_mode=2\n" .. content
			end
			local w = io.open(modfile, "w")
			if w then w:write(content); w:close() end
			return { code = 0, result = jsonc.stringify({ ok = true, wifi_offload = want }) }
		end
	},
}

local function parse_input()
	local parse = jsonc.new()
	local done, err
	while true do
		local chunk = io.read(4096)
		if not chunk then break end
		if not done and not err then done, err = parse:parse(chunk) end
	end
	if not done then
		print(jsonc.stringify({ error = err or "Incomplete input" }))
		os.exit(1)
	end
	return parse:get()
end

if arg[1] == "list" then
	local rv = {}
	for name, method in pairs(methods) do rv[name] = method.args or {} end
	print(jsonc.stringify(rv):gsub(":%[%]", ":{}"))
elseif arg[1] == "call" then
	local args = parse_input()
	local method = methods[arg[2]]
	if not method then
		print(jsonc.stringify({ error = "Method not found" }))
		os.exit(1)
	end
	local run = method.call(args)
	print(run.result)
	os.exit(run.code or 0)
end
