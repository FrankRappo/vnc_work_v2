# 1C calibration notes

Coordinate-driven 1C automation is screen-geometry sensitive.

## Assumptions

- Xvfb / VNC display: `1920x1080`
- Browser window maximized to the same geometry
- Coordinates measured in native pixels, not scaled screenshot pixels

## Suggested calibration workflow

1. Start `examples/1c-vnc/vnc_1c.example.sh up`
2. Open the VNC viewer
3. Capture a reference screenshot
4. Use `xdotool getmouselocation` while hovering target controls
5. Save the coordinates below

## Template coordinates

Replace these with your own values:

### Login screen

- username field: `(945, 559)`
- password field: `(945, 615)`
- login button: `(958, 671)`

### Main shell / logout

- system menu: `(1899, 136)`
- File: `(1703, 335)`
- Exit: `(1474, 404)`
- confirm exit: `(1003, 641)`

## Notes

- If the browser scale or viewport changes, recalibrate everything.
- Prefer clipboard paste for non-ASCII text.
- Always verify clicks with screenshots after important steps.
