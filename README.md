# miscellaneous FlyWithLua scripts for X-Plane

This is just a random collection of FlyWithLua scripts to be used with X-Plane.

## Scripts

### Reality Check

Reality Check compares locally reported with externally perceived speeds (simulation rate vs. real time) and provides simple frame rate estimations.

See the [full documentation](Documentation/reality-check.md) for more information.

### Time Control

Time Control takes an offset of up to 24 hours to apply to system time.

To install, simply drop [time-control.lua](Scripts/time-control.lua) into the FlyWithLua Scripts directory and reload the scripts in X-Plane.

The script is configured through *Plugins/FlyWithLua/FlyWithLua Macros/Show Time Control*: Simply configure an offset and hit "Apply" which unlinks X-Plane from system time and enables automated updates. While automated updates are enabled, the simulator will periodically be reset to the offset time which allows to keep the offset constant while paused or under time dilation/low FPS.

## License

Unless stated otherwise, everything within this repository is licensed under [MIT license](LICENSE.md).
