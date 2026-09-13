function love.load()
  local ok, err = pcall(function()
    package.path = ";../../src/?.lua;" .. package.path
    local f = loadfile("../../tools/debug_proto.lua")
    if f then f() else print("script not found") end
  end)
  if not ok then print("ERR: " .. tostring(err)) end
  love.event.quit()
end
