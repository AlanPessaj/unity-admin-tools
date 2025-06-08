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
            surface.SetDrawColor(40, 40, 40, 240)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(0, 120, 255, 255)
            surface.DrawOutlinedRect(0, 0, w, h, 4)
            draw.SimpleText("SELECTOR DE PERSONAJE", "DermaDefaultBold", w/2, 15, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        -- Botón de cierre
        local closeBtn = vgui.Create("DButton", panel)
        closeBtn:SetText("X")
        closeBtn:SetFont("DermaDefaultBold")
        closeBtn:SetTextColor(Color(255, 255, 255))
        closeBtn:SetSize(30, 30)
        closeBtn:SetPos(panel:GetWide() - 35, 5)
        closeBtn.Paint = function() end
        closeBtn.DoClick = function()
            panel:Remove()
            CAMERA:StopSequence()
        end
        
        -- Contenido del panel
        --local content = vgui.Create("DLabel", panel)
        --content:SetTextColor(Color(255, 255, 255))
        --content:SizeToContents()
        --content:Center()
        
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