-- Autorun cliente para Modo Evento: gestiona los net messages y reproduce el sonido en TODOS los clientes

MODO_EVENTO = MODO_EVENTO or {}
MODO_EVENTO.SpawnPoints = MODO_EVENTO.SpawnPoints or {}
MODO_EVENTO.IsParticipant = MODO_EVENTO.IsParticipant or false
MODO_EVENTO.EventTitle = MODO_EVENTO.EventTitle or ""
MODO_EVENTO.DisplayTitle = MODO_EVENTO.DisplayTitle or ""
MODO_EVENTO.TitleEntry = MODO_EVENTO.TitleEntry or nil
MODO_EVENTO.ParticipantNames = MODO_EVENTO.ParticipantNames or {}
MODO_EVENTO.OrganizerName = MODO_EVENTO.OrganizerName or ""

if UAT_EnsureFonts then
    UAT_EnsureFonts()
else
    surface.CreateFont("UAT_Circular_48", {
        font = "Circular Std Medium",
        size = 48,
        weight = 800,
        antialias = true,
        extended = true
    })
end

local overlayFont = "UAT_Circular_48"

local overlayAlpha = 0
local overlayBg = Color(18, 18, 20)
local overlayOutline = Color(0, 150, 255)
local overlayText = "EVENTO EN CURSO"

local spawnSphereColor = Color(0, 150, 255, 200)
local spawnCrossColor = Color(255, 255, 255, 200)
local spawnForwardColor = Color(255, 210, 0, 255)

local function drawOverlay(alpha)
    if alpha <= 1 then return end

    local sw, sh = ScrW(), ScrH()
    surface.SetFont(overlayFont)
    local textW, textH = surface.GetTextSize(overlayText)
    local boxW = math.max(math.floor(sw * 0.18), textW + 32)
    local boxH = textH + 24
    local x = (sw - boxW) * 0.5
    local y = math.max(8, math.floor(sh * 0.02))

    local bgColor = Color(overlayBg.r, overlayBg.g, overlayBg.b, math.Clamp(alpha, 0, 200))
    local outlineColor = Color(overlayOutline.r, overlayOutline.g, overlayOutline.b, math.Clamp(alpha + 40, 0, 255))

    surface.SetDrawColor(bgColor)
    surface.DrawRect(x, y, boxW, boxH)
    surface.SetDrawColor(outlineColor)
    surface.DrawOutlinedRect(x, y, boxW, boxH, 2)

    surface.SetTextColor(outlineColor)
    surface.SetTextPos(x + (boxW - textW) * 0.5, y + (boxH - textH) * 0.5)
    surface.DrawText(overlayText)
end

hook.Add("HUDPaint", "MODO_EVENTO_Overlay", function()
    local target = MODO_EVENTO.IsActive and 200 or 0
    overlayAlpha = Lerp(FrameTime() * 6, overlayAlpha, target)
    drawOverlay(overlayAlpha)
end)

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

    if MODO_EVENTO.UpdateUIState then
        MODO_EVENTO.UpdateUIState()
    end
end)

net.Receive("MODO_EVENTO_Sound", function()
    local isStarting = net.ReadBool()
    playEventSound(isStarting)
end)

net.Receive("MODO_EVENTO_UpdateSpawnpoints", function()
    local spawnPoints = net.ReadTable() or {}
    MODO_EVENTO.SpawnPoints = spawnPoints
    if MODO_EVENTO.UpdateUIState then
        MODO_EVENTO.UpdateUIState()
    end
end)

net.Receive("MODO_EVENTO_Participation", function()
    local isParticipant = net.ReadBool()
    MODO_EVENTO.IsParticipant = isParticipant
end)

net.Receive("MODO_EVENTO_SyncParticipants", function()
    local organizerName = net.ReadString() or ""
    local eventTitle = net.ReadString() or ""
    local count = net.ReadUInt(8) or 0
    local names = {}

    for i = 1, count do
        names[i] = net.ReadString() or ""
    end

    MODO_EVENTO.OrganizerName = organizerName
    MODO_EVENTO.DisplayTitle = eventTitle
    MODO_EVENTO.ParticipantNames = names

    if eventTitle ~= "" then
        MODO_EVENTO.EventTitle = eventTitle
        if IsValid(MODO_EVENTO.TitleEntry) then
            MODO_EVENTO.TitleEntry:SetText(eventTitle)
        end
    end

    if MODO_EVENTO.UpdateUIState then
        MODO_EVENTO.UpdateUIState()
    end
end)

local function HasModoEventoTool()
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= "gmod_tool" then return false end

    local tool = ply:GetTool()
    if not tool or tool.Mode ~= "modoevento" then return false end

    return true
end

hook.Add("PostDrawTranslucentRenderables", "MODO_EVENTO_DrawSpawnpoints", function()
    if not HasModoEventoTool() then return end

    local spawnPoints = MODO_EVENTO.SpawnPoints or {}
    if #spawnPoints == 0 then return end

    render.SetColorMaterial()

    for _, data in ipairs(spawnPoints) do
        local pos = data.pos
        if not isvector(pos) and istable(pos) and pos.x and pos.y and pos.z then
            pos = Vector(pos.x, pos.y, pos.z)
        end

        if isvector(pos) then
            local ang = data.ang
            if not isangle(ang) and istable(ang) and ang.p and ang.y and ang.r then
                ang = Angle(ang.p, ang.y, ang.r)
            elseif not isangle(ang) then
                ang = Angle(0, 0, 0)
            end

            render.DrawSphere(pos, 10, 16, 16, spawnSphereColor)

            local size = 10
            render.DrawLine(pos + Vector(-size, 0, 0), pos + Vector(size, 0, 0), spawnCrossColor, true)
            render.DrawLine(pos + Vector(0, -size, 0), pos + Vector(0, size, 0), spawnCrossColor, true)
            render.DrawLine(pos + Vector(0, 0, -size), pos + Vector(0, 0, size), spawnCrossColor, true)

            local forward = ang:Forward() * 20
            render.DrawLine(pos, pos + forward, spawnForwardColor, true)

            local right = ang:Right() * 5
            render.DrawLine(pos + forward, pos + forward * 0.7 + right, spawnForwardColor, true)
            render.DrawLine(pos + forward, pos + forward * 0.7 - right, spawnForwardColor, true)
        end
    end
end)
