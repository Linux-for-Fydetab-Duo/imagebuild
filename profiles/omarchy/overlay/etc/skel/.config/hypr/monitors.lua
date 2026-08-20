-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- The Fydetab Duo panel is portrait-native (DSI-1, 1600x2560). Its DRM
-- connector advertises panel orientation "Right Side Up" (property 219, value
-- 3); mutter honours that property, Hyprland/aquamarine ignore it, so the
-- rotation has to be applied here or the whole session appears rotated 90°
-- left. transform 3 = 270°.
-- scale 2: the panel is ~276 DPI; at scale 1 the whole UI is unreadably
-- small. GDK_SCALE matches, as in upstream's default monitors.lua.
hl.env("GDK_SCALE", "2")
hl.monitor({ output = "DSI-1", mode = "preferred", position = "auto", scale = 2, transform = 3 })

-- The himax digitizer reports coordinates in the panel's native portrait
-- space; map it to the rotated output or every touch lands 90° off
-- (mutter compensated for this automatically, Hyprland does not).
hl.config({ input = { touchdevice = { output = "DSI-1", transform = 3 } } })
