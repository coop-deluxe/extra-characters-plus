--- Misc Functions ---

if VERSION_NUMBER < 41 then -- remove this block in 1.4
    --- @class bitsize : integer

    --- @param x integer
    --- @param size bitsize
    --- @return integer
    --- Converts any integer to a signed integer
    function tosigned_integer(x, size)
        x = math.floor(x) & (1 << size) - 1
        return x - ((x & (1 << (size - 1))) << 1)
    end

    --- @param x integer
    --- @param size bitsize
    --- @return integer
    --- Converts any integer to an unsigned integer
    function tounsigned_integer(x, size)
        return math.floor(x) & (1 << size) - 1
    end

    --- @param x number
    --- @return integer
    --- Converts `x` into a valid `s16` range
    --- - `[-32768, 32767]`
    function math.s16(x)
        return tosigned_integer(x, 16)
    end

end

--- @param m MarioState
--- @param name string
--- @param accel? number
--- Plays a custom animation for MarioState `m`
function play_custom_anim(m, name, accel)
    accel = accel or 0x10000

    m.marioObj.header.gfx.animInfo.animAccel = accel

    if (smlua_anim_util_get_current_animation_name(m.marioObj) ~= name or m.marioObj.header.gfx.animInfo.animID ~= -1) then
        m.marioObj.header.gfx.animInfo.animID = -1
        set_anim_to_frame(m, 0)
    end

    smlua_anim_util_set_animation(m.marioObj, name)
end