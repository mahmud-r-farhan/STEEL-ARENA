--=============================================================================
-- Dedicated server bootstrap for plain Lua (5.1+) + LuaSocket, no LÖVE.
--   lua server/bootstrap.lua          (from src/)
--   luajit server/bootstrap.lua
--=============================================================================

local ok, err = pcall(function()
  local Server = require("server.app")
  Server.start({ port = tonumber(os.getenv("STEEL_PORT")) or nil })
end)
if not ok then
  print("server crashed: " .. tostring(err))
  os.exit(1)
end
