if not ship then
    printError("Need CC:VS!")
    return
end
peripheral.find("modem", rednet.open)

local properties, system
local protocol, request_protocol = "CBCNetWork", "CBCcenter"

----------------init-----------------
local ANGLE_TO_SPEED = 26.6666666666666666667

system = {
    fileName = "dat",
    file = nil
}

system.init = function()
    system.file = io.open(system.fileName, "r")
    if system.file then
        local tmpProp = textutils.unserialise(system.file:read("a"))
        properties = system.reset()
        for k, v in pairs(properties) do
            if tmpProp[k] then
                properties[k] = tmpProp[k]
            end
        end

        system.file:close()
    else
        properties = system.reset()
        system.updatePersistentData()
    end
end

system.reset = function()
    return {
        cannonName = "CBC",
        controlCenterId = "-1",
        power_on = "front", -- 开机信号
        fire = "back", -- 开火信号
        inversion = false,
        basic_v = true,
        minPitchAngle = -45,
        idleFace = "west",
        password = "123456",
        min_pitch = "-45",
        max_pitch = "90",
        min_yaw = "-180",
        max_yaw = "180",
        velocity = "160",
        barrelLength = "8",
        forecastMov = "1.5",
        forecastRot = "3",
        gravity = "0.05",
        drag = "0.01",
    }
end

system.updatePersistentData = function()
    system.write(system.fileName, properties)
end

system.write = function(file, obj)
    system.file = io.open(file, "w")
    system.file:write(textutils.serialise(obj))
    system.file:close()
end

system.init()

------------------------

local genStr = function(s, count)
    local result = ""
    for i = 1, count, 1 do
        result = result .. s
    end
    return result
end

local square = function (num)
    return num * num
end

local vector = {}
local newVec = function (x, y, z)
    if type(x) == "table" then
        return setmetatable({ x = x.x, y = x.y, z = x.z}, { __index = vector })
    elseif x and y and z then
        return setmetatable({ x = x, y = y, z = z}, { __index = vector})
    else
        return setmetatable({ x = 0, y = 0, z = 0}, { __index = vector})
    end
end

function vector:zero()
    self.x = 0
    self.y = 0
    self.z = 0
    return self
end

function vector:copy()
    return newVec(self.x, self.y, self.z)
end

function vector:len()
    return math.sqrt(square(self.x) + square(self.y) + square(self.z) )
end

function vector:norm()
    local l = self:len()
    if l == 0 then
        self:zero()
    else
        self.x = self.x / l
        self.y = self.y / l
        self.z = self.z / l
    end
    return self
end

function vector:nega()
    self.x = -self.x
    self.y = -self.y
    self.z = -self.z
    return self
end

function vector:add(v)
    self.x = self.x + v.x
    self.y = self.y + v.y
    self.z = self.z + v.z
    return self
end

function vector:sub(v)
    self.x = self.x - v.x
    self.y = self.y - v.y
    self.z = self.z - v.z
    return self
end

function vector:scale(num)
    self.x = self.x * num
    self.y = self.y * num
    self.z = self.z * num
    return self
end

function vector:unpack()
    return self.x, self.y, self.z
end

local vector_scale = function(v, s)
    return {
        x = v.x * s,
        y = v.y * s,
        z = v.z * s
    }
end
local unpackVec = function(v)
    return v.x, v.y, v.z
end
local quat = {}
function quat.new()
    return { w = 1, x = 0, y = 0, z = 0}
end

function quat.vecRot(q, v)
    local x = q.x * 2
    local y = q.y * 2
    local z = q.z * 2
    local xx = q.x * x
    local yy = q.y * y
    local zz = q.z * z
    local xy = q.x * y
    local xz = q.x * z
    local yz = q.y * z
    local wx = q.w * x
    local wy = q.w * y
    local wz = q.w * z
    local res = {}
    res.x = (1.0 - (yy + zz)) * v.x + (xy - wz) * v.y + (xz + wy) * v.z
    res.y = (xy + wz) * v.x + (1.0 - (xx + zz)) * v.y + (yz - wx) * v.z
    res.z = (xz - wy) * v.x + (yz + wx) * v.y + (1.0 - (xx + yy)) * v.z
    return newVec(res.x, res.y, res.z)
end

function quat.multiply(q1, q2)
    local newQuat = {}
    newQuat.w = -q1.x * q2.x - q1.y * q2.y - q1.z * q2.z + q1.w * q2.w
    newQuat.x = q1.x * q2.w + q1.y * q2.z - q1.z * q2.y + q1.w * q2.x
    newQuat.y = -q1.x * q2.z + q1.y * q2.w + q1.z * q2.x + q1.w * q2.y
    newQuat.z = q1.x * q2.y - q1.y * q2.x + q1.z * q2.w + q1.w * q2.z
    return newQuat
end

function quat.nega(q)
    return {
        w = q.w,
        x = -q.x,
        y = -q.y,
        z = -q.z,
    }
end

local newQuat = function(w, x, y, z)
    return setmetatable({ w = w, x = x, y = y, z = z }, { __index = quat })
end

local sin2cos = function(s)
    return math.sqrt( 1 - square(s))
end

local copysign = function(num1, num2)
    num1 = math.abs(num1)
    num1 = num2 > 0 and num1 or -num1
    return num1
end

local omega2Q = function (omega, tick)
    local omegaRot = {
        x = omega.x * tick,
        y = omega.y * tick * 2,
        z = omega.z * tick
    }
    local sqrt = math.sqrt(omegaRot.x ^ 2 + omegaRot.y ^ 2 + omegaRot.z ^ 2)
    sqrt = math.abs(sqrt) > math.pi and copysign(math.pi, sqrt) or sqrt
    if sqrt ~= 0 then
        omegaRot.x = omegaRot.x / sqrt
        omegaRot.y = omegaRot.y / sqrt
        omegaRot.z = omegaRot.z / sqrt
        local halfTheta = sqrt / 2
        local sinHTheta = math.sin(halfTheta)
        return {
            w = math.cos(halfTheta),
            x = omegaRot.x * sinHTheta,
            y = omegaRot.y * sinHTheta,
            z = omegaRot.z * sinHTheta
        }
    else
        return nil
    end
end

local matrixMultiplication_3d = function (m, v)
    return newVec(
        m[1][1] * v.x + m[1][2] * v.y + m[1][3] * v.z,
        m[2][1] * v.x + m[2][2] * v.y + m[2][3] * v.z,
        m[3][1] * v.x + m[3][2] * v.y + m[3][3] * v.z
    )
end

local resetAngelRange = function(angle)
    if (math.abs(angle) > 180) then
        angle = math.abs(angle) >= 360 and angle % 360 or angle
        return -copysign(360 - math.abs(angle), angle)
    else
        return angle
    end
end

local cannon, fire
local targetAngle = { pitch = 0, yaw = 0 }
local block_offset = newVec(0.5, 0.5, 0.5)

local faces = {
    up = newVec(0, 1, 0),
    down = newVec(0, -1, 0),
    north = newVec(0, 0, -1),
    south = newVec(0, 0, 1),
    west = newVec(-1, 0, 0),
    east = newVec(1, 0, 0)
}
local selfPos = newVec(coordinate.getAbsoluteCoordinates())
--commands.execAsync(("say %.2f %.2f %.2f"):format(selfPos.x, selfPos.y, selfPos.z))

local getCannon = function (pos)
    local _, str = commands.exec(("data get block %d %d %d"):format(pos.x, pos.y, pos.z))
    str = str[1]
    local yaw = str:match("CannonYaw: [-]?(%d+%.?%d*)f")
    local result = nil
    if yaw then
        result = {}
        result.yaw = resetAngelRange(tonumber(yaw))
        result.initYaw = math.floor(result.yaw + 0.5)
        result.pitch = tonumber(str:match("CannonPitch: [-]?(%d+%.?%d*)f"))
        result.initPitch = result.pitch
        result.pos = pos
    end
    return result, str
end

local initIdleAg = function ()
    if properties.idleFace == "west" then
        cannon.idle_yaw = 90
    elseif properties.idleFace == "east" then
        cannon.idle_yaw = -90
    elseif properties.idleFace == "north" then
        cannon.idle_yaw = 180
    else
        cannon.idle_yaw = 0
    end
end

local initCannon = function ()
    for k, v in pairs(faces) do
        local tPos = newVec(selfPos):add(v)
        cannon, str = getCannon(tPos)
        if cannon then
            redstone.setOutput(properties.power_on, false)
            redstone.setOutput(properties.power_on, true)
            selfPos = tPos
            cannon.type = str:match('id:%s*"([^"]*)"')
            if cannon.type == "createbigcannons:cannon_mount" then
                --commands.execAsync("say here")
                cannon.cross_offset = newVec(0, 2, 0)
                if properties.inversion == true then
                    cannon.cross_offset.y = -2
                end
            else
                if cannon.initYaw == 0 then
                    cannon.cross_offset = newVec(-1, 0, 0)
                elseif cannon.initYaw == 180 then
                    cannon.cross_offset = newVec(1, 0, 0)
                elseif cannon.initYaw == 90 then
                    cannon.cross_offset = newVec(0, 0, -1)
                else
                    cannon.cross_offset = newVec(0, 0, 1)
                end
            end
            initIdleAg()
            cannon.face = k
            cannon.faceVec = {
                x = -math.floor(math.sin(math.rad(cannon.yaw)) + 0.5),
                y = 0,
                z = math.floor(math.cos(math.rad(cannon.yaw)) + 0.5)
            }
            cannon.faceMatrix = {
                {cannon.faceVec.x, 0, cannon.faceVec.z},
                {0, 1, 0},
                {-cannon.faceVec.z, 0, cannon.faceVec.x},
            }
            break
        end
    end
end
initCannon()

local setYawAndPitch = function (yaw, pitch)
    commands.execAsync(("data modify block %d %d %d CannonYaw set value %.4f"):format(selfPos.x, selfPos.y, selfPos.z, yaw))
    commands.execAsync(("data modify block %d %d %d CannonPitch set value %.4f"):format(selfPos.x, selfPos.y, selfPos.z, pitch))
end

local getCannonPos = function()
    local wPos = newVec(ship.getWorldspacePosition())
    local yardPos = newVec(ship.getShipyardPosition())
    local offset = yardPos:sub(selfPos):sub(block_offset):sub(cannon.cross_offset)
    offset = quat.vecRot(ship.getQuaternion(), offset)
    return wPos:sub(offset)
end

local controlCenter = {
    tgPos = newVec(),
    velocity = newVec(),
    mode = 2,
    fire = false
}

local ct = 20
local listener = function()
    local controlCenterId = #properties.controlCenterId == 0 and 0 or tonumber(properties.controlCenterId)
    controlCenterId = controlCenterId and controlCenterId or 0
    while true do
        local id, msg = rednet.receive(protocol, 2)
        if id == controlCenterId then
            controlCenter = msg
            ct = 20
        end
    end
end

local box_1 = peripheral.find("gtceu:lv_super_chest")
box_1 = box_1 and box_1 or peripheral.find("gtceu:mv_super_chest")
box_1 = box_1 and box_1 or peripheral.find("gtceu:hv_super_chest")
box_1 = box_1 and box_1 or peripheral.find("gtceu:ev_super_chest")
local bullets_count = 0
local getBullets_count = function ()
    while true do
        if box_1 and box_1.getItemDetail(1) then
            bullets_count = box_1.getItemDetail(1).count
        else
            bullets_count = 0
        end
        if not box_1 then
            sleep(0.05)
        end
    end
end

local cross_point = newVec()
local sendRequest = function()
    local slug = ship and ship.getName() or nil
    while true do
        local controlCenterId = #properties.controlCenterId == 0 and 0 or tonumber(properties.controlCenterId)
        controlCenterId = controlCenterId and controlCenterId or 0
        rednet.send(controlCenterId, {
            name = properties.cannonName,
            pw = properties.password,
            bullets_count = bullets_count,
            cross_point = cross_point
        }, request_protocol)
        sleep(0.05)
    end
end

local getFashaodesu = function()
    local players = coordinate.getPlayers()
    for k, v in pairs(players) do
        if v.name == "fashaodesu" then
            return v
        end
    end
end

function math.lerp(a, b, t)
    return a + (b - a) * t
end

local pdCt = function(tgYaw, omega, p, d)
    local result = tgYaw * p + omega * d
    return math.abs(result) > properties.max_rotate_speed and copysign(properties.max_rotate_speed, result) or result
end

local ln = function(x)
    return math.log(x) / math.log(math.exp(1))
end

local getTime = function(dis, pitch)
    local barrelLength = #properties.barrelLength == 0 and 0 or tonumber(properties.barrelLength)
    barrelLength = barrelLength and barrelLength or 0
    local cosP = math.abs(math.cos(pitch))
    dis = dis - barrelLength * cosP

    local v0 = #properties.velocity == 0 and 0 or tonumber(properties.velocity) / 20
    v0 = v0 and v0 or 0

    local drag = #properties.drag == 0 and 0 or tonumber(properties.drag)
    drag = drag and 1 - drag or 0.99
    
    local result

    if drag < 0.001 or drag > 0.999 then
        result = dis / (cosP * v0)
    else
        result = math.abs(math.log(1 - dis / (100 * (cosP * v0))) / ln(drag))
    end
    -- local result = math.log((dis * lnD) / (v0 * cosP) + 1, drag)

    return result and result or 0
end

local getY2 = function(t, y0, pitch)
    if t > 10000 then
        return 0
    end
    local grav = #properties.gravity == 0 and 0 or tonumber(properties.gravity)
    grav = grav and grav or 0.05
    local sinP = math.sin(pitch)
    local barrelLength = #properties.barrelLength == 0 and 0 or tonumber(properties.barrelLength)
    barrelLength = barrelLength and barrelLength or 0
    y0 = barrelLength * sinP + y0
    local v0 = #properties.velocity == 0 and 0 or tonumber(properties.velocity) / 20
    v0 = v0 and v0 or 0
    local Vy = v0 * sinP

    local drag = #properties.drag == 0 and 0 or tonumber(properties.drag)
    drag = drag and 1 - drag or 0.99
    if drag < 0.001 then
        drag = 1
    end
    local index = 1
    local last = 0
    while index < t + 1 do
        y0 = y0 + Vy
        Vy = drag * Vy - grav
        if index == math.floor(t) then
            last = y0
        end
        index = index + 1
    end
    
    return math.lerp(last, y0, t % math.floor(t))
end

local ag_binary_search = function(arr, xDis, y0, yDis)
    local low = 1
    local high = #arr
    local mid, time
    local pitch, result = 0, 0
    while low <= high do
        mid = math.floor((low + high) / 2)
        pitch = arr[mid]
        time = getTime(xDis, pitch)
        result = yDis - getY2(time, y0, pitch)
        if result >= -0.018 and result <= 0.018 then
            break
            --return mid, time
        elseif result > 0 then
            low = mid + 1
        else
            high = mid - 1
        end
    end
    return pitch, time
end

local pitchList = {}
for i = -90, 90, 0.0375 do
    table.insert(pitchList, math.rad(i))
end
local genParticle = function(x, y, z)
    commands.execAsync(string.format("particle electric_spark %0.6f %0.6f %0.6f 0 0 0 0 0 force", x, y, z))
end

local run_cannon = function()
    sleep(0.1)
    while true do
        local cannon_pos = getCannonPos()

        local final_point
        local target_point = newVec()
        if ct > 0 and controlCenter.omega then
            ct = ct - 1
            fire = controlCenter.fire
            local forecast = #properties.forecastMov == 0 and 1 or tonumber(properties.forecastMov)
            forecast = forecast and forecast or 1
            local forecastRot = #properties.forecastRot == 0 and 1 or tonumber(properties.forecastRot)
            forecastRot = forecastRot and forecastRot or 1

            local parentOmega = quat.vecRot(quat.nega(ship.getQuaternion()), controlCenter.omega):scale(0.01)

            local nextQ = ship.getQuaternion()
            local omegaQuat = omega2Q(parentOmega, forecastRot)
            if omegaQuat then
                nextQ = quat.multiply(nextQ, omegaQuat)
            end

            local pErr = cannon_pos:copy():sub(controlCenter.pos)
    
            local pNextQ2 = controlCenter.rot
            local omegaQ2 = omega2Q(parentOmega, forecastRot * 2)
            if omegaQ2 then
                pNextQ2 = quat.multiply(pNextQ2, omegaQ2)
            end
            pErr = quat.vecRot(quat.nega(controlCenter.rot), pErr)
            pErr = quat.vecRot(pNextQ2, pErr)
            
            local parent_velocity = newVec(controlCenter.center_velocity):scale(0.05)
            local self_velocity = newVec(ship.getVelocity()):scale(0.05)

            local new_pos = newVec(controlCenter.pos):add(parent_velocity:scale(forecast))
            new_pos:add(pErr)

            genParticle(new_pos.x, new_pos.y, new_pos.z)

            local target = newVec(controlCenter.tgPos)
            target.y = target.y + 0.5
            local target_velocity = newVec(controlCenter.velocity)
            --local target = newVec(getFashaodesu())

            target_point = target:copy():sub(new_pos)

            if properties.basic_v == true then
                local tmpT = (500 - math.sqrt(square(target_point.x) + square(target_point.y) + square(target_point.z))) / 500
                tmpT = tmpT < 0 and 0 or tmpT * 8
                target:add(target_velocity:copy():scale(tmpT))
            end
            local v0 = #properties.velocity == 0 and 0 or tonumber(properties.velocity) / 8
            v0 = v0 and v0 or 0
            local tmpT2 = math.sqrt(square(target_point.x) + square(target_point.y) + square(target_point.z)) / v0
            tmpT2 = tmpT2 < 0 and 0 or tmpT2
            new_pos:add(parent_velocity:scale(tmpT2))
            target_point = target:copy():sub(new_pos)

            local xDis = math.sqrt(square(target_point.x) + square(target_point.z))
            local tmpPitch, cTime = ag_binary_search(pitchList, xDis, 0, target_point.y)
            local tmpVec

            if cTime > 10 then
                local _c = math.sqrt(square(target_point.x) + square(target_point.z))
                if controlCenter.mode > 2 then
                    target:add(target_velocity:copy():scale(cTime))
                    target_point = target:copy():sub(new_pos)
                    
                    xDis = math.sqrt(square(target_point.x) + square(target_point.z))
                    _c = xDis
                    tmpPitch, cTime = ag_binary_search(pitchList, xDis, 0, target_point.y)
                end

                local allDis = target_point:len()
                local cosP = math.cos(tmpPitch)
                tmpVec = newVec(
                    allDis * (target_point.x / _c) * cosP,
                    allDis * math.sin(tmpPitch),
                    allDis * (target_point.z / _c) * cosP
                    )
            else
                tmpVec = target_point
            end

            final_point = quat.vecRot(quat.nega(nextQ), tmpVec:copy():add(cannon_pos):sub(new_pos))
                
            local target_vector = final_point:norm()
            targetAngle.pitch = math.deg(math.asin(target_vector.y))
            targetAngle.yaw = -math.deg(math.atan2(target_vector.x, target_vector.z))

            local min_pitch, max_pitch = tonumber(properties.min_pitch), tonumber(properties.max_pitch)
            min_pitch = min_pitch and min_pitch or 0
            max_pitch = max_pitch and max_pitch or 0
            local min_yaw, max_yaw = tonumber(properties.min_yaw), tonumber(properties.max_yaw)
            min_yaw = min_yaw and min_yaw or 0
            max_yaw = max_yaw and max_yaw or 0
            targetAngle.pitch = targetAngle.pitch < min_pitch and min_pitch or targetAngle.pitch > max_pitch and max_pitch or targetAngle.pitch
            targetAngle.yaw = targetAngle.yaw < min_yaw and min_yaw or targetAngle.yaw > max_yaw and max_yaw or targetAngle.yaw

            local rot_point = matrixMultiplication_3d(cannon.faceMatrix, target_vector)
            local yaw_with_rot = math.deg(math.atan2(rot_point.z, rot_point.x))
            local pitch_with_rot = math.deg(math.asin(rot_point.y))
            local tgPoint = vector_scale(cannon.faceVec, tmpVec:len())

            local p_angle = -math.rad(pitch_with_rot) / 2
            local pitchQuat = {
                w = math.cos(p_angle),
                x = 0,
                y = 0,
                z = math.sin(p_angle)
            }

            local y_angle = -math.rad(yaw_with_rot) / 2
            local yawQuat = {
                w = math.cos(y_angle),
                x = 0,
                y = math.sin(y_angle),
                z = 0
            }
            cross_point = quat.vecRot(quat.multiply(pitchQuat, yawQuat), tgPoint)
            cross_point = quat.vecRot(ship.getQuaternion(), cross_point)
            cross_point:add(cannon_pos:add(self_velocity))
            --local target_point = quat.vecRot(quat.nega(ship_rot), target:copy():sub(new_pos))
        else
            targetAngle.pitch = 0
            targetAngle.yaw = cannon.idle_yaw
            cross_point = nil
        end
        
        setYawAndPitch(targetAngle.yaw, targetAngle.pitch)
        sleep(0.05)
    end
end

local termUtil = {
    cpX = 1,
    cpY = 1
}

local absTextField = {
    x = 1,
    y = 1,
    len = 15,
    text = "",
    textCorlor = "0",
    backgroundColor = "8"
}

function absTextField:paint()
    local str = ""
    for i = 1, self.len, 1 do
        local text = tostring(self.key[self.value])
        local tmp = string.sub(text, i, i)
        if #tmp > 0 then
            str = str .. tmp
        else
            local tmp2 = ""
            for j = 0, self.len - i, 1 do
                tmp2 = tmp2 .. " "
            end
            str = str .. tmp2
            break
        end
    end

    term.setCursorPos(self.x, self.y)
    term.blit(str, genStr(self.textCorlor, #str), genStr(self.backgroundColor, #str))
end

function absTextField:inputChar(char)
    local xPos, yPos = term.getCursorPos()
    xPos = xPos + 1 - self.x
    local field = tostring(self.key[self.value])
    if #field < self.len then
        if self.type == "number" then
            if char >= '0' and char <= '9' then
                if field == "0" then
                    field = char
                else
                    field = string.sub(field, 1, xPos) .. char .. string.sub(field, xPos, #field)
                end

                self.key[self.value] = tonumber(field)
                termUtil.cpX = termUtil.cpX + 1
            end
            if char == '-' then
                self.key[self.value] = -self.key[self.value]
            end
        elseif self.type == "string" then
            local strEnd = string.sub(field, xPos, #field)
            field = string.sub(field, 1, xPos - 1) .. char .. strEnd
            self.key[self.value] = field
            termUtil.cpX = termUtil.cpX + 1
        end
    end
end

function absTextField:inputKey(key)
    local xPos, yPos = term.getCursorPos()
    local field = tostring(self.key[self.value])
    local minXp = self.x
    local maxXp = minXp + #field
    if key == 259 or key == 261 then -- backSpace
        if xPos > minXp then
            termUtil.cpX = termUtil.cpX - 1
            if #field > 0 and termUtil.cpX > 1 then
                local index = termUtil.cpX - self.x
                field = string.sub(field, 1, index) .. string.sub(field, index + 2, #field)
            end
            if self.type == "number" then
                local number = tonumber(field)
                if not number then
                    self.key[self.value] = 0
                else
                    self.key[self.value] = number
                end
            elseif self.type == "string" then
                self.key[self.value] = field
            end
        end
    elseif key == 257 or key == 335 then
        -- print("enter")
    elseif key == 262 or key == 263 then
        if key == 262 then
            termUtil.cpX = termUtil.cpX + 1
        elseif key == 263 then
            termUtil.cpX = termUtil.cpX - 1
        end
    elseif key == 264 or key == 258 then
        -- print("down")
    elseif key == 265 then
        -- print("up")
    end
    termUtil.cpX = termUtil.cpX > maxXp and maxXp or termUtil.cpX
    termUtil.cpX = termUtil.cpX < minXp and minXp or termUtil.cpX
end

function absTextField:click(x, y)
    local xPos = self.x
    if x >= xPos then
        if x < xPos + #tostring(self.key[self.value]) then
            termUtil.cpX, termUtil.cpY = x, y
        else
            termUtil.cpX, termUtil.cpY = xPos + #tostring(self.key[self.value]), y
        end
    end
end

local newTextField = function(key, value, x, y)
    return setmetatable({
        key = key,
        value = value,
        type = type(key[value]),
        x = x,
        y = y
    }, {
        __index = absTextField
    })
end

local absSelectBox = {
    x = 1,
    y = 1,
    label = "",
    contents = {},
    count = 0,
    interval = 0,
    fontColor = "8",
    backgroundColor = "f",
    selectColor = "e"
}

function absSelectBox:paint()
    term.setCursorPos(self.x, self.y)
    local select = tostring(self.key[self.value])
    for i = 1, #self.contents, 1 do
        local str = tostring(self.contents[i])
        if select == str then
            term.blit(str, genStr(self.backgroundColor, #str), genStr(self.selectColor, #str))
        else
            term.blit(str, genStr(self.fontColor, #str), genStr(self.backgroundColor, #str))
        end
        for j = 1, self.interval, 1 do
            term.write(" ")
        end
    end
end

function absSelectBox:click(x, y)
    local xPos = x + 1 - self.x
    local index = 0
    for i = 1, #self.contents, 1 do
        if xPos >= index and xPos <= index + #tostring(self.contents[i]) then
            self.key[self.value] = self.contents[i]
            break
        end
        index = index + #tostring(self.contents[i]) + self.interval
    end
end

local newSelectBox = function(key, value, interval, x, y, ...)
    return setmetatable({
        key = key,
        value = value,
        interval = interval,
        x = x,
        y = y,
        type = type(key[value]),
        contents = {...}
    }, {
        __index = absSelectBox
    })
end

local absSlider = {
    x = 1,
    y = 1,
    min = 0,
    max = 1,
    len = 20,
    fontColor = "8",
    backgroundColor = "f"
}

function absSlider:paint()
    local field = self.key[self.value]
    if field == "-" then
        field = 0
    end
    local maxVal = self.max - self.min
    local xPos = math.floor((field - self.min) * (self.len / maxVal) + 0.5)
    xPos = xPos < 1 and 1 or xPos
    term.setCursorPos(self.x, self.y)
    for i = 1, self.len, 1 do
        if xPos == i then
            term.blit(" ", self.backgroundColor, self.fontColor)
        else
            term.blit("-", self.fontColor, self.backgroundColor)
        end
    end
end

function absSlider:click(x, y)
    local xPos = x + 1 - self.x
    if xPos > self.len then
        xPos = self.len
    end
    self.key[self.value] = math.floor((self.max - self.min) * (xPos / self.len) + 0.5) + self.min
end

local newSlider = function(key, value, min, max, len, x, y)
    return setmetatable({
        key = key,
        value = value,
        min = min,
        max = max,
        len = len,
        x = x,
        y = y
    }, {
        __index = absSlider
    })
end

local selfId = os.getComputerID()
local runTerm = function()
    local fieldTb = {
        controlCenterId = newTextField(properties, "controlCenterId", 19, 14),
        velocity = newTextField(properties, "velocity", 11, 2),
        barrelLength = newTextField(properties, "barrelLength", 30, 2),
        gravity = newTextField(properties, "gravity", 45, 2),
        drag = newTextField(properties, "drag", 45, 3),
        min_pitch = newTextField(properties, "min_pitch", 12, 6),
        max_pitch = newTextField(properties, "max_pitch", 12, 7),
        min_yaw = newTextField(properties, "min_yaw", 27, 6),
        max_yaw = newTextField(properties, "max_yaw", 27, 7),
        forecastMov = newTextField(properties, "forecastMov", 46, 6),
        forecastRot = newTextField(properties, "forecastRot", 46, 7),
        cannonName = newTextField(properties, "cannonName", 14, 12),
        password = newTextField(properties, "password", 14, 13)
    }
    fieldTb.velocity.len = 5
    fieldTb.barrelLength.len = 3
    fieldTb.controlCenterId.len = 5
    fieldTb.password.len = 14
    fieldTb.min_pitch.len = 5
    fieldTb.max_pitch.len = 5
    fieldTb.min_yaw.len = 5
    fieldTb.max_yaw.len = 5
    fieldTb.gravity.len = 6
    fieldTb.drag.len = 6
    fieldTb.forecastMov.len = 5
    fieldTb.forecastRot.len = 5
    local selectBoxTb = {
        power_on = newSelectBox(properties, "power_on", 1, 12, 3, "top", "left", "right", "front", "back"),
        fire = newSelectBox(properties, "fire", 1, 12, 4, "top", "left", "right", "front", "back"),
        idleFace = newSelectBox(properties, "idleFace", 1, 14, 10, "south", "west", "north", "east"),
        inversion = newSelectBox(properties, "inversion", 1, 14, 8, false, true),
        basic_v = newSelectBox(properties, "basic_v", 1, 34, 8, false, true)
    }

    local alarm_id = os.setAlarm(os.time() + 0.05)
    local alarm_flag = false
    term.clear()
    term.setCursorPos(15, 8)
    term.write("Press any key to continue")
    while true do
        local eventData = {os.pullEvent()}
        local event = eventData[1]
        if event == "mouse_up" or event == "key_up" or event == "alarm" or event == "mouse_click" or event ==
            "mouse_drag" or event == "key" or event == "char" then
            if not alarm_flag then
                alarm_flag = true
            else
                term.clear()
                term.setCursorPos(16, 1)
                printError(string.format("self id: %d", selfId))
                if cannon then
                    term.setCursorPos(36, 1)
                    term.write(string.format("cannon on  %s", cannon.face))
                end

                term.setCursorPos(2, 2)
                term.write("Velocity")
                term.setCursorPos(17, 2)
                term.write("BarrelLength")
                term.setCursorPos(35, 2)
                term.write("gravity: ")
                term.setCursorPos(35, 3)
                term.write("   drag: ")

                term.setCursorPos(2, 3)
                term.write("POWER_ON: ")
                term.setCursorPos(2, 4)
                term.write("FIRE: ")

                term.setCursorPos(2, 6)
                term.write("Min_Pitch: ")
                term.setCursorPos(2, 7)
                term.write("Max_Pitch: ")
                term.setCursorPos(19, 6)
                term.write("Min_Yaw: ")
                term.setCursorPos(19, 7)
                term.write("Max_Yaw: ")

                term.setCursorPos(34, 6)
                term.write("forecastMov: ")
                term.setCursorPos(34, 7)
                term.write("forecastRot: ")
                
                term.setCursorPos(2, 8)
                term.write("inversion:")
                term.setCursorPos(26, 8)
                term.write("basic_v")
                term.setCursorPos(2, 10)
                term.write("idleFace: ")

                term.setCursorPos(2, 12)
                term.write("cannonName: ")
                term.setCursorPos(2, 13)
                term.write("Password: ")
                term.setCursorPos(2, 14)
                term.write("controlCenterId: ")

                for k, v in pairs(fieldTb) do
                    v:paint()
                end

                for k, v in pairs(selectBoxTb) do
                    v:paint()
                end

                term.setCursorPos(termUtil.cpX, termUtil.cpY)

                if event == "mouse_click" then
                    term.setCursorBlink(true)
                    local x, y = eventData[3], eventData[4]
                    for k, v in pairs(fieldTb) do -- 点击了输入框
                        if y == v.y and x >= v.x and x <= v.x + v.len then
                            v:click(x, y)
                        end
                    end
                    for k, v in pairs(selectBoxTb) do -- 点击了选择框
                        if y == v.y then
                            v:click(x, y)
                        end
                    end
                elseif event == "key" then
                    local key = eventData[2]
                    for k, v in pairs(fieldTb) do
                        if termUtil.cpY == v.y and termUtil.cpX >= v.x and termUtil.cpX <= v.x + v.len then
                            v:inputKey(key)
                        end
                    end
                elseif event == "char" then
                    local char = eventData[2]
                    for k, v in pairs(fieldTb) do
                        if termUtil.cpY == v.y and termUtil.cpX >= v.x and termUtil.cpX <= v.x + v.len then
                            v:inputChar(char)
                        end
                    end
                end

                -- 刷新数据到properties
                system.updatePersistentData()
                        
                if cannon.type == "createbigcannons:cannon_mount" then
                    if properties.inversion == true then
                        cannon.cross_offset.y = -2
                    else
                        cannon.cross_offset.y = 2
                    end
                end
                
                initIdleAg()
                setYawAndPitch(cannon.idle_yaw, 0)
            end
        end
    end
end

local checkFire = function()
    while true do
        if fire and ct > 0 then
            if not redstone.getOutput(properties.fire) then
                redstone.setOutput(properties.fire, true)
            end
        else
            if redstone.getOutput(properties.fire) then
                redstone.setOutput(properties.fire, false)
            end
        end
        sleep(0.05)
    end
end

parallel.waitForAll(run_cannon, runTerm, getBullets_count, listener, sendRequest, checkFire)
