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
        YawBearID = "-1",
        PitchBearID = "-1",
        controlCenterId = "-1",
        mode = "hms",
        power_on = "front", -- 开机信号
        fire = "back", -- 开火信号
        cannonOffset = {
            x = 0,
            y = 3,
            z = 0
        },
        minPitchAngle = -90,
        face = "west",
        password = "123456",
        InvertYaw = false,
        InvertPitch = false,
        max_rotate_speed = 256,
        lock_yaw_range = "0",
        lock_yaw_face = "east",
        velocity = "160",
        barrelLength = "8",
        forecastMov = "24",
        forecastRot = "3.4",
        gravity = "0.05",
        drag = "0.01",
        P = "1",
        D = "6"
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

for i = 1, 2, 1 do
    redstone.setOutput(properties.power_on, false)
    redstone.setOutput(properties.power_on, true)
end
sleep(0.5)

-----------function------------
local quatMultiply = function(q1, q2)
    local newQuat = {}
    newQuat.w = -q1.x * q2.x - q1.y * q2.y - q1.z * q2.z + q1.w * q2.w
    newQuat.x = q1.x * q2.w + q1.y * q2.z - q1.z * q2.y + q1.w * q2.x
    newQuat.y = -q1.x * q2.z + q1.y * q2.w + q1.z * q2.x + q1.w * q2.y
    newQuat.z = q1.x * q2.y - q1.y * q2.x + q1.z * q2.w + q1.w * q2.z
    return newQuat
end

local RotateVectorByQuat = function(quat, v)
    local x = quat.x * 2
    local y = quat.y * 2
    local z = quat.z * 2
    local xx = quat.x * x
    local yy = quat.y * y
    local zz = quat.z * z
    local xy = quat.x * y
    local xz = quat.x * z
    local yz = quat.y * z
    local wx = quat.w * x
    local wy = quat.w * y
    local wz = quat.w * z
    local res = {}
    res.x = (1.0 - (yy + zz)) * v.x + (xy - wz) * v.y + (xz + wy) * v.z
    res.y = (xy + wz) * v.x + (1.0 - (xx + zz)) * v.y + (yz - wx) * v.z
    res.z = (xz - wy) * v.x + (yz + wx) * v.y + (1.0 - (xx + yy)) * v.z
    return res
end

local getConjQuat = function(q)
    return {
        w = q.w,
        x = -q.x,
        y = -q.y,
        z = -q.z
    }
end

local quatList = {
    west = {
        w = -1,
        x = 0,
        y = 0,
        z = 0
    },
    south = {
        w = -0.70710678118654752440084436210485,
        x = 0,
        y = -0.70710678118654752440084436210485,
        z = 0
    },
    east = {
        w = 0,
        x = 0,
        y = -1,
        z = 0
    },
    north = {
        w = -0.70710678118654752440084436210485,
        x = 0,
        y = 0.70710678118654752440084436210485,
        z = 0
    }
}

local copysign = function(num1, num2)
    num1 = math.abs(num1)
    num1 = num2 > 0 and num1 or -num1
    return num1
end

local genParticle = function(x, y, z)
    commands.execAsync(string.format("particle electric_spark %0.6f %0.6f %0.6f 0 0 0 0 0 force", x, y, z))
end

local genStr = function(s, count)
    local result = ""
    for i = 1, count, 1 do
        result = result .. s
    end
    return result
end

local resetAngelRange = function(angle)
    if (math.abs(angle) > 180) then
        angle = math.abs(angle) >= 360 and angle % 360 or angle
        return -copysign(360 - math.abs(angle), angle)
    else
        return angle
    end
end

local rayCaster = {
    block = nil
}

rayCaster.run = function(start, v3Speed, range, showParticle)
    local vec = {}
    vec.x = start.x
    vec.y = start.y
    vec.z = start.z
    for i = 0, range, 1 do
        vec.x = vec.x + v3Speed.x
        vec.y = vec.y + v3Speed.y
        vec.z = vec.z + v3Speed.z

        rayCaster.block = coordinate.getBlock(vec.x, vec.y, vec.z - 1)
        if (rayCaster.block ~= "minecraft:air" or i >= range) then
            break
        end
        if showParticle then
            genParticle(vec.x, vec.y, vec.z)
        end
    end
    return {
        x = vec.x,
        y = vec.y,
        z = vec.z,
        name = rayCaster.block
    }
end

local getCannonPos = function()
    local wPos = ship.getWorldspacePosition()
    local yardPos = ship.getShipyardPosition()
    local selfPos = coordinate.getAbsoluteCoordinates()
    local offset = {
        x = yardPos.x - selfPos.x - 0.5 - properties.cannonOffset.x,
        y = yardPos.y - selfPos.y - 0.5 - properties.cannonOffset.y,
        z = yardPos.z - selfPos.z - 0.5 - properties.cannonOffset.z
    }
    offset = RotateVectorByQuat(ship.getQuaternion(), offset)
    return {
        x = wPos.x - offset.x,
        y = wPos.y - offset.y,
        z = wPos.z - offset.z
    }
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
    local cosP = math.cos(pitch)
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
    while index < t do
        y0 = y0 + Vy
        Vy = drag * Vy - grav
        index = index + 1
    end

    return y0
end

local ag_binary_search = function(arr, xDis, y0, yDis)
    local low = 1
    local high = #arr
    local mid, time
    while low <= high do
        mid = math.floor((low + high) / 2)
        local pitch = arr[mid]
        time = getTime(xDis, pitch)
        local result = yDis - getY2(time, y0, pitch)
        if result >= -0.018 and result <= 0.018 then
            return mid, time
        elseif result > 0 then
            low = mid + 1
        else
            high = mid - 1
        end
    end
    return mid, time
end

local newVec = function()
    return {
        x = 0,
        y = 0,
        z = 0
    }
end
local newQuat = function ()
    return {
        w = 1,
        x = 0,
        y = 0,
        z = 0
    }
end

local parent = {
    pos = newVec(),
    quat = newQuat(),
    omega = newVec(),
    velocity = newVec()
}
local controlCenter = {
    tgPos = newVec(),
    velocity = newVec(),
    mode = 2,
    fire = false
}

local getPD = function ()
    local p = #properties.P == 0 and 0 or tonumber(properties.P)
    p = p and p or 0
    local d = #properties.D == 0 and 0 or tonumber(properties.D)
    d = d and d or 0
    return p, d
end

local getBearId = function ()
    local YawId = #properties.YawBearID == 0 and 0 or tonumber(properties.YawBearID)
    local PitchId = #properties.PitchBearID == 0 and 0 or tonumber(properties.PitchBearID)
    YawId = YawId and YawId or 0
    PitchId = PitchId and PitchId or 0
    return YawId, PitchId
end

local ct = 20
local listener = function()
    local YawId, PitchId = getBearId()
    local controlCenterId = #properties.controlCenterId == 0 and 0 or tonumber(properties.controlCenterId)
    controlCenterId = controlCenterId and controlCenterId or 0
    while true do
        local id, msg = rednet.receive(protocol, 2)
        if not id then
            YawId, PitchId = getBearId()
        elseif id == YawId then
            parent.quat = msg.quat
            parent.omega = msg.omega
            parent.slug = msg.slug
            parent.velocity = msg.velocity
            parent.pos = msg.pos
        elseif id == controlCenterId then
            controlCenter = msg
            ct = 20
        end
    end
end

local sendRequest = function()
    local slug = ship and ship.getName() or nil
    while true do
        local controlCenterId = #properties.controlCenterId == 0 and 0 or tonumber(properties.controlCenterId)
        controlCenterId = controlCenterId and controlCenterId or 0
        rednet.send(controlCenterId, {
            name = properties.cannonName,
            pw = properties.password,
            slug = slug,
            yawSlug = parent.slug
        }, request_protocol)
        sleep(1)
    end
end

local runListener = function()
    parallel.waitForAll(sendRequest, listener)
end

local cannonUtil = {
    pos = newVec(),
    prePos = newVec(),
    velocity = newVec()
}

function cannonUtil:getAtt()
    self.pos = getCannonPos()
    if ship then
        local v = ship.getVelocity()
        self.velocity = {
            x = v.x / 20,
            y = v.y / 20,
            z = v.z / 20
        }
    else
        self.velocity = {
            x = self.pos.x - self.prePos.x,
            y = self.pos.y - self.prePos.y,
            z = self.pos.z - self.prePos.z
        }
    end

    self.quat = quatMultiply(quatList[properties.face], ship.getQuaternion())
end

function cannonUtil:setPreAtt()
    self.prePos = self.pos
end

function cannonUtil:getNextPos(t)
    return {
        x = self.pos.x + self.velocity.x * t,
        y = self.pos.y + self.velocity.y * t,
        z = self.pos.z + self.velocity.z * t
    }
end

local pitchList = {}
for i = -90, 90, 0.0375 do
    table.insert(pitchList, math.rad(i))
end

------------------------------------------

local omega2Q = function (omega, tick)
    local omegaRot = {
        x = omega.x / tick,
        y = omega.y / tick,
        z = omega.z / tick
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

local fire = false
local runCt = function()
    while true do
        cannonUtil:getAtt()

        local omega = RotateVectorByQuat(getConjQuat(ship.getQuaternion()), ship.getOmega())

        local nextQ, pNextQ = ship.getQuaternion(), parent.quat
        --commands.execAsync(("say x=%0.2f, y=%0.2f, z=%0.2f"):format(pOmega.x, pOmega.y, pOmega.z))

        local forecastRot = #properties.forecastRot == 0 and 0 or tonumber(properties.forecastRot)
        forecastRot = forecastRot and forecastRot or 16

        local omegaQuat = omega2Q(parent.omega, 20 / forecastRot)

        if omegaQuat then
            nextQ = quatMultiply(nextQ, omegaQuat)
            pNextQ = quatMultiply(pNextQ, omegaQuat)
        end
        
        local pErr = {
            x = cannonUtil.pos.x - parent.pos.x,
            y = cannonUtil.pos.y - parent.pos.y,
            z = cannonUtil.pos.z - parent.pos.z,
        }

        local pNextQ2 = parent.quat
        local omegaQ2 = omega2Q(parent.omega, 6 / forecastRot)
        if omegaQ2 then
            pNextQ2 = quatMultiply(pNextQ2, omegaQ2)
        end
        pErr = RotateVectorByQuat(getConjQuat(parent.quat), pErr)
        pErr = RotateVectorByQuat(pNextQ2, pErr)
        
        --commands.execAsync(("say x=%0.4f, y=%0.4f, z=%0.4f"):format(pErr.x, pErr.y, pErr.z))

        local forecastMov = #properties.forecastMov == 0 and 0 or tonumber(properties.forecastMov)
        forecastMov = forecastMov and forecastMov or 16
        local cannonPos = {
            x = parent.pos.x + parent.velocity.x * forecastMov,
            y = parent.pos.y + parent.velocity.y * forecastMov,
            z = parent.pos.z + parent.velocity.z * forecastMov
        }
        cannonPos.x = cannonPos.x + pErr.x
        cannonPos.y = cannonPos.y + pErr.y
        cannonPos.z = cannonPos.z + pErr.z

        if commands then
            genParticle(cannonPos.x, cannonPos.y, cannonPos.z)
        end

        if ct > 0 then
            ct = ct - 1
            local target = controlCenter.tgPos
            target.x = target.x + controlCenter.velocity.x * 8
            target.y = target.y + controlCenter.velocity.y * 8
            target.z = target.z + controlCenter.velocity.z * 8
            --commands.execAsync(("say x=%0.4f, y=%0.4f, z=%0.4f"):format(target.x, target.y, target.z))
            local tgVec = {
                x = target.x - cannonPos.x,
                y = target.y - cannonPos.y,
                z = target.z - cannonPos.z
            }
            --genParticle(cannonPos.x, cannonPos.y, cannonPos.z)

            local xDis = math.sqrt(tgVec.x ^ 2 + tgVec.z ^ 2)
            local mid, cTime = ag_binary_search(pitchList, xDis, 0, tgVec.y)
            local calcPitch, tmpVec

            if cTime > 5 then
                calcPitch = pitchList[mid]
                if controlCenter.mode > 2 then
                    target.x = target.x + controlCenter.velocity.x * cTime
                    target.y = target.y + controlCenter.velocity.y * cTime
                    target.z = target.z + controlCenter.velocity.z * cTime
                    tgVec = {
                        x = target.x - cannonPos.x,
                        y = target.y - cannonPos.y,
                        z = target.z - cannonPos.z
                    }
                    xDis = math.sqrt(tgVec.x ^ 2 + tgVec.z ^ 2)
                    mid, cTime = ag_binary_search(pitchList, xDis, 0, tgVec.y)
                    calcPitch = pitchList[mid]
                end

                local _c = math.sqrt(tgVec.x ^ 2 + tgVec.z ^ 2)
                local allDis = math.sqrt(tgVec.x ^ 2 + tgVec.z ^ 2 + tgVec.z ^ 2)
                local cosP = math.cos(calcPitch)
                tmpVec = {
                    x = allDis * (tgVec.x / _c) * cosP,
                    y = allDis * math.sin(calcPitch),
                    z = allDis * (tgVec.z / _c) * cosP
                }
            else
                tmpVec = tgVec
            end

            local rot = RotateVectorByQuat(quatMultiply(quatList[properties.face], getConjQuat(nextQ)), tmpVec)

            local tmpYaw = -math.deg(math.atan2(rot.z, -rot.x))
            local tmpPitch = math.deg(math.asin(rot.y / math.sqrt(rot.x ^ 2 + rot.y ^ 2 + rot.z ^ 2)))

            local localVec = RotateVectorByQuat(quatMultiply(quatList[properties.lock_yaw_face], getConjQuat(parent.quat)), tmpVec)

            local yaw_range = #properties.lock_yaw_range == 0 and 0 or tonumber(properties.lock_yaw_range)
            yaw_range = yaw_range and yaw_range or 0
            local localYaw = -math.deg(math.atan2(localVec.z, -localVec.x))
            local localPitch = math.deg(math.asin(localVec.y / math.sqrt(localVec.x ^ 2 + localVec.y ^ 2 + localVec.z ^ 2)))
            if math.abs(localYaw) < yaw_range then
                --tmpYaw = copysign(yaw_range, tmpYaw)
                tmpYaw = 0
            end

            if localPitch < properties.minPitchAngle then
                tmpPitch = 0
                fire = false
            else
                fire = controlCenter.fire
            end

            local p, d = getPD()
            local yawSpeed = math.floor(pdCt(tmpYaw, omega.y, p, d) + 0.5)
            local pitchSpeed = math.floor(pdCt(tmpPitch, omega.z, p, d) + 0.5)

            if properties.InvertYaw then
                yawSpeed = -yawSpeed
            end
            if properties.InvertPitch then
                pitchSpeed = -pitchSpeed
            end

            local YawId, PitchId = getBearId()
            rednet.send(YawId, yawSpeed, protocol)
            rednet.send(PitchId, pitchSpeed, protocol)
        else
            local xP = RotateVectorByQuat(parent.quat, {
                x = 1,
                y = 0,
                z = 0
            })
            local pq = {
                w = cannonUtil.quat.w,
                x = -cannonUtil.quat.x,
                y = -cannonUtil.quat.y,
                z = -cannonUtil.quat.z
            }
            local xP2 = RotateVectorByQuat(pq, xP)
            local resultYaw
            if properties.InvertYaw then
                resultYaw = -math.deg(math.atan2(xP2.z, xP2.x))
            else
                resultYaw = -math.deg(math.atan2(xP2.z, -xP2.x))
            end
            local resultPitch = math.deg(math.asin(xP2.y / math.sqrt(xP2.x ^ 2 + xP2.y ^ 2 + xP2.z ^ 2)))

            --if properties.InvertPitch then
            --    resultPitch = -resultPitch
            --end

            local p, d = getPD()
            local yawSpeed = math.floor(pdCt(resultYaw, omega.y, p, d) + 0.5)
            local pitchSpeed = math.floor(pdCt(resultPitch, omega.z, p, d) + 0.5)

            if math.abs(resultYaw) or math.abs(resultPitch) > 10 then
                fire = false
            end

            local YawId, PitchId = getBearId()
            rednet.send(YawId, yawSpeed, protocol)
            rednet.send(PitchId, pitchSpeed, protocol)
        end
        cannonUtil:setPreAtt()
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
        velocity = newTextField(properties, "velocity", 11, 2),
        barrelLength = newTextField(properties, "barrelLength", 30, 2),
        YawBearID = newTextField(properties, "YawBearID", 15, 13),
        PitchBearID = newTextField(properties, "PitchBearID", 15, 14),
        minPitchAngle = newTextField(properties, "minPitchAngle", 17, 8),
        max_rotate_speed = newTextField(properties, "max_rotate_speed", 20, 10),
        lock_yaw_range = newTextField(properties, "lock_yaw_range", 20, 12),
        cannonOffset_x = newTextField(properties.cannonOffset, "x", 18, 6),
        cannonOffset_y = newTextField(properties.cannonOffset, "y", 24, 6),
        cannonOffset_z = newTextField(properties.cannonOffset, "z", 30, 6),
        P = newTextField(properties, "P", 4, 16),
        D = newTextField(properties, "D", 12, 16),
        gravity = newTextField(properties, "gravity", 45, 6),
        drag = newTextField(properties, "drag", 45, 7),
        forecastMov = newTextField(properties, "forecastMov", 46, 16),
        forecastRot = newTextField(properties, "forecastRot", 46, 17),
        cannonName = newTextField(properties, "cannonName", 14, 17),
        controlCenterId = newTextField(properties, "controlCenterId", 19, 18),
        password = newTextField(properties, "password", 37, 18)
    }
    fieldTb.velocity.len = 5
    fieldTb.barrelLength.len = 3
    fieldTb.controlCenterId.len = 5
    fieldTb.password.len = 14
    fieldTb.minPitchAngle.len = 5
    fieldTb.max_rotate_speed.len = 5
    fieldTb.lock_yaw_range.len = 5
    fieldTb.YawBearID.len = 5
    fieldTb.PitchBearID.len = 5
    fieldTb.cannonOffset_x.len = 3
    fieldTb.cannonOffset_y.len = 3
    fieldTb.cannonOffset_z.len = 3
    fieldTb.P.len = 5
    fieldTb.D.len = 5
    fieldTb.gravity.len = 6
    fieldTb.drag.len = 6
    fieldTb.forecastMov.len = 5
    fieldTb.forecastRot.len = 5
    local selectBoxTb = {
        power_on = newSelectBox(properties, "power_on", 2, 12, 3, "top", "left", "right", "front", "back"),
        fire = newSelectBox(properties, "fire", 2, 8, 4, "top", "left", "right", "front", "back"),
        face = newSelectBox(properties, "face", 2, 8, 5, "south", "west", "north", "east"),
        lock_yaw_face = newSelectBox(properties, "lock_yaw_face", 2, 27, 12, "south", "west", "north", "east"),
        InvertYaw = newSelectBox(properties, "InvertYaw", 1, 41, 13, false, true),
        InvertPitch = newSelectBox(properties, "InvertPitch", 1, 41, 14, false, true)
    }

    local sliderTb = {
        minPitchAngle = newSlider(properties, "minPitchAngle", -90, 60, 49, 2, 9),
        max_rotate_speed = newSlider(properties, "max_rotate_speed", 0, 256, 49, 2, 11)
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
                term.setCursorPos(18, 1)
                printError(string.format("self id: %d", selfId))
                term.setCursorPos(2, 2)
                term.write("Velocity")
                term.setCursorPos(17, 2)
                term.write("BarrelLength")

                term.setCursorPos(2, 3)
                term.write("POWER_ON: ")
                term.setCursorPos(2, 4)
                term.write("FIRE: ")

                term.setCursorPos(2, 6)
                term.write("CannonOffset: x=    y=    z=")
                term.setCursorPos(36, 6)
                term.write("gravity: ")
                term.setCursorPos(36, 7)
                term.write("   drag: ")

                term.setCursorPos(2, 8)
                term.write("MinPitchAngle: ")
                term.setCursorPos(2, 10)
                term.write("Max_rotate_speed: ")
                term.setCursorPos(2, 12)
                term.write("lock_yaw_range: +-")

                term.setCursorPos(2, 5)
                term.write("Face: ")

                term.setCursorPos(2, 13)
                term.write("YawBearId: ")
                term.setCursorPos(2, 14)
                term.write("PitchBearId: ")

                term.setCursorPos(30, 13)
                term.write("InvertYaw: ")
                term.setCursorPos(28, 14)
                term.write("InvertPitch: ")

                term.setCursorPos(2, 16)
                term.write("P: ")
                term.setCursorPos(10, 16)
                term.write("D: ")
                term.setCursorPos(34, 16)
                term.write("forecastMov: ")
                term.setCursorPos(34, 17)
                term.write("forecastRot: ")

                term.setCursorPos(2, 17)
                term.write("cannonName: ")
                term.setCursorPos(2, 18)
                term.write("controlCenterId: ")
                term.setCursorPos(27, 18)
                term.write("Password: ")

                for k, v in pairs(fieldTb) do
                    v:paint()
                end

                for k, v in pairs(selectBoxTb) do
                    v:paint()
                end

                for k, v in pairs(sliderTb) do
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
                    for k, v in pairs(sliderTb) do
                        if y == v.y then
                            v:click(x, y)
                        end
                    end
                elseif event == "mouse_drag" then
                    local x, y = eventData[3], eventData[4]
                    for k, v in pairs(sliderTb) do
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
            end
        end
    end
end

local checkFire = function()
    while true do
        if fire and ct > 0 then
            redstone.setOutput(properties.fire, controlCenter.fire)
        else
            redstone.setOutput(properties.fire, false)
        end
        sleep(0.05)
    end
end

local runCannonControl = function()
    parallel.waitForAll(runCt, checkFire)
end

local run = function()
    parallel.waitForAll(runCannonControl, runTerm)
end

parallel.waitForAll(run, runListener)
