peripheral.find("modem", rednet.open)
local missile_protocol, request_protocol = "CBCMissileNetWork", "CBCcenter"
local properties, system

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
        controlCenterId = "-1",
        password = "123456",
        shot_face = "down",
        offset = 1,
        speed = 6,
        shot_ct = 10,
        max_flying_time = 200,
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

local genStr = function(s, count)
    local result = ""
    for i = 1, count, 1 do
        result = result .. s
    end
    return result
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
local square = function (num)
    return num * num
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
local faces = {
    up = newVec(0, 1, 0),
    down = newVec(0, -1, 0),
    north = newVec(0, 0, -1),
    south = newVec(0, 0, 1),
    west = newVec(-1, 0, 0),
    east = newVec(1, 0, 0)
}

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
        local id, msg = rednet.receive(missile_protocol, 2)
        if id == controlCenterId then
            controlCenter = msg
            ct = 20
        end
    end
end

local msnm = "cbc_missile"
local sendRequest = function()
    while true do
        local controlCenterId = #properties.controlCenterId == 0 and 0 or tonumber(properties.controlCenterId)
        controlCenterId = controlCenterId and controlCenterId or 0
        rednet.send(controlCenterId, {
            name = msnm,
            pw = properties.password,
        }, request_protocol)
        sleep(0.05)
    end
end

local split = function(input, delimiter)
    input = tostring(input)
    delimiter = tostring(delimiter)
    if (delimiter == "") then return false end
    local pos, arr = 0, {}
    for st, sp in function() return string.find(input, delimiter, pos, true) end do
        table.insert(arr, string.sub(input, pos, st - 1))
        pos = sp + 1
    end
    table.insert(arr, string.sub(input, pos))
    return arr
end

local randomNumber = function()
    return math.random(0, 0xFFFFFFFF)
end

local stringToUUID = function(str)
    local timeStamp = os.epoch("local")
    local randomPart1 = randomNumber()
    local randomPart2 = randomNumber()

    return string.format("%08x-%04x-%04x-%04x-%012x",
        timeStamp % 0xFFFFFFFF,
        #str % 0xFFFF,
        randomPart1 % 0xFFFF,
        randomPart2 % 0xFFFF,
        randomPart1 + randomPart2
    )
end
local genCaptcha = function(len)
    local length = len and len or 5
    local result = ""
    for i = 1, length, 1 do
        local num = math.random(0, 2)
        if num == 0 then
            result = result .. string.char(math.random(65, 90))
        elseif num == 1 then
            result = result .. string.char(math.random(97, 122))
        else
            result = result .. string.char(math.random(48, 57))
        end
    end
    return result
end

local gen_uuid = function()
    return stringToUUID(genCaptcha())
end
local genParticle = function(x, y, z)
    commands.execAsync(string.format("particle minecraft:cloud %0.6f %0.6f %0.6f 0 0 0 0 0 force", x, y, z))
end
local block_offset = newVec(0.5, 0.5, 0.5)
local selfPos = newVec(coordinate.getAbsoluteCoordinates())
local getMissileGenPos = function()
    local face_offset = newVec(faces[properties.shot_face]):scale(properties.offset)
    local wPos = newVec(ship.getWorldspacePosition())
    local yardPos = newVec(ship.getShipyardPosition())
    local offset = yardPos:sub(selfPos):sub(block_offset):sub(face_offset)
    offset = quat.vecRot(ship.getQuaternion(), offset)
    return wPos:sub(offset)
end

local flying_missiles = {}
local absMissilEListener = {
    uuid = ""
}

local str_to_vec = function(str)
    if str then
        local n = split(str, ", ")
        local x, y, z = string.sub(n[1], 1, #n[1] - 1), string.sub(n[2], 1, #n[2] - 1), string.sub(n[3], 1, #n[3] - 1)

        return newVec(tonumber(x), tonumber(y), tonumber(z))
    end
end

local normFuze = "{id:\"createbigcannons:timed_fuze\",tag:{FuzeTimer:20},Count:1b}"
local targetPos = newVec()
function absMissilEListener:run()
    local _, data = commands.exec(("data get entity @e[tag=%s, limit=1]"):format(self.uuid))
    local motion = data[1]:match("Motion: %[([^%]]+)%]")
    self.time = self.time + 1
    if motion then
        motion = str_to_vec(motion)
        local pos = str_to_vec(data[1]:match("Pos: %[([^%]]+)%]"))
        
        local speed = properties.speed and properties.speed or 4
        local max_flying_time = properties.max_flying_time and math.abs(properties.max_flying_time) or 2000
        
        local tmp_pos = newVec(pos):add(newVec(motion):norm():scale(4))
        local r_tg = newVec(targetPos):sub(pos)
        tmp_pos:add(newVec(r_tg):norm():scale(speed / 2))
        
        local tg_motion = tmp_pos:sub(pos):norm():scale(speed)
        local tg_cmd = ("data modify entity @e[tag=%s, limit=1]"):format(self.uuid)
        commands.execAsync(("%s Motion set value [%.4fd,%.4fd,%.4fd]"):format(tg_cmd, tg_motion.x, tg_motion.y, tg_motion.z))

        if self.time > max_flying_time or self.time > 5 and r_tg:len() < speed then
            commands.execAsync(("%s Fuze set value {id:\"createbigcannons:timed_fuze\",tag:{FuzeTimer:1},Count:1b}"):format(tg_cmd))
        else
            commands.execAsync(("%s Fuze set value %s"):format(tg_cmd, normFuze))
        end
    else
        --commands.execAsync(("say not found %s, remove it"):format(self.uuid))
        flying_missiles[self.uuid] = nil
    end
end

local genMissileListenerThread = function(uuid)
    return setmetatable({ uuid = uuid, time = 0}, {__index = absMissilEListener})
end

local missile_manager = function ()
    while true do
        local to_run = {}
        for k, v in pairs(flying_missiles) do
            if v.run then
                table.insert(to_run, function() v:run() end)
            end
        end

        if #to_run > 0 then
            parallel.waitForAll(table.unpack(to_run))
        else
            sleep(0.05)
        end
    end
end

local genMissile = function (pos, velocity)
    local uuid = gen_uuid()
    local str_pos = string.format("%0.2f %0.2f %0.2f", pos.x, pos.y, pos.z)
    local fuze = "Fuze:{id:\"createbigcannons:timed_fuze\",tag:{FuzeTimer:60},Count:1b}"
    local out_vec = faces[properties.shot_face]
    out_vec = quat.vecRot(ship.getQuaternion(), out_vec)
    local motion = string.format("Motion:[%.4fd,%.4fd,%.4fd]", out_vec.x, out_vec.y, out_vec.z)
    local str = ("summon createbigcannons:he_shell %s {Tags:[%s],NoGravity:1b,%s,%s}"):format(str_pos, uuid, motion, fuze)
    commands.execAsync(str)
    flying_missiles[uuid] = genMissileListenerThread(uuid)
end

local run_missile = function ()
    local shot_ct = 0
    while true do
        if ct > 0 and controlCenter.omega then
            targetPos = newVec(controlCenter.tgPos):add(newVec(controlCenter.velocity):scale(2))
            ct = ct - 1
            if controlCenter.missile then
                if shot_ct < 1 then
                    --commands.execAsync(("say %d"):format(controlCenter.pos.x))
                    local ppos = getMissileGenPos()

                    genMissile(ppos, newVec(controlCenter.center_velocity):scale(0.05))
                    --genParticle(ppos.x, ppos.y, ppos.z)
                    shot_ct = properties.shot_ct
                end
            else
                shot_ct = shot_ct > 0 and shot_ct - 1 or 0
            end
        else
            controlCenter.missile = false
        end
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
        offset = newTextField(properties, "offset", 12, 5),
        speed = newTextField(properties, "speed", 12, 7),
        shot_ct = newTextField(properties, "shot_ct", 12, 9),
        max_flying_time = newTextField(properties, "max_flying_time", 20, 11),
        password = newTextField(properties, "password", 12, 13),
        controlCenterId = newTextField(properties, "controlCenterId", 19, 15)
    }
    fieldTb.controlCenterId.len = 5
    fieldTb.password.len = 14
    fieldTb.offset.len = 5
    fieldTb.speed.len = 5
    fieldTb.shot_ct.len = 5
    fieldTb.max_flying_time.len = 10
    local selectBoxTb = {
        shot_face = newSelectBox(properties, "shot_face", 1, 12, 3, "up", "down", "north", "south", "west", "east"),
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

                term.setCursorPos(2, 3)
                term.write("SHOT_ON: ")
                term.setCursorPos(2, 5)
                term.write("OFFSET: ")
                term.setCursorPos(2, 7)
                term.write("SPEED: ")
                term.setCursorPos(2, 9)
                term.write("SHOT_CT: ")
                term.setCursorPos(2, 11)
                term.write("MAX_FLYING_TIME: ")

                term.setCursorPos(2, 13)
                term.write("Password: ")
                term.setCursorPos(2, 15)
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
            end
        end
    end
end

parallel.waitForAll(run_missile, runTerm, listener, sendRequest, missile_manager)
