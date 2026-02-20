require "anims/waluigi"

_G.ACT_WALL_SLIDE       = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_MOVING | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION)
_G.ACT_ELEGANT_JUMP     = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_CONTROL_JUMP_HEIGHT)
_G.ACT_WALUIGI_AIR_SWIM = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_MOVING | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION)

function act_wall_slide(m)
    if (m.input & INPUT_A_PRESSED) ~= 0 then
        local rc = set_mario_action(m, ACT_TRIPLE_JUMP, 0)
        m.vel.y = 72.0

        if m.forwardVel < 20.0 then
            m.forwardVel = 20.0
        end
        m.wallKickTimer = 0
        return rc
    end

    -- attempt to stick to the wall a bit. if it's 0, sometimes you'll get kicked off of slightly sloped walls
    mario_set_forward_vel(m, -1.0)

    m.particleFlags = m.particleFlags | PARTICLE_DUST

    play_sound(SOUND_MOVING_TERRAIN_SLIDE + m.terrainSoundAddend, m.marioObj.header.gfx.cameraToObject)
    set_mario_animation(m, MARIO_ANIM_START_WALLKICK)

    if perform_air_step(m, 0) == AIR_STEP_LANDED then
        mario_set_forward_vel(m, 0.0)
        if check_fall_damage_or_get_stuck(m, ACT_HARD_BACKWARD_GROUND_KB) == 0 then
            return set_mario_action(m, ACT_FREEFALL_LAND, 0)
        end
    end

    m.actionTimer = m.actionTimer + 1
    if m.wall == nil and m.actionTimer > 2 then
        mario_set_forward_vel(m, 0.0)
        return set_mario_action(m, ACT_FREEFALL, 0)
    end

    -- gravity
    m.vel.y = m.vel.y + 2

    return 0
end

function act_elegant_jump(m)
    if m.actionArg == 0 then
        m.particleFlags = m.particleFlags | PARTICLE_MIST_CIRCLE
        play_character_sound(m, CHAR_SOUND_HAHA)
        m.twirlYaw = m.faceAngle.y
        m.actionArg = math.random(2)
    end
    local stepResult = common_air_action_step(m, ACT_DOUBLE_JUMP_LAND, MARIO_ANIM_RUNNING_UNUSED,
                                              AIR_STEP_CHECK_LEDGE_GRAB | AIR_STEP_CHECK_HANG)
    if stepResult == AIR_STEP_NONE then
        smlua_anim_util_set_animation(m.marioObj, "WALUIGI_ANIM_ELEGANT_JUMP_" .. tostring(m.actionArg))
    end
    m.particleFlags = m.particleFlags | PARTICLE_SPARKLES
    m.marioBodyState.eyeState = MARIO_EYES_CLOSED
    m.faceAngle.y = m.intendedYaw

    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_GROUND_POUND, 0)
    end

    if (m.input & INPUT_NONZERO_ANALOG) ~= 0 then
        mario_set_forward_vel(m, math.abs(m.forwardVel))
    end

    if stepResult == AIR_STEP_LANDED then
        if should_get_stuck_in_ground(m) ~= 0 then
            queue_rumble_data_mario(m, 5, 80)
            play_sound(SOUND_MARIO_OOOF2, m.marioObj.header.gfx.cameraToObject)
            m.particleFlags = m.particleFlags | PARTICLE_MIST_CIRCLE
            set_mario_action(m, ACT_FEET_STUCK_IN_GROUND, 0)
        else
            play_sound(SOUND_ACTION_TERRAIN_LANDING, m.marioObj.header.gfx.cameraToObject)
            set_mario_action(m, ACT_DOUBLE_JUMP_LAND, 0)
        end
    end

    m.twirlYaw = m.twirlYaw + 0x2000
    m.marioObj.header.gfx.angle.y = m.twirlYaw
    return 0
end

function act_waluigi_air_swim(m)
    local e = gCharacterStates[m.playerIndex].waluigi

    if m.actionTimer == 0 then
        set_anim_to_frame(m, 0)
        play_sound(SOUND_ACTION_SWIM_FAST, m.marioObj.header.gfx.cameraToObject)
        if m.forwardVel <= 40 then
            mario_set_forward_vel(m, 40)
        else
            mario_set_forward_vel(m, m.forwardVel + 5)
        end
    end

    if m.actionTimer >= 20 then
        set_mario_action(m, ACT_DIVE, 0)
        m.vel.y = 0
        m.faceAngle.x = 0
        mario_set_forward_vel(m, 0)
    end

    if m.actionTimer > 10 and (m.controller.buttonPressed & B_BUTTON) ~= 0 and e.swims > 0 then
        e.swims = e.swims - 1
        return set_mario_action(m, ACT_WALUIGI_AIR_SWIM, 0)
    end

    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_GROUND_POUND, 0)
    end

    m.vel.y = 0

    set_mario_animation(m, MARIO_ANIM_SWIM_PART1)

    local stepResult = perform_air_step(m, 0)
    if stepResult == AIR_STEP_LANDED then
        if should_get_stuck_in_ground(m) ~= 0 then
            queue_rumble_data_mario(m, 5, 80)
            play_character_sound(m, CHAR_SOUND_OOOF2)
            set_mario_action(m, ACT_FEET_STUCK_IN_GROUND, 0)
        else
            if check_fall_damage(m, ACT_SQUISHED) == 0 then
                set_mario_action(m, ACT_DIVE_SLIDE, 0)
            end
        end
    elseif stepResult == AIR_STEP_HIT_WALL then
        set_mario_action(m, ACT_SOFT_BONK, 0)
    end

    if m.forwardVel > 4 then mario_set_forward_vel(m, m.forwardVel - 2) end
    m.actionTimer = m.actionTimer + 1
    m.faceAngle.y = m.intendedYaw - approach_s32(math.s16(m.intendedYaw - m.faceAngle.y), 0, 0x200, 0x200)
    return 0
end

function waluigi_before_phys_step(m)
    local hScale = 1.0
    local vScale = 1.0

    -- faster ground movement
    if (m.action & ACT_FLAG_MOVING) ~= 0 then
        hScale = hScale * 1.09
    end

    m.vel.x = m.vel.x * hScale
    m.vel.y = m.vel.y * vScale
    m.vel.z = m.vel.z * hScale

    if m.action == ACT_TRIPLE_JUMP and m.prevAction == ACT_DOUBLE_JUMP and m.actionTimer < 6 then
        m.particleFlags = m.particleFlags | PARTICLE_DUST
        m.actionTimer = m.actionTimer + 1
    end
end

function waluigi_on_set_action(m)
    -- wall slide
    if m.action == ACT_SOFT_BONK then
        m.faceAngle.y = m.faceAngle.y + 0x8000
        set_mario_action(m, ACT_WALL_SLIDE, 0)
        m.vel.x = 0
        m.vel.y = 0
        m.vel.z = 0

    -- turn wall kick into flip
    elseif m.action == ACT_WALL_KICK_AIR and m.prevAction ~= ACT_HOLDING_POLE and m.prevAction ~= ACT_CLIMBING_POLE then
        local rc = set_mario_action(m, ACT_TRIPLE_JUMP, 0)
        m.vel.y = 60.0

        if m.forwardVel < 20.0 then
            m.forwardVel = 20.0
        end
        m.wallKickTimer = 0
        return rc

    -- less height on jumps
    elseif m.action == ACT_JUMP or m.action == ACT_DOUBLE_JUMP or m.action == ACT_TRIPLE_JUMP or m.action == ACT_SPECIAL_TRIPLE_JUMP or m.action == ACT_STEEP_JUMP or m.action == ACT_SIDE_FLIP or m.action == ACT_RIDING_SHELL_JUMP or m.action == ACT_BACKFLIP or m.action == ACT_WALL_KICK_AIR  or m.action == ACT_LONG_JUMP then
        m.vel.y = m.vel.y * 0.9
    end

    -- more height on triple jump
    if m.action == ACT_TRIPLE_JUMP or m.action == ACT_SPECIAL_TRIPLE_JUMP then
        m.vel.y = m.vel.y * 1.25
    end

    if m.action == ACT_ELEGANT_JUMP then
        m.vel.y = 60
    end
end

function waluigi_update(m)
    local e = gCharacterStates[m.playerIndex].waluigi

    -- increase player damage (go easy on the capless players)
    if m.hurtCounter > e.lastHurtCounter then
        if m.flags & (MARIO_NORMAL_CAP | MARIO_CAP_ON_HEAD) == 0 then
            m.hurtCounter = m.hurtCounter + 6
        else
            m.hurtCounter = m.hurtCounter + 8
        end
    end
    e.lastHurtCounter = m.hurtCounter

    -- double jump
    local shouldDoubleJump = (m.action == ACT_DOUBLE_JUMP or m.action == ACT_JUMP or m.action == ACT_SIDE_FLIP or m.action == ACT_BACKFLIP or m.action == ACT_FREEFALL)

    if shouldDoubleJump and m.actionTimer > 0 and (m.controller.buttonPressed & A_BUTTON) ~= 0 then
        return set_mario_action(m, ACT_ELEGANT_JUMP, 0)
    end
    if shouldDoubleJump then
        m.actionTimer = m.actionTimer + 1
    end

    -- swim mid-air
    if m.action == ACT_DIVE and m.actionTimer > 0 and (m.controller.buttonPressed & B_BUTTON) ~= 0 and e.swims > 0 then
        e.swims = e.swims - 1
        return set_mario_action(m, ACT_WALUIGI_AIR_SWIM, 0)
    end
    if (m.action & ACT_GROUP_AIRBORNE) == 0 then
        e.swims = 3
    end

    if m.action == ACT_DIVE then
        m.actionTimer = m.actionTimer + 1
        if m.prevAction == ACT_WALUIGI_AIR_SWIM then
            set_mario_animation(m, MARIO_ANIM_SWIM_PART1)
            set_anim_to_frame(m, 30)
        end
    end
end

hook_mario_action(ACT_WALL_SLIDE,       act_wall_slide)
hook_mario_action(ACT_ELEGANT_JUMP,     act_elegant_jump)
hook_mario_action(ACT_WALUIGI_AIR_SWIM, act_waluigi_air_swim)

return {
    { HOOK_MARIO_UPDATE, waluigi_update },
    { HOOK_BEFORE_PHYS_STEP, waluigi_before_phys_step },
    { HOOK_ON_SET_MARIO_ACTION, waluigi_on_set_action }
}