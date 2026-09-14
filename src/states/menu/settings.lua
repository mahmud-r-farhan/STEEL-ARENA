--=============================================================================
-- Settings: audio volumes, gameplay toggles, callsign. Saved instantly.
--=============================================================================

local Kit   = require("ui.kit")
local States = require("core.state")

local gfx = (love and love.graphics) or nil
if not gfx then
  gfx = setmetatable({}, { __index = function() return function() end end })
end
local W, H = function() return 1280, 720 end, function() return 1280, 720 end

local SettingsState = {}

local S = {}

function SettingsState.enter(shared, opts)
  S.shared = shared
  S.opts = opts or {}
  S.nameBuf = shared.save.data.name or ""
end

function SettingsState.update(dt)
  Kit.newFrame()
end

function SettingsState.draw()
  local w, h = W(), H()
  gfx.clear(0.06, 0.075, 0.1)
  local st = S.shared.settings.data
  local save = S.shared.save

  Kit._font(30)
  gfx.setColor(0.92, 0.94, 0.97)
  gfx.printf("SETTINGS", 0, 26, w, "center")

  local px, py = w / 2 - 240, 90
  local pw, ph = 480, 450
  Kit.panel(px, py, pw, ph)

  Kit.text("AUDIO", px + 20, py + 16, 13, { 0.6, 0.64, 0.7 })
  Kit.text("MASTER", px + 20, py + 48, 14)
  local m = Kit.slider("volM", px + 110, py + 44, 250, st.volume.master, 0, 1)
  if math.abs(m - st.volume.master) > 0.001 then
    st.volume.master = m
    S.shared.audio.applyVolumes()
    S.shared.settings.save()
  end
  Kit.text(string.format("%d%%", math.floor(st.volume.master * 100 + 0.5)), px + 380, py + 46, 13)

  Kit.text("EFFECTS", px + 20, py + 78, 14)
  local sfx = Kit.slider("volS", px + 110, py + 74, 250, st.volume.sfx, 0, 1)
  if math.abs(sfx - st.volume.sfx) > 0.001 then
    st.volume.sfx = sfx
    S.shared.audio.applyVolumes()
    S.shared.settings.save()
  end
  Kit.text(string.format("%d%%", math.floor(st.volume.sfx * 100 + 0.5)), px + 380, py + 76, 13)

  Kit.text("MUSIC", px + 20, py + 108, 14)
  local mus = Kit.slider("volMu", px + 110, py + 104, 250, st.volume.music, 0, 1)
  if math.abs(mus - st.volume.music) > 0.001 then
    st.volume.music = mus
    S.shared.settings.save()
  end

  Kit.text("GAMEPLAY", px + 20, py + 148, 13, { 0.6, 0.64, 0.7 })
  local sfps = st.show_fps
  local nfps = Kit.toggle("fps", "Show FPS counter", px + 20, py + 172, 260, 26, sfps)
  if nfps ~= sfps then
    st.show_fps = nfps
    S.shared.settings.save()
  end

  local sshake = st.screen_shake
  local nshake = Kit.toggle("shake", "Screen shake", px + 20, py + 204, 260, 24, sshake)
  if nshake ~= sshake then
    st.screen_shake = nshake
    S.shared.settings.save()
  end

  local stouch = st.touch_controls == true
  local ntouch = Kit.toggle("touch", "Touch dual-stick controls", px + 20, py + 234, 260, 24, stouch)
  if ntouch ~= stouch then
    st.touch_controls = ntouch
    S.shared.settings.save()
  end

  Kit.text("PROFILE", px + 20, py + 270, 13, { 0.6, 0.64, 0.7 })
  Kit.text("CALLSIGN", px + 20, py + 296, 14)
  S.nameBuf = Kit.textInput("sname", px + 110, py + 292, 220, 28, S.nameBuf, "name")

  -- stats
  Kit.text("BATTLES " .. save.data.stats.battles ..
    "   WINS " .. save.data.stats.wins ..
    "   KILLS " .. save.data.stats.kills ..
    "   DEATHS " .. save.data.stats.deaths,
    px + 20, py + 334, 13, { 0.7, 0.74, 0.8 })

  Kit.text("Level " .. save.data.level .. "  (" .. save.data.xp .. "/" .. (save.data.level * 100) .. " XP)",
    px + 20, py + 356, 13, { 1, 0.85, 0.35 })

  if Kit.button("sdone", "DONE", px + pw - 130, py + ph - 48, 110, 34) then
    close()
  end
  if Kit.button("swipe", "WIPE SAVE", px + 20, py + ph - 48, 130, 34, { color = { 0.4, 0.15, 0.15 } }) then
    -- reset account
    local lfs = love.filesystem
    if lfs then lfs.remove("account.lua") end
    love.event.quit("restart")
  end
end

function close()
  -- persist callsign
  local name = (S.nameBuf or ""):match("^%s*(.-)%s*$")
  if #name >= 2 then
    S.shared.save.data.name = name
    S.shared.save.dirty = true
  end
  S.shared.settings.save()
  if S.opts.fromPause then
    States.pop()
  else
    States.pop()
  end
end

function SettingsState.mousepressed(x, y, b) Kit.mousepressed(x, y, b) end
function SettingsState.mousereleased(x, y, b) Kit.mousereleased(x, y, b) end
function SettingsState.mousemoved(x, y) Kit.mousemoved(x, y) end

function SettingsState.keypressed(key)
  if key == "escape" then close() end
  if key == "backspace" and Kit.textCapture == "sname" then
    S.nameBuf = S.nameBuf:sub(1, -2)
  end
end

function SettingsState.textinput(text)
  if Kit.textCapture == "sname" and #S.nameBuf < 16 then
    S.nameBuf = S.nameBuf .. text
  end
end

return SettingsState
