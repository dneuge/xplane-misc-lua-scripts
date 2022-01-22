-- Input Proxy
-- 
-- Unifies commonly used but non-standardized button/key commands for cleaner control profiles.

-- == START OF CONFIGURATION ==
local proxied_commands = {
	["control_fd"] = "FD Control Input (CWS, TCS, FD Sync, ...)",
	["disconnect_ap"] = "AP Disconnect Soft (button on yoke/flightstick)",
	["disconnect_at"] = "AT Disconnect Soft (button on thrust lever)",
	["to_ga"] = "TO/GA"
}

local aircraft_aliases = {
	-- alias => list of possible search strings in path or aircraft file name (first found will match)
	-- note that these are actually pattern strings which also means that some characters,
    -- such as a hyphen, need to be escaped properly; see https://www.lua.org/pil/20.2.html
	["FelisB742"] = { "747 Felis" },
	["FFA320U"] = { "FlightFactor A320" },
	["FJSQ4XP"] = { "FlyJSim_Q4XP" },
	["HSCL650"] = { "CL650" },
	["IXEG733"] = { "IXEG 737 Classic" },
	["iniA300"] = { "iniSimulations A300", "iniSimulations_A310" },
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
		["control_fd"] = {
			["command"] = "sim/none/none",
			["repeat"] = false,
		},
		["disconnect_ap"] = {
			["command"] = "sim/autopilot/servos_fdir_off",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			["command"] = "sim/autopilot/autothrottle_off",
			["repeat"] = false,
		},
		["to_ga"] = {
			-- This command refers to the TO/GA button usually found on thrust levers.
			-- As every aircraft appears to do this differently and issuing the wrong command
			-- for TO/GA may have severe effects this is left INOP by default and should be
			-- configured for every aircraft individually.
			["command"] = "sim/none/none",
			["repeat"] = false
		},
	},
	
	["FelisB742"] = {
		["disconnect_ap"] = {
			["command"] = "sim/autopilot/fdir_toggle",
			["repeat"] = false,
		},
		-- B742 does not appear to have any disconnect buttons on throttles, set INOP
		["disconnect_at"] = {
			["command"] = "sim/none/none",
			["repeat"] = false,
		},
		-- B742 also has no TO/GA button (only mode selector)
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
		-- A320 has no TO/GA button (it's a thrust detent instead)
	},
	
	["FJSQ4XP"] = {
		-- TODO: find command for GA button on throttles
		["control_fd"] = {
			["command"] = "FJS/Q4XP/Autopilot/TCS_Engage",
			["repeat"] = false,
		},
		["disconnect_ap"] = {
			["command"] = "FJS/Q4XP/Autopilot/AUTOPILOT_DISCONNECT",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			-- Q4 has no auto-thrust, set INOP
			["command"] = "sim/none/none",
			["repeat"] = false,
		},
		["to_ga"] = {
			["command"] = "sim/autopilot/take_off_go_around",
			["repeat"] = false
		},
	},
	
	["HSCL650"] = {
		-- there also is a stab trim disconnect button on yokes: CL650/contwheel/0/trim_disc
		["control_fd"] = {
			["command"] = "CL650/contwheel/0/fd_sync",
			["repeat"] = false,
		},
		["disconnect_ap"] = {
			["command"] = "CL650/contwheel/0/ap_disc",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			-- only one button supported for now but both exist:
			--   CL650/pedestal/throttle/at_disc_L
			--   CL650/pedestal/throttle/at_disc_R
			["command"] = "CL650/pedestal/throttle/at_disc_L",
			["repeat"] = false,
		},
		["to_ga"] = {
			["command"] = "CL650/pedestal/throttle/toga_L",
			["repeat"] = false
		},
	},
	
	["iniA300"] = {
		-- TODO: check if there is a CWS button on yokes (A300/MCDU/cws_toggle appears to be FCP)
		["disconnect_ap"] = {
			["command"] = "A300/MCDU/yoke_ap_disconnect_captain",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			["command"] = "A300/MCDU/disconnect_at",
			["repeat"] = false,
		},
		-- TODO: check if realistic - I'm not sure if there really is a TO/GA button
		--       on A300/A310 throttles or if that's just triggering the "magic screw"
		--       provided by iniSimulations for convenience?
		["to_ga"] = {
			["command"] = "A300/MCDU/takeoff_goaround_trigger",
			["repeat"] = false
		},
	},

	["IXEG733"] = {
		-- TODO: find command for TO/GA
		["disconnect_ap"] = {
			["command"] = "ixeg/733/autopilot/AP_disengage",
			["repeat"] = false,
		},
		["disconnect_at"] = {
			["command"] = "ixeg/733/autopilot/at_disengage",
			["repeat"] = false,
		},
		-- 737 does not appear to have a CWS button on yokes
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
		-- The command appears to be correct (changes EPR if not already a TO/GA mode) but A/T cannot be armed, it's only either on or off.
		-- As it's not possible to just arm A/T and activate it via TO/GA, unless doing a GA (and with EPR already set for TO) this probably has no use.
		-- A/T switch needs to be pressed on MCP anyway; it's not activated by pressing TO/GA.
		["to_ga"] = {
			["command"] = "Rotate/md80/autopilot/to_ga_button",
			["repeat"] = false
		}
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
		-- A319 has no TO/GA button (it's a thrust detent instead), set INOP
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
		["to_ga"] = {
			["command"] = "laminar/B738/autopilot/left_toga_press",
			["repeat"] = false
		},
		-- there does not appear to be any CWS button on the yoke, only on MCP (laminar/B738/autopilot/cws_a_press)
		-- control_fd command refers to yoke, not MCP button, so leave INOP
	},
}

local command_protection = {
	-- protection against accidental triggering
	-- required_num_triggers       => number of required proxy command triggers before command is proxied (only values above 1 make sense)
	-- retrigger_time_interval_ms  => maximum milliseconds between proxy command triggers before request gets ignored and command re-locked
	-- keep_unlocked_until_expired => if true, any triggers after unlocking will be instantly allowed within retrigger time interval
	--                                if false, command will be locked after a single invocation
	--
	--                                example: 3 triggers needed within 750ms to unlock
	--
	--                                         if true:  first and second triggers get "ignored" (command still locked)
	--                                                   third trigger is allowed (command unlocked)
	--                                                   fourth, fifth, ... trigger is allowed as well (command remains unlocked)
	--                                                   ... unless last trigger was more than 750ms ago (counter gets reset)
	--
	--                                         if false: first and second triggers get "ignored" (command still locked)
	--                                                   third trigger is allowed (command unlocked)
	--                                                   command gets locked again immediately after that trigger (not just after 750ms)
	--                                                   fourth and fifth triggers get "ignored" (command locked again; seen as first and second)
	--                                                   sixth trigger is allowed again (seen as third trigger)
	["to_ga"] = {
		["required_num_triggers"] = 3,
		["retrigger_time_interval_ms"] = 750,
		["keep_unlocked_until_expired"] = true
	}
}
-- == END OF CONFIGURATION ==

local version = '0.2dev'
local LOG_PREFIX = "[Input Proxy] "

print(LOG_PREFIX .. "Initializing Input Proxy version " .. version)

-- script globals
local system_path = nil
local dir_sep = nil
local loaded_aircraft_path = ""
local commands = {}
local inputproxy_protection = {}

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

function inputproxy_protection_trigger(proxy_alias)
	-- registers trigger and checks conditions
	-- returns true if command is allowed to be proxied, false if not
	
	local config = command_protection[proxy_alias]
	if config == nil then
		-- protection is not configured for this command, always allow it to be proxied
		return true
	end
	
	-- check for bad configuration
	if config["required_num_triggers"] < 2 then
		print(LOG_PREFIX .. "Command protection number of triggers is implausible (" .. config["required_num_triggers"] .. " ), check configuration: " .. proxy_alias)
	elseif config["retrigger_time_interval_ms"] < 50 then
		print(LOG_PREFIX .. "Command protection retrigger interval is implausible (" .. config["retrigger_time_interval_ms"] .. " ms), check configuration: " .. proxy_alias)
	end
	
	local protection = inputproxy_protection[proxy_alias]
	if protection ~= nil then
		-- count this trigger event
		protection["trigger_count"] = protection["trigger_count"] + 1
	else
		-- initialize record if not tracked before
		protection = {
			["last_triggered"] = 0,
			["trigger_count"] = 1,
			["unlocked"] = false
		}
	end
	
	local now = os.clock()
	
	local was_unlocked = protection["unlocked"]
	local is_allowed = was_unlocked
	local should_reset = false
	
	-- we only have to check for unlocking if the command was still locked before this event
	if not was_unlocked then
		local minimum_last_triggered = now - (config["retrigger_time_interval_ms"] / 1000.0)
	
		if protection["last_triggered"] < minimum_last_triggered then
			-- time expired (or protection was not triggered since last lock)
			print(LOG_PREFIX .. "Command protection will be reset (trigger time): " .. proxy_alias)
			should_reset = true
		elseif protection["trigger_count"] >= config["required_num_triggers"] then
			-- number of triggers reached
			print(LOG_PREFIX .. "Command protection unlocks: " .. proxy_alias)
			is_allowed = true
		else
			print(LOG_PREFIX .. "Command protection remains locked (trigger " .. protection["trigger_count"] .. " of " .. config["required_num_triggers"] .. "): " .. proxy_alias)
		end
	end
	
	if should_reset then
		protection["trigger_count"] = 1
		protection["unlocked"] = false
		is_allowed = false
	end
	
	protection["last_triggered"] = now
	inputproxy_protection[proxy_alias] = protection
	
	if not is_allowed then
		print(LOG_PREFIX .. "Command is protected and locked: " .. proxy_alias)
	else
		protection["unlocked"] = true
	end
	
	return is_allowed
end

function inputproxy_protection_unlocked(proxy_alias)
	-- only checks if command was previously unlocked (or is unprotected)
	-- in contrast to inputproxy_protection_trigger this function does not work towards an unlock (useful for command repetitions)
	-- returns true if command is allowed to be proxied, false if not
	
	local config = command_protection[proxy_alias]
	if config == nil then
		-- protection is not configured for this command, always allow it to be proxied
		return true
	end
	
	local protection = inputproxy_protection[proxy_alias]
	local is_allowed = protection ~= nil and protection["unlocked"]
	
	if not is_allowed then
		print(LOG_PREFIX .. "Command is protected and locked: " .. proxy_alias)
	end
	
	return is_allowed
end

function inputproxy_protection_lock_again(proxy_alias)
	-- lock command but only if protection was previously unlocked
	
	local config = command_protection[proxy_alias]
	if config == nil then
		-- unprotected commands cannot and should not be locked
		return
	end
	
	local protection = inputproxy_protection[proxy_alias]
	local was_unlocked = protection ~= nil and protection["unlocked"]
	if was_unlocked then
		if config["keep_unlocked_until_expired"] then
			print(LOG_PREFIX .. "Locking command (instant retriggering allowed): " .. proxy_alias)
			
			-- only resetting "unlocked" will trigger re-evaluation of unlock criteria
			inputproxy_protection[proxy_alias]["unlocked"] = false
		else
			print(LOG_PREFIX .. "Locking command (full cycle): " .. proxy_alias)
			
			-- removing whole protection info will restart unlock sequence
			inputproxy_protection[proxy_alias] = nil
		end
	end
end

function inputproxy_command_begin(proxy_alias)
	print(LOG_PREFIX .. "Pressed: " .. proxy_alias)
	
	local command_config = commands[proxy_alias]
	if command_config == nil then
		print(LOG_PREFIX .. "Proxy command alias not configured: " .. proxy_alias)
		return
	end
	
	local is_allowed = inputproxy_protection_trigger(proxy_alias)
	if not is_allowed then
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
	
	local is_allowed = inputproxy_protection_unlocked(proxy_alias)
	if not is_allowed then
		return
	end
	
	inputproxy_run_command(command_once, command_config)
end

function inputproxy_command_end(proxy_alias)
	print(LOG_PREFIX .. "Released: " .. proxy_alias)
	
	local command_config = commands[proxy_alias]
	if command_config == nil then
		print(LOG_PREFIX .. "Proxy command alias not configured: " .. proxy_alias)
		return
	end
	
	-- protection should always allow commands to end but may have to lock the command again
	inputproxy_protection_lock_again(proxy_alias)
	
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
