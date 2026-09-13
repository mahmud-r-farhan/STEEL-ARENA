--=============================================================================
-- Store: buy tanks and camouflages with credits, equip owned tanks.
--=============================================================================

local Kit   = require("ui.kit")
local Tanks = require("data.tanks")
local States = require("core.state")

local gfx = love.graphics
local W, H = gfx.getWidth, gfx.getHeight

local Store = {}

local S = {}

function Store.enter(shared, opts)
  S.shared = shared
  S.tab = 1            -- 1 tanks, 2 camos
  S.selCamoTank = shared.save.data.selected
  S.toastMsg = nil
  S.toastT = 0
end

local function toast(text)
  S.toastMsg = text
  S.toastT = 2.5
end

function Store.update(dt)
  Kit.newFrame()
  S.toastT = math.max(0, S.toastT - dt)
end

-- draw a little tank preview (reuse world renderer primitives inline)
local function tankPreview(x, y, scale, def, camoId)
  local camo = Tanks.camouflageFor(def.id, nil, { [def.id] = camoId })
  gfx.push()
  gfx.translate(x, y)
  gfx.scale(scale, scale)
  -- tracks
  gfx.setColor(camo.track[1], camo.track[2], camo.track[3])
  gfx.rectangle("fill", -def.radius - 2, -def.radius - 3, (def.radius + 2) * 2, 7, 2)
  gfx.rectangle("fill", -def.radius - 2, def.radius - 4, (def.radius + 2) * 2, 7, 2)
  -- hull
  gfx.setColor(camo.body[1], camo.body[2], camo.body[3])
  gfx.rectangle("fill", -def.radius, -def.radius * 0.78, def.radius * 2, def.radius * 1.56, 4)
  -- turret + barrel
  gfx.setColor(camo.body[1] * 0.85, camo.body[2] * 0.85, camo.body[3] * 0.85)
  gfx.rectangle("fill", -5, -5, 10, 10, 3)
  gfx.setColor(camo.accent[1], camo.accent[2], camo.accent[3])
  gfx.rectangle("fill", 4, -2.5, def.radius + 10, 5, 2)
  gfx.pop()
end

function Store.draw()
  local w, h = W(), H()
  gfx.clear(0.06, 0.075, 0.1)
  local save = S.shared.save

  Kit._font(30)
  gfx.setColor(0.92, 0.94, 0.97)
  gfx.printf("STORE", 0, 26, w, "center")
  Kit._font(16)
  gfx.setColor(1, 0.85, 0.35)
  gfx.printf(save.data.credits .. " CR", 0, 66, w, "center")

  if Kit.button("back", "BACK", 30, 34, 110, 34) then
    States.pop()   -- back to wherever we came from
  end

  S.tab = Kit.tabs("storetabs", { "TANKS", "CAMOUFLAGE" }, w / 2 - 220, 34, 440, 34, S.tab)

  local py = 100
  if S.tab == 1 then
    -- tanks grid
    local cw, ch = 420, 110
    local cols = math.floor(w - 60) // (cw + 20)
    local x0 = (w - (cols * (cw + 20) - 20)) / 2
    local i = 0
    for _, def in ipairs(Tanks.all()) do
      local col = i % cols
      local row = i // cols
      local x = x0 + col * (cw + 20)
      local y = py + row * (ch + 16)
      i = i + 1
      local owned = save.owns(def.id)
      local equipped = save.data.selected == def.id

      Kit.panel(x, y, cw, ch, owned and { 0.1, 0.13, 0.17, 0.95 } or { 0.09, 0.1, 0.13, 0.9 })
      tankPreview(x + 70, y + ch / 2, 1.3, def, "none")

      Kit.text(def.name, x + 150, y + 12, 17, { 0.92, 0.94, 0.97 })
      Kit.text(def.class .. "  -  " .. def.desc, x + 150, y + 34, 11, { 0.62, 0.66, 0.72 })
      -- mini stats
      local statY = y + 56
      Kit.text("HP " .. math.floor(def.hp), x + 150, statY, 11, { 0.7, 0.75, 0.8 })
      Kit.text("DMG " .. def.damage, x + 205, statY, 11, { 0.7, 0.75, 0.8 })
      Kit.text("SPD " .. def.speed, x + 260, statY, 11, { 0.7, 0.75, 0.8 })
      Kit.text("RLD " .. string.format("%.2fs", def.reload), x + 320, statY, 11, { 0.7, 0.75, 0.8 })

      if owned then
        if equipped then
          Kit.text("EQUIPPED", x + 150, y + ch - 26, 13, { 0.4, 0.9, 0.5 })
        elseif Kit.button("eq" .. def.id, "EQUIP", x + 150, y + ch - 34, 110, 26, { fontSize = 12,
          color = { 0.2, 0.4, 0.25 } }) then
          save.data.selected = def.id
          save.dirty = true
          toast(def.name .. " equipped")
          if S.shared.client and S.shared.client.status == "connected" then
            S.shared.client:pushLoadout()
          end
        end
      else
        local afford = save.data.credits >= def.price
        if Kit.button("buy" .. def.id, "BUY " .. def.price .. " CR", x + 150, y + ch - 34, 150, 26,
          { fontSize = 12, color = afford and { 0.35, 0.28, 0.12 } or { 0.2, 0.2, 0.2 } }) then
          local ok, err = save.buyTank(def.id)
          if ok then
            toast("Purchased " .. def.name .. "!")
            if S.shared.audio then S.shared.audio.play("purchase") end
          else
            toast(err)
          end
        end
      end
    end
  else
    -- camos
    Kit.text("Camouflage for: " .. (Tanks.get(S.selCamoTank) or { name = "?" }).name,
      40, py, 14, { 0.85, 0.88, 0.92 })
    local bx = 40
    for _, def in ipairs(Tanks.all()) do
      if save.owns(def.id) then
        if Kit.button("ct" .. def.id, def.name, bx, py + 22, 110, 26, { fontSize = 12,
          color = (S.selCamoTank == def.id) and { 0.2, 0.4, 0.5 } or nil }) then
          S.selCamoTank = def.id
        end
        bx = bx + 115
      end
    end

    local cy = py + 64
    local cw, ch = 300, 120
    local cols = math.max(1, math.floor(w - 60) // (cw + 20))
    local x0 = (w - (math.min(cols, #(Tanks.camos and {} or {})) ) ) -- placeholder
    local i = 0
    for camoId, camo in pairs(Tanks.camos) do
      local col = i % cols
      local row = i // cols
      local x = 40 + col * (cw + 20)
      local y = cy + row * (ch + 16)
      i = i + 1
      local owned = save.data.camo[S.selCamoTank] and save.data.camo[S.selCamoTank][camoId] or (camo.price == 0)
      local equipped = save.data.camo_sel[S.selCamoTank] == camoId
      Kit.panel(x, y, cw, ch)
      tankPreview(x + 60, y + ch / 2, 1.1, Tanks.get(S.selCamoTank) or Tanks.get("scout"), camoId)
      Kit.text(camo.name, x + 140, y + 14, 16, { 0.92, 0.94, 0.97 })
      local priceTxt = camo.price == 0 and "FREE" or (owned and "OWNED" or (camo.price .. " CR"))
      Kit.text(priceTxt, x + 140, y + 38, 13, { 1, 0.85, 0.35 })
      if equipped then
        Kit.text("EQUIPPED", x + 140, y + ch - 30, 13, { 0.4, 0.9, 0.5 })
      elseif owned then
        if Kit.button("ceq" .. camoId, "EQUIP", x + 140, y + ch - 36, 100, 26, { fontSize = 12,
          color = { 0.2, 0.4, 0.25 } }) then
          save.data.camo_sel[S.selCamoTank] = camoId
          save.dirty = true
          toast(camo.name .. " camo equipped")
          if S.shared.client and S.shared.client.status == "connected" then
            S.shared.client:pushLoadout()
          end
        end
      else
        if Kit.button("cbuy" .. camoId, "BUY", x + 140, y + ch - 36, 100, 26, { fontSize = 12,
          color = save.data.credits >= camo.price and { 0.35, 0.28, 0.12 } or { 0.2, 0.2, 0.2 } }) then
          if save.spendCredits(camo.price) then
            save.data.camo[S.selCamoTank] = save.data.camo[S.selCamoTank] or {}
            save.data.camo[S.selCamoTank][camoId] = true
            save.dirty = true
            toast(camo.name .. " camo purchased!")
            if S.shared.audio then S.shared.audio.play("purchase") end
          else
            toast("Not enough credits")
          end
        end
      end
    end
  end

  if S.toastT > 0 and S.toastMsg then
    Kit.text(S.toastMsg, 30, h - 30, 14, { 1, 0.9, 0.5 })
  end
end

function Store.mousepressed(x, y, b) Kit.mousepressed(x, y, b) end
function Store.mousereleased(x, y, b) Kit.mousereleased(x, y, b) end
function Store.mousemoved(x, y) Kit.mousemoved(x, y) end

function Store.keypressed(key)
  if key == "escape" then States.pop() end
end

return Store
