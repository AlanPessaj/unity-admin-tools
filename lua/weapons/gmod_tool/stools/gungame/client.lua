include("shared.lua")

-- Client state
local GUNGAME = GUNGAME or {}
GUNGAME.AreaPoints = {}
GUNGAME.AreaPanel = nil
GUNGAME.SpawnPoints = {}
GUNGAME.SpawnPanel = nil
GUNGAME.Weapons = {}
local weaponListPanel

-- Language strings
language.Add("tool.gungame.name", "[CGO] GunGame Tool")
language.Add("tool.gungame.desc", "Creado por AlanPessaj ◢ ◤")
language.Add("tool.gungame.0", "Configura las opciones en el menú de la herramienta.")

-- Network receivers
net.Receive("gungame_play_win_sound", function()
    local winSound = "gungame/win/win_sound.mp3"
    if file.Exists("sound/" .. winSound, "GAME") then
        sound.PlayFile("sound/" .. winSound, "noplay", function(station, errorID, errorName)
            if IsValid(station) then
                station:SetVolume(1)
                station:Play()
            end
        end)
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

-- Recibir mensajes de depuración del servidor
net.Receive("gungame_debug_message", function()
    local message = net.ReadString()
    if message then
        LocalPlayer():ChatPrint("[GunGame Debug] " .. message)
        MsgC(Color(0, 255, 255), "[GunGame Debug] ", Color(255, 255, 255), message, "\n")
    end
end)

net.Receive("gungame_area_update_points", function()
    GUNGAME.AreaPoints = net.ReadTable() or {}
    -- Update the panel if it exists
    if IsValid(GUNGAME.AreaPanel) then
        GUNGAME.AreaPanel:InvalidateLayout(true)
    end
    hook.Run("GunGame_AreaUpdated")
end)

net.Receive("gungame_update_spawnpoints", function()
    GUNGAME.SpawnPoints = net.ReadTable() or {}
    if IsValid(GUNGAME.SpawnPanel) then
        GUNGAME.SpawnPanel:InvalidateLayout(true)
    end
end)

net.Receive("gungame_event_stopped", function()
    GUNGAME.SpawnPoints = {}
    if GUNGAME.SetButtonState then
        GUNGAME.SetButtonState(false)
    end
end)

-- Función para actualizar la lista de armas en la UI
local function UpdateWeaponList()
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
    net.Start("gungame_sync_weapons")
        net.WriteUInt(#GUNGAME.Weapons, 8)
        for _, weaponID in ipairs(GUNGAME.Weapons) do
            net.WriteString(weaponID or "")
        end
    net.SendToServer()
end

-- Función para limpiar la lista de armas
local function ClearWeaponList()
    GUNGAME.Weapons = {}
    if IsValid(weaponListPanel) then
        weaponListPanel:Clear()
    end
    SyncWeaponsWithServer()
end

net.Receive("gungame_weapon_validated", function()
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
    ClearWeaponList()
    hook.Run("GunGame_WeaponsUpdated")
end)

-- Tool panel creation
function TOOL.BuildCPanel(panel)
    if panel.SetName then panel:SetName("") end
    
    GUNGAME.AreaPanel = panel
    panel:DockPadding(8, 8, 8, 8)
    
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
    label:SetFont("DermaDefaultBold")
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
    btnSelect:SetFont("DermaDefaultBold")
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
    btnDelete:SetFont("DermaDefaultBold")
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
    spawnLabel:SetFont("DermaDefaultBold")
    spawnLabel:SetTextColor(Color(40, 40, 40))
    spawnLabel:SizeToContents()

    local btnAddSpawn = vgui.Create("DButton", panel)
    btnAddSpawn:SetText("Add Spawn Point")
    btnAddSpawn:Dock(TOP)
    btnAddSpawn:DockMargin(0, 8, 0, 4)
    btnAddSpawn:SetTall(28)
    btnAddSpawn:SetFont("DermaDefaultBold")
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
    btnClearSpawns:SetFont("DermaDefaultBold")
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
    weaponsLabel:SetFont("DermaDefaultBold")
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
    weaponListPanel:DockMargin(0, 0, 0, 16)
    weaponListPanel:SetTall(100)
    weaponListPanel:SetPaintBackground(true)
    weaponListPanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(240, 240, 240))
    end

    -- Event control button
    GUNGAME.EventActive = false
    local btnStart = vgui.Create("DButton", panel)
    btnStart:SetText("Start event")
    btnStart:Dock(TOP)
    btnStart:DockMargin(0, 24, 0, 0)
    btnStart:SetTall(32)
    btnStart:SetFont("DermaDefaultBold")
    btnStart:SetWide(panel:GetWide() - 16)

    -- Update start button state based on conditions
    local function UpdateStartButtonState()
        local hasArea = #GUNGAME.AreaPoints > 0
        local hasWeapons = GUNGAME.Weapons and #GUNGAME.Weapons > 0
        
        if not GUNGAME.EventActive then
            btnStart:SetEnabled(hasArea and hasWeapons)
            if not hasArea then
                btnStart:SetTooltip("You need to define an area first")
            elseif not hasWeapons then
                btnStart:SetTooltip("You need to add at least one weapon")
            else
                btnStart:SetTooltip("Start the event")
            end
        end
    end
    
    -- Button state management
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
        else
            btnStart:SetText("Start event")
            btnSelect:SetEnabled(true)
            btnDelete:SetEnabled(true)
            btnAddSpawn:SetEnabled(true)
            btnClearSpawns:SetEnabled(true)
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
            if ply:Alive() and GUNGAME.PointInPoly2D(ply:GetPos(), areaPoints) then
                count = count + 1
            end
        end
        return count
    end

    -- Start/stop event button handler
    btnStart.DoClick = function()
        if not GUNGAME.EventActive then
            -- Verificar si hay un área definida y armas configuradas
            if #GUNGAME.AreaPoints == 0 or not GUNGAME.Weapons or #GUNGAME.Weapons == 0 then
                notification.AddLegacy("Cannot start event: Missing area or weapons", NOTIFY_ERROR, 3)
                return
            end
            
            -- Contar jugadores dentro del área
            local playerCount = CountPlayersInArea()
            
            -- Verificar si hay suficientes puntos de spawn
            local spawnPointCount = #(GUNGAME.SpawnPoints or {})
            
            if playerCount < 2 then
                notification.AddLegacy("You need at least 2 players in the area to start the event", NOTIFY_ERROR, 3)
                return
            end
            
            if spawnPointCount < playerCount then
                notification.AddLegacy("There are not enough spawn points (" .. spawnPointCount .. ") for players (" .. playerCount .. ")", NOTIFY_ERROR, 5)
                return
            end
            
            Derma_Query(
                "Are you sure you want to start the event?\n\n" ..
                "Players in the area: " .. playerCount .. "\n" ..
                "Spawn points available: " .. spawnPointCount,
                "Confirm event start",
                "Yes", function()
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
                "Are you sure you want to stop the event?",
                "Confirm event stop",
                "Yes", function()
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
