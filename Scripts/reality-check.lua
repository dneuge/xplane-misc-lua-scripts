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

RC_MINIMUM_INDICATED_GROUND_SPEED = 10.0 -- minimum indicated GS at which we should start recording

RC_ANALYZE_MAX_AGE_SECONDS = 30.0 -- age of oldest record to analyze
RC_ANALYZE_INTERVAL = 3 -- analyze at most once every x seconds
RC_ANALYZE_FPS_THRESHOLD = 20.0 -- count number of records below this threshold of FPS
RC_ANALYZE_GS_FACTOR_THRESHOLD1 = 0.95 -- "warning" level of ground speed slow-down factor
RC_ANALYZE_GS_FACTOR_THRESHOLD2 = 0.85 -- "critical" level of ground speed slow-down factor
RC_ANALYZE_DISTANCE_ERROR_CUMULATIVE_THRESHOLD1 = 0.75 -- "warning" level of cumulative error of distance over time in nautical miles
RC_ANALYZE_DISTANCE_ERROR_CUMULATIVE_THRESHOLD2 = 1.50 -- "critical" level of cumulative error of distance over time in nautical miles

MEAN_RADIUS_EARTH_METERS = 6371009
METERS_PER_NAUTICAL_MILE = 1852
RC_FACTOR_METERS_PER_SECOND_TO_KNOTS = 3600.0 / METERS_PER_NAUTICAL_MILE

--- CONFIG END


DataRef("RC_GROUND_SPEED", "sim/flightmodel/position/groundspeed", "readonly")
DataRef("RC_PAUSED", "sim/time/paused", "readonly")

rc_records={}
rc_ring={}
rc_last_analyze=0.0

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
	
	for i,record in ipairs(rc_records) do
		ground_speed_meters_per_second = record[4]
	
		if not first_record then
			first_record = record
		end
		
		last_record = record
		
		if ground_speed_meters_per_second < slowest_indicated_ground_speed_meters_per_second then
			slowest_indicated_ground_speed_meters_per_second = ground_speed_meters_per_second
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
	
	if ground_speed_factor > 1.0 then
		ground_speed_factor = 1.0
	elseif ground_speed_factor < 0.0 then
		ground_speed_factor = 0.0
	end
	
	fps = num_records / diff_time
	
	table.insert(rc_ring, {os.clock(), diff_time, fps, slowest_indicated_ground_speed, externally_perceived_ground_speed, ground_speed_factor})
	
	--print(string.format("%.2f %.1f %.5f %.2f %.2f %.2f", diff_time, fps, great_circle_distance, slowest_indicated_ground_speed, externally_perceived_ground_speed, ground_speed_factor))
end

function RC_Record()
	table.insert(rc_records, {os.clock(), LATITUDE, LONGITUDE, RC_GROUND_SPEED})
end

function RC_Analyze()
	now = os.clock()
	if (now - rc_last_analyze) < RC_ANALYZE_INTERVAL then
		return
	end
	rc_last_analyze = now
	
	oldest_record = nil
	current_records = 0
	
	fps_min = 99999.99
	fps_avg = nil
	fps_max = 0.0
	fps_sum = 0.0
	fps_below_threshold = 0
	
	gs_factor_min = 99999.99
	gs_factor_avg = nil
	gs_factor_max = 0.0
	gs_factor_sum = 0.0
	gs_factor_below_threshold1 = 0
	gs_factor_below_threshold2 = 0
	
	distance_indicated = 0.0
	distance_externally_perceived = 0.0
	distance_error = nil
	
	ring_delete = {}
	for i,record in ipairs(rc_ring) do
		record_time = record[1]
		diff_time = record[2]
		fps = record[3]
		gs_slowest_indicated = record[4]
		gs_externally_perceived = record[5]
		
		age = now - record_time
		if age >= RC_ANALYZE_MAX_AGE_SECONDS then
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
			
			gs_factor = record[6]
			if gs_factor < gs_factor_min then
				gs_factor_min = gs_factor
			end
			if gs_factor > gs_factor_max then
				gs_factor_max = gs_factor
			end
			gs_factor_sum = gs_factor_sum + gs_factor
			if gs_factor < RC_ANALYZE_GS_FACTOR_THRESHOLD1 then
				gs_factor_below_threshold1 = gs_factor_below_threshold1 + 1
			end
			if gs_factor < RC_ANALYZE_GS_FACTOR_THRESHOLD2 then
				gs_factor_below_threshold2 = gs_factor_below_threshold2 + 1
			end
			
			distance_indicated = distance_indicated + (gs_slowest_indicated * diff_time / 3600)
			distance_externally_perceived = distance_externally_perceived + (gs_externally_perceived * diff_time / 3600)
		end
	end
	
	for i = #ring_delete,1,-1 do
		table.remove(rc_ring, i)
	end
	
	fps_avg = fps_sum / current_records
	gs_factor_avg = gs_factor_sum / current_records
	distance_error = distance_indicated - distance_externally_perceived
	
	if distance_error < 0.0 then
		distance_error = 0.0
	end
	
	if not oldest_record then
		print("no data")
		return
	end
	
	oldest_record_age = now - oldest_record[1]
	
	print(string.format("have data for last %.1f seconds", oldest_record_age))
	print(string.format("FPS min %.1f / avg %.1f / max %.1f, WARN: %d", fps_min, fps_avg, fps_max, fps_below_threshold))
	print(string.format("GSx min %.1f / avg %.1f / max %.1f, WARN: %d, CRIT: %d", gs_factor_min, gs_factor_avg, gs_factor_max, gs_factor_below_threshold1, gs_factor_below_threshold2))
	print(string.format("cumulative distance indicated %.2f nm / externally perceived %.2f nm / error %.2f nm", distance_indicated, distance_externally_perceived, distance_error))
	
	if distance_error >= RC_ANALYZE_DISTANCE_ERROR_CUMULATIVE_THRESHOLD2 then
		print("cumulative distance error is CRITICAL")
	elseif distance_error >= RC_ANALYZE_DISTANCE_ERROR_CUMULATIVE_THRESHOLD1 then
		print("cumulative distance error exceeds WARNING threshold")
	else
		print("cumulative distance error is OK")
	end
end

do_every_frame("RC_Record()")
do_often("RC_Count()")
do_often("RC_Analyze()")

print("Loaded Reality Check LUA script")
