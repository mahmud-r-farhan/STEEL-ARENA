--=============================================================================
-- Settings: graphics, audio, controls. Persisted separately from account.
--=============================================================================

local lfs = love and love.filesystem or nil

local Settings = {
  data = {
    volume   = { master = 0.8, sfx = 1.0, music = 0.6 },
    show_fps = false,
    screen_shake = true,
    mouse_sensitivity = 1.0,
    name     = nil,
    last_server = nil,
  },
}

local function ser(v, indent)
  local t = type(v)
  if t == "number" or t == "boolean" then return tostring(v)
  elseif t == "string" then return string.format("%q", v)
  elseif t == "table" then
    local parts, n = {}, 0
    for k, val in pairs(v) do
      n = n + 1
      local key = type(k) == "string" and string.format("[%q]", k) or ("[" .. tostring(k) .. "]")
      parts[n] = indent .. "\t" .. key .. " = " .. ser(val, indent .. "\t")
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  return "nil"
end

function Settings.load()
  if not lfs or not lfs.getInfo("settings.lua") then return end
  local chunk = lfs.load("settings.lua")
  if not chunk then return end
  local ok, result = pcall(chunk)
  if ok and type(result) == "table" then
    for k, v in pairs(result) do
      if type(v) == "table" and type(Settings.data[k]) == "table" then
        for kk, vv in pairs(v) do Settings.data[k][kk] = vv end
      else
        Settings.data[k] = v
      end
    end
  end
end

function Settings.save()
  if not lfs then return end
  pcall(lfs.write, "settings.lua", "return " .. ser(Settings.data, ""))
end

function Settings.applyAudio()
  if love and love.audio then
    love.audio.setVolume(Settings.data.volume.master or 0.8)
  end
end

return Settings
