-- Input Proxy
-- 
-- Unifies commonly used but non-standardized button/key commands for cleaner control profiles.

-- == START OF CONFIGURATION ==
local proxied_commands = {
	["disconnect_ap"] = "AP Disconnect Soft (button on yoke/flightstick)",
	["disconnect_at"] = "AT Disconnect Soft (button on thrust lever)"
}

local aircraft_aliases = {
	-- alias => list of possible search strings in path or aircraft file name (first found will match)
	-- note that these are actually pattern strings which also means that some characters,
    -- such as a hyphen, need to be escaped properly; see https://www.lua.org/pil/20.2.html
	["FFA320U"] = { "FlightFactor A320" },
	["IXEG733"] = { "IXEG 737 Classic" },
	["RotateMD80"] = { "Rotate%-MD%-80" },
	["ToLissA319"] = { "ToLiss319" },
	["Zibo738"] = { "B737%-800X" },
}

local aircraft_commands = {
	-- aircraft alias => configuration by command alias:
	--                   command => actual command (hover list of commands in X-Plane joystick configuration to reveal)
	--                   repeat  => should command trigger repeatedly? (called "once" in API although it is triggered many times)
	["default"] = {
		-- TODO: find reasonable defaults
		["disconnect_ap"] = {
			["command"] = "sim/autopilot/servos_fdir_off",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			["command"] = "sim/autopilot/autothrottle_off",
			["repeat"] = false,
		},
	},
	
	["FFA320U"] = {
		["disconnect_ap"] = {
			["command"] = "sim/autopilot/fdir_servos_up_one",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			["command"] = "a320/Pedestal/EngineDisconnect1_button",
			["repeat"] = false,
		},
	},
	
	["IXEG733"] = {
		["disconnect_ap"] = {
			["command"] = "ixeg/733/autopilot/AP_disengage",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			["command"] = "ixeg/733/autopilot/at_disengage",
			["repeat"] = false,
		},
	},
	
	["RotateMD80"] = {
		["disconnect_ap"] = {
			["command"] = "Rotate/md80/autopilot/ap_disc",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			["command"] = "Rotate/md80/autopilot/at_disc",
			["repeat"] = false,
		},
	},
	
	["ToLissA319"] = {
		["disconnect_ap"] = {
			["command"] = "sim/autopilot/fdir_servos_down_one",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			["command"] = "sim/autopilot/autothrottle_off",
			["repeat"] = false,
		},
	},
	
	["Zibo738"] = {
		["disconnect_ap"] = {
			--["command"] = "laminar/B738/autopilot/disconnect_toggle",
			["command"] = "laminar/B738/autopilot/disconnect_button",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			["command"] = "laminar/B738/autopilot/right_at_dis_press",
			["repeat"] = false,
		},
	},
}
-- == END OF CONFIGURATION ==

local version = '0.1dev'
local LOG_PREFIX = "[Input Proxy] "

print(LOG_PREFIX .. "Initializing Input Proxy version " .. version)

-- script globals
local system_path = nil
local dir_sep = nil
local loaded_aircraft_path = ""
local commands = {}

-- register commands (button/key mappings) before we do anything else
function register_proxied_commands(proxied_commands)
	for alias, description in pairs(proxied_commands) do
		local command = "FlyWithLua/inputproxy/" .. alias
		create_command(
			command,
			description,
			"inputproxy_command_begin('" .. alias .. "')",
			"inputproxy_command_once('" .. alias .. "')",
			"inputproxy_command_end('" .. alias .. "')"
		)
		print(LOG_PREFIX .. "Registered command " .. command)
	end
end

register_proxied_commands(proxied_commands)

-- prepare native calls using ffi and XPLM
--
-- see https://developer.x-plane.com/sdk/XPLMUtilities/
--
-- XPLM loading and a quick start on how to access X-Plane aircraft data thanks to:
--
-- jörn-jören jörensön (jjj/3j)  https://forums.x-plane.org/index.php?/forums/topic/123390-xplm-library-how-to-load-and-use/
-- Speedy JTAC 3.1 by XPJavelin  https://forums.x-plane.org/index.php?/files/file/50956-speedy-jtac/
local ffi = require("ffi")

function inputproxy_load_xplm()
	-- find the right lib to load
	local XPLMlib = ""
	if SYSTEM == "IBM" then
		-- Windows OS (no path and file extension needed)
		if SYSTEM_ARCHITECTURE == 64 then
				XPLMlib = "XPLM_64"  -- 64bit
		else
				XPLMlib = "XPLM"     -- 32bit
		end
	elseif SYSTEM == "LIN" then
		-- Linux OS (we need the path "Resources/plugins/" here for some reason)
		if SYSTEM_ARCHITECTURE == 64 then
				XPLMlib = "Resources/plugins/XPLM_64.so"  -- 64bit
		else
				XPLMlib = "Resources/plugins/XPLM.so"     -- 32bit
		end
	elseif SYSTEM == "APL" then
		-- Mac OS (we need the path "Resources/plugins/" here for some reason)
		XPLMlib = "Resources/plugins/XPLM.framework/XPLM" -- 64bit and 32 bit
	else
		return nil -- this should not happen
	end

	-- load the lib
	return ffi.load(XPLMlib)
end

local XPLM = inputproxy_load_xplm()

function inputproxy_find_system_path()
	local ffi_system_path = ffi.new("char[4096]")
	XPLM.XPLMGetSystemPath(ffi_system_path)
	return ffi.string(ffi_system_path)
end

function inputproxy_get_directory_separator()
	local xp_const_dir_sep = XPLM.XPLMGetDirectorySeparator()
	return ffi.string(xp_const_dir_sep, 1)
end

function inputproxy_get_aircraft()
	local ffi_aircraft_name = ffi.new("char[1024]")
	local ffi_aircraft_path = ffi.new("char[4096]")
	XPLM.XPLMGetNthAircraftModel(0, ffi_aircraft_name, ffi_aircraft_path)
	local name = ffi.string(ffi_aircraft_name)
	local path = ffi.string(ffi_aircraft_path)
	return {name, path}
end

-- that was enough native API binding, back to our script now...
function inputproxy_check_aircraft()
	local aircraft_info = inputproxy_get_aircraft()
	local aircraft_path = aircraft_info[2]
	
	if aircraft_path ~= loaded_aircraft_path then
		print(LOG_PREFIX .. "Aircraft change detected, was '" .. loaded_aircraft_path .. "', now '" .. aircraft_path .. "'")
		inputproxy_load_aircraft_config(aircraft_path)
	end
end

function inputproxy_string_split(haystack, needle)
	local last_pos = 0
	local next_pos = 1
	local result = {}
	
	repeat
		next_pos = string.find(haystack, needle, last_pos + 1)
		if next_pos ~= nil then
			item = string.sub(haystack, last_pos + 1, next_pos - 1)
			if item ~= "" then
				table.insert(result, item)
			end
			last_pos = next_pos
		end
	until next_pos == nil
	
	table.insert(result, string.sub(haystack, last_pos + 1))
	
	return result
end

function inputproxy_match_aircraft_path(aircraft_path)
	local pos = string.len(system_path) + 1
	local subpath = string.sub(aircraft_path, pos)
	
	local split = inputproxy_string_split(subpath, dir_sep)
	for i, part in ipairs(split) do
		for alias, needles in pairs(aircraft_aliases) do
			for i, needle in ipairs(needles) do
				if string.find(part, needle) ~= nil then
					return alias
				end
			end
		end
	end
	
	return nil
end

function inputproxy_load_aircraft_config(aircraft_path)
	loaded_aircraft_path = ""
	
	print(LOG_PREFIX .. "Configuring for " .. aircraft_path)
	
	aircraft_alias = inputproxy_match_aircraft_path(aircraft_path)
	if aircraft_alias ~= nil then
		print(LOG_PREFIX .. "matched configuration alias '" .. aircraft_alias .. "'")
	else
		print(LOG_PREFIX .. "aircraft path " .. aircraft_path .. " did not match any configured alias; falling back to default configuration")
		aircraft_alias = "default"
	end
	
	commands = aircraft_commands[aircraft_alias]
	if commands == nil then
		-- fall back to default if no such configuration exists
		print(LOG_PREFIX .. "WARNING: no configuration found for " .. aircraft_alias .. "; falling back to default configuration")
		commands = aircraft_commands["default"]
	else
		-- complete missing aliases with defaults if available
		for alias, default_command_config in pairs(aircraft_commands["default"]) do
			if commands[alias] == nil then
				print(LOG_PREFIX .. "Command alias " .. alias .. " has not been configured for " .. aircraft_alias .. ", using default configuration")
				commands[alias] = default_command_config
			end
		end
	end
	
	-- warn if any aliases are still missing
	for alias, _ in pairs(proxied_commands) do
		if commands[alias] == nil then
			print(LOG_PREFIX .. "WARNING: Command alias " .. alias .. " has not been configured for " .. aircraft_alias .. " (also no default has been configured)")
		end
	end
	
	loaded_aircraft_path = aircraft_path
end

function inputproxy_check_cached_command_available(command_config)
	local found = command_config["found"] or false
	
	if not found then
		found = (XPLMFindCommand(command_config["command"]) ~= nil)
		command_config["found"] = found
	end
	
	return found
end

function inputproxy_run_command(fn, command_config)
	local available = inputproxy_check_cached_command_available(command_config)
	
	if not available then
		print(LOG_PREFIX .. "command unavailable: " .. command)
	else
		fn(command_config["command"])
	end
end

function inputproxy_command_begin(proxy_alias)
	print(LOG_PREFIX .. "Pressed: " .. proxy_alias)
	
	local command_config = commands[proxy_alias]
	if command_config == nil then
		print(LOG_PREFIX .. "Proxy command alias not configured: " .. proxy_alias)
		return
	end
	
	inputproxy_run_command(command_begin, command_config)
end

function inputproxy_command_once(proxy_alias)
	local command_config = commands[proxy_alias] or {}
	local allowed_to_repeat = command_config["repeat"]
	
	if allowed_to_repeat ~= nil and not allowed_to_repeat then
		return
	end
	
	print(LOG_PREFIX .. "Repeat: " .. proxy_alias)
	
	inputproxy_run_command(command_once, command_config)
end

function inputproxy_command_end(proxy_alias)
	print(LOG_PREFIX .. "Released: " .. proxy_alias)
	
	local command_config = commands[proxy_alias]
	if command_config == nil then
		print(LOG_PREFIX .. "Proxy command alias not configured: " .. proxy_alias)
		return
	end
	
	inputproxy_run_command(command_end, command_config)
end

-- restore empty default in case it was omitted
if aircraft_commands["default"] == nil then
	aircraft_commands["default"] = {}
end

-- initialize only if XPLM is available
if XPLM == nil then
	print(LOG_PREFIX .. "XPLM not found, we are incompatible... Did X-Plane API change?")
else
	print(LOG_PREFIX .. "Defining native API functions")
	ffi.cdef[[
		void XPLMGetNthAircraftModel(int inIndex, char *outFileName, char *outPath);
		void XPLMGetSystemPath(char *outSystemPath);
		const char *XPLMGetDirectorySeparator(void);
	]]
	
	print(LOG_PREFIX .. "Querying X-Plane API for constants")
	system_path = inputproxy_find_system_path()
	dir_sep = inputproxy_get_directory_separator()
	
	print(LOG_PREFIX .. "Registering callbacks")
	do_sometimes("inputproxy_check_aircraft()")
	
	print(LOG_PREFIX .. "Performing first call")
	inputproxy_check_aircraft()
	
	print(LOG_PREFIX .. "Ready")
end
