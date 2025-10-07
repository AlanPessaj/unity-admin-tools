-- Parkour Tool
TOOL = TOOL or {}
TOOL.Name = "Parkour"
TOOL.Category = "CGO Admin Tools"
TOOL.Command = nil
TOOL.ConfigName = ""

-- Include shared file first
AddCSLuaFile("weapons/gmod_tool/stools/parkour/shared.lua")
include("weapons/gmod_tool/stools/parkour/shared.lua")

-- Server files
if SERVER then
    AddCSLuaFile("weapons/gmod_tool/stools/parkour/client.lua")
    include("weapons/gmod_tool/stools/parkour/server.lua")
end

-- Función para verificar si el jugador tiene permisos (misma lógica que GunGame y PropMovement)
local function HasParkourAccess(ply)
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

-- Función para verificar permisos
function TOOL:CanTool(ply)
    return HasParkourAccess(ply)
end

-- Client files
if CLIENT then
    language.Add("tool.parkour.name", "[CGO] Parkour Tool")
    language.Add("tool.parkour.desc", "Creado por AlanPessaj ◢ ◤")
    language.Add("tool.parkour.0", "Configura las opciones en el menú de la herramienta.")
    
    -- Include client files
    include("weapons/gmod_tool/stools/parkour/client.lua")
    
    -- Tool menu con verificación de permisos
    function TOOL.BuildCPanel(panel)
        -- Verificar permisos antes de mostrar la interfaz
        if not HasParkourAccess(LocalPlayer()) then
            panel:AddControl("Label", {Text = "Acceso denegado."})
            return
        end
        
        -- Mostrar la interfaz solo si tiene permisos
        if not Parkour_UI then return end
        Parkour_UI(panel)
    end
end
