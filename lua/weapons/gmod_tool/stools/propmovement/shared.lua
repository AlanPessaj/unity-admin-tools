-- Shared variables and functions for PropMovement
PropMovement = PropMovement or {}

-- Network strings
if SERVER then
    util.AddNetworkString("PropMovement_Config")
    util.AddNetworkString("PropMovement_Start")
    util.AddNetworkString("PropMovement_Stop")
    util.AddNetworkString("PropMovement_StartAll")
    util.AddNetworkString("PropMovement_CheckServer")
    util.AddNetworkString("PropMovement_ServerResponse")
    util.AddNetworkString("PropMovement_ClearAll")
    util.AddNetworkString("PropMovement_Remove")
end

-- Default settings
PropMovement.Settings = {
    MoveSpeed = 10,
    RotateSpeed = 1,
    GridSize = 1,
    SnapToGrid = true
}

-- Store selected props and their settings
PropMovement.SelectedProps = {}
PropMovement.Directions = {
    ["UP"] = Vector(0, 0, 1),
    ["DOWN"] = Vector(0, 0, -1),
    ["RIGHT"] = Vector(0, 1, 0),
    ["LEFT"] = Vector(0, -1, 0),
    ["FORWARD"] = Vector(1, 0, 0),
    ["BACK"] = Vector(-1, 0, 0)
}

-- Permissions
function PropMovement.HasPermission(ply)
    if not IsValid(ply) or not ply.GetUserGroup then return false end
    
    -- Lista de rangos que tienen acceso (misma que GunGame)
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

-- Add a prop to the selected list
function PropMovement.AddProp(ent)
    if not IsValid(ent) or not ent:IsValid() then return end
    
    local entIndex = ent:EntIndex()
    if not PropMovement.SelectedProps[entIndex] then
        PropMovement.SelectedProps[entIndex] = {
            ent = ent,
            direction = "FORWARD",
            speed = 100,
            distance = 100,
            cooldown = 1
        }
        return true
    end
    return false
end

-- Remove a prop from the selected list
function PropMovement.RemoveProp(ent)
    if not IsValid(ent) then return end
    PropMovement.SelectedProps[ent:EntIndex()] = nil
end

-- Clear all selected props
function PropMovement.ClearProps()
    PropMovement.SelectedProps = {}
end

-- Network strings will be registered in the server file
