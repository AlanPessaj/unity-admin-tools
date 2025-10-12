MODO_EVENTO = MODO_EVENTO or {}

local EVENT_BASE_START = "modoevento/start/eventstartsfx"
local EVENT_BASE_STOP = "modoevento/stop/eventstopsfx"

if SERVER then
    util.AddNetworkString("MODO_EVENTO_Toggle")
    util.AddNetworkString("MODO_EVENTO_Sound")
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
    if not addedStart or not addedStop then
        print("[Modo Evento] Aviso: no se encontró alguno de los sonidos en server para registrar (start/stop)")
    end
end

MODO_EVENTO.IsActive = (CH_Purge and CH_Purge.PhasePaused) or MODO_EVENTO.IsActive or false
local lastSoundState = MODO_EVENTO.IsActive

local function NotifyPlayer(ply, msg)
    if not IsValid(ply) then return end
    ply:ChatPrint("[Modo Evento] " .. msg)
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
        return false, "Solo se puede pausar cuando la purga está en reposo."
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
        NotifyPlayer(ply, "Temporizador de la purga pausado.")
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
        NotifyPlayer(ply, "Temporizador de la purga reanudado.")
        return true
    end

    NotifyPlayer(ply, "No se pudo reanudar la purga en este momento.")
    return false
end

net.Receive("MODO_EVENTO_Toggle", function(_, ply)
	if not MODO_EVENTO.HasAccess or not MODO_EVENTO.HasAccess(ply) then
		return
	end

	local requestedState = net.ReadBool()

	if requestedState then
		if PausePurge(ply) then
			MODO_EVENTO.IsActive = true
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
			hook.Run("ModoEventoToggled", false, ply)
			MODO_EVENTO.BroadcastState()
		else
			net.Start("MODO_EVENTO_Toggle")
				net.WriteBool(MODO_EVENTO.IsActive)
			net.Send(ply)
		end
	end
end)

hook.Add("PlayerInitialSpawn", "ModoEventoSync", function(ply)
    timer.Simple(2, function()
        if not IsValid(ply) then return end
        net.Start("MODO_EVENTO_Toggle")
            net.WriteBool(MODO_EVENTO.IsActive)
        net.Send(ply)
    end)
end)

timer.Simple(0, function()
    if MODO_EVENTO.BroadcastState then
        MODO_EVENTO.BroadcastState()
    end
end)
