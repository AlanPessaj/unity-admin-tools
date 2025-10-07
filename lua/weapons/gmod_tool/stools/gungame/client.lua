include("shared.lua")

-- Client state
local GUNGAME = GUNGAME or {}
GUNGAME.AreaPoints = {}
GUNGAME.AreaPanel = nil
GUNGAME.SpawnPoints = {}
GUNGAME.SpawnPanel = nil
GUNGAME.Weapons = {}
GUNGAME.EventPanel = nil
GUNGAME.EventActive = false
GUNGAME.EventTimeLeft = 0
GUNGAME.EventStartTime = 0
GUNGAME.TopPlayers = {}
local weaponListPanel

-- Language strings
language.Add("tool.gungame.name", "[CGO] GunGame Tool")
language.Add("tool.gungame.desc", "Creado por AlanPessaj ◢ ◤")
language.Add("tool.gungame.0", "Configura las opciones en el menú de la herramienta.")

-- Network receivers
net.Receive("gungame_play_end_sound", function()
    local winSound = "gungame/win/win_sound.mp3"
    local winner = net.ReadEntity()
    if winner == LocalPlayer() then
        if file.Exists("sound/" .. winSound, "GAME") then
            sound.PlayFile("sound/" .. winSound, "noplay", function(station, errorID, errorName)
                if IsValid(station) then
                    station:SetVolume(1)
                    station:Play()
                end
            end)
        end
    else
        if file.Exists("sound/gungame/loose/looseSound.mp3", "GAME") then
            sound.PlayFile("sound/gungame/loose/looseSound.mp3", "noplay", function(station, errorID, errorName)
                if IsValid(station) then
                    station:SetVolume(2)
                    station:Play()
                end
            end)
        end
    end
end)


net.Receive("gungame_set_button_state", function()
    local enabled = net.ReadBool()
    if GUNGAME.SetButtonState and HasGunGameAccess(LocalPlayer()) then
        GUNGAME.SetButtonState(enabled)
    end
end)

net.Receive("gungame_play_kill_sound", function()
    local killSound = "gungame/kill/kill_sound.mp3"
    if file.Exists("sound/" .. killSound, "GAME") then
        sound.PlayFile("sound/" .. killSound, "noplay", function(station, errorID, errorName)
            if IsValid(station) then
                station:SetVolume(2)
                station:Play()
            end
        end)
    end
end)

net.Receive("gungame_humiliation", function()
    local killSound = "gungame/humiliation/humiliationSound.wav"
    if file.Exists("sound/" .. killSound, "GAME") then
        sound.PlayFile("sound/" .. killSound, "noplay", function(station, errorID, errorName)
            if IsValid(station) then
                station:SetVolume(2)
                station:Play()
            end
        end)
    end
end)

-- Handle player won notification with prize
net.Receive("gungame_player_won", function()
    local winner = net.ReadEntity()
    local prizeAmount = net.ReadUInt(32)
    local event_starter_money = LocalPlayer():getDarkRPVar("money") or 0
    
    if not IsValid(winner) or not prizeAmount or prizeAmount <= 0 or winner == LocalPlayer() then return end
    

    if event_starter_money < prizeAmount then
        Derma_Query(
            "You don't have enough money to pay the prize $" .. prizeAmount .. "\n Do you want to give the rest of your money to the winner " .. winner:Nick() .. "?",
            "Confirmation of Prize",
            "Yes", function()
                net.Start("gungame_transfer_prize")
                    net.WriteEntity(winner)
                    net.WriteUInt(event_starter_money, 32)
                net.SendToServer()
            end,
            "No"
        )
    else
        Derma_Query(
            "Do you want to give the prize of $" .. prizeAmount .. " to the winner " .. winner:Nick() .. "?",
            "Confirmation of Prize",
            "Yes", function()
                net.Start("gungame_transfer_prize")
                    net.WriteEntity(winner)
                    net.WriteUInt(prizeAmount, 32)
                net.SendToServer()
            end,
            "No"
        )
    end
end)

-- Reproducir sonido de cuenta regresiva
net.Receive("gungame_play_countdown_sound", function()
    local countdownSound = "gungame/countdown/countdown_sound.mp3"
    if file.Exists("sound/" .. countdownSound, "GAME") then
        sound.PlayFile("sound/" .. countdownSound, "noplay", function(station, errorID, errorName)
            if IsValid(station) then
                station:SetVolume(3)
                station:Play()
            end
        end)
    end
    
    -- Animación de parpadeo del temporizador
    if IsValid(GUNGAME.EventPanel) and IsValid(GUNGAME.EventPanel.TimeLeft) then
        local originalColor = Color(0, 150, 255)
        local flashColor = Color(255, 0, 0)
        local flashCount = 0
        local maxFlashes = 30
        local flashInterval = 0.3
        
        -- Función para alternar el color
        local function ToggleFlash()
            if not IsValid(GUNGAME.EventPanel) or not IsValid(GUNGAME.EventPanel.TimeLeft) then return end
            
            local currentColor = GUNGAME.EventPanel.TimeLeft:GetTextColor()
            local newColor = (currentColor.r == originalColor.r) and flashColor or originalColor
            
            GUNGAME.EventPanel.TimeLeft:SetTextColor(newColor)
            
            flashCount = flashCount + 0.5
            
            if flashCount < maxFlashes then
                timer.Simple(flashInterval, ToggleFlash)
            else
                if IsValid(GUNGAME.EventPanel) and IsValid(GUNGAME.EventPanel.TimeLeft) then
                    GUNGAME.EventPanel.TimeLeft:SetTextColor(originalColor)
                end
            end
        end
        
        -- Iniciar la animación
        ToggleFlash()
    end
end)

-- Recibir mensajes de depuración del servidor
net.Receive("gungame_debug_message", function()
    if not HasGunGameAccess(LocalPlayer()) then return end
    local message = net.ReadString()
    if message then
        LocalPlayer():ChatPrint("[GunGame Debug] " .. message)
        MsgC(Color(0, 255, 255), "[GunGame Debug] ", Color(255, 255, 255), message, "\n")
    end
end)

-- Función para actualizar el panel del top de jugadores
function GUNGAME.UpdateTopPlayersPanel()
    if not IsValid(GUNGAME.EventPanel) or not GUNGAME.TopPlayers then return end
    
    -- Eliminar el panel anterior si existe
    if IsValid(GUNGAME.EventPanel.TopPlayersPanel) then
        GUNGAME.EventPanel.TopPlayersPanel:Remove()
    end
    
    -- Calcular la posición Y basada en si el temporizador está visible o no
    local posY = 40
    if IsValid(GUNGAME.EventPanel.TimeLeft) and GUNGAME.EventPanel.TimeLeft:IsVisible() then
        posY = 70 
    end
    
    -- Crear el panel contenedor
    local topPanel = vgui.Create("DPanel", GUNGAME.EventPanel)
    local playerCount = math.min(5, #GUNGAME.TopPlayers)
    topPanel:SetSize(180, 10 + (playerCount * 20))
    topPanel:SetPos(10, posY)
    topPanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, 180))
    end
    
    -- Lista de jugadores
    for i, data in ipairs(GUNGAME.TopPlayers) do
        if i > 5 then break end
        
        local yPos = 5 + ((i-1) * 20)
        
        -- Fondo de la fila
        local rowBg = vgui.Create("DPanel", topPanel)
        rowBg:SetSize(160, 18)
        rowBg:SetPos(10, yPos)
        rowBg.Paint = function(self, w, h)
            draw.RoundedBox(0, 0, 0, w, h, i % 2 == 0 and Color(50, 50, 50, 120) or Color(70, 70, 70, 120))
        end
        
        -- Posición
        local posLabel = vgui.Create("DLabel", rowBg)
        posLabel:SetText(tostring(i) .. ".")
        posLabel:SetTextColor(Color(255, 255, 255))
    posLabel:SetFont("UAT_Circular_14")
        posLabel:SetSize(20, 18)
        posLabel:SetPos(2, 0)
        posLabel:SetContentAlignment(4)
        
        -- Nombre
        local nameLabel = vgui.Create("DLabel", rowBg)
        nameLabel:SetText(data.name or "")
        nameLabel:SetTextColor(Color(255, 255, 255))
    nameLabel:SetFont("UAT_Circular_13")
        nameLabel:SetSize(100, 18)
        nameLabel:SetPos(25, 0)
        nameLabel:SetContentAlignment(4)
        
        -- Nivel
        local levelLabel = vgui.Create("DLabel", rowBg)
        levelLabel:SetText(tostring(data.level-1 or 0))
        levelLabel:SetTextColor(Color(100, 255, 100))
    levelLabel:SetFont("UAT_Circular_14")
        levelLabel:SetSize(40, 18)
        levelLabel:SetPos(110, 0)
        levelLabel:SetContentAlignment(6)
    end
    
    GUNGAME.EventPanel.TopPlayersPanel = topPanel
    
    -- Ajustar tamaño del panel principal si es necesario
    local baseHeight = 60
    if IsValid(GUNGAME.EventPanel.TimeLeft) and GUNGAME.EventPanel.TimeLeft:IsVisible() then
        baseHeight = 70
    end
    local totalHeight = baseHeight + topPanel:GetTall() + 10
    GUNGAME.EventPanel:SetSize(200, totalHeight)
end

-- Función para actualizar el panel de evento
local function UpdateEventPanel(active, eventStarter, timeLimit, startTime)

    if IsValid(GUNGAME.EventPanel) then
        GUNGAME.EventPanel:Remove()
    end

    if active then
        GUNGAME.EventPanel = vgui.Create("DPanel")
        GUNGAME.EventPanel:SetSize(200, 100)
        GUNGAME.EventPanel:SetPos(20, 20)
        GUNGAME.EventPanel:SetDrawBackground(true)
        GUNGAME.EventPanel.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(0, 0, 0, 200))
            surface.SetDrawColor(0, 0, 255, 150)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
        end
        
        -- Título centrado
        GUNGAME.EventPanel.Title = vgui.Create("DLabel", GUNGAME.EventPanel)
        GUNGAME.EventPanel.Title:SetText("GunGame")
    GUNGAME.EventPanel.Title:SetFont("UAT_Circular_24")
        GUNGAME.EventPanel.Title:SetTextColor(Color(255, 255, 255))
        GUNGAME.EventPanel.Title:SetContentAlignment(5)
        GUNGAME.EventPanel.Title:SetSize(180, 30)
        GUNGAME.EventPanel.Title:SetPos(10, 5)
        
        -- Tiempo centrado
        GUNGAME.EventPanel.TimeLeft = vgui.Create("DLabel", GUNGAME.EventPanel)
        GUNGAME.EventPanel.TimeLeft:SetText("--:--")
    GUNGAME.EventPanel.TimeLeft:SetFont("UAT_Circular_24")
        GUNGAME.EventPanel.TimeLeft:SetTextColor(Color(0, 150, 255))
        GUNGAME.EventPanel.TimeLeft:SetContentAlignment(5)
        GUNGAME.EventPanel.TimeLeft:SetSize(180, 50)
        GUNGAME.EventPanel.TimeLeft:SetPos(67.5, 30)
        
        -- Mostrar/ocultar según el tiempo límite
        if timeLimit and timeLimit > 0 then
            GUNGAME.EventTimeLeft = timeLimit
            GUNGAME.EventStartTime = startTime or CurTime()
            GUNGAME.EventPanel.TimeLeft:SetVisible(true)
        else
            GUNGAME.EventTimeLeft = 0
            GUNGAME.EventPanel.TimeLeft:SetVisible(false)
        end

        -- Animación de entrada
        GUNGAME.EventPanel:SetAlpha(0)
        GUNGAME.EventPanel:AlphaTo(255, 0.5, 0)
        
        -- Crear panel de top jugadores
        if #GUNGAME.TopPlayers > 0 then
            GUNGAME.UpdateTopPlayersPanel()
        end
    elseif IsValid(GUNGAME.EventPanel) and not active then
        if IsValid(GUNGAME.EventPanel.TopPlayersPanel) then
            GUNGAME.EventPanel.TopPlayersPanel:Remove()
            GUNGAME.EventPanel.TopPlayersPanel = nil
        end
    end
    
    -- Actualizar estado del evento
    GUNGAME.EventActive = active
    if active then
        GUNGAME.EventTimeLeft = timeLimit or 0
        GUNGAME.EventStartTime = startTime or CurTime()
    end
end

-- Recibir actualizaciones del estado del evento
net.Receive("gungame_update_event_status", function()
    local active = net.ReadBool()
    local eventStarter = nil
    local timeLimit = 0
    local startTime = 0
    
    if active then
        eventStarter = net.ReadEntity()
        timeLimit = net.ReadUInt(32)
        startTime = net.ReadUInt(32)
    end
    
    UpdateEventPanel(active, eventStarter, timeLimit, startTime)
end)

-- Hook para dibujar el tiempo restante
hook.Add("HUDPaint", "GunGame_EventHUD", function()
    if not GUNGAME.EventActive then
        -- Asegurarse de que el panel se elimine si por alguna razón sigue existiendo
        if IsValid(GUNGAME.EventPanel) then
            GUNGAME.EventPanel:Remove()
            GUNGAME.EventPanel = nil
        end
        return 
    end
    
    if not IsValid(GUNGAME.EventPanel) then return end
    
    -- Actualizar tiempo restante
    if GUNGAME.EventTimeLeft > 0 then
        local timeElapsed = CurTime() - GUNGAME.EventStartTime
        local timeLeft = math.max(0, GUNGAME.EventTimeLeft - timeElapsed)
        
        local minutes = math.floor(timeLeft / 60)
        local seconds = math.floor(timeLeft % 60)
        
        if IsValid(GUNGAME.EventPanel.TimeLeft) then
            GUNGAME.EventPanel.TimeLeft:SetText(string.format("%02d:%02d", minutes, seconds))
            GUNGAME.EventPanel.TimeLeft:SizeToContents()
        end
    end
    
    -- Actualizar contador de jugadores
    if IsValid(GUNGAME.EventPanel.Players) then
        local playerCount = CountPlayersInArea()
        GUNGAME.EventPanel.Players:SetText("Jugadores: " .. playerCount)
        GUNGAME.EventPanel.Players:SizeToContents()
    end
end)

-- Limpiar el panel al desconectarse
hook.Add("OnReloaded", "GunGame_CleanupEventPanel", function()
    if IsValid(GUNGAME.EventPanel) then
        GUNGAME.EventPanel:Remove()
        GUNGAME.EventPanel = nil
    end
    GUNGAME.EventActive = false
end)

net.Receive("gungame_area_update_points", function()
    if not HasGunGameAccess(LocalPlayer()) then return end
    GUNGAME.AreaPoints = net.ReadTable() or {}
    -- Update the panel if it exists
    if IsValid(GUNGAME.AreaPanel) then
        GUNGAME.AreaPanel:InvalidateLayout(true)
    end
    hook.Run("GunGame_AreaUpdated")
end)

net.Receive("gungame_update_spawnpoints", function()
    if not HasGunGameAccess(LocalPlayer()) then return end
    GUNGAME.SpawnPoints = net.ReadTable() or {}
    if IsValid(GUNGAME.SpawnPanel) then
        GUNGAME.SpawnPanel:InvalidateLayout(true)
    end
end)

net.Receive("gungame_event_stopped", function()
    if not HasGunGameAccess(LocalPlayer()) then return end
    GUNGAME.SpawnPoints = {}
    if GUNGAME.SetButtonState then
        GUNGAME.SetButtonState(false)
    end
    
    -- Cerrar el panel del evento si está abierto
    if IsValid(GUNGAME.EventPanel) then
        GUNGAME.EventPanel:Remove()
        GUNGAME.EventPanel = nil
    end
    
    -- Limpiar el estado del evento
    GUNGAME.EventActive = false
    GUNGAME.EventTimeLeft = 0
    GUNGAME.EventStartTime = 0
end)

-- Función para actualizar la lista de armas en la UI
local function UpdateWeaponList()
    if not HasGunGameAccess(LocalPlayer()) then return end
    if not IsValid(weaponListPanel) then return end
    weaponListPanel:Clear()
    
    for _, weaponID in ipairs(GUNGAME.Weapons or {}) do
        local label = weaponListPanel:Add("DLabel")
        label:SetText(weaponID)
        label:Dock(TOP)
        label:DockMargin(0, 2, 0, 2)
        label:SetTextColor(Color(40, 40, 40))
    end
end

-- Función para sincronizar la lista de armas con el servidor
local function SyncWeaponsWithServer()
    if not HasGunGameAccess(LocalPlayer()) then return end
    net.Start("gungame_sync_weapons")
        net.WriteUInt(#GUNGAME.Weapons, 8)
        for _, weaponID in ipairs(GUNGAME.Weapons) do
            net.WriteString(weaponID or "")
        end
    net.SendToServer()
end

-- Función para limpiar la lista de armas
local function ClearWeaponList()
    if not HasGunGameAccess(LocalPlayer()) then return end
    GUNGAME.Weapons = {}
    if IsValid(weaponListPanel) then
        weaponListPanel:Clear()
    end
    SyncWeaponsWithServer()
end



net.Receive("gungame_weapon_validated", function()
    if not HasGunGameAccess(LocalPlayer()) then return end
    local isValid = net.ReadBool()
    local weaponID = net.ReadString()
    
    if isValid then
        table.insert(GUNGAME.Weapons, weaponID)
        UpdateWeaponList()
        notification.AddLegacy("Added weapon: " .. weaponID, NOTIFY_GENERIC, 2)
        SyncWeaponsWithServer()
        hook.Run("GunGame_WeaponsUpdated")
    else
        notification.AddLegacy("Invalid weapon: " .. weaponID, NOTIFY_ERROR, 2)
    end
end)

net.Receive("gungame_clear_weapons", function()
    if not HasGunGameAccess(LocalPlayer()) then return end
    ClearWeaponList()
    hook.Run("GunGame_WeaponsUpdated")
end)

-- Recibir actualización del top de jugadores
net.Receive("gungame_update_top_players", function()
    local count = net.ReadUInt(8)
    GUNGAME.TopPlayers = {}
    
    for i = 1, count do
        if net.ReadBool() then
            local name = net.ReadString()
            local level = net.ReadUInt(16)
            GUNGAME.TopPlayers[i] = {name = name, level = level}
        end
    end
    
    -- Actualizar el panel si está activo
    if IsValid(GUNGAME.EventPanel) and GUNGAME.EventActive then
        GUNGAME.UpdateTopPlayersPanel()
    end
end)

-- La función BuildCPanel ha sido movida al archivo principal de la herramienta

-- Esta función se usará para construir la interfaz de usuario
local function CreateGunGameUI(panel)
    if CLIENT and UAT_EnsureFonts then UAT_EnsureFonts() end
    -- Header
    local headerPanel = vgui.Create("DPanel", panel)
    headerPanel:Dock(TOP)
    headerPanel:SetTall(32)
    headerPanel:SetPaintBackground(false)

    -- Status circle
    local circle = vgui.Create("DPanel", headerPanel)
    circle:Dock(LEFT)
    circle:SetWide(28)
    circle.Paint = function(self, w, h)
        local points = GUNGAME.AreaPoints or {}
        local color = (#points >= 4) and Color(0, 200, 0) or Color(200, 0, 0)
        draw.RoundedBox(8, 6, 6, 20, 20, color)
    end

    -- Header label
    local label = vgui.Create("DLabel", headerPanel)
    label:Dock(LEFT)
    label:DockMargin(8, 0, 0, 0)
    label:SetText("Set the game area")
    label:SetFont("UAT_Circular_14")
    label:SetTextColor(Color(40, 40, 40))
    label:SizeToContents()

    -- Panel styling
    panel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(255, 255, 255, 245))
        surface.SetDrawColor(180, 180, 180, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
    end

    -- Select area button
    local btnSelect = vgui.Create("DButton", panel)
    btnSelect:SetText("Select area")
    btnSelect:Dock(TOP)
    btnSelect:DockMargin(0, 8, 0, 4)
    btnSelect:SetTall(28)
    btnSelect:SetFont("UAT_Circular_14")
    btnSelect:SetWide(panel:GetWide() - 16)
    btnSelect.DoClick = function()
        RunConsoleCommand("gungame_area_start")
    end

    -- Delete selection button
    local btnDelete = vgui.Create("DButton", panel)
    btnDelete:SetText("Delete selection")
    btnDelete:Dock(TOP)
    btnDelete:DockMargin(0, 4, 0, 16)
    btnDelete:SetTall(28)
    btnDelete:SetFont("UAT_Circular_14")
    btnDelete:SetWide(panel:GetWide() - 16)
    btnDelete.DoClick = function()
        net.Start("gungame_area_clear")
        net.SendToServer()
        GUNGAME.AreaPoints = {}
        hook.Run("GunGame_AreaUpdated")
    end

    -- Spawn Points Section
    local spawnHeader = vgui.Create("DPanel", panel)
    spawnHeader:Dock(TOP)
    spawnHeader:DockMargin(0, 24, 0, 0)
    spawnHeader:SetTall(32)
    spawnHeader:SetPaintBackground(false)

    local spawnCircle = vgui.Create("DPanel", spawnHeader)
    spawnCircle:Dock(LEFT)
    spawnCircle:SetWide(28)
    spawnCircle.Paint = function(self, w, h)
        local hasPoints = #(GUNGAME.SpawnPoints or {}) > 0
        local color = hasPoints and Color(0, 200, 0) or Color(200, 0, 0)
        draw.RoundedBox(8, 6, 6, 20, 20, color)
    end

    local spawnLabel = vgui.Create("DLabel", spawnHeader)
    spawnLabel:Dock(LEFT)
    spawnLabel:DockMargin(8, 0, 0, 0)
    spawnLabel:SetText("Spawn Points (at least one per player)")
    spawnLabel:SetFont("UAT_Circular_14")
    spawnLabel:SetTextColor(Color(40, 40, 40))
    spawnLabel:SizeToContents()

    local btnAddSpawn = vgui.Create("DButton", panel)
    btnAddSpawn:SetText("Add Spawn Point")
    btnAddSpawn:Dock(TOP)
    btnAddSpawn:DockMargin(0, 8, 0, 4)
    btnAddSpawn:SetTall(28)
    btnAddSpawn:SetFont("UAT_Circular_14")
    btnAddSpawn:SetWide(panel:GetWide() - 16)
    btnAddSpawn.DoClick = function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        
        -- Obtener posición y ángulo del jugador
        local pos = ply:GetPos()
        local ang = ply:EyeAngles()
        
        net.Start("gungame_add_spawnpoint")
            net.WriteVector(pos)
            net.WriteAngle(ang)
        net.SendToServer()
        notification.AddLegacy("Spawn point agregado!", NOTIFY_GENERIC, 2)
        surface.PlaySound("buttons/button14.wav")
    end

    local btnClearSpawns = vgui.Create("DButton", panel)
    btnClearSpawns:SetText("Clear Spawn Points")
    btnClearSpawns:Dock(TOP)
    btnClearSpawns:DockMargin(0, 4, 0, 16)
    btnClearSpawns:SetTall(28)
    btnClearSpawns:SetFont("UAT_Circular_14")
    btnClearSpawns:SetWide(panel:GetWide() - 16)
    btnClearSpawns.DoClick = function()
        net.Start("gungame_clear_spawnpoints")
        net.SendToServer()
    end

    -- Weapons Section
    local weaponsHeader = vgui.Create("DPanel", panel)
    weaponsHeader:Dock(TOP)
    weaponsHeader:DockMargin(0, 24, 0, 0)
    weaponsHeader:SetTall(32)
    weaponsHeader:SetPaintBackground(false)
    
    local weaponsLabel = vgui.Create("DLabel", weaponsHeader)
    weaponsLabel:Dock(LEFT)
    weaponsLabel:DockMargin(0, 0, 0, 0)
    weaponsLabel:SetText("Weapons")
    weaponsLabel:SetFont("UAT_Circular_14")
    weaponsLabel:SetTextColor(Color(40, 40, 40))
    weaponsLabel:SizeToContents()

    -- Weapons input container
    local weaponsInputContainer = vgui.Create("DPanel", panel)
    weaponsInputContainer:Dock(TOP)
    weaponsInputContainer:DockMargin(0, 4, 0, 4)
    weaponsInputContainer:SetTall(28)
    weaponsInputContainer:SetPaintBackground(false)
    
    -- Text entry for weapon class
    local weaponEntry = vgui.Create("DTextEntry", weaponsInputContainer)
    weaponEntry:Dock(FILL)
    weaponEntry:SetPlaceholderText("Weapon ID")
    weaponEntry:SetUpdateOnType(true)
    
    -- Button container for the two square buttons
    local buttonContainer = vgui.Create("DPanel", weaponsInputContainer)
    buttonContainer:Dock(RIGHT)
    buttonContainer:SetWide(60)
    buttonContainer:SetPaintBackground(false)
    
    -- Add button (+)
    local addButton = vgui.Create("DButton", buttonContainer)
    addButton:SetText("+")
    addButton:Dock(LEFT)
    addButton:SetWide(28)
    addButton.DoClick = function()
        local weaponID = string.Trim(weaponEntry:GetValue())
        if weaponID == "" then return end
        if table.HasValue(GUNGAME.Weapons, weaponID) then
            notification.AddLegacy("Weapon already in list!", NOTIFY_ERROR, 2)
            return
        end
        net.Start("gungame_validate_weapon")
            net.WriteString(weaponID)
        net.SendToServer()
        weaponEntry:SetValue("")
    end
    
    -- Reset button (R)
    local randomButton = vgui.Create("DButton", buttonContainer)
    randomButton:SetText("R")
    randomButton:Dock(RIGHT)
    randomButton:SetWide(28)
    randomButton.DoClick = function()
        net.Start("gungame_clear_weapons")
        net.SendToServer()
        ClearWeaponList()
        notification.AddLegacy("Weapon list cleared", NOTIFY_GENERIC, 2)
    end
    
    -- Weapon list panel
    weaponListPanel = vgui.Create("DScrollPanel", panel)
    weaponListPanel:Dock(TOP)
    weaponListPanel:DockMargin(0, 0, 0, 8)
    weaponListPanel:SetTall(100)
    weaponListPanel:SetPaintBackground(true)
    weaponListPanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(240, 240, 240))
    end
    
    -- Options Label
    local optionsLabel = vgui.Create("DLabel", panel)
    optionsLabel:Dock(TOP)
    optionsLabel:DockMargin(0, 8, 0, 8)
    optionsLabel:SetText("Options")
    optionsLabel:SetFont("UAT_Circular_14")
    optionsLabel:SetTextColor(Color(40, 40, 40))
    optionsLabel:SizeToContents()
    
    -- Health input field
    local healthContainer = vgui.Create("DPanel", panel)
    healthContainer:Dock(TOP)
    healthContainer:DockMargin(0, 0, 0, 8)
    healthContainer:SetTall(28)
    healthContainer:SetPaintBackground(false)
    
    local healthLabel = vgui.Create("DLabel", healthContainer)
    healthLabel:Dock(LEFT)
    healthLabel:SetWide(60)
    healthLabel:SetText("Health:")
    healthLabel:SetTextColor(Color(40, 40, 40))
    
    local healthEntry = vgui.Create("DTextEntry", healthContainer)
    healthEntry:Dock(FILL)
    healthEntry:SetNumeric(true)
    healthEntry:SetValue("100")
    healthEntry:SetPlaceholderText("Enter health value")
    healthEntry:SetUpdateOnType(true)
    
    -- Store the health entry for later use
    GUNGAME.HealthEntry = healthEntry
    
    -- Armor input field
    local armorContainer = vgui.Create("DPanel", panel)
    armorContainer:Dock(TOP)
    armorContainer:DockMargin(0, 0, 0, 8)
    armorContainer:SetTall(28)
    armorContainer:SetPaintBackground(false)
    
    local armorLabel = vgui.Create("DLabel", armorContainer)
    armorLabel:Dock(LEFT)
    armorLabel:SetWide(60)
    armorLabel:SetText("Armor:")
    armorLabel:SetTextColor(Color(40, 40, 40))
    
    local armorEntry = vgui.Create("DTextEntry", armorContainer)
    armorEntry:Dock(FILL)
    armorEntry:SetNumeric(true)
    armorEntry:SetValue("100")
    armorEntry:SetPlaceholderText("Ingresar valor de armadura")
    armorEntry:SetUpdateOnType(true)
    
    -- Store the armor entry for later use
    GUNGAME.ArmorEntry = armorEntry
    
    -- Knife input field
    local knifeContainer = vgui.Create("DPanel", panel)
    knifeContainer:Dock(TOP)
    knifeContainer:DockMargin(0, 0, 0, 8)
    knifeContainer:SetTall(28)
    knifeContainer:SetPaintBackground(false)
    
    local knifeLabel = vgui.Create("DLabel", knifeContainer)
    knifeLabel:Dock(LEFT)
    knifeLabel:SetWide(60)
    knifeLabel:SetText("Knife:")
    knifeLabel:SetTextColor(Color(40, 40, 40))
    
    local knifeEntry = vgui.Create("DTextEntry", knifeContainer)
    knifeEntry:Dock(FILL)
    knifeEntry:SetValue("")
    knifeEntry:SetPlaceholderText("Dejar vacio para desactivar")
    knifeEntry:SetUpdateOnType(true)
    
    -- Store the knife entry for later use
    GUNGAME.KnifeEntry = knifeEntry
    
    -- Time input field
    local timeContainer = vgui.Create("DPanel", panel)
    timeContainer:Dock(TOP)
    timeContainer:DockMargin(0, 0, 0, 8)
    timeContainer:SetTall(28)
    timeContainer:SetPaintBackground(false)
    
    local timeLabel = vgui.Create("DLabel", timeContainer)
    timeLabel:Dock(LEFT)
    timeLabel:SetWide(100)
    timeLabel:SetText("Time (minutes):")
    timeLabel:SetTextColor(Color(40, 40, 40))
    
    local timeEntry = vgui.Create("DTextEntry", timeContainer)
    timeEntry:Dock(LEFT)
    timeEntry:SetWide(100)
    timeEntry:SetValue("-1")
    timeEntry:SetTooltip("Limite de tiempo en minutos (-1 para sin limite)")
    timeEntry:SetNumeric(true)
    
    -- Validar que solo se ingresen números, punto decimal y signo negativo
    timeEntry.OnChange = function(self)
        local text = self:GetValue()
        local newText = ""
        local hasDecimal = false
        
        for i = 1, #text do
            local c = text:sub(i, i)
            if c == "-" and i == 1 then
                newText = newText .. c
            elseif c == "." and not hasDecimal then
                newText = newText .. c
                hasDecimal = true
            elseif tonumber(c) ~= nil then
                newText = newText .. c
            end
        end
        
        -- Limitar a un máximo de 60
        if tonumber(newText) and tonumber(newText) > 60 then
            newText = "60"
        end
        
        if newText ~= text then
            self:SetText(newText)
            self:SetCaretPos(#newText)
        end
    end
    
    -- Store the time entry for later use
    GUNGAME.TimeEntry = timeEntry
    
    -- Speed input field
    local speedContainer = vgui.Create("DPanel", panel)
    speedContainer:Dock(TOP)
    speedContainer:DockMargin(0, 0, 0, 8)
    speedContainer:SetTall(28)
    speedContainer:SetPaintBackground(false)
    
    local speedLabel = vgui.Create("DLabel", speedContainer)
    speedLabel:Dock(LEFT)
    speedLabel:SetWide(100)
    speedLabel:SetText("Speed:")
    speedLabel:SetTextColor(Color(40, 40, 40))
    
    local speedEntry = vgui.Create("DTextEntry", speedContainer)
    speedEntry:Dock(LEFT)
    speedEntry:SetWide(100)
    speedEntry:SetValue("1")
    speedEntry:SetTooltip("Multiplicador de velocidad (1 = velocidad normal)")
    speedEntry:SetNumeric(true)
    
    -- Validate that only numbers and decimal points can be entered
    speedEntry.OnChange = function(self)
        local text = self:GetValue()
        local newText = ""
        local hasDecimal = false
        
        for i = 1, #text do
            local c = text:sub(i, i)
            if c == "." and not hasDecimal then
                newText = newText .. c
                hasDecimal = true
            elseif tonumber(c) ~= nil then
                newText = newText .. c
            end
        end
        
        -- Ensure minimum value of 0.1
        if tonumber(newText) and tonumber(newText) <= 0 then
            newText = "0.1"
        end
        
        if newText ~= text then
            self:SetText(newText)
            self:SetCaretPos(#newText)
        end
    end
    
    -- Store the speed entry for later use
    GUNGAME.SpeedEntry = speedEntry
    
    -- Regeneration combobox
    local regenContainer = vgui.Create("DPanel", panel)
    regenContainer:Dock(TOP)
    regenContainer:DockMargin(0, 0, 0, 8)
    regenContainer:SetTall(28)
    regenContainer:SetPaintBackground(false)
    
    local regenLabel = vgui.Create("DLabel", regenContainer)
    regenLabel:Dock(LEFT)
    regenLabel:SetWide(100)
    regenLabel:SetText("Regeneration:")
    regenLabel:SetTextColor(Color(40, 40, 40))
    
    local regenCombo = vgui.Create("DComboBox", regenContainer)
    regenCombo:Dock(FILL)
    regenCombo:SetValue("Desabilitado")
    regenCombo:AddChoice("Habilitado")
    regenCombo:AddChoice("Desabilitado")
    regenCombo:AddChoice("Lento")
    regenCombo:AddChoice("Baja confirmada")
    
    -- Store the regeneration combobox for later use
    GUNGAME.RegenCombo = regenCombo
    
    -- Prize input
    local prizeContainer = vgui.Create("DPanel", panel)
    prizeContainer:Dock(TOP)
    prizeContainer:DockMargin(0, 0, 0, 8)
    prizeContainer:SetTall(28)
    prizeContainer:SetPaintBackground(false)
    
    local prizeLabel = vgui.Create("DLabel", prizeContainer)
    prizeLabel:Dock(LEFT)
    prizeLabel:SetWide(100)
    prizeLabel:SetText("Prize:")
    prizeLabel:SetTextColor(Color(40, 40, 40))
    
    local prizeEntry = vgui.Create("DTextEntry", prizeContainer)
    prizeEntry:Dock(FILL)
    prizeEntry:SetPlaceholderText("0")
    prizeEntry:SetNumeric(true) -- Only allow numbers
    prizeEntry:SetValue("0")
    
    -- Store the prize entry for later use
    GUNGAME.PrizeEntry = prizeEntry

    -- Event control button
    GUNGAME.EventActive = false
    local btnStart = vgui.Create("DButton", panel)
    btnStart:SetText("Start event")
    btnStart:Dock(TOP)
    btnStart:DockMargin(0, 24, 0, 0)
    btnStart:SetTall(32)
    btnStart:SetFont("UAT_Circular_14")
    btnStart:SetWide(panel:GetWide() - 16)

    -- Update start button state based on conditions
    local function UpdateStartButtonState()
        local hasArea = #GUNGAME.AreaPoints > 0
        local hasWeapons = GUNGAME.Weapons and #GUNGAME.Weapons > 0
        
        if not GUNGAME.EventActive then
            btnStart:SetEnabled(hasArea and hasWeapons)
            if not hasArea then
                btnStart:SetTooltip("Necesitas definir un área primero")
            elseif not hasWeapons then
                btnStart:SetTooltip("Necesitas añadir al menos cinco armas")
            else
                btnStart:SetTooltip("Start the event")
            end
        end
    end
    
    -- Button state management CHECKPOINT BUTTON TOGGLE
    GUNGAME.SetButtonState = function(active)
        GUNGAME.EventActive = active
        if active then
            btnStart:SetText("Stop event")
            btnStart:SetEnabled(true)
            btnStart:SetTooltip("Stop the event")
            btnSelect:SetEnabled(false)
            btnDelete:SetEnabled(false)
            btnAddSpawn:SetEnabled(false)
            btnClearSpawns:SetEnabled(false)
            randomButton:SetEnabled(false)
            addButton:SetEnabled(false)
            healthEntry:SetEnabled(false)
            armorEntry:SetEnabled(false)
            knifeEntry:SetEnabled(false)
            timeEntry:SetEnabled(false)
            speedEntry:SetEnabled(false)
            regenCombo:SetEnabled(false)
            prizeEntry:SetEnabled(false)
        else
            btnStart:SetText("Start event")
            btnSelect:SetEnabled(true)
            btnDelete:SetEnabled(true)
            btnAddSpawn:SetEnabled(true)
            btnClearSpawns:SetEnabled(true)
            randomButton:SetEnabled(true)
            addButton:SetEnabled(true)
            healthEntry:SetEnabled(true)
            armorEntry:SetEnabled(true)
            knifeEntry:SetEnabled(true)
            timeEntry:SetEnabled(true)
            speedEntry:SetEnabled(true)
            regenCombo:SetEnabled(true)
            prizeEntry:SetEnabled(true)
            UpdateStartButtonState()
        end
    end
    
    -- Update button state when weapons or area changes
    hook.Add("GunGame_WeaponsUpdated", "UpdateStartButton", UpdateStartButtonState)
    hook.Add("GunGame_AreaUpdated", "UpdateStartButton", UpdateStartButtonState)

    -- Función para contar jugadores dentro del área
    local function CountPlayersInArea()
        local count = 0
        local areaPoints = GUNGAME.AreaPoints
        if #areaPoints < 3 then return 0 end
        
        for _, ply in ipairs(player.GetAll()) do
                -- Exclude specific SteamID (do not count this player)
                if not IsValid(ply) then return end
                if ply:IsBot() then
                    -- skip this SteamID
                else
                    if ply:Alive() and GUNGAME.PointInPoly2D(ply:GetPos(), areaPoints) then
                        count = count + 1
                    end
                end
        end
        return count
    end

    -- Start/stop event button handler
    btnStart.DoClick = function()
        if not GUNGAME.EventActive then
            -- Verificar si hay un área definida y armas configuradas
            if #GUNGAME.AreaPoints == 0 or not GUNGAME.Weapons or #GUNGAME.Weapons == 0 then
                notification.AddLegacy("No se puede iniciar el evento: Falta área o armas", NOTIFY_ERROR, 3)
                return
            end
            
            -- Contar jugadores dentro del área
            local playerCount = CountPlayersInArea()
            
            -- Verificar si hay suficientes puntos de spawn
            local spawnPointCount = #(GUNGAME.SpawnPoints or {})
            
            if playerCount < 2 then
                notification.AddLegacy("Necesitas al menos 5 jugadores en el área para iniciar el evento", NOTIFY_ERROR, 3)
                return
            end
            
            if spawnPointCount < playerCount then
                notification.AddLegacy("No hay suficientes spawnpoints (" .. spawnPointCount .. ") para los jugadores (" .. playerCount .. ")", NOTIFY_ERROR, 5)
                return
            end
            
            local timeValue = tonumber(GUNGAME.TimeEntry:GetValue()) or 10
            local timeDisplay = timeValue < 0 and "No limit" or (timeValue .. (timeValue == 1 and " minute" or " minutes"))
            
            Derma_Query(
                "¿Estas seguro que quieres iniciar el evento?\n\n" ..
                "Jugadores en el área: " .. playerCount .. "\n" ..
                "Spawn points disponibles: " .. spawnPointCount .. "\n" ..
                "Vida: " .. (GUNGAME.HealthEntry:GetValue() or "100") .. "\n" ..
                "Armadura: " .. (GUNGAME.ArmorEntry:GetValue() or "100") .. "\n" ..
                "Cuchillo: " .. (GUNGAME.KnifeEntry:GetValue() or "weapon_knife") .. "\n" ..
                "Tiempo limite: " .. timeDisplay .. "\n" ..
                "Premio: " .. (GUNGAME.PrizeEntry:GetValue() or "none") .. "\n",
                "Confirmar inicio del evento",
                "Sí", function()
                    -- Get and validate knife class
                    local knifeClass = GUNGAME.KnifeEntry:GetValue() or "weapon_knife"
                    knifeClass = string.Trim(knifeClass)
                    
                    -- If knife class is empty, use default
                    if knifeClass == "" then
                        knifeClass = "weapon_knife"
                    end
                    
                    -- Send game options
                    net.Start("gungame_options")
                        net.WriteUInt(math.floor(tonumber(GUNGAME.HealthEntry:GetValue()) or 100), 16)
                        net.WriteUInt(math.floor(tonumber(GUNGAME.ArmorEntry:GetValue()) or 100), 16)
                        local speedMultiplier = tonumber(GUNGAME.SpeedEntry:GetValue()) or 1.0
                        net.WriteFloat(math.max(0.1, math.min(10.0, speedMultiplier)))
                        local timeInSeconds = math.floor(timeValue * 60)
                        net.WriteUInt(timeInSeconds >= 0 and timeInSeconds or 0, 16)
                        
                        -- Send regeneration option (0: Desabilitado, 1: Habilitado, 2: Lento, 3: Baja confirmada)
                        local regenOption = 0
                        local regenText = GUNGAME.RegenCombo:GetValue()
                        if regenText == "Habilitado" then
                            regenOption = 1
                        elseif regenText == "Lento" then
                            regenOption = 2
                        elseif regenText == "Baja confirmada" then
                            regenOption = 3
                        end
                        net.WriteUInt(regenOption, 2) -- Using 2 bits (0-3)
                        
                        -- Send prize amount
                        local prizeAmount = math.max(0, tonumber(GUNGAME.PrizeEntry:GetValue()) or 0)
                        net.WriteUInt(prizeAmount, 32) -- Using 32 bits for prize amount
                        
                        -- Send knife class
                        net.WriteString(knifeClass)
                    net.SendToServer()
                    
                    -- Then start the event
                    net.Start("gungame_start_event")
                    net.SendToServer()
                    GUNGAME.SetButtonState(true)
                    notification.AddLegacy("Event started", NOTIFY_CLEANUP, 3)
                    surface.PlaySound("buttons/button15.wav")
                end,
                "No"
            )
        else
            Derma_Query(
                "¿Seguro que quieres frenar el evento?",
                "Confirmar detención del evento",
                "Sí", function()
                    net.Start("gungame_stop_event")
                    net.SendToServer()
                    net.Start("gungame_area_clear")
                    net.SendToServer()
                    ClearWeaponList()
                    GUNGAME.SetButtonState(false)
                end,
                "No"
            )
        end
    end
end

-- Console command for area selection
concommand.Add("gungame_area_start", function()
    RunConsoleCommand("gmod_toolmode", "gungame")
    local ply = LocalPlayer()
    timer.Simple(0, function()
        if IsValid(ply) then
            ply:ConCommand("use gmod_tool")
        end
    end)
    net.Start("gungame_area_start")
    net.SendToServer()
end)

-- Drawing the area points and lines
hook.Add("PostDrawTranslucentRenderables", "gungame_area_draw_points", function()
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    local isToolActive = IsValid(wep) and wep:GetClass() == "gmod_tool" and ply:GetTool() and ply:GetTool().Mode == "gungame"
    
    -- Only draw if we have the tool active
    if not isToolActive then return end
    
    -- Get the synchronized area points
    local points = GUNGAME.AreaPoints or {}
    if #points > 0 then
        render.SetColorMaterial()
        for i, pos in ipairs(points) do
            render.DrawSphere(pos, 8, 16, 16, Color(255, 0, 0, 180))
            if i > 1 then
                render.DrawLine(points[i-1], pos, Color(255, 0, 0), true)
            end
        end

        -- Draw preview line to cursor
        if #points < 4 then
            local tr = ply:GetEyeTrace()
            if tr.Hit then
                local last = points[#points]
                if last then
                    render.DrawLine(last, tr.HitPos, Color(0, 255, 0), true)
                    render.DrawSphere(tr.HitPos, 6, 12, 12, Color(0, 0, 0, 120))
                end
            end
        end

        -- Close the polygon if there are 4 points
        if #points == 4 then
            render.DrawLine(points[4], points[1], Color(255, 0, 0), true)
        end
    end
    
    -- Draw spawn points (only when the tool is active)
    if not isToolActive then return end
    
    local spawnPoints = GUNGAME.SpawnPoints or {}
    if #spawnPoints > 0 then
        render.SetColorMaterial()
        for _, data in ipairs(spawnPoints) do
            if data.pos then
                local pos = data.pos
                local ang = data.ang or Angle(0, 0, 0)
                render.DrawSphere(pos, 10, 16, 16, Color(0, 150, 255, 200))
                local size = 10
                render.DrawLine(pos + Vector(-size, 0, 0), pos + Vector(size, 0, 0), Color(255, 255, 255, 200), true)
                render.DrawLine(pos + Vector(0, -size, 0), pos + Vector(0, size, 0), Color(255, 255, 255, 200), true)
                render.DrawLine(pos + Vector(0, 0, -size), pos + Vector(0, 0, size), Color(255, 255, 255, 200), true)
                local forward = ang:Forward() * 20
                render.DrawLine(pos, pos + forward, Color(255, 255, 0, 255), true)
                local right = ang:Right() * 5
                render.DrawLine(pos + forward, pos + forward * 0.7 + right, Color(255, 255, 0, 255), true)
                render.DrawLine(pos + forward, pos + forward * 0.7 - right, Color(255, 255, 0, 255), true)
            end
        end
    end
end)

_G.CreateGunGameUI = CreateGunGameUI
return CreateGunGameUI
