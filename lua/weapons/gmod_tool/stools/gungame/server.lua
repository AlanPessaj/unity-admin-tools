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
util.AddNetworkString("gungame_debug_message")
util.AddNetworkString("gungame_options")

-- Server state
local selecting = {}
local points = {}
local spawnPoints = {}
local gungame_players = {}
local gungame_area_center = nil
local gungame_event_active = false
local gungame_area_points = {}
local gungame_respawn_time = {}
local event_starter = nil
local has_winner = false
local event_start_time = 0
local time_limit_timer = nil

-- Función para enviar mensajes de depuración al iniciador del evento
local function DebugMessage(msg)
    if IsValid(event_starter) then
        net.Start("gungame_debug_message")
            net.WriteString(msg)
        net.Send(event_starter)
    end
    print("[GunGame Debug] " .. msg)
end

-- Network receive handler for game options
net.Receive("gungame_options", function(len, ply)
    if not ply:IsAdmin() then return end
    
    local health = net.ReadUInt(16)
    local armor = net.ReadUInt(16)
    local timeLimit = net.ReadUInt(16)
    
    -- Store the options in the global table
    GUNGAME.PlayerHealth = health
    GUNGAME.PlayerArmor = armor
    -- Set time limit (negative means no limit)
    if timeLimit < 0 then
        GUNGAME.TimeLimit = -1  -- No time limit
        DebugMessage(string.format("Game options updated - Health: %d, Armor: %d, Time: No limit", 
            health, armor))
    else
        GUNGAME.TimeLimit = timeLimit * 60  -- Convert minutes to seconds
        DebugMessage(string.format("Game options updated - Health: %d, Armor: %d, Time: %d minutes", 
            health, armor, timeLimit))
    end
end)

-- Función para detener el evento de GunGame
function GUNGAME.StopEvent()
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
    has_winner = false
    
    -- Notificar a los clientes
    net.Start("gungame_event_stopped")
    net.Broadcast()
    net.Start("gungame_update_spawnpoints")
        net.WriteTable({})
    net.Broadcast()
end

-- Función para manejar la victoria de un jugador
local function HandlePlayerWin(ply)
    if not IsValid(ply) or has_winner then return end
    
    has_winner = true
    local winnerName = ply:Nick()
    
    -- Notificar a todos los jugadores
    for _, v in ipairs(player.GetAll()) do
        v:ChatPrint("[GunGame] ¡" .. winnerName .. " ha ganado el GunGame!")
    end
    
    -- Reproducir sonido solo para el ganador
    net.Start("gungame_play_win_sound")
    net.Send(ply)
    
    -- Detener el evento después de 5 segundos
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
        net.SendOmit(sender)
    else
        net.Broadcast()
    end
end
-- Iniciar la selección del área
net.Receive("gungame_area_start", function(_, ply)
    if not IsValid(ply) then return end
    selecting[ply] = true
    points[ply] = table.Copy(gungame_area_points)
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

net.Receive("gungame_sync_weapons", function(_, ply)
    if not IsValid(ply) then return end
    local count = net.ReadUInt(8)
    local weaponsList = {}
    for i = 1, count do
        local weaponID = net.ReadString()
        if weaponID and weaponID ~= "" then
            table.insert(weaponsList, weaponID)
        end
    end
    GUNGAME.Weapons = weaponsList
end)
net.Receive("gungame_clear_weapons", function(len, ply)
    if not IsValid(ply) then return end
    GUNGAME.Weapons = {}
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

-- Función para dar un arma a un jugador según su índice de kill
local function GiveWeaponByKillCount(ply, killCount)
    if not IsValid(ply) then return end
    if not GUNGAME.Weapons or #GUNGAME.Weapons == 0 then return end
    
    -- Usar el operador módulo para hacer un bucle en la lista de armas
    local weaponIndex = (killCount % #GUNGAME.Weapons) + 1
    local weaponClass = GUNGAME.Weapons[weaponIndex]
    
    if weaponClass then
        ply:Give(weaponClass)
    end
end

net.Receive("gungame_start_event", function(_, ply)
    local area = points[ply]
    if not area or #area < GUNGAME.Config.MinPoints then return end

    gungame_area_points = area
    gungame_area_center = GUNGAME.CalculateCenter(area)
    gungame_players = {}
    event_starter = ply

    -- Obtener puntos de spawn dentro del área
    local validSpawnPoints = {}
    for _, spawnPoint in ipairs(spawnPoints) do
        if GUNGAME.PointInPoly2D(spawnPoint.pos, area) then
            table.insert(validSpawnPoints, spawnPoint)
        end
    end
    table.Shuffle(validSpawnPoints)

    local playerCount = 0
    local spawnIndex = 1
    local playersInArea = {}
    
    -- Recolectar a los jugadores en el área
    for _, p in ipairs(player.GetAll()) do
        if GUNGAME.PointInPoly2D(p:GetPos(), area) then
            table.insert(playersInArea, p)
        end
    end
    table.Shuffle(playersInArea)
    
    -- Ahora asignar un spawn point a cada jugador
    for _, p in ipairs(playersInArea) do
        local steamid64 = p:SteamID64()
        if not gungame_players[steamid64] then
            local spawnPoint = validSpawnPoints[spawnIndex]
            if not spawnPoint and #validSpawnPoints > 0 then
                spawnIndex = 1
                spawnPoint = validSpawnPoints[spawnIndex]
            end
            
            gungame_players[steamid64] = {
                player = p,
                kills = 0,
                steamid64 = steamid64,
                weaponIndex = 0,
                spawnPoint = spawnPoint
            }
            playerCount = playerCount + 1
            if spawnPoint then
                p:SetPos(spawnPoint.pos)
                p:SetEyeAngles(spawnPoint.ang or Angle(0, 0, 0))
                spawnIndex = spawnIndex + 1
            end
            
            p:StripWeapons()
            p:SetHealth(GUNGAME.PlayerHealth)
            p:SetArmor(GUNGAME.PlayerArmor)
            if GUNGAME.Weapons and #GUNGAME.Weapons > 0 then
                local firstWeapon = GUNGAME.Weapons[1]
                if firstWeapon then
                    p:Give(firstWeapon)
                end
            end
        end
    end

    gungame_event_active = true
    event_start_time = CurTime()
    has_winner = false
    
    -- Iniciar el temporizador si hay un límite de tiempo
    if GUNGAME.TimeLimit and GUNGAME.TimeLimit >= 0 then
        if IsValid(time_limit_timer) then
            time_limit_timer:Remove()
        end
        
        time_limit_timer = timer.Create("GunGame_TimeLimit", GUNGAME.TimeLimit, 1, function()
            if gungame_event_active then
                -- Buscar al jugador con más kills
                local topPlayer = nil
                local topKills = -1
                
                for _, data in pairs(gungame_players) do
                    if IsValid(data.player) and data.kills > topKills then
                        topKills = data.kills
                        topPlayer = data.player
                    end
                end
                
                -- Si hay un ganador, manejarlo
                if IsValid(topPlayer) then
                    HandlePlayerWin(topPlayer)
                end
                
                -- Notificar solo a los jugadores en el evento
                for _, data in pairs(gungame_players) do
                    if IsValid(data.player) then
                        data.player:ChatPrint("[GunGame] ¡Se ha alcanzado el límite de tiempo!")
                    end
                end

                GUNGAME.StopEvent()
            end
        end)
        
        -- Notificar a los jugadores en el evento sobre el límite de tiempo
        local minutes = math.floor(GUNGAME.TimeLimit / 60)
        for _, data in pairs(gungame_players) do
            if IsValid(data.player) then
                data.player:ChatPrint(string.format("[GunGame] El evento tiene un límite de tiempo de %d minutos.", minutes))
            end
        end
    end
    
    DebugMessage("Event started with " .. table.Count(gungame_players) .. " players")
    for steamid64, data in pairs(gungame_players) do
        local msg = "Player added: " .. data.player:Nick() .. " (SteamID64: " .. steamid64 .. ")"
        if IsValid(event_starter) then
            event_starter:PrintMessage(HUD_PRINTCONSOLE, msg)
        end
    end
    
    for steamid64, data in pairs(gungame_players) do
        if IsValid(data.player) then
            data.player:ChatPrint("[GunGame] ¡El evento ha comenzado!")
        end
    end
end)

net.Receive("gungame_stop_event", function(_, ply)
    for steamid64, data in pairs(gungame_players) do
        if IsValid(data.player) then
            data.player:ChatPrint("[GunGame] ¡El evento ha sido detenido!")
        end
    end
    
    for steamid64, data in pairs(gungame_players) do
        if IsValid(data.player) then
            data.player:StripWeapons()
            data.player:KillSilent()
        end
    end
    
    -- Detener el temporizador si existe
    if IsValid(time_limit_timer) then
        time_limit_timer:Remove()
        time_limit_timer = nil
    end
    
    gungame_players = {}
    gungame_area_center = nil
    gungame_event_active = false
    gungame_area_points = {}
    gungame_respawn_time = {}
    spawnPoints = {}
    event_start_time = 0
    net.Start("gungame_event_stopped")
    net.Broadcast()
    net.Start("gungame_update_spawnpoints")
        net.WriteTable({})
    net.Broadcast()
end)

-- Hooks
-- Función para manejar el respawn de un jugador
local function HandlePlayerRespawn(ply, isImmediate)
    if not IsValid(ply) then return end
    if not gungame_event_active or not gungame_area_center then return end
    
    local steamid64 = ply:SteamID64()
    if not gungame_players[steamid64] then return end
    gungame_respawn_time[steamid64] = CurTime()
    local spawnPos = gungame_area_center
    local spawnAng = Angle(0, math.random(0, 360), 0)
    local spawnData = GUNGAME.GetSpawnPoint()
    if spawnData and spawnData.pos then
        spawnPos = spawnData.pos
        if spawnData.ang then
            spawnAng = spawnData.ang
        end
    end
    if IsValid(ply) and spawnPos then
        if isImmediate then
            ply:SetPos(spawnPos)
            ply:SetEyeAngles(spawnAng)
        else
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
    
    -- Verificar si el jugador está en el evento
    local steamid64 = ply:SteamID64()
    local playerData = gungame_players[steamid64]
    if not playerData then return end
    
    -- Usar GetSpawnPoint para encontrar el mejor lugar para aparecer
    local spawnPoint = GUNGAME.GetSpawnPoint(ply)
    if spawnPoint then
        ply:SetPos(spawnPoint.pos)
        ply:SetEyeAngles(spawnPoint.ang or Angle(0, 0, 0))
    else
        HandlePlayerRespawn(ply, true)
    end
    
    ply:SetHealth(GUNGAME.PlayerHealth)
    ply:SetArmor(GUNGAME.PlayerArmor)
    
    -- Dar armas si es necesario
    if GUNGAME.Weapons and #GUNGAME.Weapons > 0 then
        local weaponIndex = math.min(playerData.level or 1, #GUNGAME.Weapons)
        local weaponClass = GUNGAME.Weapons[weaponIndex]
        
        if weaponClass then
            timer.Simple(0.1, function()
                if IsValid(ply) then
                    ply:StripWeapons()
                    ply:Give(weaponClass)
                    ply:SelectWeapon(weaponClass)
                end
            end)
        end
    end
end)

-- Hook para el respawn después de morir
hook.Add("PlayerSpawn", "gungame_respawn_after_death", function(ply)
    if not IsValid(ply) then return end
    
    -- Establecer vida y armadura al reaparecer después de morir
    if gungame_event_active and gungame_players[ply:SteamID64()] then
        timer.Simple(0.1, function()
            if IsValid(ply) then
                ply:SetHealth(GUNGAME.PlayerHealth or 100)
                ply:SetArmor(GUNGAME.PlayerArmor or 0)
            end
        end)
    end
    if not gungame_event_active or not gungame_area_center then return end
    
    local steamid64 = ply:SteamID64()
    local playerData = gungame_players[steamid64]
    if not playerData then return end
    
    timer.Simple(0.1, function()
        if not IsValid(ply) or not gungame_event_active then return end
            
        -- Usar GetSpawnPoint para encontrar el mejor lugar para aparecer
        local spawnPoint = GUNGAME.GetSpawnPoint(ply)
        if spawnPoint then
            ply:SetPos(spawnPoint.pos)
            ply:SetEyeAngles(spawnPoint.ang or Angle(0, 0, 0))
        else
            HandlePlayerRespawn(ply, false)
        end
        
        -- Dar armas basadas en el nivel actual
        if GUNGAME.Weapons and #GUNGAME.Weapons > 0 then
            local weaponIndex = math.min(playerData.level or 1, #GUNGAME.Weapons)
            local weaponClass = GUNGAME.Weapons[weaponIndex]
            
            if weaponClass then
                ply:StripWeapons()
                ply:Give(weaponClass)
                ply:SelectWeapon(weaponClass)
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
                
                -- Verificar si el jugador está en la penúltima arma (último nivel antes de ganar)
                if gungame_players[attacker_steamid64].level == #GUNGAME.Weapons then
                    local weaponName = weapons.Get(GUNGAME.Weapons[gungame_players[attacker_steamid64].level]) and 
                                     weapons.Get(GUNGAME.Weapons[gungame_players[attacker_steamid64].level]).PrintName or 
                                     GUNGAME.Weapons[gungame_players[attacker_steamid64].level]
                    
                    -- Enviar mensaje a todos los jugadores
                    for steamid64, data in pairs(gungame_players) do
                        if IsValid(data.player) then
                            data.player:ChatPrint("[GunGame] ¡" .. attacker:Nick() .. " está a 1 arma de ganar!")
                        end
                    end
                -- Verificar si el jugador ha alcanzado el nivel máximo (última arma)
                elseif gungame_players[attacker_steamid64].level > #GUNGAME.Weapons then
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
                        end
                    end)
                end
            else
                -- Mostrar progreso hacia la siguiente arma
                local killsNeeded = 1 - gungame_players[attacker_steamid64].kills
                local currentLevel = gungame_players[attacker_steamid64].level or 1
                local nextWeapon = GUNGAME.Weapons[currentLevel + 1] or "Desconocida"
                local weaponName = weapons.Get(nextWeapon) and weapons.Get(nextWeapon).PrintName or nextWeapon
            end
            
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
    
    for steamid64, data in pairs(gungame_players) do
        local ply = data.player
        if IsValid(ply) and ply:Alive() then
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
    net.Start("gungame_area_update_points")
        net.WriteTable(gungame_area_points)
    net.Send(ply)
end

TOOL.Holster = function(self)
    local ply = self:GetOwner()
    selecting[ply] = false
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
end)

net.Receive("gungame_clear_spawnpoints", function(_, ply)
    if gungame_event_active then return end
    
    spawnPoints = {}
    
    -- Update all clients that spawn points have been cleared
    net.Start("gungame_update_spawnpoints")
        net.WriteTable({})
    net.Broadcast()
end)

-- Function to get the best spawn point (prioritize spawns far from other players)
function GUNGAME.GetSpawnPoint(ply)
    if #spawnPoints == 0 then return nil end
    
    local playerCount = table.Count(gungame_players or {})
    if playerCount <= 1 then
        return table.Random(spawnPoints)
    end
    
    local activePlayers = {}
    for steamid64, data in pairs(gungame_players) do
        local p = data.player
        if IsValid(p) and p:Alive() and (not IsValid(ply) or p ~= ply) then
            table.insert(activePlayers, p)
        end
    end
    
    if #activePlayers == 0 then
        return table.Random(spawnPoints)
    end
    
    local shuffledSpawns = table.Copy(spawnPoints)
    table.Shuffle(shuffledSpawns)
    local bestSpawn = nil
    local maxMinDistance = -1
    
    for _, spawn in ipairs(shuffledSpawns) do
        local minDistance = math.huge
        
        for _, otherPlayer in ipairs(activePlayers) do
            local dist = spawn.pos:Distance(otherPlayer:GetPos())
            if dist < minDistance then
                minDistance = dist
            end
        end
        
        if minDistance > maxMinDistance then
            maxMinDistance = minDistance
            bestSpawn = spawn
            
            if maxMinDistance > 2000 then
                return bestSpawn
            end
        end
    end
    
    return bestSpawn or table.Random(spawnPoints)
end

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
