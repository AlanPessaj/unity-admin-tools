MODO_EVENTO = MODO_EVENTO or {}

local activeColor = Color(204, 72, 72)
local inactiveColor = Color(72, 160, 72)
local fontName = "UAT_Circular_24"

local function ensureFonts()
    if UAT_EnsureFonts then
        UAT_EnsureFonts()
    end
end

local function updateButtonVisual(button)
    if not IsValid(button) then
        return
    end

    button.CurrentLabel = MODO_EVENTO.IsActive and "Desactivar" or "Activar"
    button.BackgroundColor = MODO_EVENTO.IsActive and activeColor or inactiveColor
    button:InvalidateLayout(true)
end

local function createToggleButton(panel)
    ensureFonts()

    local button = vgui.Create("DButton", panel)
    button:SetText("")
    button:SetTall(90)
    button:Dock(TOP)
    button:DockMargin(0, 0, 0, 8)
    button:SetCursor("hand")

    MODO_EVENTO.ActiveButton = button

    button.OnRemove = function()
        if MODO_EVENTO.ActiveButton == button then
            MODO_EVENTO.ActiveButton = nil
        end
    end

    updateButtonVisual(button)

    button.Paint = function(btn, w, h)
        draw.RoundedBox(12, 0, 0, w, h, btn.BackgroundColor or inactiveColor)
        draw.SimpleText(btn.CurrentLabel or "", fontName, w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    button.DoClick = function(btn)
        local shouldActivate = not MODO_EVENTO.IsActive
        local actionText = shouldActivate and "activar" or "desactivar"

        Derma_Query(
            "¿Estas seguro de " .. actionText .. " el modo evento?",
            "[CGO] Modo Evento",
            "Si",
            function()
                if not IsValid(btn) then return end

                btn:SetEnabled(false)
                MODO_EVENTO.IsActive = shouldActivate
                updateButtonVisual(btn)

                net.Start("MODO_EVENTO_Toggle")
                    net.WriteBool(shouldActivate)
                net.SendToServer()
            end,
            "No"
        )
    end

    return button
end

function MODO_EVENTO.BuildPanel(panel)
    panel:ClearControls()
    panel:DockPadding(8, 0, 8, 8)

    panel:AddControl("Header", {Text = "[CGO] Modo Evento"})

    local spacer = vgui.Create("DPanel", panel)
    spacer:SetTall(20)
    spacer:SetPaintBackground(false)
    if panel.AddItem then
        panel:AddItem(spacer)
    end

    local button = createToggleButton(panel)
    button:DockMargin(0, 8, 0, 8)
    if panel.AddItem then
        panel:AddItem(button)
    else
        button:SetParent(panel)
    end
end

-- Los receptores de red se mueven a autorun/cliente para que funcionen aunque el jugador no tenga el stool abierto.
