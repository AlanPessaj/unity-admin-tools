-- [CGO] Modo Evento Tool Definition
TOOL = TOOL or {}
TOOL.Name = "Modo Evento"
TOOL.Category = "CGO Admin Tools"
TOOL.Command = nil
TOOL.ConfigName = ""

local baseDir = "weapons/gmod_tool/stools/modoevento/"

AddCSLuaFile(baseDir .. "shared.lua")
include(baseDir .. "shared.lua")

if SERVER then
    AddCSLuaFile(baseDir .. "client.lua")
    include(baseDir .. "server.lua")
end

local function HasModoEventoAccess(ply)
    return MODO_EVENTO.HasAccess and MODO_EVENTO.HasAccess(ply) or false
end

function TOOL:CanTool(ply)
    return HasModoEventoAccess(ply)
end

if CLIENT then
    language.Add("tool.modoevento.name", "[CGO] Modo Evento")
    language.Add("tool.modoevento.desc", "Creado por AlanPessaj ◢ ◤")
    language.Add("tool.modoevento.0", "Usa el boton para alternar el modo evento.")

    include(baseDir .. "client.lua")

    function TOOL.BuildCPanel(panel)
        if not HasModoEventoAccess(LocalPlayer()) then
            panel:AddControl("Label", {Text = "Acceso denegado."})
            return
        end

        if not MODO_EVENTO.BuildPanel then
            panel:AddControl("Label", {Text = "No se pudo cargar la interfaz."})
            return
        end

        MODO_EVENTO.BuildPanel(panel)
    end
end
