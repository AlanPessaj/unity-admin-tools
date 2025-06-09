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
    util.AddNetworkString("character_creator_request_presets_list")
    util.AddNetworkString("character_creator_send_presets_list")
    util.AddNetworkString("character_creator_delete_preset")
    util.AddNetworkString("character_creator_delete_success")
    util.AddNetworkString("character_creator_save_exists") -- NUEVO
    util.AddNetworkString("character_creator_overwrite_preset") -- NUEVO
    util.AddNetworkString("character_creator_apply_model")

    -- Tabla en memoria para presets (ahora persistente y multi-preset)
    local presets = {}

    local function SavePresetsToDisk()
        file.Write("character_creator_presets.txt", util.TableToJSON(presets, true))
    end

    local function LoadPresetsFromDisk()
        if file.Exists("character_creator_presets.txt", "DATA") then
            local json = file.Read("character_creator_presets.txt", "DATA")
            local tbl = util.JSONToTable(json)
            if istable(tbl) then
                presets = tbl
            end
        end
    end

    LoadPresetsFromDisk()

    net.Receive("character_creator_save_preset", function(len, ply)
        local data = net.ReadTable()
        if not istable(data) then return end
        local steamid = ply:SteamID()
        presets[steamid] = presets[steamid] or {}
        -- Validar nombre único por usuario
        for idx, v in ipairs(presets[steamid]) do
            if istable(v) and v.nombre == data.nombre then
                -- Ya existe, avisar al cliente para preguntar si quiere sobrescribir
                net.Start("character_creator_save_exists")
                    net.WriteString(data.nombre)
                    net.WriteTable(data)
                net.Send(ply)
                return
            end
        end
        table.insert(presets[steamid], data)
        SavePresetsToDisk()
        net.Start("character_creator_save_success")
        net.Send(ply)
    end)

    net.Receive("character_creator_overwrite_preset", function(len, ply)
        local data = net.ReadTable()
        if not istable(data) then return end
        local steamid = ply:SteamID()
        presets[steamid] = presets[steamid] or {}
        local found = false
        for idx, v in ipairs(presets[steamid]) do
            if istable(v) and v.nombre == data.nombre then
                presets[steamid][idx] = data
                found = true
                break
            end
        end
        if not found then
            table.insert(presets[steamid], data)
        end
        SavePresetsToDisk()
        net.Start("character_creator_save_success")
        net.Send(ply)
    end)

    net.Receive("character_creator_request_preset", function(len, ply)
        local steamid = ply:SteamID()
        local name = net.ReadString()
        local preset
        if presets[steamid] then
            for _, v in ipairs(presets[steamid]) do
                if v.nombre == name then
                    preset = v
                    break
                end
            end
        end
        net.Start("character_creator_send_preset")
            net.WriteTable(preset or {})
        net.Send(ply)
    end)

    net.Receive("character_creator_request_presets_list", function(len, ply)
        local steamid = ply:SteamID()
        local names = {}
        if presets[steamid] then
            for _, v in ipairs(presets[steamid]) do
                table.insert(names, v.nombre)
            end
        end
        net.Start("character_creator_send_presets_list")
            net.WriteTable(names)
        net.Send(ply)
    end)

    net.Receive("character_creator_delete_preset", function(len, ply)
        local steamid = ply:SteamID()
        local name = net.ReadString()
        if presets[steamid] then
            for i, v in ipairs(presets[steamid]) do
                if v.nombre == name then
                    table.remove(presets[steamid], i)
                    SavePresetsToDisk()
                    break
                end
            end
        end
        net.Start("character_creator_delete_success")
        net.Send(ply)
    end)

    -- Guardar el último modelo y bodygroups aplicados por jugador
    local lastApplied = {}

    net.Receive("character_creator_apply_model", function(len, ply)
        local model = net.ReadString()
        local bodygroups = net.ReadTable()
        if not isstring(model) or model == "" then return end
        ply:SetModel(model)
        if istable(bodygroups) then
            for k, v in pairs(bodygroups) do
                -- Asume que los bodygroups están en el orden correcto
                if isnumber(v) then
                    local bgid = nil
                    if k == "torso" then bgid = 1
                    elseif k == "legs" then bgid = 2
                    elseif k == "hands" then bgid = 3
                    elseif k == "headgear" then bgid = 4
                    end
                    if bgid then
                        ply:SetBodygroup(bgid, v)
                    end
                end
            end
        end
        lastApplied[ply:SteamID()] = {model = model, bodygroups = bodygroups}
    end)

    -- Aplicar modelo y bodygroups tras respawn
    hook.Add("PlayerSpawn", "character_creator_apply_on_spawn", function(ply)
        local data = lastApplied[ply:SteamID()]
        if data and isstring(data.model) and data.model ~= "" then
            timer.Simple(0, function()
                if not IsValid(ply) then return end
                ply:SetModel(data.model)
                if istable(data.bodygroups) then
                    for k, v in pairs(data.bodygroups) do
                        if isnumber(v) then
                            local bgid = nil
                            if k == "torso" then bgid = 1
                            elseif k == "legs" then bgid = 2
                            elseif k == "hands" then bgid = 3
                            elseif k == "headgear" then bgid = 4
                            end
                            if bgid then
                                ply:SetBodygroup(bgid, v)
                            end
                        end
                    end
                end
            end)
        end
    end)
end