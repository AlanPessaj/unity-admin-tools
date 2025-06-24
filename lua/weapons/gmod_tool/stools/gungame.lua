-- Main GunGame Tool Definition
TOOL = TOOL or {}
TOOL.Name = "GunGame"
TOOL.Category = "CGO Admin Tools"
TOOL.Command = nil
TOOL.ConfigName = ""

-- Include shared, client, and server files
AddCSLuaFile("gungame/shared.lua")
AddCSLuaFile("gungame/client.lua")
AddCSLuaFile("gungame/cl_holograms.lua")
include("gungame/shared.lua")

-- Include server-side code
if SERVER then
    include("gungame/server.lua")
end

-- Include client-side code
if CLIENT then
    include("gungame/client.lua")
    include("gungame/cl_holograms.lua")
end
