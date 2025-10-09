-- Ensures F4 is blocked while participating in an active GunGame event.
-- This file runs very early (autorun) to guard against other addons.

local IsParticipant = false

net.Receive("gungame_participation", function()
    IsParticipant = net.ReadBool() and true or false
end)

local function ShouldBlockF4()
    return IsParticipant
end

local lastWarn = 0
local function WarnOnce()
    local now = CurTime()
    if now - (lastWarn or 0) < 0.8 then return end
    lastWarn = now
    notification.AddLegacy("No puedes abrir el menú F4 durante el evento.", NOTIFY_ERROR, 1)
    surface.PlaySound("buttons/button10.wav")
end

hook.Add("PlayerBindPress", "UAT_GunGame_BlockF4_Binds", function(ply, bind, pressed)
    if not pressed then return end
    if not ShouldBlockF4() then return end
    if not isstring(bind) then return end
    bind = string.lower(bind)
    if string.find(bind, "gm_showspare2", 1, true) then
        WarnOnce()
        return true
    end
end)

hook.Add("ShowSpare2", "UAT_GunGame_BlockF4_Spare2", function()
    if not ShouldBlockF4() then return end
    WarnOnce()
    return true
end)

-- As an extra safety, wrap the DarkRP F4 menu function once it's available
local function InstallF4Guard()
    if not DarkRP or not DarkRP.toggleF4Menu then return end
    if DarkRP._UAT_F4GuardInstalled then return end

    local old = DarkRP.toggleF4Menu
    DarkRP.toggleF4Menu = function(...)
        if ShouldBlockF4() then
            WarnOnce()
            return
        end
        return old(...)
    end
    DarkRP._UAT_F4GuardInstalled = true
end

timer.Create("UAT_GunGame_InstallF4Guard", 1, 0, function()
    InstallF4Guard()
    if DarkRP and DarkRP._UAT_F4GuardInstalled then
        timer.Remove("UAT_GunGame_InstallF4Guard")
    end
end)
