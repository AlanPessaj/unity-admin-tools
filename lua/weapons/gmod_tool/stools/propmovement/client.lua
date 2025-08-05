-- PropMovement Client Side
-- Variables globales para almacenar props seleccionados
local selectedProps = {}
local propsListPanel = nil

-- Función para obtener nombre descriptivo del prop
local function GetPropName(ent)
    if not IsValid(ent) then return "Invalid" end
    
    local model = ent:GetModel() or "unknown"
    local fileName = string.GetFileFromFilename(model)
    local entID = ent:EntIndex()
    
    return string.format("%s [%d]", fileName, entID)
end

-- Función para verificar si un prop ya está seleccionado
local function IsAlreadySelected(ent)
    for _, prop in ipairs(selectedProps) do
        if IsValid(prop) and prop == ent then
            return true
        end
    end
    return false
end

-- Función para limpiar props inválidos de la lista
local function CleanInvalidProps()
    for i = #selectedProps, 1, -1 do
        if not IsValid(selectedProps[i]) then
            table.remove(selectedProps, i)
        end
    end
end

-- Función para actualizar la lista visual de props
local function UpdatePropsList()
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
    
    -- Agregar cada prop a la lista
    for i, prop in ipairs(selectedProps) do
        if IsValid(prop) then
            local propLabel = propsListPanel:Add("DLabel")
            propLabel:SetText(string.format("%d. %s", i, GetPropName(prop)))
            propLabel:Dock(TOP)
            propLabel:SetTextColor(Color(0, 0, 0))
            propLabel:DockMargin(5, 2, 5, 2)
        end
    end
end

-- Función principal del click izquierdo
function TOOL:LeftClick(tr)
    if not IsFirstTimePredicted() then return false end
    
    -- Verificar que sea un prop válido
    if not IsValid(tr.Entity) or tr.Entity:GetClass() ~= "prop_physics" then
        return false
    end
    
    -- Crear efecto visual del rayo
    local effectData = EffectData()
    effectData:SetOrigin(tr.HitPos)
    effectData:SetStart(self:GetOwner():GetShootPos())
    effectData:SetAttachment(1)
    effectData:SetEntity(self:GetOwner())
    util.Effect("ToolTracer", effectData)
    
    -- Verificar si ya está seleccionado
    if IsAlreadySelected(tr.Entity) then
        surface.PlaySound("buttons/button10.wav") -- Sonido de error
        return false
    end
    
    -- Agregar prop a la lista
    table.insert(selectedProps, tr.Entity)
    surface.PlaySound("buttons/button14.wav") -- Sonido de éxito
    
    -- Actualizar UI
    UpdatePropsList()
    
    return true
end

-- Función para crear la interfaz de usuario
function PropMovement_UI(panel)
    -- Limpiar panel
    panel:ClearControls()
    
    -- Título
    local titleLabel = vgui.Create("DLabel")
    titleLabel:SetText("PropMovement Tool")
    titleLabel:SetFont("DermaDefaultBold")
    titleLabel:SetTextColor(Color(0, 0, 0))
    titleLabel:SizeToContents()
    panel:AddItem(titleLabel)
    
    -- Instrucciones
    local instructLabel = vgui.Create("DLabel")
    instructLabel:SetText("Left click on props to select them")
    instructLabel:SetTextColor(Color(64, 64, 64))
    instructLabel:SizeToContents()
    panel:AddItem(instructLabel)
    
    -- Contador de props
    local countLabel = vgui.Create("DLabel")
    countLabel:SetText(string.format("Selected: %d props", #selectedProps))
    countLabel:SetTextColor(Color(0, 100, 0))
    countLabel:SizeToContents()
    panel:AddItem(countLabel)
    
    -- Botón para limpiar selección
    local clearBtn = vgui.Create("DButton")
    clearBtn:SetText("Clear All")
    clearBtn:SetSize(100, 25)
    clearBtn.DoClick = function()
        selectedProps = {}
        UpdatePropsList()
        countLabel:SetText("Selected: 0 props")
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
    propsListPanel:SetTall(150)
    panel:AddItem(propsListPanel)
    
    -- Actualizar lista inicial
    UpdatePropsList()
    
    -- Timer para actualizar automáticamente
    if not panel.PropMovementTimer then
        panel.PropMovementTimer = true
        panel.Think = function()
            if (panel.NextUpdate or 0) < CurTime() then
                panel.NextUpdate = CurTime() + 1 -- Actualizar cada segundo
                
                -- Limpiar props inválidos y actualizar contador
                local oldCount = #selectedProps
                CleanInvalidProps()
                
                if #selectedProps ~= oldCount then
                    UpdatePropsList()
                    countLabel:SetText(string.format("Selected: %d props", #selectedProps))
                end
            end
        end
    end
end
