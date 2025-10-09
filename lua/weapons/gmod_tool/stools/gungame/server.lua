AddCSLuaFile("shared.lua")
AddCSLuaFile("client.lua")
include("shared.lua")

-- Network strings
util.AddNetworkString("gungame_area_start")
util.AddNetworkString("gungame_area_clear")
util.AddNetworkString("gungame_area_update_points")
util.AddNetworkString("gungame_update_cooldown")
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
util.AddNetworkString("gungame_transfer_prize")
util.AddNetworkString("gungame_update_event_status")
util.AddNetworkString("gungame_validate_weapon")
util.AddNetworkString("gungame_weapon_validated")
util.AddNetworkString("gungame_clear_weapons")
util.AddNetworkString("gungame_play_countdown_sound")
util.AddNetworkString("gungame_play_end_sound")
util.AddNetworkString("gungame_play_kill_sound")
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
util.AddNetworkString("gungame_options")
util.AddNetworkString("gungame_last_weapon")
util.AddNetworkString("gungame_update_event_status")
util.AddNetworkString("gungame_set_button_state")
util.AddNetworkString("gungame_humiliation")
util.AddNetworkString("gungame_restore_visuals")
util.AddNetworkString("gungame_sync_weapon_list")
util.AddNetworkString("gungame_request_weapon_list")

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
local event_starter_sid64 = nil
local has_winner = false
local event_start_time = 0
local time_limit_timer = nil
local top_players_timer = nil
local regenerating_players = {}
local STARTER_COOLDOWN_DURATION = 2 * 60 * 60 -- 2 hours
local STARTER_COOLDOWN_TABLE = "uat_gungame_cooldowns"
local starterCooldowns = {}
local GLOBAL_COOLDOWN_DURATION = 30 * 60 -- 30 minutes
local GLOBAL_COOLDOWN_KEY = "__GLOBAL__"
local globalCooldownExpiry = 0

local function EnsureCooldownTable()
    if not sql or not sql.TableExists then return end
    if sql.TableExists(STARTER_COOLDOWN_TABLE) then return end

    local query = [[
        CREATE TABLE IF NOT EXISTS ]] .. STARTER_COOLDOWN_TABLE .. [[ (
            steamid64 TEXT PRIMARY KEY,
            expires INTEGER NOT NULL
        );
    ]]
    sql.Query(query)
end

local function CleanupGlobalCooldown()
    if not globalCooldownExpiry or globalCooldownExpiry <= 0 then return end
    if globalCooldownExpiry > os.time() then return end

    globalCooldownExpiry = 0
    if sql and sql.TableExists and sql.TableExists(STARTER_COOLDOWN_TABLE) then
        sql.Query("DELETE FROM " .. STARTER_COOLDOWN_TABLE .. " WHERE steamid64 = " .. sql.SQLStr(GLOBAL_COOLDOWN_KEY) .. ";")
    end
end

local function LoadStarterCooldowns()
    starterCooldowns = {}
    EnsureCooldownTable()
    if not sql or not sql.TableExists or not sql.TableExists(STARTER_COOLDOWN_TABLE) then return end

    local rows = sql.Query("SELECT steamid64, expires FROM " .. STARTER_COOLDOWN_TABLE .. ";")
    if not istable(rows) then return end

    local now = os.time()
    for _, row in ipairs(rows) do
        local steam64 = row.steamid64
        local expiry = tonumber(row.expires)
        if steam64 == GLOBAL_COOLDOWN_KEY then
            if expiry and expiry > now then
                globalCooldownExpiry = expiry
            else
                globalCooldownExpiry = 0
                sql.Query("DELETE FROM " .. STARTER_COOLDOWN_TABLE .. " WHERE steamid64 = " .. sql.SQLStr(steam64) .. ";")
            end
        elseif isstring(steam64) and steam64 ~= "" and expiry and expiry > now then
            starterCooldowns[steam64] = expiry
        elseif isstring(steam64) and steam64 ~= "" then
            sql.Query("DELETE FROM " .. STARTER_COOLDOWN_TABLE .. " WHERE steamid64 = " .. sql.SQLStr(steam64) .. ";")
        end
    end
end

local function FormatCooldown(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds <= 0 then return "0 segundos" end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    local parts = {}
    if hours > 0 then
        table.insert(parts, hours .. " hora" .. (hours ~= 1 and "s" or ""))
    end
    if minutes > 0 then
        table.insert(parts, minutes .. " minuto" .. (minutes ~= 1 and "s" or ""))
    end
    if secs > 0 and hours == 0 then
        table.insert(parts, secs .. " segundo" .. (secs ~= 1 and "s" or ""))
    end

    return table.concat(parts, " ")
end

local function SendCooldownToPlayer(ply)
    if not IsValid(ply) then return end

    local steam64 = ply:SteamID64()
    if not steam64 then return end

    local now = os.time()
    CleanupGlobalCooldown()
    local personal = starterCooldowns[steam64]
    if personal and personal <= now then
        starterCooldowns[steam64] = nil
        if sql and sql.TableExists and sql.TableExists(STARTER_COOLDOWN_TABLE) then
            sql.Query("DELETE FROM " .. STARTER_COOLDOWN_TABLE .. " WHERE steamid64 = " .. sql.SQLStr(steam64) .. ";")
        end
        personal = nil
    end

    local expiry = personal
    if globalCooldownExpiry and globalCooldownExpiry > now then
        if not expiry or globalCooldownExpiry > expiry then
            expiry = globalCooldownExpiry
        end
    end

    if expiry and expiry > now then
        local remaining = math.max(0, expiry - now)
        net.Start("gungame_update_cooldown")
            net.WriteBool(true)
            net.WriteUInt(math.min(remaining, 4294967295), 32)
        net.Send(ply)
    else
        net.Start("gungame_update_cooldown")
            net.WriteBool(false)
        net.Send(ply)
    end
end

local function BroadcastCooldownStatus()
    for _, ply in ipairs(player.GetAll()) do
        if HasGunGameAccess(ply) then
            SendCooldownToPlayer(ply)
        end
    end
end

local function ApplyStarterCooldown(steam64)
    if not steam64 or steam64 == "" then return end

    local expiry = os.time() + STARTER_COOLDOWN_DURATION
    starterCooldowns[steam64] = expiry
    if sql and sql.TableExists then
        EnsureCooldownTable()
        sql.Query("REPLACE INTO " .. STARTER_COOLDOWN_TABLE .. " (steamid64, expires) VALUES (" .. sql.SQLStr(steam64) .. ", " .. expiry .. ");")
    end

    local ply = player.GetBySteamID64(steam64)
    if IsValid(ply) then
        SendCooldownToPlayer(ply)
        local message = string.format(
            "[GunGame] Debes esperar %s antes de iniciar otro evento.",
            FormatCooldown(expiry - os.time())
        )
        ply:ChatPrint(message)
    end
end

local function ApplyGlobalCooldown()
    local expiry = os.time() + GLOBAL_COOLDOWN_DURATION
    globalCooldownExpiry = expiry

    if sql and sql.TableExists then
        EnsureCooldownTable()
        sql.Query("REPLACE INTO " .. STARTER_COOLDOWN_TABLE .. " (steamid64, expires) VALUES (" .. sql.SQLStr(GLOBAL_COOLDOWN_KEY) .. ", " .. expiry .. ");")
    end

    BroadcastCooldownStatus()
end

local function ResetAllCooldowns()
    starterCooldowns = {}
    globalCooldownExpiry = 0

    if sql and sql.TableExists and sql.TableExists(STARTER_COOLDOWN_TABLE) then
        sql.Query("DELETE FROM " .. STARTER_COOLDOWN_TABLE .. ";")
    end

    BroadcastCooldownStatus()
end

concommand.Add("gungame_reset_cooldowns", function(ply)
    if IsValid(ply) then
        ply:ChatPrint("Este comando solo puede ejecutarse desde la consola del servidor.")
        return
    end

    ResetAllCooldowns()
    print("[GunGame] Todos los cooldowns han sido restablecidos manualmente.")
end)

LoadStarterCooldowns()

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
local function GetSteamID64Safe(ply)
    if not ply then return nil end

    if isstring(ply) then
        if ply == "" then return nil end

        if util and util.SteamIDTo64 and ply:find("STEAM_") then
            local ok, sid64 = pcall(util.SteamIDTo64, ply)
            if ok and sid64 and sid64 ~= "" then
                return sid64
            end
        end

        if string.sub(ply, 1, 4) == "7656" then
            return ply
        end

        return nil
    end

    local steamid64
    if ply.SteamID64 then
        local ok, sid = pcall(ply.SteamID64, ply)
        if ok then
            steamid64 = sid
        end
    end

    if steamid64 and steamid64 ~= "" then
        return steamid64
    end

    if ply.SteamID and ply.IsPlayer then
        local ok, sid = pcall(ply.SteamID, ply)
        if ok and sid and sid ~= "" and util.SteamIDTo64 then
            local ok64, sid64 = pcall(util.SteamIDTo64, sid)
            if ok64 and sid64 and sid64 ~= "" then
                return sid64
            end
        end
    end

    return nil
end

local function StopPlayerRegeneration(ply)
    local steamid64 = GetSteamID64Safe(ply)
    if steamid64 then
        regenerating_players[steamid64] = nil
    end
end

local function RemoveGunGamePlayer(steamid64)
    if not steamid64 then return false end

    if gungame_players[steamid64] then
        gungame_players[steamid64] = nil
        regenerating_players[steamid64] = nil
        return true
    end

    return false
end

local function CountActiveGunGamePlayers()
    local count = 0
    for steamid64, data in pairs(gungame_players) do
        if data and IsValid(data.player) then
            count = count + 1
        else
            RemoveGunGamePlayer(steamid64)
        end
    end
    return count
end

-- Notifica a todos los jugadores del evento y también al iniciador (event_starter)
-- aunque éste no esté participando (no esté en gungame_players)
local function NotifyGunGamePlayers(message, filterFn)
    if not message or message == "" then return end
    local starterSID64 = IsValid(event_starter) and event_starter.SteamID64 and event_starter:SteamID64() or nil
    local sentStarter = false
    for steamid64, data in pairs(gungame_players) do
        if data and IsValid(data.player) then
            if not filterFn or filterFn(data.player, steamid64, data) then
                data.player:ChatPrint(message)
            end
            if starterSID64 and steamid64 == starterSID64 then
                sentStarter = true
            end
        end
    end
    if IsValid(event_starter) and (not sentStarter) then
        if (not filterFn) or filterFn(event_starter, starterSID64, nil) then
            event_starter:ChatPrint(message)
        end
    end
end

local function HandleGunGameParticipantLeft(ply, steamid64, source)
    if not gungame_event_active then return end

    StopPlayerRegeneration(ply or steamid64)

    local sid64 = steamid64 or GetSteamID64Safe(ply)
    local removed = false

    if sid64 then
        removed = RemoveGunGamePlayer(sid64)
    end

    if not removed and IsValid(ply) then
        local plySteam64 = GetSteamID64Safe(ply)
        if plySteam64 and plySteam64 ~= sid64 then
            sid64 = plySteam64
            removed = RemoveGunGamePlayer(plySteam64)
        end
    end

    if not removed and sid64 then
        for storedSteam64, data in pairs(gungame_players) do
            if data and (storedSteam64 == sid64 or data.steamid64 == sid64) then
                RemoveGunGamePlayer(storedSteam64)
                sid64 = storedSteam64
                removed = true
                break
            end
        end
    end

    if not removed and IsValid(ply) then
        for storedSteam64, data in pairs(gungame_players) do
            if data and data.player == ply then
                RemoveGunGamePlayer(storedSteam64)
                sid64 = storedSteam64
                removed = true
                break
            end
        end
    end

    local remainingPlayers = CountActiveGunGamePlayers()
    local minPlayers = tonumber(GUNGAME.MinPlayersNeeded) or 0

    if remainingPlayers < minPlayers then
        NotifyGunGamePlayers("[GunGame] El evento se detuvo por falta de jugadores.")
        DebugMessage(string.format(
            "Stopping GunGame event: player count dropped a %d jugadores (mínimo requerido %d) [fuente: %s]",
            remainingPlayers,
            minPlayers,
            source or "desconocida"
        ))
        GUNGAME.StopEvent()
    elseif removed then
        DebugMessage(string.format(
            "GunGame participant %s eliminado vía %s. Jugadores restantes: %d",
            tostring(sid64 or "desconocido"),
            source or "desconocida",
            remainingPlayers
        ))
    end
end

-- Handle player disconnection
hook.Add("PlayerDisconnected", "GunGame_PlayerDisconnected", function(ply)
    if not gungame_event_active then return end

    local steamID64 = GetSteamID64Safe(ply)
    DebugMessage(string.format("PlayerDisconnected hook called (steam64: %s)", tostring(steamID64 or "desconocido")))
    HandleGunGameParticipantLeft(ply, steamID64, "PlayerDisconnected hook")
end)

if gameevent and gameevent.Listen then
    gameevent.Listen("player_disconnect")

    hook.Add("player_disconnect", "GunGame_PlayerDisconnected_Event", function(data)
        if not gungame_event_active then return end

        local steamID64 = nil
        local networkID = data.networkid

        if networkID and networkID ~= "" and networkID ~= "BOT" then
            steamID64 = GetSteamID64Safe(networkID)
        end

        local ply = nil
        if data.userid then
            local ent = Player and Player(data.userid) or nil
            if IsValid(ent) then
                ply = ent
                steamID64 = steamID64 or GetSteamID64Safe(ent)
            end
        end

        DebugMessage(string.format(
            "player_disconnect event recibido para %s (steam64: %s)",
            data.name or "desconocido",
            tostring(steamID64 or "desconocido")
        ))

        HandleGunGameParticipantLeft(ply, steamID64, "player_disconnect event")
    end)
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
        ply:ChatPrint("Error: No tienes permisos para usar esta herramienta.")
        return 
    end
    
    local health = net.ReadUInt(16)
    local armor = net.ReadUInt(16)
    local speedMultiplier = net.ReadFloat()
    local timeLimit = net.ReadUInt(16)
    local regenOption = net.ReadUInt(2) -- Read regeneration option (0-3)
    local prizeAmount = net.ReadUInt(32) -- Read prize amount
    local knifeClass = net.ReadString() -- Read knife class
    
    -- Validate knife class (ensure it's a valid weapon)
    if not weapons.Get(knifeClass) then
        knifeClass = ""
    end
    
    -- Store the options in the global table
    GUNGAME.PlayerHealth = health
    GUNGAME.PlayerArmor = armor
    GUNGAME.PlayerSpeedMultiplier = math.max(0.1, math.min(10.0, speedMultiplier))
    GUNGAME.RegenOption = regenOption -- Store regeneration option (0: Disabled, 1: Enabled, 2: Slow, 3: Confirmed Kill)
    GUNGAME.PrizeAmount = prizeAmount -- Store the prize amount
    GUNGAME.KnifeClass = knifeClass -- Store the knife class
    
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

    -- Restaurar armas por defecto y sincronizar con todos los clientes
    if GUNGAME.RestoreDefaultWeapons then
        GUNGAME.RestoreDefaultWeapons()
        if GUNGAME.Weapons then
            net.Start("gungame_sync_weapon_list")
                net.WriteUInt(#GUNGAME.Weapons, 8)
                for _, w in ipairs(GUNGAME.Weapons) do
                    net.WriteString(w)
                end
            net.Broadcast()
        end
    end

    event_starter_sid64 = nil
end

-- Función para manejar la victoria de un jugador
local function HandlePlayerWin(ply)
        -- Enviar lista restaurada a todos
        net.Start("gungame_sync_weapon_list")
            net.WriteUInt(#GUNGAME.Weapons, 8)
            for _, w in ipairs(GUNGAME.Weapons) do
                net.WriteString(w)
            end
        net.Broadcast()
    if not IsValid(ply) or has_winner then return end
    
    has_winner = true
    local winnerName = ply:Nick()

    if event_starter_sid64 then
        ApplyStarterCooldown(event_starter_sid64)
    end
    ApplyGlobalCooldown()
    
    -- Notificar a los jugadores del evento
    NotifyGunGamePlayers("[GunGame] ¡" .. winnerName .. " ha ganado el GunGame!")
    
    -- Reproducir sonido solo para el ganador
    net.Start("gungame_play_end_sound")
    net.WriteEntity(ply)
    net.Broadcast()
    
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
    net.Broadcast()
end)

net.Receive("gungame_sync_weapons", function(_, ply)
    if not IsValid(ply) or not HasGunGameAccess(ply) then return end

    if gungame_event_active then
        ply:ChatPrint("Error: Ya hay un evento de GunGame activo.")
        return
    end

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

-- Responder con la lista de armas actual al cliente que lo solicite
net.Receive("gungame_request_weapon_list", function(_, ply)
    if not IsValid(ply) then return end
    if not HasGunGameAccess(ply) then return end
    local list = GUNGAME.Weapons or {}
    net.Start("gungame_sync_weapon_list")
        net.WriteUInt(#list, 8)
        for _, w in ipairs(list) do
            net.WriteString(w)
        end
    net.Send(ply)

    SendCooldownToPlayer(ply)
end)
net.Receive("gungame_clear_weapons", function(len, ply)
    if not IsValid(ply) then return end
    if gungame_event_active then
        ply:ChatPrint("Error: Ya hay un evento de GunGame activo.")
        return
    end
    -- El usuario pidió que al pulsar Clear se borren todas las armas (lista vacía temporal)
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
        ply:ChatPrint("Error: No tienes permisos para usar esta herramienta.")
        return 
    end
    
    if gungame_event_active then
        ply:ChatPrint("Error: Ya hay un evento de GunGame activo.")
        return
    end
    
    -- Clear points for this player
    selecting[ply] = false
    points[ply] = {}
    
    -- Clear global points and notify all clients
    gungame_area_points = {}
    net.Start("gungame_area_update_points")
        net.WriteTable({})
    net.Broadcast()

    -- Restaurar armas por defecto tras finalizar cualquier evento
    if GUNGAME.RestoreDefaultWeapons then
        GUNGAME.RestoreDefaultWeapons()
    end
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

-- Helper: dar munición al jugador para el arma recién entregada
local function GiveGunGameAmmo(ply, weaponClass)
    if not IsValid(ply) then return end
    if not weaponClass or weaponClass == "" then return end

    local wep = ply:GetWeapon(weaponClass)
    if not IsValid(wep) then
        -- Intentar nuevamente al siguiente tick si aún no existe el arma
        timer.Simple(0, function()
            if IsValid(ply) then
                local w2 = ply:GetWeapon(weaponClass)
                if IsValid(w2) then
                    GiveGunGameAmmo(ply, weaponClass)
                end
            end
        end)
        return
    end

    local desiredPrimary = GUNGAME.DefaultPrimaryAmmo or 90
    local desiredSecondary = GUNGAME.DefaultSecondaryAmmo or 12

    local primaryType = wep:GetPrimaryAmmoType()
    if primaryType and primaryType >= 0 then
        local current = ply:GetAmmoCount(primaryType)
        if current < desiredPrimary then
            ply:SetAmmo(desiredPrimary, primaryType)
        end
    end

    local secondaryType = wep:GetSecondaryAmmoType()
    if secondaryType and secondaryType >= 0 and secondaryType ~= primaryType then
        local current2 = ply:GetAmmoCount(secondaryType)
        if current2 < desiredSecondary then
            ply:SetAmmo(desiredSecondary, secondaryType)
        end
    end
end

net.Receive("gungame_start_event", function(_, ply)
    if not HasGunGameAccess(ply) then 
        ply:ChatPrint("Error: No tienes permisos para usar esta herramienta.")
        return 
    end
    CleanupGlobalCooldown()

    local starterSteam64 = ply:SteamID64()
    if not starterSteam64 or starterSteam64 == "" then
        ply:ChatPrint("No se pudo determinar tu SteamID64. Intenta nuevamente.")
        return
    end

    local now = os.time()
    local cooldownExpiry = starterCooldowns[starterSteam64]
    if cooldownExpiry and cooldownExpiry > now then
        local remaining = cooldownExpiry - now
        ply:ChatPrint(string.format(
            "[GunGame] Debes esperar %s antes de iniciar otro evento.",
            FormatCooldown(remaining)
        ))
        SendCooldownToPlayer(ply)
        return
    elseif cooldownExpiry and cooldownExpiry <= now then
        starterCooldowns[starterSteam64] = nil
        if sql and sql.TableExists and sql.TableExists(STARTER_COOLDOWN_TABLE) then
            sql.Query("DELETE FROM " .. STARTER_COOLDOWN_TABLE .. " WHERE steamid64 = " .. sql.SQLStr(starterSteam64) .. ";")
        end
        SendCooldownToPlayer(ply)
    end

    if globalCooldownExpiry and globalCooldownExpiry > now then
        local remainingGlobal = globalCooldownExpiry - now
        ply:ChatPrint(string.format(
            "[GunGame] Debes esperar %s antes de iniciar un nuevo evento.",
            FormatCooldown(remainingGlobal)
        ))
        SendCooldownToPlayer(ply)
        return
    end
    
    -- Verificar si ya hay un evento activo
    if gungame_event_active and IsValid(event_starter) then
        local starterName = event_starter:Nick()
        ply:ChatPrint("¡Ya hay un evento de GunGame activo iniciado por: " .. starterName)
        return
    end

    net.Start("gungame_set_button_state")
        net.WriteBool(true)
    net.Broadcast()
    
    local area = points[ply]
    if not area or #area < GUNGAME.Config.MinPoints then 
        ply:ChatPrint("Error: No hay suficientes puntos definidos para el área.")
        return 
    end

    gungame_area_points = area
    gungame_area_center = GUNGAME.CalculateCenter(area)
    gungame_players = {}
    event_starter = ply
    event_starter_sid64 = starterSteam64

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
    
    -- Recolectar a los jugadores en el área (excluyendo bots)
    for _, p in ipairs(player.GetAll()) do
        if not IsValid(p) then continue end
        if p:IsBot() then continue end
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
                    GiveGunGameAmmo(p, firstWeapon)
                    if GUNGAME.KnifeClass ~= "" then
                        p:Give(GUNGAME.KnifeClass)
                    end
                    p:SelectWeapon(firstWeapon)
                end
            end
            
            p:SetWalkSpeed(160 * GUNGAME.PlayerSpeedMultiplier)
            p:SetRunSpeed(255 * GUNGAME.PlayerSpeedMultiplier)
            p:SetSlowWalkSpeed(120 * GUNGAME.PlayerSpeedMultiplier)
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
                        
                        NotifyGunGamePlayers("¡Se ha alcanzado el límite de tiempo!")
                        NotifyGunGamePlayers(drawMessage)
                    else
                        -- Si no hay empate, solo notificar el límite de tiempo
                        NotifyGunGamePlayers("[GunGame] ¡Se ha alcanzado el límite de tiempo!")
                    end
                    
                    -- Manejar al ganador
                    HandlePlayerWin(topPlayer)
                end
                
                -- Detener el evento
                RunConsoleCommand("gungame_stop_event")
                
                net.Start("gungame_set_button_state")
                    net.WriteBool(false)
                net.Broadcast()
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
        
        NotifyGunGamePlayers(string.format("[GunGame] El evento tiene un límite de tiempo de %s.", timeMessage))
    end
    DebugMessage("Event started with " .. table.Count(gungame_players) .. " players")
    for steamid64, data in pairs(gungame_players) do
        local msg = "Player added: " .. data.player:Nick() .. " (SteamID64: " .. steamid64 .. ")"
        if IsValid(event_starter) then
            event_starter:PrintMessage(HUD_PRINTCONSOLE, msg)
        end
    end
    
    NotifyGunGamePlayers("[GunGame] ¡El evento ha comenzado!")
end)

net.Receive("gungame_stop_event", function(_, ply)
    if not HasGunGameAccess(ply) then 
        ply:ChatPrint("Error: No tienes permisos para usar esta herramienta.")
        return 
    end
    NotifyGunGamePlayers("[GunGame] ¡El evento ha sido detenido!")
    
    net.Start("gungame_set_button_state")
        net.WriteBool(false)
    net.Broadcast()
    
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
    -- También restaurar armas por defecto cuando se detiene manualmente
    if GUNGAME.RestoreDefaultWeapons then
        GUNGAME.RestoreDefaultWeapons()
        net.Start("gungame_sync_weapon_list")
            net.WriteUInt(#GUNGAME.Weapons, 8)
            for _, w in ipairs(GUNGAME.Weapons) do
                net.WriteString(w)
            end
        net.Broadcast()
    end
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
                    GiveGunGameAmmo(ply, weaponClass)
                    if GUNGAME.KnifeClass ~= "" then
                        ply:Give(GUNGAME.KnifeClass)
                    end
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
                local baseWalkSpeed = 160
                local baseRunSpeed = 255
                local baseSlowWalkSpeed = 120
                
                ply:SetWalkSpeed(baseWalkSpeed * GUNGAME.PlayerSpeedMultiplier)
                ply:SetRunSpeed(baseRunSpeed * GUNGAME.PlayerSpeedMultiplier)
                ply:SetSlowWalkSpeed(baseSlowWalkSpeed * GUNGAME.PlayerSpeedMultiplier)
            end
        end)
        
        -- Forzar eliminación de Babygod inmediatamente
        local function ForceRemoveBabyGod(p)
            if not IsValid(p) then return end
            p.Babygod = nil -- Evita que el override de SetColor siga aplicando alpha 100
            timer.Remove(p:EntIndex() .. "babygod") -- Previene que DarkRP vuelva a tocarlo
            p:GodDisable()
            p:SetRenderMode(RENDERMODE_NORMAL)
            p:SetColor(Color(255,255,255,255))
        end
        -- Ejecutar varias veces para asegurarnos que corra después de DarkRP
        ForceRemoveBabyGod(ply)
        timer.Simple(0, function() ForceRemoveBabyGod(ply) end)
        timer.Simple(0.05, function() ForceRemoveBabyGod(ply) end)
        timer.Simple(0.15, function() ForceRemoveBabyGod(ply) end)

        -- Broadcast a todos los clientes para que actualicen representación de este jugador
        if IsValid(ply) then
            net.Start("gungame_restore_visuals")
                net.WriteEntity(ply)
            net.Broadcast()
        end
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
                GiveGunGameAmmo(ply, weaponClass)
                if GUNGAME.KnifeClass ~= "" then
                    ply:Give(GUNGAME.KnifeClass)
                end
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

            if inflictor:GetClass() == GUNGAME.KnifeClass and gungame_players[victim_steamid64].level > 1 then
                gungame_players[victim_steamid64].level = gungame_players[victim_steamid64].level - 1
                net.Start("gungame_humiliation")
                net.Send(victim)
                NotifyGunGamePlayers("¡Humillación! " .. victim:Nick() .. " ha sido humillado por " .. attacker:Nick())
            end
            
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
                    NotifyGunGamePlayers("[GunGame] " .. attacker:Nick() .. " está a 1 arma de ganar.")
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
                            GiveGunGameAmmo(attacker, weaponID)

                            if GUNGAME.KnifeClass ~= "" then
                                attacker:Give(GUNGAME.KnifeClass)
                            end
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
        ply:ChatPrint("Error: No tienes permisos para usar esta herramienta.")
        return 
    end

    if gungame_event_active then
        ply:ChatPrint("Error: Ya hay un evento de GunGame activo.")
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
        ply:ChatPrint("Error: No tienes permisos para usar esta herramienta.")
        return 
    end
    
    if gungame_event_active then
        ply:ChatPrint("Error: Ya hay un evento de GunGame activo.")
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

            -- Enviar lista de armas actual (defaults si aplica)
            if GUNGAME.Weapons then
                net.Start("gungame_sync_weapon_list")
                    net.WriteUInt(#GUNGAME.Weapons, 8)
                    for _, w in ipairs(GUNGAME.Weapons) do
                        net.WriteString(w)
                    end
                net.Send(ply)
            end
        end
    end)
end)

-- Handle prize money transfer
net.Receive("gungame_transfer_prize", function(_, ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    
    -- Only the event starter can transfer money
    if ply ~= event_starter then return end
    
    local winner = net.ReadEntity()
    local prizeAmount = net.ReadUInt(32)
    
    -- Validate the winner and amount
    if not IsValid(winner) or not winner:IsPlayer() or prizeAmount <= 0 then return end
    
    -- Check if the event starter has enough money
    local starterMoney = ply:getDarkRPVar("money") or 0
    if starterMoney < prizeAmount then
        DarkRP.notify(ply, 1, 5, "No tienes suficiente dinero para este premio.")
        return
    end
    
    -- Take money from the event starter
    ply:addMoney(-prizeAmount)
    
    -- Give money to the winner
    winner:addMoney(prizeAmount)
    
    -- Notify both players
    DarkRP.notify(ply, 3, 5, "Has dado $" .. prizeAmount .. " a " .. winner:Nick())
    DarkRP.notify(winner, 3, 5, "Has recibido $" .. prizeAmount .. " por ganar el GunGame!")

    -- Log the transaction
    print(string.format("[GunGame] %s (%s) gave $%d to %s (%s) as a prize",
        ply:Nick(), ply:SteamID(), prizeAmount, winner:Nick(), winner:SteamID()))
end)
