if not _G.charSelectExists then return end

local princessFloatActs = {
    [ACT_JUMP] = true,
    [ACT_DOUBLE_JUMP] = true,
    [ACT_TRIPLE_JUMP] = true,
    [ACT_LONG_JUMP] = true,
    [ACT_BACKFLIP] = true,
    [ACT_SIDE_FLIP] = true,
    [ACT_WALL_KICK_AIR] = true,
}

-----------------
-- Peach Float --
-----------------

ACT_PEACH_FLOAT = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_MOVING)

--- @param m MarioState
local function act_peach_float(m)
    -- apply movement when using action
    common_air_action_step(m, ACT_JUMP_LAND, CHAR_ANIM_BEND_KNESS_RIDING_SHELL, AIR_STEP_NONE)

    -- setup when action starts (horizontal speed and voiceline)
    if m.actionTimer == 0 then
        play_character_sound(m, CHAR_SOUND_HELLO)
    end

    
    if m.forwardVel > 20 then
        m.forwardVel = m.forwardVel - 0.5
    end

    -- Slowly decend
    m.vel.y = -1
    set_mario_particle_flags(m, PARTICLE_SPARKLES, 0)

    -- avoid issue with flying and then make the hover end after 2 secs or when stopping holding the button
    if m.prevAction ~= ACT_TRIPLE_JUMP and (m.flags & MARIO_WING_CAP) ~= 0 then
        if m.actionTimer >= 50 or (m.controller.buttonDown & A_BUTTON) == 0 then
            set_mario_action(m, ACT_FREEFALL, 0)
        end
    else
        if m.actionTimer >= 50 or (m.controller.buttonDown & A_BUTTON) == 0 then
            set_mario_action(m, ACT_FREEFALL, 0)
        end
    end

    -- increment the action timer to make the hover stop
    m.actionTimer = m.actionTimer + 1
end

--- @param m MarioState
function peach_update(m)
    if (m.input & INPUT_A_DOWN) ~= 0 and m.vel.y < -10 and m.prevAction ~= ACT_PEACH_FLOAT and princessFloatActs[m.action] then
        set_mario_action(m, ACT_PEACH_FLOAT, 0)
    end
end

hook_mario_action(ACT_PEACH_FLOAT, act_peach_float)

-----------------------
-- Daisy Double Jump --
-----------------------

ACT_DAISY_JUMP = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_MOVING)

--- @param m MarioState
local function act_daisy_jump(m)
    -- apply movement when using action
    common_air_action_step(m, ACT_JUMP_LAND, CHAR_ANIM_BEND_KNESS_RIDING_SHELL, AIR_STEP_NONE)

    -- setup when action starts (vertical speed and voiceline)
    if m.actionTimer == 0 then
        m.vel.y = m.forwardVel*0.3 + 40
        m.forwardVel = m.forwardVel*0.7
        play_character_sound(m, CHAR_SOUND_HELLO)
    end

    set_mario_particle_flags(m, PARTICLE_LEAF, 0)

    -- avoid issue with flying and then make the hover end after 2 secs or when stopping holding the button
    if m.prevAction ~= ACT_TRIPLE_JUMP and (m.flags & MARIO_WING_CAP) ~= 0 then
        if m.actionTimer >= 10 or (m.controller.buttonDown & A_BUTTON) == 0 then
            set_mario_action(m, ACT_FREEFALL, 0)
        end
    else
        if m.actionTimer >= 10 or (m.controller.buttonDown & A_BUTTON) == 0 then
            set_mario_action(m, ACT_FREEFALL, 0)
        end
    end

    -- increment the action timer to make the hover stop
    m.actionTimer = m.actionTimer + 1
end

--- @param m MarioState
function daisy_update(m)
    if (m.input & INPUT_A_PRESSED) ~= 0 and m.vel.y < 10 and m.prevAction ~= ACT_DAISY_JUMP and princessFloatActs[m.action] then
        set_mario_action(m, ACT_DAISY_JUMP, 0)
    end
end

hook_mario_action(ACT_DAISY_JUMP, act_daisy_jump)

-------------------
-- Rosalina Spin --
-------------------

ACT_SPINJUMP = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ATTACKING)
E_MODEL_SPIN_ATTACK = smlua_model_util_get_id("spin_attack_geo")

---@param o Object
local function bhv_spin_attack_init(o)
    o.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE
end

---@param o Object
local function bhv_spin_attack_loop(o)
    cur_obj_set_pos_relative_to_parent(0, 20, 0)

    o.oFaceAngleYaw = o.oFaceAngleYaw + 0x2000
    if o.oTimer >= 10 then
        obj_mark_for_deletion(o)
    end
end

local id_bhvSpinAttack = hook_behavior(nil, OBJ_LIST_GENACTOR, true, bhv_spin_attack_init, bhv_spin_attack_loop)

local usedSpinJump = false

---@param m MarioState
function act_spinjump(m)
    m.marioBodyState.handState = 2

    if m.actionTimer == 0 then
        if not usedSpinJump then
            play_character_sound(m, CHAR_SOUND_WAH2)
        end
        play_sound_with_freq_scale(SOUND_ACTION_SIDE_FLIP_UNK, m.marioObj.header.gfx.cameraToObject, 1.9)
        m.marioObj.header.gfx.animInfo.animFrame = 0

        -- short syntax that sets y velocity based on the spin jump already being used or not
        m.vel.y = usedSpinJump and 0 or 30
        m.marioObj.hurtboxRadius = 100

        usedSpinJump = true

        -- spawn spin_attack_geo
        local o = spawn_non_sync_object(
            id_bhvSpinAttack,
            E_MODEL_SPIN_ATTACK,
            m.pos.x, m.pos.y, m.pos.z,
            nil)
        o.parentObj = m.marioObj
        o.globalPlayerIndex = m.marioObj.globalPlayerIndex
    end

    common_air_action_step(m, ACT_FREEFALL_LAND, CHAR_ANIM_BEND_KNESS_RIDING_SHELL, AIR_STEP_NONE)

    if m.actionTimer >= 15 then
        --m.marioBodyState.handState = 0
        set_mario_action(m, ACT_FREEFALL, 0)

        m.marioObj.hurtboxRadius = 37
    end
    -- make the action time go forward
    m.actionTimer = m.actionTimer + 1
end

local spinCanCancel = {
    [ACT_LONG_JUMP] = true,
    [ACT_BACKFLIP] = true,
}

local function rosalina_update(m)
    if m.action ~= ACT_SPINJUMP then
        m.marioObj.hurtboxRadius = 37
    end

    if spinCanCancel[m.action] and m.controller.buttonPressed & B_BUTTON ~= 0 and m.input & (INPUT_Z_DOWN | INPUT_A_DOWN) == 0 then
        set_mario_action(m, ACT_SPINJUMP, 0)
    end
end
hook_mario_action(ACT_SPINJUMP, { every_frame = act_spinjump }, INT_FAST_ATTACK_OR_SHELL)

local spinJumpActs = {
    [ACT_PUNCHING] = true,
    [ACT_MOVE_PUNCHING] = true,
    [ACT_JUMP_KICK] = true,
    [ACT_DIVE] = true
}

---@param m MarioState
local function rosalina_before_action(m, nextAct)
    if spinJumpActs[nextAct] and m.input & (INPUT_Z_DOWN | INPUT_A_DOWN) == 0 then
        return set_mario_action(m, ACT_SPINJUMP, 0)
    end
    if usedSpinJump and ((nextAct & ACT_GROUP_MASK) ~= ACT_GROUP_AIRBORNE) then
        usedSpinJump = false
        play_sound_with_freq_scale(SOUND_GENERAL_COIN_SPURT_EU, m.marioObj.header.gfx.cameraToObject, 1.6)
        spawn_non_sync_object(id_bhvSparkle, E_MODEL_SPARKLES_ANIMATION, m.pos.x, m.pos.y + 200, m.pos.z, function (o)
            obj_scale(o, 0.75)
        end)
    end
    -- Recharge without indicator (Accurate to Galaxy)
    if usedSpinJump and nextAct == ACT_WALL_KICK_AIR then
        usedSpinJump = false
    end
end

local function rosalina_on_interact(m, o, intType)
    if intType == INTERACT_GRABBABLE and m.action == ACT_SPINJUMP and o.oInteractionSubtype & INT_SUBTYPE_NOT_GRABBABLE == 0 then
        m.action = ACT_MOVE_PUNCHING
        m.actionArg = 1
        return
    end
end

local function rosalina_on_pvp_attack(attacker, victim)
    if attacker.action == ACT_SPINJUMP then
        victim.faceAngle.y = mario_obj_angle_to_object(victim, attacker.marioObj)
        set_mario_action(victim, ACT_BACKWARD_AIR_KB, 0)
    end
end

local function on_character_select_load()
    local CT_PEACH = extraCharacters[2].tablePos
    local CT_DAISY = extraCharacters[3].tablePos
    local CT_ROSALINA = extraCharacters[9].tablePos
    
    -- Peach
    _G.charSelect.character_hook_moveset(CT_PEACH, HOOK_MARIO_UPDATE, peach_update)
    -- Daisy
    _G.charSelect.character_hook_moveset(CT_DAISY, HOOK_MARIO_UPDATE, daisy_update)
    -- Rosalina
    _G.charSelect.character_hook_moveset(CT_ROSALINA, HOOK_MARIO_UPDATE, rosalina_update)
    _G.charSelect.character_hook_moveset(CT_ROSALINA, HOOK_ON_PVP_ATTACK, rosalina_on_pvp_attack)
    _G.charSelect.character_hook_moveset(CT_ROSALINA, HOOK_ON_INTERACT, rosalina_on_interact)
    _G.charSelect.character_hook_moveset(CT_ROSALINA, HOOK_BEFORE_SET_MARIO_ACTION, rosalina_before_action)
end

hook_event(HOOK_ON_MODS_LOADED, on_character_select_load)