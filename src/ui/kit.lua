--=============================================================================
-- Immediate-mode UI kit. Draw + hit-test in one pass per frame.
-- All functions take absolute screen coords; states handle layout.
-- Falls back to a stub when love.graphics is unavailable (headless tests).
--=============================================================================

local gfx = (love and love.graphics) or nil
if not gfx then
  -- minimal stub so module loading and layout math still work headless
  gfx = setmetatable({}, { __index = function() return function() end end })
end
gfx = gfx

local Kit = {
  mouse = { x = 0, y = 0, down = false, pressed = false, released = false, wheel = 0 },
  hot = nil,
  active = nil,
  textCapture = nil,
}

local _fonts = {}
function Kit._font(size)
  if gfx.newFont then
    if not _fonts[size] then _fonts[size] = gfx.newFont(size) end
    gfx.setFont(_fonts[size])
    return _fonts[size]
  end
  -- headless stub
  return { getWidth = function(_, s) return #(tostring(s)) * 8 end }
end

local function inRect(px, py, x, y, w, h)
  return px >= x and px <= x + w and py >= y and py <= y + h
end

function Kit.newFrame()
  Kit.mouse.pressed = false
  Kit.mouse.released = false
  Kit.mouse.wheel = 0
end

function Kit.mousepressed(x, y, button)
  if button == 1 then
    Kit.mouse.down = true
    Kit.mouse.pressed = true
    Kit.mouse.x, Kit.mouse.y = x, y
  end
end

function Kit.mousereleased(x, y, button)
  if button == 1 then
    Kit.mouse.down = false
    Kit.mouse.released = true
    Kit.mouse.x, Kit.mouse.y = x, y
  end
end

function Kit.mousemoved(x, y)
  Kit.mouse.x, Kit.mouse.y = x, y
end

function Kit.wheelmoved(x, y)
  Kit.mouse.wheel = y * 40
end

--=============================================================================
-- Primitives
--=============================================================================

function Kit.panel(x, y, w, h, color)
  gfx.setColor(color or { 0.09, 0.11, 0.14, 0.92 })
  gfx.rectangle("fill", x, y, w, h, 10)
  gfx.setColor(1, 1, 1, 0.07)
  gfx.setLineWidth(1)
  gfx.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 10)
end

function Kit.text(text, x, y, size, color, align, alignW)
  if size then Kit._font(size) end
  gfx.setColor(color or { 0.9, 0.92, 0.95 })
  local w = alignW or 0
  if align == "center" then
    gfx.printf(text, x, y, w, "center")
  elseif align == "right" then
    gfx.printf(text, x, y, w, "right")
  else
    gfx.print(text, x, y)
  end
end

function Kit.textWidth(text, size)
  local f = Kit._font(size or 14)
  return f:getWidth(text)
end

--=============================================================================
-- Widgets (return truthy when activated)
--=============================================================================

function Kit.button(id, label, x, y, w, h, opts)
  opts = opts or {}
  local mx, my = Kit.mouse.x, Kit.mouse.y
  local hov = inRect(mx, my, x, y, w, h)
  local down = hov and Kit.mouse.down
  local clicked = hov and Kit.mouse.released

  local base = opts.color or { 0.16, 0.2, 0.26 }
  local alpha = opts.color and opts.color[4] or 1
  local r, g, b = base[1], base[2], base[3]
  if down then
    r, g, b = r * 0.75, g * 0.75, b * 0.75
  elseif hov then
    r, g, b = math.min(1, r * 1.35), math.min(1, g * 1.35), math.min(1, b * 1.35)
  end
  gfx.setColor(r, g, b, alpha)
  gfx.rectangle("fill", x, y, w, h, opts.radius or 6)
  gfx.setColor(1, 1, 1, hov and 0.18 or 0.08)
  gfx.setLineWidth(1)
  gfx.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, opts.radius or 6)

  local size = opts.fontSize or 15
  Kit._font(size)
  gfx.setColor(opts.textColor or { 0.93, 0.95, 0.97 })
  gfx.printf(label, x + 4, y + h / 2 - size * 0.72, w - 8, "center")
  return clicked
end

function Kit.toggle(id, label, x, y, w, h, value)
  local mx, my = Kit.mouse.x, Kit.mouse.y
  local boxH = math.min(22, h)
  local boxW = 44
  local hit = inRect(mx, my, x, y, w, h)
  if hit and Kit.mouse.released then value = not value end
  gfx.setColor(value and { 0.25, 0.55, 0.3 } or { 0.3, 0.32, 0.36 })
  gfx.rectangle("fill", x, y + (h - boxH) / 2, boxW, boxH, 11)
  local kx = value and (x + boxW - boxH + 3) or (x + 3)
  gfx.setColor(0.95, 0.95, 0.95)
  gfx.circle("fill", kx + boxH / 2 - 3, y + h / 2, boxH / 2 - 3)
  if label then
    Kit.text(label, x + boxW + 10, y + h / 2 - 8, 14)
  end
  return value, (hit and Kit.mouse.released)
end

function Kit.slider(id, x, y, w, value, lo, hi)
  lo, hi = lo or 0, hi or 1
  local mx, my = Kit.mouse.x, Kit.mouse.y
  local h = 20
  local hit = inRect(mx, my, x - 6, y - 8, w + 12, h + 8)
  if hit and Kit.mouse.down then Kit.active = id end
  if Kit.active == id then
    local k = math.min(1, math.max(0, (mx - x) / w))
    value = lo + (hi - lo) * k
    if not Kit.mouse.down then Kit.active = nil end
  end
  gfx.setColor(0.25, 0.28, 0.33)
  gfx.rectangle("fill", x, y + h / 2 - 3, w, 6, 3)
  local k = (value - lo) / (hi - lo)
  gfx.setColor(0.4, 0.7, 0.95)
  gfx.rectangle("fill", x, y + h / 2 - 3, w * k, 6, 3)
  gfx.setColor(0.95, 0.95, 0.95)
  gfx.circle("fill", x + w * k, y + h / 2, 8)
  return value
end

function Kit.textInput(id, x, y, w, h, value, placeholder, opts)
  opts = opts or {}
  local mx, my = Kit.mouse.x, Kit.mouse.y
  local hov = inRect(mx, my, x, y, w, h)
  if hov and Kit.mouse.pressed then Kit.textCapture = id end
  local active = (Kit.textCapture == id)

  gfx.setColor(active and { 0.13, 0.17, 0.22 } or { 0.1, 0.12, 0.16 })
  gfx.rectangle("fill", x, y, w, h, 6)
  gfx.setColor(active and { 0.4, 0.7, 0.95 } or { 1, 1, 1, 0.12 })
  gfx.setLineWidth(active and 2 or 1)
  gfx.rectangle("line", x + 1, y + 1, w - 2, h - 2, 6)

  local shown = value
  if opts.masked and value and #value > 0 then
    shown = string.rep("*", #value)
  end
  if (not shown or #shown == 0) and placeholder then
    Kit.text(placeholder, x + 10, y + h / 2 - 8, 14, { 0.5, 0.53, 0.58 })
  else
    Kit.text(shown or "", x + 10, y + h / 2 - 8, 14)
  end
  if active and math.floor(love.timer.getTime() * 2) % 2 == 0 then
    local tw = Kit.textWidth(shown or "", 14)
    gfx.setColor(1, 1, 1, 0.8)
    gfx.rectangle("fill", x + 12 + tw, y + 6, 1.5, h - 12)
  end
  return value
end

function Kit.listRow(id, x, y, w, h)
  local mx, my = Kit.mouse.x, Kit.mouse.y
  local hov = inRect(mx, my, x, y, w, h)
  if hov then
    gfx.setColor(1, 1, 1, 0.05)
    gfx.rectangle("fill", x, y, w, h, 6)
  end
  return hov and Kit.mouse.released
end

function Kit.scrollArea(id, x, y, w, h, contentH, wheelDelta, currentOffset)
  local offset = currentOffset or 0
  local maxOff = math.max(0, contentH - h)
  local mx, my = Kit.mouse.x, Kit.mouse.y
  local hov = inRect(mx, my, x, y, w, h)
  local delta = wheelDelta or Kit.mouse.wheel or 0
  if hov and delta ~= 0 then
    offset = math.max(0, math.min(maxOff, offset - delta))
  end
  if maxOff > 0 then
    local barH = math.max(24, h * (h / contentH))
    local barY = y + (h - barH) * (offset / maxOff)
    gfx.setColor(1, 1, 1, 0.12)
    gfx.rectangle("fill", x + w - 4, barY, 3, barH, 2)
  end
  gfx.setScissor(x, y, w, h)
  return offset
end

function Kit.endScroll()
  gfx.setScissor()
end

function Kit.beginClip(x, y, w, h)
  gfx.setScissor(x, y, w, h)
end

function Kit.endClip()
  gfx.setScissor()
end

function Kit.tabs(id, labels, x, y, w, h, selected)
  local n = #labels
  local bw = w / n
  local mx, my = Kit.mouse.x, Kit.mouse.y
  for i, label in ipairs(labels) do
    local bx = x + (i - 1) * bw
    local hov = inRect(mx, my, bx, y, bw, h)
    local isSel = (selected == i)
    if hov and Kit.mouse.released then selected = i end
    gfx.setColor(isSel and { 0.22, 0.32, 0.42 } or { 0.12, 0.15, 0.19 })
    gfx.rectangle("fill", bx + 2, y, bw - 4, h, 6)
    gfx.setColor(isSel and { 0.55, 0.8, 1 } or { 0.65, 0.68, 0.72 })
    Kit._font(14)
    gfx.printf(label, bx + 2, y + h / 2 - 9, bw - 4, "center")
  end
  return selected
end

function Kit.bar(x, y, w, h, frac, color)
  frac = math.max(0, math.min(1, frac or 0))
  gfx.setColor(0.08, 0.09, 0.11)
  gfx.rectangle("fill", x, y, w, h, 4)
  gfx.setColor(color or { 0.4, 0.8, 0.4 })
  if frac > 0 then
    gfx.rectangle("fill", x + 1, y + 1, (w - 2) * frac, h - 2, 3)
  end
end

return Kit
