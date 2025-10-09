-- Sistema de Hologramas para GunGame
local holograms = {}
local HOLOGRAM_RADIUS = 75 -- Radio de colisión del holograma
local HOLOGRAM_VERTICAL_LIMIT = 120 -- Límite vertical para la colisión
local COLLISION_COOLDOWN = 0.3 -- Tiempo entre comprobaciones de colisión
local HOLOGRAM_SPHERE_COLOR = Color(0, 255, 0, 100)
local HOLOGRAM_GLOW_COLOR = Color(100, 255, 100, 180)
local HEALTHKIT_MODEL = "models/items/healthkit.mdl"
local HEALTHKIT_SCALE = 1.2
local HEALTHKIT_ALPHA = 200
local HEALTHKIT_OFFSET = Vector(0, 0, 5)
local lastCollisionCheck = 0

-- Recibir y crear un nuevo holograma
net.Receive("GunGame_CreateHologram", function()
    local pos = net.ReadVector()
    local endTime = net.ReadFloat()
    local holoID = net.ReadString()

    -- Crear un modelo clientside del botiquín que girará dentro del holograma
    local ent = ClientsideModel(HEALTHKIT_MODEL, RENDERGROUP_BOTH)
    if not IsValid(ent) then
        print("[GunGame] Error al crear la entidad del holograma")
        return
    end

    local centerPos = pos
    local entPos = centerPos + HEALTHKIT_OFFSET
    ent:SetPos(entPos)
    ent:SetAngles(Angle(90, math.Rand(0, 360), 0))
    ent:SetModelScale(HEALTHKIT_SCALE, 0)
    ent:DrawShadow(false)
    ent:SetRenderMode(RENDERMODE_TRANSALPHA)
    ent:SetColor(Color(255, 255, 255, HEALTHKIT_ALPHA))

    -- Añadir a la tabla de hologramas
    holograms[holoID] = {
        ent = ent,
        endTime = endTime,
        startTime = CurTime(),
        center = Vector(centerPos),
        position = Vector(centerPos),
        id = holoID,
        bobOffset = 0,
        bobSpeed = math.random(15, 22) / 10,
        bobHeight = math.random(15, 25) / 10,
        rotationSpeed = math.Rand(45, 90),
        rotationAngle = ent:GetAngles().y,
        baseZ = centerPos.z
    }

    -- Eliminar después de 5 segundos
    timer.Simple(10, function()
        SafeRemoveEntity(ent)
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
        local centerPos = holo.center or holo.position
        if not centerPos then
            centerPos = holo.ent:GetPos() - HEALTHKIT_OFFSET
            holo.center = Vector(centerPos)
        end
        local baseZ = holo.baseZ or centerPos.z
        local bobbedCenter = Vector(centerPos.x, centerPos.y, baseZ + bob)
        holo.rotationAngle = (holo.rotationAngle + FrameTime() * holo.rotationSpeed) % 360
        holo.ent:SetPos(bobbedCenter + HEALTHKIT_OFFSET)
        holo.ent:SetAngles(Angle(90, holo.rotationAngle, 0))
        holo.ent:SetColor(Color(255, 255, 255, HEALTHKIT_ALPHA))
        holo.position = bobbedCenter

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
        local pulse = 0.8 + (math.sin(CurTime() * 2) * 0.2)

        render.SetColorMaterial()
        render.DrawSphere(pos, 25, 20, 20, HOLOGRAM_SPHERE_COLOR)
        render.SetMaterial(Material("sprites/light_glow02_add"))
        render.DrawSprite(pos, 24 * pulse, 24 * pulse, HOLOGRAM_GLOW_COLOR)

        -- Dibujar el botiquín con el alpha configurable
        local blend = HEALTHKIT_ALPHA / 255
        render.SetBlend(blend)
        holo.ent:DrawModel()
        render.SetBlend(1)
    end
end)

-- Recibir comando para eliminar un holograma
net.Receive("GunGame_RemoveHologram", function()
    local holoID = net.ReadString()

    if holograms[holoID] then
        SafeRemoveEntity(holograms[holoID].ent)
        holograms[holoID] = nil
    end
end)

-- Limpiar al desconectarse o recargar
hook.Add("OnReloaded", "CleanupHolograms", function()
    for id, holo in pairs(holograms) do
        SafeRemoveEntity(holo.ent)
    end
    holograms = {}
end)
