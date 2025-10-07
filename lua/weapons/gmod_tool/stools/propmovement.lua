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

-- Función para verificar si el jugador tiene permisos (misma lógica que GunGame)
local function HasPropMovementAccess(ply)
    if not IsValid(ply) or not ply.GetUserGroup then return false end
    
    -- Lista de rangos que tienen acceso
    local allowedRanks = {
        ["superadmin"] = true,
        ["moderadorelite"] = true,
        ["moderadorsenior"] = true,
        ["moderador"] = true,
        ["directormods"] = true,
        ["ejecutivo"] = true
    }
    
    -- Verificar si el jugador tiene uno de los rangos permitidos
    return ply:IsSuperAdmin() or (allowedRanks[ply:GetUserGroup():lower()] == true)
end

function RankLevel(ply)
    if not IsValid(ply) or not ply.GetUserGroup then return 0 end
    local rankLevels = {
        ["superadmin"] = 999,
        ["moderadorelite"] = 4,
        ["moderador"] = 2,
        ["moderadorsenior"] = 6,
        ["directormods"] = 10,
        ["ejecutivo"] = 100
    }

    return rankLevels[ply:GetUserGroup():lower()] or 0
end

-- Función para verificar permisos
function TOOL:CanTool(ply)
    return HasPropMovementAccess(ply)
end

-- Función para manejar el clic izquierdo
function TOOL:LeftClick(tr)
    if CLIENT then return true end -- Let client handle the visual feedback
    
    -- Verificar permisos en el servidor
    if not HasPropMovementAccess(self:GetOwner()) then return false end
    
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
    
    -- Tool menu con verificación de permisos
    function TOOL.BuildCPanel(panel)
        -- Verificar permisos antes de mostrar la interfaz
        if not HasPropMovementAccess(LocalPlayer()) then
            panel:AddControl("Label", {Text = "Acceso denegado."})
            return
        end
        
        -- Mostrar la interfaz solo si tiene permisos
        if not PropMovement_UI then return end
        PropMovement_UI(panel)
    end
end
