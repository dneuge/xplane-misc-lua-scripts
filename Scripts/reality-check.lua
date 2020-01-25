--- Reality Check
--- compares locally reported with externally perceived speeds (simulation rate vs. real time)
---
--- Repository: https://github.com/dneuge/xplane-misc-lua-scripts
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
--- 3jFPS-wizard [2] or AutoLOD [3] are available to maintain a steady framerate.
---
--- [1] https://developer.x-plane.com/2017/10/x-plane-11-10-beta-5-ding-dong-the-fps-nag-is-gone-mostly/
--- [2] https://forums.x-plane.org/index.php?/files/file/43281-3jfps-wizard11/
--- [3] http://www.x-plane.at/drupal/node/386


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

-- - time dilation (assumed to activate at inverse frame time < RC_ZERO_TIME_DILATION_FRAME_RATE)
RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD1 =  2.0 -- "warning" level for real time lost in time dilation (seconds)
RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD2 = 10.0 -- "critical" level for real time lost in time dilation (seconds)

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
RC_NOTIFICATION_THRESHOLD = 3

-- Where should the notification be printed? (Y coordinate starts at bottom!)
RC_NOTIFICATION_X = 10
RC_NOTIFICATION_Y = 800

-- Print all details to developer console? (users usually don't need this)
RC_DEBUG = false

--- CONFIG END

RC_VERSION = "0.4dev"

RC_ZERO_TIME_DILATION_FRAME_RATE = 20 -- FPS (floored, inverse frame time) which is the minimum to not trigger time dilation
RC_ZERO_TIME_DILATION_FRAME_TIME = 1.0/RC_ZERO_TIME_DILATION_FRAME_RATE

RC_WINDOW_WIDTH = 420
RC_WINDOW_HEIGHT = 440
RC_WINDOW_OFFSET = 10

RC_MEAN_RADIUS_EARTH_METERS = 6371009
RC_METERS_PER_NAUTICAL_MILE = 1852
RC_FACTOR_METERS_PER_SECOND_TO_KNOTS = 3600.0 / RC_METERS_PER_NAUTICAL_MILE

DataRef("RC_GROUND_SPEED", "sim/flightmodel/position/groundspeed", "readonly")
DataRef("RC_PAUSED", "sim/time/paused", "readonly")
DataRef("RC_FRAME_TIME1", "sim/operation/misc/frame_rate_period", "readonly")
DataRef("RC_FRAME_TIME2", "sim/time/framerate_period", "readonly")

rc_records = {}
rc_ring = {}
rc_previous_record_last = nil
rc_last_analyze = 0.0
rc_notify_level = 0
rc_notification_text = ""
rc_notification_activated = true
rc_frame_time_source = 2

rc_current_records = 0

rc_fps_min = 99999.99
rc_fps_avg = nil
rc_fps_max = 0.0
rc_fps_below_threshold = 0

rc_inv_frame_time_min = 99999.99
rc_inv_frame_time_avg = nil
rc_inv_frame_time_max = 0.0

rc_gs_slowest_indicated_min = 99999.99
rc_gs_slowest_indicated_avg = nil
rc_gs_slowest_indicated_max = 0.0

rc_gs_externally_perceived_min = 99999.99
rc_gs_externally_perceived_avg = nil
rc_gs_externally_perceived_max = 0.0

rc_gs_factor_min = 99999.99
rc_gs_factor_avg = nil
rc_gs_factor_max = 0.0
rc_gs_factor_single_below_threshold1 = 0
rc_gs_factor_single_below_threshold2 = 0

rc_distance_indicated = 0.0
rc_distance_externally_perceived = 0.0
rc_distance_error = nil
rc_distance_error_level = 0

rc_window = nil

rc_hist_inv_frame_times_count = {}
rc_hist_inv_frame_times_time_spent = {}
rc_time_spent_at_low_ift = 0.0
rc_time_spent_at_low_ift_percentage = 0.0
rc_num_low_ift_frames = 0
rc_num_low_ift_frames_percentage = 0.0
rc_time_lost_in_time_dilation = 0
rc_time_lost_in_time_dilation_percentage = 0.0

rc_observed_time = 0.0

rc_show_ift_count = true
rc_show_ift_time_spent = false

rc_logging_raw_file = nil
rc_logging_raw_buffer = {}
rc_logging_ring_file = nil
rc_logging_ring_buffer = {}
rc_logging_analysis_file = nil
rc_logging_analysis_buffer = {}

function RC_GreatCircleDistanceInMetersByHaversine(latitude1, longitude1, latitude2, longitude2)
	local latitude1Radians = math.rad(latitude1)
	local longitude1Radians = math.rad(longitude1)
	local latitude2Radians = math.rad(latitude2)
	local longitude2Radians = math.rad(longitude2)
	
	local deltaLatitude = math.abs(latitude1Radians - latitude2Radians) -- delta phi
	local deltaLongitude = math.abs(longitude1Radians - longitude2Radians) -- delta lambda
	
	local singleSineHalfDeltaLatitude = math.sin(deltaLatitude / 2.0)
	local haversineDeltaLatitude = singleSineHalfDeltaLatitude * singleSineHalfDeltaLatitude
	
	local singleSineHalfDeltaLongitude = math.sin(deltaLongitude / 2.0)
	local haversineDeltaLongitude = singleSineHalfDeltaLongitude * singleSineHalfDeltaLongitude
	
	local centralAngle = 2.0 * math.asin(math.sqrt(haversineDeltaLatitude + math.cos(latitude1Radians) * math.cos(latitude2Radians) * haversineDeltaLongitude))
	local distanceMeters = RC_MEAN_RADIUS_EARTH_METERS * centralAngle
	
	return distanceMeters
end

function RC_Count()
	local slowest_indicated_ground_speed_meters_per_second = 9999.99
	local last_record = nil
	local num_records = #rc_records
	local frame_times_by_inv = {}
	
	if num_records <= 0 then
		return
	end
	
	local first_record = rc_records[1]
	
	if not rc_previous_record_last and num_records > 0 then
		-- first record since script start, use first recorded frame instead
		rc_previous_record_last = first_record
	end
	
	local previous_record = rc_previous_record_last
	for i,record in ipairs(rc_records) do
		local ground_speed_meters_per_second = record[4]
	
		last_record = record
		
		if ground_speed_meters_per_second < slowest_indicated_ground_speed_meters_per_second then
			slowest_indicated_ground_speed_meters_per_second = ground_speed_meters_per_second
		end
		
		local frame_time = record[5]
		if rc_frame_time_source == 3 then
			-- use external clock instead of X-Plane datarefs
			-- to base IFT calculation on
			frame_time = record[1] - previous_record[1]
		end
		
		if frame_time > 0.0 then
			local inv_frame_time = math.floor(1.0 / frame_time)
			if inv_frame_time > 0 then
				local previous = frame_times_by_inv[inv_frame_time]
				if not previous then
					previous = {0, 0.0}
				end
				frame_times_by_inv[inv_frame_time] = {previous[1]+1, previous[2]+frame_time}
			end
		end
		
		if rc_logging_raw_file then
			table.insert(rc_logging_raw_buffer, string.format("%.3f,%.6f,%.6f,%.6f,%.6f,%d",record[1],record[2],record[3],record[4],record[5],record[6]))
		end
		
		previous_record = record
	end
	
	rc_records={}
	
	local diff_time = last_record[1] - first_record[1] + first_record[5]
	local slowest_indicated_ground_speed = slowest_indicated_ground_speed_meters_per_second * RC_FACTOR_METERS_PER_SECOND_TO_KNOTS
	
	if slowest_indicated_ground_speed < RC_MINIMUM_INDICATED_GROUND_SPEED or RC_PAUSED > 0 then
		-- print(string.format("not calculated: %.2f %.2f %d", slowest_indicated_ground_speed, RC_MINIMUM_INDICATED_GROUND_SPEED, RC_PAUSED))
		rc_previous_record_last = last_record
		return
	end
	
	local great_circle_distance = RC_GreatCircleDistanceInMetersByHaversine(rc_previous_record_last[2], rc_previous_record_last[3], last_record[2], last_record[3]) / RC_METERS_PER_NAUTICAL_MILE
	local externally_perceived_ground_speed = great_circle_distance / diff_time * 3600
	local ground_speed_factor = externally_perceived_ground_speed / slowest_indicated_ground_speed
	
	-- limit GS factor to range [0..1]
	if ground_speed_factor > 1.0 then
		ground_speed_factor = 1.0
	elseif ground_speed_factor < 0.0 then
		ground_speed_factor = 0.0
	end
	
	local fps = num_records / diff_time
	
	local now = os.clock()
	table.insert(rc_ring, {now, diff_time, fps, slowest_indicated_ground_speed, externally_perceived_ground_speed, ground_speed_factor, frame_times_by_inv, great_circle_distance, rc_frame_time_source})
	
	if rc_logging_ring_file then
		local ift_keys = {}
		for ift,arr in pairs(frame_times_by_inv) do
			table.insert(ift_keys, ift)
		end
		table.sort(ift_keys)
		
		local s_frame_times_by_inv = ""
		local is_first = true
		for _,ift in ipairs(ift_keys) do
			local arr = frame_times_by_inv[ift]
			if not is_first then
				s_frame_times_by_inv = s_frame_times_by_inv .. ","
			end
			is_first = false
			s_frame_times_by_inv = s_frame_times_by_inv .. string.format("%d:[%d,%.6f]", ift, arr[1], arr[2])
		end
		
		table.insert(rc_logging_ring_buffer, string.format("%.3f,%.3f,%.2f,%.2f,%.2f,%.4f,%.4f,%d,\"{%s}\"", now, diff_time, fps, slowest_indicated_ground_speed, externally_perceived_ground_speed, ground_speed_factor, great_circle_distance, rc_frame_time_source, s_frame_times_by_inv))
	end
	
	rc_previous_record_last = last_record
end

function RC_Record()
	local frame_time = nil
	if rc_frame_time_source == 1 then
		frame_time = RC_FRAME_TIME1
	else
		frame_time = RC_FRAME_TIME2
	end

	table.insert(rc_records, {os.clock(), LATITUDE, LONGITUDE, RC_GROUND_SPEED, frame_time, rc_frame_time_source})
end

function RC_Analyze()
	local now = os.clock()
	if (now - rc_last_analyze) < RC_ANALYZE_INTERVAL then
		return
	end
	rc_last_analyze = now
	
	rc_notify_level = 0
	rc_notification_text = ""
	
	local oldest_record = nil
	rc_current_records = 0
	
	rc_fps_min = 99999.99
	rc_fps_avg = nil
	rc_fps_max = 0.0
	rc_fps_below_threshold = 0
	
	rc_inv_frame_time_min = 99999.99
	rc_inv_frame_time_avg = nil
	rc_inv_frame_time_max = 0.0

	rc_gs_slowest_indicated_min = 99999.99
	rc_gs_slowest_indicated_avg = nil
	rc_gs_slowest_indicated_max = 0.0

	rc_gs_externally_perceived_min = 99999.99
	rc_gs_externally_perceived_avg = nil
	rc_gs_externally_perceived_max = 0.0

	rc_gs_factor_min = 99999.99
	rc_gs_factor_avg = nil
	rc_gs_factor_max = 0.0
	rc_gs_factor_single_below_threshold1 = 0
	rc_gs_factor_single_below_threshold2 = 0
	
	rc_distance_indicated = 0.0
	rc_distance_externally_perceived = 0.0
	rc_distance_error = nil
	rc_distance_error_level = 0
	
	rc_hist_inv_frame_times_count = {}
	rc_hist_inv_frame_times_time_spent = {}
	rc_time_spent_at_low_ift = 0.0
	rc_time_spent_at_low_ift_percentage = 0.0
	rc_num_low_ift_frames = 0
	rc_num_low_ift_frames_percentage = 0.0
	rc_time_lost_in_time_dilation = 0
	rc_time_lost_in_time_dilation_percentage = 0.0
	
	local aggregated_frame_times_by_inv = {}
	local gs_slowest_indicated_sum = 0.0
	local gs_externally_perceived_sum = 0.0
	local gs_factor_sum = 0.0
	local fps_sum = 0.0
	
	local ring_delete = {}
	for i,record in ipairs(rc_ring) do
		local record_time = record[1]
		local diff_time = record[2]
		local fps = record[3]
		local gs_slowest_indicated = record[4]
		local gs_externally_perceived = record[5]
		local gs_factor = record[6]
		local frame_times_by_inv = record[7]
		local great_circle_distance = record[8]
		
		local age = now - record_time + diff_time
		if age > RC_ANALYZE_MAX_AGE_SECONDS then
			-- record is too old, ignore and remember to delete it
			table.insert(ring_delete, i)
		else
			if not oldest_record then
				oldest_record = record
			end
			
			rc_current_records = rc_current_records + 1
			
			if fps < rc_fps_min then
				rc_fps_min = fps
			end
			if fps > rc_fps_max then
				rc_fps_max = fps
			end
			fps_sum = fps_sum + fps
			if fps < RC_ANALYZE_FPS_THRESHOLD then
				rc_fps_below_threshold = rc_fps_below_threshold + 1
			end
			
			if gs_slowest_indicated < rc_gs_slowest_indicated_min then
				rc_gs_slowest_indicated_min = gs_slowest_indicated
			end
			if gs_slowest_indicated > rc_gs_slowest_indicated_max then
				rc_gs_slowest_indicated_max = gs_slowest_indicated
			end
			gs_slowest_indicated_sum = gs_slowest_indicated_sum + gs_slowest_indicated
			
			if gs_externally_perceived < rc_gs_externally_perceived_min then
				rc_gs_externally_perceived_min = gs_externally_perceived
			end
			if gs_externally_perceived > rc_gs_externally_perceived_max then
				rc_gs_externally_perceived_max = gs_externally_perceived
			end
			gs_externally_perceived_sum = gs_externally_perceived_sum + gs_externally_perceived
			
			if gs_factor < rc_gs_factor_min then
				rc_gs_factor_min = gs_factor
			end
			if gs_factor > rc_gs_factor_max then
				rc_gs_factor_max = gs_factor
			end
			gs_factor_sum = gs_factor_sum + gs_factor
			
			if gs_factor <= RC_ANALYZE_GS_FACTOR_SINGLE_THRESHOLD2 then
				rc_gs_factor_single_below_threshold2 = rc_gs_factor_single_below_threshold2 + 1
			elseif gs_factor <= RC_ANALYZE_GS_FACTOR_SINGLE_THRESHOLD1 then
				rc_gs_factor_single_below_threshold1 = rc_gs_factor_single_below_threshold1 + 1
			end
			
			rc_distance_indicated = rc_distance_indicated + (gs_slowest_indicated * diff_time / 3600)
			rc_distance_externally_perceived = rc_distance_externally_perceived + great_circle_distance
			
			for inv_frame_time, arr in pairs(frame_times_by_inv) do
				local num_frames = arr[1]
				local time_spent = arr[2]
				
				--print(string.format("%03d %03d %.3f", inv_frame_time, num_frames, time_spent))
				
				local aggregated = aggregated_frame_times_by_inv[inv_frame_time]
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
	
	rc_fps_avg = fps_sum / rc_current_records
	rc_gs_slowest_indicated_avg = gs_slowest_indicated_sum / rc_current_records
	rc_gs_externally_perceived_avg = gs_externally_perceived_sum / rc_current_records
	rc_gs_factor_avg = gs_factor_sum / rc_current_records
	rc_distance_error = rc_distance_indicated - rc_distance_externally_perceived
	
	if rc_distance_error < 0.0 then
		rc_distance_error = 0.0
	end
	
	if not oldest_record then
		--print("no data")
		return
	end
	
	local latest_record = rc_ring[#rc_ring]
	rc_observed_time = latest_record[1] - oldest_record[1] + oldest_record[2] -- approximate
	
	rc_distance_error_level = 0
	if rc_distance_error >= RC_ANALYZE_DISTANCE_ERROR_CUMULATIVE_THRESHOLD2 then
		rc_distance_error_level = 2
	elseif rc_distance_error >= RC_ANALYZE_DISTANCE_ERROR_CUMULATIVE_THRESHOLD1 then
		rc_distance_error_level = 1
	end
	
	rc_hist_inv_frame_times_count = RC_ComputeHistogram(aggregated_frame_times_by_inv, 1)
	rc_hist_inv_frame_times_time_spent = RC_ComputeHistogram(aggregated_frame_times_by_inv, 2)
	
	local inv_frame_time_sum = 0.0
	local inv_frame_time_total = 0
	local num_frames_total = 0
	for inv_frame_time,arr in pairs(aggregated_frame_times_by_inv) do
		local num_frames = arr[1]
		num_frames_total = num_frames_total + num_frames
		
		if inv_frame_time < RC_ZERO_TIME_DILATION_FRAME_RATE then
			rc_time_spent_at_low_ift = rc_time_spent_at_low_ift + arr[2]
			rc_num_low_ift_frames = rc_num_low_ift_frames + num_frames
		end
		
		inv_frame_time_sum = inv_frame_time_sum + num_frames * inv_frame_time
		inv_frame_time_total = inv_frame_time_total + num_frames
		if inv_frame_time < rc_inv_frame_time_min then
			rc_inv_frame_time_min = inv_frame_time
		end
		if inv_frame_time > rc_inv_frame_time_max then
			rc_inv_frame_time_max = inv_frame_time
		end
	end
	
	rc_time_spent_at_low_ift_percentage = rc_time_spent_at_low_ift / rc_observed_time * 100.0
	rc_inv_frame_time_avg = inv_frame_time_sum / inv_frame_time_total
	
	rc_num_low_ift_frames_percentage = rc_num_low_ift_frames / num_frames_total * 100.0
	rc_time_lost_in_time_dilation = rc_time_spent_at_low_ift - rc_num_low_ift_frames * RC_ZERO_TIME_DILATION_FRAME_TIME
	rc_time_lost_in_time_dilation_percentage = rc_time_lost_in_time_dilation / rc_observed_time * 100.0
	
	if RC_DEBUG then
		print(string.format("analyzed data of %.1f seconds", rc_observed_time))
		print(string.format("#f/1 min %.1f / avg %.1f / max %.1f, WARN: %d", rc_fps_min, rc_fps_avg, rc_fps_max, rc_fps_below_threshold))
		print(string.format("GSx  min %.2f / avg %.2f / max %.2f, WARN: %d, CRIT: %d", rc_gs_factor_min, rc_gs_factor_avg, rc_gs_factor_max, rc_gs_factor_single_below_threshold1, rc_gs_factor_single_below_threshold2))
		print(string.format("cumulative distance indicated %.2f nm / externally perceived %.2f nm / error %.2f nm / warn level %d", rc_distance_indicated, rc_distance_externally_perceived, rc_distance_error, rc_distance_error_level))
	end
	
	local fps_warning = rc_fps_below_threshold >= RC_NOTIFICATION_THRESHOLD
	local fps_critical = rc_fps_below_threshold >= RC_ANALYZE_FPS_THRESHOLD_TIMES_CRITICAL
	
	local gsx_warning = rc_gs_factor_avg <= RC_ANALYZE_GS_FACTOR_AVERAGE_THRESHOLD1 or rc_gs_factor_single_below_threshold1 >= RC_NOTIFICATION_THRESHOLD
	local gsx_critical = rc_gs_factor_avg <= RC_ANALYZE_GS_FACTOR_AVERAGE_THRESHOLD2 or(rc_gs_factor_single_below_threshold1 + rc_gs_factor_single_below_threshold2) >= RC_NOTIFICATION_THRESHOLD
	
	local dilation_time_warning = rc_time_lost_in_time_dilation >= RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD1
	local dilation_time_critical = rc_time_lost_in_time_dilation >= RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD2
	
	if fps_critical or gsx_critical or rc_distance_error_level > 1 or dilation_time_critical then
		rc_notify_level = 2
	elseif fps_warning or gsx_warning or rc_distance_error_level > 0 or dilation_time_warning then
		rc_notify_level = 1
	end
	
	if rc_logging_analysis_file then
		table.insert(rc_logging_analysis_buffer, string.format("%.3f,%d,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%d,%d,%.3f,%.3f,%.3f,%d,%.3f,%.3f,%.2f,%d,%.2f,%.3f,%.2f", now, rc_current_records, rc_frame_time_source, rc_inv_frame_time_min, rc_inv_frame_time_avg, rc_inv_frame_time_max, rc_fps_min, rc_fps_avg, rc_fps_max, rc_fps_below_threshold, rc_gs_slowest_indicated_min, rc_gs_slowest_indicated_avg, rc_gs_slowest_indicated_max, rc_gs_externally_perceived_min, rc_gs_externally_perceived_avg, rc_gs_externally_perceived_max, rc_gs_factor_min, rc_gs_factor_avg, rc_gs_factor_max, rc_gs_factor_single_below_threshold1, rc_gs_factor_single_below_threshold2, rc_distance_indicated, rc_distance_externally_perceived, rc_distance_error, rc_distance_error_level, rc_time_spent_at_low_ift, rc_observed_time, rc_time_spent_at_low_ift_percentage, rc_num_low_ift_frames, rc_num_low_ift_frames_percentage, rc_time_lost_in_time_dilation, rc_time_lost_in_time_dilation_percentage))
	end
	
	if rc_notify_level < 1 then
		return
	end
	
	rc_notification_text = "Time dilation:"
	local has_preceding_text = false
	
	if dilation_time_warning or dilation_time_critical then
		rc_notification_text = rc_notification_text .. string.format(" lost %.1f seconds (%.1f%%) [%d]", rc_time_lost_in_time_dilation, rc_time_lost_in_time_dilation_percentage, rc_frame_time_source)
		has_preceding_text = true
	end
	
	if rc_distance_error_level > 0 then
		rc_notification_text = rc_notification_text .. string.format(" %.2f nm off expected position", rc_distance_error)
		has_preceding_text = true
	end
	
	if gsx_warning or gsx_critical then
		if has_preceding_text then
			rc_notification_text = rc_notification_text .. " /"
		end
	
		rc_notification_text = rc_notification_text .. string.format(" GSx %.2f/%.2f/%.2f W%d C%d", rc_gs_factor_min, rc_gs_factor_avg, rc_gs_factor_max, rc_gs_factor_single_below_threshold1, rc_gs_factor_single_below_threshold2)
		has_preceding_text = true
	end
	
	if fps_warning or fps_critical then
		if has_preceding_text then
			rc_notification_text = rc_notification_text .. " /"
		end
	
		rc_notification_text = rc_notification_text .. string.format(" #f/s %.1f/%.1f/%.1f W%d", rc_fps_min, rc_fps_avg, rc_fps_max, rc_fps_below_threshold)
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

	local color = "yellow"
	if rc_notify_level > 1 and os.clock() % 2 < 1.0 then
		color = "red"
	end
	
	draw_string(RC_NOTIFICATION_X, RC_NOTIFICATION_Y, rc_notification_text, color)
end

function RC_OpenWindow()
	if rc_window then
		return
	end
	
	rc_window = float_wnd_create(RC_WINDOW_WIDTH, RC_WINDOW_HEIGHT, 1, true)
	float_wnd_set_title(rc_window, "Reality Check v" .. RC_VERSION)
	float_wnd_set_imgui_builder(rc_window, "RC_BuildWindow")
	float_wnd_set_onclose(rc_window, "RC_OnCloseWindow")
	float_wnd_set_position(rc_window, SCREEN_WIDTH - RC_WINDOW_WIDTH - RC_WINDOW_OFFSET, SCREEN_HIGHT - RC_WINDOW_HEIGHT - RC_WINDOW_OFFSET)
end

function RC_BuildWindow(wnd, x, y)
	local has_data = rc_fps_avg ~= nil and rc_fps_min < 99999 and rc_gs_factor_avg ~= nil and rc_gs_factor_min < 99999
	
	if not has_data then
		imgui.TextUnformatted(string.format("No data. Start moving faster than %.0f knots \nindicated GS.", RC_MINIMUM_INDICATED_GROUND_SPEED))
		return
	end
	
	local width = imgui.GetWindowWidth()

	local yellow = 0xFF00FFFF
	local red = 0xFF0000FF
	local color = nil
	
	imgui.TextUnformatted("                min    avg    max")
	imgui.TextUnformatted(string.format("1/frametime%d %6.2f %6.2f %6.2f", rc_frame_time_source, rc_inv_frame_time_min, rc_inv_frame_time_avg, rc_inv_frame_time_max))
	imgui.TextUnformatted(string.format("#frames/1sec %6.2f %6.2f %6.2f", rc_fps_min, rc_fps_avg, rc_fps_max))
	imgui.TextUnformatted(string.format("GS factor    %6.2f %6.2f %6.2f", rc_gs_factor_min, rc_gs_factor_avg, rc_gs_factor_max))
	imgui.TextUnformatted(string.format("GS ind min   %6.1f %6.1f %6.1f", rc_gs_slowest_indicated_min, rc_gs_slowest_indicated_avg, rc_gs_slowest_indicated_max))
	imgui.TextUnformatted(string.format("GS ext pcvd  %6.1f %6.1f %6.1f", rc_gs_externally_perceived_min, rc_gs_externally_perceived_avg, rc_gs_externally_perceived_max))
	
	imgui.TextUnformatted("")
	imgui.TextUnformatted(string.format("%5d frames with low IFT (%.1f%%)", rc_num_low_ift_frames, rc_num_low_ift_frames_percentage))
	imgui.TextUnformatted(string.format("%5.2f seconds spent at low IFT (%.1f%%)", rc_time_spent_at_low_ift, rc_time_spent_at_low_ift_percentage))
	
	if rc_time_lost_in_time_dilation >= RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD2 then
		color = red
	elseif rc_time_lost_in_time_dilation >= RC_ANALYZE_TIME_DILATION_ACTIVE_TIME_THRESHOLD1 then
		color = yellow
	end
	if color then
		imgui.PushStyleColor(imgui.constant.Col.Text, color)
	end
	imgui.TextUnformatted(string.format("%5.2f seconds lost in time dilation (%.1f%%)", rc_time_lost_in_time_dilation, rc_time_lost_in_time_dilation_percentage))
	if color then
		imgui.PopStyleColor()
		color = nil
	end
	
	imgui.TextUnformatted("")
	imgui.TextUnformatted(string.format("cum distance %6.2f nm expected by indication", rc_distance_indicated))
	imgui.TextUnformatted(string.format("             %6.2f nm externally perceived", rc_distance_externally_perceived))
	imgui.TextUnformatted(string.format("             %6.2f nm off expectation", rc_distance_error))
	
	imgui.TextUnformatted("")
	imgui.TextUnformatted(string.format("%3d records analyzed covering %4.1f seconds", rc_current_records, rc_observed_time))
	
	if rc_fps_below_threshold > RC_ANALYZE_FPS_THRESHOLD_TIMES_CRITICAL then
		color = red
	elseif rc_fps_below_threshold > 0 then
		color = yellow
	end
	if color then
		imgui.PushStyleColor(imgui.constant.Col.Text, color)
	end
	imgui.TextUnformatted(string.format("%3d records below #frames/1sec warning threshold", rc_fps_below_threshold))
	if color then
		imgui.PopStyleColor()
		color = nil
	end
	
	if rc_gs_factor_single_below_threshold1 > 0 then
		color = yellow
	end
	if color then
		imgui.PushStyleColor(imgui.constant.Col.Text, color)
	end
	imgui.TextUnformatted(string.format("%3d records below GS factor warning threshold", rc_gs_factor_single_below_threshold1))
	if color then
		imgui.PopStyleColor()
		color = nil
	end
	
	if rc_gs_factor_single_below_threshold2 > 0 then
		color = red
	end
	if color then
		imgui.PushStyleColor(imgui.constant.Col.Text, color)
	end
	imgui.TextUnformatted(string.format("%3d records below GS factor critical threshold", rc_gs_factor_single_below_threshold2))
	if color then
		imgui.PopStyleColor()
		color = nil
	end

	imgui.TextUnformatted("")
	
	local text = "within expected range."
	if rc_gs_factor_avg <= RC_ANALYZE_GS_FACTOR_AVERAGE_THRESHOLD2 then
		color = red
		text = "below critical threshold."
	elseif rc_gs_factor_avg <= RC_ANALYZE_GS_FACTOR_AVERAGE_THRESHOLD1 then
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
	
	if rc_distance_error_level == 0 then
		imgui.TextUnformatted("Cumulative distance is within expected range.")
	elseif rc_distance_error_level == 1 then
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
    if imgui.TreeNode("Inverse Frame Time Histograms") then
		local has_changed = false
		local new_value = false
		
		imgui.TextUnformatted("Show: ")
		
		imgui.SameLine()
		has_changed, new_value = imgui.Checkbox("Count", rc_show_ift_count)
		if has_changed then
			rc_show_ift_count = new_value
		end
		
		imgui.SameLine()
		has_changed, new_value = imgui.Checkbox("Time spent", rc_show_ift_time_spent)
		if has_changed then
			rc_show_ift_time_spent = new_value
		end
		
		if rc_show_ift_count then
			local offset_x, offset_y = imgui.GetCursorScreenPos()
			imgui.PlotHistogram("", rc_hist_inv_frame_times_count, #rc_hist_inv_frame_times_count, -1, "Count", FLT_MAX, FLT_MAX, inner_width - offset_x - 10, 120)
		end
		
		if rc_show_ift_time_spent then
			local offset_x, offset_y = imgui.GetCursorScreenPos()
			imgui.PlotHistogram("", rc_hist_inv_frame_times_time_spent, #rc_hist_inv_frame_times_time_spent, -1, "Time spent", FLT_MAX, FLT_MAX, inner_width - offset_x - 10, 120)
		end
		
		imgui.TreePop()
	end
	
    if imgui.TreeNode("Settings") then
		imgui.TextUnformatted(string.format("Frame time source: [data consistent after %d seconds]", RC_ANALYZE_MAX_AGE_SECONDS))
		
        if imgui.RadioButton("dataref frame_rate_period", rc_frame_time_source == 1) then
            rc_frame_time_source = 1
        end
		imgui.TextUnformatted("   (default before v0.4; IFT never below 19)")
		imgui.TextUnformatted("")
        if imgui.RadioButton("dataref framerate_period", rc_frame_time_source == 2) then
            rc_frame_time_source = 2
        end
		imgui.TextUnformatted("   (default since v0.4)")
		imgui.TextUnformatted("")
        if imgui.RadioButton("LUA clock difference between frames", rc_frame_time_source == 3) then
            rc_frame_time_source = 3
        end
		imgui.TextUnformatted("   (may grow inaccurate in extended sessions)")
		
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

function RC_EnableLoggingRaw()
	if rc_logging_raw_file then
		return
	end
	
	rc_logging_raw_buffer = {}
	rc_logging_raw_file = RC_NewLogFile("raw")
end

function RC_DisableLoggingRaw()
	if not rc_logging_raw_file then
		return
	end
	
	RC_EndLogFile(rc_logging_raw_buffer)
	RC_FlushLogFile(rc_logging_raw_file, rc_logging_raw_buffer)
	rc_logging_raw_file:close()
	
	rc_logging_raw_file = nil
	rc_logging_raw_buffer = {}
end

function RC_EnableLoggingRing()
	if rc_logging_ring_file then
		return
	end
	
	rc_logging_ring_buffer = {}
	rc_logging_ring_file = RC_NewLogFile("ring")
end

function RC_DisableLoggingRing()
	if not rc_logging_ring_file then
		return
	end
	
	RC_EndLogFile(rc_logging_ring_buffer)
	RC_FlushLogFile(rc_logging_ring_file, rc_logging_ring_buffer)
	rc_logging_ring_file:close()
	
	rc_logging_ring_file = nil
	rc_logging_ring_buffer = {}
end

function RC_EnableLoggingAnalysis()
	if rc_logging_analysis_file then
		return
	end
	
	rc_logging_analysis_buffer = {}
	rc_logging_analysis_file = RC_NewLogFile("analysis")
end

function RC_DisableLoggingAnalysis()
	if not rc_logging_analysis_file then
		return
	end
	
	RC_EndLogFile(rc_logging_analysis_buffer)
	RC_FlushLogFile(rc_logging_analysis_file, rc_logging_analysis_buffer)
	rc_logging_analysis_file:close()
	
	rc_logging_analysis_file = nil
	rc_logging_analysis_buffer = {}
end

function RC_NewLogFile(log_type)
	local filename = "RC_" .. os.date("%Y-%m-%d_%H%M%S_") .. log_type
	local fileextension = ".csv"
	
	local file = io.open(filename .. fileextension, "w")
	
	file:write("\"Reality Check\"\n")
	file:write("\"Script version:\",\"", RC_VERSION, "\"\n")
	file:write("\"Log type:\",\"", log_type, "\"\n")
	file:write("\"Start time:\",\"", os.date("%Y-%m-%d %H:%M:%S"), "\"\n")
	file:write("\"LUA clock at start:\",", os.clock(), "\n")
	file:write("\r\n")
	
	if log_type == "raw" then
		file:write("\"clock\",\"latitude\",\"longitude\",\"ground_speed_metric\",\"frame_time\",\"frame_time_source\"\n")
	elseif log_type == "ring" then
		file:write(",,,,,,,, \"{ift:[count,sum_frame_time],...}\"\n")
		file:write("\"record_clock\", \"diff_time\", \"num_frames_1sec\", \"slowest_indicated_gs\", \"externally_perceived_gs\", \"gs_factor\", \"great_circle_distance\", \"frame_time_source\", \"frame_times\"\n")
	elseif log_type == "analysis" then
		file:write("\"analysis_clock\", \"record_count\", \"frame_time_source\", \"ift_min\", \"ift_avg\", \"ift_max\", \"num_frames_1sec_min\", \"num_frames_1sec_avg\", \"num_frames_1sec_max\", \"count_records_num_frames_1sec_below_threshold\", \"gs_ind_slow_min\", \"gs_ind_slow_avg\", \"gs_ind_slow_max\", \"gs_ext_pcvd_min\", \"gs_ext_pcvd_avg\", \"gs_ext_pcvd_max\", \"gs_factor_min\", \"gs_factor_avg\", \"gs_factor_max\", \"gs_factor_single_below_threshold1\", \"gs_factor_single_below_threshold2\", \"distance_expected\", \"distance_externally_perceived\", \"distance_error\", \"distance_error_level\", \"time_spent_at_low_ift\", \"observed_time\", \"time_spent_at_low_ift_percentage\", \"num_low_ift_frames\", \"num_low_ift_frames_percentage\", \"time_lost_in_dilation\", \"time_lost_in_dilation_percentage\"\n")
	end
	
	return file
end

function RC_EndLogFile(buffer)
	table.insert(buffer, "")
	table.insert(buffer, "\"End time:\",\"" .. os.date("%Y-%m-%d %H:%M:%S") .. "\"")
end

function RC_FlushLogFile(file, buffer)
	for i,line in ipairs(buffer) do
		file:write(line, "\n")
		buffer[i] = nil
	end
	
	file:flush()
end

function RC_FlushLogFiles()
	if rc_logging_raw_file then
		RC_FlushLogFile(rc_logging_raw_file, rc_logging_raw_buffer)
	end

	if rc_logging_ring_file then
		RC_FlushLogFile(rc_logging_ring_file, rc_logging_ring_buffer)
	end

	if rc_logging_analysis_file then
		RC_FlushLogFile(rc_logging_analysis_file, rc_logging_analysis_buffer)
	end
end



rc_macro_default_state_notifications = "activate"
if not rc_notification_activated then
	rc_macro_default_state_notifications = "deactivate"
end

add_macro("Show Reality Check analysis", "RC_OpenWindow()")
add_macro("Enable Reality Check notifications", "RC_EnableNotifications()", "RC_DisableNotifications()", rc_macro_default_state_notifications)
add_macro("Log Reality Check raw data", "RC_EnableLoggingRaw()", "RC_DisableLoggingRaw()", "deactivate")
add_macro("Log Reality Check ring data", "RC_EnableLoggingRing()", "RC_DisableLoggingRing()", "deactivate")
add_macro("Log Reality Check analysed data", "RC_EnableLoggingAnalysis()", "RC_DisableLoggingAnalysis()", "deactivate")

do_every_draw("RC_Draw()")
do_every_frame("RC_Record()")
do_often("RC_Count()")
do_often("RC_Analyze()")
do_sometimes("RC_FlushLogFiles()")
do_on_exit("RC_DisableLoggingRaw()")
do_on_exit("RC_DisableLoggingRing()")
do_on_exit("RC_DisableLoggingAnalysis()")

-- if dev version open window for faster development
if string.find(RC_VERSION, 'dev') then
	RC_OpenWindow()
end

print("Loaded Reality Check LUA script version " .. RC_VERSION)
