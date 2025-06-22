AddCSLuaFile("shared.lua")
AddCSLuaFile("client.lua")
include("shared.lua")

-- Network strings
util.AddNetworkString("gungame_area_start")
util.AddNetworkString("gungame_area_clear")
util.AddNetworkString("gungame_area_update_points")
util.AddNetworkString("gungame_start_event")
util.AddNetworkString("gungame_stop_event")
util.AddNetworkString("gungame_event_stopped")
util.AddNetworkString("gungame_add_spawnpoint")
util.AddNetworkString("gungame_clear_spawnpoints")
util.AddNetworkString("gungame_update_spawnpoints")

-- Server state
local selecting = {}
local points = {}
local spawnPoints = {}
local gungame_players = {}
local gungame_area_center = nil
local gungame_event_active = false
local gungame_area_points = {}
local gungame_respawn_time = {}

-- Function to update area points for all clients
local function UpdateAreaPointsForAll(plyPoints, sender)
    net.Start("gungame_area_update_points")
        net.WriteTable(plyPoints or {})
    if sender then
        net.SendOmit(sender) -- Send to all except the sender (who already has the update)
    else
        net.Broadcast()
    end
end

-- Net receivers

-- Iniciar la selección del área
net.Receive("gungame_area_start", function(_, ply)
    if not IsValid(ply) then return end
    
    -- Iniciar modo de selección para este jugador
    selecting[ply] = true
    points[ply] = table.Copy(gungame_area_points) -- Initialize with current global points
    
    -- Enviar los puntos actuales al jugador que acaba de iniciar la selección
    net.Start("gungame_area_update_points")
        net.WriteTable(gungame_area_points)
    net.Send(ply)
end)

-- Validar un arma con el servidor
net.Receive("gungame_validate_weapon", function(len, ply)
    if not IsValid(ply) then return end
    
    local weaponID = net.ReadString()
    local isValid = weapons.Get(weaponID) ~= nil
    
    net.Start("gungame_weapon_validated")
        net.WriteBool(isValid)
        net.WriteString(weaponID)
    net.Send(ply)
end)

-- Limpiar la lista de armas
net.Receive("gungame_clear_weapons", function(len, ply)
    if not IsValid(ply) then return end
    
    -- Limpiar la lista local
    GUNGAME.Weapons = {}
    
    -- Notificar a todos los clientes
    net.Start("gungame_clear_weapons")
    net.Broadcast()
end)

-- Net receivers
net.Receive("gungame_area_start", function(_, ply)
    if gungame_event_active then return end
    selecting[ply] = true
    points[ply] = {}
    net.Start("gungame_area_update_points")
        net.WriteTable(points[ply])
    net.Send(ply)
end)

net.Receive("gungame_area_clear", function(_, ply)
    if gungame_event_active then return end
    
    -- Clear points for this player
    selecting[ply] = false
    points[ply] = {}
    
    -- Clear global points and notify all clients
    gungame_area_points = {}
    net.Start("gungame_area_update_points")
        net.WriteTable({})
    net.Broadcast()
end)

net.Receive("gungame_start_event", function(_, ply)
    local area = points[ply]
    if not area or #area < GUNGAME.Config.MinPoints then return end

    gungame_area_points = area
    gungame_area_center = GUNGAME.CalculateCenter(area)
    gungame_players = {}

    -- Find players inside the area
    for _, p in ipairs(player.GetAll()) do
        if GUNGAME.PointInPoly2D(p:GetPos(), area) then
            table.insert(gungame_players, p:SteamID64())
        end
    end

    gungame_event_active = true
    print("[GunGame] Event started! Players in area: " .. #gungame_players)
end)

net.Receive("gungame_stop_event", function(_, ply)
    gungame_players = {}
    gungame_area_center = nil
    gungame_event_active = false
    gungame_area_points = nil
    gungame_respawn_time = {}
    
    -- Limpiar los spawn points
    spawnPoints = {}

    -- Notificar a los clientes
    net.Start("gungame_event_stopped")
    net.Broadcast()
    
    -- Actualizar a los clientes con la lista vacía de spawn points
    net.Start("gungame_update_spawnpoints")
        net.WriteTable({})
    net.Broadcast()
    
    print("[GunGame] Event stopped")
end)

-- Hooks
hook.Add("PlayerSpawn", "gungame_respawn_in_area", function(ply)
    if not gungame_event_active or not gungame_area_center then return end
    if not table.HasValue(gungame_players, ply:SteamID64()) then return end
    
    gungame_respawn_time[ply:SteamID64()] = CurTime()
    timer.Simple(0, function()
        if IsValid(ply) then
            -- Try to use a random spawn point if available, otherwise use area center
            local spawnData = GUNGAME.GetSpawnPoint()
            
            if spawnData and spawnData.pos then
                -- Usar la posición y ángulo guardados
                ply:SetPos(spawnData.pos)
                if spawnData.ang then
                    ply:SetEyeAngles(spawnData.ang)
                end
            else
                -- Si no hay spawn points, usar el centro del área
                ply:SetPos(gungame_area_center)
                ply:SetEyeAngles(Angle(0, math.random(0, 360), 0))
            end
        end
    end)
end)

-- Area check timer
timer.Create("gungame_area_check", GUNGAME.Config.CheckInterval, 0, function()
    if not gungame_event_active or not gungame_players or not gungame_area_points then return end
    
    local area = gungame_area_points
    for _, ply in ipairs(player.GetAll()) do
        if table.HasValue(gungame_players, ply:SteamID64()) and IsValid(ply) and ply:Alive() then
            if not GUNGAME.PointInPoly2D(ply:GetPos(), area) then
                ply:Kill()
            end
        end
    end
end)

-- TOOL functions
TOOL.LeftClick = function(self, trace)
    if not selecting[self:GetOwner()] then return false end
    
    local ply = self:GetOwner()
    points[ply] = points[ply] or {}
    
    if #points[ply] < GUNGAME.Config.MaxPoints then
        local newPoint = trace.HitPos + Vector(0, 0, GUNGAME.Config.RespawnHeight)
        table.insert(points[ply], newPoint)
        
        -- Update global points and sync to all clients
        gungame_area_points = table.Copy(points[ply])
        net.Start("gungame_area_update_points")
            net.WriteTable(gungame_area_points)
        net.Broadcast()
        
        -- If this completes the area, stop selecting
        if #points[ply] >= GUNGAME.Config.MaxPoints then
            selecting[ply] = false
        end
    end
    
    return true
end

TOOL.RightClick = function() return false end

TOOL.Deploy = function(self)
    local ply = self:GetOwner()
    -- Send current area points to the player who deployed the tool
    net.Start("gungame_area_update_points")
        net.WriteTable(gungame_area_points)
    net.Send(ply)
end

TOOL.Holster = function(self)
    local ply = self:GetOwner()
    selecting[ply] = false
    -- Don't clear points when holstering, only clear when explicitly requested
    -- No need to send any update here as we want to keep the points
end

-- Spawn points network handlers
net.Receive("gungame_add_spawnpoint", function(_, ply)
    if gungame_event_active then return end
    
    -- Leer la posición y ángulo enviados por el cliente
    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    
    if not pos or not ang then return end
    
    -- Crear tabla con posición y ángulo
    local spawnData = {
        pos = pos,
        ang = ang
    }
    
    table.insert(spawnPoints, spawnData)
    
    -- Actualizar a todos los clientes
    net.Start("gungame_update_spawnpoints")
        net.WriteTable(spawnPoints)
    net.Broadcast()
    
    print(string.format("[GunGame] Spawn point agregado en %s, %s", tostring(pos), tostring(ang)))
end)

net.Receive("gungame_clear_spawnpoints", function(_, ply)
    if gungame_event_active then return end
    
    spawnPoints = {}
    
    -- Update all clients that spawn points have been cleared
    net.Start("gungame_update_spawnpoints")
        net.WriteTable({})
    net.Broadcast()
end)

-- Function to get the best spawn point (prioritize empty spawns)
function GUNGAME.GetSpawnPoint()
    if #spawnPoints == 0 then return nil end
    
    local safeSpawns = {}
    local minSafeDistance = 300
    local activePlayers = {}
    for _, steamID in ipairs(gungame_players or {}) do
        local ply = player.GetBySteamID64(steamID)
        if IsValid(ply) and ply:Alive() then
            table.insert(activePlayers, ply)
        end
    end
    
    -- Si no hay jugadores activos, devolver un spawn aleatorio
    if #activePlayers == 0 then
        return table.Random(spawnPoints)
    end
    
    -- Buscar spawns seguros (sin jugadores cerca)
    for _, spawn in ipairs(spawnPoints) do
        local isSafe = true
        local spawnPos = spawn.pos
        
        for _, ply in ipairs(activePlayers) do
            if spawnPos:Distance(ply:GetPos()) < minSafeDistance then
                isSafe = false
                break
            end
        end
        
        if isSafe then
            table.insert(safeSpawns, spawn)
        end
    end
    
    -- Si hay spawns seguros, elegir uno al azar
    if #safeSpawns > 0 then
        return table.Random(safeSpawns)
    end
    
    -- Si no hay spawns seguros, encontrar el más alejado de otros jugadores
    local bestSpawn = nil
    local maxMinDistance = -1
    
    for _, spawn in ipairs(spawnPoints) do
        local minDistance = math.huge
        local spawnPos = spawn.pos
        
        for _, ply in ipairs(activePlayers) do
            local dist = spawnPos:Distance(ply:GetPos())
            if dist < minDistance then
                minDistance = dist
            end
        end
        
        if minDistance > maxMinDistance then
            maxMinDistance = minDistance
            bestSpawn = spawn
        end
    end
    
    return bestSpawn or table.Random(spawnPoints)
end

-- Function to get just a random spawn position (backwards compatibility)
function GUNGAME.GetSpawnPosition()
    local spawn = GUNGAME.GetSpawnPoint()
    return spawn and spawn.pos or nil
end

-- Send spawn points to players when they join the server
hook.Add("PlayerInitialSpawn", "GunGame_SendSpawnPoints", function(ply)
    timer.Simple(1, function()
        if IsValid(ply) then
            net.Start("gungame_update_spawnpoints")
                net.WriteTable(spawnPoints)
            net.Send(ply)
        end
    end)
end)
