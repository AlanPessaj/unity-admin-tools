-- PropMovement Client Side
-- Variables globales para almacenar props seleccionados
local selectedProps = {}
local propsListPanel = nil

-- Tabla para almacenar la configuración de cada prop
-- Estructura: propConfigs[entID] = {entity, direction, distance, time, cooldown}
local propConfigs = {}

-- Función para obtener nombre descriptivo del prop
local function GetPropName(ent)
    if not IsValid(ent) then return "Invalid" end
    
    local model = ent:GetModel() or "unknown"
    local fileName = string.GetFileFromFilename(model)
    local entID = ent:EntIndex()
    
    return string.format("%s [%d]", fileName, entID)
end

-- Función para inicializar configuración de un prop
local function InitPropConfig(ent)
    if not IsValid(ent) then return end
    
    local entID = ent:EntIndex()
    if not propConfigs[entID] then
        propConfigs[entID] = {
            entity = ent,
            direction = "UP",
            distance = 100,
            time = 2,
            cooldown = 1
        }
    end
end

-- Función para obtener configuración de un prop
local function GetPropConfig(ent)
    if not IsValid(ent) then return nil end
    return propConfigs[ent:EntIndex()]
end

-- Función para actualizar configuración de un prop
local function UpdatePropConfig(ent, key, value)
    if not IsValid(ent) then return end
    
    local entID = ent:EntIndex()
    if propConfigs[entID] then
        propConfigs[entID][key] = value
        
        -- Enviar configuración actualizada al servidor
        net.Start("PropMovement_Config")
        net.WriteInt(entID, 16)
        net.WriteTable(propConfigs[entID])
        net.SendToServer()
    end
end

-- Función para eliminar configuración de un prop
local function RemovePropConfig(ent)
    if not IsValid(ent) then return end
    
    local entID = ent:EntIndex()
    propConfigs[entID] = nil
    
    -- Remover de la lista de props seleccionados
    for i = #selectedProps, 1, -1 do
        if selectedProps[i] == ent then
            table.remove(selectedProps, i)
            break
        end
    end
end

-- Variable para controlar la verificación del servidor
local serverCheckPending = {}
local pendingCallbacks = {}

-- Función para verificar si un prop ya está seleccionado (solo localmente)
local function IsAlreadySelectedLocal(ent)
    for _, prop in ipairs(selectedProps) do
        if IsValid(prop) and prop == ent then
            return true
        end
    end
    return false
end

-- Función para verificar si un prop ya está seleccionado
local function IsAlreadySelected(ent, callback)
    -- Verificación local primero
    if IsAlreadySelectedLocal(ent) then
        if callback then callback(true) end
        return true
    end
    
    -- Si no hay callback, solo hacer verificación local (modo síncrono)
    if not callback then
        return false
    end
    
    -- Si hay callback, verificar también en el servidor (modo asíncrono)
    if IsValid(ent) then
        local entID = ent:EntIndex()
        
        -- Si ya hay una verificación pendiente para esta entidad, agregar callback a la cola
        if serverCheckPending[entID] then
            if not pendingCallbacks[entID] then
                pendingCallbacks[entID] = {}
            end
            table.insert(pendingCallbacks[entID], callback)
            return false
        end
        
        -- Marcar como pendiente y almacenar callback
        serverCheckPending[entID] = true
        pendingCallbacks[entID] = {callback}
        
        -- Solicitar verificación al servidor
        net.Start("PropMovement_CheckServer")
        net.WriteInt(entID, 16)
        net.SendToServer()
    end
    
    return false
end

-- Función para limpiar props inválidos de la lista
local function CleanInvalidProps()
    for i = #selectedProps, 1, -1 do
        if not IsValid(selectedProps[i]) then
            local prop = selectedProps[i]
            RemovePropConfig(prop)
            table.remove(selectedProps, i)
        end
    end
    
    -- Limpiar configuraciones huérfanas
    for entID, config in pairs(propConfigs) do
        if not IsValid(config.entity) then
            propConfigs[entID] = nil
        end
    end
end

-- Forward declarations para evitar dependencias circulares
local UpdatePropsList
local CreatePropConfigPanel

-- Función para actualizar la lista visual de props
UpdatePropsList = function()
    if not IsValid(propsListPanel) then return end
    
    -- Limpiar lista actual
    propsListPanel:Clear()
    
    -- Limpiar props inválidos
    CleanInvalidProps()
    
    -- Mostrar mensaje si no hay props
    if #selectedProps == 0 then
        local noPropsLabel = propsListPanel:Add("DLabel")
        noPropsLabel:SetText("No props selected")
        noPropsLabel:Dock(TOP)
        noPropsLabel:SetTextColor(Color(128, 128, 128))
        noPropsLabel:DockMargin(5, 5, 5, 2)
        return
    end
    
    -- Agregar cada prop con su configuración
    for i, prop in ipairs(selectedProps) do
        if IsValid(prop) then
            CreatePropConfigPanel(propsListPanel, prop, i)
        end
    end
end

-- Función para crear la configuración de un prop individual
CreatePropConfigPanel = function(parent, prop, index)
    if not IsValid(prop) then return end
    
    local config = GetPropConfig(prop)
    if not config then return end
    
    -- Panel contenedor para este prop
    local propPanel = parent:Add("DCollapsibleCategory")
    propPanel:SetLabel(string.format("%d. %s", index, GetPropName(prop)))
    propPanel:SetExpanded(false)
    propPanel:Dock(TOP)
    propPanel:DockMargin(0, 2, 0, 2)
    
    -- Panel interno
    local innerPanel = vgui.Create("DPanel")
    innerPanel:SetTall(240)
    innerPanel:SetPaintBackground(false)
    propPanel:SetContents(innerPanel)
    
    -- Direction ComboBox
    local dirLabel = innerPanel:Add("DLabel")
    dirLabel:SetText("Direction:")
    dirLabel:SetPos(10, 10)
    dirLabel:SetSize(80, 20)
    dirLabel:SetTextColor(Color(0, 0, 0))
    
    local dirCombo = innerPanel:Add("DComboBox")
    dirCombo:SetPos(100, 10)
    dirCombo:SetSize(120, 20)
    dirCombo:AddChoice("UP")
    dirCombo:AddChoice("DOWN")
    dirCombo:AddChoice("LEFT")
    dirCombo:AddChoice("RIGHT")
    dirCombo:AddChoice("BACK")
    dirCombo:AddChoice("FORWARD")
    dirCombo:SetValue(config.direction)
    dirCombo.OnSelect = function(self, index, value)
        UpdatePropConfig(prop, "direction", value)
    end
    
    -- Distance NumSlider
    local distLabel = innerPanel:Add("DLabel")
    distLabel:SetText("Distance:")
    distLabel:SetPos(10, 40)
    distLabel:SetSize(80, 20)
    distLabel:SetTextColor(Color(0, 0, 0))
    
    local distSlider = innerPanel:Add("DNumSlider")
    distSlider:SetPos(-100, 38)
    distSlider:SetSize(400, 20)
    distSlider:SetMin(1)
    distSlider:SetMax(1000)
    distSlider:SetDecimals(0)
    distSlider:SetValue(config.distance)
    distSlider.OnValueChanged = function(self, value)
        UpdatePropConfig(prop, "distance", math.floor(value))
    end
    
    -- Time NumSlider
    local timeLabel = innerPanel:Add("DLabel")
    timeLabel:SetText("Time:")
    timeLabel:SetPos(10, 70)
    timeLabel:SetSize(80, 20)
    timeLabel:SetTextColor(Color(0, 0, 0))
    
    local timeSlider = innerPanel:Add("DNumSlider")
    timeSlider:SetPos(-100, 68)
    timeSlider:SetSize(400, 20)
    timeSlider:SetMin(0.1)
    timeSlider:SetMax(30)
    timeSlider:SetDecimals(1)
    timeSlider:SetValue(config.time)
    timeSlider.OnValueChanged = function(self, value)
        UpdatePropConfig(prop, "time", value)
    end
    
    -- Cooldown NumSlider
    local coolLabel = innerPanel:Add("DLabel")
    coolLabel:SetText("Cooldown:")
    coolLabel:SetPos(10, 100)
    coolLabel:SetSize(80, 20)
    coolLabel:SetTextColor(Color(0, 0, 0))
    
    local coolSlider = innerPanel:Add("DNumSlider")
    coolSlider:SetPos(-100, 98)
    coolSlider:SetSize(400, 20)
    coolSlider:SetMin(0)
    coolSlider:SetMax(60)
    coolSlider:SetDecimals(1)
    coolSlider:SetValue(config.cooldown)
    coolSlider.OnValueChanged = function(self, value)
        UpdatePropConfig(prop, "cooldown", value)
    end
    
    -- Botón Eliminar
    local removeBtn = innerPanel:Add("DButton")
    removeBtn:SetText("Remove Prop")
    removeBtn:SetPos(190, 130)
    removeBtn:SetSize(90, 25)
    removeBtn.DoClick = function()
        -- Detener movimiento antes de eliminar
        net.Start("PropMovement_Stop")
        net.WriteInt(prop:EntIndex(), 16)
        net.SendToServer()
        net.Start("PropMovement_Remove")
        net.WriteInt(prop:EntIndex(), 16)
        net.SendToServer()
        RemovePropConfig(prop)
        UpdatePropsList()
        surface.PlaySound("buttons/button15.wav")
    end
    
    -- Botón Start Movement
    local startBtn = innerPanel:Add("DButton")
    startBtn:SetText("Start Movement")
    startBtn:SetPos(0, 130)
    startBtn:SetSize(90, 25)
    startBtn.DoClick = function()
        -- Enviar configuración actualizada y iniciar movimiento
        net.Start("PropMovement_Config")
        net.WriteInt(prop:EntIndex(), 16)
        net.WriteTable(config)
        net.SendToServer()
        
        -- Iniciar movimiento
        net.Start("PropMovement_Start")
        net.WriteInt(prop:EntIndex(), 16)
        net.SendToServer()
        
        surface.PlaySound("buttons/button14.wav")
    end
    
    -- Botón Stop Movement
    local stopBtn = innerPanel:Add("DButton")
    stopBtn:SetText("Stop Movement")
    stopBtn:SetPos(95, 130)
    stopBtn:SetSize(90, 25)
    stopBtn.DoClick = function()
        net.Start("PropMovement_Stop")
        net.WriteInt(prop:EntIndex(), 16)
        net.SendToServer()
        
        surface.PlaySound("buttons/button15.wav")
    end
end

-- Función principal del click izquierdo
function TOOL:LeftClick(tr)
    if not IsFirstTimePredicted() then return false end
    if RankLevel(self:GetOwner()) <= #selectedProps then
        notification.AddLegacy( "You have reached the maximum number of props you can select.", NOTIFY_ERROR, 5 )
        surface.PlaySound("buttons/button10.wav")
        return false
    end
    -- Verificar que sea un prop válido
    if not IsValid(tr.Entity) or tr.Entity:GetClass() ~= "prop_physics" then
        return false
    end
    
    -- Verificar si ya está seleccionado (con callback para manejar respuesta del servidor)
    IsAlreadySelected(tr.Entity, function(isSelected)
        if isSelected then
            surface.PlaySound("buttons/button10.wav")
            return
        end
        
        -- Si no está seleccionado, agregarlo
        table.insert(selectedProps, tr.Entity)
        InitPropConfig(tr.Entity) -- Inicializar configuración del prop
        
        -- Enviar configuración inicial al servidor
        local config = GetPropConfig(tr.Entity)
        if config then
            net.Start("PropMovement_Config")
            net.WriteInt(tr.Entity:EntIndex(), 16)
            net.WriteTable(config)
            net.SendToServer()
        end
        
        -- Actualizar UI
        UpdatePropsList()
    end)
    
    return true
end

-- Función para la tecla R (Reload)
function TOOL:Reload(tr)
    if not IsFirstTimePredicted() then return false end
    
    -- Verificar que sea un prop válido
    if not IsValid(tr.Entity) or tr.Entity:GetClass() ~= "prop_physics" then
        return false
    end
    
    -- Verificar si el prop está en la lista seleccionada
    if not IsAlreadySelectedLocal(tr.Entity) then
        surface.PlaySound("buttons/button10.wav") -- Sonido de error
        return false
    end
    
    -- Detener movimiento antes de eliminar
    net.Start("PropMovement_Stop")
    net.WriteInt(tr.Entity:EntIndex(), 16)
    net.SendToServer()
    
    -- Enviar comando para eliminar configuración del servidor
    net.Start("PropMovement_Remove")
    net.WriteInt(tr.Entity:EntIndex(), 16)
    net.SendToServer()
    
    -- Eliminar prop de la configuración local
    RemovePropConfig(tr.Entity)
    
    -- Actualizar UI
    UpdatePropsList()
    
    -- Sonido de confirmación
    surface.PlaySound("buttons/button15.wav")
    
    return true
end

-- Receptor para la respuesta del servidor sobre verificación de entidades
net.Receive("PropMovement_ServerResponse", function()
    local entID = net.ReadInt(16)
    local existsInServer = net.ReadBool()
    
    -- Ejecutar todos los callbacks pendientes para esta entidad
    if pendingCallbacks[entID] then
        for _, callback in ipairs(pendingCallbacks[entID]) do
            callback(existsInServer)
        end
    end
    
    -- Limpiar estado pendiente
    serverCheckPending[entID] = nil
    pendingCallbacks[entID] = nil
end)

-- Función para crear la interfaz de usuario
function PropMovement_UI(panel)
    -- Limpiar panel
    panel:ClearControls()
    
    -- Boton para iniciar todos los props
    local startAll = vgui.Create("DButton")
    startAll:SetText("Start All Props")
    startAll:SetSize(100, 25)
    startAll.DoClick = function()
        for _, prop in ipairs(selectedProps) do
            if IsValid(prop) then
                -- Enviar configuración actualizada antes de iniciar
                local config = GetPropConfig(prop)
                if config then
                    net.Start("PropMovement_Config")
                    net.WriteInt(prop:EntIndex(), 16)
                    net.WriteTable(config)
                    net.SendToServer()
                end
                
                -- Iniciar movimiento
                net.Start("PropMovement_Start")
                net.WriteInt(prop:EntIndex(), 16)
                net.SendToServer()
            end
        end

        surface.PlaySound("buttons/button14.wav")
    end
    panel:AddItem(startAll)

    -- Boton para parar todos los props
    local stopAll = vgui.Create("DButton")
    stopAll:SetText("Stop All Props")
    stopAll:SetSize(100, 25)
    stopAll.DoClick = function()
        for _, prop in ipairs(selectedProps) do
            if IsValid(prop) then
                net.Start("PropMovement_Stop")
                net.WriteInt(prop:EntIndex(), 16)
                net.SendToServer()
            end
        end
        surface.PlaySound("buttons/button14.wav")
    end
    panel:AddItem(stopAll)

    -- Botón para limpiar selección
    local clearBtn = vgui.Create("DButton")
    clearBtn:SetText("Clear All")
    clearBtn:SetSize(100, 25)
    clearBtn.DoClick = function()
        -- Recopilar IDs de las entidades a limpiar
        local entIDs = {}
        for _, prop in ipairs(selectedProps) do
            if IsValid(prop) then
                table.insert(entIDs, prop:EntIndex())
                -- Detener movimiento
                net.Start("PropMovement_Stop")
                net.WriteInt(prop:EntIndex(), 16)
                net.SendToServer()
            end
        end
        
        -- Enviar lista al servidor para limpiar configuraciones
        if #entIDs > 0 then
            net.Start("PropMovement_ClearAll")
            net.WriteUInt(#entIDs, 8)
            for _, entID in ipairs(entIDs) do
                net.WriteInt(entID, 16)
            end
            net.SendToServer()
        end
        
        -- Limpiar listas locales
        selectedProps = {}
        propConfigs = {}
        
        UpdatePropsList()
        surface.PlaySound("buttons/button15.wav")
    end

    panel:AddItem(clearBtn)
    
    -- Panel con lista de props seleccionados
    local listHeader = vgui.Create("DLabel")
    listHeader:SetText("Selected Props:")
    listHeader:SetFont("DermaDefaultBold")
    listHeader:SetTextColor(Color(0, 0, 0))
    listHeader:SizeToContents()
    panel:AddItem(listHeader)
    
    -- Panel scrolleable para la lista
    propsListPanel = vgui.Create("DScrollPanel")
    propsListPanel:SetTall(780)
    panel:AddItem(propsListPanel)
    
    -- Actualizar lista inicial
    UpdatePropsList()
    
    -- Timer para actualizar automáticamente
    if not panel.PropMovementTimer then
        panel.PropMovementTimer = true
        panel.Think = function()
            if (panel.NextUpdate or 0) < CurTime() then
                panel.NextUpdate = CurTime() + 1 -- Actualizar cada segundo
                
                -- Limpiar props inválidos
                local oldCount = #selectedProps
                CleanInvalidProps()
                
                if #selectedProps ~= oldCount then
                    UpdatePropsList()
                end
            end
        end
    end
end
