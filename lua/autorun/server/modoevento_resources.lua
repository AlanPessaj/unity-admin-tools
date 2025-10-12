if SERVER then
    -- 1) Registrar SIEMPRE los sonidos para que los clientes los descarguen al conectar
    local sounds = {
        "modoevento/start/eventstartsfx.wav",
        "modoevento/stop/eventstopsfx.wav",
        -- fallback por si mantienes MP3 además del WAV
        "modoevento/start/eventstartsfx.mp3",
        "modoevento/stop/eventstopsfx.mp3",
    }

    for _, rel in ipairs(sounds) do
        resource.AddFile("sound/" .. rel)
        util.PrecacheSound(rel)
    end
    print("[Modo Evento] Registrados sonidos para descarga (autorun): ", table.concat(sounds, ", "))

    -- 2) Canales de depuración y respuesta
    util.AddNetworkString("MODO_EVENTO_Debug")
    util.AddNetworkString("MODO_EVENTO_Debug_Reply")

    net.Receive("MODO_EVENTO_Debug", function(_, ply)
        if not IsValid(ply) then return end

        local allowdownload = GetConVar("sv_allowdownload")
        local downloadurl = GetConVar("sv_downloadurl")
        local maxfilesize = GetConVar("net_maxfilesize")

        local startWav = "sound/modoevento/start/eventstartsfx.wav"
        local startMp3 = "sound/modoevento/start/eventstartsfx.mp3"
        local stopWav  = "sound/modoevento/stop/eventstopsfx.wav"
        local stopMp3  = "sound/modoevento/stop/eventstopsfx.mp3"

        local startExistsMp3 = file.Exists(startMp3, "GAME")
        local startExistsWav = file.Exists(startWav, "GAME")
        local stopExistsMp3  = file.Exists(stopMp3,  "GAME")
        local stopExistsWav  = file.Exists(stopWav,  "GAME")
        local startSizeMp3   = startExistsMp3 and (file.Size(startMp3, "GAME") or 0) or 0
        local startSizeWav   = startExistsWav and (file.Size(startWav, "GAME") or 0) or 0
        local stopSizeMp3    = stopExistsMp3  and (file.Size(stopMp3,  "GAME") or 0) or 0
        local stopSizeWav    = stopExistsWav  and (file.Size(stopWav,  "GAME") or 0) or 0

        net.Start("MODO_EVENTO_Debug_Reply")
            net.WriteBool(true) -- autorun cargado
            net.WriteString(allowdownload and allowdownload:GetString() or "?")
            net.WriteString(downloadurl and downloadurl:GetString() or "")
            net.WriteUInt(maxfilesize and maxfilesize:GetInt() or 64, 16)
            net.WriteBool(startExistsMp3)
            net.WriteBool(startExistsWav)
            net.WriteBool(stopExistsMp3)
            net.WriteBool(stopExistsWav)
            net.WriteUInt(startSizeMp3, 32)
            net.WriteUInt(startSizeWav, 32)
            net.WriteUInt(stopSizeMp3, 32)
            net.WriteUInt(stopSizeWav, 32)
        net.Send(ply)
    end)
end
