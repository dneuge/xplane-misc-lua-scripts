# Reality Check

Reality Check compares locally reported with externally perceived speeds (simulation rate vs. real time) and provides simple frame rate estimations.

## What's the issue?

As explained by X-Plane developer Ben Supnik in an excellent [blog post](https://developer.x-plane.com/2017/10/x-plane-11-10-beta-5-ding-dong-the-fps-nag-is-gone-mostly/) some years ago, graphic and physics computation frame rates are linked in X-Plane which generates a requirement for a certain minimum frame rate to be maintained for stable flight model computation. Since that frame rate cannot be guaranteed at all times, X-Plane 11 will slow down the simulation rate if it falls under the minimum FPS, causing time dilation (simulated time passes slower than real time). For users, that behaviour has a benefit of maintaining a smoother control over an aircraft under low FPS conditions while other flight simulators would simply exhibit erratic movements by freezing and skipping ahead in time.

Time dilation is a great feature when flying offline but as you connect to a network of other pilots or ATC it causes issues because your simulator uses its own out-of-sync clock, resulting in your aircraft moving at (much) slower speeds than indicated.

As detailed in the [X-Plane blog](https://developer.x-plane.com/2017/10/x-plane-11-10-beta-5-ding-dong-the-fps-nag-is-gone-mostly/), this is neither an error in X-Plane nor can the behaviour easily be changed. Instead, X-Plane warns the user at least once when the issue is first experienced (usually caused by excessive graphics/detail settings) but most users just disable the notice and then forget about it. Recently, online networks have started to detect such slow-downs and forcibly disconnect users who
are unable to maintain real-time simulation rates.

The goal of this script is to experiment with some ways of detecting time dilation in X-Plane to possibly improve those detections in order to lower the number of false positives (disconnects when they were actually not required).

The issue of time dilation has been around for a long time but only lately and solutions such as [3jFPS-wizard](https://forums.x-plane.org/index.php?/files/file/43281-3jfps-wizard11/) or [AutoLOD](http://www.x-plane.at/drupal/node/386) are available to maintain a steady framerate.

## What does the script do?

Reality Check experiments with a number of different metrics to estimate the error caused by time dilation. This is useful in different ways:

 - users can see when time dilation is active on their machines and what issues it might be causing to other clients
 - developers can gain better insights and gather comparable data about the effects of time dilation in X-Plane

The script collects basic data per frame (position, indicated speed, frame time; raw log file) and aggregates it over time windows of approximately 1 second ("records", ring log file).

An analysis is performed on that aggregated data every 3 seconds by default, including records of the last 30 seconds (analysis log file).

If any issues are detected, a simple text will appear on your screen with triggering criteria in a compressed format (see [Understanding the analysed values](#understanding-the-analysed-values)).

At any time, users can call up the analysis window with detailed information about collected values.

Users can also log data to later submit them to developers or do their own calculations on collected data. Log files can be opened in any spreadsheet program such as LibreOffice or Excel.

## What does the script not do?

 - it does not disconnect you from any network
 - it cannot give you an accurate indication if you would have been disconnected using any pilot client (pilot clients perform their own calculations and have different criteria)
 - it does not say if a pilot client "is wrong" because there is no "wrong" - there are just different calculations/criteria being applied
   - however, Reality Check aims at helping developers to fine-tune and evaluate calculation methods, so please be nice and maintain a positive, supporting way of communication when submitting data to developers

## Usage

First, make sure you got [FlyWithLua](https://forums.x-plane.org/index.php?/files/file/38445-flywithlua-ng-next-generation-edition-for-x-plane-11-win-lin-mac/), then copy [Scripts/reality-check.lua](../Scripts/reality-check.lua) to the same folder on your FlyWithLua installation. If X-Plane is already running, simply select *Plugins/FlyWithLua/Reload all Lua script files* from the menu.

The script will run in the background and display a notification on screen in case it detects any abnormal behaviour.

To test the analysis, you can trigger some conditions by pausing and unpausing in quick succession while moving faster than the minimum speed (default: 10 knots ground speed).

*Plugins/FlyWithLua/FlyWithLuaMacros* lists multiple new entries upon installation:

 - *Show Reality Check analysis* opens a window displaying details of the analysis carried out in the background
 - *Enable Reality Check notifications* can be used to disabled/reenable notifications in case they grow too annoying
 - *Log Reality Check ... data* starts/stops logging to a timestamped CSV file in your X-Plane root folder
   - *raw* logs unprocessed data captured for each frame
   - *ring* logs first-level aggregated information (referred to as "records" in analysis)
   - *analysed* logs fully analyzed information (basically the same as displayed in the analysis window)

Detection parameters can be tuned by editing the script file between `CONFIG START` and `CONFIG END` comments.

Furthermore, the analysis window offers an option to select between multiple sources of frame time values. Please read more about [frame time sources](#frame-time-source) before changing that.

Options will not be persisted across restarts/script reloads.

To uninstall, simply delete the script or move it to another folder (such as *Scripts (disabled)*).

## Understanding the analysed values

Recorded raw data is aggregated to "records" once each second, so a "record" always refers to aggregated data over a time window of roughly 1 second.

Analysed values are based on

 - calculated frame time/frame rate 
 - distance covered by your aircraft (position, reported speed)

To avoid errors in distance calculations, by default a minimum ground speed of 10 knots is required to start analysis.

### Analysis window

Lines may be colored grey (no warning), yellow (first warning level) or red ("critical" warning level) depending on triggered warning conditions.

The top section shows various values, displaying minimum (*min*), average (*avg*) and maximum (*max*) for each record (aggregated data over a period of ~1 second):

 - *1/frametime* is also referred to as *Inverse Frame Time* or *IFT* and is an indication of the frame rate determined by dividing a second by the time it took each single frame to be calculated. The number after *frametime* is just an indication of the currently selected frame time source (only useful to developers). Time dilation is believed to affect frames below 20 IFT. This should roughly be what is usually known as "FPS".
 - *#frames/sec* is another way of calculating the frame rate and takes "FPS" literal as it is the number of frames seen in a record, normalized to a period of 1.0 seconds. It will most-likely not match what's known as "FPS" but if the value drops 20 it will be a pretty good guarantee that time dilation is causing some error.
 - *GS factor* shows the factor of your indicated ground speed compared to your actual change in position as observed outside your simulator. A value of 1.0 indicates no time dilation or acceleration (your externally perceived position/speed matched what is indicated in your simulator). Lower values mean that, when using a real-time clock, you are moving at a slower speed than indicated in your aircraft's avionics. Higher values indicate that you appear to be affected by some sort of time acceleration. Note that very small deviations such as 0.99 or 1.01 (each meaning you are 1% off real time) are most-likely just calculation errors. In general, small deviations cannot be noticed by external observers such as other pilots or controllers in a networked environment so there is no need to be alarmed by small fluctuations.
 - *GS ind min* (short for "indicated minimum") is the indicated ground speed as displayed in your simulator/avionics. Only the minimum observed per record is taken into consideration.
 - *GS ext pcvd* (short for "externally perceived") is the ground speed based on your system's real-time clock, calculated using the distance covered between two records. If it is lower than your indicated minimum ground speed, time dilation is most-likely in effect. If time is either dilated or accelerated the distance error will grow over time. Note that even when running completely at real-time this value may deviate (and exceed) from the indicated minimum ground speed as it is the average ground speed over the record time window (~1 second) instead of the minimum of the same time period.

Next, you see some values calculated from inverse frame time (IFT or "FPS"; only data from observed moving time window of up to 30 seconds is used):

 - *n frames with low IFT* is the total number of frames with an IFT below 20 (assumed criteria for activation of time dilation) over the total observed time period (up to 30 seconds). The fraction of low IFT frames to total frames over the observed time period is displayed as a percentage.
 - *x seconds spent at low IFT* shows the sum of all frame times with IFT below 20. The fraction of time with low IFT over observed total time period (up to 30 seconds) is displayed as a percentage.
 - *x seconds lost in time dilation* shows the cumulative difference of all frame times to 20 IFT (50 milliseconds). Assuming that X-Plane applies time dilation to all frames with IFT below 20, this value should equal the time your simulator runs late when compared to a real-time clock. Percentage refers to the fraction of total observed time (up to 30 seconds).

The next block deals with *cum(ulative) distance*:

 - *x nm expected by indication* is the distance your aircraft should have covered over the total observation period (up to 30 seconds) if it flew at real-time at its indicated minimum ground speed. The distance is calculated by the sum of indicated minimum ground speed over covered time periods.
 - *x nm externally perceived* is the distance your aircraft has actually covered over the total observation period (up to 30 seconds). This is what others would see your aircraft do when connected to a networked simulation environment with real-time clocks not synchronized to your simulator. The distance is calculated as the sum of great circle distances between positions of each record (at ~1 second intervals).
 - *x nm off expectation* is the absolute difference between expectation by indication and externally perceived distance (up to 30 seconds). This is the error an external observer will see. An error of 1.0 nm would mean that your position (compared over 30 seconds) is one nautical mile behind (if in time dilation) or ahead (if time is accelerated) the position your aircraft should have been at if it had been moved at real-time simulation rate. The error will grow as time dilation gets stronger (i.e. *GS factor* drops) or time dilation or acceleration continues over a longer period of time (see *seconds lost in time dilation*).

The second-to-last block shows evaluations counting records exceeding thresholds of warning criteria:

 - *n records analyzed covering x seconds* is just informational and gives you an indication of how much data has been included in the analysis.
 - *n records below #frames/1sec warning threshold* shows how many records saw less than 20 frames during their time period. Keep in mind that this does not match the momentary "FPS" calculated by IFT; think of it more as an "average per second". As explained above, having this value drop below 20 will be a guarantee to see some problems due to time dilation but it is not an accurate method for more detailed time dilation analysis.
 - *n records exceeded GS factor warning threshold* shows how many records dropped below a threshold factor of 0.80 (time dilation) or went above 1.10 (time acceleration). The number excludes records which exceeded the critical threshold.
 - *n records exceeded GS factor critical threshold* shows how many records dropped below a threshold factor of 0.70 (time dilation) or went above 1.20 (time acceleration).

The last block shows evaluations based on average values over the total observed time period (up to 30 seconds):

 - *Average GS factor*
   - *is within expected range*: GS factor is > 0.95 and < 1.05 (you are moving at or close to real-time within 5% of your indicated speed)
   - *exceeds warning threshold*: GS factor is <= 0.95 (you are moving 5% slower than indicated) or >= 1.05 (5% faster than indicated)
   - *exceeds critical threshold*: GS factor is <= 0.85 (you are moving 15% slower than indicated) or >= 1.10 (10% faster than indicated)
 - *Cumulative distance is*
   - *within expected range*: distance error is less than 0.3 nautical miles
   - *slightly off external perception*: distance error is at least 0.3 nautical miles (external observers may start to notice the position error)
   - *severely off external perception*: distance error is at least 0.75 nautical miles (external observers are most-likely influenced by your simulator's position error, particularly on final approach)

*Inverse Time Histograms* offers you to inspect the number of frames counted by their IFT and the (cumulative) time spent at each frame rate.

In *Settings* you can select an alternate source for frame time calculation. Please only change this option if you understand the effects; read the section about [frame time source](#frame-time-source) below.

### Text notification

If averaged values trigger warning conditions or a minimum number (default: 3) of record-based criteria is triggered, a text notification (starting with "Time dilation:") will appear on screen, even if the analysis window is closed. The notification can be disabled through the FlyWithLua menu (deselect *Enable Reality Check notifications*).

Only triggered criteria will be shown.

The notification will start flashing between red if critical criteria have been triggered.

Displayed information:

 - *lost x seconds (y%) [z]*: see analysis window *x seconds lost in time dilation (y%)*; *z* indicates the time source (useful for developers)
 - *x nm off expected position*: see analysis window *cum distance x nm off expectation*
 - *GSx x/y/z Wa Cb*: GS factor (see analysis window) has a mininum value of *x*, average value of *y* and maximum value of *z*, *a* records trigger warning condition, *b* records trigger critical condition
   - an additional explanation *(too slow)*, *(too fast)* or even *(too slow and too fast)* (if different records over the observation period indicated both types) will be added to signify the type of error
 - *#f/s x/y/z Wa*: see analysis window *#frames/1sec* (number of frames seen per record); minimum value is *x*, average *y*, maximum *z*, *a* records trigger warning condition (only shown if at least 5 records exceeded the threshold)

### Log files

All log files are prefixed `RC_`, contain the timestamp of log start, indicate the type of log (`raw`, `ring`, `analysis`) and have an extension of `csv`, for example: `RC_2020-01-26_142531_analysis.csv`

Log files are saved without changing the working directory (by default: X-Plane root folder). If another LUA script has changed the working directory, files may be found there instead.

All log files contain a header showing script version, log type and time at start of log. If a log has been closed normally, the last line will contain the time when logging has been terminated. Logs are buffered and flushed at irregular intervals.

The created CSV files use commas (`,`) for column separation and double quotes (`"`) around strings. Floating point numbers use an English decimal point (`.`). Be careful when opening these files in spreadsheet programs as the decimal point may be mistaken for a thousands-separator on import, resulting in values being randomly shifted by several orders of magnitude. If the spreadsheet program offers a language/locale selection, choose a standard English formatting for import.

Applying to all log files:
 - If `frame_time_source` is `1`, `frame_time` has been read from dataref `sim/operation/misc/frame_rate_period`. If set to `2` (default), `frame_time` has been read from dataref `sim/time/framerate_period`. `3` means that ring and analysis log files use the difference in LUA clock to previous record in which case the column is not relevant for raw log (treat value as undefined). Read the section about [frame time source](#frame-time-source) for more details.

#### Raw log file (`raw`)

The raw log file contains unaggregated data recorded per frame.

| Column                | Data                                            |
| --------------------- | ----------------------------------------------- |
| `clock`               | LUA clock at time of running the frame callback |
| `latitude`            | latitude of aircraft position                   |
| `longitude`           | longitude of aircraft position                  |
| `ground_speed_metric` | indicated ground speed in meters per second     |
| `frame_time`          | frame time (see above)                          |
| `frame_time_source`   | user-selected frame time source                 |

#### Ring log file (`ring`)

The ring log file contains aggregated data per record (approximately once per second).

| Column                    | Data                                                                                                    |
| ------------------------- | ------------------------------------------------------------------------------------------------------- |
| `record_clock`            | LUA clock at time of record aggregation                                                                 |
| `diff_time`               | time difference to previous record in seconds                                                           |
| `num_frames_1sec`         | number of frames counted in record time window, normalized to one second                                |
| `slowest_indicated_gs`    | slowest indicated ground speed in knots over record time window                                         |
| `externally_perceived_gs` | ground speed calculated based on real-time difference between records from actual great-circle distance |
| `gs_factor`               | fraction of externally perceived ground speed compared to slowest indicated ground speed                |
| `great_circle_distance`   | actual great circle distance in nautical miles covered since last record                                |
| `frame_time_source`       | user-selected frame time source                                                                         |
| `frame_times`             | histogram data holding number of frames and sum of frame times by IFT                                   |

Note that any change in `frame_time_source` will lead to inconsistent frame time data during the first record after change.

#### Analysis log file (`analysis`)

The analysis log file contains most data shown to user in the analysis window.

| Column                                          | Data                                                                                                     |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `analysis_clock`                                | LUA clock at time of analysis                                                                            |
| `record_count`                                  | number of records included in analysis                                                                   |
| `frame_time_source`                             | user-selected frame time source                                                                          |
| `ift_min`                                       | minimum inverse frame time (*1/frametime min*)                                                           |
| `ift_avg`                                       | average inverse frame time (*1/frametime avg*)                                                           |
| `ift_max`                                       | maximum inverse frame time (*1/frametime max*)                                                           |
| `num_frames_1sec_min`                           | minimum of frames counted normalized to 1 second (*#frames/1sec min*)                                    |
| `num_frames_1sec_avg`                           | average of frames counted normalized to 1 second (*#frames/1sec avg*)                                    |
| `num_frames_1sec_max`                           | maximum of frames counted normalized to 1 second (*#frames/1sec max*)                                    |
| `count_records_num_frames_1sec_below_threshold` | number of records which have *#frames/1sec* below threshold (default 20)                                 |
| `gs_ind_slow_min`                               | minimum of slowest indicated ground speed                                                                |
| `gs_ind_slow_avg`                               | average of slowest indicated ground speed                                                                |
| `gs_ind_slow_max`                               | maximum of slowest indicated ground speed                                                                |
| `gs_ext_pcvd_min`                               | minimum of externally perceived ground speed                                                             |
| `gs_ext_pcvd_avg`                               | average of externally perceived ground speed                                                             |
| `gs_ext_pcvd_max`                               | maximum of externally perceived ground speed                                                             |
| `gs_factor_min`                                 | minimum ground speed factor                                                                              |
| `gs_factor_avg`                                 | average ground speed factor                                                                              |
| `gs_factor_max`                                 | maximum ground speed factor                                                                              |
| `gs_factor_single_below_threshold1`             | number of records with GS factor at or below single record warning threshold (0.80)                      |
| `gs_factor_single_below_threshold2`             | number of records with GS factor at or below single record critical threshold (0.70)                     |
| `gs_over_factor_single_above_threshold1`        | number of records with GS factor at or above single record warning threshold (1.10)                      |
| `gs_over_factor_single_above_threshold2`        | number of records with GS factor at or above single record critical threshold (1.20)                     |
| `distance_expected`                             | cumulative distance in nautical miles as expected by indication                                          |
| `distance_externally_perceived`                 | cumulative distance in nautical miles actually covered                                                   |
| `distance_error`                                | distance error in nautical miles                                                                         |
| `distance_error_level`                          | `1` = warning level (distance error >= 0.3nm), `2` = critical level (distance error >= 0.75nm)           |
| `time_spent_at_low_ift`                         | total seconds of frame time where IFT was below 20                                                       |
| `observed_time`                                 | total seconds covered by records included in analysis                                                    |
| `time_spent_at_low_ift_percentage`              | percentage of total frame time where IFT was below 20 compared to total observed time                    |
| `num_low_ift_frames`                            | number of frames with IFT below 20                                                                       |
| `num_low_ift_frames_percentage`                 | percentage of number of frames with IFT below 20 compared to total number of frames included in analysis |
| `time_lost_in_dilation`                         | seconds "lost in time dilation" (difference of frame times to 1/20 = 50 milliseconds)                    |
| `time_lost_in_dilation_percentage`              | percentage of seconds "lost in time dilation" compared to total observed time                            |
| `num_records_gs_factor_unreliable`              | number of records with imprecise data making GS factor unreliable (related warnings disabled if >0)      |

Note that any change in `frame_time_source` will lead to inconsistent frame time data for a full data cycle (by default approximately 30 seconds).

## Details of data collection and analysis (for developers)

### General notes

Reality Check has been written "quick and dirty" proof of concept to quickly have a way to evaluate methods to solve the immediate problems experienced on an online network. As a result, the source code is not perfect and in some parts even "sloppy", in particular terms or variable names may not be used consistently and there may be some errors in calculations.

### Accuracy

 - FlyWithLua's `os.clock()` (seconds since start of simulator) is used as source for real-time and record timestamps; it appears this value is using a single-precision float, so it should be considered that times measured down to milliseconds will have a certain error which increases with simulator uptime
 - great circle distance (externally perceived distance) and, as a result, calculated externally perceived ground speed, GS factor and distance error has a high error at very steep climbs or dives (aerobatics or stalls)
 - calculations are not guaranteed to be 100% correct; you are advised to check the source code for any errors or misinterpretations and not blindly copy calculations

### Frame time source

The analysis window offers an option to change the source of frame times. You should only change the frame time source if you have a good reason to do so (e.g. testing data sources):

 - *dataref frame_rate_period* was used in versions 0.2 and 0.3 of this script, full name is `sim/operation/misc/frame_rate_period`. Unfortunately that dataref appears to be limited to a lowest frame rate of 19 FPS, so apparently it refers more to the physics engine than actual frame rate. Using this dataref voids multiple analyzed values.
 - *dataref framerate_period* is the default as of version 0.4, full name is `sim/time/framerate_period`. Although [official documentation](https://developer.x-plane.com/datarefs/) says this dataref is "smoothed" and also refers to it as "frame rate", it gives more reasonable results which match actual FPS more closely.
 - *LUA clock difference between frames* simply subtracts timestamps logged each frame internally by this script, not using any dataref but `os.clock()` in LUA. This methods yields somewhat different results (lower) than `framerate_period` and it's hard to tell what's correct. Unfortunately, most values in LUA only use single-precision floating point numbers which means measured frame time will grow inaccurate with increasing uptime.

## License

Reality Check is licensed under [MIT license](LICENSE.md).
