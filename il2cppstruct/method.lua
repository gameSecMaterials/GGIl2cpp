AndroidInfo = require("until.androidinfo")

---@class MethodsApi
---@field ClassOffset number
---@field NameOffset number
---@field ParamCount number
---@field ReturnType number
local MethodsApi = {


    ---@param self MethodsApi
    ---@param MethodName string
    ---@return MethodInfoRaw[]
    FindMethodWithName = function(self, MethodName)
        local FinalMethods, name = {}, "00 " .. MethodName:gsub('.', function(c)
            return string.format('%02X', string.byte(c)) .. " "
        end) .. "00"
        gg.clearResults()
        gg.setRanges(gg.REGION_C_HEAP | gg.REGION_C_ALLOC | gg.REGION_ANONYMOUS | gg.REGION_C_BSS | gg.REGION_C_DATA |
                         gg.REGION_OTHER)
        gg.searchNumber('h ' .. name, gg.TYPE_BYTE, false, gg.SIGN_EQUAL, Il2cpp.globalMetadataStart,
            Il2cpp.globalMetadataEnd)
        if gg.getResultsCount() == 0 then
            error('the "' .. MethodName .. '" function was not found')
        end
        gg.refineNumber('h ' .. string.sub(name, 4, 5))
        local r = gg.getResults(gg.getResultsCount())
        gg.clearResults()
        for j = 1, #r do
            if gg.BUILD < 16126 then
                gg.searchNumber(string.format("%8.8X", Il2cpp.FixValue(r[j].address)) .. 'h', self.MainType)
            else
                gg.loadResults({r[j]})
                gg.searchPointer(0)
            end
            if gg.getResultsCount() <= 0 and AndroidInfo.platform and AndroidInfo.sdk >= 30 then
                gg.searchNumber(tostring(tonumber(Il2cpp.FixValue(r[j].address), 16) | 0xB400000000000000),
                    gg.TYPE_QWORD)
            end
            local MethodsInfo = gg.getResults(gg.getResultsCount())
            gg.clearResults()
            for k, v in ipairs(MethodsInfo) do
                v.address = v.address - self.NameOffset
                local FinalAddress = Il2cpp.FixValue(gg.getValues({v})[1].value)
                if (FinalAddress > Il2cpp.il2cppStart and FinalAddress < Il2cpp.il2cppEnd) then
                    FinalMethods[#FinalMethods + 1] = {
                        MethodName = MethodName,
                        MethodAddress = FinalAddress,
                        MethodInfoAddress = v.address
                    }
                end
            end
        end
        if (#FinalMethods == 0) then
            error('the "' .. MethodName .. '" function pointer was not found')
        end
        return FinalMethods
    end,


    ---@param self MethodsApi
    ---@param MethodOffset number
    ---@return MethodInfoRaw[]
    FindMethodWithOffset = function(self, MethodOffset)
        local MethodsInfo = self.FindMethodWithAddressInMemory(Il2cpp.il2cppStart + MethodOffset, MethodOffset)
        if (#MethodsInfo == 0) then
            error('nothing was found for this offset 0x' .. string.format("%X", MethodOffset))
        end
        return MethodsInfo
    end,


    ---@param self MethodsApi
    ---@param MethodAddress number
    ---@param MethodOffset number | nil
    ---@return MethodInfoRaw[]
    FindMethodWithAddressInMemory = function(self, MethodAddress, MethodOffset)
        local RawMethodsInfo = {} -- the same as MethodsInfo
        gg.clearResults()
        gg.setRanges(gg.REGION_C_HEAP | gg.REGION_C_ALLOC | gg.REGION_ANONYMOUS | gg.REGION_C_BSS | gg.REGION_C_DATA |
                         gg.REGION_OTHER)
        if gg.BUILD < 16126 then
            gg.searchNumber(string.format("%8.8X", MethodAddress) .. 'h', Il2cpp.MainType)
        else
            gg.loadResults({{
                address = MethodAddress,
                flags = Il2cpp.MainType
            }})
            gg.searchPointer(0)
        end
        local r = gg.getResults(gg.getResultsCount())
        gg.clearResults()
        for j = 1, #r do
            RawMethodsInfo[#RawMethodsInfo + 1] = {
                MethodAddress = MethodAddress,
                MethodInfoAddress = r[j].address,
                Offset = MethodOffset
            }
        end
        if (#RawMethodsInfo == 0 and MethodOffset == nil) then
            error('nothing was found for this address 0x' .. string.format("%X", MethodAddress))
        end
        return RawMethodsInfo
    end,


    ---@param self MethodsApi
    ---@param _MethodsInfo MethodInfo[]
    DecodeMethodsInfo = function(self, _MethodsInfo, MethodsInfo)
        for i = 1, #_MethodsInfo do
            local index = (i - 1) * 5
            local TypeInfo = Il2cpp.FixValue(MethodsInfo[index + 5].value)
            local _TypeInfo = gg.getValues({{ -- type index
                address = TypeInfo + Il2cpp.TypeApi.Type,
                flags = gg.TYPE_BYTE
            }, { -- index
                address = TypeInfo,
                flags = Il2cpp.MainType
            }})
            local MethodAddress = Il2cpp.FixValue(MethodsInfo[index + 1].value)
            _MethodsInfo[i] = {
                MethodName = _MethodsInfo[i].MethodName or
                    Il2cpp.Utf8ToString(Il2cpp.FixValue(MethodsInfo[index + 2].value)),
                Offset = string.format("%X", _MethodsInfo[i].Offset or MethodAddress - Il2cpp.il2cppStart),
                AddressInMemory = string.format("%X", MethodAddress),
                MethodInfoAddress = _MethodsInfo[i].MethodInfoAddress,
                ClassName = _MethodsInfo[i].ClassName or Il2cpp.ClassApi:GetClassName(MethodsInfo[index + 3].value),
                ClassAddress = string.format('%X', Il2cpp.FixValue(MethodsInfo[index + 3].value)),
                ParamCount = MethodsInfo[index + 4].value,
                ReturnType = Il2cpp.TypeApi:GetTypeName(_TypeInfo[1].value, _TypeInfo[2].value)
            }
        end
    end,


    ---@param self MethodsApi
    ---@param MethodInfo MethodInfoRaw
    UnpackMethodInfo = function(self, MethodInfo)
        return {
            { -- Address Method in Memory
                address = MethodInfo.MethodInfoAddress,
                flags = Il2cpp.MainType
            },
            { -- Name Address
                address = MethodInfo.MethodInfoAddress + self.NameOffset,
                flags = Il2cpp.MainType
            },
            { -- Class address
                address = MethodInfo.MethodInfoAddress + self.ClassOffset,
                flags = Il2cpp.MainType
            },
            { -- Param Count
                address = MethodInfo.MethodInfoAddress + self.ParamCount,
                flags = gg.TYPE_WORD
            },
            { -- Return Type
                address = MethodInfo.MethodInfoAddress + self.ReturnType,
                flags = Il2cpp.MainType
            }
        }, 
        {
            MethodName = MethodInfo.MethodName or nil,
            Offset = MethodInfo.Offset or nil,
            MethodInfoAddress = MethodInfo.MethodInfoAddress,
            ClassName = MethodInfo.ClassName
        }
    end,


    FindParamsCheck = {
        ---@param self MethodsApi
        ---@param method number
        ['number'] = function(self, method)
            if (method > Il2cpp.il2cppStart and method < Il2cpp.il2cppEnd) then
                return Protect:Call(self.FindMethodWithAddressInMemory, self, method)
            else
                return Protect:Call(self.FindMethodWithOffset, self, method)
            end
        end,
        ---@param self MethodsApi
        ---@param method string
        ['string'] = function(self, method)
            return Protect:Call(self.FindMethodWithName, self, method)
        end,
        ['default'] = function()
            return {
                Error = 'Invalid search criteria'
            }
        end
    },


    ---@param self MethodsApi
    ---@param method number | string
    ---@return MethodInfo[] | ErrorSearch
    Find = function(self, method)
        ---@type MethodInfoRaw[] | ErrorSearch
        local _MethodsInfo = (self.FindParamsCheck[type(method)] or self.FindParamsCheck['default'])(self, method)
        if (#_MethodsInfo > 0) then
            local MethodsInfo = {}
            for i = 1, #_MethodsInfo do
                local MethodInfo
                MethodInfo, _MethodsInfo[i] = self:UnpackMethodInfo(_MethodsInfo[i])
                table.move(MethodInfo, 1, #MethodInfo, #MethodsInfo + 1, MethodsInfo)
            end
            MethodsInfo = gg.getValues(MethodsInfo)
            self:DecodeMethodsInfo(_MethodsInfo, MethodsInfo)
        end

        return _MethodsInfo
    end
}

return MethodsApi