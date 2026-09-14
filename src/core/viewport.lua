--=============================================================================
-- Viewport: manages virtual resolution (1280x720) scaling, letterboxing,
-- and coordinate translations for any display, window size, or mobile aspect ratio.
--=============================================================================

local Viewport = {
  w = 1280,
  h = 720,
  scale = 1,
  ox = 0,
  oy = 0,
  touchActive = false,
}

function Viewport.update()
  if not love or not love.graphics or not love.graphics.getWidth then return end
  local winW = love.graphics.getWidth()
  local winH = love.graphics.getHeight()
  if winW <= 0 or winH <= 0 then return end

  local scale = math.min(winW / Viewport.w, winH / Viewport.h)
  if scale <= 0 then scale = 1 end
  Viewport.scale = scale
  Viewport.ox = math.floor((winW - Viewport.w * scale) / 2)
  Viewport.oy = math.floor((winH - Viewport.h * scale) / 2)
end

function Viewport.toVirtual(x, y)
  if not x or not y then return 0, 0 end
  local scale = Viewport.scale > 0 and Viewport.scale or 1
  local vx = (x - Viewport.ox) / scale
  local vy = (y - Viewport.oy) / scale
  return vx, vy
end

function Viewport.toScreen(vx, vy)
  if not vx or not vy then return 0, 0 end
  local scale = Viewport.scale > 0 and Viewport.scale or 1
  return Viewport.ox + vx * scale, Viewport.oy + vy * scale
end

function Viewport.apply()
  if not love or not love.graphics then return end
  Viewport.update()
  local gfx = love.graphics

  -- Clear letterbox padding with deep sleek dark color
  gfx.clear(0.04, 0.05, 0.07)

  gfx.push()
  gfx.translate(Viewport.ox, Viewport.oy)
  gfx.scale(Viewport.scale, Viewport.scale)
  local sw = math.floor(Viewport.w * Viewport.scale)
  local sh = math.floor(Viewport.h * Viewport.scale)
  if sw > 0 and sh > 0 then
    gfx.setScissor(Viewport.ox, Viewport.oy, sw, sh)
  end
end

function Viewport.pop()
  if not love or not love.graphics then return end
  love.graphics.setScissor()
  love.graphics.pop()
end

function Viewport.isMobile()
  if love and love.system and love.system.getOS then
    local os = love.system.getOS()
    if os == "Android" or os == "iOS" then return true end
  end
  return Viewport.touchActive
end

return Viewport
