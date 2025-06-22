-- Shared configuration and utility functions for GunGame

GUNGAME = GUNGAME or {}
GUNGAME.Weapons = GUNGAME.Weapons or {}

-- Network messages
util.AddNetworkString("gungame_validate_weapon")
util.AddNetworkString("gungame_weapon_validated")
util.AddNetworkString("gungame_clear_weapons")
util.AddNetworkString("gungame_area_start")
util.AddNetworkString("gungame_area_clear")
util.AddNetworkString("gungame_area_update_points")
util.AddNetworkString("gungame_start_event")
util.AddNetworkString("gungame_stop_event")
util.AddNetworkString("gungame_event_stopped")
util.AddNetworkString("gungame_add_spawnpoint")
util.AddNetworkString("gungame_clear_spawnpoints")
util.AddNetworkString("gungame_update_spawnpoints")
util.AddNetworkString("gungame_sync_weapons")

GUNGAME.Config = {
    MinPoints = 3, -- Minimum points to define an area
    MaxPoints = 4, -- Maximum points to define an area
    RespawnHeight = 10, -- Height above ground to respawn players
    CheckInterval = 1, -- How often to check player positions (in seconds)
}

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
