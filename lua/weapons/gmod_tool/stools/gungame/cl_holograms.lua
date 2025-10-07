-- Sistema de Hologramas para GunGame
local holograms = {}
local HOLOGRAM_RADIUS = 75 -- Radio de colisión del holograma
local HOLOGRAM_VERTICAL_LIMIT = 120 -- Límite vertical para la colisión
local COLLISION_COOLDOWN = 0.3 -- Tiempo entre comprobaciones de colisión
local lastCollisionCheck = 0

-- Recibir y crear un nuevo holograma
net.Receive("GunGame_CreateHologram", function()
    local pos = net.ReadVector()
    local endTime = net.ReadFloat()
    local holoID = net.ReadString()
    
    -- Crear una entidad vacía para la posición
    local ent = ents.CreateClientProp()
    if not IsValid(ent) then 
        print("[GunGame] Error al crear la entidad del holograma")
        return 
    end
    
    ent:SetPos(pos + Vector(0, 0, 5))
    ent:Spawn()
    ent:Activate()
    ent:SetNoDraw(true)
    
    -- Configurar propiedades visuales
    local color = Color(100, 255, 100, 180)
    local radius = 15
    
    -- Añadir a la tabla de hologramas
    holograms[holoID] = {
        ent = ent,
        endTime = endTime,
        startTime = CurTime(),
        position = Vector(pos),
        id = holoID,
        bobOffset = 0,
        bobSpeed = math.random(15, 22) / 10,
        bobHeight = math.random(15, 25) / 10,
        baseZ = pos.z
    }
    
    -- Eliminar después de 5 segundos
    timer.Simple(5, function()
        if IsValid(ent) then
            ent:Remove()
        end
        holograms[holoID] = nil
    end)
end)

-- Actualizar hologramas (rotación, flotación y colisiones)
hook.Add("Think", "UpdateGunGameHolograms", function()
    local currentTime = CurTime()
    local localPlayer = LocalPlayer()
    
    -- Solo verificar colisiones cada COLLISION_COOLDOWN segundos
    local checkCollisions = (currentTime - lastCollisionCheck) >= COLLISION_COOLDOWN
    if checkCollisions then
        lastCollisionCheck = currentTime
    end
    
    for id, holo in pairs(holograms) do
        if not IsValid(holo.ent) then
            holograms[id] = nil
            continue
        end
        
        local time = currentTime * holo.bobSpeed
        local bob = math.sin(time) * (holo.bobHeight * 3)
        local pos = holo.ent:GetPos()
        local newZ = holo.baseZ + bob
        local newPos = Vector(holo.position.x, holo.position.y, newZ)
        holo.ent:SetPos(newPos)
        holo.position = newPos
        render.SetColorMaterial()
        render.DrawWireframeSphere(holo.position, 12, 12, 12, color, true)
        local pulse = 0.8 + (math.sin(CurTime() * 2) * 0.2)
        render.SetMaterial(Material("sprites/light_glow02_add"))
        render.DrawSprite(holo.position, 24 * pulse, 24 * pulse, color)
        
        -- Verificar colisiones con el jugador
        if checkCollisions and IsValid(localPlayer) and localPlayer:Alive() then
            local playerPos = localPlayer:GetPos()
            local toHologram = holo.position - playerPos
            local distSqr = toHologram:LengthSqr()
            local verticalDist = math.abs(toHologram.z)
            
            if distSqr <= (HOLOGRAM_RADIUS * HOLOGRAM_RADIUS) and verticalDist <= HOLOGRAM_VERTICAL_LIMIT then
                -- Notificar al servidor sobre la colisión
                net.Start("GunGame_PlayerTouchedHologram")
                    net.WriteString(holo.id)
                net.SendToServer()
                
                -- Reproducir sonido de recolección
                surface.PlaySound("items/medshot4.wav")
                
                -- Solo procesar una colisión por frame
                break
            end
        end
    end
end)

-- Dibujar efectos del holograma
hook.Add("PostDrawTranslucentRenderables", "DrawHologramEffects", function()
    if not LocalPlayer() then return end
    local localPlayer = LocalPlayer()
    if not IsValid(localPlayer) then return end
    
    -- Forzar la actualización de la matriz de renderizado
    cam.Start3D(EyePos(), EyeAngles())
    cam.End3D()
    
    for id, holo in pairs(holograms) do
        if not IsValid(holo.ent) then continue end
        
        local pos = holo.position or holo.ent:GetPos()
        
        -- Dibujar la esfera del holograma
        render.SetColorMaterial()
        render.DrawSphere(pos, 25, 20, 20, Color(0, 255, 0, 100))
    end
end)

-- Recibir comando para eliminar un holograma
net.Receive("GunGame_RemoveHologram", function()
    local holoID = net.ReadString()
    
    if holograms[holoID] then
        if IsValid(holograms[holoID].ent) then
            holograms[holoID].ent:Remove()
        end
        holograms[holoID] = nil
    end
end)

-- Limpiar al desconectarse o recargar
hook.Add("OnReloaded", "CleanupHolograms", function()
    for id, holo in pairs(holograms) do
        if IsValid(holo.ent) then
            holo.ent:Remove()
        end
    end
    holograms = {}
end)
