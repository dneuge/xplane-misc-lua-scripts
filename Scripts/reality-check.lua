--- Reality Check
--- compares locally reported with externally perceived speeds (simulation rate vs. real time)
--- 
--- What's the issue?
--- As explained by X-Plane developer Ben Supnik in an excellent blog post [1] some years ago,
--- graphic and physics computation frame rates are linked in X-Plane which generates a requirement
--- for a certain minimum frame rate to be maintained for stable flight model computation. Since
--- that frame rate cannot be guaranteed at all times, X-Plane 11 will slow down the simulation rate
--- if it falls under the minimum FPS, causing time dilation (simulated time passes slower than real
--- time). For users, that behaviour has a benefit of maintaining a smoother control over an aircraft
--- under low FPS conditions while other flight simulators would simply exhibit erratic movements by
--- freezing and skipping ahead in time.
--- Time dilation is a great feature when flying offline but as you connect to a network of other
--- pilots or ATC it causes issues because your simulator uses its own out-of-sync clock, resulting in
--- your aircraft moving at (much) slower speeds than indicated.
--- As detailed in [1], this is neither an error in X-Plane nor can the behaviour easily be changed.
--- Instead, X-Plane warns the user at least once when the issue is first experienced (usually caused by
--- excessive graphics/detail settings) but most users just disable the notice and then forget about it.
--- Recently, online networks have started to detect such slow-downs and forcibly disconnect users who
--- are unable to maintain real-time simulation rates.
---
--- The goal of this script is to experiment with some ways of detecting time dilation in X-Plane to
--- possibly improve those detections in order to lower the number of false positives (disconnects when
--- they were actually not required).
---
--- The issue of time dilation has been around for a long time but only lately and solutions such as
--- 3jFPS-wizard or AutoLOD are available to maintain a steady framerate.
---
--- [1] https://developer.x-plane.com/2017/10/x-plane-11-10-beta-5-ding-dong-the-fps-nag-is-gone-mostly/


--- CONFIG START

-- What should be recorded?
RC_MINIMUM_INDICATED_GROUND_SPEED               = 10.0 -- minimum indicated GS at which we should start recording

-- When and what should be analyzed?
RC_ANALYZE_MAX_AGE_SECONDS                      = 30.0 -- age of oldest record to analyze
RC_ANALYZE_INTERVAL                             = 3    -- analyze at most once every x seconds

-- Thresholds to trigger warnings for
-- - frames per second (based on averaged count over 1 second windows)
RC_ANALYZE_FPS_THRESHOLD                        = 20.0 -- count number of records below this threshold of FPS
RC_ANALYZE_FPS_THRESHOLD_TIMES_CRITICAL         = 5    -- number of triggering records in analyzed time window to interpret as critical

-- - time dilation (assumed to activate at inverse frame time <= RC_TIME_DILATION_FRAME_RATE)
RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD1 =  2.0 -- "warning" level for real time spent with time dilation (seconds)
RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD2 = 10.0 -- "critical" level for real time spent with time dilation (seconds)

-- - ground speed factor (approximate externally observed time dilation factor)
RC_ANALYZE_GS_FACTOR_AVERAGE_THRESHOLD1         = 0.95 -- "warning" level for average of all records
RC_ANALYZE_GS_FACTOR_AVERAGE_THRESHOLD2         = 0.85 -- "critical" level for average of all records
RC_ANALYZE_GS_FACTOR_SINGLE_THRESHOLD1          = 0.80 -- "warning" level of a single record
RC_ANALYZE_GS_FACTOR_SINGLE_THRESHOLD2          = 0.70 -- "critical" level of a single record

-- - cumulative error in distance (externally observed cumulative time dilation position error)
RC_ANALYZE_DISTANCE_ERROR_CUMULATIVE_THRESHOLD1 = 0.30 -- "warning" level in nautical miles
RC_ANALYZE_DISTANCE_ERROR_CUMULATIVE_THRESHOLD2 = 0.75 -- "critical" level in nautical miles

-- How many FPS/GS warnings (including critical level) are needed to start notifying user?
-- Warnings resulting from distance errors and average values are always shown.
RC_NOTIFICATION_THRESHOLD = 2

-- Where should the notification be printed? (Y coordinate starts at bottom!)
RC_NOTIFICATION_X = 10
RC_NOTIFICATION_Y = 800

-- Print all details to developer console? (users usually don't need this)
RC_DEBUG = false

--- CONFIG END

RC_VERSION = "0.2dev"

RC_TIME_DILATION_FRAME_RATE = 19 -- FPS (floored, inverse frame time) when X-Plane starts time dilation

MEAN_RADIUS_EARTH_METERS = 6371009
METERS_PER_NAUTICAL_MILE = 1852
RC_FACTOR_METERS_PER_SECOND_TO_KNOTS = 3600.0 / METERS_PER_NAUTICAL_MILE

DataRef("RC_GROUND_SPEED", "sim/flightmodel/position/groundspeed", "readonly")
DataRef("RC_PAUSED", "sim/time/paused", "readonly")
DataRef("RC_FRAME_TIME", "sim/operation/misc/frame_rate_period", "readonly")

rc_records = {}
rc_ring = {}
rc_last_analyze = 0.0
rc_notify_level = 0
rc_notification_text = ""
rc_notification_activated = true

current_records = 0

fps_min = 99999.99
fps_avg = nil
fps_max = 0.0
fps_below_threshold = 0

rc_inv_frame_time_min = 99999.99
rc_inv_frame_time_avg = nil
rc_inv_frame_time_max = 0.0

gs_factor_min = 99999.99
gs_factor_avg = nil
gs_factor_max = 0.0
gs_factor_sum = 0.0
gs_factor_single_below_threshold1 = 0
gs_factor_single_below_threshold2 = 0

distance_indicated = 0.0
distance_externally_perceived = 0.0
distance_error = nil

rc_window = nil

rc_hist_inv_frame_times_count = {}
rc_hist_inv_frame_times_time_spent = {}
rc_time_spent_in_time_dilation = 0.0
rc_time_spent_in_time_dilation_percentage = 0.0

rc_observed_time = 0.0

function greatCircleDistanceInMetersByHaversine(latitude1, longitude1, latitude2, longitude2)
	latitude1Radians = math.rad(latitude1)
	longitude1Radians = math.rad(longitude1)
	latitude2Radians = math.rad(latitude2)
	longitude2Radians = math.rad(longitude2)
	
	deltaLatitude = math.abs(latitude1Radians - latitude2Radians) -- delta phi
	deltaLongitude = math.abs(longitude1Radians - longitude2Radians) -- delta lambda
	
	singleSineHalfDeltaLatitude = math.sin(deltaLatitude / 2.0)
	haversineDeltaLatitude = singleSineHalfDeltaLatitude * singleSineHalfDeltaLatitude
	
	singleSineHalfDeltaLongitude = math.sin(deltaLongitude / 2.0)
	haversineDeltaLongitude = singleSineHalfDeltaLongitude * singleSineHalfDeltaLongitude
	
	centralAngle = 2.0 * math.asin(math.sqrt(haversineDeltaLatitude + math.cos(latitude1Radians) * math.cos(latitude2Radians) * haversineDeltaLongitude))
	distanceMeters = MEAN_RADIUS_EARTH_METERS * centralAngle
	
	return distanceMeters
end

function RC_Count()
	slowest_indicated_ground_speed_meters_per_second = 9999.99
	first_record = nil
	last_record = nil
	num_records = #rc_records
	frame_times_by_inv = {}
	
	for i,record in ipairs(rc_records) do
		ground_speed_meters_per_second = record[4]
	
		if not first_record then
			first_record = record
		end
		
		last_record = record
		
		if ground_speed_meters_per_second < slowest_indicated_ground_speed_meters_per_second then
			slowest_indicated_ground_speed_meters_per_second = ground_speed_meters_per_second
		end
		
		frame_time = record[5]
		if frame_time > 0.0 then
			inv_frame_time = math.floor(1.0 / frame_time)
			if inv_frame_time > 0 then
				previous = frame_times_by_inv[inv_frame_time]
				if not previous then
					previous = {0, 0.0}
				end
				frame_times_by_inv[inv_frame_time] = {previous[1]+1, previous[2]+frame_time}
			end
		end
	end
	
	rc_records={}
	
	diff_time = last_record[1] - first_record[1]
	slowest_indicated_ground_speed = slowest_indicated_ground_speed_meters_per_second * RC_FACTOR_METERS_PER_SECOND_TO_KNOTS
	
	if slowest_indicated_ground_speed < RC_MINIMUM_INDICATED_GROUND_SPEED or RC_PAUSED > 0 then
		-- print(string.format("not calculated: %.2f %.2f %d", slowest_indicated_ground_speed, RC_MINIMUM_INDICATED_GROUND_SPEED, RC_PAUSED))
		return
	end
	
	great_circle_distance = greatCircleDistanceInMetersByHaversine(first_record[2], first_record[3], last_record[2], last_record[3]) / METERS_PER_NAUTICAL_MILE
	externally_perceived_ground_speed = great_circle_distance / diff_time * 3600
	ground_speed_factor = externally_perceived_ground_speed / slowest_indicated_ground_speed
	
	-- limit GS factor to range [0..1]
	if ground_speed_factor > 1.0 then
		ground_speed_factor = 1.0
	elseif ground_speed_factor < 0.0 then
		ground_speed_factor = 0.0
	end
	
	fps = num_records / diff_time
	
	table.insert(rc_ring, {os.clock(), diff_time, fps, slowest_indicated_ground_speed, externally_perceived_ground_speed, ground_speed_factor, frame_times_by_inv, great_circle_distance})
	
	--print(string.format("%.2f %.1f %.5f %.2f %.2f %.2f", diff_time, fps, great_circle_distance, slowest_indicated_ground_speed, externally_perceived_ground_speed, ground_speed_factor))
end

function RC_Record()
	table.insert(rc_records, {os.clock(), LATITUDE, LONGITUDE, RC_GROUND_SPEED, RC_FRAME_TIME})
end

function RC_Analyze()
	now = os.clock()
	if (now - rc_last_analyze) < RC_ANALYZE_INTERVAL then
		return
	end
	rc_last_analyze = now
	
	rc_notify_level = 0
	rc_notification_text = ""
	
	oldest_record = nil
	current_records = 0
	
	fps_min = 99999.99
	fps_avg = nil
	fps_max = 0.0
	fps_sum = 0.0
	fps_below_threshold = 0
	
	rc_inv_frame_time_min = 99999.99
	rc_inv_frame_time_avg = nil
	rc_inv_frame_time_max = 0.0

	gs_factor_min = 99999.99
	gs_factor_avg = nil
	gs_factor_max = 0.0
	gs_factor_sum = 0.0
	gs_factor_single_below_threshold1 = 0
	gs_factor_single_below_threshold2 = 0
	
	distance_indicated = 0.0
	distance_externally_perceived = 0.0
	distance_error = nil
	
	aggregated_frame_times_by_inv = {}
	rc_hist_inv_frame_times_count = {}
	rc_hist_inv_frame_times_time_spent = {}
	rc_time_spent_in_time_dilation = 0.0
	rc_time_spent_in_time_dilation_percentage = 0.0
	
	ring_delete = {}
	for i,record in ipairs(rc_ring) do
		record_time = record[1]
		diff_time = record[2]
		fps = record[3]
		gs_slowest_indicated = record[4]
		gs_externally_perceived = record[5]
		gs_factor = record[6]
		frame_times_by_inv = record[7]
		great_circle_distance = record[8]
		
		age = now - record_time
		if age >= RC_ANALYZE_MAX_AGE_SECONDS then
			-- record is too old, ignore and remember to delete it
			table.insert(ring_delete, i)
		else
			if not oldest_record then
				oldest_record = record
			end
			
			current_records = current_records + 1
			
			if fps < fps_min then
				fps_min = fps
			end
			if fps > fps_max then
				fps_max = fps
			end
			fps_sum = fps_sum + fps
			if fps < RC_ANALYZE_FPS_THRESHOLD then
				fps_below_threshold = fps_below_threshold + 1
			end
			
			if gs_factor < gs_factor_min then
				gs_factor_min = gs_factor
			end
			if gs_factor > gs_factor_max then
				gs_factor_max = gs_factor
			end
			gs_factor_sum = gs_factor_sum + gs_factor
			
			if gs_factor <= RC_ANALYZE_GS_FACTOR_SINGLE_THRESHOLD2 then
				gs_factor_single_below_threshold2 = gs_factor_single_below_threshold2 + 1
			elseif gs_factor <= RC_ANALYZE_GS_FACTOR_SINGLE_THRESHOLD1 then
				gs_factor_single_below_threshold1 = gs_factor_single_below_threshold1 + 1
			end
			
			distance_indicated = distance_indicated + (gs_slowest_indicated * diff_time / 3600)
			distance_externally_perceived = distance_externally_perceived + great_circle_distance
			
			for inv_frame_time, arr in pairs(frame_times_by_inv) do
				num_frames = arr[1]
				time_spent = arr[2]
				
				--print(string.format("%03d %03d %.3f", inv_frame_time, num_frames, time_spent))
				
				aggregated = aggregated_frame_times_by_inv[inv_frame_time]
				if not aggregated then
					aggregated = {0, 0.0}
				end
				aggregated_frame_times_by_inv[inv_frame_time] = {aggregated[1] + num_frames, aggregated[2] + time_spent}
			end
		end
	end
	
	-- delete all outdated items from buffer
	for i = #ring_delete,1,-1 do
		table.remove(rc_ring, ring_delete[i])
	end
	
	fps_avg = fps_sum / current_records
	gs_factor_avg = gs_factor_sum / current_records
	distance_error = distance_indicated - distance_externally_perceived
	
	if distance_error < 0.0 then
		distance_error = 0.0
	end
	
	if not oldest_record then
		--print("no data")
		return
	end
	
	oldest_record_age = now - oldest_record[1] + oldest_record[2] -- time of record creation - difference; approximate
	latest_record = rc_ring[#rc_ring]
	rc_observed_time = latest_record[1] - oldest_record[1] + oldest_record[2] -- approximate
	
	distance_error_level = 0
	if distance_error >= RC_ANALYZE_DISTANCE_ERROR_CUMULATIVE_THRESHOLD2 then
		distance_error_level = 2
	elseif distance_error >= RC_ANALYZE_DISTANCE_ERROR_CUMULATIVE_THRESHOLD1 then
		distance_error_level = 1
	end
	
	rc_hist_inv_frame_times_count = RC_ComputeHistogram(aggregated_frame_times_by_inv, 1)
	rc_hist_inv_frame_times_time_spent = RC_ComputeHistogram(aggregated_frame_times_by_inv, 2)
	
	inv_frame_time_sum = 0.0
	inv_frame_time_total = 0
	for inv_frame_time,arr in pairs(aggregated_frame_times_by_inv) do
		if inv_frame_time <= RC_TIME_DILATION_FRAME_RATE then
			rc_time_spent_in_time_dilation = rc_time_spent_in_time_dilation + arr[2]
		end
		
		num_frames = arr[1]
		inv_frame_time_sum = inv_frame_time_sum + num_frames * inv_frame_time
		inv_frame_time_total = inv_frame_time_total + num_frames
		if inv_frame_time < rc_inv_frame_time_min then
			rc_inv_frame_time_min = inv_frame_time
		end
		if inv_frame_time > rc_inv_frame_time_max then
			rc_inv_frame_time_max = inv_frame_time
		end
	end
	
	rc_time_spent_in_time_dilation_percentage = rc_time_spent_in_time_dilation / rc_observed_time * 100.0
	rc_inv_frame_time_avg = inv_frame_time_sum / inv_frame_time_total
	
	if RC_DEBUG then
		print(string.format("analyzed data for last %.1f seconds", oldest_record_age))
		print(string.format("#f/1 min %.1f / avg %.1f / max %.1f, WARN: %d", fps_min, fps_avg, fps_max, fps_below_threshold))
		print(string.format("GSx  min %.2f / avg %.2f / max %.2f, WARN: %d, CRIT: %d", gs_factor_min, gs_factor_avg, gs_factor_max, gs_factor_single_below_threshold1, gs_factor_single_below_threshold2))
		print(string.format("cumulative distance indicated %.2f nm / externally perceived %.2f nm / error %.2f nm / warn level %d", distance_indicated, distance_externally_perceived, distance_error, distance_error_level))
	end
	
	fps_warning = fps_below_threshold >= RC_NOTIFICATION_THRESHOLD
	fps_critical = fps_below_threshold >= RC_ANALYZE_FPS_THRESHOLD_TIMES_CRITICAL
	
	gsx_warning = gs_factor_avg <= RC_ANALYZE_GS_FACTOR_AVERAGE_THRESHOLD1 or gs_factor_single_below_threshold1 >= RC_NOTIFICATION_THRESHOLD
	gsx_critical = gs_factor_avg <= RC_ANALYZE_GS_FACTOR_AVERAGE_THRESHOLD2 or(gs_factor_single_below_threshold1 + gs_factor_single_below_threshold2) >= RC_NOTIFICATION_THRESHOLD
	
	dilation_time_spent_warning = rc_time_spent_in_time_dilation >= RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD1
	dilation_time_spent_critical = rc_time_spent_in_time_dilation >= RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD2
	
	if fps_critical or gsx_critical or distance_error_level > 1 or dilation_time_spent_critical then
		rc_notify_level = 2
	elseif fps_warning or gsx_warning or distance_error_level > 0 or dilation_time_spent_warning then
		rc_notify_level = 1
	else
		return
	end
	
	rc_notification_text = "Time dilation:"
	has_preceding_text = false
	
	if dilation_time_spent_warning or dilation_time_spent_critical then
		rc_notification_text = rc_notification_text .. string.format(" active for %.1f seconds (%.1f%%)", rc_time_spent_in_time_dilation, rc_time_spent_in_time_dilation_percentage)
		has_preceding_text = true
	end
	
	if distance_error_level > 0 then
		rc_notification_text = rc_notification_text .. string.format(" %.2f nm off expected position", distance_error)
		has_preceding_text = true
	end
	
	if gsx_warning or gsx_critical then
		if has_preceding_text then
			rc_notification_text = rc_notification_text .. " /"
		end
	
		rc_notification_text = rc_notification_text .. string.format(" GSx %.2f/%.2f/%.2f W%d C%d", gs_factor_min, gs_factor_avg, gs_factor_max, gs_factor_single_below_threshold1, gs_factor_single_below_threshold2)
		has_preceding_text = true
	end
	
	if fps_warning or fps_critical then
		if has_preceding_text then
			rc_notification_text = rc_notification_text .. " /"
		end
	
		rc_notification_text = rc_notification_text .. string.format(" #f/s %.1f/%.1f/%.1f W%d", fps_min, fps_avg, fps_max, fps_below_threshold)
		has_preceding_text = true
	end
end

function RC_ComputeHistogram(data, value_index)
	-- keys must be unique in data! (direct assignment)
	
	local histogram = {}
	
	for key,arr in pairs(data) do
		-- initialize histogram to hold as many elements as the key
		for i=#histogram,key do
			table.insert(histogram,0)
		end
		
		-- copy value
		histogram[key] = arr[value_index]
	end
	
	return histogram
end

function RC_Draw()
	if rc_notify_level < 1 or not rc_notification_activated then
		return
	end

	color = "yellow"
	if rc_notify_level > 1 and os.clock() % 2 < 1.0 then
		color = "red"
	end
	
	draw_string(RC_NOTIFICATION_X, RC_NOTIFICATION_Y, rc_notification_text, color)
end

function RC_OpenWindow()
	if rc_window then
		return
	end
	
	rc_window = float_wnd_create(420, 380, 1, true)
	float_wnd_set_title(rc_window, "Reality Check v" .. RC_VERSION)
	float_wnd_set_imgui_builder(rc_window, "RC_BuildWindow")
	float_wnd_set_onclose(rc_window, "RC_OnCloseWindow")
end

function RC_BuildWindow(wnd, x, y)
	has_data = fps_avg ~= nil and fps_min < 99999 and gs_factor_avg ~= nil and gs_factor_min < 99999
	
	if not has_data then
		imgui.TextUnformatted(string.format("No data. Start moving faster than %.0f knots \nindicated GS.", RC_MINIMUM_INDICATED_GROUND_SPEED))
		return
	end
	
	local width = imgui.GetWindowWidth()

	yellow = 0xFF00FFFF
	red = 0xFF0000FF
	color = nil
	
	imgui.TextUnformatted("                min    avg    max")
	imgui.TextUnformatted(string.format("1/frametime  %6.2f %6.2f %6.2f", rc_inv_frame_time_min, rc_inv_frame_time_avg, rc_inv_frame_time_max))
	imgui.TextUnformatted(string.format("#frames/1sec %6.2f %6.2f %6.2f", fps_min, fps_avg, fps_max))
	imgui.TextUnformatted(string.format("GS factor    %6.2f %6.2f %6.2f", gs_factor_min, gs_factor_avg, gs_factor_max))
	
	imgui.TextUnformatted("")
	if rc_time_spent_in_time_dilation >= RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD2 then
		color = red
	elseif rc_time_spent_in_time_dilation >= RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD1 then
		color = yellow
	end
	if color then
		imgui.PushStyleColor(imgui.constant.Col.Text, color)
	end
	imgui.TextUnformatted(string.format("%5.2f seconds spent with time dilation (%.1f%%)", rc_time_spent_in_time_dilation, rc_time_spent_in_time_dilation_percentage))
	if color then
		imgui.PopStyleColor()
		color = nil
	end
	
	imgui.TextUnformatted("")
	imgui.TextUnformatted(string.format("cum distance %6.2f nm expected by indication", distance_indicated))
	imgui.TextUnformatted(string.format("             %6.2f nm externally perceived", distance_externally_perceived))
	imgui.TextUnformatted(string.format("             %6.2f nm off expectation", distance_error))
	
	imgui.TextUnformatted("")
	imgui.TextUnformatted(string.format("%3d records analyzed covering %4.1f seconds", current_records, rc_observed_time))
	
	if fps_below_threshold > RC_ANALYZE_FPS_THRESHOLD_TIMES_CRITICAL then
		color = red
	elseif fps_below_threshold > 0 then
		color = yellow
	end
	if color then
		imgui.PushStyleColor(imgui.constant.Col.Text, color)
	end
	imgui.TextUnformatted(string.format("%3d records below #frames/1sec warning threshold", fps_below_threshold))
	if color then
		imgui.PopStyleColor()
		color = nil
	end
	
	if gs_factor_single_below_threshold1 > 0 then
		color = yellow
	end
	if color then
		imgui.PushStyleColor(imgui.constant.Col.Text, color)
	end
	imgui.TextUnformatted(string.format("%3d records below GS factor warning threshold", gs_factor_single_below_threshold1))
	if color then
		imgui.PopStyleColor()
		color = nil
	end
	
	if gs_factor_single_below_threshold2 > 0 then
		color = red
	end
	if color then
		imgui.PushStyleColor(imgui.constant.Col.Text, color)
	end
	imgui.TextUnformatted(string.format("%3d records below GS factor critical threshold", gs_factor_single_below_threshold2))
	if color then
		imgui.PopStyleColor()
		color = nil
	end

	imgui.TextUnformatted("")
	
	text = "within expected range."
	if gs_factor_avg <= RC_ANALYZE_GS_FACTOR_AVERAGE_THRESHOLD2 then
		color = red
		text = "below critical threshold."
	elseif gs_factor_avg <= RC_ANALYZE_GS_FACTOR_AVERAGE_THRESHOLD1 then
		color = yellow
		text = "below warning threshold."
	end
	if color then
		imgui.PushStyleColor(imgui.constant.Col.Text, color)
	end
	imgui.TextUnformatted("Average GS factor is "..text)
	if color then
		imgui.PopStyleColor()
		color = nil
	end
	
	if distance_error_level == 0 then
		imgui.TextUnformatted("Cumulative distance is within expected range.")
	elseif distance_error_level == 1 then
		imgui.PushStyleColor(imgui.constant.Col.Text, yellow)
		imgui.TextUnformatted("Cumulative distance is slightly below external perception.")
		imgui.PopStyleColor()
	else 
		imgui.PushStyleColor(imgui.constant.Col.Text, red)
		imgui.TextUnformatted("Cumulative distance is severely below external perception.")
		imgui.PopStyleColor()
	end
	
	imgui.TextUnformatted("")
	
	local inner_width, inner_height = float_wnd_get_dimensions(wnd)
    if imgui.TreeNode("Inverse Frame Time Count") then
		local offset_x, offset_y = imgui.GetCursorScreenPos()
		imgui.PlotHistogram("", rc_hist_inv_frame_times_count, #rc_hist_inv_frame_times_count, -1, "", FLT_MAX, FLT_MAX, inner_width - offset_x - 10, 120)
		imgui.TreePop()
	end
    if imgui.TreeNode("Inverse Frame Time Spent") then
		local offset_x, offset_y = imgui.GetCursorScreenPos()
		imgui.PlotHistogram("", rc_hist_inv_frame_times_time_spent, #rc_hist_inv_frame_times_time_spent, -1, "", FLT_MAX, FLT_MAX, inner_width - offset_x - 10, 120)
		imgui.TreePop()
	end
end

function RC_OnCloseWindow(wnd)
	rc_window = nil
end

function RC_EnableNotifications()
	rc_notification_activated = true
end

function RC_DisableNotifications()
	rc_notification_activated = false
end




rc_macro_default_state_notifications = "activate"
if not rc_notification_activated then
	rc_macro_default_state_notifications = "deactivate"
end

add_macro("Show Reality Check analysis", "RC_OpenWindow()")
add_macro("Enable Reality Check notifications", "RC_EnableNotifications()", "RC_DisableNotifications()", rc_macro_default_state_notifications)

RC_OpenWindow()

do_every_draw("RC_Draw()")
do_every_frame("RC_Record()")
do_often("RC_Count()")
do_often("RC_Analyze()")

print("Loaded Reality Check LUA script version " .. RC_VERSION)
