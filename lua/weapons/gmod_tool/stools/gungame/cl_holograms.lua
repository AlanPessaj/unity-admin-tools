-- Sistema de Hologramas para GunGame
local holograms = {}
local HOLOGRAM_RADIUS = 100 -- Radio de colisión del holograma
local HOLOGRAM_VERTICAL_LIMIT = 150 -- Límite vertical para la colisión
local COLLISION_COOLDOWN = 0.5 -- Medio segundo entre comprobaciones de colisión
local lastCollisionCheck = 0

-- Recibir y crear un nuevo holograma
net.Receive("GunGame_CreateHologram", function()
    local pos = net.ReadVector()
    local endTime = net.ReadFloat()
    local holoID = net.ReadString()
    
    print("[GunGame] Creando esfera holográfica con ID:", holoID)
    
    -- Crear una entidad vacía para la posición
    local ent = ents.CreateClientProp()
    if not IsValid(ent) then 
        print("[GunGame] Error al crear la entidad del holograma")
        return 
    end
    
    ent:SetPos(pos + Vector(0, 0, 5)) -- Elevar un poco la posición
    ent:Spawn()
    ent:Activate()
    ent:SetNoDraw(true) -- No dibujar el modelo de la entidad
    
    -- Configurar propiedades visuales
    local color = Color(100, 255, 100, 180)
    local radius = 15 -- Tamaño de la esfera
    
    -- Añadir a la tabla de hologramas
    holograms[holoID] = {
        ent = ent,
        endTime = endTime,
        angle = 0,
        startTime = CurTime(),
        position = Vector(pos),
        id = holoID,
        bobOffset = 0,
        bobSpeed = math.random(1, 3),
        bobHeight = math.random(5, 10) / 10
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
        
        -- Rotación suave
        holo.angle = (holo.angle + FrameTime() * 20) % 360
        holo.ent:SetAngles(Angle(0, holo.angle, 0))
        
        -- Movimiento de flotación más suave
        local time = currentTime * holo.bobSpeed
        local bob = math.sin(time) * holo.bobHeight
        
        -- Posición base
        local pos = holo.ent:GetPos()
        
        -- Aplicar movimiento de flotación
        local newZ = pos.z + (bob - holo.bobOffset) * 0.1
        holo.bobOffset = bob
        
        -- Actualizar posición
        local newPos = Vector(pos.x, pos.y, newZ)
        holo.ent:SetPos(newPos)
        holo.position = newPos
        
        -- Dibujar la esfera
        render.SetColorMaterial()
        render.DrawWireframeSphere(holo.position, 15, 16, 16, color, true)
        
        -- Añadir un efecto de brillo
        render.SetMaterial(Material("sprites/light_glow02_add"))
        render.DrawSprite(holo.position, 30, 30, color)
        
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
