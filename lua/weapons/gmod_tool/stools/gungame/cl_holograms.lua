-- Sistema de Hologramas para GunGame
local holograms = {}
local HOLOGRAM_RADIUS = 100 -- Radio de colisión del holograma
local HOLOGRAM_VERTICAL_LIMIT = 150 -- Límite vertical para la colisión
local COLLISION_COOLDOWN = 0.5 -- Medio segundo entre comprobaciones de colisión
local lastCollisionCheck = 0

-- Precargar el modelo
util.PrecacheModel("models/items/healthkit.mdl")

-- Recibir y crear un nuevo holograma
net.Receive("GunGame_CreateHologram", function()
    local pos = net.ReadVector()
    local endTime = net.ReadFloat()
    local holoID = net.ReadString()
    
    print("[GunGame] Creando holograma con ID:", holoID)
    
    -- Crear el efecto de holograma
    local ent = ClientsideModel("models/items/healthkit.mdl")
    if not IsValid(ent) then 
        print("[GunGame] Error al crear el modelo del holograma")
        return 
    end
    
    ent:SetPos(pos + Vector(0, 0, 30)) -- Elevar un poco el modelo
    ent:SetModelScale(0.5) -- Tamaño más manejable
    
    -- Hacer el modelo semi-transparente y verde
    local color = Color(100, 255, 100, 180)
    ent:SetColor(color)
    ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
    ent:DrawShadow(false)
    ent:SetMaterial("models/shiny")
    
    -- Asegurarse de que el modelo se renderice
    ent:Spawn()
    ent:Activate()
    
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
                surface.PlaySound("items/ammo_pickup.wav")
                
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
        
        -- Dibujar el área de colisión si estamos cerca
        local playerPos = localPlayer:GetPos()
        local distSqr = (pos - playerPos):LengthSqr()
        local inRange = distSqr <= (HOLOGRAM_RADIUS * HOLOGRAM_RADIUS * 4)
        
        if inRange then
            -- Dibujar un círculo en la base
            local radius = HOLOGRAM_RADIUS
            local segments = 32
            local angleStep = (2 * math.pi) / segments
            local lastPos
            
            for i = 0, segments do
                local angle = i * angleStep
                local x = pos.x + radius * math.cos(angle)
                local y = pos.y + radius * math.sin(angle)
                local nextPos = Vector(x, y, pos.z)
                
                if lastPos then
                    render.DrawLine(lastPos, nextPos, Color(0, 255, 0, 50), false)
                end
                lastPos = nextPos
            end
        end
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
