--=============================================================================
-- State machine: manages game screens (menu, lobby, garage, battle, ...).
-- Each state is a module in states/ exposing load/enter/leave/update/draw
-- and optional input handlers.
--=============================================================================

local States = {
  stack   = {},          -- stack of { name = ..., module = ... }
  shared  = {},          -- injected services (save, settings, audio)
  states  = {},
}

function States.init(services)
  States.shared = services or {}
end

-- Register a state module (called via require at boot or lazily).
function States.register(name, module)
  States.states[name] = module
end

-- Lazy-require a state by name; module path mirrors state name.
local function resolve(name)
  if States.states[name] then return States.states[name] end
  local ok, mod = pcall(require, "states." .. name:gsub("%.", "."))
  if not ok or type(mod) ~= "table" then
    error("unknown state: " .. tostring(name) .. " (" .. tostring(mod) .. ")")
  end
  States.states[name] = mod
  return mod
end

local function call(mod, fname, ...)
  if mod and type(mod[fname]) == "function" then
    return mod[fname](...)
  end
end

function States.current()
  return States.stack[#States.stack]
end

function States.switch(name, ...)
  while #States.stack > 0 do
    local top = table.remove(States.stack)
    call(top.module, "leave")
  end
  local mod = resolve(name)
  local entry = { name = name, module = mod }
  table.insert(States.stack, entry)
  call(mod, "enter", States.shared, ...)
end

function States.push(name, ...)
  local mod = resolve(name)
  call(States.current().module, "pause")
  local entry = { name = name, module = mod }
  table.insert(States.stack, entry)
  call(mod, "enter", States.shared, ...)
end

function States.pop(...)
  if #States.stack <= 1 then
    States.switch("menu.main")
    return
  end
  local top = table.remove(States.stack)
  call(top.module, "leave")
  call(States.current().module, "resume", ...)
end

function States.update(dt)
  local top = States.current()
  if top then call(top.module, "update", dt) end
end

function States.draw()
  local top = States.current()
  if top then call(top.module, "draw") end
end

-- Overlay support: if top state wants draw only its own content over the
-- one below (pause menus), draw the state beneath first.
function States.drawWithOverlays()
  for i = 1, #States.stack do
    local entry = States.stack[i]
    local overlayOnly = entry.module.draw_overlay_only
    if not overlayOnly or i == #States.stack then
      if not (overlayOnly and i < #States.stack) then
        call(entry.module, "draw")
      elseif overlayOnly and i == #States.stack - 0 then
        call(entry.module, "draw")
      end
    end
  end
end

function States.keypressed(key, scancode, isrepeat)
  local top = States.current()
  if top then call(top.module, "keypressed", key, scancode, isrepeat) end
end

function States.keyreleased(key, scancode)
  local top = States.current()
  if top then call(top.module, "keyreleased", key, scancode) end
end

function States.mousepressed(x, y, button, istouch, presses)
  local top = States.current()
  if top then call(top.module, "mousepressed", x, y, button, istouch, presses) end
end

function States.mousereleased(x, y, button, istouch, presses)
  local top = States.current()
  if top then call(top.module, "mousereleased", x, y, button, istouch, presses) end
end

function States.mousemoved(x, y, dx, dy, istouch)
  local top = States.current()
  if top then call(top.module, "mousemoved", x, y, dx, dy, istouch) end
end

function States.wheelmoved(x, y)
  local top = States.current()
  if top then call(top.module, "wheelmoved", x, y) end
end

function States.textinput(text)
  local top = States.current()
  if top then call(top.module, "textinput", text) end
end

function States.touchpressed(id, x, y, dx, dy, pressure)
  local top = States.current()
  if top then call(top.module, "touchpressed", id, x, y, dx, dy, pressure) end
end

function States.touchreleased(id, x, y, dx, dy, pressure)
  local top = States.current()
  if top then call(top.module, "touchreleased", id, x, y, dx, dy, pressure) end
end

function States.touchmoved(id, x, y, dx, dy, pressure)
  local top = States.current()
  if top then call(top.module, "touchmoved", id, x, y, dx, dy, pressure) end
end

function States.resize(w, h)
  for _, entry in ipairs(States.stack) do
    call(entry.module, "resize", w, h)
  end
end

function States.quit()
  for i = #States.stack, 1, -1 do
    call(States.stack[i].module, "leave")
  end
  -- flush persistence
  if States.shared and States.shared.save then
    States.shared.save.save()
  end
  if States.shared and States.shared.settings then
    States.shared.settings.save()
  end
end

return States
