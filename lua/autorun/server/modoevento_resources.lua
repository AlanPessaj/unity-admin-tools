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
end
