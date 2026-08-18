-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- The FydeTab Duo panel is portrait-native (DSI-1, 1600x2560). Its DRM
-- connector advertises panel orientation "Right Side Up" (property 219, value
-- 3); mutter honours that property, Hyprland/aquamarine ignore it, so the
-- rotation has to be applied here or the whole session appears rotated 90°
-- left. transform 3 = 270°.
-- scale 2: the panel is ~276 DPI; at scale 1 the whole UI is unreadably
-- small. GDK_SCALE matches, as in upstream's default monitors.lua.
hl.env("GDK_SCALE", "2")
hl.monitor({ output = "DSI-1", mode = "preferred", position = "auto", scale = 2, transform = 3 })
