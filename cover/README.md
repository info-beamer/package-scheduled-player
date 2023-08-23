# Small plugin for covering the screen

Add this plugin to either a layout or an individual tile.
Controlling the plugin requires you to send UDP data to
the running info-beamer process on port 4444. You can send

```
root/plugin/cover/alpha:1,1
```

The first value is the opaqueness of the overlay with 1 being
completely black while 0 is transparent. The second value sets
the duration of the change in seconds. The above sets the
screen to black within one second.

Similarly the following removes the black overlay and shows
your content again in 2 seconds.

```
root/plugin/cover/alpha:0,2
```
