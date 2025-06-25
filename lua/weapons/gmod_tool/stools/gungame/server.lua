AddCSLuaFile("shared.lua")
AddCSLuaFile("client.lua")
include("shared.lua")

-- Función para verificar si el jugador tiene permisos
local function HasGunGameAccess(ply)
    if not IsValid(ply) or not ply.GetUserGroup then return false end
    
    local allowedRanks = {
        ["superadmin"] = true,
        ["moderadorelite"] = true,
        ["moderadorsenior"] = true,
        ["directormods"] = true,
        ["ejecutivo"] = true
    }
    
    return ply:IsSuperAdmin() or (allowedRanks[ply:GetUserGroup():lower()] == true)
end

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
util.AddNetworkString("gungame_debug_message")
util.AddNetworkString("gungame_options")
util.AddNetworkString("gungame_update_top_players")
util.AddNetworkString("GunGame_CreateHologram")
util.AddNetworkString("GunGame_PlayerTouchedHologram")
util.AddNetworkString("GunGame_RemoveHologram")
util.AddNetworkString("gungame_play_pickup_sound")
util.AddNetworkString("gungame_player_won")

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
local top_players_timer = nil
local regenerating_players = {}

-- Función para enviar mensajes de depuración al iniciador del evento
local function DebugMessage(msg)
    if IsValid(event_starter) then
        net.Start("gungame_debug_message")
            net.WriteString(msg)
        net.Send(event_starter)
    end
    print("[GunGame Debug] " .. msg)
end

-- Función para detener la regeneración de un jugador
local function StopPlayerRegeneration(ply)
    if IsValid(ply) and regenerating_players[ply:SteamID64()] then
        regenerating_players[ply:SteamID64()] = nil
    end
end

-- Hook para manejar la regeneración progresiva
hook.Add("Think", "GunGameProgressiveRegen", function()
    if not gungame_event_active or (GUNGAME.RegenOption or 0) ~= 2 then return end
    
    local currentTime = CurTime()
    
    for steamid64, regenData in pairs(regenerating_players) do
        local ply = player.GetBySteamID64(steamid64)
        
        if not IsValid(ply) or not ply:Alive() then
            regenerating_players[steamid64] = nil
            continue
        end
        
        -- Verificar si es momento de la próxima regeneración
        if currentTime >= regenData.nextRegenTime then
            -- Regenerar vida
            local newHealth = math.min(ply:Health() + regenData.amountPerTick, regenData.targetHealth)
            ply:SetHealth(newHealth)
            
            -- Regenerar armadura si es necesario
            if regenData.targetArmor then
                local newArmor = math.min((ply:Armor() or 0) + regenData.amountPerTick, regenData.targetArmor)
                ply:SetArmor(newArmor)
            end
            
            -- Verificar si la regeneración ha terminado
            if newHealth >= regenData.targetHealth and 
               (not regenData.targetArmor or ply:Armor() >= regenData.targetArmor) then
                regenerating_players[steamid64] = nil
            else
                regenerating_players[steamid64].nextRegenTime = currentTime + regenData.interval
            end
        end
    end
end)

-- Detener la regeneración cuando un jugador recibe daño
hook.Add("EntityTakeDamage", "StopRegenOnDamage", function(target, dmg)
    if not gungame_event_active or (GUNGAME.RegenOption or 0) ~= 2 then return end
    
    -- Verificar si el objetivo es un jugador y está en la lista de regeneración
    if target:IsPlayer() and regenerating_players[target:SteamID64()] then
        -- Verificar si el daño es significativo (mayor a 0)
        if dmg:GetDamage() > 0 then
            StopPlayerRegeneration(target)
        end
    end
end)

-- Limpiar la regeneración cuando un jugador muere o se desconecta
hook.Add("PlayerDeath", "StopRegenOnDeath", function(ply)
    StopPlayerRegeneration(ply)
end)

hook.Add("PlayerDisconnected", "CleanupRegenOnDisconnect", function(ply)
    StopPlayerRegeneration(ply)
end)

-- Función para notificar a los clientes sobre el estado del evento
local function UpdateEventStatus(active)
    net.Start("gungame_update_event_status")
        net.WriteBool(active)
        if active then
            net.WriteEntity(event_starter or Entity(0))
            net.WriteUInt(GUNGAME.TimeLimit, 32)
            net.WriteUInt(CurTime(), 32)
        end
    net.Broadcast()
end

-- Network receive handler for game options
net.Receive("gungame_options", function(len, ply)
    if not HasGunGameAccess(ply) then 
        ply:ChatPrint("Error: No tienes permisos para modificar las opciones.")
        return 
    end
    
    local health = net.ReadUInt(16)
    local armor = net.ReadUInt(16)
    local speedMultiplier = net.ReadFloat()
    local timeLimit = net.ReadUInt(16)
    local regenOption = net.ReadUInt(2) -- Read regeneration option (0-3)
    local prizeAmount = net.ReadUInt(32) -- Read prize amount
    
    -- Store the options in the global table
    GUNGAME.PlayerHealth = health
    GUNGAME.PlayerArmor = armor
    GUNGAME.PlayerSpeedMultiplier = math.max(0.1, math.min(10.0, speedMultiplier))
    GUNGAME.RegenOption = regenOption -- Store regeneration option (0: Disabled, 1: Enabled, 2: Slow, 3: Confirmed Kill)
    GUNGAME.PrizeAmount = prizeAmount -- Store the prize amount
    
    if timeLimit < 0 then
        GUNGAME.TimeLimit = -1
    else
        GUNGAME.TimeLimit = timeLimit
        local timeLeft = GUNGAME.TimeLimit - (CurTime() - event_start_time)
        if timeLeft <= 0 then
            timeLeft = 0
        end
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
    
    -- Detener el temporizador de actualización del top de jugadores
    if IsValid(top_players_timer) then
        top_players_timer:Remove()
        top_players_timer = nil
    end
    
    -- Limpiar variables globales
    gungame_players = {}
    gungame_area_center = nil
    
    -- Notificar a los clientes que el evento ha terminado
    if gungame_event_active then
        UpdateEventStatus(false)
    end
    
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
    
    -- Notificar a los jugadores del evento
    for steamid64, _ in pairs(gungame_players) do
        local ply = player.GetBySteamID64(steamid64)
        if IsValid(ply) then
            ply:ChatPrint("[GunGame] ¡" .. winnerName .. " ha ganado el GunGame!")
        end
    end
    
    -- Reproducir sonido solo para el ganador
    net.Start("gungame_play_win_sound")
    net.Send(ply)
    
    -- Detener el evento después de 5 segundos
    timer.Simple(5, function()
        GUNGAME.StopEvent()
        -- Si hay un premio y hay un iniciador del evento, notificarle
        if GUNGAME.PrizeAmount and GUNGAME.PrizeAmount > 0 and IsValid(event_starter) then
            net.Start("gungame_player_won")
                net.WriteEntity(ply)
                net.WriteUInt(GUNGAME.PrizeAmount, 32)
            net.Send(event_starter)
        end
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
    if not HasGunGameAccess(ply) then 
        ply:ChatPrint("Error: No tienes permisos para limpiar el área.")
        return 
    end
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
    if not HasGunGameAccess(ply) then 
        ply:ChatPrint("Error: No tienes permisos para iniciar el evento.")
        return 
    end
    
    local area = points[ply]
    if not area or #area < GUNGAME.Config.MinPoints then 
        ply:ChatPrint("Error: No hay suficientes puntos definidos para el área.")
        return 
    end

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
                level = 1,
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
            
            p:SetWalkSpeed(250 * GUNGAME.PlayerSpeedMultiplier)
            p:SetRunSpeed(500 * GUNGAME.PlayerSpeedMultiplier)
            p:SetSlowWalkSpeed(150 * GUNGAME.PlayerSpeedMultiplier)
        end
    end

    -- Iniciar el evento
    gungame_event_active = true
    event_starter = ply
    event_start_time = CurTime()
    
    -- Iniciar actualización periódica del top de jugadores
    if IsValid(top_players_timer) then
        top_players_timer:Remove()
    end
    
    -- Función para actualizar el top de jugadores
    local function UpdateTopPlayers()
        if not gungame_event_active then return end
        
        -- Crear una tabla temporal para ordenar a los jugadores por nivel
        local playersToSort = {}
        for steamid64, data in pairs(gungame_players) do
            if IsValid(data.player) then
                table.insert(playersToSort, {
                    name = data.player:Nick(),
                    level = data.level or 1
                })
            end
        end
        
        -- Ordenar por nivel (de mayor a menor)
        table.sort(playersToSort, function(a, b)
            return a.level > b.level
        end)
        
        -- Enviar a los clientes
        net.Start("gungame_update_top_players")
            net.WriteUInt(math.min(5, #playersToSort), 8)
            for i = 1, math.min(5, #playersToSort) do
                local playerData = playersToSort[i]
                if playerData then
                    net.WriteBool(true)
                    net.WriteString(playerData.name or "")
                    net.WriteUInt(playerData.level or 1, 16)
                else
                    net.WriteBool(false)
                end
            end
        net.Broadcast()
    end
    
    -- Actualizar cada 2 segundos
    top_players_timer = timer.Create("GunGame_UpdateTopPlayers", 2, 0, UpdateTopPlayers)
    
    -- Primera actualización inmediata
    UpdateTopPlayers()
    has_winner = false
    
    -- Notificar a todos los clientes que el evento ha comenzado
    UpdateEventStatus(true)
    
    -- Iniciar el temporizador solo si hay un límite de tiempo positivo
    if GUNGAME.TimeLimit and GUNGAME.TimeLimit > 0 then
        -- Eliminar cualquier temporizador existente
        if IsValid(time_limit_timer) then
            time_limit_timer:Remove()
            time_limit_timer = nil
        end
        
        -- Crear un temporizador para la notificación de 10 segundos
        local warningTime = GUNGAME.TimeLimit - 15
        if warningTime > 0 then
            timer.Create("GunGame_10SecWarning", warningTime, 1, function()
                if gungame_event_active and not has_winner then
                    -- Enviar sonido de cuenta regresiva a todos los jugadores
                    net.Start("gungame_play_countdown_sound")
                    net.Broadcast()
                end
            end)
        end
        
        -- Crear el temporizador con el límite de tiempo especificado
        time_limit_timer = timer.Create("GunGame_TimeLimit", GUNGAME.TimeLimit, 1, function()
            if gungame_event_active and not has_winner then
                local topPlayers = {}
                local topLevel = -1
                
                -- Encontrar el nivel más alto y todos los jugadores que lo tengan
                for _, data in pairs(gungame_players) do
                    if IsValid(data.player) and data.level ~= nil then
                        if data.level > topLevel then
                            topLevel = data.level
                            topPlayers = {data.player}
                        elseif data.level == topLevel then
                            table.insert(topPlayers, data.player)
                        end
                    end
                end
                
                -- Elegir un jugador al azar de los que tienen el nivel más alto
                local topPlayer = nil
                if #topPlayers > 0 then
                    topPlayer = table.Random(topPlayers)
                end
                
                -- Verificar si hay empate (más de un jugador en el top)
                local isDraw = #topPlayers > 1
                
                -- Si hay un ganador, manejarlo
                if IsValid(topPlayer) then
                    if isDraw then
                        -- Si hay empate, notificar a todos los jugadores
                        local playerNames = {}
                        for _, player in ipairs(topPlayers) do
                            if IsValid(player) then
                                table.insert(playerNames, player:Nick())
                            end
                        end
                        
                        local drawMessage = "[GunGame] ¡Hubo un empate entre " .. table.concat(playerNames, ", ") .. "! Se eligirá un ganador al azar"
                        
                        for _, data in pairs(gungame_players) do
                            if IsValid(data.player) then
                                data.player:ChatPrint("[GunGame] ¡Se ha alcanzado el límite de tiempo!")
                                data.player:ChatPrint(drawMessage)
                            end
                        end
                    else
                        -- Si no hay empate, solo notificar el límite de tiempo
                        for _, data in pairs(gungame_players) do
                            if IsValid(data.player) then
                                data.player:ChatPrint("[GunGame] ¡Se ha alcanzado el límite de tiempo!")
                            end
                        end
                    end
                    
                    -- Manejar al ganador
                    HandlePlayerWin(topPlayer)
                end
                
                -- Detener el evento
                GUNGAME.StopEvent()
            end
        end)
        
        -- Notificar a los jugadores en el evento sobre el límite de tiempo
        local minutes = math.floor(GUNGAME.TimeLimit / 60)
        local seconds = math.Round(GUNGAME.TimeLimit % 60)
        local timeMessage
        
        if minutes > 0 then
            if seconds == 0 then
                timeMessage = string.format("%d minutos", minutes)
            else
                timeMessage = string.format("%d minutos y %d segundos", minutes, seconds)
            end
        else
            timeMessage = string.format("%d segundos", seconds)
        end
        
        for _, data in pairs(gungame_players) do
            if IsValid(data.player) then
                data.player:ChatPrint(string.format("[GunGame] El evento tiene un límite de tiempo de %s.", timeMessage))
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
    if not HasGunGameAccess(ply) then 
        ply:ChatPrint("Error: No tienes permisos para detener el evento.")
        return 
    end
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
    
    -- Aplicar multiplicador de velocidad
    local baseWalkSpeed = 250
    local baseRunSpeed = 500
    local baseSlowWalkSpeed = 150
    
    ply:SetWalkSpeed(baseWalkSpeed * GUNGAME.PlayerSpeedMultiplier)
    ply:SetRunSpeed(baseRunSpeed * GUNGAME.PlayerSpeedMultiplier)
    ply:SetSlowWalkSpeed(baseSlowWalkSpeed * GUNGAME.PlayerSpeedMultiplier)
    
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
    
    -- Establecer vida, armadura y velocidad al reaparecer después de morir
    if gungame_event_active and gungame_players[ply:SteamID64()] then
        timer.Simple(0.1, function()
            if IsValid(ply) then
                ply:SetHealth(GUNGAME.PlayerHealth or 100)
                ply:SetArmor(GUNGAME.PlayerArmor or 0)
                -- Aplicar multiplicador de velocidad
                local baseWalkSpeed = 250
                local baseRunSpeed = 500
                local baseSlowWalkSpeed = 150
                
                ply:SetWalkSpeed(baseWalkSpeed * GUNGAME.PlayerSpeedMultiplier)
                ply:SetRunSpeed(baseRunSpeed * GUNGAME.PlayerSpeedMultiplier)
                ply:SetSlowWalkSpeed(baseSlowWalkSpeed * GUNGAME.PlayerSpeedMultiplier)
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

-- Función para limpiar los hologramas de un jugador
local function ClearPlayerHolograms(steamid64)
    if not gungame_players[steamid64] or not gungame_players[steamid64].holograms then return end
    
    -- Notificar al cliente para que elimine los hologramas
    for holoID, _ in pairs(gungame_players[steamid64].holograms) do
        net.Start("GunGame_RemoveHologram")
            net.WriteString(holoID)
        net.Send(gungame_players[steamid64].player)
    end
    
    -- Limpiar la tabla de hologramas del jugador
    gungame_players[steamid64].holograms = {}
end

-- Hook para manejar las muertes de jugadores
hook.Add("PlayerDeath", "gungame_player_death", function(victim, inflictor, attacker)
    if not gungame_event_active then return end
    
    -- Limpiar los hologramas del jugador que murió
    local victim_steamid64 = victim:SteamID64()
    ClearPlayerHolograms(victim_steamid64)
    
    -- Verificar si el atacante es un jugador válido y no se está suicidando
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
        local attacker_steamid64 = attacker:SteamID64()
        local victim_steamid64 = victim:SteamID64()
        
        -- Verificar si ambos están en el evento
        if gungame_players[attacker_steamid64] and gungame_players[victim_steamid64] then
            -- Incrementar las kills del jugador
            gungame_players[attacker_steamid64].kills = gungame_players[attacker_steamid64].kills + 1
            
            -- Manejar la regeneración según la opción seleccionada
            local regenOption = GUNGAME.RegenOption or 0
            if regenOption == 1 then
                -- Regeneración instantánea
                attacker:SetHealth(GUNGAME.PlayerHealth)
                attacker:SetArmor(GUNGAME.PlayerArmor)
            elseif regenOption == 2 and attacker:Alive() then
                -- Detener cualquier regeneración en curso
                StopPlayerRegeneration(attacker)
                
                -- Configurar regeneración progresiva
                local currentHealth = attacker:Health()
                local maxHealth = GUNGAME.PlayerHealth
                local currentArmor = attacker:Armor() or 0
                local maxArmor = GUNGAME.PlayerArmor or 0
                local healthToRegen = maxHealth - currentHealth
                local armorToRegen = maxArmor - currentArmor
                
                if healthToRegen > 0 or armorToRegen > 0 then
                    regenerating_players[attacker_steamid64] = {
                        targetHealth = maxHealth,
                        targetArmor = maxArmor > 0 and maxArmor or nil, -- Solo regenerar armadura si es mayor a 0
                        amountPerTick = 2, -- Cantidad de vida/armadura por tick
                        interval = 0.1,    -- Intervalo en segundos entre ticks
                        nextRegenTime = CurTime() + 0.05
                    }
                end
            end
            -- Verificar si el jugador sube de nivel
            if gungame_players[attacker_steamid64].kills >= 1 then
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
            
            -- Solo crear holograma si la opción "Confirmed Kill" está activada (regenOption == 3)
            local regenOption = GUNGAME.RegenOption or 0
            if regenOption == 3 then
                -- Crear un holograma en la posición de la víctima
                local hologramPos = victim:GetPos() + Vector(0, 0, 50)
                local endTime = CurTime() + 5
                local holoID = "holo_" .. tostring(CurTime()) .. "_" .. attacker:SteamID64()
                
                -- Inicializar la tabla de hologramas si no existe
                if not gungame_players[attacker_steamid64].holograms then
                    gungame_players[attacker_steamid64].holograms = {}
                end
                
                -- Registrar el holograma
                gungame_players[attacker_steamid64].holograms[holoID] = {
                    pos = hologramPos,
                    time = CurTime()
                }
                
                -- Enviar al cliente del atacante para que cree el holograma
                net.Start("GunGame_CreateHologram")
                    net.WriteVector(hologramPos)
                    net.WriteFloat(endTime)
                    net.WriteString(holoID) -- Enviar el ID al cliente
                net.Send(attacker)
                
                -- Limpiar después de 5 segundos
                timer.Simple(5, function()
                    if gungame_players[attacker_steamid64] and gungame_players[attacker_steamid64].holograms then
                        if gungame_players[attacker_steamid64].holograms[holoID] then
                            gungame_players[attacker_steamid64].holograms[holoID] = nil
                        end
                    end
                end)
            end
        end
    end
end)

-- Manejar cuando un jugador toca un holograma
net.Receive("GunGame_PlayerTouchedHologram", function(_, ply)
    if not IsValid(ply) then return end
    
    local holoID = net.ReadString()
    local steamid64 = ply:SteamID64()
    
    -- Verificar que el jugador esté en el evento y tenga hologramas
    if not gungame_players[steamid64] then return end
    
    -- Inicializar la tabla de hologramas si no existe
    if not gungame_players[steamid64].holograms then
        gungame_players[steamid64].holograms = {}
    end
    
    -- Verificar si el holograma existe
    if gungame_players[steamid64].holograms[holoID] then
        -- Restaurar vida y escudo al máximo
        ply:SetHealth(GUNGAME.PlayerHealth or 100)
        ply:SetArmor(GUNGAME.PlayerArmor or 0)
        
        -- Reproducir sonido de recolección de vida
        net.Start("gungame_play_pickup_sound")
            net.WriteString("items/healthvial.wav")
        net.Send(ply)
        
        gungame_players[steamid64].holograms[holoID] = nil
        
        net.Start("GunGame_RemoveHologram")
            net.WriteString(holoID)
        net.Send(ply)
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
    if not HasGunGameAccess(ply) then 
        ply:ChatPrint("Error: No tienes permisos para añadir puntos de aparición.")
        return 
    end
    
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
    if not HasGunGameAccess(ply) then 
        ply:ChatPrint("Error: No tienes permisos para limpiar los puntos de aparición.")
        return 
    end
    
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
