-- Headless detection must happen here: window is disabled for
-- dedicated server / self-test runs so they work on any host.
local headless = false
if type(arg) == "table" then
  for _, a in ipairs(arg) do
    if a == "--server" or a == "--selftest" then headless = true end
  end
end

function love.conf(t)
  t.identity = "steel_arena"          -- save dir: %APPDATA%/LOVE/steel_arena
  t.version = "11.5"
  t.window.title = "STEEL ARENA - 2D Tank Battle"
  if headless then
    t.window = false                  -- no window for server/selftest
    t.modules.graphics = false
    t.modules.audio = false
    t.modules.sound = false
  else
    t.window.width = 1280
    t.window.height = 720
    t.window.vsync = 1
    t.window.resizable = true
    t.window.minwidth = 960
    t.window.minheight = 600
    t.window.highdpi = true
  end
  t.modules.joystick = false
  t.modules.physics = false
end
