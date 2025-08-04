-- Tabla para almacenar los props seleccionados con información adicional
local selectedProps = {}
local selectedPropsPanel = nil
local mainPanel = nil

-- Función para obtener un nombre descriptivo del prop
local function GetPropDisplayName(ent)
    if not IsValid(ent) then return "Invalid Entity" end
    
    local model = ent:GetModel() or "unknown"
    local modelName = string.GetFileFromFilename(model)
    local entIndex = ent:EntIndex()
    
    return string.format("%s (ID: %d)", modelName, entIndex)
end

-- Función para actualizar la lista de props en la UI
local function UpdateSelectedPropsUI()
    if not IsValid(selectedPropsPanel) then return end
    
    -- Limpiar la lista actual
    selectedPropsPanel:Clear()
    
    -- Limpiar props inválidos de la lista primero
    for i = #selectedProps, 1, -1 do
        if not IsValid(selectedProps[i].entity) then
            table.remove(selectedProps, i)
        end
    end
    
    -- Agregar cada prop a la lista
    if #selectedProps == 0 then
        local noPropsLabel = selectedPropsPanel:Add("DLabel")
        noPropsLabel:SetText("No props selected")
        noPropsLabel:Dock(TOP)
        noPropsLabel:SetTextColor(Color(100, 100, 100))
        noPropsLabel:DockMargin(5, 2, 5, 2)
        noPropsLabel:SizeToContents()
    else
        for i, propData in ipairs(selectedProps) do
            if IsValid(propData.entity) then
                local label = selectedPropsPanel:Add("DLabel")
                label:SetText(string.format("%d. %s", i, propData.displayName))
                label:Dock(TOP)
                label:SetTextColor(Color(0, 0, 0))
                label:DockMargin(5, 2, 5, 2)
                label:SizeToContents()
            end
        end
    end
    
    -- Actualizar el contador en el header
    if IsValid(mainPanel) and IsValid(mainPanel.headerLabel) then
        mainPanel.headerLabel:SetText(string.format("Selected Props (%d):", #selectedProps))
        mainPanel.headerLabel:SizeToContents()
    end
end

-- Función para manejar la selección de props
local function SelectProp(ent)
    if not IsValid(ent) or ent:GetClass() ~= "prop_physics" then 
        return false 
    end
    
    -- Verificar si el prop ya está en la lista
    for i, propData in ipairs(selectedProps) do
        if not IsValid(propData.entity) then
            -- Remover props inválidos
            table.remove(selectedProps, i)
        elseif propData.entity == ent then
            -- Ya existe
            return false
        end
    end
    
    -- Agregar el prop a la lista
    local propData = {
        entity = ent,
        displayName = GetPropDisplayName(ent),
        model = ent:GetModel(),
        entIndex = ent:EntIndex()
    }
    
    table.insert(selectedProps, propData)
    surface.PlaySound("buttons/button14.wav")
    return true
end

-- Función para el clic izquierdo
function TOOL:LeftClick(tr)
    if not IsFirstTimePredicted() then return false end
    if not IsValid(tr.Entity) or tr.Entity:GetClass() ~= "prop_physics" then 
        return false 
    end
    
    -- Crear el efecto del rayo de la toolgun
    local effectdata = EffectData()
    effectdata:SetOrigin(tr.HitPos)
    effectdata:SetStart(self:GetOwner():GetShootPos())
    effectdata:SetAttachment(1)
    effectdata:SetEntity(self:GetOwner())
    util.Effect("ToolTracer", effectdata)
    
    -- Seleccionar el prop
    local success = SelectProp(tr.Entity)
    
    -- Actualizar la UI
    UpdateSelectedPropsUI()
    
    return success
end

-- Global UI function that will be called by the tool
function PropMovement_UI(panel)
    -- Clear the panel first
    panel:ClearControls()
    mainPanel = panel
    
    -- Header con contador
    local headerLabel = vgui.Create("DLabel")
    headerLabel:SetText(string.format("Selected Props (%d):", #selectedProps))
    headerLabel:SetFont("DermaDefaultBold")
    headerLabel:SetTextColor(Color(0, 0, 0))
    headerLabel:SizeToContents()
    panel:AddItem(headerLabel)
    mainPanel.headerLabel = headerLabel
    
    -- Instrucciones
    local instructionLabel = vgui.Create("DLabel")
    instructionLabel:SetText("Left click on props to select them")
    instructionLabel:SetTextColor(Color(60, 60, 60))
    instructionLabel:SizeToContents()
    panel:AddItem(instructionLabel)
    
    -- Botón para limpiar selección
    local clearButton = vgui.Create("DButton")
    clearButton:SetText("Clear All")
    clearButton.DoClick = function()
        selectedProps = {}
        UpdateSelectedPropsUI()
        surface.PlaySound("buttons/button15.wav")
    end
    panel:AddItem(clearButton)
    
    -- Panel para la lista de props
    selectedPropsPanel = vgui.Create("DScrollPanel")
    selectedPropsPanel:SetTall(200)
    panel:AddItem(selectedPropsPanel)
    
    -- Actualizar la UI con los props ya seleccionados
    UpdateSelectedPropsUI()
    
    -- Timer para limpiar props inválidos automáticamente
    if not panel.PropMovementInitialized then
        panel.Think = function()
            -- Verificar cada 2 segundos
            if (panel.NextCheck or 0) < CurTime() then
                panel.NextCheck = CurTime() + 2
                
                local removed = 0
                for i = #selectedProps, 1, -1 do
                    if not IsValid(selectedProps[i].entity) then
                        table.remove(selectedProps, i)
                        removed = removed + 1
                    end
                end
                
                if removed > 0 then
                    UpdateSelectedPropsUI()
                end
            end
        end
        panel.PropMovementInitialized = true
    end
end