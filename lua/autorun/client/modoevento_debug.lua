-- Comando de depuración para Modo Evento
-- Uso: en consola del cliente, escribe: modoevento_debug

if CLIENT then
    concommand.Add("modoevento_debug", function()
    local startRelW = "modoevento/start/eventstartsfx.wav"
    local stopRelW  = "modoevento/stop/eventstopsfx.wav"
    local startRelM = "modoevento/start/eventstartsfx.mp3"
    local stopRelM  = "modoevento/stop/eventstopsfx.mp3"

        -- Estado local en el cliente
    local cStartW = file.Exists("sound/" .. startRelW, "GAME")
    local cStopW  = file.Exists("sound/" .. stopRelW,  "GAME")
    local cStartM = file.Exists("sound/" .. startRelM, "GAME")
    local cStopM  = file.Exists("sound/" .. stopRelM,  "GAME")
    print(string.format("[Modo Evento][CLIENT] WAV start:%s stop:%s | MP3 start:%s stop:%s", tostring(cStartW), tostring(cStopW), tostring(cStartM), tostring(cStopM)))

    if cStartW then print("[Modo Evento][CLIENT] size start.wav:", file.Size("sound/" .. startRelW, "GAME") or 0) end
    if cStopW  then print("[Modo Evento][CLIENT] size stop.wav:",  file.Size("sound/" .. stopRelW,  "GAME") or 0) end
    if cStartM then print("[Modo Evento][CLIENT] size start.mp3:", file.Size("sound/" .. startRelM, "GAME") or 0) end
    if cStopM  then print("[Modo Evento][CLIENT] size stop.mp3:",  file.Size("sound/" .. stopRelM,  "GAME") or 0) end

        -- Pedir info al servidor
        net.Start("MODO_EVENTO_Debug")
        net.SendToServer()
    end)

    net.Receive("MODO_EVENTO_Debug_Reply", function()
        local autorunLoaded = net.ReadBool()
        local allowdownload = net.ReadString()
        local downloadurl   = net.ReadString()
        local maxfilesize   = net.ReadUInt(16)
        local sMp3          = net.ReadBool()
        local sWav          = net.ReadBool()
        local eMp3          = net.ReadBool()
        local eWav          = net.ReadBool()
        local sMp3Size      = net.ReadUInt(32)
        local sWavSize      = net.ReadUInt(32)
        local eMp3Size      = net.ReadUInt(32)
        local eWavSize      = net.ReadUInt(32)

        print("[Modo Evento][SERVER] autorun:", autorunLoaded)
        print("[Modo Evento][SERVER] sv_allowdownload:", allowdownload)
        print("[Modo Evento][SERVER] sv_downloadurl:", downloadurl ~= "" and downloadurl or "<vacio>")
        print("[Modo Evento][SERVER] net_maxfilesize:", maxfilesize)
        print("[Modo Evento][SERVER] start mp3:", sMp3, "size:", sMp3Size, " start wav:", sWav, "size:", sWavSize)
        print("[Modo Evento][SERVER] stop  mp3:", eMp3, "size:", eMp3Size, " stop  wav:", eWav, "size:", eWavSize)
    end)
end
