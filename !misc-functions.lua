--- Misc Functions ---

--- @param m MarioState
--- @param name string
--- @param accel? number
--- Plays a custom animation for MarioState `m`
function play_custom_anim(m, name, accel)
    m.marioObj.header.gfx.animInfo.animAccel = accel or 0x10000

    if (smlua_anim_util_get_current_animation_name(m.marioObj) ~= name or m.marioObj.header.gfx.animInfo.animID ~= -1) then
        m.marioObj.header.gfx.animInfo.animID = -1
        set_anim_to_frame(m, 0)
    end

    smlua_anim_util_set_animation(m.marioObj, name)
end

--- @param str string
--- @param splitAt? string
function string.split(str, splitAt)
    if splitAt == nil then
        splitAt = " "
    end
    local result = {}
    for match in str:gmatch(string.format("[^%s]+", splitAt)) do
        table.insert(result, match)
    end
    return result
end

--- @param x integer
--- @param min integer
--- @param max integer
--- @param inclusive? boolean
--- @return boolean
function in_between(x, min, max, inclusive)
    if inclusive then
        return min <= x and x <= max
    else
        return min < x and x < max
    end
end

-- Generates a truth table
function T(t)
    local t2 = {}
    for _, v in ipairs(t) do
        t2[v] = 1
    end
    return t2
end

--- Returns a table populated with all textures starting at `name .. i` and continuing until `name .. j`.
--- Starts at `insert` and stops at `j`.
--- 
--- Given textures "my_texture_1", "my_texture_2", and "my_texture_3":
--- ```lua
--- texTable = load_textures("my_texture_", 1, 3)
--- ```
--- 
--- @param name string
--- @param i integer
--- @param j integer
--- @return TextureInfo[]
function load_textures(name, i, j)
    print("loaded " .. name)
    local t = {}
    for i = i, j do
        t[i] = get_texture_info(name .. i)
    end
    return t
end

function load_meter(name)
    return {
        label = {
            left  = get_texture_info("char-select-ec-"..name.."-meter-left"),
            right = get_texture_info("char-select-ec-"..name.."-meter-right"),
        },
        pie = {}
    }
end