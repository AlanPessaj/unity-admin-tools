if CLIENT then
    local CAMERA = CAMERA or {}
    CAMERA.Active = false
    CAMERA.CurrentPoint = 1
    CAMERA.StartTime = 0
    CAMERA.StartPos = Vector(0, 0, 0)
    CAMERA.StartAng = Angle(0, 0, 0)
    CAMERA.IsAtStartPos = false
    CAMERA.Panel = nil

    CAMERA.Points = {
        {Vector(0, 0, 100), Vector(100, 0, 100), Angle(0, 0, 0), Angle(0, 90, 0), 2.0},
        {Vector(100, 100, 100), Vector(100, -100, 100), Angle(25, 45, 0), Angle(25, -45, 0), 3.0},
        {Vector(-100, -100, 50), Vector(-200, -100, 50), Angle(15, -45, 0), Angle(15, -90, 0), 2.5}
        -- Punto inicial - Punto final - Angulo inicial - Angulo final - Tiempo de transición
    }

    util.AddNetworkString = util.AddNetworkString or function() end // Para evitar errores en cliente puro

    function CAMERA:CreatePanel()
        if IsValid(self.Panel) then self.Panel:Remove() end

        -- Panel principal
        local panel = vgui.Create("DFrame")
        panel:SetSize(ScrW() * 0.8, ScrH() * 0.8)
        panel:Center()
        panel:SetTitle("")
        panel:SetDraggable(false)
        panel:ShowCloseButton(false)
        panel:MakePopup()
        panel.Paint = function(self, w, h)
            surface.SetDrawColor(0, 0, 0, 240)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(0, 120, 255, 255)
            surface.DrawOutlinedRect(0, 0, w, h, 4)
            draw.SimpleText("SELECTOR DE PERSONAJE", "DermaDefaultBold", w/2, 15, Color(200, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        -- Botón de cierre
        local closeBtn = vgui.Create("DButton", panel)
        closeBtn:SetText("X")
        closeBtn:SetFont("DermaDefaultBold")
        closeBtn:SetTextColor(Color(200, 220, 255))
        closeBtn:SetSize(30, 30)
        closeBtn:SetPos(panel:GetWide() - 35, 5)
        closeBtn.Paint = function() end
        closeBtn.DoClick = function()
            panel:Remove()
            CAMERA:StopSequence()
        end

        -- Variables de selección
        local bodygroupSelections = {
            torso = 0,
            legs = 0,
            hands = 0,
            headgear = 0
        }
        local currentGender = "Masculino"
        local currentModelIndex = 1
        local currentModels = CHARACTER_CREATOR.Models[currentGender] or {}

        -- Nombre
        local nombreLabel = vgui.Create("DLabel", panel)
        nombreLabel:SetText("Nombre:")
        nombreLabel:SetFont("DermaLarge")
        nombreLabel:SetSize(400, 60)
        nombreLabel:SetTextColor(Color(200, 220, 255))
        nombreLabel:SetPos(80, 60)
        nombreLabel:SizeToContents()
        local nombreEntry = vgui.Create("DTextEntry", panel)
        nombreEntry:SetPos(80, 105)
        nombreEntry:SetSize(300, 45)
        nombreEntry:SetFont("DermaLarge")
        nombreEntry:SetTextColor(Color(200, 220, 255))
        nombreEntry.Paint = function(self, w, h)
            surface.SetDrawColor(40, 50, 60, 200)
            surface.DrawRect(0, 0, w, h)
            self:DrawTextEntryText(Color(200, 220, 255), Color(30, 100, 200), Color(200, 220, 255))
        end

        -- Género
        local generoLabel = vgui.Create("DLabel", panel)
        generoLabel:SetText("Genero:")
        generoLabel:SetFont("DermaLarge")
        generoLabel:SetSize(400, 60)
        generoLabel:SetTextColor(Color(200, 220, 255))
        generoLabel:SetPos(80, 180)
        generoLabel:SizeToContents()
        local generoEntry = vgui.Create("DComboBox", panel)
        generoEntry:SetPos(80, 225)
        generoEntry:SetSize(300, 45)
        generoEntry:SetFont("DermaLarge")
        generoEntry:AddChoice("Masculino")
        generoEntry:AddChoice("Femenino")
        generoEntry:ChooseOptionID(1)
        generoEntry:SetTextColor(Color(200, 220, 255))
        generoEntry.Paint = function(self, w, h)
            surface.SetDrawColor(40, 50, 60, 200)
            surface.DrawRect(0, 0, w, h)
            self:DrawTextEntryText(Color(200, 220, 255), Color(30, 100, 200), Color(200, 220, 255))
        end

        -- ModelPanel
        local modelPanel = vgui.Create("DModelPanel", panel)
        modelPanel:SetAnimated(false)
        modelPanel:SetSize(600, 600)
        modelPanel:SetPos(panel:GetWide()/2 - 300, panel:GetTall()/2 - 400)
        modelPanel:SetFOV(45)
        modelPanel.LayoutEntity = function(self, ent) end

        -- Declaración adelantada de funciones locales para evitar problemas de scope
        local UpdateBodygroups, CreateBodygroupControls, UpdateModel

        -- Definición de UpdateBodygroups
        UpdateBodygroups = function(entity)
            if not IsValid(entity) then return end
            entity:SetBodygroup(1, bodygroupSelections.torso or 0)
            entity:SetBodygroup(2, bodygroupSelections.legs or 0)
            entity:SetBodygroup(3, bodygroupSelections.hands or 0)
            entity:SetBodygroup(4, bodygroupSelections.headgear or 0)
        end

        -- Definición de CreateBodygroupControls
        CreateBodygroupControls = function(parent, entity)
            local container = vgui.Create("DPanel", parent)
            container:SetSize(300, 250)
            container:SetPos(80, 480)
            container.Paint = function(self, w, h)
                surface.SetDrawColor(20, 30, 45, 230)
                surface.DrawRect(0, 0, w, h)
                surface.DrawOutlinedRect(0, 0, w, h)
            end

            local title = vgui.Create("DLabel", container)
            title:SetText("Personalización")
            title:SetFont("DermaLarge")
            title:SetTextColor(Color(200, 220, 255))
            title:SetSize(380, 25)
            title:SetPos(50, 5)
            title:SizeToContents()

            local function CreateControl(y, name, bgId, max)
                local bgPanel = vgui.Create("DPanel", container)
                bgPanel:SetSize(250, 30)
                bgPanel:SetPos(25, y+10)
                bgPanel.Paint = function(self, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, Color(30, 40, 50, 200))
                    surface.SetDrawColor(60, 80, 100, 150)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                end
                local label = vgui.Create("DLabel", bgPanel)
                label:SetText(name .. ":")
                label:SetTextColor(Color(200, 220, 255))
                label:SetPos(5, 7)
                label:SizeToContents()

                local leftBtn = vgui.Create("DButton", bgPanel)
                leftBtn:SetText("◀")
                leftBtn:SetSize(30, 25)
                leftBtn:SetTextColor(Color(200, 220, 255, 255))
                leftBtn.Paint = function(self, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, Color(40, 80, 140, 200))
                    if self:IsHovered() then
                        draw.RoundedBox(4, 0, 0, w, h, Color(60, 120, 200, 200))
                    end
                end
                leftBtn:SetPos(125, 2.5)
                leftBtn.DoClick = function()
                    bodygroupSelections[name:lower()] = (bodygroupSelections[name:lower()] - 1) % (max + 1)
                    if bodygroupSelections[name:lower()] < 0 then 
                        bodygroupSelections[name:lower()] = max 
                    end
                    UpdateBodygroups(entity)
                end

                local valueLabel = vgui.Create("DLabel", bgPanel)
                valueLabel:SetText("0")
                valueLabel:SetTextColor(Color(200, 220, 255))
                valueLabel:SetFont("DermaDefaultBold")
                valueLabel:SetPos(155, 1)
                valueLabel:SetSize(50, 25)
                valueLabel:SetContentAlignment(5)

                local rightBtn = vgui.Create("DButton", bgPanel)
                rightBtn:SetText("▶")
                rightBtn:SetSize(30, 25)
                rightBtn:SetTextColor(Color(200, 220, 255, 255))
                rightBtn.Paint = function(self, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, Color(40, 80, 140, 200))
                    if self:IsHovered() then
                        draw.RoundedBox(4, 0, 0, w, h, Color(60, 120, 200, 200))
                    end
                end
                rightBtn:SetPos(205, 2.5)
                rightBtn.DoClick = function()
                    bodygroupSelections[name:lower()] = (bodygroupSelections[name:lower()] + 1) % (max + 1)
                    UpdateBodygroups(entity)
                end

                function bgPanel:Think()
                    valueLabel:SetText(tostring(bodygroupSelections[name:lower()] or 0))
                end

                return bgPanel
            end

            CreateControl(40, "Torso", 1, 16)
            CreateControl(90, "Legs", 2, 6)
            CreateControl(140, "Hands", 3, 1)
            CreateControl(190, "Headgear", 4, 4)

            return container
        end

        -- Definición de UpdateModel
        UpdateModel = function()
            if not currentModels or #currentModels == 0 then return end

            currentModelIndex = math.Clamp(currentModelIndex, 1, #currentModels)
            local modelPath = currentModels[currentModelIndex]

            if IsValid(modelPanel) and modelPanel:GetModel() ~= modelPath then
                modelPanel:SetModel(modelPath)
                modelPanel.Entity:SetAngles(Angle(0, 45, 0))

                local mn, mx = modelPanel.Entity:GetRenderBounds()
                local size = 0
                size = math.max(size, math.abs(mn.x) + math.abs(mx.x))
                size = math.max(size, math.abs(mn.y) + math.abs(mx.y))
                size = math.max(size, math.abs(mn.z) + math.abs(mx.z))
                modelPanel:SetCamPos(Vector(size, size, size/2))
                modelPanel:SetLookAt((mn + mx) * 0.5)

                timer.Simple(0.1, function()
                    if not IsValid(modelPanel) or not IsValid(modelPanel.Entity) then return end
                    if IsValid(modelPanel.BodygroupControls) then
                        modelPanel.BodygroupControls:Remove()
                    end
                    modelPanel.BodygroupControls = CreateBodygroupControls(panel, modelPanel.Entity)
                    UpdateBodygroups(modelPanel.Entity)
                end)
            elseif IsValid(modelPanel) and IsValid(modelPanel.Entity) then
                UpdateBodygroups(modelPanel.Entity)
            end
        end

        -- Botón de flecha izquierda
        local leftArrow = vgui.Create("DButton", panel)
        leftArrow:SetText("❮")
        leftArrow:SetFont("DermaLarge")
        leftArrow:SetSize(30, 30)
        leftArrow:SetPos(625, 230)
        leftArrow.Paint = function(self, w, h)
            surface.SetDrawColor(60, 60, 60, 200)
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText("❮", "DermaLarge", w/2, h/2, Color(200, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        leftArrow.DoClick = function()
            currentModelIndex = currentModelIndex - 1
            if currentModelIndex < 1 then
                currentModelIndex = #currentModels
            end
            UpdateModel()
        end

        -- Botón de flecha derecha
        local rightArrow = vgui.Create("DButton", panel)
        rightArrow:SetText("❯")
        rightArrow:SetFont("DermaLarge")
        rightArrow:SetSize(30, 30)
        rightArrow:SetPos(855, 230)
        rightArrow.Paint = function(self, w, h)
            surface.SetDrawColor(60, 60, 60, 200)
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText("❯", "DermaLarge", w/2, h/2, Color(200, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
        rightArrow.DoClick = function()
            currentModelIndex = currentModelIndex + 1
            if currentModelIndex > #currentModels then
                currentModelIndex = 1
            end
            UpdateModel()
        end

        -- Asignar el evento OnSelect del combobox de género DESPUÉS de definir UpdateModel
        generoEntry.OnSelect = function(self, index, value)
            currentGender = value
            currentModels = CHARACTER_CREATOR.Models[value] or {}
            currentModelIndex = 1
            UpdateModel()
        end

        -- ComboBox de presets guardados
        local presetsCombo = vgui.Create("DComboBox", panel)
        presetsCombo:SetPos(80, 300)
        presetsCombo:SetSize(300, 40)
        presetsCombo:SetFont("DermaLarge")
        presetsCombo:SetValue("Seleccionar preset")
        presetsCombo:SetTextColor(Color(200, 220, 255))
        presetsCombo.Paint = function(self, w, h)
            surface.SetDrawColor(40, 50, 60, 200)
            surface.DrawRect(0, 0, w, h)
            self:DrawTextEntryText(Color(200, 220, 255), Color(30, 100, 200), Color(200, 220, 255))
        end

        -- Al seleccionar un preset del combo, cargarlo
        presetsCombo.OnSelect = function(self, index, value)
            if not value or value == "" then return end
            net.Start("character_creator_request_preset")
                net.WriteString(value)
            net.SendToServer()
        end

        -- Botón cargar preset (opcional, puedes dejarlo si quieres un botón además del combo)
        local loadPresetBtn = vgui.Create("DButton", panel)
        loadPresetBtn:SetText("Cargar")
        loadPresetBtn:SetFont("DermaLarge")
        loadPresetBtn:SetSize(120, 40)
        loadPresetBtn:SetPos(400, 300)
        loadPresetBtn:SetTextColor(Color(200, 220, 255))
        loadPresetBtn.Paint = function(self, w, h)
            surface.SetDrawColor(40, 80, 140, 220)
            surface.DrawRect(0, 0, w, h)
            if self:IsHovered() then
                surface.SetDrawColor(60, 120, 200, 240)
                surface.DrawRect(0, 0, w, h)
            end
            surface.SetDrawColor(0, 120, 255, 255)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
            draw.SimpleText("Cargar", "DermaLarge", w/2, h/2, Color(200, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        loadPresetBtn.DoClick = function()
            local selected = presetsCombo:GetSelected()
            if not selected or selected == "" then
                notification.AddLegacy("Selecciona un preset para cargar.", NOTIFY_ERROR, 3)
                return
            end
            net.Start("character_creator_request_preset")
                net.WriteString(selected)
            net.SendToServer()
        end

        -- Recibir lista de presets y poblar el combobox
        local function RequestAndPopulatePresets(selectedName)
            presetsCombo:Clear()
            net.Start("character_creator_request_presets_list")
            net.SendToServer()
            -- Guardar el nombre seleccionado para después
            presetsCombo._pendingSelect = selectedName
        end

        net.Receive("character_creator_send_presets_list", function()
            local names = net.ReadTable() or {}
            local selectName = presetsCombo._pendingSelect
            presetsCombo._pendingSelect = nil
            presetsCombo:Clear()
            for _, name in ipairs(names) do
                presetsCombo:AddChoice(name)
            end
            -- Seleccionar el nombre deseado si existe, si no el primero
            if selectName and table.HasValue(names, selectName) then
                for i, v in ipairs(names) do
                    if v == selectName then
                        presetsCombo:ChooseOptionID(i)
                        break
                    end
                end
            elseif #names > 0 then
                presetsCombo:ChooseOptionID(1)
            end
        end)

        -- Recibir preset y cargarlo en los campos
        net.Receive("character_creator_send_preset", function()
            local preset = net.ReadTable()
            if not preset or not preset.nombre then
                notification.AddLegacy("No se pudo cargar el preset.", NOTIFY_ERROR, 3)
                return
            end
            nombreEntry:SetValue(preset.nombre or "")
            currentGender = preset.genero or "Masculino"
            currentModels = CHARACTER_CREATOR.Models[currentGender] or {}
            currentModelIndex = preset.modelIndex or 1
            generoEntry:ChooseOption(currentGender)
            bodygroupSelections = table.Copy(preset.bodygroups or bodygroupSelections)
            UpdateModel()
            timer.Simple(0.2, function()
                if IsValid(modelPanel) and IsValid(modelPanel.Entity) then
                    UpdateBodygroups(modelPanel.Entity)
                end
            end)
        end)

        -- Preguntar si sobrescribir preset existente
        net.Receive("character_creator_save_exists", function()
            local nombre = net.ReadString()
            local data = net.ReadTable()
            Derma_Query(
                "Ya existe un personaje con ese nombre. ¿Deseas sobrescribirlo?",
                "Sobrescribir preset",
                "Sí", function()
                    net.Start("character_creator_overwrite_preset")
                        net.WriteTable(data)
                    net.SendToServer()
                end,
                "No"
            )
        end)

        -- Botón Guardar
        local saveBtn = vgui.Create("DButton", panel)
        saveBtn:SetText("Guardar")
        saveBtn:SetFont("DermaLarge")
        saveBtn:SetSize(200, 50)
        saveBtn:SetPos(panel:GetWide()/2 - 100, modelPanel:GetY() + modelPanel:GetTall() + 20)
        saveBtn:SetTextColor(Color(200, 220, 255))
        saveBtn.Paint = function(self, w, h)
            surface.SetDrawColor(40, 80, 140, 220)
            surface.DrawRect(0, 0, w, h)
            if self:IsHovered() then
                surface.SetDrawColor(60, 120, 200, 240)
                surface.DrawRect(0, 0, w, h)
            end
            surface.SetDrawColor(0, 120, 255, 255)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
            draw.SimpleText("Guardar", "DermaLarge", w/2, h/2, Color(200, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        saveBtn.DoClick = function()
            surface.PlaySound("buttons/button15.wav")
            net.Start("character_creator_save_preset")
                net.WriteTable({
                    nombre = nombreEntry:GetValue(),
                    genero = currentGender,
                    model = currentModels[currentModelIndex],
                    modelIndex = currentModelIndex,
                    bodygroups = table.Copy(bodygroupSelections)
                })
            net.SendToServer()
        end

        -- Recargar lista tras eliminar
        net.Receive("character_creator_delete_success", function()
            notification.AddLegacy("Preset eliminado.", NOTIFY_GENERIC, 3)
            RequestAndPopulatePresets()
        end)

        -- Llamar al cargar panel
        RequestAndPopulatePresets()

        -- Cargar el modelo inicial
        UpdateModel()

        self.Panel = panel
        return panel
    end
    
    function CAMERA:StartSequence()
        if #self.Points == 0 then return end
        
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        
        -- Panel
        self:CreatePanel()
        
        self.Active = true
        self.CurrentPoint = 1
        self.IsAtStartPos = false
        self:MoveToStartPosition()
    end

    function CAMERA:MoveToStartPosition()
        if self.CurrentPoint > #self.Points then
            self.CurrentPoint = 1 -- Reinicio
            return
        end
        
        local pointData = self.Points[self.CurrentPoint]
        self.StartPos = pointData[1]  -- Posición inicial del punto actual
        self.StartAng = pointData[3]  -- Ángulo inicial del punto actual
        self.IsAtStartPos = true
        self.StartTime = CurTime()
    end

    function CAMERA:StopSequence()
        self.Active = false
        self.IsAtStartPos = false
        if IsValid(self.Panel) then
            self.Panel:Remove()
            self.Panel = nil
        end
    end

    hook.Add("CalcView", "CameraLerpMovement", function(ply, pos, angles, fov)
        if not IsValid(CAMERA.Panel) then
            CAMERA:StopSequence()
            return
        end
        
        if not CAMERA.Active or not CAMERA.IsAtStartPos then return end
        
        local currentPoint = CAMERA.CurrentPoint
        if currentPoint > #CAMERA.Points then return end
        
        local pointData = CAMERA.Points[currentPoint]
        local startPos = pointData[1]  -- Posición inicial
        local endPos = pointData[2]    -- Posición final
        local startAng = pointData[3]  -- Ángulo inicial
        local endAng = pointData[4]    -- Ángulo final
        local transitionTime = pointData[5]  -- Tiempo de transición
        
        local currentTime = CurTime() - CAMERA.StartTime
        local progress = math.Clamp(currentTime / transitionTime, 0, 1)
        
        -- Lerp entre la posición/ángulo inicial y final del punto actual
        local newPos = LerpVector(progress, startPos, endPos)
        local newAng = LerpAngle(progress, startAng, endAng)
        
        local view = {
            origin = newPos,
            angles = newAng,
            fov = fov,
            drawviewer = true
        }
        
        if progress >= 1 then
            CAMERA.CurrentPoint = currentPoint + 1
            CAMERA:MoveToStartPosition()
        end
        
        return view
    end)


    -- Comando debug (BORRAR)
    concommand.Add("character_selector", function()
        CAMERA:StartSequence()
    end)
end