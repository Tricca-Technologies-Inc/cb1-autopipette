# Boot-splash white blink: investigated and closed

Status: accepted — closed, do not reopen without an explicit request.

Boot goes black → tricca plymouth theme (logo, throbber below) → logo holds
(plymouth-quit units neutralized; kiosk pre-script quits with
`--retain-splash`) → kiosk, but a sub-second white blink appears between
splash and kiosk. The blink is Chromium's X11 window-clear on startup. All
mitigations were tried and exhausted (flags, dark first-paint, Wayland/cage)
and none eliminated it. The owner has explicitly closed this line of work as
not worth further time.
