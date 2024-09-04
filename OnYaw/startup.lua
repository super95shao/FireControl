local gear = peripheral.find("Create_RotationSpeedController")
local protocol = "CBCNetWork"
peripheral.find("modem", rednet.open)

local genStr = function(s, count)
    local result = ""
    for i = 1, count, 1 do
        result = result .. s
    end
    return result
end

local system, properties, parentId
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
    parentId = tonumber(properties.parentId)
end

system.reset = function()
    return {
        parentId = "-1",
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

gear.setTargetSpeed(0)

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

function termUtil:init()
    self.fieldTb = {
        password = newTextField(properties, "parentId", 12, 3),
    }

    termUtil:refresh()
end

function termUtil:refresh()
    term.clear()
    term.setCursorPos(2, 3)
    term.write("parentId: ")
    for k, v in pairs(self.fieldTb) do
        v:paint()
    end
end

local id, msg
local run = function ()
    while true do
        repeat
            id, msg = rednet.receive(protocol)
        until id == parentId
        if msg ~= msg then
            msg = 0
        end
        gear.setTargetSpeed(msg)
        if parentId then
            rednet.send(parentId, ship.getQuaternion(), protocol)
        end
    end
end

local listener = function ()
    while true do
        local eventData = { os.pullEvent() }
        local event = eventData[1]

        if event == "mouse_click" or event == "key" or event == "char" then
            if event == "mouse_click" then
                term.setCursorBlink(true)
                local x, y = eventData[3], eventData[4]
                for k, v in pairs(termUtil.fieldTb) do --点击了输入框
                    if y == v.y and x >= v.x and x <= v.x + v.len then
                        v:click(x, y)
                    end
                end
            elseif event == "key" then
                local key = eventData[2]
                for k, v in pairs(termUtil.fieldTb) do
                    if termUtil.cpY == v.y and termUtil.cpX >= v.x and termUtil.cpX <= v.x + v.len then
                        v:inputKey(key)
                    end
                end
            elseif event == "char" then
                local char = eventData[2]
                for k, v in pairs(termUtil.fieldTb) do
                    if termUtil.cpY == v.y and termUtil.cpX >= v.x and termUtil.cpX <= v.x + v.len then
                        v:inputChar(char)
                    end
                end
            end

            --刷新数据到properties
            system.updatePersistentData()
            termUtil:refresh()
            parentId = tonumber(properties.parentId)

            term.setCursorPos(termUtil.cpX, termUtil.cpY)
        end
    end
end

system.init()
termUtil:init()
parallel.waitForAll(run, listener)
