-- Main GunGame Tool Definition
TOOL = TOOL or {}
TOOL.Name = "GunGame"
TOOL.Category = "CGO Admin Tools"
TOOL.Command = nil
TOOL.ConfigName = ""

-- Include shared, client, and server files
local toolDir = "weapons/gmod_tool/stools/gungame/"
AddCSLuaFile(toolDir.."shared.lua")
AddCSLuaFile(toolDir.."client.lua")
AddCSLuaFile(toolDir.."cl_holograms.lua")
include(toolDir.."shared.lua")

-- Función para verificar si el jugador tiene permisos
local function HasGunGameAccess(ply)
    if not IsValid(ply) or not ply.GetUserGroup then return false end
    
    -- Lista de rangos que tienen acceso
    local allowedRanks = {
        ["superadmin"] = true,
        ["moderadorelite"] = true,
        ["moderadorsenior"] = true,
        ["directormods"] = true,
        ["ejecutivo"] = true
    }
    
    -- Verificar si el jugador tiene uno de los rangos permitidos
    return ply:IsSuperAdmin() or (allowedRanks[ply:GetUserGroup():lower()] == true)
end

-- Verificar permisos para usar la herramienta
function TOOL:CanTool(ply, trace)
    return HasGunGameAccess(ply)
end

if CLIENT then
    function TOOL:DrawHUD()
        if not HasGunGameAccess(LocalPlayer()) then return end
        if self.BaseClass then
            self.BaseClass.DrawHUD(self)
        end
    end
end

if CLIENT then
    include(toolDir.."cl_holograms.lua")
end


function TOOL.BuildCPanel(panel)
    include(toolDir.."cl_holograms.lua")
    if not HasGunGameAccess(LocalPlayer()) then
        panel:AddControl("Label", {Text = "Acceso denegado."})
        return
    end
    
    -- Cargar el código del cliente
    local CreateGunGameUI = include(toolDir.."client.lua")
    
    if CreateGunGameUI then
        -- Inicializar el panel
        if panel.SetName then panel:SetName("") end
        
        GUNGAME = GUNGAME or {}
        GUNGAME.AreaPanel = panel
        panel:DockPadding(8, 8, 8, 8)
        
        -- Crear la interfaz de usuario
        CreateGunGameUI(panel)
    else
        panel:AddControl("Label", {Text = "Error al cargar la interfaz de usuario."})
    end
end

-- Include server-side code
if SERVER then
    include(toolDir.."server.lua")
end
