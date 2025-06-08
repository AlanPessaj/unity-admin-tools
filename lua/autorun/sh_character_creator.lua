CHARACTER_CREATOR = CHARACTER_CREATOR or {}
CHARACTER_CREATOR.Models = {
    Masculino = {
        "models/player/tnb/citizens/male_01.mdl",
        "models/player/tnb/citizens/male_02.mdl",
        "models/player/tnb/citizens/male_03.mdl",
        "models/player/tnb/citizens/male_04.mdl",
        "models/player/tnb/citizens/male_05.mdl",
        "models/player/tnb/citizens/male_06.mdl",
        "models/player/tnb/citizens/male_07.mdl",
        "models/player/tnb/citizens/male_08.mdl",
        "models/player/tnb/citizens/male_09.mdl",
        "models/player/tnb/citizens/male_10.mdl",
        "models/player/tnb/citizens/male_11.mdl",
        "models/player/tnb/citizens/male_12.mdl",
        "models/player/tnb/citizens/male_13.mdl",
        "models/player/tnb/citizens/male_14.mdl",
        "models/player/tnb/citizens/male_15.mdl",
        "models/player/tnb/citizens/male_16.mdl",
        "models/player/tnb/citizens/male_17.mdl",
        "models/player/tnb/citizens/male_18.mdl"
    },
    Femenino = {
        "models/player/tnb/citizens/female_01.mdl",
        "models/player/tnb/citizens/female_02.mdl",
        "models/player/tnb/citizens/female_03.mdl",
        "models/player/tnb/citizens/female_04.mdl",
        "models/player/tnb/citizens/female_06.mdl",
        "models/player/tnb/citizens/female_07.mdl",
        "models/player/tnb/citizens/female_08.mdl",
        "models/player/tnb/citizens/female_09.mdl",
        "models/player/tnb/citizens/female_10.mdl",
        "models/player/tnb/citizens/female_11.mdl",
        
    }
}

if SERVER then
    util.AddNetworkString("character_creator_save_preset")
    util.AddNetworkString("character_creator_request_preset")
    util.AddNetworkString("character_creator_send_preset")
    util.AddNetworkString("character_creator_save_error")
    util.AddNetworkString("character_creator_save_success")

    -- Tabla en memoria para presets (ahora persistente)
    local presets = {}

    -- Función para guardar la tabla en disco
    local function SavePresetsToDisk()
        file.Write("character_creator_presets.txt", util.TableToJSON(presets, true))
    end

    -- Función para cargar la tabla desde disco
    local function LoadPresetsFromDisk()
        if file.Exists("character_creator_presets.txt", "DATA") then
            local json = file.Read("character_creator_presets.txt", "DATA")
            local tbl = util.JSONToTable(json)
            if istable(tbl) then
                presets = tbl
            end
        end
    end

    -- Cargar presets al iniciar
    LoadPresetsFromDisk()

    net.Receive("character_creator_save_preset", function(len, ply)
        local data = net.ReadTable()
        if not istable(data) then return end
        local steamid = ply:SteamID()
        -- Validar nombre único por usuario
        if presets[steamid] and presets[steamid].nombre and presets[steamid].nombre == data.nombre then
            net.Start("character_creator_save_error")
                net.WriteString("Ya tienes un personaje con ese nombre.")
            net.Send(ply)
            return
        end
        presets[steamid] = data
        SavePresetsToDisk()
        net.Start("character_creator_save_success")
        net.Send(ply)
    end)

    net.Receive("character_creator_request_preset", function(len, ply)
        local preset = presets[ply:SteamID()] or nil
        net.Start("character_creator_send_preset")
            net.WriteTable(preset or {})
        net.Send(ply)
    end)
end