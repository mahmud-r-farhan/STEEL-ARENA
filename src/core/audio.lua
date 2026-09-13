--=============================================================================
-- Audio: procedurally-synthesized SFX (no asset files needed) + volume bus.
-- Ships sounds via love.sound.newSoundData from math-generated waveforms.
--=============================================================================

local Audio = {
  sounds = {},
  musicSource = nil,
  volumes = { master = 0.8, sfx = 1.0, music = 0.6 },
  _nextPlay = 0,
}

local bit = bit32 or bit

-- Synthesize a short mono sound as PCM and register it.
local function synth(name, seconds, fn, sampleRate)
  sampleRate = sampleRate or 22050
  local n = math.floor(seconds * sampleRate)
  local sd
  local ok, err = pcall(function()
    sd = love.sound.newSoundData(n, sampleRate, 16, 1)
  end)
  if not ok then return end
  for i = 0, n - 1 do
    local t = i / sampleRate
    local v = fn(t, seconds)
    v = math.max(-1, math.min(1, v))
    sd:setSample(i, v)
  end
  local src = love.audio.newSource(sd, "static")
  Audio.sounds[name] = src
end

function Audio.load(settings)
  Audio.volumes = settings.data.volume
  if not love or not love.sound then return end

  local pi = math.pi

  -- cannon: big low boom with decay + noise crack
  synth("fire", 0.28, function(t, dur)
    local env = math.exp(-t * 14)
    local rumble = math.sin(2 * pi * 70 * t) * 0.7 + math.sin(2 * pi * 43 * t) * 0.5
    local noise = (math.random() * 2 - 1) * 0.35 * math.exp(-t * 40)
    return (rumble * env + noise) * 0.9
  end)

  -- machine-gun pop
  synth("fire_mg", 0.09, function(t, dur)
    local env = math.exp(-t * 55)
    local pop = math.sin(2 * pi * 180 * t)
    local noise = (math.random() * 2 - 1) * 0.6 * math.exp(-t * 90)
    return (pop * env + noise) * 0.55
  end)

  -- ricochet ping
  synth("ricochet", 0.20, function(t, dur)
    local env = math.exp(-t * 22)
    local sweep = math.sin(2 * pi * (1500 - 900 * t / dur) * t)
    return sweep * env * 0.25
  end)

  -- metal hit on armor
  synth("hit", 0.16, function(t, dur)
    local env = math.exp(-t * 30)
    local clank = math.sin(2 * pi * 320 * t) * 0.6 + math.sin(2 * pi * 810 * t) * 0.3
    local noise = (math.random() * 2 - 1) * 0.4 * math.exp(-t * 70)
    return (clank * env + noise) * 0.7
  end)

  -- explosion: deep boom, long tail
  synth("explosion", 0.7, function(t, dur)
    local env = math.exp(-t * 6)
    local boom = math.sin(2 * pi * 48 * t) * 0.8 + math.sin(2 * pi * 33 * t) * 0.6
    local noise = (math.random() * 2 - 1) * 0.5 * math.exp(-t * 10)
    return (boom * env + noise) * 1.0
  end)

  -- pickup chime
  synth("pickup", 0.30, function(t, dur)
    local env = math.exp(-t * 9)
    local note = math.sin(2 * pi * 660 * t) + math.sin(2 * pi * 990 * t) * 0.6
    return (note * env) * 0.28
  end)

  -- UI click
  synth("click", 0.05, function(t, dur)
    local env = math.exp(-t * 90)
    return math.sin(2 * pi * 1100 * t) * env * 0.3
  end)

  -- UI hover
  synth("hover", 0.03, function(t, dur)
    return math.sin(2 * pi * 700 * t) * math.exp(-t * 120) * 0.12
  end)

  -- UI purchase: two-tone
  synth("purchase", 0.35, function(t, dur)
    local f = t < 0.15 and 880 or 1320
    local env = math.exp(-(t % 0.15) * 12)
    return math.sin(2 * pi * f * t) * env * 0.25
  end)

  -- level up fanfare
  synth("win", 0.9, function(t, dur)
    local seq = { 523, 659, 784, 1046 }
    local idx = math.min(4, math.floor(t / 0.22) + 1)
    local f = seq[idx] or 523
    local env = math.exp(-((t % 0.22)) * 6)
    return math.sin(2 * pi * f * t) * env * 0.22
  end)

  synth("lose", 0.9, function(t, dur)
    local seq = { 392, 330, 262, 196 }
    local idx = math.min(4, math.floor(t / 0.22) + 1)
    local f = seq[idx] or 392
    local env = math.exp(-((t % 0.22)) * 6)
    return math.sin(2 * pi * f * t) * env * 0.22
  end)

  synth("reload", 0.35, function(t, dur)
    if t < 0.15 then
      return math.sin(2 * pi * 300 * t) * math.exp(-t * 25) * 0.2
    else
      local tt = t - 0.18
      return math.sin(2 * pi * 420 * tt) * math.exp(-tt * 25) * 0.2
    end
  end)
end

function Audio.applyVolumes()
  if love and love.audio then
    love.audio.setVolume(Audio.volumes.master or 0.8)
  end
  for _, src in pairs(Audio.sounds) do
    src:setVolume(Audio.volumes.sfx or 1.0)
  end
  if Audio.musicSource then
    Audio.musicSource:setVolume(Audio.volumes.music or 0.6)
  end
end

function Audio.play(name, pitch)
  local src = Audio.sounds[name]
  if not src then return end
  -- clone so overlapping plays don't cut each other
  local ok, inst = pcall(function() return src:clone() end)
  if not ok then return end
  if pitch then inst:setPitch(pitch) end
  inst:setVolume(Audio.volumes.sfx or 1.0)
  inst:play()
  table.insert(Audio._live or {}, inst)
  Audio._live = Audio._live or {}
  -- garbage collect finished instances occasionally
  if #Audio._live > 24 then
    for i = #Audio._live, 1, -1 do
      if not Audio._live[i]:isPlaying() then table.remove(Audio._live, i) end
    end
  end
end

function Audio.update(dt) end

function Audio.shutdown()
  for _, src in pairs(Audio.sounds) do
    src:release()
  end
  Audio.sounds = {}
end

return Audio
