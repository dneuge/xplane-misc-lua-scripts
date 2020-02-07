--- Time Control
--- applies a constant time offset to system time

local tc_window = nil
local tc_offsetNegative = false
local tc_offsetTotalSeconds = 0
local tc_autoUpdate = false

local TC_MIN_OFFSET_TOTAL_SECONDS = -86399
local TC_MAX_OFFSET_TOTAL_SECONDS = 86399

local TC_WINDOW_WIDTH = 260
local TC_WINDOW_HEIGHT = 290

local TC_VERSION = "0.1"

DataRef("TC_USE_SYSTEM_TIME", "sim/time/use_system_time", "writable")
DataRef("TC_ZULU_TIME_SEC", "sim/time/zulu_time_sec", "writable")
DataRef("TC_LOCAL_TIME_SEC", "sim/time/local_time_sec", "readonly")
DataRef("TC_LOCAL_YEAR_DAY", "sim/time/local_date_days", "writable")
DataRef("TC_REPLAY_MODE", "sim/operation/prefs/replay_mode", "readonly")


function TC_Sign(x)
	if x < 0 then
		return -1
	else
		return 1
	end
end

function TC_Limit(x, min, max)
	if x < min then
		return min
	elseif x > max then
		return max
	end
	
	return x
end

function TC_SplitTime(totalSeconds)
	local offsetHours = math.floor(math.abs(totalSeconds) / 3600)
	local offsetMinutes = math.floor((math.abs(totalSeconds) % 3600) / 60)
	local offsetSeconds = math.floor(math.abs(totalSeconds) % 60)
	
	return offsetHours, offsetMinutes, offsetSeconds
end

function TC_CalculateTarget(totalOffset)
	local systemTime = os.date("!*t") -- ! requests UTC
	
	local targetTotalSeconds = ((systemTime["hour"] * 60) + systemTime["min"]) * 60 + systemTime["sec"] + tc_offsetTotalSeconds
	
	local targetOffsetDay = 0
	if targetTotalSeconds < 0 then
		targetTotalSeconds = targetTotalSeconds + 86400
		targetOffsetDay = -1
	elseif targetTotalSeconds > 86399 then
		targetTotalSeconds = targetTotalSeconds - 86400
		targetOffsetDay = 1
	end
	
	local targetDay = systemTime["yday"] + targetOffsetDay - 1
	if targetDay < 0 then
		targetDay = 366 + targetDay
	elseif targetDay > 365 then
		targetDay = targetDay - 366
	end
	
	-- TODO: X-Plane local day 59 is Feb 29, check if leap year and skip if not
	
	return targetDay, targetTotalSeconds
end

function TC_ApplyOffset()
	if TC_REPLAY_MODE ~= 0 then
		-- manipulating time during replays may crash X-Plane
		return
	end
	
	local targetDay, targetTotalSeconds = TC_CalculateTarget(tc_offsetTotalSeconds)
	
	TC_USE_SYSTEM_TIME = 0
	TC_LOCAL_YEAR_DAY = targetDay
	TC_ZULU_TIME_SEC = targetTotalSeconds
end

function TC_Sometimes()
	if tc_autoUpdate then
		TC_ApplyOffset()
	end
end

function TC_OpenWindow()
	if tc_window then
		return
	end
	
	tc_window = float_wnd_create(TC_WINDOW_WIDTH, TC_WINDOW_HEIGHT, 1, true)
	float_wnd_set_title(tc_window, "Time Control")
	float_wnd_set_imgui_builder(tc_window, "TC_BuildWindow")
	float_wnd_set_onclose(tc_window, "TC_OnCloseWindow")
end

function TC_OnCloseWindow()
	tc_window = nil
end

function TC_BuildWindow()
	local changed = false
	local newVal = nil
	
	changed, newVal = imgui.Checkbox("Use system time?", TC_USE_SYSTEM_TIME ~= 0)
	if changed then
		if newVal then
			TC_USE_SYSTEM_TIME = 1
			tc_autoUpdate = false
		else
			TC_USE_SYSTEM_TIME = 0
		end
	end
	
	imgui.TextUnformatted("")
	
	local simHours, simMinutes, simSeconds = TC_SplitTime(TC_ZULU_TIME_SEC)
	imgui.TextUnformatted(string.format("Simulator time: Day %d, %02d:%02d:%02d", TC_LOCAL_YEAR_DAY + 1, simHours, simMinutes, simSeconds))
	
	local simLocalHours, simLocalMinutes, simLocalSeconds = TC_SplitTime(TC_LOCAL_TIME_SEC)
	imgui.TextUnformatted(string.format("                (local) %02d:%02d:%02d", simLocalHours, simLocalMinutes, simLocalSeconds))
	
	local systemTime = os.date("!*t")
	imgui.TextUnformatted(string.format("System time:    Day %d, %02d:%02d:%02d", systemTime["yday"], systemTime["hour"], systemTime["min"], systemTime["sec"]))
	
	local offsetSign = 1
	if tc_offsetNegative then
		offsetSign = -1
	end
	
	local offsetHours, offsetMinutes, offsetSeconds = TC_SplitTime(tc_offsetTotalSeconds)
	
	local targetDay, targetTotalSeconds = TC_CalculateTarget(tc_offsetTotalSeconds)
	
	local targetHours, targetMinutes, targetSeconds = TC_SplitTime(targetTotalSeconds)
	
	imgui.TextUnformatted(string.format("Target time:    Day %d, %02d:%02d:%02d", targetDay + 1, targetHours, targetMinutes, targetSeconds))
	
	imgui.TextUnformatted("")
	
	-- sign
	changed, newVal = imgui.Checkbox("Negative Offset?", tc_offsetNegative)
	if changed then
		tc_offsetNegative = newVal
	end
	
	-- hours
	changed, newVal = imgui.InputInt("Hours", offsetHours)
	if changed then
		offsetHours = TC_Limit(newVal, 0, 23)
	end
	
	-- minutes
	changed, newVal = imgui.InputInt("Minutes", offsetMinutes)
	if changed then
		offsetMinutes = TC_Limit(newVal, 0, 59)
	end
	
	-- seconds
	changed, newVal = imgui.InputInt("Seconds", offsetSeconds)
	if changed then
		offsetSeconds = TC_Limit(newVal, 0, 59)
	end
	
	tc_offsetTotalSeconds = offsetSign * ((offsetHours * 60 + offsetMinutes) * 60 + offsetSeconds)
	
	if tc_offsetTotalSeconds < TC_MIN_OFFSET_TOTAL_SECONDS then
		tc_offsetTotalSeconds = TC_MIN_OFFSET_TOTAL_SECONDS
	elseif tc_offsetTotalSeconds > TC_MAX_OFFSET_TOTAL_SECONDS then
		tc_offsetTotalSeconds = TC_MAX_OFFSET_TOTAL_SECONDS
	end
	
	imgui.TextUnformatted(string.format("Total offset:   %d",tc_offsetTotalSeconds))
	
	imgui.TextUnformatted("")
	
	if imgui.Button("Apply") then
		tc_autoUpdate = true
		TC_ApplyOffset()
	end
	
	imgui.SameLine()
	changed, newVal = imgui.Checkbox("auto update", tc_autoUpdate)
	if changed then
		tc_autoUpdate = newVal
	end
	
	-- add version label
	local versionText = "v" .. TC_VERSION
    local windowWidth = imgui.GetWindowWidth()
    local windowHeight = imgui.GetWindowHeight()
	local textWidth, textHeight = imgui.CalcTextSize(versionText)
	imgui.SetCursorPos(windowWidth - textWidth - 20, windowHeight - textHeight - 10)
	imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF999999)
	imgui.TextUnformatted(versionText)
	imgui.PopStyleColor()
end

add_macro("Show Time Control", "TC_OpenWindow()")

do_sometimes("TC_Sometimes()")
