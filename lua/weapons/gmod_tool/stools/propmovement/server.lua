-- PropMovement Server Side
-- Tabla para almacenar props en movimiento y sus configuraciones
local movingProps = {}
local propConfigs = {}

-- Funciones de utilidad para convertir direcciones a vectores locales
local function GetLocalDirectionVector(direction, entity)
    if not IsValid(entity) then
        return Vector(0, 0, 1)
    end
    
    -- Obtener los vectores de dirección local del prop
    local forward = entity:GetForward()
    local right = entity:GetRight()
    local up = entity:GetUp()
    
    local directions = {
        ["FORWARD"] = forward,
        ["BACK"] = -forward,
        ["RIGHT"] = right,
        ["LEFT"] = -right,
        ["UP"] = up,
        ["DOWN"] = -up
    }
    
    return directions[direction] or up
end

-- Función para hacer pausa en corrutina
local function wait(seconds)
    local startTime = CurTime()
    while CurTime() - startTime < seconds do
        coroutine.yield()
    end
end

-- Función para mover un prop
local function MoveProp(ent, config)
    if not IsValid(ent) then return end
    
    local entID = ent:EntIndex()
    if movingProps[entID] then return end -- Ya se está moviendo
    
    -- Obtener posición inicial y calcular posición final usando coordenadas locales
    local startPos = ent:GetPos()
    local direction = GetLocalDirectionVector(config.direction, ent)
    local endPos = startPos + (direction * config.distance)
    
    -- Crear tabla de información de movimiento
    movingProps[entID] = {
        entity = ent,
        startPos = startPos,
        endPos = endPos,
        startTime = CurTime(),
        duration = config.time,
        cooldown = config.cooldown,
        returning = false,
        lastMove = 0
    }
end

-- Función para procesar el movimiento de todos los props
local function ProcessMovingProps()
    for entID, moveData in pairs(movingProps) do
        -- Ejecutar cada movimiento como corrutina
        if not moveData.coroutine or coroutine.status(moveData.coroutine) == "dead" then
            moveData.coroutine = coroutine.create(function()
                MovePropCoroutine(entID, moveData)
            end)
        end
        if coroutine.status(moveData.coroutine) == "suspended" then
            local ok, err = coroutine.resume(moveData.coroutine)
            if not ok then
                movingProps[entID] = nil
            end
        end
    end
end

function MovePropCoroutine(entID, moveData)
    local ent = moveData.entity
    
    if not IsValid(ent) then
        movingProps[entID] = nil
        return
    end
    
    while IsValid(ent) do
        -- Movimiento hacia adelante
        local startTime = CurTime()
        while CurTime() - startTime < moveData.duration do
            local progress = (CurTime() - startTime) / moveData.duration
            progress = math.sin(progress * math.pi * 0.5) -- Easing out
            local newPos = LerpVector(progress, moveData.startPos, moveData.endPos)
            ent:SetPos(newPos)
            coroutine.yield() -- Pausa para el siguiente frame
        end
        
        -- Asegurar posición final
        ent:SetPos(moveData.endPos)
        
        -- Aplicar cooldown después del movimiento hacia adelante
        if moveData.cooldown > 0 then
            wait(moveData.cooldown)
        end
        
        -- Movimiento de regreso
        startTime = CurTime()
        while CurTime() - startTime < moveData.duration do
            local progress = (CurTime() - startTime) / moveData.duration
            progress = math.sin(progress * math.pi * 0.5) -- Easing out
            local newPos = LerpVector(progress, moveData.endPos, moveData.startPos)
            ent:SetPos(newPos)
            coroutine.yield()
        end
        
        -- Asegurar posición inicial
        ent:SetPos(moveData.startPos)
        
        -- Aplicar cooldown después del movimiento de regreso
        if moveData.cooldown > 0 then
            wait(moveData.cooldown)
        end
    end
    
    -- Limpiar cuando termine
    movingProps[entID] = nil
end

-- Función para iniciar el movimiento con cooldown
local function StartPropMovement(ent, config)
    if not IsValid(ent) then return end
    
    local entID = ent:EntIndex()
    local moveData = movingProps[entID]
    
    if moveData then
        -- Verificar cooldown
        if moveData.lastMove > 0 and CurTime() < moveData.startTime then
            return -- Aún en cooldown
        end
    end
    
    -- Iniciar movimiento
    MoveProp(ent, config)
end

-- Función para recibir configuración del cliente
local function ReceivePropConfig(len, ply)
    -- Verificar permisos del jugador
    if not PropMovement.HasPermission(ply) then return end
    
    local entID = net.ReadInt(16)
    local config = net.ReadTable()
    
    local ent = Entity(entID)
    if not IsValid(ent) then return end
    
    propConfigs[entID] = config
    propConfigs[entID].entity = ent
end

-- Función para iniciar movimiento desde el cliente
local function StartMovement(len, ply)
    -- Verificar permisos del jugador
    if not PropMovement.HasPermission(ply) then return end
    
    local entID = net.ReadInt(16)
    local ent = Entity(entID)
    
    if not IsValid(ent) then return end
    
    local config = propConfigs[entID]
    if not config then return end
    
    StartPropMovement(ent, config)
end

-- Función para detener el movimiento de un prop
local function StopPropMovement(entID)
    if movingProps[entID] then
        local moveData = movingProps[entID]
        local ent = Entity(entID)
        if IsValid(ent) and moveData and moveData.startPos then
            ent:SetPos(moveData.startPos)
        end
        movingProps[entID] = nil
        propConfigs[entID] = nil
    end
end

-- Función para limpiar props eliminados
local function CleanupInvalidProps()
    for entID, config in pairs(propConfigs) do
        if not IsValid(config.entity) then
            propConfigs[entID] = nil
            movingProps[entID] = nil
        end
    end
end

-- Hook para procesar movimientos cada tick
hook.Add("Think", "PropMovement_ProcessMoving", ProcessMovingProps)

-- Hook para limpiar props inválidos periódicamente
timer.Create("PropMovement_Cleanup", 5, 0, CleanupInvalidProps)

-- Función para verificar si una entidad ya está en el servidor
local function CheckEntityInServer(len, ply)
    -- Verificar permisos del jugador
    if not PropMovement.HasPermission(ply) then return end
    
    local entID = net.ReadInt(16)
    local ent = Entity(entID)
    
    -- Verificar si la entidad existe en el servidor (configuraciones o en movimiento)
    local existsInServer = propConfigs[entID] ~= nil or movingProps[entID] ~= nil
    
    -- Enviar respuesta al cliente
    net.Start("PropMovement_ServerResponse")
    net.WriteInt(entID, 16)
    net.WriteBool(existsInServer)
    net.Send(ply)
end

-- Función para limpiar todas las configuraciones de un jugador
local function ClearAllProps(len, ply)
    -- Verificar permisos del jugador
    if not PropMovement.HasPermission(ply) then return end
    
    -- Leer la lista de entIDs que el cliente quiere limpiar
    local entCount = net.ReadUInt(8)
    local entIDs = {}
    
    for i = 1, entCount do
        local entID = net.ReadInt(16)
        table.insert(entIDs, entID)
    end
    
    -- Limpiar configuraciones y movimientos solo para las entidades del cliente
    for _, entID in ipairs(entIDs) do
        if propConfigs[entID] then
            propConfigs[entID] = nil
        end
        if movingProps[entID] then
            local ent = Entity(entID)
            if IsValid(ent) and movingProps[entID].startPos then
                ent:SetPos(movingProps[entID].startPos)
            end
            movingProps[entID] = nil
        end
    end
end

-- Recibir networks del cliente
net.Receive("PropMovement_Config", ReceivePropConfig)
net.Receive("PropMovement_Start", StartMovement)
net.Receive("PropMovement_CheckServer", CheckEntityInServer)
net.Receive("PropMovement_ClearAll", ClearAllProps)
net.Receive("PropMovement_StartAll", function(len, ply)
    -- Verificar permisos del jugador
    if not PropMovement.HasPermission(ply) then return end
    
    for entID, config in pairs(propConfigs) do
        local ent = Entity(entID)
        if IsValid(ent) then
            StartPropMovement(ent, config)
        end
    end
end)
net.Receive("PropMovement_Stop", function(len, ply)
    -- Verificar permisos del jugador
    if not PropMovement.HasPermission(ply) then return end
    
    local entID = net.ReadInt(16)
    StopPropMovement(entID)
end)