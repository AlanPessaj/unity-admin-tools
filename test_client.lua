local frame = vgui.Create("DFrame")
frame:SetSize(100, 100)
frame:SetVisible(true)
frame:SetTitle("ex")
frame:Center()
frame:MakePopup()

local b = vgui.Create("DButton", frame)
b.DoClick = function()
    net.Start("MessageName")
    net.SendToServer()
end