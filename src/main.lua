--=============================================================================
-- Steel Arena - 2D Tank Battle
-- Entry point: boot shared data, networking, persistence, state machine.
--
-- Run client:      love src
-- Run dedicated:   love src --server
--=============================================================================

local Save      = require("core.save")
local Settings  = require("core.settings")
local Tanks     = require("data.tanks")
local Maps      = require("data.maps")
local Modes     = require("data.modes")
local States    = require("core.state")
local Audio     = require("core.audio")

local love_errorhandler = love.errorhandler

function love.load(args)
  math.randomseed(os.time())
  Settings.load()
  Save.load()
  Audio.load(Settings.data)

  Tanks.init()
  Maps.init()
  Modes.init()

  States.init({
    save     = Save,
    settings = Settings,
    audio    = Audio,
  })

  -- Dedicated server / self-test modes: headless, no states.
  for _, a in ipairs(args or {}) do
    if a == "--server" then
      local ok, err = pcall(function()
        require("server.app").start()
      end)
      if not ok then print("SERVER ERROR: " .. tostring(err)) end
      love.event.quit()
      return
    elseif a == "--selftest" then
      local ok, err = pcall(function()
        local st = require("core.selftest")
        local passed = st.run()
        os.exit(passed and 0 or 1)
      end)
      if not ok then
        print("SELFTEST ERROR: " .. tostring(err))
        os.exit(1)
      end
      return
    end
  end

  love.errorhandler = function(msg)
    return love_errorhandler(msg)
  end

  States.switch("menu.main")
end

function love.update(dt)
  States.update(dt)
end

function love.draw()
  States.draw()
end

function love.keypressed(key, scancode, isrepeat)
  States.keypressed(key, scancode, isrepeat)
end

function love.keyreleased(key, scancode)
  States.keyreleased(key, scancode)
end

function love.mousepressed(x, y, button, istouch, presses)
  States.mousepressed(x, y, button, istouch, presses)
end

function love.mousereleased(x, y, button, istouch, presses)
  States.mousereleased(x, y, button, istouch, presses)
end

function love.mousemoved(x, y, dx, dy, istouch)
  States.mousemoved(x, y, dx, dy, istouch)
end

function love.wheelmoved(x, y)
  States.wheelmoved(x, y)
end

function love.textinput(text)
  States.textinput(text)
end

function love.resize(w, h)
  States.resize(w, h)
end

function love.quit()
  States.quit()
  return true
end
