-- Global UI function that will be called by the tool
function PropMovement_UI(panel)
    -- Clear the panel first
    panel:ClearControls()
    
    -- Header
    local header = vgui.Create("DLabel")
    header:SetText("PropMovement - Controles")
    header:SetFont("DermaDefaultBold")
    header:SetTextColor(Color(0, 0, 0))
    header:SizeToContents()
    panel:AddItem(header)
    
    -- Add a divider
    panel:AddControl("Header", { Description = "Configuración de movimiento" })
    
    -- Movement speed slider
    local movespeed = vgui.Create("DNumSlider", panel)
    movespeed:SetText("Velocidad de movimiento")
    movespeed:SetMin(1)
    movespeed:SetMax(100)
    movespeed:SetDecimals(0)
    movespeed:SetValue(PropMovement.Settings.MoveSpeed)
    movespeed:SetDark(true)
    movespeed.OnValueChanged = function(_, value)
        PropMovement.Settings.MoveSpeed = math.Round(tonumber(value) or 10)
    end
    panel:AddItem(movespeed)
    
    -- Rotation speed slider
    local rotspeed = vgui.Create("DNumSlider", panel)
    rotspeed:SetText("Velocidad de rotación")
    rotspeed:SetMin(0.1)
    rotspeed:SetMax(5)
    rotspeed:SetDecimals(1)
    rotspeed:SetValue(PropMovement.Settings.RotateSpeed)
    rotspeed:SetDark(true)
    rotspeed.OnValueChanged = function(_, value)
        PropMovement.Settings.RotateSpeed = tonumber(value) or 1
    end
    panel:AddItem(rotspeed)
    
    -- Grid size slider
    local gridsize = vgui.Create("DNumSlider", panel)
    gridsize:SetText("Tamaño de la grilla")
    gridsize:SetMin(0)
    gridsize:SetMax(10)
    gridsize:SetDecimals(1)
    gridsize:SetValue(PropMovement.Settings.GridSize)
    gridsize:SetDark(true)
    gridsize.OnValueChanged = function(_, value)
        PropMovement.Settings.GridSize = tonumber(value) or 1
    end
    panel:AddItem(gridsize)
    
    -- Snap to grid checkbox
    local snap = vgui.Create("DCheckBoxLabel", panel)
    snap:SetText("Ajustar a la grilla")
    snap:SetValue(PropMovement.Settings.SnapToGrid and 1 or 0)
    snap:SetDark(true)
    snap.OnChange = function(_, value)
        PropMovement.Settings.SnapToGrid = tobool(value)
    end
    panel:AddItem(snap)
    
    -- Add a divider for selected props section
    panel:AddControl("Header", { Description = "Props Seleccionados" })
    
    -- Scroll panel for selected props
    local scroll = vgui.Create("DScrollPanel", panel)
    scroll:SetTall(200)
    panel:AddItem(scroll)
    
    -- Function to update the props list
    local function UpdatePropsList()
        scroll:Clear()
        
        for entIndex, propData in pairs(PropMovement.SelectedProps) do
            if not IsValid(propData.ent) then
                PropMovement.SelectedProps[entIndex] = nil
                continue
            end
            
            local panel = vgui.Create("DPanel", scroll)
            panel:Dock(TOP)
            panel:DockMargin(0, 0, 0, 5)
            panel:SetTall(110)
            panel:DockPadding(5, 5, 5, 5)
            panel.Paint = function(self, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(240, 240, 240))
                draw.RoundedBox(4, 1, 1, w-2, h-2, Color(255, 255, 255, 255))
            end
            
            -- Prop name label
            local name = vgui.Create("DLabel", panel)
            name:SetText("Entidad #" .. entIndex)
            name:SetDark(true)
            name:Dock(TOP)
            name:SetContentAlignment(4)
            
            -- Direction combo
            local dir = vgui.Create("DComboBox", panel)
            dir:Dock(TOP)
            dir:DockMargin(0, 5, 0, 0)
            dir:SetValue(propData.direction)
            for dirName, _ in SortedPairs(PropMovement.Directions) do
                dir:AddChoice(dirName)
            end
            dir.OnSelect = function(_, _, value)
                if PropMovement.SelectedProps[entIndex] then
                    PropMovement.SelectedProps[entIndex].direction = value
                end
            end
            
            -- Speed entry
            local speed = vgui.Create("DTextEntry", panel)
            speed:Dock(TOP)
            speed:DockMargin(0, 5, 0, 0)
            speed:SetPlaceholderText("Velocidad")
            speed:SetValue(propData.speed)
            speed.OnEnter = function(self)
                local val = tonumber(self:GetValue()) or 100
                if PropMovement.SelectedProps[entIndex] then
                    PropMovement.SelectedProps[entIndex].speed = math.Clamp(val, 1, 1000)
                    self:SetValue(PropMovement.SelectedProps[entIndex].speed)
                end
            end
            
            -- Distance entry
            local distance = vgui.Create("DTextEntry", panel)
            distance:Dock(TOP)
            distance:DockMargin(0, 5, 0, 0)
            distance:SetPlaceholderText("Distancia")
            distance:SetValue(propData.distance)
            distance.OnEnter = function(self)
                local val = tonumber(self:GetValue()) or 100
                if PropMovement.SelectedProps[entIndex] then
                    PropMovement.SelectedProps[entIndex].distance = math.Clamp(val, 1, 10000)
                    self:SetValue(PropMovement.SelectedProps[entIndex].distance)
                end
            end
            
            -- Cooldown entry
            local cooldown = vgui.Create("DTextEntry", panel)
            cooldown:Dock(TOP)
            cooldown:DockMargin(0, 5, 0, 0)
            cooldown:SetPlaceholderText("Cooldown (segundos)")
            cooldown:SetValue(propData.cooldown)
            cooldown.OnEnter = function(self)
                local val = tonumber(self:GetValue()) or 1
                if PropMovement.SelectedProps[entIndex] then
                    PropMovement.SelectedProps[entIndex].cooldown = math.Clamp(val, 0.1, 60)
                    self:SetValue(PropMovement.SelectedProps[entIndex].cooldown)
                end
            end
            
            -- Remove button
            local remove = vgui.Create("DButton", panel)
            remove:Dock(TOP)
            remove:DockMargin(0, 5, 0, 0)
            remove:SetText("Eliminar")
            remove.DoClick = function()
                if IsValid(propData.ent) then
                    PropMovement.RemoveProp(propData.ent)
                    UpdatePropsList()
                end
            end
        end
    end
    
    -- Clear all button
    local clear = vgui.Create("DButton", panel)
    clear:Dock(TOP)
    clear:DockMargin(0, 5, 0, 0)
    clear:SetText("Limpiar selección")
    clear.DoClick = function()
        PropMovement.ClearProps()
        UpdatePropsList()
    end
    
    -- Initial update
    UpdatePropsList()
    
    -- Add some space
    panel:AddControl("Label", { Text = "" })
    
    -- Help text
    local help = vgui.Create("DLabel")
    help:SetText("Instrucciones:\n- Click izquierdo: Seleccionar objeto\n- Click derecho: Mover objeto\n- Rueda del ratón: Acercar/alejar\n- Q/E: Rotar\n- R: Reiniciar posición")
    help:SetTextColor(Color(0, 0, 0))
    help:SizeToContents()
    panel:AddItem(help)
end

-- Handle prop selection on left click when tool is active
hook.Add("KeyPress", "PropMovement_SelectProps", function(ply, key)
    if key ~= IN_ATTACK then return end
    if not IsFirstTimePredicted() then return end
    
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= "gmod_tool" or wep:GetMode() ~= "propmovement" then return end
    
    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:EyeAngles():Forward() * 10000,
        filter = ply
    })
    
    if IsValid(tr.Entity) and (tr.Entity:GetClass() == "prop_physics" or tr.Entity:GetClass() == "prop_dynamic") then
        if PropMovement.AddProp(tr.Entity) then
            -- Update the props list in the UI
            local toolPanel = controlpanel.Get("propmovement")
            if IsValid(toolPanel) then
                PropMovement_UI(toolPanel)
            end
            -- Don't return true here, allow the attack to continue
        end
    end
end)
