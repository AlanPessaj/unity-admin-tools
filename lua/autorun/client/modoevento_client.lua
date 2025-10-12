-- Autorun cliente para Modo Evento: gestiona los net messages y reproduce el sonido en TODOS los clientes

MODO_EVENTO = MODO_EVENTO or {}

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

    draw.RoundedBox(12, x, y, boxW, boxH, bgColor)
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
end)

net.Receive("MODO_EVENTO_Sound", function()
    local isStarting = net.ReadBool()
    playEventSound(isStarting)
end)
