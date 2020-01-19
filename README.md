# miscellaneous FlyWithLua scripts for X-Plane

This is just a random collection of FlyWithLua scripts to be used with X-Plane.

## Scripts

### Reality Check

Reality Check compares locally reported with externally perceived speeds (simulation rate vs. real time).

#### What's the issue?

As explained by X-Plane developer Ben Supnik in an excellent [blog post](https://developer.x-plane.com/2017/10/x-plane-11-10-beta-5-ding-dong-the-fps-nag-is-gone-mostly/) some years ago, graphic and physics computation frame rates are linked in X-Plane which generates a requirement for a certain minimum frame rate to be maintained for stable flight model computation. Since that frame rate cannot be guaranteed at all times, X-Plane 11 will slow down the simulation rate if it falls under the minimum FPS, causing time dilation (simulated time passes slower than real time). For users, that behaviour has a benefit of maintaining a smoother control over an aircraft under low FPS conditions while other flight simulators would simply exhibit erratic movements by freezing and skipping ahead in time.

Time dilation is a great feature when flying offline but as you connect to a network of other pilots or ATC it causes issues because your simulator uses its own out-of-sync clock, resulting in your aircraft moving at (much) slower speeds than indicated.

As detailed in the [X-Plane blog](https://developer.x-plane.com/2017/10/x-plane-11-10-beta-5-ding-dong-the-fps-nag-is-gone-mostly/), this is neither an error in X-Plane nor can the behaviour easily be changed. Instead, X-Plane warns the user at least once when the issue is first experienced (usually caused by excessive graphics/detail settings) but most users just disable the notice and then forget about it. Recently, online networks have started to detect such slow-downs and forcibly disconnect users who
are unable to maintain real-time simulation rates.

The goal of this script is to experiment with some ways of detecting time dilation in X-Plane to possibly improve those detections in order to lower the number of false positives (disconnects when they were actually not required).

The issue of time dilation has been around for a long time but only lately and solutions such as (3jFPS-wizard)[https://forums.x-plane.org/index.php?/files/file/43281-3jfps-wizard11/] or AutoLOD are available to maintain a steady framerate.

#### Usage

First, make sure you got [FlyWithLua](https://forums.x-plane.org/index.php?/files/file/38445-flywithlua-ng-next-generation-edition-for-x-plane-11-win-lin-mac/), then copy [Scripts/reality-check.lua](Scripts/reality-check.lua) to the same folder on your FlyWithLua installation. If X-Plane is already running, simply select *Plugins/FlyWithLua/Reload all Lua script files* from the menu.

The script will run in the background and display a notification on screen in case it detects any abnormal behaviour.

To test the analysis, you can trigger some conditions by pausing and unpausing in quick succession.

*Plugins/FlyWithLua/FlyWithLuaMacros* lists two new entries upon installation:

 - *Show Reality Check analysis* opens a window displaying details of the analysis carried out in the background
 - *Enable Reality Check notifications* can be used to disabled/reenable notifications in case they grow too annoying

Detection parameters can be tuned by editing the script file between `CONFIG START` and `CONFIG END` comments.

To uninstall, simply delete the script or move it to another folder (such as *Scripts (disabled)*).

## License

Unless stated otherwise, everything within this repository is licensed under [MIT license](LICENSE.md).
