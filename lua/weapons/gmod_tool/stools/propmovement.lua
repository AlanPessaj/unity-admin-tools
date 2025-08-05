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

-- Función para verificar permisos
function TOOL:CanTool(ply)
    if not IsValid(ply) then return false end
    return PropMovement.HasPermission(ply)
end

-- Función para manejar el clic izquierdo
function TOOL:LeftClick(tr)
    if CLIENT then return true end -- Let client handle the visual feedback
    
    if not IsValid(tr.Entity) or tr.Entity:GetClass() ~= "prop_physics" then 
        return false 
    end
    
    -- Server-side logic can be added here if needed
    return true
end

-- Client files
if CLIENT then
    language.Add("tool.propmovement.name", "[CGO] PropMovement")
    language.Add("tool.propmovement.desc", "Creado por AlanPessaj ◢ ◤")
    language.Add("tool.propmovement.0", "Configura las opciones en el menú de la herramienta.")
    
    -- Include client files
    include("weapons/gmod_tool/stools/propmovement/client.lua")
    
    -- Tool menu
    function TOOL.BuildCPanel(panel)
        if not PropMovement_UI then return end
        PropMovement_UI(panel)
    end
end
