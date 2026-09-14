--=============================================================================
-- Save system: player account (currency, owned tanks, upgrades) persisted to
-- love's save dir. Serialized as plain Lua (write/read) - no external deps.
--=============================================================================

local lfs = love and love.filesystem or nil

local Save = {
  data = {
    version   = 1,
    credits   = 1500,          -- starting currency
    xp        = 0,
    level     = 1,
    name      = nil,
    owned     = { scout = true },   -- first tank granted
    upgrades  = {},                    -- ["scout.reload"] = 2
    selected  = "scout",
    camo      = {},                    -- tank id -> camo id owned
    camo_sel  = {},                    -- tank id -> camo equipped
    stats     = { battles = 0, wins = 0, kills = 0, deaths = 0 },
  },
  dirty = false,
}

local function ser(v, indent)
  local t = type(v)
  if t == "number" or t == "boolean" then
    return tostring(v)
  elseif t == "string" then
    return string.format("%q", v)
  elseif t == "table" then
    local parts = {}
    local n = 0
    for k, val in pairs(v) do
      n = n + 1
      local key = type(k) == "string" and string.format("[%q]", k) or ("[" .. tostring(k) .. "]")
      parts[n] = indent .. "\t" .. key .. " = " .. ser(val, indent .. "\t")
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  return "nil"
end

function Save.path()
  return "account.lua"
end

function Save.load()
  if not lfs then return Save.data end
  if not lfs.getInfo(Save.path()) then return Save.data end
  local chunk, err = lfs.load(Save.path())
  if not chunk then
    print("[save] load failed: " .. tostring(err))
    return Save.data
  end
  local ok, result = pcall(chunk)
  if ok and type(result) == "table" then
    -- shallow-merge to survive schema additions
    for k, v in pairs(result) do
      if type(v) == "table" and type(Save.data[k]) == "table" then
        for kk, vv in pairs(v) do Save.data[k][kk] = vv end
      else
        Save.data[k] = v
      end
    end
  else
    print("[save] corrupt save, starting fresh")
  end
  return Save.data
end

function Save.save()
  if not lfs then return false end
  local body = "return " .. ser(Save.data, "")
  local ok, err = pcall(lfs.write, Save.path(), body)
  if not ok then print("[save] write failed: " .. tostring(err)) end
  Save.dirty = false
  return ok
end

function Save.autosave()
  if Save.dirty then Save.save() end
end

function Save.grantCredits(n)
  Save.data.credits = Save.data.credits + n
  Save.dirty = true
end

function Save.spendCredits(n)
  if Save.data.credits < n then return false end
  Save.data.credits = Save.data.credits - n
  Save.dirty = true
  return true
end

function Save.addXp(n)
  Save.data.xp = Save.data.xp + n
  -- 100 XP per level, growing slightly
  while Save.data.xp >= Save.data.level * 100 do
    Save.data.xp = Save.data.xp - Save.data.level * 100
    Save.data.level = Save.data.level + 1
  end
  Save.dirty = true
end

function Save.owns(tankId)
  return Save.data.owned[tankId] == true
end

function Save.buyTank(tankId, price)
  if Save.owns(tankId) then return true, "already owned" end
  if not Save.spendCredits(price) then return false, "not enough credits" end
  Save.data.owned[tankId] = true
  Save.dirty = true
  return true
end

function Save.upgradeLevel(tankId, partId)
  local k = tankId .. "." .. partId
  return Save.data.upgrades[k] or 0
end

function Save.buyUpgrade(tankId, partId, price)
  local k = tankId .. "." .. partId
  if not Save.spendCredits(price) then return false, "not enough credits" end
  Save.data.upgrades[k] = (Save.data.upgrades[k] or 0) + 1
  Save.dirty = true
  return true
end

return Save
