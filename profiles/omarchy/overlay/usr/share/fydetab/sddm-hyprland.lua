-- SDDM greeter compositor config for the Fydetab Duo: upstream's minimal
-- greeter config plus the rotation the user session gets from monitors.lua
-- (the DSI-1 panel is portrait-native; Hyprland ignores the DRM panel
-- orientation property, so without this the greeter renders 90 deg left).
dofile("/usr/share/sddm/hyprland.lua")

hl.monitor({ output = "DSI-1", mode = "preferred", position = "auto", scale = 2, transform = 3 })
hl.config({ input = { touchdevice = { output = "DSI-1", transform = 3 } } })
