TOOL = TOOL or {}
TOOL.Name = "GunGame"
TOOL.Category = "CGO Admin Tools"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
    GUNGAME_AREA_POINTS = {}
    net.Receive("gungame_area_update_points", function()
        GUNGAME_AREA_POINTS = net.ReadTable() or {}
        if IsValid(GUNGAME_AREA_PANEL) then
            GUNGAME_AREA_PANEL:InvalidateLayout(true)
        end
    end)
end

function TOOL.BuildCPanel(panel)
    if panel.SetName then panel:SetName("") end

    if CLIENT then
        GUNGAME_AREA_PANEL = panel

        panel:DockPadding(8, 8, 8, 8)
        local headerPanel = vgui.Create("DPanel", panel)
        headerPanel:Dock(TOP)
        headerPanel:SetTall(32)
        headerPanel:SetPaintBackground(false)

        local circle = vgui.Create("DPanel", headerPanel)
        circle:Dock(LEFT)
        circle:SetWide(28)
        circle.Paint = function(self, w, h)
            local points = GUNGAME_AREA_POINTS or {}
            local color = (#points >= 4) and Color(0, 200, 0) or Color(200, 0, 0)
            draw.RoundedBox(8, 6, 6, 20, 20, color)
        end

        local label = vgui.Create("DLabel", headerPanel)
        label:Dock(LEFT)
        label:DockMargin(8, 0, 0, 0)
        label:SetText("Set the game area")
        label:SetFont("DermaDefaultBold")
        label:SetTextColor(Color(40,40,40))
        label:SizeToContents()
        net.Receive("gungame_area_update_points", function()
            GUNGAME_AREA_POINTS = net.ReadTable() or {}
            if IsValid(circle) then circle:InvalidateLayout(true) end
            if IsValid(GUNGAME_AREA_PANEL) then GUNGAME_AREA_PANEL:InvalidateLayout(true) end
        end)

        panel.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(255,255,255,245))
            surface.SetDrawColor(180, 180, 180, 255)
            surface.DrawOutlinedRect(0, 0, w, h)
        end

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
        end

        local eventActive = false
        local btnStart = vgui.Create("DButton", panel)
        btnStart:SetText("Start event")
        btnStart:Dock(TOP)
        btnStart:DockMargin(0, 24, 0, 0)
        btnStart:SetTall(32)
        btnStart:SetFont("DermaDefaultBold")
        btnStart:SetWide(panel:GetWide() - 16)

        local function setButtonState(active)
            eventActive = active
            if active then
                btnStart:SetText("Stop event")
                btnSelect:SetEnabled(false)
                btnDelete:SetEnabled(false)
            else
                btnStart:SetText("Start event")
                btnSelect:SetEnabled(true)
                btnDelete:SetEnabled(true)
            end
        end

        btnStart.DoClick = function()
            if not eventActive then
                Derma_Query(
                    "Are you sure you want to start the event?",
                    "Confirm event start",
                    "Yes", function()
                        net.Start("gungame_start_event")
                        net.SendToServer()
                        setButtonState(true)
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
                        setButtonState(false)
                    end,
                    "No"
                )
            end
        end

        net.Receive("gungame_event_stopped", function()
            setButtonState(false)
        end)
    else
        panel:Button("Select area", "gungame_area_start")
        panel:Button("Delete selection", "gungame_area_clear")
    end
end

if CLIENT then
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
end

if SERVER then
    util.AddNetworkString("gungame_area_start")
    util.AddNetworkString("gungame_area_clear")
    util.AddNetworkString("gungame_area_update_points")
    util.AddNetworkString("gungame_start_event")
    util.AddNetworkString("gungame_stop_event")
    util.AddNetworkString("gungame_event_stopped")

    local selecting = {}
    local points = {}
    local gungame_players = {} -- Ahora es lista de SteamID64
    local gungame_area_center = nil
    local gungame_event_active = false
    local gungame_area_points = nil
    local gungame_respawn_time = {}

    net.Receive("gungame_area_start", function(_, ply)
        if gungame_event_active then return end
        selecting[ply] = true
        points[ply] = {}
        net.Start("gungame_area_update_points")
            net.WriteTable(points[ply])
        net.Send(ply)
    end)
    net.Receive("gungame_area_clear", function(_, ply)
        if gungame_event_active then return end
        selecting[ply] = false
        points[ply] = {}
        net.Start("gungame_area_update_points")
            net.WriteTable(points[ply])
        net.Send(ply)
    end)

    net.Receive("gungame_start_event", function(_, ply)
        local area = points[ply]
        if not area or #area < 3 then return end

        gungame_area_points = area

        local center = Vector(0,0,0)
        for _, v in ipairs(area) do center = center + v end
        center = center / #area
        gungame_area_center = center

        gungame_players = {}
        for _, p in ipairs(player.GetAll()) do
            local pos = p:GetPos()
            if PointInPoly2D(pos, area) then
                table.insert(gungame_players, p:SteamID64())
            end
        end

        gungame_event_active = true

        print("[GunGame] Event started! Players in area: " .. #gungame_players)
    end)

    net.Receive("gungame_stop_event", function(_, ply)
        -- Limpiar todo
        gungame_players = {}
        gungame_area_center = nil
        gungame_event_active = false
        gungame_area_points = nil

        points[ply] = {}
        net.Start("gungame_area_update_points")
            net.WriteTable({})
        net.Send(ply)

        net.Start("gungame_event_stopped")
        net.Broadcast()
    end)

    function PointInPoly2D(pos, poly)
        local x, y = pos.x, pos.y
        local inside = false
        local j = #poly
        for i = 1, #poly do
            local xi, yi = poly[i].x, poly[i].y
            local xj, yj = poly[j].x, poly[j].y
            if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 0.00001) + xi) then
                inside = not inside
            end
            j = i
        end
        return inside
    end

    hook.Add("PlayerSpawn", "gungame_respawn_in_area", function(ply)
        if not gungame_event_active then return end
        if not gungame_area_center then return end
        if not ply:IsValid() then return end
        if table.HasValue(gungame_players, ply:SteamID64()) then
            gungame_respawn_time[ply:SteamID64()] = CurTime()
            timer.Simple(0, function()
                if IsValid(ply) then
                    ply:SetPos(gungame_area_center)
                end
            end)
        end
    end)

    timer.Remove("gungame_area_check")
    timer.Create("gungame_area_check", 1, 0, function()
        if not gungame_event_active or not gungame_players or not gungame_area_center or not gungame_area_points then return end
        local area = gungame_area_points
        for _, ply in ipairs(player.GetAll()) do
            if table.HasValue(gungame_players, ply:SteamID64()) and IsValid(ply) and ply:Alive() then
                if not PointInPoly2D(ply:GetPos(), area) then
                    ply:Kill()
                end
            end
        end
    end)

    function TOOL:LeftClick(trace)
        if not selecting[self:GetOwner()] then return false end
        if CLIENT then return true end
        local ply = self:GetOwner()
        points[ply] = points[ply] or {}
        if #points[ply] < 4 then
            table.insert(points[ply], trace.HitPos+Vector(0, 0, 10))
            net.Start("gungame_area_update_points")
                net.WriteTable(points[ply])
            net.Send(ply)
        end
        if #points[ply] >= 4 then
            selecting[ply] = false
        end
        return true
    end

    function TOOL:RightClick(trace)
        return false
    end

    function TOOL:Deploy()
        local ply = self:GetOwner()
        net.Start("gungame_area_update_points")
            net.WriteTable(points[ply] or {})
        net.Send(ply)
    end

    function TOOL:Holster()
        local ply = self:GetOwner()
        selecting[ply] = false
        points[ply] = {}
        net.Start("gungame_area_update_points")
            net.WriteTable({})
        net.Send(ply)
    end
end

if CLIENT then
    hook.Add("PostDrawTranslucentRenderables", "gungame_area_draw_points", function()
        local ply = LocalPlayer()
        local wep = ply:GetActiveWeapon()
        if not (IsValid(wep) and wep:GetClass() == "gmod_tool" and ply:GetTool() and ply:GetTool().Mode == "gungame") then return end
        local points = GUNGAME_AREA_POINTS or {}
        if not points or #points == 0 then return end

        render.SetColorMaterial()
        for i, pos in ipairs(points) do
            render.DrawSphere(pos, 8, 16, 16, Color(255, 0, 0, 180))
            if i > 1 then
                render.DrawLine(points[i-1], pos, Color(255, 0, 0), true)
            end
        end

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

        if #points == 4 then
            render.DrawLine(points[4], points[1], Color(255, 0, 0), true)
        end
    end)
end
