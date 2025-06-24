-- Sistema de Hologramas para GunGame
local holograms = {}

-- Recibir y crear un nuevo holograma
net.Receive("GunGame_CreateHologram", function()
    local pos = net.ReadVector()
    local endTime = net.ReadFloat()
    
    -- Crear el efecto de holograma
    local ent = ClientsideModel("models/healthvial.mdl")
    if not IsValid(ent) then return end
    
    ent:SetPos(pos)
    ent:SetModelScale(2)
    ent:SetColor(Color(100, 255, 100, 200))
    ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
    ent:DrawShadow(false)
    
    -- Añadir a la tabla de hologramas
    local id = tostring(ent:EntIndex())
    holograms[id] = {
        ent = ent,
        endTime = endTime,
        angle = 0
    }
    
    -- Eliminar después de 5 segundos
    timer.Simple(5, function()
        if IsValid(ent) then
            ent:Remove()
        end
        holograms[id] = nil
    end)
end)

-- Actualizar hologramas (rotación y flotación)
hook.Add("Think", "UpdateHolograms", function()
    for id, holo in pairs(holograms) do
        if not IsValid(holo.ent) then
            holograms[id] = nil
            continue
        end
        
        -- Rotar el holograma
        holo.angle = (holo.angle + 0.5) % 360
        holo.ent:SetAngles(Angle(0, holo.angle, 0))
        
        -- Hacer que flote
        local pos = holo.ent:GetPos()
        pos.z = pos.z + math.sin(CurTime() * 2) * 0.5
        holo.ent:SetPos(pos)
    end
end)

-- Dibujar efectos del holograma
hook.Add("PostDrawTranslucentRenderables", "DrawHologramEffects", function()
    for id, holo in pairs(holograms) do
        if not IsValid(holo.ent) then continue end
        
        local pos = holo.ent:GetPos()
        
        -- Dibujar un efecto de brillo
        render.SetColorMaterial()
        render.DrawSphere(pos, 20, 10, 10, Color(0, 255, 0, 30))
    end
end)

-- Limpiar al desconectarse
hook.Add("OnReloaded", "CleanupHolograms", function()
    for id, holo in pairs(holograms) do
        if IsValid(holo.ent) then
            holo.ent:Remove()
        end
    end
    holograms = {}
end)
