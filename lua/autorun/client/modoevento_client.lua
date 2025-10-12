-- Autorun cliente para Modo Evento: gestiona los net messages y reproduce el sonido en TODOS los clientes

MODO_EVENTO = MODO_EVENTO or {}

local function playEventSound(isStarting)
    local wavRel = isStarting and "modoevento/start/eventstartsfx.wav" or "modoevento/stop/eventstopsfx.wav"
    local mp3Rel = isStarting and "modoevento/start/eventstartsfx.mp3" or "modoevento/stop/eventstopsfx.mp3"

    local wavPath = "sound/" .. wavRel
    local mp3Path = "sound/" .. mp3Rel

    if file.Exists(wavPath, "GAME") then
        surface.PlaySound(wavRel)
        return
    end

    -- Fallback: si el WAV aún no está, intenta MP3 (algunos clientes ya lo tienen)
    if file.Exists(mp3Path, "GAME") then
        surface.PlaySound(mp3Rel)
        return
    end

    print("[Modo Evento] Sonidos no encontrados en cliente (WAV/MP3):", wavPath, mp3Path)
end

net.Receive("MODO_EVENTO_Toggle", function()
    local state = net.ReadBool()
    MODO_EVENTO.IsActive = state

    -- Si el botón existe (stool abierto), re-habilitarlo y refrescar
    if IsValid(MODO_EVENTO.ActiveButton) and MODO_EVENTO.ActiveButton.SetEnabled then
        MODO_EVENTO.ActiveButton:SetEnabled(true)
        if MODO_EVENTO.ActiveButton.InvalidateLayout then
            MODO_EVENTO.ActiveButton:InvalidateLayout(true)
        end
    end
end)

net.Receive("MODO_EVENTO_Sound", function()
    local isStarting = net.ReadBool()
    playEventSound(isStarting)
end)