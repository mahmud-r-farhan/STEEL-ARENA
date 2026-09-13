function love.conf(t)
  t.identity = "steel_arena"          -- save dir: %APPDATA%/LOVE/steel_arena
  t.version = "11.5"
  t.window.title = "STEEL ARENA - 2D Tank Battle"
  t.window.width = 1280
  t.window.height = 720
  t.window.vsync = 1
  t.window.resizable = true
  t.window.minwidth = 960
  t.window.minheight = 600
  t.window.highdpi = true
  t.modules.joystick = false
  t.modules.physics = false
end
