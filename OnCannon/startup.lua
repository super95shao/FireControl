peripheral.find("modem", rednet.open)

local properties, system
local protocol, request_protocol = "CBCNetWork", "CBCcenter"

----------------init-----------------
local ANGLE_TO_SPEED = 26.6666666666666666667

system = {
    fileName = "dat",
    file = nil,
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
        phyBearID = "-1",
        controlCenterId = "-1",
        mode = "hms",
        power_on = "front", --开机信号
        fire = "back",      --开火信号
        cannonOffset = { x = 0, y = 3, z = 0 },
        minPitchAngle = -45,
        face = "west",
        password = "123456",
        InvertYaw = false,
        InvertPitch = false,
        max_rotate_speed = 256,
        lock_yaw_range = "0",
        lock_yaw_face = "east",
        velocity = "158",
        barrelLength = "8",
        forecast = "16",
        P = "0.5",
        D = "1",
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

local gear = peripheral.find("Create_RotationSpeedController")
local nbt_reader = peripheral.find("blockReader")
if not nbt_reader then
    printError("Need Advanced Periperals:block_reader!")
    return
end
if not gear then
    printError("Need SpeedController")
else
    gear.setTargetSpeed(0)
    for i = 1, 2, 1 do
        redstone.setOutput(properties.power_on, false)
        redstone.setOutput(properties.power_on, true)
    end
    sleep(0.1)
end


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
        z = -q.z,
    }
end

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
    return { x = vec.x, y = vec.y, z = vec.z, name = rayCaster.block }
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
    dis = dis - barrelLength * math.cos(pitch)

    local v0 = #properties.velocity == 0 and 0 or tonumber(properties.velocity) / 20
    v0 = v0 and v0 or 0
    --local result = math.log((dis * lnD) / (v0 * math.cos(pitch)) + 1, drag)
    local result = math.abs(math.log(1 - dis / (100 * (math.cos(pitch) * v0))) / (-0.010050335853501))

    return result and result or 0
end

local lnD = ln(0.99)
local getYcoord = function(t, y0, pitch)
    t = t - 1
    local sinA = math.sin(pitch)
    local dt = math.pow(0.99, t)
    local barrelLength = #properties.barrelLength == 0 and 0 or tonumber(properties.barrelLength)
    barrelLength = barrelLength and barrelLength or 0
    y0 = barrelLength * sinA + y0
    local v0 = #properties.velocity == 0 and 0 or tonumber(properties.velocity) / 20
    local Vy = v0 * sinA
    return (dt * Vy) / lnD - (-0.05 * dt) / (lnD * (1 - 0.99)) + (-0.05 * t) / (1 - 0.99) +
        (-0.05 / (1 - 0.99) - Vy) / lnD + y0
end

local getY2 = function(t, y0, pitch)
    if t > 10000 then return "out" end
    local sinA = math.sin(pitch)
    local barrelLength = #properties.barrelLength == 0 and 0 or tonumber(properties.barrelLength)
    barrelLength = barrelLength and barrelLength or 0
    y0 = barrelLength * sinA + y0
    local v0 = #properties.velocity == 0 and 0 or tonumber(properties.velocity) / 20
    v0 = v0 and v0 or 0
    local Vy = v0 * sinA

    local index = 1
    local lastY0, lastVy = 0, 0
    while index < t do
        lastY0 = y0
        lastVy = Vy
        y0 = y0 + Vy
        Vy = 0.99 * Vy - 0.05
        index = index + 1
    end

    index = index - 1
    y0 = lastY0
    Vy = lastVy
    for i = index, t, 0.1 do
        Vy = 0.999 * Vy
        y0 = y0 + Vy
    end

    return y0
end

local ag_binary_search = function(arr, xDis, y0, yDis)
    local low = 1
    local high = #arr
    local mid, time
    while low <= high do
        mid = math.floor((low + high) / 2)
        local pitch = math.rad(arr[mid])
        time = getTime(xDis, pitch)
        local result = yDis - getY2(time, y0, pitch)
        if result >= -0.015 and result <= 0.015 then
            return mid, time
        elseif result > 0 then
            low = mid + 1
        else
            high = mid - 1
        end
    end
    return mid, time
end

local parent = { quat = { w = 1, x = 0, y = 0, z = 0 } }
local controlCenter = { tgPos = { x = 0, y = 0, z = 0 }, velocity = { x = 0, y = 0, z = 0 }, mode = 2, fire = false }
local listener = function()
    local parentId = #properties.phyBearID == 0 and 0 or tonumber(properties.phyBearID)
    parentId = parentId and parentId or 0
    local controlCenterId = #properties.controlCenterId == 0 and 0 or tonumber(properties.controlCenterId)
    controlCenterId = controlCenterId and controlCenterId or 0
    while true do
        local id, msg = rednet.receive(protocol, 2)
        if not id then
            parentId = #properties.phyBearID == 0 and 0 or tonumber(properties.phyBearID)
            parentId = parentId and parentId or 0
        elseif id == parentId then
            parent.quat = msg
        elseif id == controlCenterId then
            controlCenter = msg
        end
    end
end

local sendRequest = function()
    while true do
        local controlCenterId = #properties.controlCenterId == 0 and 0 or tonumber(properties.controlCenterId)
        controlCenterId = controlCenterId and controlCenterId or 0
        rednet.send(controlCenterId, { name = properties.cannonName, pw = properties.password }, request_protocol)
        sleep(1)
    end
end

local cannonNet = function()
    parallel.waitForAll(sendRequest, listener)
end

local cannon = { CannonPitch = 0, CannonYaw = 0 }
local getPitch = function()
    while true do
        cannon = nbt_reader.getBlockData()
    end
end

local runListener = function()
    parallel.waitForAll(cannonNet, getPitch)
end


local quatList = {
    west  = { w = -1, x = 0, y = 0, z = 0 },
    south = { w = -0.70710678118654752440084436210485, x = 0, y = -0.70710678118654752440084436210485, z = 0 },
    east  = { w = 0, x = 0, y = -1, z = 0 },
    north = { w = -0.70710678118654752440084436210485, x = 0, y = 0.70710678118654752440084436210485, z = 0 },
}

local cannonUtil = {
    pos = { x = 0, y = 0, z = 0 },
    prePos = { x = 0, y = 0, z = 0 },
    velocity = { x = 0, y = 0, z = 0 },
    preVel = { x = 0, y = 0, z = 0 }
}

function cannonUtil:getAtt()
    self.pos = getCannonPos()
    if ship then
        local v = ship.getVelocity()
        self.velocity = {
            x = v.x / 20,
            y = v.y / 20,
            z = v.z / 20,
        }
    else
        self.velocity = {
            x = self.pos.x - self.prePos.x,
            y = self.pos.y - self.prePos.y,
            z = self.pos.z - self.prePos.z,
        }
    end


    self.quat = quatMultiply(quatList[properties.face], ship.getQuaternion())
end

function cannonUtil:setPreAtt()
    self.prePos = self.pos
    self.preVel = self.velocity
end

function cannonUtil:getNextPos(t)
    --local v2 = {
    --    x = self.velocity.x / self.preVel.x,
    --    y = self.velocity.y / self.preVel.y,
    --    z = self.velocity.z / self.preVel.z,
    --}
    --local velocity = {
    --    x = self.velocity.x,
    --    y = self.velocity.y,
    --    z = self.velocity.z,
    --}
    --
    --for i = 1, t, 1 do
    --    velocity.x = velocity.x * math.abs(v2.x)
    --    velocity.y = velocity.y * math.abs(v2.y)
    --    velocity.z = velocity.z * math.abs(v2.z)
    --end

    return {
        x = self.pos.x + self.velocity.x * t,
        y = self.pos.y + self.velocity.y * t,
        z = self.pos.z + self.velocity.z * t,
    }
end

local pitchList = {}
for i = -90, 90, 0.0375 do
    table.insert(pitchList, i)
end

------------------------------------------

local preQ = ship.getQuaternion()
local runCt = function()
    while true do
        cannonUtil:getAtt()

        local forecast = #properties.forecast == 0 and 0 or tonumber(properties.forecast)
        forecast = forecast and forecast or 16
        local cannonPos = cannonUtil:getNextPos(forecast)
        --genParticle(cannonPos.x, cannonPos.y, cannonPos.z)

        local target = controlCenter.tgPos
        --commands.execAsync(("say x=%0.4f, y=%0.4f, z=%0.4f"):format(target.x, target.y, target.z))
        local tgVec = {
            x = target.x - cannonPos.x,
            y = target.y - cannonPos.y,
            z = target.z - cannonPos.z
        }
        --genParticle(cannonPos.x, cannonPos.y, cannonPos.z)

        local q = cannonUtil.quat

        local pX = RotateVectorByQuat(q, { x = 1, y = 0, z = 0 })
        local pY = RotateVectorByQuat(q, { x = 0, y = 1, z = 0 })
        local pZ = RotateVectorByQuat(q, { x = 0, y = 0, z = -1 })
        preQ.x = -preQ.x
        preQ.y = -preQ.y
        preQ.z = -preQ.z
        local XPoint = RotateVectorByQuat(preQ, pX)
        local ZPoint = RotateVectorByQuat(preQ, pZ)
        local omega = {
            x = math.deg(math.asin(ZPoint.y)),
            z = math.deg(math.asin(XPoint.y)),
            y = math.deg(math.atan2(-XPoint.z, XPoint.x))
        }

        local xDis = math.sqrt(tgVec.x ^ 2 + tgVec.z ^ 2)
        local mid, cTime = ag_binary_search(pitchList, xDis, 0, tgVec.y)
        local tmpPitch = pitchList[mid]

        if controlCenter.mode > 2 then
            --commands.execAsync(("say cTime=%0.1f"):format(cTime))
            cTime = cTime + 10
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
            tmpPitch = pitchList[mid]
        end

        --commands.execAsync(("say tmpPitch=%0.4f, cTime=%0.4f"):format(tmpPitch, cTime))
        --commands.execAsync(("say xDis=%0.2f, y=%0.2f, tmpPitch=%0.2f, cTime=%0.2f"):format(xDis, tgVec.y, tmpPitch, cTime))
        local allDis = math.sqrt(tgVec.x ^ 2 + tgVec.y ^ 2 + tgVec.z ^ 2)
        local tmpVec = {
            x = tgVec.x,
            y = allDis * math.sin(math.rad(tmpPitch)),
            z = tgVec.z
        }

        local rot = RotateVectorByQuat(quatMultiply(quatList[properties.face], getConjQuat(ship.getQuaternion())), tmpVec)
        --genParticle(cannonPos.x + tmpVec.x, cannonPos.y + tmpVec.y, cannonPos.z + tmpVec.z)
        --commands.execAsync(("say x=%0.4f, y=%0.4f, z=%0.4f"):format(tmpVec.x, tmpVec.y, tmpVec.z))

        local tmpYaw = -math.deg(math.atan2(rot.z, -rot.x))
        local localVec = RotateVectorByQuat(quatMultiply(quatList[properties.lock_yaw_face], getConjQuat(parent.quat)), tmpVec)

        local yaw_range = #properties.lock_yaw_range == 0 and 0 or tonumber(properties.lock_yaw_range)
        yaw_range = yaw_range and yaw_range or 0
        local localYaw = -math.deg(math.atan2(localVec.z, -localVec.x))
        --commands.execAsync(("say localYaw=%d"):format(localYaw))
        if math.abs(localYaw) < yaw_range then
            tmpYaw = 0
        end
        --commands.execAsync(("say tmpYaw=%0.2f"):format(tmpYaw))
        local p = #properties.P == 0 and 0 or tonumber(properties.P)
        p = p and p or 0
        local d = #properties.D == 0 and 0 or tonumber(properties.D)
        d = d and d or 0
        local yawSpeed = math.floor(pdCt(tmpYaw, omega.y, p, d) + 0.5)
        if properties.InvertYaw then
            yawSpeed = -yawSpeed
        end

        local id = #properties.phyBearID == 0 and 0 or tonumber(properties.phyBearID)
        id = id and id or 0
        rednet.send(id, yawSpeed, protocol)
        preQ = q

        ------self(pitch)-------
        local tgPitch = math.deg(math.asin(rot.y / math.sqrt(rot.x ^ 2 + rot.y ^ 2 + rot.z ^ 2)))

        --commands.execAsync(("say tgPitch=%d, CannonPitch=%d"):format(tgPitch, cannon.CannonPitch))
        tgPitch = tgPitch < properties.minPitchAngle and properties.minPitchAngle or tgPitch

        if properties.InvertPitch then
            tgPitch = resetAngelRange(tgPitch - cannon.CannonPitch)
        else
            tgPitch = resetAngelRange(cannon.CannonPitch - tgPitch)
        end

        tgPitch = math.abs(tgPitch) > 0.01875 and tgPitch or 0
        local pSpeed = math.floor(tgPitch * ANGLE_TO_SPEED / 8 + 0.5)
        pSpeed = math.abs(pSpeed) < properties.max_rotate_speed and pSpeed or
            copysign(properties.max_rotate_speed, pSpeed)
        --commands.execAsync(("say tgPitch=%0.2f, CannonPitch=%0.2f"):format(tgPitch, cannon.CannonPitch))

        --commands.execAsync(("say yaw=%0.2f, pitch=%0.2f"):format(omega.y, cannon.CannonPitch))
        gear.setTargetSpeed(pSpeed)
        cannonUtil:setPreAtt()
    end
end

local termUtil = {
    cpX = 1,
    cpY = 1,
}

local absTextField = {
    x = 1,
    y = 1,
    len = 15,
    text = "",
    textCorlor = "0",
    backgroundColor = "8",
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
            field = string.sub(field, 1, xPos) .. char .. strEnd
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
    if key == 259 or key == 261 then --backSpace
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
        --print("enter")
    elseif key == 262 or key == 263 then
        if key == 262 then
            termUtil.cpX = termUtil.cpX + 1
        elseif key == 263 then
            termUtil.cpX = termUtil.cpX - 1
        end
    elseif key == 264 or key == 258 then
        --print("down")
    elseif key == 265 then
        --print("up")
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
    return setmetatable({ key = key, value = value, type = type(key[value]), x = x, y = y },
        { __index = absTextField })
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
    return setmetatable(
        { key = key, value = value, interval = interval, x = x, y = y, type = type(key[value]), contents = { ... } },
        { __index = absSelectBox })
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
    return setmetatable({ key = key, value = value, min = min, max = max, len = len, x = x, y = y },
        { __index = absSlider })
end

local runTerm = function()
    local fieldTb = {
        velocity = newTextField(properties, "velocity", 11, 2),
        barrelLength = newTextField(properties, "barrelLength", 30, 2),
        phyBearIdField = newTextField(properties, "phyBearID", 46, 2),
        minPitchAngle = newTextField(properties, "minPitchAngle", 17, 8),
        max_rotate_speed = newTextField(properties, "max_rotate_speed", 20, 10),
        lock_yaw_range = newTextField(properties, "lock_yaw_range", 20, 12),
        cannonOffset_x = newTextField(properties.cannonOffset, "x", 18, 6),
        cannonOffset_y = newTextField(properties.cannonOffset, "y", 24, 6),
        cannonOffset_z = newTextField(properties.cannonOffset, "z", 30, 6),
        P = newTextField(properties, "P", 4, 16),
        D = newTextField(properties, "D", 12, 16),
        forecast = newTextField(properties, "forecast", 37, 16),
        cannonName = newTextField(properties, "cannonName", 14, 17),
        controlCenterId = newTextField(properties, "controlCenterId", 19, 18),
        password = newTextField(properties, "password", 37, 18),
    }
    fieldTb.velocity.len = 5
    fieldTb.barrelLength.len = 3
    fieldTb.controlCenterId.len = 5
    fieldTb.password.len = 14
    fieldTb.minPitchAngle.len = 5
    fieldTb.max_rotate_speed.len = 5
    fieldTb.lock_yaw_range.len = 5
    fieldTb.phyBearIdField.len = 5
    fieldTb.cannonOffset_x.len = 3
    fieldTb.cannonOffset_y.len = 3
    fieldTb.cannonOffset_z.len = 3
    fieldTb.P.len = 5
    fieldTb.D.len = 5
    fieldTb.forecast.len = 5
    local selectBoxTb = {
        power_on = newSelectBox(properties, "power_on", 2, 12, 3, "top", "bottom", "left", "right", "front", "back"),
        fire = newSelectBox(properties, "fire", 2, 8, 4, "top", "bottom", "left", "right", "front", "back"),
        face = newSelectBox(properties, "face", 2, 8, 5, "south", "west", "north", "east"),
        lock_yaw_face = newSelectBox(properties, "lock_yaw_face", 2, 27, 12, "south", "west", "north", "east"),
        InvertYaw = newSelectBox(properties, "InvertYaw", 1, 41, 14, false, true),
        InvertPitch = newSelectBox(properties, "InvertPitch", 1, 15, 14, false, true),
    }

    local sliderTb = {
        minPitchAngle = newSlider(properties, "minPitchAngle", -45, 60, 49, 2, 9),
        max_rotate_speed = newSlider(properties, "max_rotate_speed", 0, 256, 49, 2, 11),
    }

    local alarm_id = os.setAlarm(os.time() + 0.05)
    local alarm_flag = false
    term.clear()
    term.setCursorPos(15, 8)
    term.write("click or waiting...")
    while true do
        local eventData = { os.pullEvent() }
        local event = eventData[1]
        if event == "mouse_up" or event == "key_up" or event == "alarm"
            or event == "mouse_click" or event == "mouse_drag" or event == "key" or event == "char" then
            if not alarm_flag then
                alarm_flag = true
            else
                term.clear()
                term.setCursorPos(2, 2)
                term.write("Velocity")
                term.setCursorPos(17, 2)
                term.write("BarrelLength")
                term.setCursorPos(36, 2)
                term.write("Yaw_Pc_ID")

                term.setCursorPos(2, 3)
                term.write("POWER_ON: ")
                term.setCursorPos(2, 4)
                term.write("FIRE: ")

                term.setCursorPos(2, 6)
                term.write("CannonOffset: x=    y=    z=")

                term.setCursorPos(2, 8)
                term.write("MinPitchAngle: ")
                term.setCursorPos(2, 10)
                term.write("Max_rotate_speed: ")
                term.setCursorPos(2, 12)
                term.write("lock_yaw_range: +-")

                term.setCursorPos(2, 5)
                term.write("Face: ")

                term.setCursorPos(2, 14)
                term.write("InvertPitch: ")
                term.setCursorPos(30, 14)
                term.write("InvertYaw: ")

                term.setCursorPos(2, 16)
                term.write("P: ")
                term.setCursorPos(10, 16)
                term.write("D: ")
                term.setCursorPos(27, 16)
                term.write("forecast: ")

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
                    for k, v in pairs(fieldTb) do --点击了输入框
                        if y == v.y and x >= v.x and x <= v.x + v.len then
                            v:click(x, y)
                        end
                    end
                    for k, v in pairs(selectBoxTb) do --点击了选择框
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

                --刷新数据到properties
                system.updatePersistentData()
            end
        end
    end
end

local checkFire = function()
    while true do
        if controlCenter.fire then
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

local runCannonControl = function()
    parallel.waitForAll(runCt, checkFire)
end

local run = function()
    parallel.waitForAll(runCannonControl, runTerm)
end

parallel.waitForAll(run, runListener)
