require "anims/wario"

SPIN_TIMER_SUCCESSFUL_INPUT = 4

_G.ACT_WARIO_DASH             = allocate_mario_action(ACT_GROUP_MOVING | ACT_FLAG_MOVING | ACT_FLAG_ATTACKING)
_G.ACT_WARIO_AIR_DASH         = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ATTACKING)
_G.ACT_WARIO_DASH_REBOUND     = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR)
_G.ACT_PILEDRIVER             = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ATTACKING | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION)
_G.ACT_PILEDRIVER_LAND        = allocate_mario_action(ACT_GROUP_MOVING | ACT_FLAG_MOVING | ACT_FLAG_ATTACKING)
_G.ACT_WARIO_HOLD_JUMP        = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION)
_G.ACT_WARIO_HOLD_FREEFALL    = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION)
_G.ACT_CORKSCREW_CONK         = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ATTACKING | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_CONTROL_JUMP_HEIGHT)
_G.ACT_WARIO_SPINNING_OBJ     = allocate_mario_action(ACT_GROUP_OBJECT | ACT_FLAG_STATIONARY)

-- shoulder bash interactions
local function dash_attacks(m, o, intType)
    if obj_has_behavior_id(o, id_bhvKingBobomb) ~= 0 and o.oAction ~= 0 then
        o.oMoveAngleYaw = m.faceAngle.y
        o.oAction = 4
        o.oVelY = 50
        o.oForwardVel = 20

    elseif obj_has_behavior_id(o, id_bhvBreakableBoxSmall) ~= 0 then
        o.oMoveAngleYaw = m.faceAngle.y
        o.oVelY = 30
        o.oForwardVel = 40

    elseif obj_has_behavior_id(o, id_bhvChuckya) ~= 0 then
        o.oMoveAngleYaw = m.faceAngle.y
        o.oAction = 2
        o.oVelY = 30
        o.oForwardVel = 40

    elseif obj_has_behavior_id(o, id_bhvMrBlizzard) ~= 0 then
        o.oFaceAngleRoll = 0x3000
        o.oMrBlizzardHeldObj = nil
        o.prevObj = o.oMrBlizzardHeldObj
        o.oAction = MR_BLIZZARD_ACT_DEATH

    elseif obj_has_behavior_id(o, id_bhvHeaveHo) ~= 0 then
        obj_mark_for_deletion(o)
        spawn_triangle_break_particles(30, 138, 3.0, 4)
        spawn_non_sync_object(
            id_bhvBlueCoinJumping,
            E_MODEL_BLUE_COIN,
            o.oPosX, o.oPosY, o.oPosZ,
            function (coin)
                coin.oVelY = math.random(20, 40)
                coin.oForwardVel = 0
            end)

    elseif (intType & INTERACT_BULLY) ~= 0 then
        o.oVelY = 30
        o.oForwardVel = 50
    end
end

function act_corkscrew_conk(m)
    -- visuals
    m.particleFlags = m.particleFlags | PARTICLE_DUST

    -- physics
    common_air_action_step(m, ACT_JUMP_LAND, MARIO_ANIM_FORWARD_SPINNING, AIR_STEP_NONE)

    -- fast ground pound out of it
    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        local rc = set_mario_action(m, ACT_GROUND_POUND, 0)
        m.actionTimer = 5
        return rc
    end

    return 0
end

function act_wario_dash(m)
    m.marioBodyState.eyeState = 5

    -- make sound
    if m.actionTimer == 0 then
        m.actionState = m.actionArg
        play_character_sound(m, CHAR_SOUND_WAH2)
    end

    -- walk once dash is up
    if m.actionTimer > 30 then
        return set_mario_action(m, ACT_WALKING, 0)
    end

    -- physics
    local stepResult = perform_ground_step(m)
    if stepResult == GROUND_STEP_HIT_WALL then
        if m.wall.object == nil or m.wall.object.oInteractType & (INTERACT_BREAKABLE) == 0 then
            return wario_rebound(m, -40, 30)
        end
    elseif stepResult == GROUND_STEP_LEFT_GROUND then
        m.action = ACT_WARIO_AIR_DASH
    end

    set_mario_anim_with_accel(m, MARIO_ANIM_RUNNING_UNUSED, m.forwardVel / 5 * 0x10000)
    smlua_anim_util_set_animation(m.marioObj, "WARIO_ANIM_SHOULDER_BASH")
    play_step_sound(m, 15, 35)

    -- set dash speed
    local speed = 50
    if m.actionTimer > 8 then
        speed = speed - (m.actionTimer - 8)
    end
    mario_set_forward_vel(m, speed)

    -- corkscrew conk
    if (m.input & INPUT_A_PRESSED) ~= 0 then
        set_jumping_action(m, ACT_CORKSCREW_CONK, 0)
        play_character_sound(m, CHAR_SOUND_YAHOO_WAHA_YIPPEE)
    end

    -- slide kick
    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_SLIDE_KICK, 0)
    end

    m.faceAngle.y = m.intendedYaw - approach_s32(math.s16(m.intendedYaw - m.faceAngle.y), 0, 0x400, 0x400)

    m.actionTimer = m.actionTimer + 1
    return 0
end

function act_wario_air_dash(m)
    m.marioBodyState.eyeState = 5

    -- fall once dash is up
    if m.actionTimer > 30 * 5 then
        return set_mario_action(m, ACT_FREEFALL, 0)
    end

    -- physics
    local stepResult = perform_air_step(m, 0)
    update_air_without_turn(m)
    set_mario_animation(m, MARIO_ANIM_FIRST_PUNCH)
    smlua_anim_util_set_animation(m.marioObj, "WARIO_ANIM_SHOULDER_BASH_AIR")
    if stepResult == AIR_STEP_HIT_WALL then
        if m.wall.object and m.wall.object.oInteractType & (INTERACT_BREAKABLE) == 0 then
            return wario_rebound(m, -40, 15)
        end
    elseif stepResult == AIR_STEP_LANDED then
        if check_fall_damage_or_get_stuck(m, ACT_HARD_BACKWARD_GROUND_KB) == 0 then
            if m.actionTimer < 1 then
                m.action = ACT_WARIO_DASH
            else
                set_mario_action(m, ACT_WALKING, 0)
            end
        end
    end

    -- corkscrew conk
    if (m.input & INPUT_A_PRESSED) ~= 0 then
        m.particleFlags = m.particleFlags | PARTICLE_MIST_CIRCLE
        set_jumping_action(m, ACT_CORKSCREW_CONK, 0)
        play_character_sound(m, CHAR_SOUND_YAHOO)
    end

    -- slide kick
    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_SLIDE_KICK, 0)
    end

    m.faceAngle.y = m.intendedYaw - approach_s32(math.s16(m.intendedYaw - m.faceAngle.y), 0, 0x400, 0x400)

    m.actionTimer = m.actionTimer + 1
    return 0
end

function act_wario_dash_rebound(m)
    m.marioBodyState.eyeState = 5

    -- physics
    local stepResult = perform_air_step(m, 0)
    update_air_without_turn(m)
    set_mario_animation(m, MARIO_ANIM_FIRST_PUNCH)
    smlua_anim_util_set_animation(m.marioObj, "WARIO_ANIM_SHOULDER_BASH_AIR")
    if stepResult == AIR_STEP_LANDED then
        if check_fall_damage_or_get_stuck(m, ACT_HARD_BACKWARD_GROUND_KB) == 0 then
            return set_mario_action(m, ACT_FREEFALL_LAND, 0)
        end
    end
    return 0
end

function wario_rebound(m, VelF, VelY)
    mario_set_forward_vel(m, VelF)
    set_camera_shake_from_point(SHAKE_POS_SMALL, m.pos.x, m.pos.y, m.pos.z)
    m.vel.y = VelY
    set_mario_action(m, ACT_WARIO_DASH_REBOUND, 0)
    m.particleFlags = m.particleFlags | PARTICLE_VERTICAL_STAR
    play_sound(SOUND_ACTION_BOUNCE_OFF_OBJECT, m.marioObj.header.gfx.cameraToObject)
    return 0
end

function act_wario_spinning_obj(m)
    local spin = 0

    -- throw object
    if m.playerIndex == 0 and (m.input & INPUT_B_PRESSED) ~= 0 then
        play_character_sound_if_no_flag(m, CHAR_SOUND_WAH2, MARIO_MARIO_SOUND_PLAYED)
        play_sound_if_no_flag(m, SOUND_ACTION_THROW, MARIO_ACTION_SOUND_PLAYED)
        return set_mario_action(m, ACT_RELEASING_BOWSER, 0)
    end

    -- set animation
    if m.playerIndex == 0 and m.angleVel.y == 0 then
        m.actionTimer = m.actionTimer + 1
        if m.actionTimer > 120 then
            return set_mario_action(m, ACT_RELEASING_BOWSER, 1)
        end

        set_mario_animation(m, MARIO_ANIM_HOLDING_BOWSER)
    else
        m.actionTimer = 0
        set_mario_animation(m, MARIO_ANIM_SWINGING_BOWSER)
    end

    -- spin
    if m.intendedMag > 20.0 then
        -- spin = acceleration
        spin = (m.intendedYaw - m.twirlYaw) / 0x20

        if spin < -0x80 then
            spin = -0x80
        end
        if spin > 0x80 then
            spin = 0x80
        end

        m.twirlYaw = m.intendedYaw
        m.angleVel.y = m.angleVel.y + spin

        if m.angleVel.y > 0x1000 then
            m.angleVel.y = 0x1000
        end
        if m.angleVel.y < -0x1000 then
            m.angleVel.y = -0x1000
        end
    elseif m.angleVel.y > -0x750 and m.angleVel.y < 0x750 then
        -- go back to walking
        if m.forwardVel ~= 0 then m.faceAngle.y = atan2s(m.vel.z, m.vel.x) end
        return set_mario_action(m, ACT_HOLD_WALKING, 0)
    else
        -- slow down spin
        m.angleVel.y = approach_s32(m.angleVel.y, 0, 128, 128);
    end

    -- apply spin
    spin = m.faceAngle.y
    m.faceAngle.y = m.faceAngle.y + m.angleVel.y

    -- play sound on overflow
    if m.angleVel.y <= -0x100 and spin < m.faceAngle.y then
        queue_rumble_data_mario(m, 4, 20)
        play_sound(SOUND_OBJ_BOWSER_SPINNING, m.marioObj.header.gfx.cameraToObject)
    end
    if m.angleVel.y >= 0x100 and spin > m.faceAngle.y then
        queue_rumble_data_mario(m, 4, 20)
        play_sound(SOUND_OBJ_BOWSER_SPINNING, m.marioObj.header.gfx.cameraToObject)
    end

    perform_ground_step(m)

    apply_slope_decel(m, 0.1)

    if m.angleVel.y >= 0 then
        m.marioObj.header.gfx.angle.x = -m.angleVel.y
    else
        m.marioObj.header.gfx.angle.x = m.angleVel.y
    end

    return false
end

function wario_update_spin_input(m)
    local e = gCharacterStates[m.playerIndex].wario
    local rawAngle = atan2s(-m.controller.stickY, m.controller.stickX)

    -- prevent issues due to the frame going out of the dead zone registering the last angle as 0
    if e.lastIntendedMag > 0.5 and m.intendedMag > 0.5 then
        local angleOverFrames = 0
        local thisFrameDelta = 0

        local newDirection = e.spinDirection
        local signedOverflow = 0

        if rawAngle < e.stickLastAngle then
            if (e.stickLastAngle - rawAngle) > 0x8000 then
                signedOverflow = 1
            end
            if signedOverflow ~= 0 then
                newDirection = 1
            else
                newDirection = -1
            end
        elseif rawAngle > e.stickLastAngle then
            if (rawAngle - e.stickLastAngle) > 0x8000 then
                signedOverflow = 1
            end
            if signedOverflow ~= 0 then
                newDirection = -1
            else
                newDirection = 1
            end
        end

        if e.spinDirection ~= newDirection then
            for i = 1, ANGLE_QUEUE_SIZE do
                e.angleDeltaQueue[i] = 0
            end
            e.spinDirection = newDirection
        else
            for i = ANGLE_QUEUE_SIZE, 2, -1 do
                e.angleDeltaQueue[i] = e.angleDeltaQueue[i-1]
                angleOverFrames = angleOverFrames + e.angleDeltaQueue[i]
            end
        end

        if e.spinDirection < 0 then
            if signedOverflow ~= 0 then
                thisFrameDelta = math.floor((1.0*e.stickLastAngle + 0x10000) - rawAngle)
            else
                thisFrameDelta = e.stickLastAngle - rawAngle
            end
        elseif e.spinDirection > 0 then
            if signedOverflow ~= 0 then
                thisFrameDelta = math.floor(1.0 * rawAngle + 0x10000 - e.stickLastAngle)
            else
                thisFrameDelta = rawAngle - e.stickLastAngle
            end
        end

        e.angleDeltaQueue[1] = thisFrameDelta
        angleOverFrames = angleOverFrames + thisFrameDelta

        if angleOverFrames >= 0xA000 then
            e.spinBufferTimer = SPIN_TIMER_SUCCESSFUL_INPUT
        end


        -- allow a buffer after a successful input so that you can switch directions
        if e.spinBufferTimer > 0 then
            e.spinInput = e.spinInput + 1
            e.spinBufferTimer = e.spinBufferTimer - 1
        end
    else
        e.spinDirection = 0
        e.spinBufferTimer = 0
        e.spinInput = 0
    end

    e.stickLastAngle = rawAngle
    e.lastIntendedMag = m.intendedMag
end

-- patch wario's hold jump for piledriver
function act_wario_hold_jump(m)
    if (m.marioObj.oInteractStatus & INT_STATUS_MARIO_DROP_OBJECT) ~= 0 then
        return drop_and_set_mario_action(m, ACT_FREEFALL, 0)
    end

    if (m.input & INPUT_B_PRESSED) ~= 0 and (m.heldObj and (m.heldObj.oInteractionSubtype & INT_SUBTYPE_HOLDABLE_NPC) ~= 0) then
        return set_mario_action(m, ACT_AIR_THROW, 0)
    end

    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_PILEDRIVER, 0)
    end

    play_mario_sound(m, SOUND_ACTION_TERRAIN_JUMP, 0)
    common_air_action_step(m, ACT_HOLD_JUMP_LAND, MARIO_ANIM_JUMP_WITH_LIGHT_OBJ,
                           AIR_STEP_CHECK_LEDGE_GRAB)
    return false
end

function act_wario_hold_freefall(m)
    local animation = (m.actionArg == 0) and CHAR_ANIM_FALL_WITH_LIGHT_OBJ or CHAR_ANIM_FALL_FROM_SLIDING_WITH_LIGHT_OBJ

    if (m.marioObj.oInteractStatus & INT_STATUS_MARIO_DROP_OBJECT) ~= 0 then
        return drop_and_set_mario_action(m, ACT_FREEFALL, 0)
    end

    if (m.input & INPUT_B_PRESSED) ~= 0 and (m.heldObj and (m.heldObj.oInteractionSubtype & INT_SUBTYPE_HOLDABLE_NPC) ~= 0) then
        return set_mario_action(m, ACT_AIR_THROW, 0)
    end

    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_PILEDRIVER, 0)
    end

    common_air_action_step(m, ACT_HOLD_FREEFALL_LAND, animation, AIR_STEP_CHECK_LEDGE_GRAB)
    return false
end

function act_piledriver(m)
    if m.actionTimer == 0 then
        play_sound(SOUND_ACTION_SPIN, m.marioObj.header.gfx.cameraToObject)
        play_character_sound(m, CHAR_SOUND_SO_LONGA_BOWSER)
    end
    set_mario_animation(m, MARIO_ANIM_GRAB_BOWSER)

    local stepResult = perform_air_step(m, 0)
    update_air_without_turn(m)
    if stepResult == AIR_STEP_LANDED then
        if should_get_stuck_in_ground(m) ~= 0 then
            queue_rumble_data_mario(m, 5, 80)
            play_sound(SOUND_MARIO_OOOF2, m.marioObj.header.gfx.cameraToObject)
            m.particleFlags = m.particleFlags | PARTICLE_MIST_CIRCLE
            set_mario_action(m, ACT_BUTT_STUCK_IN_GROUND, 0)
        else
            play_mario_heavy_landing_sound(m, SOUND_ACTION_TERRAIN_HEAVY_LANDING)
            if check_fall_damage(m, ACT_HARD_BACKWARD_GROUND_KB) == 0 then
                m.particleFlags = m.particleFlags | PARTICLE_MIST_CIRCLE | PARTICLE_HORIZONTAL_STAR
                -- set facing direction
                -- not part of original Extended Moveset
                m.faceAngle.y = m.intendedYaw
                return set_mario_action(m, ACT_PILEDRIVER_LAND, 0)
            end
        end
    end

    if m.vel.y >= 0 then
        m.angleVel.y = 0
        m.marioObj.header.gfx.angle.y = m.faceAngle.y
    else
        m.angleVel.y = m.angleVel.y + math.abs(m.vel.y) * 0x100
        m.marioObj.header.gfx.angle.y = m.marioObj.header.gfx.angle.y + m.angleVel.y
        m.particleFlags = m.particleFlags | PARTICLE_DUST
    end
    m.actionTimer = m.actionTimer + 1
    return 0
end

function act_piledriver_land(m)
    set_mario_animation(m, MARIO_ANIM_SWINGING_BOWSER)

    local stepResult = perform_ground_step(m)

    if stepResult == GROUND_STEP_LEFT_GROUND then
        m.action = ACT_PILEDRIVER
    end

    -- A debuff so that players can't just bounce up slides.
    if (m.input & INPUT_ABOVE_SLIDE) ~= 0 then
        return set_mario_action(m, ACT_BUTT_SLIDE, 0)
    end

    if (m.input & INPUT_UNKNOWN_10) ~= 0 then
        return drop_and_set_mario_action(m, ACT_SHOCKWAVE_BOUNCE, 0)
    end

    if m.actionTimer > 2 then return set_mario_action(m, ACT_RELEASING_BOWSER, 0) end

	m.actionTimer = m.actionTimer + 1
end

function wario_before_phys_step(m)
    local hScale = 1.0
    local vScale = 1.0

    -- slower on ground
    if (m.action & ACT_FLAG_MOVING) ~= 0 then
        hScale = hScale * 0.9
    end

    -- fixes the momentum bug
    if (m.action == ACT_HOLD_WATER_JUMP) then
        return
    end

    -- faster holding item
    if m.action == ACT_HOLD_WALKING then
        hScale = hScale * 2
    end

    -- make wario sink
    if (m.action & ACT_FLAG_SWIMMING) ~= 0 then
        if m.action ~= ACT_BACKWARD_WATER_KB and
           m.action ~= ACT_FORWARD_WATER_KB and
           m.action ~= ACT_WATER_PLUNGE then
            m.vel.y = m.vel.y - 3
        end
    end

    m.vel.x = m.vel.x * hScale
    m.vel.z = m.vel.z * hScale
end

function wario_on_set_action(m)
    -- air dash
    if m.action == ACT_MOVE_PUNCHING and m.prevAction == ACT_WARIO_DASH then
        local actionTimer = m.actionTimer
        set_mario_action(m, ACT_WARIO_AIR_DASH, 0)
        m.actionTimer = actionTimer
        vec3f_zero(m.vel)
        return
    end

    -- slow down when dash/conk ends
    if (m.prevAction == ACT_WARIO_DASH) or (m.prevAction == ACT_WARIO_AIR_DASH) or (m.prevAction == ACT_CORKSCREW_CONK) then
        if m.action == ACT_CORKSCREW_CONK then
            m.vel.x = 0
            -- nerf the conk when executed in the air
            if (m.prevAction == ACT_WARIO_DASH) then
                set_mario_y_vel_based_on_fspeed(m, 30 , 0.6)
            elseif (m.prevAction == ACT_WARIO_AIR_DASH) then
                m.vel.y = 60.0
            end
        elseif m.action == ACT_SLIDE_KICK then
            mario_set_forward_vel(m, 40)
            m.vel.y = 30.0
        elseif m.forwardVel > 20 then
            mario_set_forward_vel(m, 20)
        end
    end

    if m.action == ACT_PILEDRIVER then
        if m.vel.y < 50 then m.vel.y = 50 end
    end

    -- patch wario's hold jump for piledriver
    if m.action == ACT_HOLD_JUMP then
        m.action = ACT_WARIO_HOLD_JUMP
    end

    if m.action == ACT_HOLD_FREEFALL then
        m.action = ACT_WARIO_HOLD_FREEFALL
    end

    -- less height on other jumps
    if m.action == ACT_JUMP or
       m.action == ACT_DOUBLE_JUMP or
       m.action == ACT_STEEP_JUMP or
       m.action == ACT_RIDING_SHELL_JUMP or
       m.action == ACT_BACKFLIP or
       m.action == ACT_LONG_JUMP or
       m.action == ACT_SIDE_FLIP then

        m.vel.y = m.vel.y * 0.9

        -- prevent from getting stuck on platform
        if m.marioObj.platform then
            m.pos.y = m.pos.y + 10
        end
    end
end

function wario_update(m)
    local hScale = 1.0
    local e = gCharacterStates[m.playerIndex].wario

    wario_update_spin_input(m)

    -- spin around objects
    if m.action == ACT_HOLD_IDLE or m.action == ACT_HOLD_WALKING then
        if e.spinInput > 30 then
            m.twirlYaw = m.intendedYaw
            if e.spinDirection == 1 then
                m.angleVel.y = 3000
            else
                m.angleVel.y = -3000
            end
            m.intendedMag = 21
            return set_mario_action(m, ACT_WARIO_SPINNING_OBJ, 1)
        end
    end

    -- turn heavy objects into light
    if m.action == ACT_HOLD_HEAVY_IDLE then
        return set_mario_action(m, ACT_HOLD_IDLE, 0)
    end

    -- turn dive into dash
    if m.action == ACT_DIVE and m.prevAction == ACT_WALKING then
        if (m.controller.buttonPressed & B_BUTTON) ~= 0 then
            m.actionTimer = 0
            return set_mario_action(m, ACT_WARIO_DASH, 0)
        end
    end

    -- shake camera
    if m.action == ACT_GROUND_POUND_LAND then
        set_camera_shake_from_point(SHAKE_POS_MEDIUM, m.pos.x, m.pos.y, m.pos.z)
        m.squishTimer = 5
    end

    -- faster ground pound
    if m.action == ACT_GROUND_POUND then
        m.vel.y = m.vel.y * 1.3
    end

    -- decrease player damage
    if m.hurtCounter > e.lastHurtCounter and m.action ~= ACT_LAVA_BOOST then
        m.hurtCounter = math.max(3, m.hurtCounter - 4)
    end
    e.lastHurtCounter = m.hurtCounter

    m.vel.x = m.vel.x * hScale
    m.vel.z = m.vel.z * hScale
end

local dashActions = {
    [ACT_WARIO_DASH] = 30,
    [ACT_WARIO_AIR_DASH] = 15
}
function wario_on_interact(m, o, intType)
    local damagableTypes = (INTERACT_BOUNCE_TOP | INTERACT_BOUNCE_TOP2 | INTERACT_HIT_FROM_BELOW | 2097152 | INTERACT_KOOPA |
    INTERACT_BREAKABLE | INTERACT_GRABBABLE | INTERACT_BULLY)

    -- rebound from bash and interact
    local force = dashActions[m.action]
    if force and (intType & damagableTypes) ~= 0 then
        dash_attacks(m, o, intType)

        wario_rebound(m, -40, force)
        return false
    end
end

function wario_on_pvp_attack(a, v)
    local force = dashActions[a.action]
    if force then
        wario_rebound(a, -40, force)
    end
end

hook_mario_action(ACT_WARIO_DASH,          act_wario_dash, INT_KICK)
hook_mario_action(ACT_WARIO_AIR_DASH,      act_wario_air_dash, INT_KICK)
hook_mario_action(ACT_WARIO_DASH_REBOUND,  act_wario_dash_rebound)
hook_mario_action(ACT_CORKSCREW_CONK,      act_corkscrew_conk, INT_FAST_ATTACK_OR_SHELL)
hook_mario_action(ACT_WARIO_SPINNING_OBJ,  act_wario_spinning_obj)
hook_mario_action(ACT_PILEDRIVER,          act_piledriver)
hook_mario_action(ACT_PILEDRIVER_LAND,     act_piledriver_land, INT_GROUND_POUND_OR_TWIRL)
hook_mario_action(ACT_WARIO_HOLD_JUMP,     act_wario_hold_jump)
hook_mario_action(ACT_WARIO_HOLD_FREEFALL, act_wario_hold_freefall)

return {
    { HOOK_MARIO_UPDATE, wario_update },
    { HOOK_BEFORE_PHYS_STEP, wario_before_phys_step },
    { HOOK_ON_SET_MARIO_ACTION, wario_on_set_action },
    { HOOK_ON_INTERACT, wario_on_interact },
    { HOOK_ON_PVP_ATTACK, wario_on_pvp_attack }
}