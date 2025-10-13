MODO_EVENTO = MODO_EVENTO or {}

local activeColor = Color(204, 72, 72)
local inactiveColor = Color(72, 160, 72)
local fontName = "UAT_Circular_24"
local smallFont = "UAT_Circular_14"

MODO_EVENTO.SpawnPoints = MODO_EVENTO.SpawnPoints or {}
MODO_EVENTO.EventTitle = MODO_EVENTO.EventTitle or ""
MODO_EVENTO.IsParticipant = MODO_EVENTO.IsParticipant or false

local function ensureFonts()
    if UAT_EnsureFonts then
        UAT_EnsureFonts()
    end
end

local function hasSpawnpoints()
    return #(MODO_EVENTO.SpawnPoints or {}) > 0
end

local function hasTitle()
    local title = MODO_EVENTO.EventTitle or ""
    return string.Trim(title) ~= ""
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
    button:SetEnabled(true)

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
        if shouldActivate then
            if not hasTitle() then
                Derma_Message("Debes ingresar un título antes de activar el modo evento.", "[CGO] Modo Evento", "Entendido")
                return
            end

            if not hasSpawnpoints() then
                Derma_Message("Necesitas al menos un spawnpoint definido para activar el modo evento.", "[CGO] Modo Evento", "Entendido")
                return
            end
        end

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
                    if shouldActivate then
                        net.WriteString(MODO_EVENTO.EventTitle or "")
                    end
                net.SendToServer()
            end,
            "No"
        )
    end

    return button
end

local function applyLabelText(label, text)
    if not IsValid(label) then return end
    label:SetText(text or "")
    label:SizeToContents()
end

local function requirementsText()
    local pieces = {}
    table.insert(pieces, "Título: " .. (hasTitle() and "OK" or "Pendiente"))
    table.insert(pieces, "Spawnpoints: " .. (hasSpawnpoints() and "OK" or "Pendiente"))
    return "Requisitos -> " .. table.concat(pieces, " | ")
end

function MODO_EVENTO.UpdateUIState()
    if IsValid(MODO_EVENTO.RequirementsLabel) then
        applyLabelText(MODO_EVENTO.RequirementsLabel, requirementsText())
    end

    if IsValid(MODO_EVENTO.SpawnCountLabel) then
        local count = #(MODO_EVENTO.SpawnPoints or {})
        applyLabelText(MODO_EVENTO.SpawnCountLabel, "Spawnpoints actuales: " .. count)
    end

    if IsValid(MODO_EVENTO.SpawnIndicator) then
        MODO_EVENTO.SpawnIndicator:InvalidateLayout(true)
    end

    if IsValid(MODO_EVENTO.ActiveButton) then
        updateButtonVisual(MODO_EVENTO.ActiveButton)
    end
end

function MODO_EVENTO.BuildPanel(panel)
    panel:ClearControls()
    panel:DockPadding(8, 8, 8, 8)

    panel:AddControl("Header", {Text = "[CGO] Modo Evento"})

    local titleLabel = vgui.Create("DLabel", panel)
    titleLabel:SetFont(smallFont)
    titleLabel:SetTextColor(Color(40, 40, 40))
    titleLabel:SetText("Título del evento")
    titleLabel:Dock(TOP)
    titleLabel:DockMargin(0, 4, 0, 4)
    titleLabel:SizeToContents()
    if panel.AddItem then
        panel:AddItem(titleLabel)
    end

    local titleEntry = vgui.Create("DTextEntry", panel)
    titleEntry:Dock(TOP)
    titleEntry:DockMargin(0, 0, 0, 8)
    titleEntry:SetTall(28)
    titleEntry:SetUpdateOnType(true)
    titleEntry:SetPlaceholderText("Ingresa un título descriptivo")
    titleEntry:SetText(MODO_EVENTO.EventTitle or "")
    titleEntry.OnValueChange = function(self, value)
        MODO_EVENTO.EventTitle = value or ""
        MODO_EVENTO.UpdateUIState()
    end

    if panel.AddItem then
        panel:AddItem(titleEntry)
    end

    local requirementsLabel = vgui.Create("DLabel", panel)
    requirementsLabel:SetFont(smallFont)
    requirementsLabel:SetTextColor(Color(90, 90, 90))
    requirementsLabel:Dock(TOP)
    requirementsLabel:DockMargin(0, 4, 0, 12)
    requirementsLabel:SetText("")
    if panel.AddItem then
        panel:AddItem(requirementsLabel)
    end
    MODO_EVENTO.RequirementsLabel = requirementsLabel

    local spawnHeader = vgui.Create("DPanel", panel)
    spawnHeader:Dock(TOP)
    spawnHeader:SetTall(22)
    spawnHeader:SetPaintBackground(false)
    spawnHeader:DockMargin(0, 0, 0, 4)

    local indicator = vgui.Create("DPanel", spawnHeader)
    indicator:Dock(LEFT)
    indicator:SetWide(22)
    indicator.Paint = function(_, w, h)
        local ready = hasSpawnpoints()
        local col = ready and Color(60, 180, 75) or Color(200, 60, 60)
        draw.RoundedBox(6, 0, 4, w - 4, h - 8, col)
    end
    MODO_EVENTO.SpawnIndicator = indicator

    local spawnTitle = vgui.Create("DLabel", spawnHeader)
    spawnTitle:Dock(FILL)
    spawnTitle:SetFont(smallFont)
    spawnTitle:SetTextColor(Color(40, 40, 40))
    spawnTitle:SetText("Spawnpoints para teletransportes")
    spawnTitle:SetContentAlignment(4)

    if panel.AddItem then
        panel:AddItem(spawnHeader)
    end

    local spawnCount = vgui.Create("DLabel", panel)
    spawnCount:SetFont(smallFont)
    spawnCount:SetTextColor(Color(90, 90, 90))
    spawnCount:Dock(TOP)
    spawnCount:DockMargin(0, 0, 0, 6)
    spawnCount:SetText("")
    if panel.AddItem then
        panel:AddItem(spawnCount)
    end
    MODO_EVENTO.SpawnCountLabel = spawnCount

    local btnAddSpawn = vgui.Create("DButton", panel)
    btnAddSpawn:SetText("Agregar spawnpoint aquí")
    btnAddSpawn:SetFont(smallFont)
    btnAddSpawn:SetTall(28)
    btnAddSpawn:Dock(TOP)
    btnAddSpawn:DockMargin(0, 0, 0, 4)
    btnAddSpawn.DoClick = function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        net.Start("MODO_EVENTO_AddSpawnpoint")
            net.WriteVector(ply:GetPos())
            net.WriteAngle(ply:EyeAngles())
        net.SendToServer()
        surface.PlaySound("buttons/button14.wav")
    end
    if panel.AddItem then
        panel:AddItem(btnAddSpawn)
    end

    local btnClearSpawns = vgui.Create("DButton", panel)
    btnClearSpawns:SetText("Borrar todos los spawnpoints")
    btnClearSpawns:SetFont(smallFont)
    btnClearSpawns:SetTall(28)
    btnClearSpawns:Dock(TOP)
    btnClearSpawns:DockMargin(0, 0, 0, 12)
    btnClearSpawns.DoClick = function()
        Derma_Query(
            "¿Seguro que deseas borrar todos los spawnpoints del modo evento?",
            "[CGO] Modo Evento",
            "Sí",
            function()
                net.Start("MODO_EVENTO_ClearSpawnpoints")
                net.SendToServer()
            end,
            "No"
        )
    end
    if panel.AddItem then
        panel:AddItem(btnClearSpawns)
    end

    local spacer = vgui.Create("DPanel", panel)
    spacer:SetTall(8)
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

    MODO_EVENTO.UpdateUIState()
end

-- Los receptores de red se mueven a autorun/cliente para que funcionen aunque el jugador no tenga el stool abierto.
