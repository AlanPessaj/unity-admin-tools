GUNGAME = GUNGAME or {}

-- Armas por defecto del GunGame
GUNGAME.DEFAULT_WEAPONS = {
    "arccw_ak47",
    "arccw_ump45",
    "arccw_ragingbull",
    "arccw_go_ssg08",
    "arccw_melee_machete"
}

-- Si no hay armas definidas aún, usar los defaults
if not GUNGAME.Weapons or #GUNGAME.Weapons == 0 then
    GUNGAME.Weapons = table.Copy(GUNGAME.DEFAULT_WEAPONS)
end

-- Función para restaurar las armas por defecto
function GUNGAME.RestoreDefaultWeapons()
    GUNGAME.Weapons = table.Copy(GUNGAME.DEFAULT_WEAPONS)
end


-- Default player settings
GUNGAME.PlayerHealth = 100
GUNGAME.PlayerArmor = 100
GUNGAME.PlayerSpeedMultiplier = 1.0
GUNGAME.TimeLimit = -1
-- Jugadores mínimos requeridos para que el evento siga activo
GUNGAME.MinPlayersNeeded = 2 --TODO: Change to 5 for production

GUNGAME.Config = {
    MinPoints = 3, -- Minimum points to define an area
    MaxPoints = 4, -- Maximum points to define an area
    RespawnHeight = 10, -- Height above ground to respawn players
    CheckInterval = 1, -- How often to check player positions (in seconds)
}

-- Munición por defecto al dar un arma (primaria / secundaria)
GUNGAME.DefaultPrimaryAmmo = 1000
GUNGAME.DefaultSecondaryAmmo = 100

-- Helper function to check if a point is inside a polygon
function GUNGAME.PointInPoly2D(pos, poly)
    local x, y = pos.x, pos.y
    local inside = false
    local j = #poly
    
    for i = 1, #poly do
        local xi, yi = poly[i].x, poly[i].y
        local xj, yj = poly[j].x, poly[j].y
        
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 0.00001) + xi) then
            inside = not inside
        end
        j = i
    end
    
    return inside
end

-- Calculate center point of polygon
function GUNGAME.CalculateCenter(points)
    if not points or #points == 0 then return Vector(0, 0, 0) end
    
    local center = Vector(0, 0, 0)
    for _, v in ipairs(points) do 
        center = center + v 
    end
    
    return center / #points
end

function HasGunGameAccess(ply)
    if not IsValid(ply) or not ply.GetUserGroup then return false end
    
    local allowedRanks = {
        ["superadmin"] = true,
        ["moderadorelite"] = true,
        ["moderadorsenior"] = true,
        ["moderador"] = true,
        ["directormods"] = true,
        ["ejecutivo"] = true
    }
    
    return ply:IsSuperAdmin() or (allowedRanks[ply:GetUserGroup():lower()] == true)
end
