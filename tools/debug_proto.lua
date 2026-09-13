package.path = ";./?.lua;" .. package.path
local Protocol = require("net.protocol")
local T = Protocol.T

local data = Protocol.encode(T.HELLO, { name = "Ace", tankId = "heavy",
  camoId = "none", upgrades = { 1, 2, 3, 0, 1 }, version = 1 })
print("encoded len:", #data)
for i = 1, #data do
  io.write(string.format("%02x ", data:byte(i)))
end
print()
local t, m, used = Protocol.decode(data)
print("decoded type:", t, "used:", used)
print("name:", m.name, "tank:", m.tankId, "camo:", m.camoId)
print("upg:", table.concat(m.upgrades, ","), "ver:", m.version)
