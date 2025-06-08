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

    -- Tabla en memoria para presets (puedes guardar en archivo si quieres persistencia)
    local presets = {}

    net.Receive("character_creator_save_preset", function(len, ply)
        local data = net.ReadTable()
        if not istable(data) then return end
        presets[ply:SteamID()] = data
    end)

    net.Receive("character_creator_request_preset", function(len, ply)
        local preset = presets[ply:SteamID()] or nil
        net.Start("character_creator_send_preset")
            net.WriteTable(preset or {})
        net.Send(ply)
    end)
end