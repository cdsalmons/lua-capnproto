local ffi = require "ffi"
local lower = string.lower
local upper = string.upper
local gsub = string.gsub
local format = string.format
local concat = table.concat
local insert = table.insert

local _M = {}

function _M.upper_dash_naming(name)
    return upper(gsub(name, "(%u+)", "-%1"))
end

function _M.lower_underscore_naming(name)
    return lower(gsub(name, "(%u+)", "_%1"))
end

function _M.upper_underscore_naming(name)
    return upper(gsub(name, "(%u+)", "_%1"))
end

-- capnp only allow camel naming for enums
function _M.camel_naming(name)
    return name
end

function _M.parse_capnp_decode_txt(infile)
    local f = io.open(infile)
    if not f then
        return nil, "Can't open file: " .. tostring(infile)
    end

    local s = f:read("*a")
    f:close()

    s = gsub(s, "%(", "{")
    s = gsub(s, "%)", "}")
    s = gsub(s, "%[", "{")
    s = gsub(s, "%]", "}")
    s = gsub(s, "%<", "'")
    s = gsub(s, "%>", "'")
    s = gsub(s, "id = (%d+)", "id = \"%1\"")
    s = gsub(s, "typeId = (%d+)", "typeId = \"%1\"")
    s = gsub(s, "scopeId = (%d+)", "scopeId = \"%1\"")
    s = gsub(s, "= void([^\"])", "= \"void\"%1")
    s = gsub(s, "type = {", '[\"type\"] = {')
    s = "return " .. s

    return s
end

function _M.table_diff(t1, t2, namespace)
    local keys = {}

    if not namespace then
        namespace = ""
    end

    for k, v in pairs(t1) do
        k = _M.lower_underscore_naming(k)
        keys[k] = true
        t1[k] = v
    end

    for k, v in pairs(t2) do
        k = _M.lower_underscore_naming(k)
        keys[k] = true
        t2[k] = v
    end

    for k, v in pairs(keys) do
        local name = namespace .. "." .. k
        local v1 = t1[k]
        local v2 = t2[k]

        local t1 = type(v1)
        local t2 = type(v2)

        if t1 ~= t2 then
            print(format("%s: different type: %s %s, value: %s %s", name,
                    t1, t2, tostring(v1), tostring(v2)))
        elseif t1 == "table" then
            _M.table_diff(v1, v2, namespace .. "." .. k)
        elseif v1 ~= v2 then
            print(format("%s: different value: %s %s", name,
                    tostring(v1), tostring(v2)))
        end
    end
end

function _M.write_file(name, content)
    local f = assert(io.open(name, "w"))
    f:write(content)
    f:close()
end

function _M.get_output_name(schema)
    return string.gsub(schema.requestedFiles[1].filename, "%.capnp", "_capnp")
end

function _M.hex_buf_str(buf, len)
    local str = ffi.string(buf, len)
    local t = {}
    for i = 1, len do
        table.insert(t, bit.tohex(string.byte(str, i), 2))
    end
    return table.concat(t, " ")
end
function _M.print_hex_buf(buf, len)
    local str = _M.hex_buf_str(buf, len)
    print(str)
end

function _M.new_buf(hex, ct)
    if type(hex) ~= "table" then
        error("expected the first argument as a table")
    end
    local len = #hex
    local buf = ffi.new("char[?]", len)
    for i=1, len do
        buf[i - 1] = hex[i]
    end
    if not ct then
        ct = "uint32_t *"
    end
    return ffi.cast(ct, buf)
end

function equal(a, b)
    if type(a) == "boolean" then
        a = a and 1 or 0
    end
    if type(b) == "boolean" then
        b = b and 1 or 0
    end
    return a == b
end

function to_text_core(val, T, res)
    local typ = type(val)
    if typ == "table" then
        if #val > 0 then
            -- list
            insert(res, "[")
            for i = 1, #val do
                if i ~= 1 then
                    insert(res, ", ")
                end
                insert(res, '"')
                insert(res, val[i])
                insert(res, '"')
            end
            insert(res, "]")
        else
            -- struct
            insert(res, "(")
            local i = 1
            for _, item in pairs(T.fields) do
                local k = item.name
                local default = item.default
                if type(default) == "boolean" then
                    default = default and 1 or 0
                end
                if val[k] ~= nil then
                    if not equal(val[k], default) then
                        if i ~= 1 then
                            insert(res, ", ")
                        end
                        insert(res, k)
                        insert(res, " = ")
                        to_text_core(val[k], T[k], res)
                        i = i + 1
                    end
                end
            end
            insert(res, ")")
        end
    elseif typ == "string" then
        insert(res, '"')
        insert(res, val)
        insert(res, '"')
    elseif typ == "boolean" then
        insert(res, val and 1 or 0)
    else
        insert(res, val)
    end
end

function _M.to_text(val, T)
    local res = {}
    to_text_core(val, T, res)
    return concat(res)
end

return _M
