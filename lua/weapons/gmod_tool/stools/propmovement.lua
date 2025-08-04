-- PropMovement Tool
TOOL = TOOL or {}
TOOL.Name = "PropMovement"
TOOL.Category = "CGO Admin Tools"
TOOL.Command = nil
TOOL.ConfigName = ""

-- Include shared file first
AddCSLuaFile("weapons/gmod_tool/stools/propmovement/shared.lua")
include("weapons/gmod_tool/stools/propmovement/shared.lua")

-- Server files
if SERVER then
    AddCSLuaFile("weapons/gmod_tool/stools/propmovement/client.lua")
    include("weapons/gmod_tool/stools/propmovement/server.lua")
end

-- Client files
if CLIENT then
    language.Add("tool.propmovement.name", "[CGO] PropMovement")
    language.Add("tool.propmovement.desc", "Herramienta para mover props")
    language.Add("tool.propmovement.0", "Configura las opciones en el menú de la herramienta.")
    
    -- Include client files
    include("weapons/gmod_tool/stools/propmovement/client.lua")
    
    -- Tool menu
    function TOOL.BuildCPanel(panel)
        if not PropMovement_UI then return end
        PropMovement_UI(panel)
    end
end
