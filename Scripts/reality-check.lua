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

--DataRef("RC_NETWORK_SECONDS", "sim/network/misc/network_time_sec", "readonly")
DataRef("RC_GROUND_SPEED", "sim/flightmodel/position/groundspeed", "readonly")
DataRef("RC_PAUSED", "sim/time/paused", "readonly")

MEAN_RADIUS_EARTH_METERS = 6371009
METERS_PER_NAUTICAL_MILE = 1852

RC_FACTOR_METERS_PER_SECOND_TO_KNOTS = 3600.0 / METERS_PER_NAUTICAL_MILE

RC_MINIMUM_INDICATED_GROUND_SPEED = 10.0

rc_records={}

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
		print(string.format("not calculated: %.2f %.2f %d", slowest_indicated_ground_speed, RC_MINIMUM_INDICATED_GROUND_SPEED, RC_PAUSED))
		return
	end
	
	great_circle_distance = greatCircleDistanceInMetersByHaversine(first_record[2], first_record[3], last_record[2], last_record[3]) / METERS_PER_NAUTICAL_MILE
	externally_perceived_ground_speed = great_circle_distance / diff_time * 3600
	ground_speed_factor = externally_perceived_ground_speed / slowest_indicated_ground_speed
	
	print(string.format("%0.2f %0.5f %0.2f %0.2f %0.2f", diff_time, great_circle_distance, slowest_indicated_ground_speed, externally_perceived_ground_speed, ground_speed_factor))
end

function RC_Record()
	table.insert(rc_records, {os.clock(), LATITUDE, LONGITUDE, RC_GROUND_SPEED})
end

do_every_frame("RC_Record()")
do_often("RC_Count()")
