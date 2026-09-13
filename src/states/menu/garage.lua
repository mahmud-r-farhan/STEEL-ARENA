--=============================================================================
-- Garage: inspect stats, buy upgrades (3 levels per part), switch tanks,
-- quick-equip camos. Shows current vs preview stat bars.
--=============================================================================

local Kit   = require("ui.kit")
local Tanks = require("data.tanks")
local States = require("core.state")

local gfx = love.graphics
local W, H = gfx.getWidth, gfx.getHeight

local Garage = {}

local S = {}

function Garage.enter(shared, opts)
  S.shared = shared
  S.tankId = (opts and opts.tankId) or shared.save.data.selected
  if not shared.save.owns(S.tankId) then S.tankId = "scout" end
  S.toastMsg = nil
  S.toastT = 0
end

local function toast(text)
  S.toastMsg = text
  S.toastT = 2.5
end

function Garage.update(dt)
  Kit.newFrame()
  S.toastT = math.max(0, S.toastT - dt)
end

local function statBar(x, y, w, label, frac, color, valText)
  Kit.text(label, x, y - 2, 12, { 0.6, 0.64, 0.7 })
  Kit.bar(x + 90, y, w - 90, 12, frac, color)
  Kit.text(valText, x + 94, y + 1, 10, { 0, 0, 0, 0.85 })
end

local function tankPreviewBig(x, y, scale, tankId, camoId)
  local def = Tanks.get(tankId)
  if not def then return end
  local camo = Tanks.camouflageFor(tankId, nil, { [tankId] = camoId })
  gfx.push()
  gfx.translate(x, y)
  gfx.scale(scale, scale)
  gfx.setColor(camo.track[1], camo.track[2], camo.track[3])
  gfx.rectangle("fill", -def.radius - 2, -def.radius - 3, (def.radius + 2) * 2, 7, 2)
  gfx.rectangle("fill", -def.radius - 2, def.radius - 4, (def.radius + 2) * 2, 7, 2)
  gfx.setColor(camo.body[1], camo.body[2], camo.body[3])
  gfx.rectangle("fill", -def.radius, -def.radius * 0.78, def.radius * 2, def.radius * 1.56, 4)
  gfx.setColor(camo.body[1] * 0.85, camo.body[2] * 0.85, camo.body[3] * 0.85)
  gfx.rectangle("fill", -5, -5, 10, 10, 3)
  gfx.setColor(camo.accent[1], camo.accent[2], camo.accent[3])
  gfx.rectangle("fill", 4, -2.5, def.radius + 10, 5, 2)
  gfx.pop()
end

function Garage.draw()
  local w, h = W(), H()
  gfx.clear(0.06, 0.075, 0.1)
  local save = S.shared.save
  local def = Tanks.get(S.tankId)

  Kit._font(30)
  gfx.setColor(0.92, 0.94, 0.97)
  gfx.printf("GARAGE", 0, 26, w, "center")
  Kit._font(16)
  gfx.setColor(1, 0.85, 0.35)
  gfx.printf(save.data.credits .. " CR", 0, 66, w, "center")

  if Kit.button("back", "BACK", 30, 34, 110, 34) then
    States.pop()
  end

  -- left: tank carousel (owned tanks)
  local lx, ly = 30, 110
  Kit.panel(lx, ly, 260, h - 150)
  Kit.text("YOUR TANKS", lx + 14, ly + 12, 13, { 0.6, 0.64, 0.7 })
  local ty = ly + 38
  for _, d in ipairs(Tanks.all()) do
    if save.owns(d.id) then
      local selected = S.tankId == d.id
      if Kit.listRow("tank" .. d.id, lx + 8, ty, 244, 44) or selected then
        -- highlight
      end
      if selected then
        gfx.setColor(0.2, 0.4, 0.5, 0.55)
        gfx.rectangle("fill", lx + 8, ty, 244, 44, 6)
      end
      Kit.text(d.name, lx + 18, ty + 5, 15, selected and { 0.6, 0.9, 1 } or { 0.88, 0.9, 0.93 })
      Kit.text(d.class, lx + 18, ty + 24, 12, { 0.6, 0.64, 0.7 })
      if save.data.selected == d.id then
        Kit.text("E", lx + 232, ty + 5, 12, { 0.4, 0.9, 0.5 })
      end
      ty = ty + 48
    end
  end

  -- center: preview + stats
  local cx = 320
  local cw = 400
  Kit.panel(cx, ly, cw, h - 150)
  local camoId = save.data.camo_sel[S.tankId] or "none"
  tankPreviewBig(cx + cw / 2, ly + 110, 2.4, S.tankId, camoId)
  Kit.text(def.name .. "  -  " .. def.class, cx + 20, ly + 200, 20, { 0.92, 0.94, 0.97 })
  Kit.text(def.desc, cx + 20, ly + 226, 12, { 0.62, 0.66, 0.72 })

  local stats = Tanks.statsFor(S.tankId, save.data.upgrades)
  local maxRef = { hp = 260, speed = 260, damage = 75, reload = 2.6, turret = 4.5 }
  local upgLevels = {}
  for i, part in ipairs(Tanks.parts) do
    upgLevels[i] = save.upgradeLevel(S.tankId, part.id)
  end

  -- stat bars: current
  local sy = ly + 260
  Kit.text("CURRENT STATS", cx + 20, sy - 18, 12, { 0.6, 0.64, 0.7 })
  statBar(cx + 20, sy, cw - 40, "HULL HP", stats.hp / maxRef.hp, { 0.35, 0.75, 0.4 }, tostring(math.floor(stats.hp)))
  statBar(cx + 20, sy + 22, cw - 40, "SPEED", stats.speed / maxRef.speed, { 0.4, 0.65, 0.9 }, tostring(math.floor(stats.speed)))
  statBar(cx + 20, sy + 44, cw - 40, "DAMAGE", stats.damage / maxRef.damage, { 0.9, 0.5, 0.3 }, tostring(math.floor(stats.damage)))
  statBar(cx + 20, sy + 66, cw - 40, "DPS ~", stats.damage / stats.reload / 60, { 0.8, 0.6, 0.3 },
    string.format("%.0f", stats.damage / stats.reload))
  statBar(cx + 20, sy + 88, cw - 40, "TURRET", stats.turret / maxRef.turret, { 0.6, 0.5, 0.9 },
    string.format("%.1f r/s", stats.turret))

  -- equip
  if save.data.selected ~= S.tankId then
    if Kit.button("equip", "EQUIP THIS TANK", cx + 20, ly + 380, 200, 34, { color = { 0.2, 0.4, 0.25 } }) then
      save.data.selected = S.tankId
      save.dirty = true
      if S.shared.client and S.shared.client.status == "connected" then
        S.shared.client:pushLoadout()
      end
    end
  else
    Kit.text("EQUIPPED", cx + 20, ly + 390, 14, { 0.4, 0.9, 0.5 })
  end

  -- right: upgrades
  local rx = 740
  local rw = w - rx - 30
  Kit.panel(rx, ly, rw, h - 150)
  Kit.text("UPGRADES", rx + 16, ly + 12, 13, { 0.6, 0.64, 0.7 })
  local uy = ly + 40
  for i, part in ipairs(Tanks.parts) do
    local lvl = save.upgradeLevel(S.tankId, part.id)
    local maxed = lvl >= Tanks.maxUpgradeLevel
    local price = Tanks.upgradePrice(S.tankId, part.id, lvl)

    Kit.panel(rx + 10, uy, rw - 20, 62, { 0.11, 0.13, 0.17, 0.9 })
    Kit.text(part.name, rx + 22, uy + 8, 14, { 0.9, 0.92, 0.95 })
    Kit.text(part.desc, rx + 22, uy + 28, 11, { 0.6, 0.64, 0.7 })
    -- pips
    for p = 1, Tanks.maxUpgradeLevel do
      gfx.setColor(p <= lvl and { 0.4, 0.8, 0.95 } or { 0.22, 0.25, 0.3 })
      gfx.rectangle("fill", rx + 22 + (p - 1) * 18, uy + 44, 14, 8, 2)
    end
    if maxed then
      Kit.text("MAX", rx + rw - 90, uy + 22, 13, { 0.4, 0.9, 0.5 })
    else
      local afford = save.data.credits >= price
      if Kit.button("up" .. part.id, price .. " CR", rx + rw - 118, uy + 16, 96, 28, { fontSize = 12,
        color = afford and { 0.35, 0.28, 0.12 } or { 0.2, 0.2, 0.2 } }) then
        local ok, err = save.buyUpgrade(S.tankId, part.id, price)
        if ok then
          toast(part.name .. " upgraded to level " .. (lvl + 1))
          if S.shared.audio then S.shared.audio.play("purchase") end
          if S.shared.client and S.shared.client.status == "connected" then
            S.shared.client:pushLoadout()
          end
        else
          toast(err)
        end
      end
    end
    uy = uy + 70
  end

  -- camo quick select
  Kit.text("CAMOUFLAGE", rx + 16, uy + 8, 13, { 0.6, 0.64, 0.7 })
  local cxx = rx + 16
  uy = uy + 28
  for camoId2, camo in pairs(Tanks.camos) do
    local owned = (camo.price == 0) or (save.data.camo[S.tankId] and save.data.camo[S.tankId][camoId2])
    local equipped = (save.data.camo_sel[S.tankId] or "none") == camoId2
    if Kit.button("gcamo" .. camoId2, camo.name .. (equipped and " *" or ""), cxx, uy, 120, 26,
      { fontSize = 11, color = owned and (equipped and { 0.2, 0.4, 0.5 } or { 0.15, 0.22, 0.28 }) or { 0.14, 0.14, 0.16 } }) then
      if owned then
        save.data.camo_sel[S.tankId] = camoId2
        save.dirty = true
        if S.shared.client and S.shared.client.status == "connected" then
          S.shared.client:pushLoadout()
        end
      else
        toast("Buy this camo in the Store first")
      end
    end
    cxx = cxx + 125
    if cxx > rx + rw - 130 then
      cxx = rx + 16
      uy = uy + 30
    end
  end

  if S.toastT > 0 and S.toastMsg then
    Kit.text(S.toastMsg, 30, h - 30, 14, { 1, 0.9, 0.5 })
  end
end

function Garage.mousepressed(x, y, b) Kit.mousepressed(x, y, b) end
function Garage.mousereleased(x, y, b) Kit.mousereleased(x, y, b) end
function Garage.mousemoved(x, y) Kit.mousemoved(x, y) end

function Garage.keypressed(key)
  if key == "escape" then States.pop() end
end

return Garage
