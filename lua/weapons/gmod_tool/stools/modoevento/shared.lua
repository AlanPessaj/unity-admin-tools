MODO_EVENTO = MODO_EVENTO or {}

local allowedRanks = {
    ["superadmin"] = true,
    ["moderadorelite"] = true,
    ["moderadorsenior"] = true,
    ["moderador"] = true,
    ["directormods"] = true,
    ["ejecutivo"] = true
}

MODO_EVENTO.IsActive = MODO_EVENTO.IsActive or false

function MODO_EVENTO.HasAccess(ply)
    if not IsValid(ply) or not ply.GetUserGroup then
        return false
    end

    if ply:IsSuperAdmin() then
        return true
    end

    local group = ply:GetUserGroup()
    if not group then
        return false
    end

    return allowedRanks[group:lower()] == true
end
