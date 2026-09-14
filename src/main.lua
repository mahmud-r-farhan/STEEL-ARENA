--=============================================================================
-- Steel Arena - 2D Tank Battle
-- Entry point: boot shared data, networking, persistence, state machine.
--
-- Run client:      love src
-- Run dedicated:   love src --server
-- Self-test:       love src --selftest
-- Smoke test:      love src --smoke
--=============================================================================

-- ensure both src-root and LÖVE save-dir module resolution
package.path = ";./?.lua;./?/init.lua" .. package.path

local Save      = require("core.save")
local Settings  = require("core.settings")
local Tanks     = require("data.tanks")
local Maps      = require("data.maps")
local Modes     = require("data.modes")
local States    = require("core.state")
local Audio     = require("core.audio")
local Viewport  = require("core.viewport")
local Kit       = require("ui.kit")

local love_errorhandler = love.errorhandler

-- smoke-test flags (set by --smoke arg)
SMOKE_TEST = false
SMOKE_START = 0

function love.load(args)
  math.randomseed(os.time())
  Settings.load()
  Save.load()
  Audio.load(Settings)
  Audio.applyVolumes()

  Tanks.init()
  Maps.init()
  Modes.init()

  States.init({
    save     = Save,
    settings = Settings,
    audio    = Audio,
    viewport = Viewport,
  })

  Viewport.update()

  if love and love.mouse and love.mouse.getPosition then
    local _rawGetPos = love.mouse.getPosition
    love.mouse.getPosition = function()
      Viewport.update()
      local rx, ry = _rawGetPos()
      return Viewport.toVirtual(rx, ry)
    end
  end

  -- Dedicated server / self-test / net-test / smoke-test modes.
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
    elseif a == "--nettest" then
      -- headless end-to-end client<->server test
      local ok, err = pcall(function()
        local nt = require("core.nettest")
        local passed = nt.run()
        os.exit(passed and 0 or 1)
      end)
      if not ok then
        print("NETTEST ERROR: " .. tostring(err))
        os.exit(1)
      end
      return
    elseif a == "--smoke" then
      -- windowed smoke test: boot menu, then quit after 3s
      SMOKE_TEST = true
      SMOKE_START = love.timer.getTime()
    end
  end

  love.errorhandler = function(msg)
    return love_errorhandler(msg)
  end

  print("[boot] switching to menu.main")
  States.switch("menu.main")
  print("[boot] menu.main entered")
end

local _rawUpdate = nil
function love.update(dt)
  local ok, err = xpcall(function() _updateBody(dt) end, function(e)
    print("[UPDATE ERROR] " .. tostring(e))
    print(debug.traceback(e, 2))
  end)
  if not ok then love.event.quit() end
end

function _updateBody(dt)
  States.update(dt)
  if SMOKE_TEST and love.timer.getTime() - SMOKE_START > 3 then
    SMOKE_TEST = false
    print("SMOKE TEST PASSED: menu booted, rendered and updated for 3s")
    love.event.quit()
  end
end

function love.draw()
  Viewport.apply()
  local ok, err = xpcall(States.draw, function(e)
    print("[DRAW ERROR] " .. tostring(e))
    print(debug.traceback(e, 2))
  end)
  Viewport.pop()
  Kit.clearClick()
  if not ok then love.event.quit() end
end

function love.keypressed(key, scancode, isrepeat)
  States.keypressed(key, scancode, isrepeat)
end

function love.keyreleased(key, scancode)
  States.keyreleased(key, scancode)
end

function love.mousepressed(x, y, button, istouch, presses)
  Viewport.update()
  local vx, vy = Viewport.toVirtual(x, y)
  States.mousepressed(vx, vy, button, istouch, presses)
end

function love.mousereleased(x, y, button, istouch, presses)
  Viewport.update()
  local vx, vy = Viewport.toVirtual(x, y)
  States.mousereleased(vx, vy, button, istouch, presses)
end

function love.mousemoved(x, y, dx, dy, istouch)
  Viewport.update()
  local vx, vy = Viewport.toVirtual(x, y)
  local scale = Viewport.scale > 0 and Viewport.scale or 1
  States.mousemoved(vx, vy, dx / scale, dy / scale, istouch)
end

local function denormTouch(x, y, dx, dy)
  local gw = (love and love.graphics and love.graphics.getWidth) and love.graphics.getWidth() or 1280
  local gh = (love and love.graphics and love.graphics.getHeight) and love.graphics.getHeight() or 720
  local px = (x <= 1 and y <= 1) and (x * gw) or x
  local py = (x <= 1 and y <= 1) and (y * gh) or y
  local pdx = (dx and math.abs(dx) <= 1) and (dx * gw) or (dx or 0)
  local pdy = (dy and math.abs(dy) <= 1) and (dy * gh) or (dy or 0)
  return px, py, pdx, pdy
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  Viewport.touchActive = true
  Viewport.update()
  local px, py, pdx, pdy = denormTouch(x, y, dx, dy)
  local vx, vy = Viewport.toVirtual(px, py)
  local scale = Viewport.scale > 0 and Viewport.scale or 1
  States.touchpressed(id, vx, vy, pdx / scale, pdy / scale, pressure)
  States.mousepressed(vx, vy, 1, true, 1)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  Viewport.update()
  local px, py, pdx, pdy = denormTouch(x, y, dx, dy)
  local vx, vy = Viewport.toVirtual(px, py)
  local scale = Viewport.scale > 0 and Viewport.scale or 1
  States.touchreleased(id, vx, vy, pdx / scale, pdy / scale, pressure)
  States.mousereleased(vx, vy, 1, true, 1)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  Viewport.update()
  local px, py, pdx, pdy = denormTouch(x, y, dx, dy)
  local vx, vy = Viewport.toVirtual(px, py)
  local scale = Viewport.scale > 0 and Viewport.scale or 1
  States.touchmoved(id, vx, vy, pdx / scale, pdy / scale, pressure)
  States.mousemoved(vx, vy, pdx / scale, pdy / scale, true)
end

function love.wheelmoved(x, y)
  States.wheelmoved(x, y)
end

function love.textinput(text)
  States.textinput(text)
end

function love.resize(w, h)
  Viewport.update()
  States.resize(w, h)
end

-- NOTE: returning true from love.quit() ABORTS quitting in LÖVE 11,
-- so flush persistence and return nothing.
function love.quit()
  States.quit()
end
