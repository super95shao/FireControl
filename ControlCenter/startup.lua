local goggle_link_port = peripheral.find("goggle_link_port")

local system, properties, linkedCannons, scanner, rayCaster
local linkedgoggles = {}
local modList = {"HMS", "POINT", "SHIP", "PLAYER", "MONSTER", "ENTITY"}
local protocol, request_protocol = "CBCNetWork", "CBCcenter"
local group = {}
for i = 1, 10, 1 do
    group[i] = {
        name = "group" .. i,
        mode = 2,
        pos = {
            x = 0,
            y = 0,
            z = 0
        },
        HmsUser = nil,
        HmsMode = 1,
        radarTargets = {},
        fire = false,
        fireCd = 0,
        autoFire = false,
        autoSelect = false,
    }
end

local tm_monitors = {
    list = {}
}

linkedCannons = {}

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
        password = "123456",
        raycastRange = 256,
        selectColor = 0x50B358,
        targetColor = 0xFF0000,
        fontColor = 0xFFFFFF,
        bgColor = 0x000000,
        lockColor = 0x666666,
        face = "south",
        maxSelectRange = "480",
        whiteList = {}
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

local quatMultiply = function(q1, q2)
    local newQuat = {}
    newQuat.w = -q1.x * q2.x - q1.y * q2.y - q1.z * q2.z + q1.w * q2.w
    newQuat.x = q1.x * q2.w + q1.y * q2.z - q1.z * q2.y + q1.w * q2.x
    newQuat.y = -q1.x * q2.z + q1.y * q2.w + q1.z * q2.x + q1.w * q2.y
    newQuat.z = q1.x * q2.y - q1.y * q2.x + q1.z * q2.w + q1.w * q2.z
    return newQuat
end

local genParticle = function(x, y, z)
    commands.execAsync(string.format("particle electric_spark %0.6f %0.6f %0.6f 0 0 0 0 0 force", x, y, z))
end

function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
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

local genStr = function(s, count)
    local result = ""
    for i = 1, count, 1 do
        result = result .. s
    end
    return result
end

rayCaster = {
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

        rayCaster.block = coordinate.getBlock(vec.x - 1, vec.y, vec.z - 1)
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

scanner = {
    commander = {},
    playerList = {},
    entities = {},
    preEntities = {},
    vsShips = {},
    monsters = {},
    MONSTER = {"minecraft:zombie", "minecraft:spider", "minecraft:creeper", "minecraft:cave_spider", "minecraft:husk",
               "minecraft:skeleton", "minecraft:wither_skeleton", "minecraft:guardian", "minecraft:phantom",
               "minecraft:pillager", "minecraft:ravager", "minecraft:vex", "minecraft:warden", "minecraft:vindicator",
               "minecraft:witch", "minecraft:ender_dragon", "minecraft:wither"}
}

scanner.getShips = function()
    if not coordinate then
        return
    end
    local ships = coordinate.getShips(2500)

    local flagEmpty = true
    for k, v in pairs(ships) do
        flagEmpty = false
        break
    end

    if flagEmpty then
        ships = coordinate.getShipsAll(2500)
    end

    for k, v in pairs(scanner.vsShips) do
        v.flag = false
    end

    for k, v in pairs(ships) do
        if scanner.vsShips[v.slug] then
            v.velocity = {
                x = v.x - scanner.vsShips[v.slug].x,
                y = v.y - scanner.vsShips[v.slug].y,
                z = v.z - scanner.vsShips[v.slug].z
            }
        else
            v.velocity = {
                x = 0,
                y = 0,
                z = 0
            }
        end
        v.flag = true
        scanner.vsShips[v.slug] = v
    end

    for k, v in pairs(scanner.vsShips) do
        if not v.flag then
            scanner.vsShips[k] = nil
        end
    end
end

scanner.scanEntity = function()
    if not coordinate then
        return
    end
    local ett = coordinate.getEntities(-1)
    local flagEmpty = true
    for k, v in pairs(ett) do
        flagEmpty = false
        break
    end

    if flagEmpty then
        ett = coordinate.getEntitiesAll(-1)
    end

    scanner.entities = ett
    if ett ~= nil then
        for k, v in pairs(scanner.playerList) do
            v.flag = false
        end
        for k, v in pairs(scanner.monsters) do
            v.flag = false
        end

        for k, v in pairs(ett) do
            if scanner.preEntities[v.uuid] then
                v.velocity = {
                    x = v.x - scanner.preEntities[v.uuid].x,
                    y = v.y - scanner.preEntities[v.uuid].y,
                    z = v.z - scanner.preEntities[v.uuid].z
                }
            else
                v.velocity = {
                    x = 0,
                    y = 0,
                    z = 0
                }
            end
            if v.isPlayer then
                v.flag = true
                scanner.playerList[v.uuid] = v
            else
                for _, v2 in pairs(scanner.MONSTER) do
                    if v.type == v2 then
                        v.flag = true
                        scanner.monsters[v.uuid] = v
                        break
                    end
                end
            end
        end

        for k, v in pairs(scanner.playerList) do
            if not v.flag then
                scanner.playerList[k] = nil
            end
        end
        for k, v in pairs(scanner.monsters) do
            if not v.flag then
                scanner.monsters[k] = nil
            end
        end
        scanner.preEntities = {}
        for k, v in pairs(ett) do
            scanner.preEntities[v.uuid] = v
        end
    end
end

scanner.run = function()
    while true do
        scanner.getShips()
        scanner.scanEntity()

        for k, v in pairs(tm_monitors.list) do -- 刷新所有处于雷达界面的窗口
            for k2, v2 in pairs(v.windows) do
                if group[v2.group.index].mode > 2 then
                    v2:refresh()
                    v.gpu.sync()
                end
            end
        end

        for _, g in pairs(group) do
            if g.fireCd > 0 then
                g.fireCd = g.fireCd - 1
                if g.fireCd == 1 then
                    g.fire = false
                end
            elseif g.fireCd < 1 then
                if g.autoFire then
                    g.fire = true
                    g.fireCd = 20
                else
                    g.fire = false
                end
            end
        end

        local onVsShip = ship
        local selfPos = onVsShip and ship.getWorldspacePosition() or coordinate.getAbsoluteCoordinates()
    
        for k, v in pairs(group) do
            local kk1
            if v.mode == 3 then kk1 = "vsShips"
            elseif v.mode == 4 then kk1 = "playerList"
            elseif v.mode == 5 then kk1 = "monsters"
            elseif v.mode == 6 then kk1 = "entities"
            end

            local kk2 = kk1 == "vsShips" and "slug" or "uuid"
            if v.autoSelect and kk1 then
                v.radarTargets = {}
                for k2, v2 in pairs(scanner[kk1]) do
                    local contains = false
                    for v3, v3 in pairs(properties.whiteList) do
                        if v3 == v2[kk2] then
                            contains = true
                            break
                        end
                    end

                    if not contains then
                        local posV = {
                            x = v2.x - selfPos.x,
                            y = v2.y - selfPos.y,
                            z = v2.z - selfPos.z,
                        }
                        v2.dis = math.sqrt(posV.x ^ 2 + posV.y ^ 2 + posV.z ^ 2)
                        table.insert(v.radarTargets, v2)
                    end
                end

                table.sort(v.radarTargets, function(a, b) return a.dis < b.dis end)
                local len = 0
                for _, ca in pairs(linkedCannons) do
                    if ca.group and group[ca.group].name == v.name then
                        len = len + 1
                    end
                end

                local range = #properties.maxSelectRange == 0 and 0 or tonumber(properties.maxSelectRange)
                range = range and range or 450
                local newList = {}
                for i = 1, len, 1 do
                    if v.radarTargets[i] and v.radarTargets[i].dis < range then
                        table.insert(newList, v.radarTargets[i])
                    else
                        break
                    end
                end

                v.radarTargets = newList
                if #newList ~= 0 then
                    local index = 1
                    for _, ca in pairs(linkedCannons) do
                        if ca.group and group[ca.group].name == v.name then
                            local iIndex = index % #newList + 1
                            rednet.send(ca.id, {
                                tgPos = v.radarTargets[iIndex],
                                velocity = v.radarTargets[iIndex].velocity,
                                mode = group[ca.group].mode,
                                fire = group[ca.group].fire
                            }, protocol)
                            index = index + 1
                        end
                    end
                end
            else
                if scanner[kk1] and v.radarTargets[1] then
                    for k2, v2 in pairs(scanner[kk1]) do
                        if v2[kk2] == v.radarTargets[1][kk2] then
                            v.radarTargets[1] = v2
                            break
                        end
                    end
                
                    for _, ca in pairs(linkedCannons) do
                        if ca.group and group[ca.group].name == v.name then
                            rednet.send(ca.id, {
                                tgPos = v.radarTargets[1],
                                velocity = v.radarTargets[1].velocity,
                                mode = group[ca.group].mode,
                                fire = group[ca.group].fire
                            }, protocol)
                        end
                    end
                end
            end
        end

        sleep(0.05)
    end
end

local absTextSelectBox = {
    index = 1,
    draww = nil,
    list = nil,
    x = 1,
    y = 1,
    mode = "index",
    width = 64,
    height = 8,
    page = 1
}

function absTextSelectBox:click(x, y, button)
    local index = (self.page - 1) * 6
    if y < 7 * 8 then
        if self.mode == "index" then
            local gIndex = math.floor(y / 8) + index
            if gIndex > 0 and gIndex <= #self.list then
                self.group.index = math.floor(y / 8) + index
            end
        elseif self.mode == "switch" then
            local gIndex = math.floor(y / 8) + index
            if gIndex > 0 and gIndex <= #self.list then
                if self.list[gIndex].group == nil then
                    self.list[gIndex].group = self.group.index
                elseif self.list[gIndex].group == self.group.index then
                    self.list[gIndex].group = nil
                end
            end
        end
    else
        self.page = self.page + 1
        self.page = self.page > #self.list / 6 + 1 and 1 or self.page
    end
end

function absTextSelectBox:refresh()
    self.drawW.fill()
    self.drawW.drawText(3, 1, self.name)
    local index = 1 + (self.page - 1) * 6
    for i = index, #self.list, 1 do
        if i >= index + 6 then
            break
        end
        local str = self.list[i].name
        if #str > 10 then
            str = string.sub(str, 1, 10)
        elseif #str < 10 then
            for j = 1, 10 - #str, 1 do
                str = str .. " "
            end
        end
        if self.mode == "index" then
            if i == self.group.index then
                self.drawW.drawText(3, (i + 1 - index) * 8 + 1, str, properties.bgColor, properties.selectColor, 1)
            else
                self.drawW.drawText(3, (i + 1 - index) * 8 + 1, str, properties.bgColor, properties.fontColor, 1)
            end
        elseif self.mode == "switch" then
            if self.list[i].group == self.group.index then
                self.drawW.drawText(3, (i + 1 - index) * 8 + 1, str, properties.bgColor, properties.selectColor, 1)
            elseif self.list[i].group == nil then
                self.drawW.drawText(3, (i + 1 - index) * 8 + 1, str, properties.bgColor, properties.fontColor, 1)
            else
                self.drawW.drawText(3, (i + 1 - index) * 8 + 1, str, properties.lockColor, properties.bgColor, 1)
            end
        end
    end

    if #self.list > 5 then
        self.drawW.drawText(3, 56, "    v     ", properties.bgColor, properties.fontColor)
    end
    self.drawW.sync()
end

local absModeSwitchBox = {}

function absModeSwitchBox:refresh()
    self.drawW.fill()

    self.drawW.drawText(1, 1, "   <              >")
    local str = modList[group[self.group.index].mode]
    self.drawW.drawText(math.floor(64 - (#str / 2) * 6), 1, str)
    self.drawW.sync()
end

function absModeSwitchBox:click(x, y, button)
    local result = 0
    if x < 64 then
        result = -1
    else
        result = 1
    end

    group[self.group.index].mode = group[self.group.index].mode + result
    group[self.group.index].mode = group[self.group.index].mode > #modList and 1 or group[self.group.index].mode
    group[self.group.index].mode = group[self.group.index].mode < 1 and #modList or group[self.group.index].mode
end

local absCoordInputWindow = {
    tmpPos = {
        x = "0",
        y = "0",
        z = "0"
    }
}

function absCoordInputWindow:refresh()
    self.drawW.fill()
    self.tmpPos = {
        x = tostring(math.abs(group[self.group.index].pos.x)),
        y = tostring(math.abs(group[self.group.index].pos.y)),
        z = tostring(math.abs(group[self.group.index].pos.z))
    }

    for k, v in pairs(self.tmpPos) do
        if #v < 8 then
            for i = 1, 8 - #v, 1 do
                self.tmpPos[k] = "0" .. self.tmpPos[k]
            end
        end
    end

    if group[self.group.index].pos.x > 0 then
        self.drawW.drawText(26, 24, "x: +")
    else
        self.drawW.drawText(26, 24, "x: -")
    end

    self.drawW.drawText(46, 16, "++++++++", 0x666666, 0x000000)
    self.drawW.drawText(46, 24, self.tmpPos.x, 0x000000, 0xFFFFFF)
    self.drawW.drawText(46, 32, "--------", 0x666666, 0x000000)

    if group[self.group.index].pos.y > 0 then
        self.drawW.drawText(26, 56, "y: +")
    else
        self.drawW.drawText(26, 56, "y: -")
    end
    self.drawW.drawText(46, 48, "++++++++", 0x666666, 0x000000)
    self.drawW.drawText(46, 56, self.tmpPos.y, 0x000000, 0xFFFFFF)
    self.drawW.drawText(46, 64, "--------", 0x666666, 0x000000)

    if group[self.group.index].pos.z > 0 then
        self.drawW.drawText(26, 88, "z: +")
    else
        self.drawW.drawText(26, 88, "z: -")
    end

    self.drawW.drawText(46, 80, "++++++++", 0x666666, 0x000000)
    self.drawW.drawText(46, 88, self.tmpPos.z, 0x000000, 0xFFFFFF)
    self.drawW.drawText(46, 96, "++++++++", 0x666666, 0x000000)
    self.drawW.sync()
end

function absCoordInputWindow:click(x, y, button)
    if x > 36 and x < 94 then
        local index = math.floor((x - 46) / 6 + 1)
        index = index > 8 and 8 or index < 1 and 1 or index
        if y >= 16 and y < 40 then
            if x > 45 then
                local n = tonumber(string.sub(self.tmpPos.x, index, index))
                if y < 24 then
                    n = n + 1 > 9 and 0 or n + 1
                elseif y >= 32 then
                    n = n - 1 < 0 and 9 or n - 1
                end

                local result = string.sub(self.tmpPos.x, 1, index - 1) .. n .. string.sub(self.tmpPos.x, index + 1, 8)
                if group[self.group.index].pos.x < 0 then
                    result = "-" .. result
                end
                group[self.group.index].pos.x = tonumber(result)
            else
                group[self.group.index].pos.x = -group[self.group.index].pos.x
            end
        elseif y >= 48 and y < 72 then
            if x > 45 then
                local n = tonumber(string.sub(self.tmpPos.y, index, index))
                if y < 56 then
                    n = n + 1 > 9 and 0 or n + 1
                elseif y >= 64 then
                    n = n - 1 < 0 and 9 or n - 1
                end
                local result = string.sub(self.tmpPos.y, 1, index - 1) .. n .. string.sub(self.tmpPos.y, index + 1, 8)
                if group[self.group.index].pos.y < 0 then
                    result = "-" .. result
                end
                group[self.group.index].pos.y = tonumber(result)
            else
                group[self.group.index].pos.y = -group[self.group.index].pos.y
            end
        elseif y >= 80 and y < 104 then
            if x > 45 then
                local n = tonumber(string.sub(self.tmpPos.z, index, index))
                if y < 88 then
                    n = n + 1 > 9 and 0 or n + 1
                elseif y >= 96 then
                    n = n - 1 < 0 and 9 or n - 1
                end
                local result = string.sub(self.tmpPos.z, 1, index - 1) .. n .. string.sub(self.tmpPos.z, index + 1, 8)
                if group[self.group.index].pos.z < 0 then
                    result = "-" .. result
                end
                group[self.group.index].pos.z = tonumber(result)
            else
                group[self.group.index].pos.z = -group[self.group.index].pos.z
            end
        end
    end
end

local absHmsSelectWindow = {
    xStart = 25,
    yStart = 9
}

function absHmsSelectWindow:refresh()
    self.drawW.fill()
    local col1 = group[self.group.index].HmsMode == 1 and properties.selectColor or properties.fontColor
    local col2 = group[self.group.index].HmsMode == 2 and properties.selectColor or properties.fontColor

    self.drawW.drawText(13, 99, "Metaphy..", properties.bgColor, col1)
    self.drawW.drawText(73, 99, "Goggle...", properties.bgColor, col2)

    local index = 1
    local tgtb
    if group[self.group.index].HmsMode == 1 then
        tgtb = scanner.playerList
    else
        tgtb = linkedgoggles
    end

    for k, v in pairs(tgtb) do
        if index > 10 then
            break
        end

        local tgName, str
        if v.info then
            local infos = v.info
            if infos.is_player then
                str = infos.nickname
                tgName = infos.nickname
            else
                str = infos.entity_type
                tgName = infos.entity_type
            end
        else
            str = v.name
            tgName = v.name
        end

        if #str > 12 then
            str = string.sub(str, 1, 12)
        elseif #str < 12 then
            for j = 1, 12 - #str, 1 do
                str = str .. " "
            end
        end

        if group[self.group.index].HmsUser == tgName then
            self.drawW.drawText(self.xStart, self.yStart + (index - 1) * 8 + 1, str, properties.bgColor,
                properties.selectColor)
        else
            self.drawW.drawText(self.xStart, self.yStart + (index - 1) * 8 + 1, str, properties.bgColor,
                properties.fontColor)
        end

        index = index + 1
    end
    self.drawW.sync()
end

function absHmsSelectWindow:click(x, y, button)
    if y > 97 and y < 106 then
        if x > 12 and x < 58 then
            group[self.group.index].HmsMode = 1
        elseif x > 72 and x < 116 then
            group[self.group.index].HmsMode = 2
        end
    elseif y >= self.yStart and (x >= self.xStart and x < self.xStart + 72) then
        local index = math.floor((y - self.yStart) / 8 + 1)
        local tgtb
        if group[self.group.index].HmsMode == 1 then
            tgtb = scanner.playerList
        else
            tgtb = linkedgoggles
        end
        local i2, flag = 1, false
        for k, v in pairs(tgtb) do
            if i2 == index then
                group[self.group.index].HmsUser = v.name
                flag = true
                break
            end
            i2 = i2 + 1
        end
        if not flag then
            group[self.group.index].HmsUser = nil
        end
    else
        group[self.group.index].HmsUser = nil
    end
end

local absRadarButtons = {
    range = 128
}

function absRadarButtons:refreshRadar()
    self.drawW.rectangle(1, 1, 128, 120, 0x666666)
    self.drawW.line(64, 2, 64, 110, 0x666666)
    self.drawW.line(1, 56, 128, 56, 0x666666)
    local onVsShip = ship
    local selfPos = onVsShip and ship.getWorldspacePosition() or coordinate.getAbsoluteCoordinates()

    local quat = {}
    if onVsShip then
        quat = quatMultiply(quatList[properties.face], getConjQuat(ship.getQuaternion()))
    else
        quat = quatList[properties.face]
    end

    local scale = self.range / 64
    for k, v in pairs(self.tgTb[self.tgK]) do
        local tmpPos = {
            x = v.x - selfPos.x,
            y = v.y - selfPos.y,
            z = v.z - selfPos.z
        }
        
        tmpPos = RotateVectorByQuat(quat, tmpPos)

        local x, y = 64 - tmpPos.x / scale, 56 - tmpPos.z / scale
        if (x > 2 and x < 127) and (y > 2 and y < 111) then
            local yDis = 128 + tmpPos.y * 2
            yDis = yDis < 6 and 6 or yDis > 255 and 255 or yDis
            local yColor = tonumber(string.format("%x%xFF", yDis, yDis), 16)

            local kkey = group[self.group.index].mode == 3 and "slug" or "uuid"

            local contains = false
            local wl = false
            for k2, v2 in pairs(properties.whiteList) do
                if v2 == v[kkey] then
                    wl = true
                    break
                end
            end

            if not wl then
                for k2, v2 in pairs(group[self.group.index].radarTargets) do
                    if v2[kkey] == v[kkey] then
                        contains = true
                        break
                    end
                end
            end
            
            if wl then
                self.drawW.filledRectangle(x, y, 3, 3, 0x66FF66)
            elseif contains then
                self.drawW.filledRectangle(x - 1, y - 1, 5, 5, properties.targetColor)
            else
                self.drawW.filledRectangle(x, y, 2, 2, yColor)
            end
        end
    end

    local fireColor = group[self.group.index].fire and 0xFF0000 or 0x444444
    local autoColor = group[self.group.index].autoFire and 0x50B358 or 0xFF0000
    self.drawW.line(2, 2, 2, 2, autoColor)
    self.drawW.rectangle(4, 4, 5, 5, fireColor)
    self.drawW.line(6, 3, 6, 9, fireColor)
    self.drawW.line(3, 6, 9, 6, fireColor)
    if group[self.group.index].autoSelect then
        self.drawW.drawText(12, 3, "A", 0xFF0000)
    else
        self.drawW.drawText(12, 3, "N", 0x444444)
    end

    self.drawW.drawText(103, 112, tostring(self.range), 0xFFFFFF)
    self.drawW.filledRectangle(3, 112, 99, 8, 0x444444)
    local tmpx = math.floor(self.range / 25.958333333) + 3
    tmpx = tmpx < 3 and 3 or tmpx
    self.drawW.filledRectangle(tmpx, 113, 3, 6, 0xFFFFFF)
end

function absRadarButtons:RadarClick(x, y, button)
    if y <= 110 then
        if x < 18 and y < 9 then
            if x <= 4 and y <= 3 then
                group[self.group.index].autoFire = not group[self.group.index].autoFire
            end
            if x < 10 then
                group[self.group.index].fire = true
                group[self.group.index].fireCd = 20
            else
                group[self.group.index].autoSelect = not group[self.group.index].autoSelect
                if not group[self.group.index].autoSelect then
                    group[self.group.index].radarTargets = {}
                end
            end
        else
            local onVsShip = ship
            local selfPos = onVsShip and ship.getWorldspacePosition() or coordinate.getAbsoluteCoordinates()

            local quat, tgName = {}, ""
            if onVsShip then
                quat = quatMultiply(quatList[properties.face], getConjQuat(ship.getQuaternion()))
                tgName = ship.getName()
            else
                quat = quatList[properties.face]
            end
            local scale = self.range / 64
            local minDis = 128

            if button == 1 or not group[self.group.index].autoSelect then
                local target
                for k, v in pairs(self.tgTb[self.tgK]) do
                    local tmpPos = {
                        x = v.x - selfPos.x,
                        y = v.y - selfPos.y,
                        z = v.z - selfPos.z
                    }
                    tmpPos = RotateVectorByQuat(quat, tmpPos)
                    local px, py = 64 - tmpPos.x / scale, 56 - tmpPos.z / scale
                    v.clickDis = math.abs(x - px) + math.abs(y - py)
                    if group[self.group.index].mode > 2 then
                        if v.clickDis < minDis then
                            minDis = v.clickDis
                            target = v
                        end
                    end
                end
    
                local kk1 = group[self.group.index].mode == 3 and "slug" or "uuid"

                if button == 1 then
                    local val = target[kk1]
                    local inWl = false
                    local iii = 0
                    for i = 1, #properties.whiteList, 1 do
                        iii = i
                        if properties.whiteList[i] == val then
                            inWl = true
                            break
                        end
                    end

                    if inWl then
                        table.remove(properties.whiteList, iii)
                    else
                        table.insert(properties.whiteList, val)
                    end
                else
                    group[self.group.index].radarTargets[1] = target
                end

                for k, v in pairs(properties.whiteList) do
                    if group[self.group.index].radarTargets[1] and v == group[self.group.index].radarTargets[1][kk1] then
                        group[self.group.index].radarTargets[1] = nil
                        break
                    end
                end
    
                if group[self.group.index].radarTargets[1] and group[self.group.index].radarTargets[1].clickDis > 5 then
                    group[self.group.index].radarTargets[1] = nil
                end
            end
        end
    elseif y > 110 and x <= 100 then
        self.range = math.floor((x - 3) * 25.958333333 + 0.5)
        self.range = self.range < 8 and 8 or self.range
    end
end

local absShipRadarWindow = setmetatable({}, {
    __index = absRadarButtons
})

function absShipRadarWindow:refresh()
    self.drawW.fill()
    self:refreshRadar()
    self.drawW.sync()
end

function absShipRadarWindow:click(x, y, button)
    self:RadarClick(x, y, button)
end

local absWindow = {}

function absWindow:init()
    self.windows = {}
    self.windows.groupList = setmetatable({
        list = group,
        mode = "index",
        name = "  GROUP",
        drawW = self.drawW.createWindow(1, 1, 64, 64),
        group = self.group
    }, {
        __index = absTextSelectBox
    })
    self.windows.cannonList = setmetatable({
        list = linkedCannons,
        mode = "switch",
        name = "  CANNON",
        drawW = self.drawW.createWindow(1, 65, 64, 64),
        group = self.group
    }, {
        __index = absTextSelectBox
    })
    self.windows.modeSwitch = setmetatable({
        drawW = self.drawW.createWindow(65, 1, 128, 8),
        group = self.group
    }, {
        __index = absModeSwitchBox
    })
    self.windows.pointInput = setmetatable({
        drawW = self.drawW.createWindow(65, 8, 128, 120),
        group = self.group
    }, {
        __index = absCoordInputWindow
    })
    self.windows.hmsWindow = setmetatable({
        drawW = self.drawW.createWindow(65, 8, 128, 120),
        group = self.group
    }, {
        __index = absHmsSelectWindow
    })
    self.windows.shipRadar = setmetatable({
        drawW = self.drawW.createWindow(65, 8, 128, 120),
        group = self.group,
        tgTb = scanner,
        tgK = "vsShips"
    }, {
        __index = absShipRadarWindow
    })
    self.windows.antiairRadar = setmetatable({
        drawW = self.drawW.createWindow(65, 8, 128, 120),
        group = self.group,
        tgTb = scanner,
        tgK = "vsShips"
    }, {
        __index = absShipRadarWindow
    })
    self.windows.playerRadar = setmetatable({
        drawW = self.drawW.createWindow(65, 8, 128, 120),
        group = self.group,
        tgTb = scanner,
        tgK = "playerList"
    }, {
        __index = absShipRadarWindow
    })
    self.windows.monsterRadar = setmetatable({
        drawW = self.drawW.createWindow(65, 8, 128, 120),
        group = self.group,
        tgTb = scanner,
        tgK = "monsters"
    }, {
        __index = absShipRadarWindow
    })
    self.windows.entitiesRadar = setmetatable({
        drawW = self.drawW.createWindow(65, 8, 128, 120),
        group = self.group,
        tgTb = scanner,
        tgK = "entities"
    }, {
        __index = absShipRadarWindow
    })

    self:refresh()
end

function absWindow:click(x, y, button)
    if x <= 64 then
        if y <= 64 then
            self.windows.groupList:click(x, y, button)
        else
            self.windows.cannonList:click(x, y - 64, button)
        end
    else
        if y <= 8 then
            self.windows.modeSwitch:click(x - 64, y, button)
        else
            if modList[group[self.group.index].mode] == "POINT" then
                self.windows.pointInput:click(x - 64, y - 8, button)
            elseif modList[group[self.group.index].mode] == "HMS" then
                self.windows.hmsWindow:click(x - 64, y - 8, button)
            elseif modList[group[self.group.index].mode] == "SHIP" then
                self.windows.shipRadar:click(x - 64, y - 8, button)
            elseif modList[group[self.group.index].mode] == "ANTIAIRCRAFT" then
                self.windows.antiairRadar:click(x - 64, y - 8, button)
            elseif modList[group[self.group.index].mode] == "PLAYER" then
                self.windows.playerRadar:click(x - 64, y - 8, button)
            elseif modList[group[self.group.index].mode] == "MONSTER" then
                self.windows.monsterRadar:click(x - 64, y - 8, button)
            elseif modList[group[self.group.index].mode] == "ENTITY" then
                self.windows.entitiesRadar:click(x - 64, y - 8, button)
            end
        end
    end
end

function absWindow:refresh()
    self.windows.groupList:refresh()
    self.windows.cannonList:refresh()
    self.windows.modeSwitch:refresh()
    if modList[group[self.group.index].mode] == "POINT" then
        self.windows.pointInput:refresh()
    elseif modList[group[self.group.index].mode] == "HMS" then
        self.windows.hmsWindow:refresh()
    elseif modList[group[self.group.index].mode] == "SHIP" then
        self.windows.shipRadar:refresh()
    elseif modList[group[self.group.index].mode] == "ANTIAIRCRAFT" then
        self.windows.antiairRadar:refresh()
    elseif modList[group[self.group.index].mode] == "PLAYER" then
        self.windows.playerRadar:refresh()
    elseif modList[group[self.group.index].mode] == "MONSTER" then
        self.windows.monsterRadar:refresh()
    elseif modList[group[self.group.index].mode] == "ENTITY" then
        self.windows.entitiesRadar:refresh()
    end
    self.drawW.sync()
end

local absGpu = {
    gpu = nil,
    windows = nil
}

function absGpu:init()
    self.gpu.refreshSize()
    self.gpu.setSize(64)
    self.gpu.fill()
    self.gpu.sync()
    self.w, self.h = self.gpu.getSize()
    self.windows = {}
    for i = 1, self.w / 192, 1 do
        for j = 1, self.h / 128, 1 do
            local x, y = (i - 1) * 192 + 1, (j - 1) * 128 + 1
            local subWin = setmetatable({
                x = x,
                y = y,
                drawW = self.gpu.createWindow(x, y, 192, 128),
                group = {
                    index = 1
                }
            }, {
                __index = absWindow
            })
            subWin:init()
            table.insert(self.windows, subWin)
        end
    end

    self.gpu.sync()
end

function absGpu:click(x, y, button)
    for k, v in pairs(self.windows) do
        if (x >= v.x and x <= v.x + 192) and (y >= v.y and y <= v.y + 128) then
            v:click(x + 1 - v.x, y + 1 - v.y, button)
        end
    end

    self.gpu.sync()
end

function absGpu:scroll(x, y, d)
end

function absGpu:move(x, y)
    local g = self.gpu
    g.fill()
    for k, v in pairs(self.windows) do
        v.drawW.sync()
    end
    local w = self.brush
    g.filledRectangle(x, y, 1, 1, 0xFFFFFF)
    g.sync()
end

function absGpu:refresh()
    for k, v in pairs(self.windows) do
        v:refresh()
    end
    self.gpu.sync()
end

function tm_monitors:getGpus()
    local ps = {peripheral.find("tm_gpu")}
    for k, v in pairs(ps) do
        self.list[peripheral.getName(v)] = setmetatable({
            gpu = v
        }, {
            __index = absGpu
        })
    end
end

function tm_monitors:init()
    for k, v in pairs(self.list) do
        v:init()
    end
end

function tm_monitors:refresh()
    for k, v in pairs(self.list) do
        v:refresh()
    end
end

local emptyTb = {}
local getGoggles = function()
    while true do
        local dis = properties.raycastRange

        if goggle_link_port then
            local connect = goggle_link_port.getConnected()

            for k, v in pairs(connect) do
                local infos = v.getInfo()
                if infos.is_player then
                    v.info = infos
                    v.name = infos.nickname
                    linkedgoggles[k] = v
                else
                    linkedgoggles[k] = nil
                end
            end

        else
            linkedgoggles = emptyTb
        end

        local flag = false
        for k, v in pairs(group) do -- 如果没有组在头瞄模式，不开启raycast
            if modList[v.mode] == "HMS" then
                flag = true
                break
            end
        end

        if flag then
            for k, v in pairs(scanner.playerList) do
                for _, ca in pairs(linkedCannons) do
                    if ca.group then
                        if group[ca.group].mode == 1 and group[ca.group].HmsMode == 1 and group[ca.group].HmsUser ==
                            v.name then
                            if not v.targetPos then
                                v.y = v.y + 1.75
                                v.targetPos = rayCaster.run(v, {
                                    x = v.raw_euler_x,
                                    y = v.raw_euler_y,
                                    z = v.raw_euler_z
                                }, dis, false)
                            end

                            rednet.send(ca.id, {
                                tgPos = v.targetPos,
                                velocity = {
                                    x = 0,
                                    y = 0,
                                    z = 0
                                },
                                mode = 1,
                                fire = group[ca.group].fire
                            }, protocol)
                        end
                    end
                end
                v.targetPos = nil
            end
        end

        if flag then
            local index = 0
            for k, v in pairs(linkedgoggles) do
                local flag3 = false
                for k2, v2 in pairs(group) do
                    if v2.HmsUser == v.name then -- 只有选择头瞄了玩家，才开启raycast
                        flag3 = true
                        break
                    end
                end

                if flag3 then
                    index = index + 1
                    local target = v.raycast(dis)
                    local hitpos = target.hit_pos
                    v.targetPos = {
                        x = 0,
                        y = 0,
                        z = 0
                    }
                    if hitpos then
                        v.targetPos.x = hitpos[1]
                        v.targetPos.y = hitpos[2]
                        v.targetPos.z = hitpos[3]
                    else
                        local infos = v.getInfo()
                        local xRot = math.rad(infos.xRot)
                        local yRot = math.rad(infos.yHeadRot)
                        local cosH = math.cos(xRot)
                        v.targetPos.x = infos.eye_pos[1] - dis * math.sin(yRot) * cosH
                        v.targetPos.z = infos.eye_pos[3] + dis * math.cos(yRot) * cosH
                        v.targetPos.y = infos.eye_pos[2] - dis * math.sin(xRot)
                    end

                    for _, ca in pairs(linkedCannons) do
                        if ca.group then
                            if group[ca.group].mode == 1 and group[ca.group].HmsMode == 2 and group[ca.group].HmsUser ==
                                v.name then
                                rednet.send(ca.id, {
                                    tgPos = v.targetPos,
                                    velocity = {
                                        x = 0,
                                        y = 0,
                                        z = 0
                                    },
                                    mode = 1,
                                    fire = group[ca.group].fire
                                }, protocol)
                            end
                        end
                    end
                end
            end

            if index == 0 then
                sleep(0.1)
            end
        else
            sleep(0.05)
        end
    end
end

local termUtil = {
    cpX = 1,
    cpY = 1,

    fieldTb = nil,
    selectBoxTb = nil
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
            field = string.sub(field, 1, xPos) .. char .. string.sub(field, xPos, #field)
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

function termUtil:init()
    self.fieldTb = {
        password = newTextField(properties, "password", 12, 3),
        maxSelectRange = newTextField(properties, "maxSelectRange", 18, 7),
    }
    self.selectBoxTb = {
        face = newSelectBox(properties, "face", 2, 12, 5, "south", "west", "north", "east")
    }

    termUtil:refresh()
end

local selfId = os.getComputerID()
function termUtil:refresh()
    term.clear()
    term.setCursorPos(18, 1)
    printError(string.format("self id: %d", selfId))

    term.setCursorPos(2, 3)
    term.write("password: ")
    term.setCursorPos(2, 5)
    term.write("Face: ")
    term.setCursorPos(2, 7)
    term.write("MaxSelectRange: ")

    for k, v in pairs(self.fieldTb) do
        v:paint()
    end
    for k, v in pairs(self.selectBoxTb) do
        v:paint()
    end
end

peripheral.find("modem", rednet.open)
-- {name = properties.cannonName, pw = properties.password}
local redNet = function()
    while true do
        local id, msg
        repeat
            id, msg = rednet.receive(request_protocol)
        until type(msg) == "table"
        if msg.pw == properties.password then
            local flag = false
            for k, v in pairs(linkedCannons) do
                if v.id == id then
                    v.beat = 3
                    v.name = msg.name
                    flag = true
                    break
                end
            end

            if not flag then
                table.insert(linkedCannons, {
                    id = id,
                    name = msg.name,
                    beat = 3,
                    mode = 2,
                    group = nil
                })

                if not table.contains(properties.whiteList, msg.slug) then
                    table.insert(properties.whiteList, msg.slug)
                end
                
                if not table.contains(properties.whiteList, msg.yawSlug) then
                    table.insert(properties.whiteList, msg.yawSlug)
                end
            end

            for k, v in pairs(tm_monitors.list) do
                for k2, v2 in pairs(v.windows) do
                    v2.windows.cannonList:refresh()
                    v2.drawW.sync()
                end
                v.gpu.sync()
            end
            for _, ca in pairs(linkedCannons) do -- 如果是point模式顺便发送坐标
                if ca.group then
                    if group[ca.group].mode == 2 then
                        rednet.send(ca.id, {
                            tgPos = group[ca.group].pos,
                            velocity = {
                                x = 0,
                                y = 0,
                                z = 0
                            },
                            mode = 2,
                            fire = group[ca.group].fire
                        }, protocol)
                    end
                end
            end
        end
    end
end

local beats = function()
    while true do
        local index = 1
        while true do
            if index > #linkedCannons then
                break
            end
            linkedCannons[index].beat = linkedCannons[index].beat - 1
            if linkedCannons[index].beat < 0 then
                table.remove(linkedCannons, index)
                index = index - 1
            end
            index = index + 1
        end
        sleep(1)
    end
end

local events = function()
    while true do
        local eventData = {os.pullEvent()}
        local event = eventData[1]

        if event == "mouse_click" or event == "key" or event == "char" then
            if event == "mouse_click" then
                term.setCursorBlink(true)
                local x, y = eventData[3], eventData[4]
                for k, v in pairs(termUtil.fieldTb) do -- 点击了输入框
                    if y == v.y and x >= v.x and x <= v.x + v.len then
                        v:click(x, y)
                    end
                end
                for k, v in pairs(termUtil.selectBoxTb) do -- 点击了选择框
                    if y == v.y then
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

            -- 刷新数据到properties
            system.updatePersistentData()
            termUtil:refresh()

            term.setCursorPos(termUtil.cpX, termUtil.cpY)
        elseif event == "tm_monitor_touch" then
            tm_monitors.list[eventData[2]]:click(eventData[3], eventData[4], 2)
            for k, v in pairs(tm_monitors.list) do
                v:refresh()
            end
        elseif event == "tm_monitor_mouse_click" or event == "tm_monitor_mouse_drag" then
            tm_monitors.list[eventData[2]]:click(eventData[3], eventData[4], eventData[5])
        elseif event == "tm_monitor_mouse_scroll" then
            tm_monitors.list[eventData[2]]:scroll(eventData[3], eventData[4], eventData[5])
        elseif event == "tm_monitor_mouse_move" then
            tm_monitors.list[eventData[2]]:move(eventData[3], eventData[4])
        end
    end
end

tm_monitors:getGpus()
tm_monitors:init()

termUtil:init()

local runScanner = function()
    parallel.waitForAll(getGoggles, scanner.run)
end

local runRednet = function()
    parallel.waitForAll(redNet, beats)
end

local runListener = function()
    parallel.waitForAll(runRednet, events)
end

local run = function()
    parallel.waitForAll(runListener, runScanner)
end

run()
