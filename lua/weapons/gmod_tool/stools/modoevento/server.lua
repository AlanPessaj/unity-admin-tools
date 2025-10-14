MODO_EVENTO = MODO_EVENTO or {}

local EVENT_BASE_START = "modoevento/start/eventstartsfx"
local EVENT_BASE_STOP = "modoevento/stop/eventstopsfx"

MODO_EVENTO.SpawnPoints = MODO_EVENTO.SpawnPoints or {}
MODO_EVENTO.Participants = MODO_EVENTO.Participants or {}
MODO_EVENTO.CurrentTitle = MODO_EVENTO.CurrentTitle or ""
MODO_EVENTO.CurrentVote = MODO_EVENTO.CurrentVote or nil

if SERVER then
    util.AddNetworkString("MODO_EVENTO_Toggle")
    util.AddNetworkString("MODO_EVENTO_Sound")
    util.AddNetworkString("MODO_EVENTO_AddSpawnpoint")
    util.AddNetworkString("MODO_EVENTO_ClearSpawnpoints")
    util.AddNetworkString("MODO_EVENTO_UpdateSpawnpoints")
    util.AddNetworkString("MODO_EVENTO_Participation")
    util.AddNetworkString("MODO_EVENTO_RequestVoteReminder")

    local function addIfExists(rel)
        if file.Exists("sound/" .. rel, "GAME") then
            resource.AddFile("sound/" .. rel)
            util.PrecacheSound(rel)
            return true
        end
        return false
    end

    local addedStart = addIfExists(EVENT_BASE_START .. ".wav") or addIfExists(EVENT_BASE_START .. ".mp3")
    local addedStop  = addIfExists(EVENT_BASE_STOP  .. ".wav") or addIfExists(EVENT_BASE_STOP  .. ".mp3")
end

MODO_EVENTO.IsActive = (CH_Purge and CH_Purge.PhasePaused) or MODO_EVENTO.IsActive or false
local lastSoundState = MODO_EVENTO.IsActive

local function NotifyPlayer(ply, msg)
    if not IsValid(ply) then return end
    ply:ChatPrint("[Modo Evento] " .. msg)
end

local function ReadOptionalString()
    local hasBytes = true
    if net.BytesLeft then
        hasBytes = net.BytesLeft() > 0
    elseif net.BytesRemaining then
        hasBytes = net.BytesRemaining() > 0
    end

    if not hasBytes then return "" end

    local ok, str = pcall(net.ReadString)
    if not ok then return "" end
    return str or ""
end

local function BroadcastSpawnpoints(target)
    local payload = table.Copy(MODO_EVENTO.SpawnPoints or {})
    net.Start("MODO_EVENTO_UpdateSpawnpoints")
        net.WriteTable(payload)
    if IsValid(target) then
        net.Send(target)
    else
        net.Broadcast()
    end
end

local function BroadcastEventSound(isStarting)
	net.Start("MODO_EVENTO_Sound")
		net.WriteBool(isStarting)
	net.Broadcast()
end

function MODO_EVENTO.BroadcastState(forceSound)
	local state = MODO_EVENTO.IsActive and true or false

	if forceSound or state ~= lastSoundState then
		lastSoundState = state
		BroadcastEventSound(state)
	end

	net.Start("MODO_EVENTO_Toggle")
		net.WriteBool(state)
	net.Broadcast()
end

local function CanPausePurge()
    if not CH_Purge or not CH_Purge.PausePhaseTimer then
        return false, "El sistema de purga no está disponible."
    end

    if CH_Purge.CurrentPhase ~= 0 then
        return false, "No puede iniciarse durante la purga."
    end

    if CH_Purge.Config.PurgeMode ~= "Interval" and CH_Purge.CurrentPhase == 0 then
        return false, "El modo de purga actual no utiliza un temporizador para pausar."
    end

    return true
end

local function PausePurge(ply)
    local allowed, reason = CanPausePurge()
    if not allowed then
        if reason then NotifyPlayer(ply, reason) end
        return false
    end

    if CH_Purge.PhasePaused then
        return true
    end

    if CH_Purge.PausePhaseTimer() then
        return true
    end

    NotifyPlayer(ply, "No se pudo pausar la purga en este momento.")
    return false
end

local function ResumePurge(ply)
    if not CH_Purge or not CH_Purge.ResumePhaseTimer then
        NotifyPlayer(ply, "El sistema de purga no está disponible.")
        return false
    end

    if not CH_Purge.PhasePaused then
        NotifyPlayer(ply, "El temporizador de la purga no está pausado.")
        return false
    end

    if CH_Purge.ResumePhaseTimer() then
        return true
    end

    NotifyPlayer(ply, "No se pudo reanudar la purga en este momento.")
    return false
end

local function CountHumanPlayers()
    local count = 0
    for _, client in ipairs(player.GetAll()) do
        if IsValid(client) and not client:IsBot() then
            count = count + 1
        end
    end
    return count
end

local function IsGovernmentJob(ply)
    if not IsValid(ply) or not RPExtraTeams then return false end

    local jobData = RPExtraTeams[ply:Team()]
    if not jobData or not jobData.category then return false end

    local category = string.Trim(jobData.category)
    return string.lower(category) == "gubernamentales"
end

local function ResetParticipants()
    for sid, data in pairs(MODO_EVENTO.Participants or {}) do
        if data and IsValid(data.player) then
            net.Start("MODO_EVENTO_Participation")
                net.WriteBool(false)
            net.Send(data.player)
        end
    end

    MODO_EVENTO.Participants = {}
end

local function RemoveParticipantBySteamID(sid)
    if not sid then return end
    local data = MODO_EVENTO.Participants and MODO_EVENTO.Participants[sid]
    if not data then return end

    if data.player and IsValid(data.player) then
        net.Start("MODO_EVENTO_Participation")
            net.WriteBool(false)
        net.Send(data.player)
    end

    MODO_EVENTO.Participants[sid] = nil
end

local function IsParticipant(ply)
    if not IsValid(ply) then return false end
  	local sid = ply:SteamID64()
    if not sid then return false end
    return MODO_EVENTO.Participants and MODO_EVENTO.Participants[sid] ~= nil
end

local function GetPendingParticipants(exclude)
    local pending = {}
    for _, client in ipairs(player.GetAll()) do
        if IsValid(client) and not client:IsBot() and client ~= exclude and not IsParticipant(client) then
            table.insert(pending, client)
        end
    end
    return pending
end

local function GetBestSpawnPoint(ply)
    local list = MODO_EVENTO.SpawnPoints or {}
    if #list == 0 then return nil end

    local activePlayers = {}
    for sid, data in pairs(MODO_EVENTO.Participants or {}) do
        local participant = data and data.player
        if IsValid(participant) and participant ~= ply and participant:Alive() then
            table.insert(activePlayers, participant)
        end
    end

    if #activePlayers == 0 then
        return table.Random(list)
    end

    local shuffled = table.Copy(list)
    table.Shuffle(shuffled)

    local bestSpawn
    local maxMinDistance = -1

    for _, spawn in ipairs(shuffled) do
        local minDistance = math.huge

        for _, other in ipairs(activePlayers) do
            local dist = spawn.pos:Distance(other:GetPos())
            if dist < minDistance then
                minDistance = dist
            end
        end

        if minDistance > maxMinDistance then
            maxMinDistance = minDistance
            bestSpawn = spawn
            if maxMinDistance > 2000 then
                break
            end
        end
    end

    return bestSpawn or table.Random(list)
end

local function AddParticipant(ply)
    if not IsValid(ply) then return false end
    local sid = ply:SteamID64()
    if not sid or IsParticipant(ply) then return false end

    if IsGovernmentJob(ply) then
        NotifyPlayer(ply, "No puedes participar en el evento con tu trabajo actual.")
        return false
    end

    local spawn = GetBestSpawnPoint(ply)
    if not spawn then
        NotifyPlayer(ply, "No hay spawnpoints disponibles para el evento.")
        return false
    end

    ply:SetPos(spawn.pos)
    if spawn.ang then
        ply:SetEyeAngles(spawn.ang)
    end

    MODO_EVENTO.Participants[sid] = {
        player = ply,
        joinedAt = CurTime(),
        spawn = spawn
    }

    net.Start("MODO_EVENTO_Participation")
        net.WriteBool(true)
    net.Send(ply)

    return true
end

local function BuildVoteExclude(starter)
    local exclude = {}
    if IsValid(starter) then
        exclude[starter] = true
    end

    for _, ply in ipairs(player.GetAll()) do
        if IsParticipant(ply) then
            exclude[ply] = true
        end
    end

    return exclude
end

local function StartParticipationVote(ply, title)
    if not DarkRP or not DarkRP.createVote then
        NotifyPlayer(ply, "No se pudo iniciar la votación (DarkRP.createVote no existe).")
        return false
    end

    local question = string.format("%s\n¿Participar?", title or "Evento")

    local vote = DarkRP.createVote(question, "modoevento_participacion", ply, 20, function() end, BuildVoteExclude(ply))
    if not vote then
        NotifyPlayer(ply, "No se pudo iniciar la votación.")
        return false
    end

    local originalHandle = vote.handleNewVote

    function vote:handleNewVote(voter, choice)
        if choice == "yea" and IsValid(voter) and MODO_EVENTO.IsActive then
            if IsParticipant(voter) or (IsValid(ply) and voter == ply) then
                -- ignored: already in list or starter
            else
                AddParticipant(voter)
            end
        end

        return originalHandle(self, voter, choice)
    end

    MODO_EVENTO.CurrentVote = vote
    return true
end

net.Receive("MODO_EVENTO_AddSpawnpoint", function(_, ply)
    if not MODO_EVENTO.HasAccess or not MODO_EVENTO.HasAccess(ply) then
        return
    end

    if MODO_EVENTO.IsActive then
        NotifyPlayer(ply, "No puedes editar spawnpoints mientras el evento está activo.")
        return
    end

    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    if not pos or not ang then return end

    table.insert(MODO_EVENTO.SpawnPoints, {
        pos = pos,
        ang = ang
    })

    BroadcastSpawnpoints()
end)

net.Receive("MODO_EVENTO_ClearSpawnpoints", function(_, ply)
    if not MODO_EVENTO.HasAccess or not MODO_EVENTO.HasAccess(ply) then
        return
    end

    if MODO_EVENTO.IsActive then
        NotifyPlayer(ply, "No puedes borrar los spawnpoints mientras el evento está activo.")
        return
    end

    MODO_EVENTO.SpawnPoints = {}
    BroadcastSpawnpoints()
end)

net.Receive("MODO_EVENTO_Toggle", function(_, ply)
	if not MODO_EVENTO.HasAccess or not MODO_EVENTO.HasAccess(ply) then
		return
	end

	local requestedState = net.ReadBool()
    local requestedTitle = ""
    if requestedState then
        requestedTitle = ReadOptionalString()
    end

    if requestedState then
        requestedTitle = string.Trim(requestedTitle or "")
        if requestedTitle == "" then
            NotifyPlayer(ply, "Debes ingresar un título para iniciar el evento.")
            net.Start("MODO_EVENTO_Toggle")
                net.WriteBool(false)
            net.Send(ply)
            return
        end

        if not MODO_EVENTO.SpawnPoints or #MODO_EVENTO.SpawnPoints == 0 then
            NotifyPlayer(ply, "Debes agregar al menos un spawnpoint antes de iniciar el evento.")
            net.Start("MODO_EVENTO_Toggle")
                net.WriteBool(false)
            net.Send(ply)
            return
        end

        if CountHumanPlayers() <= 1 then
            NotifyPlayer(ply, "Necesitas al menos otro jugador conectado para iniciar el evento.")
            net.Start("MODO_EVENTO_Toggle")
                net.WriteBool(false)
            net.Send(ply)
            return
        end
    end

	if requestedState then
		if PausePurge(ply) then
            if not StartParticipationVote(ply, requestedTitle) then
                ResumePurge(ply)
                net.Start("MODO_EVENTO_Toggle")
                    net.WriteBool(false)
                net.Send(ply)
                return
            end

			MODO_EVENTO.IsActive = true
            MODO_EVENTO.CurrentTitle = requestedTitle
            ResetParticipants()
			hook.Run("ModoEventoToggled", true, ply)
			MODO_EVENTO.BroadcastState()
		else
			net.Start("MODO_EVENTO_Toggle")
				net.WriteBool(MODO_EVENTO.IsActive)
			net.Send(ply)
		end
	else
		if ResumePurge(ply) then
			MODO_EVENTO.IsActive = false
            MODO_EVENTO.CurrentTitle = ""
            MODO_EVENTO.CurrentVote = nil
            ResetParticipants()
			hook.Run("ModoEventoToggled", false, ply)
			MODO_EVENTO.BroadcastState()
		else
			net.Start("MODO_EVENTO_Toggle")
				net.WriteBool(MODO_EVENTO.IsActive)
			net.Send(ply)
		end
	end
end)

net.Receive("MODO_EVENTO_RequestVoteReminder", function(_, ply)
    if not MODO_EVENTO.HasAccess or not MODO_EVENTO.HasAccess(ply) then
        return
    end

    if not MODO_EVENTO.IsActive then
        NotifyPlayer(ply, "El evento no está activo.")
        return
    end

    local pending = GetPendingParticipants(ply)
    if #pending == 0 then
        NotifyPlayer(ply, "Todos los jugadores ya respondieron o participan.")
        return
    end

    local currentTitle = MODO_EVENTO.CurrentTitle
    if currentTitle == "" then
        currentTitle = "Evento"
    end

    if StartParticipationVote(ply, currentTitle) then
        NotifyPlayer(ply, "Se reenviaron las invitaciones al evento.")
    else
        NotifyPlayer(ply, "No se pudo reenviar la votación en este momento.")
    end
end)

hook.Add("PlayerInitialSpawn", "ModoEventoSync", function(ply)
    timer.Simple(2, function()
        if not IsValid(ply) then return end
        net.Start("MODO_EVENTO_Toggle")
            net.WriteBool(MODO_EVENTO.IsActive)
        net.Send(ply)

        BroadcastSpawnpoints(ply)
        net.Start("MODO_EVENTO_Participation")
            net.WriteBool(IsParticipant(ply))
        net.Send(ply)
    end)
end)

timer.Simple(0, function()
    if MODO_EVENTO.BroadcastState then
        MODO_EVENTO.BroadcastState()
    end
end)

hook.Add("PlayerDisconnected", "ModoEvento_RemoveParticipant", function(ply)
    RemoveParticipantBySteamID(ply and ply:SteamID64())
end)
