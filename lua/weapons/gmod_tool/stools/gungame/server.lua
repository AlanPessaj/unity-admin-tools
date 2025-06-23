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
util.AddNetworkString("gungame_sync_weapons")
util.AddNetworkString("gungame_play_win_sound")
util.AddNetworkString("gungame_play_kill_sound")

-- Server state
local selecting = {}
local points = {}
local spawnPoints = {}
local gungame_players = {} -- Ahora será una tabla con más información por jugador
local gungame_area_center = nil
local gungame_event_active = false
local gungame_area_points = {}
local gungame_respawn_time = {}

-- Función para detener el evento de GunGame
function GUNGAME.StopEvent()
    -- Restaurar a los jugadores antes de limpiar
    for steamid64, data in pairs(gungame_players) do
        if IsValid(data.player) then
            data.player:StripWeapons()
            data.player:KillSilent()
        end
    end
    
    -- Limpiar variables globales
    gungame_players = {}
    gungame_area_center = nil
    gungame_event_active = false
    gungame_area_points = {}
    gungame_respawn_time = {}
    spawnPoints = {}
    
    -- Notificar a los clientes que el evento ha terminado
    net.Start("gungame_event_stopped")
    net.Broadcast()
    
    -- Actualizar a los clientes con la lista vacía de spawn points
    net.Start("gungame_update_spawnpoints")
        net.WriteTable({})
    net.Broadcast()
    
    print("[GunGame] Evento detenido después de la victoria")
end

-- Función para manejar la victoria de un jugador
local function HandlePlayerWin(ply)
    if not IsValid(ply) then return end
    
    -- Anunciar al ganador
    local winnerName = ply:Nick()
    local message = "[GunGame] ¡" .. winnerName .. " ha ganado el GunGame!"
    
    -- Mostrar mensaje en el chat de todos los jugadores
    for _, v in ipairs(player.GetAll()) do
        v:ChatPrint(message)
    end
    
    -- Reproducir sonido de victoria solo para el ganador
    net.Start("gungame_play_win_sound")
    net.Send(ply)
    
    -- Esperar un poco antes de detener el evento para que los jugadores vean el mensaje
    timer.Simple(5, function()
        GUNGAME.StopEvent()
    end)
end

-- Función para obtener las kills de un jugador
function GUNGAME.GetPlayerKills(steamid64)
    return gungame_players[steamid64] and gungame_players[steamid64].kills or 0
end

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

-- Sincronizar lista de armas desde el cliente
net.Receive("gungame_sync_weapons", function(_, ply)
    if not IsValid(ply) then return end
    
    -- Leer la cantidad de armas
    local count = net.ReadUInt(8) -- Hasta 255 armas
    local weaponsList = {}
    
    -- Leer cada arma
    for i = 1, count do
        local weaponID = net.ReadString()
        if weaponID and weaponID ~= "" then
            table.insert(weaponsList, weaponID)
        end
    end
    
    -- Actualizar la lista de armas
    GUNGAME.Weapons = weaponsList
    
    print("[GunGame] Lista de armas actualizada desde el cliente. Total: " .. #weaponsList)
end)

-- Limpiar la lista de armas
net.Receive("gungame_clear_weapons", function(len, ply)
    if not IsValid(ply) then return end
    
    -- Limpiar la lista local
    GUNGAME.Weapons = {}
    
    -- Notificar a todos los clientes
    net.Start("gungame_clear_weapons")
    net.Broadcast()
    
    print("[GunGame] Lista de armas limpiada")
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

-- Función para dar un arma a un jugador según su índice de kill
local function GiveWeaponByKillCount(ply, killCount)
    if not IsValid(ply) then return end
    if not GUNGAME.Weapons or #GUNGAME.Weapons == 0 then return end
    
    -- Usar el operador módulo para hacer un bucle en la lista de armas
    local weaponIndex = (killCount % #GUNGAME.Weapons) + 1
    local weaponClass = GUNGAME.Weapons[weaponIndex]
    
    if weaponClass then
        ply:Give(weaponClass)
        print("[GunGame] Dando arma " .. weaponClass .. " a " .. ply:Nick() .. " (kills: " .. killCount .. ")")
    end
end

net.Receive("gungame_start_event", function(_, ply)
    local area = points[ply]
    if not area or #area < GUNGAME.Config.MinPoints then return end

    gungame_area_points = area
    gungame_area_center = GUNGAME.CalculateCenter(area)
    gungame_players = {}

    -- Find players inside the area
    local playerCount = 0
    for _, p in ipairs(player.GetAll()) do
        if GUNGAME.PointInPoly2D(p:GetPos(), area) then
            local steamid64 = p:SteamID64()
            if not gungame_players[steamid64] then
                gungame_players[steamid64] = {
                    player = p,
                    kills = 0,
                    steamid64 = steamid64,
                    weaponIndex = 0 -- Índice del arma actual
                }
                playerCount = playerCount + 1
                
                -- Dar arma inicial (índice 0)
                p:StripWeapons()
                if GUNGAME.Weapons and #GUNGAME.Weapons > 0 then
                    local firstWeapon = GUNGAME.Weapons[1]
                    if firstWeapon then
                        p:Give(firstWeapon)
                        print("[GunGame] Arma inicial (" .. firstWeapon .. ") dada a " .. p:Nick())
                    end
                end
            end
        end
    end

    gungame_event_active = true
    print("[GunGame] Event started! Players in area: " .. playerCount)
    
    -- Mostrar mensaje a todos los jugadores
    for _, p in ipairs(player.GetAll()) do
        if gungame_players[p:SteamID64()] then
            p:ChatPrint("[GunGame] ¡El evento ha comenzado! Mata jugadores para obtener mejores armas.")
        end
    end
end)

net.Receive("gungame_stop_event", function(_, ply)
    -- Restaurar a los jugadores antes de limpiar
    for steamid64, data in pairs(gungame_players) do
        if IsValid(data.player) then
            data.player:StripWeapons()
            data.player:KillSilent()
        end
    end
    
    gungame_players = {}
    gungame_area_center = nil
    gungame_event_active = false
    gungame_area_points = {}
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
    
    print("[GunGame] Evento detenido y jugadores restaurados")
end)

-- Hooks
-- Función para manejar el respawn de un jugador
local function HandlePlayerRespawn(ply, isImmediate)
    if not IsValid(ply) then return end
    if not gungame_event_active or not gungame_area_center then return end
    
    local steamid64 = ply:SteamID64()
    if not gungame_players[steamid64] then return end
    
    -- Guardar el tiempo de respawn
    gungame_respawn_time[steamid64] = CurTime()
    
    -- Obtener punto de spawn
    local spawnPos = gungame_area_center
    local spawnAng = Angle(0, math.random(0, 360), 0)
    
    -- Intentar obtener un punto de spawn personalizado
    local spawnData = GUNGAME.GetSpawnPoint()
    if spawnData and spawnData.pos then
        spawnPos = spawnData.pos
        if spawnData.ang then
            spawnAng = spawnData.ang
        end
    end
    
    -- Aplicar posición y ángulo
    if IsValid(ply) and spawnPos then
        -- Si es un respawn inmediato, forzar la posición
        if isImmediate then
            ply:SetPos(spawnPos)
            ply:SetEyeAngles(spawnAng)
        else
            -- Si no es inmediato, usar un timer muy corto
            timer.Simple(0, function()
                if IsValid(ply) and gungame_event_active then
                    ply:SetPos(spawnPos)
                    ply:SetEyeAngles(spawnAng)
                end
            end)
        end
    end
end

-- Hook para el respawn inicial
hook.Add("PlayerSpawn", "gungame_respawn_in_area", function(ply)
    if not IsValid(ply) then return end
    if not gungame_event_active or not gungame_area_center then return end
    
    local steamid64 = ply:SteamID64()
    if not gungame_players[steamid64] then return end
    
    -- Manejar el respawn de inmediato
    HandlePlayerRespawn(ply, true)
end)

-- Hook para el respawn después de morir
hook.Add("PlayerSpawn", "gungame_respawn_after_death", function(ply)
    if not IsValid(ply) then return end
    if not gungame_event_active or not gungame_area_center then return end
    
    local steamid64 = ply:SteamID64()
    local playerData = gungame_players[steamid64]
    if not playerData then return end
    
    -- Usar un pequeño retraso para el respawn después de morir
    timer.Simple(0.1, function()
        if IsValid(ply) and gungame_event_active then
            HandlePlayerRespawn(ply, false)
            
            -- Asegurarse de que el jugador tenga su arma
            if GUNGAME.Weapons and #GUNGAME.Weapons > 0 then
                local weaponIndex = (playerData.kills % #GUNGAME.Weapons) + 1
                local weaponClass = GUNGAME.Weapons[weaponIndex]
                
                if weaponClass then
                    ply:StripWeapons()
                    ply:Give(weaponClass)
                    ply:SelectWeapon(weaponClass)
                    print("[GunGame] Arma " .. weaponClass .. " dada a " .. ply:Nick() .. " (kills: " .. playerData.kills .. ")")
                end
            end
        end
    end)
end)

-- Hook para manejar las muertes de jugadores
hook.Add("PlayerDeath", "gungame_player_death", function(victim, inflictor, attacker)
    if not gungame_event_active then return end
    
    -- Verificar si el atacante es un jugador válido y no se está suicidando
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
        local attacker_steamid64 = attacker:SteamID64()
        local victim_steamid64 = victim:SteamID64()
        
        -- Verificar si ambos están en el evento
        if gungame_players[attacker_steamid64] and gungame_players[victim_steamid64] then
            -- Inicializar datos del atacante si no existen
            if not gungame_players[attacker_steamid64].kills then
                gungame_players[attacker_steamid64].kills = 0
                gungame_players[attacker_steamid64].level = 1
            end
            
            -- Incrementar las kills del jugador
            gungame_players[attacker_steamid64].kills = gungame_players[attacker_steamid64].kills + 1
            
            -- Verificar si el jugador sube de nivel
            if gungame_players[attacker_steamid64].kills >= 1 then  -- 1 kill por nivel por defecto
                gungame_players[attacker_steamid64].kills = 0
                gungame_players[attacker_steamid64].level = (gungame_players[attacker_steamid64].level or 1) + 1
                
                -- Verificar si el jugador ha alcanzado el nivel máximo (última arma)
                if gungame_players[attacker_steamid64].level > #GUNGAME.Weapons then
                    HandlePlayerWin(attacker)
                    return
                end
                
                -- Dar el arma correspondiente al nuevo nivel
                local weaponID = GUNGAME.Weapons[gungame_players[attacker_steamid64].level]
                if weaponID then
                    timer.Simple(0.1, function()
                        if IsValid(attacker) then
                            attacker:StripWeapons()
                            attacker:Give(weaponID)
                            attacker:SelectWeapon(weaponID)
                            
                            -- Obtener el nombre bonito del arma si existe
                            local weaponName = weapons.Get(weaponID) and weapons.Get(weaponID).PrintName or weaponID
                            attacker:ChatPrint("[GunGame] ¡Nivel " .. gungame_players[attacker_steamid64].level .. "! " .. 
                                          "Arma: " .. weaponName)
                            
                            -- Anunciar en el chat general
                            PrintMessage(HUD_PRINTTALK, attacker:Nick() .. " ha subido al nivel " .. 
                                        gungame_players[attacker_steamid64].level .. " (" .. weaponName .. ")")
                        end
                    end)
                end
            else
                -- Mostrar progreso hacia la siguiente arma
                local killsNeeded = 1 - gungame_players[attacker_steamid64].kills
                local currentLevel = gungame_players[attacker_steamid64].level or 1
                local nextWeapon = GUNGAME.Weapons[currentLevel + 1] or "Desconocida"
                local weaponName = weapons.Get(nextWeapon) and weapons.Get(nextWeapon).PrintName or nextWeapon
                
                attacker:ChatPrint(string.format("[GunGame] %d kill(s) más para la siguiente arma (%s - Nivel %d)", 
                    killsNeeded, weaponName, currentLevel + 1))
            end
            
            -- Mostrar mensaje en el chat sobre el asesinato
            PrintMessage(HUD_PRINTTALK, attacker:Nick() .. " ha asesinado a " .. victim:Nick() .. 
                          "! (Nivel " .. (gungame_players[attacker_steamid64].level or 1) .. ")")
            
            -- Reproducir sonido de kill para el atacante
            net.Start("gungame_play_kill_sound")
            net.Send(attacker)
        end
    end
end)

-- Area check timer
timer.Create("gungame_area_check", GUNGAME.Config.CheckInterval, 0, function()
    if not gungame_event_active or not gungame_players or not gungame_area_points then return end
    
    local area = gungame_area_points
    for _, ply in ipairs(player.GetAll()) do
        local steamid64 = ply:SteamID64()
        if gungame_players[steamid64] and IsValid(ply) and ply:Alive() then
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
