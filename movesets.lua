local charSelect, OmmEnabled = charSelect, OmmEnabled
if not charSelect then return end

ANGLE_QUEUE_SIZE = 9
SPIN_TIMER_SUCCESSFUL_INPUT = 4

gEventTable = {}
gCharSelectEventTable = {}

gStateExtras = {}
for i = 0, (MAX_PLAYERS - 1) do
    gStateExtras[i] = {}
    local m = gMarioStates[i]
    local e = gStateExtras[i]
    e.prevPos = {}
    e.prevPos.x = 0
    e.prevPos.y = 0
    e.prevPos.z = 0
    e.angleDeltaQueue = {}
    for j = 0, (ANGLE_QUEUE_SIZE - 1) do e.angleDeltaQueue[j] = 0 end
    e.lastAction = m.action
    e.animFrame = 0
    e.animArg = 0
    e.scuttle = 0
    e.averageForwardVel = 0
    e.boostTimer = 0
    e.rotAngle = 0
    e.lastHurtCounter = 0
    e.stickLastAngle = 0
    e.spinDirection = 0
    e.spinBufferTimer = 0
    e.spinInput = 0
    e.lastIntendedMag = 0
    e.swims = 0
    -- birdo
    e.spitTimer = 0
    e.framesSinceShoot = 255
    e.flameCharge = 0
    e.spinCharge = 0
end

local princessFloatActs = {
    [ACT_JUMP]          = true,
    [ACT_DOUBLE_JUMP]   = true,
    [ACT_TRIPLE_JUMP]   = true,
    [ACT_LONG_JUMP]     = true,
    [ACT_BACKFLIP]      = true,
    [ACT_SIDE_FLIP]     = true,
    [ACT_WALL_KICK_AIR] = true,
}

--- @param m MarioState
--- @param name string
--- @param accel? number
--- Plays a custom animation for MarioState `m`
local function play_custom_anim(m, name, accel)
    if not accel then
        accel = 0x10000
    else
        accel = accel * 0x10000
    end

    m.marioObj.header.gfx.animInfo.animAccel = accel

    if (smlua_anim_util_get_current_animation_name(m.marioObj) ~= name or m.marioObj.header.gfx.animInfo.animID ~= -1) then
        m.marioObj.header.gfx.animInfo.animFrame = 1
        set_anim_to_frame(m, 0)
    end

    -- jank may occur without this line
    m.marioObj.header.gfx.animInfo.animID = -1

    smlua_anim_util_set_animation(m.marioObj, name)
end

--- @class bitsize : integer

--- @param x integer
--- @param size bitsize
--- @return integer
--- Converts any integer to a signed integer
local function tosigned_integer(x, size)
    x = math.floor(x) & (1 << size) - 1
    return x - ((x & (1 << (size - 1))) << 1)
end

--- @param x integer
--- @param size bitsize
--- @return integer
--- Converts any integer to an unsigned integer
local function tounsigned_integer(x, size)
    return math.floor(x) & (1 << size) - 1
end

local SOUND_SPIT = audio_sample_load("spit.ogg") -- Load audio sample

-----------------------
-- Toadette Movement --
-----------------------

function toadette_before_phys_step(m)
    local hScale = 1.0
    local vScale = 1.0

    -- faster ground movement
    if (m.action & ACT_FLAG_MOVING) ~= 0 then
        hScale = hScale * 1.05
    end

    -- slower holding item
    if m.heldObj then
        m.vel.y = m.vel.y - 2.0
        hScale = hScale * 0.9
        if (m.action & ACT_FLAG_AIR) ~= 0 then
            hScale = hScale * 0.9
        end
    end

    m.vel.x = m.vel.x * hScale
    m.vel.y = m.vel.y * vScale
    m.vel.z = m.vel.z * hScale
end

function toadette_on_set_action(m)
    local e = gStateExtras[m.playerIndex]

    -- wall kick height based on how fast toadette is going
    if m.action == ACT_WALL_KICK_AIR and m.prevAction ~= ACT_HOLDING_POLE and m.prevAction ~= ACT_CLIMBING_POLE then
        m.vel.y = m.vel.y * 0.8
        m.vel.y = m.vel.y + e.averageForwardVel * 0.8
        return
    end

    -- more distance on dive and long jump
    if m.action == ACT_DIVE or m.action == ACT_LONG_JUMP then
        m.forwardVel = m.forwardVel * 1
    end

    -- less height on jumps
    if m.action == ACT_JUMP or m.action == ACT_DOUBLE_JUMP or m.action == ACT_TRIPLE_JUMP or m.action == ACT_SPECIAL_TRIPLE_JUMP or m.action == ACT_STEEP_JUMP or m.action == ACT_RIDING_SHELL_JUMP or m.action == ACT_BACKFLIP or m.action == ACT_WALL_KICK_AIR or m.action == ACT_LONG_JUMP then
        m.vel.y = m.vel.y * 1

        -- prevent from getting stuck on platform
        if m.marioObj.platform ~= nil then
            m.pos.y = m.pos.y + 10
        end
    elseif m.action == ACT_SIDE_FLIP then
        m.vel.y = m.vel.y * 0.86

        -- prevent from getting stuck on platform
        if m.marioObj.platform ~= nil then
            m.pos.y = m.pos.y + 10
        end
    end
end

function toadette_update(m)
    local e = gStateExtras[m.playerIndex]

    -- track average forward velocity
    if e.averageForwardVel > m.forwardVel then
        e.averageForwardVel = e.averageForwardVel * 0.93 + m.forwardVel * 0.07
    else
        e.averageForwardVel = m.forwardVel
    end

    -- keep your momentum for a while
    if m.action == ACT_WALKING and m.forwardVel > 30 then
        mario_set_forward_vel(m, m.forwardVel + 0.8)
    end

    -- faster flip during ground pound
    if m.action == ACT_GROUND_POUND then
        m.marioObj.header.gfx.animInfo.animAccel = 32768 * 4
        if m.actionTimer < 10 then
            m.actionTimer = m.actionTimer + 1
        end
    end

    -- Floaty
    if m.vel.y < 0 and (m.action == ACT_JUMP or m.action == ACT_DOUBLE_JUMP or m.action == ACT_TRIPLE_JUMP or m.action == ACT_HOLD_JUMP) then
        m.vel.y = m.vel.y + 0.9
    end
end

-----------------
-- Peach Float --
-----------------

_G.ACT_PEACH_FLOAT = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_MOVING)

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

_G.ACT_DAISY_JUMP = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_MOVING)

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
-- Yoshi Flutter --
-------------------

-- Flutterable actions, these don't match the DS flutterable actions
local flutterWhiteList = {
    [ACT_JUMP]        = true,
    [ACT_DOUBLE_JUMP] = true,
    [ACT_TRIPLE_JUMP] = true,
    [ACT_LONG_JUMP]   = true,
    [ACT_FREEFALL]    = true
}

_G.ACT_FLUTTER = allocate_mario_action(ACT_FLAG_AIR | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_GROUP_AIRBORNE)
YOSHI_ANIM_FLUTTER = 'yoshi_flutter_jump'
local YOSHI_SOUND_FLUTTER = audio_sample_load("yoshi_flutter.ogg") -- Load audio sample

---@param m MarioState
function act_flutter(m)

    -- End flutter after 1 second
    if m.actionTimer >= 30 or (m.input & INPUT_A_DOWN) == 0 then
        if m.actionTimer < 30 then
            audio_sample_stop(YOSHI_SOUND_FLUTTER) -- Stop sample after letting go of A
        end
        return set_mario_action(m, ACT_FREEFALL, 0)
    end

    local ended = common_air_action_step(m, ACT_JUMP_LAND, CHAR_ANIM_RUNNING_UNUSED, 0) ~= 0 -- Checks if the action ended earlier due to forced actions like bonking or landing

    if ended then
        audio_sample_stop(YOSHI_SOUND_FLUTTER) -- Stop sample after landing
    elseif m.actionTimer == 0 then
        audio_sample_play(YOSHI_SOUND_FLUTTER, m.pos, 1) -- Play audio sample
    end

    smlua_anim_util_set_animation(m.marioObj, YOSHI_ANIM_FLUTTER) -- Sets the animation

    m.marioBodyState.eyeState = MARIO_EYES_CLOSED -- Eye State
    m.vel.y = approach_f32(m.vel.y, m.actionTimer / 1.25, 8, 8) -- Height increases faster as the 1 second passes
    m.marioObj.header.gfx.animInfo.animAccel = 65536 * 2 -- Animation Speed

    m.actionTimer = m.actionTimer + 1
    return false
end

---@param m MarioState
function yoshi_update(m)
    if m.prevAction & ACT_FLAG_AIR == 0 and m.action & ACT_FLAG_AIR ~= 0 and flutterWhiteList[m.action] and m.controller.buttonDown & A_BUTTON ~= 0 and m.vel.y < 0 then
        set_mario_action(m, ACT_FLUTTER, 0)
    end
end

hook_mario_action(ACT_FLUTTER, act_flutter)

---------------
-- Birdo Egg --
---------------

_G.ACT_BIRDO_HOLD_WALKING  = allocate_mario_action(ACT_FLAG_MOVING | ACT_GROUP_OBJECT)
_G.ACT_BIRDO_SPIT_EGG      = allocate_mario_action(ACT_FLAG_STATIONARY | ACT_FLAG_IDLE | ACT_FLAG_ALLOW_FIRST_PERSON | ACT_FLAG_PAUSE_EXIT)
_G.ACT_BIRDO_SPIT_EGG_WALK = allocate_mario_action(ACT_FLAG_MOVING | ACT_FLAG_ALLOW_FIRST_PERSON)
_G.ACT_BIRDO_SPIT_EGG_AIR  = allocate_mario_action(ACT_FLAG_AIR | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_CONTROL_JUMP_HEIGHT)

-- this version works more like regular walking
---@param m MarioState
local function act_birdo_hold_walking(m)

    local startYaw = m.faceAngle.y

    if m.heldObj and m.heldObj.behavior == get_behavior_from_id(id_bhvJumpingBox) then
        return set_mario_action(m, ACT_CRAZY_BOX_BOUNCE, 0)
    end

    if (m.marioObj.oInteractStatus & INT_STATUS_MARIO_DROP_OBJECT) ~= 0 then
        return drop_and_set_mario_action(m, ACT_WALKING, 0)
    end

    if (should_begin_sliding(m)) ~= 0 then
        return set_mario_action(m, ACT_HOLD_BEGIN_SLIDING, 0)
    end

    if (m.input & INPUT_B_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_THROWING, 0)
    end

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        return set_jumping_action(m, ACT_HOLD_JUMP, 0)
    end

    if (m.input & INPUT_ZERO_MOVEMENT) ~= 0 then
        return set_mario_action(m, ACT_HOLD_DECELERATING, 0)
    end

    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        return drop_and_set_mario_action(m, ACT_CROUCH_SLIDE, 0)
    end

    update_walking_speed(m) -- normal walking speed

    local result = perform_ground_step(m)
    if result == GROUND_STEP_LEFT_GROUND then
        set_mario_action(m, ACT_HOLD_FREEFALL, 0)
    elseif result == GROUND_STEP_HIT_WALL then
        if (m.forwardVel > 16) then
            mario_set_forward_vel(m, 16)
        end
    end

    -- for the animation, temporarily read birdo's speed as lower so it looks less goofy
    local prevForwardVel = m.forwardVel
    local prevMag = m.intendedMag
    m.forwardVel = m.forwardVel * 0.6
    m.intendedMag = m.intendedMag * 0.6
    anim_and_audio_for_hold_walk(m)
    m.forwardVel = prevForwardVel
    m.intendedMag = prevMag


    -- tilt body
    local dYaw = m.faceAngle.y - startYaw
    local val02 = -(dYaw * m.forwardVel / 12)
    local val00 = (m.forwardVel * 170)

    val02 = math.clamp(val02, -0x1555, 0x1555)
    val00 = math.clamp(val02, 0, 0x1555)

    m.marioBodyState.allowPartRotation = 1
    m.marioBodyState.torsoAngle.z = approach_s32(m.marioBodyState.torsoAngle.z, val02, 0x400, 0x400)
    m.marioBodyState.torsoAngle.x = approach_s32(m.marioBodyState.torsoAngle.x, val00, 0x400, 0x400)

    if (0.4 * m.intendedMag - m.forwardVel > 10) then
        set_mario_particle_flags(m, PARTICLE_DUST, 0)
    end

    return 0
end

-- spit egg actions
local function act_birdo_spit_egg(m)
    local e = gStateExtras[m.playerIndex]
    if (m.quicksandDepth > 30) then
        return set_mario_action(m, ACT_IN_QUICKSAND, 0)
    end

    if m.actionState == 0 then
        play_custom_anim(m, "BIRDO_ANIM_IDLE_TO_AIM_IDLE")
        if is_anim_past_end(m) ~= 0 then
            m.actionState = 1
        end
    elseif e.flameCharge == 0 and e.framesSinceShoot > 10 then
        play_custom_anim(m, "BIRDO_ANIM_AIM_IDLE_TO_IDLE")
        if is_anim_past_end(m) ~= 0 then
            return set_mario_action(m, ACT_IDLE, 0)
        end
    else
        play_custom_anim(m, "BIRDO_ANIM_AIM_IDLE")
    end
    mario_drop_held_object(m)

    m.actionTimer = m.actionTimer + 1

    local oldActTimer = m.actionTimer
    if (m.input & INPUT_NONZERO_ANALOG) ~= 0 then
        mario_set_forward_vel(m, 0)
        local result = set_mario_action(m, ACT_BIRDO_SPIT_EGG_WALK, 0)
        m.actionTimer = oldActTimer
        return result
    elseif (check_common_idle_cancels(m) ~= 0) then
        if m.action & ACT_FLAG_AIR ~= 0 then
            mario_set_forward_vel(m, 0)
            set_mario_action(m, ACT_BIRDO_SPIT_EGG_AIR, 1)
            if m.vel.y <= 0 then
                m.actionArg = 0
            end
            m.actionTimer = oldActTimer
        end
        return 1
    end

    mario_set_forward_vel(m, 0)
    perform_ground_step(m)
    return 0
end

local function act_birdo_spit_egg_walk(m)
    if not m then return 0 end
    local e = gStateExtras[m.playerIndex]
    local mBody = m.marioBodyState

    mario_drop_held_object(m)

    m.actionTimer = m.actionTimer + 1
    if e.flameCharge == 0 and e.framesSinceShoot > 10 then
        if m.forwardVel < 0 then
            m.forwardVel = m.intendedMag
            m.faceAngle.y = m.intendedYaw
            return set_mario_action(m, ACT_FINISH_TURNING_AROUND, 0)
        end
        m.forwardVel = m.intendedMag
        m.faceAngle.y = m.intendedYaw
        return set_mario_action(m, ACT_WALKING, 0)
    end

    if mario_floor_is_slippery(m) ~= 0 then
        return set_mario_action(m, ACT_WALKING, 0)
    end

    if (should_begin_sliding(m)) ~= 0 then
        return set_mario_action(m, ACT_BEGIN_SLIDING, 0)
    end

    if (m.input & INPUT_FIRST_PERSON) ~= 0 then
        m.intendedMag = 0
        if m.slideVelX == 0 and m.slideVelZ == 0 then
            return begin_braking_action(m)
        end
    end

    if (m.input & INPUT_ZERO_MOVEMENT) ~= 0 and m.slideVelX == 0 and m.slideVelZ == 0 then
        local oldActTimer = m.actionTimer
        local result = set_mario_action(m, ACT_BIRDO_SPIT_EGG, 0)
        m.actionTimer = oldActTimer
        return result
    end

    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_CROUCH_SLIDE, 0)
    end

    -- strafe movement
    local newVelX = sins(m.intendedYaw) * m.intendedMag
    local newVelZ = coss(m.intendedYaw) * m.intendedMag
    m.slideVelX = approach_f32(m.slideVelX, newVelX, 4, 4)
    m.slideVelZ = approach_f32(m.slideVelZ, newVelZ, 4, 4)
    m.vel.x, m.vel.z = m.slideVelX, m.slideVelZ
    m.forwardVel = math.sqrt(m.vel.x ^ 2 + m.vel.z ^ 2)

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        set_mario_y_vel_based_on_fspeed(m, 42, 0.25)
        m.slideVelX = m.slideVelX * 0.8
        m.slideVelZ = m.slideVelZ * 0.8
        m.vel.x, m.vel.z = m.slideVelX, m.slideVelZ
        m.forwardVel = m.forwardVel * 0.8
        local oldActTimer = m.actionTimer
        local result = set_mario_action(m, ACT_BIRDO_SPIT_EGG_AIR, 1)
        m.actionTimer = oldActTimer
        return result
    end

    local result = (perform_ground_step(m))
    if result == GROUND_STEP_LEFT_GROUND then
        m.vel.y = 0
        local oldActTimer = m.actionTimer
        set_mario_action(m, ACT_BIRDO_SPIT_EGG_AIR, 0)
        m.actionTimer = oldActTimer
        --set_character_animation(m, CHAR_ANIM_GENERAL_FALL)
    elseif result == GROUND_STEP_NONE then
        --anim_and_audio_for_walk(m)
        play_step_sound(m, 10, 49)

        local dYaw = tosigned_integer(m.faceAngle.y - m.intendedYaw, 16)
        play_custom_anim(m, "BIRDO_ANIM_AIM_WALK", m.forwardVel / 4)

        mBody.allowPartRotation = 1
        m.marioObj.header.gfx.angle.y = m.intendedYaw
        m.marioObj.header.gfx.animInfo.curAnim.flags = m.marioObj.header.gfx.animInfo.curAnim.flags & ~ANIM_FLAG_BACKWARD
        if math.abs(dYaw) > 0x4000 then
            m.marioObj.header.gfx.angle.y = m.intendedYaw - 0x8000
            m.marioObj.header.gfx.animInfo.curAnim.flags = ANIM_FLAG_BACKWARD
        end

        mBody.torsoAngle.y = tosigned_integer(m.faceAngle.y - m.marioObj.header.gfx.angle.y, 16) * 0.4
        mBody.headAngle.y =  m.faceAngle.y - m.marioObj.header.gfx.angle.y - mBody.torsoAngle.y

        if m.intendedMag - m.forwardVel > 16 then
            set_mario_particle_flags(m, PARTICLE_DUST, 0)
        end
    end

    check_ledge_climb_down(m)
    --tilt_body_walking(m, startYaw)
    return 0
end

---@param m MarioState
local function act_birdo_spit_egg_air(m)
    local e = gStateExtras[m.playerIndex]

    play_custom_anim(m, "BIRDO_ANIM_AIM_JUMP")
    if m.actionArg ~= 1 then
        set_anim_to_frame(m, m.marioObj.header.gfx.animInfo.curAnim.loopEnd)
    else
        play_mario_sound(m, SOUND_ACTION_TERRAIN_JUMP, 0)
    end

    m.actionTimer = m.actionTimer + 1

    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_GROUND_POUND, 0)
    end

    -- air strafe
    local newVelX = sins(m.intendedYaw) * m.intendedMag
    local newVelZ = coss(m.intendedYaw) * m.intendedMag
    m.slideVelX = approach_f32(m.slideVelX, newVelX, 1, 1)
    m.slideVelZ = approach_f32(m.slideVelZ, newVelZ, 1, 1)
    m.vel.x, m.vel.z = m.slideVelX, m.slideVelZ
    m.forwardVel = m.slideVelX * sins(m.faceAngle.y) + m.slideVelZ * coss(m.faceAngle.y)
    --local absSpeed = math.max(math.abs(m.slideVelX), math.abs(m.slideVelZ))

    local result = (perform_air_step(m, 0))
    if result == AIR_STEP_LANDED then
        if check_fall_damage_or_get_stuck(m, ACT_HARD_BACKWARD_GROUND_KB) ~= 0 then
            return 1
        elseif e.flameCharge == 0 and e.framesSinceShoot > 10 then
            set_mario_action(m, ACT_FREEFALL_LAND, 0)
        else
            local oldActTimer = m.actionTimer
            set_mario_action(m, ACT_BIRDO_SPIT_EGG_WALK, 0)
            m.actionTimer = oldActTimer
        end
        return 1
    elseif result == AIR_STEP_HIT_WALL then
        mario_set_forward_vel(m, 0)
    elseif result == AIR_STEP_HIT_LAVA_WALL then
        lava_boost_on_wall(m)
    end

    return 0
end

-- egg object
E_MODEL_EGG = smlua_model_util_get_id("egg_geo")
---@param o Object
function bhv_birdo_egg_init(o)
    o.oFlags = (OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE | OBJ_FLAG_SET_FACE_YAW_TO_MOVE_YAW | OBJ_FLAG_HOLDABLE | OBJ_FLAG_COMPUTE_DIST_TO_MARIO)
    o.oFaceAngleRoll = 0
    o.oMoveAngleRoll = 0
    o.oGravity = 0
    o.oBounciness = 0
    o.oFriction = 1
    o.oDragStrength = 0
    o.oBuoyancy = 0
    o.oWallHitboxRadius = 60
    o.oVelY = 0

    o.collisionData = smlua_collision_util_get("egg_collision")

    local hitbox = get_temp_object_hitbox()
    hitbox.interactType = INTERACT_DAMAGE
    hitbox.hurtboxRadius = 60
    hitbox.hurtboxHeight = 80
    hitbox.downOffset = 80
    hitbox.radius = 60
    hitbox.height = 80
    hitbox.damageOrCoinValue = 1
    if o.oBehParams ~= 0 then
        hitbox.interactType = INTERACT_FLAME
        hitbox.hurtboxRadius = 30
        hitbox.downOffset = 0
        obj_set_billboard(o)
        o.header.gfx.scale.x = 3
        o.header.gfx.scale.y = 3
        o.header.gfx.scale.z = 3
    end
    obj_set_hitbox(o, hitbox)
    o.oIntangibleTimer = 10

    -- do manual shadow, otherwise the shadow renders on top of itself
    o.header.gfx.disableAutomaticShadowPos = true
    o.header.gfx.shadowPos.x = o.oPosX
    o.header.gfx.shadowPos.y = o.oPosY - 50
    o.header.gfx.shadowPos.z = o.oPosZ

    network_init_object(o, true, { 'globalPlayerIndex' })
end

---@param o Object
function bhv_birdo_egg_loop(o)
    if o.oBehParams ~= 0 then
        o.oAnimState = o.oAnimState + 1
    end

    if o.oHeldState == HELD_FREE then
        cur_obj_enable_rendering()
        if o.oAction == 0 then
            o.oGravity = 0
        else
            o.oMoveAnglePitch = 0
            o.oFaceAnglePitch = 0
            o.oGravity = -2
        end

        cur_obj_update_floor_and_walls()
        local oldForwardVel = o.oForwardVel
        if o.oAction == 0 then
            obj_compute_vel_from_move_pitch(o.oForwardVel)
        end
        cur_obj_move_standard(60)
        o.oForwardVel = oldForwardVel

        local defaultVel = 20
        if o.oBehParams ~= 0 then
            defaultVel = 40
        end
        if o.oAction == 0 and o.oForwardVel > defaultVel then
            o.oForwardVel = approach_f32(o.oForwardVel, defaultVel, 3, 3)
        end

        -- manual object collision
        local dieFromCollision = false
        o.numCollidedObjs = obj_attack_collided_from_other_object(o)
        if o.numCollidedObjs ~= 0 and o.oBehParams == 0 then
            dieFromCollision = true
        end
        if o.oDistanceToMario < 2000 then
            local obj_lists_check = {
                OBJ_LIST_GENACTOR,
                OBJ_LIST_PUSHABLE,
                OBJ_LIST_SURFACE,
            }
            for i, list in ipairs(obj_lists_check) do
                local o2 = obj_get_first(list)
                while o2 and o.numCollidedObjs < 4 do
                    if o ~= o2 and obj_check_hitbox_overlap(o, o2) and o2.oInteractType ~= INTERACT_DOOR and o2.oInteractType ~= INTERACT_WARP_DOOR and o2.oInteractType ~= INTERACT_TEXT then
                        if obj_has_behavior_id(o2, id_bhvBowser) == 0 then
                            o2.oInteractStatus = o2.oInteractStatus | ATTACK_PUNCH | INT_STATUS_WAS_ATTACKED | INT_STATUS_INTERACTED | INT_STATUS_TOUCHED_BOB_OMB
                        end
                        o2.numCollidedObjs = o2.numCollidedObjs - 1 -- prevent game crash
                        if o.oBehParams == 0 or birdo_fireball_interaction(o2, o) then
                            dieFromCollision = true
                        end
                    end
                    o2 = obj_get_next(o2)
                end
                if o.numCollidedObjs >= 4 then break end
            end
        end

        -- surface collision
        if o.oAction == 0 and o.oBehParams == 0 and o.oMoveFlags & OBJ_MOVE_MASK_IN_WATER == 0 then
            local m0 = gMarioStates[0]
            load_object_collision_model()
            if cur_obj_is_mario_on_platform() ~= 0 then
                if (m0.action == ACT_PUNCHING or m0.action == ACT_MOVE_PUNCHING) then
                    -- pick up egg
                    m0.heldObj = o
                    m0.marioBodyState.grabPos = GRAB_POS_LIGHT_OBJ
                    o.heldByPlayerIndex = 0
                    o.oHeldState = HELD_HELD
                    set_mario_action(m0, ACT_HOLD_FREEFALL, 0)
                    if (o.oSyncID ~= 0) then network_send_object(o, false) end
                elseif (m0.prevAction & ACT_FLAG_AIR) ~= 0 then -- prevent falling off of egg easily
                    m0.pos.x = o.oPosX
                    m0.pos.z = o.oPosZ
                end
            end
        end

        if dieFromCollision or o.oMoveFlags & (OBJ_MOVE_HIT_WALL | OBJ_MOVE_UNDERWATER_ON_GROUND | OBJ_MOVE_MASK_ON_GROUND) ~= 0 or o.oTimer > 120 then
            o.numCollidedObjs = 0
            spawn_mist_particles()
            obj_mark_for_deletion(o)
            o.header.gfx.disableAutomaticShadowPos = false
        end
        o.oInteractStatus = 0
        o.numCollidedObjs = 0
    elseif o.oHeldState == HELD_HELD then
        o.oFaceAnglePitch = 0
        o.oMoveAnglePitch = 0
        o.oInteractType = INTERACT_GRABBABLE
        cur_obj_disable_rendering_and_become_intangible(o)
    elseif o.oHeldState == HELD_THROWN then
        o.oFaceAnglePitch = 0
        o.oMoveAnglePitch = 0
        o.oInteractType = INTERACT_DAMAGE
        cur_obj_enable_rendering_and_become_tangible(o)
        cur_obj_change_action(1)
        local m = gMarioStates[o.heldByPlayerIndex]
        o.oForwardVel = math.max(m.forwardVel + 15, 40)
        o.oVelY = 10
        o.oTimer = 0
        o.oHeldState = HELD_FREE
        o.oIntangibleTimer = 10
    elseif o.oHeldState == HELD_DROPPED then
        spawn_mist_particles()
        obj_mark_for_deletion(o)
        o.header.gfx.disableAutomaticShadowPos = false
    end

    -- do manual shadow, otherwise the shadow renders on top of itself
    if o.activeFlags & ACTIVE_FLAG_DEACTIVATED == 0 then
        o.header.gfx.disableAutomaticShadowPos = true
        o.header.gfx.shadowPos.x = o.oPosX
        o.header.gfx.shadowPos.y = o.oPosY - 50
        o.header.gfx.shadowPos.z = o.oPosZ
    end
end

id_bhvBirdoEgg = hook_behavior(nil, OBJ_LIST_SURFACE, true, bhv_birdo_egg_init, bhv_birdo_egg_loop, "bhvBirdoEgg")

---@param m MarioState
function birdo_update(m)
    -- spit egg
    local e = gStateExtras[m.playerIndex]
    local inSpitAction = (m.action == ACT_BIRDO_SPIT_EGG or m.action == ACT_BIRDO_SPIT_EGG_WALK or m.action == ACT_BIRDO_SPIT_EGG_AIR or m.action == ACT_FIRST_PERSON or m.action == ACT_WATER_PUNCH or m.action == ACT_FLYING)
    local headRot = m.marioBodyState.headAngle

    if m.controller.buttonPressed & B_BUTTON ~= 0 and inSpitAction then
        -- when mashing B, stay in spit action
        e.framesSinceShoot = 0
        if e.spitTimer == 0 then
            e.flameCharge = 0
        end
    else
        -- handle shooting repeatedly/charging
        if e.framesSinceShoot ~= 255 then
            e.framesSinceShoot = e.framesSinceShoot + 1
        end
        if m.controller.buttonDown & B_BUTTON ~= 0 then
            if inSpitAction then
                e.flameCharge = e.flameCharge + 1
            end
        elseif e.spitTimer < 25 then
            if e.flameCharge >= 30 then
                e.framesSinceShoot = 0 -- shoot fireball
            else
                e.flameCharge = 0
            end
        end
    end

    if (e.framesSinceShoot <= 10 or e.flameCharge ~= 0) and (not m.heldObj) and inSpitAction then
        local canShoot = true
        local eggCount = 0
        local gIndex = network_global_index_from_local(m.playerIndex)
        local egg = obj_get_first_with_behavior_id(id_bhvBirdoEgg)
        while egg do
            if egg.oAction == 0 and egg.oHeldState == HELD_FREE and egg.globalPlayerIndex == gIndex then
                eggCount = eggCount + 1
                if eggCount >= 3 then -- max of 3 eggs/fireballs per player
                    canShoot = false
                    break
                end
            end
            egg = obj_get_next_with_same_behavior_id(egg)
        end

        if e.spitTimer ~= 0 then
            e.spitTimer = e.spitTimer - 1
            m.marioBodyState.allowPartRotation = 1
            if e.spitTimer > 24 then
                headRot.x = approach_f32(headRot.x, degrees_to_sm64(-30), degrees_to_sm64(10), degrees_to_sm64(10))
            else
                headRot.x = approach_f32(headRot.x, degrees_to_sm64(0), degrees_to_sm64(3.5), degrees_to_sm64(3.5))
            end
        end
        if e.spitTimer == 0 and canShoot and e.framesSinceShoot <= 10 then
            m.actionTimer = 0
            m.actionArg = 0
        end

        local mouthPos = {x = 0, y = 0, z = 0}
        local yaw = m.faceAngle.y
        local pitch = 0
        if canShoot then
            -- when swimming, flying, or in first person, allow shooting in any direction (UNUSED)
            if m.action == ACT_FIRST_PERSON then
                yaw = m.statusForCamera.headRotation.y + yaw
                pitch = m.statusForCamera.headRotation.x
                mouthPos.x = m.pos.x + sins(yaw) * 60 * coss(pitch)
                mouthPos.y = m.pos.y + 120 - sins(pitch) * 120
                mouthPos.z = m.pos.z + coss(yaw) * 60 * coss(pitch)
            elseif m.action & ACT_FLAG_SWIMMING_OR_FLYING ~= 0 then
                pitch = -m.faceAngle.x
                if pitch < 0 then
                    mouthPos.x = m.pos.x + sins(yaw) * 80 * coss(pitch)
                    mouthPos.y = m.pos.y + 120
                    mouthPos.z = m.pos.z + coss(yaw) * 80 * coss(pitch)
                else
                    mouthPos.x = m.pos.x + sins(yaw) * 80
                    mouthPos.y = m.pos.y + 120 - sins(pitch) * 150
                    mouthPos.z = m.pos.z + coss(yaw) * 80
                end
            else
                mouthPos.x = m.marioBodyState.headPos.x + sins(yaw+m.marioBodyState.headAngle.y) * 60
                mouthPos.y = m.marioBodyState.headPos.y + 20
                mouthPos.z = m.marioBodyState.headPos.z + coss(yaw+m.marioBodyState.headAngle.y) * 60
            end
        end

        if canShoot and e.spitTimer == 0 and e.flameCharge >= 30 and m.action & ACT_FLAG_SWIMMING == 0 then
            spawn_non_sync_object(id_bhvKoopaShellFlame, E_MODEL_RED_FLAME,
            mouthPos.x,
            mouthPos.y,
            mouthPos.z,
            function(o)
                o.oKoopaShellFlameUnkF8 = 2
                o.oMoveAngleYaw = math.random(0, 0xFFFF)
                o.oVelY = math.random(1, 10)
                o.oAnimState = math.random(1, 10)
                o.oGravity = -4.0
                o.oTimer = 1
                o.oForwardVel = math.random(1, 10)
            end)
            play_sound(SOUND_AIR_BLOW_FIRE, m.marioObj.header.gfx.cameraToObject)
        end

        if canShoot and e.spitTimer == 0 and e.framesSinceShoot <= 10 then
            e.spitTimer = 30
        elseif e.spitTimer == 25 then
            local model = E_MODEL_EGG
            local isFireball = (e.flameCharge >= 30)
            if isFireball then
                model = E_MODEL_RED_FLAME
                e.flameCharge = 0
            end

            if not isFireball then
                audio_sample_play(SOUND_SPIT, m.pos, 1) -- Play audio sample
            else
                play_sound(SOUND_AIR_BOWSER_SPIT_FIRE, m.marioObj.header.gfx.cameraToObject)
            end

            if m.playerIndex == 0 then
                local eggVel = m.forwardVel * 2 + 25
                -- add double floor velocity to prevent being able to platform on eggs forever
                if m.floor and m.floor.object and m.floor.object.oForwardVel ~= 0 then
                    eggVel = eggVel + m.floor.object.oForwardVel * 2
                end
                spawn_sync_object(id_bhvBirdoEgg, model, mouthPos.x + sins(yaw) * 40 * coss(pitch), mouthPos.y, mouthPos.z + coss(yaw) * 40 * coss(pitch), function(o)
                        o.oForwardVel = math.max(eggVel, 40)
                        o.oMoveAngleYaw = yaw
                        o.oFaceAnglePitch = pitch
                        o.oMoveAnglePitch = pitch
                        o.oIntangibleTimer = 100
                        o.globalPlayerIndex = gIndex
                        o.oBehParams = (isFireball and 1) or 0
                        spawn_mist_particles_variable(20, 120, 5)
                    end)
            end
        end
    elseif e.spitTimer ~= 0 then
        e.spitTimer = e.spitTimer - 1
        m.marioBodyState.allowPartRotation = 1
        if e.spitTimer > 24 then
            headRot.x = approach_f32(headRot.x, degrees_to_sm64(-30), degrees_to_sm64(10), degrees_to_sm64(10))
        else
            headRot.x = approach_f32(headRot.x, degrees_to_sm64(0), degrees_to_sm64(3.5), degrees_to_sm64(3.5))
        end
    end

    -- throw objects instantly
    if m.action == ACT_THROWING then
        if m.actionTimer < 6 then
            m.actionTimer = 6
            set_anim_to_frame(m, 6)
        end
    elseif m.action == ACT_AIR_THROW or m.action == ACT_AIR_THROW_LAND then
        if m.actionTimer < 3 then
            m.actionTimer = 3
            set_anim_to_frame(m, 3)
        end
    end
end

hook_mario_action(ACT_BIRDO_HOLD_WALKING,  act_birdo_hold_walking)
hook_mario_action(ACT_BIRDO_SPIT_EGG,      act_birdo_spit_egg)
hook_mario_action(ACT_BIRDO_SPIT_EGG_AIR,  act_birdo_spit_egg_air)
hook_mario_action(ACT_BIRDO_SPIT_EGG_WALK, act_birdo_spit_egg_walk)

-- needed to prevent torso bug
local wasBirdo = false
function fix_torso_bug(m)
    if m.playerIndex ~= 0 or not charSelectExists then return end
    local charTable = charSelect.character_get_current_table()
    if charTable and charTable.name == "Birdo" and charSelect.get_options_status(charSelect.optionTableRef.localMoveset) ~= 0 then
        wasBirdo = true
    elseif wasBirdo then
        wasBirdo = false
        m.marioBodyState.allowPartRotation = 0
        m.marioBodyState.torsoAngle.x = 0
        m.marioBodyState.torsoAngle.y = 0
        m.marioBodyState.torsoAngle.z = 0
        m.marioBodyState.headAngle.y = 0
        gStateExtras[m.playerIndex].spitTimer = 0
        if m.action == ACT_BIRDO_HOLD_WALKING or m.action == ACT_BIRDO_SPIT_EGG or m.action == ACT_BIRDO_SPIT_EGG_AIR or m.action == ACT_BIRDO_SPIT_EGG_WALK then
            force_idle_state(m)
        end
    end
end
hook_event(HOOK_MARIO_UPDATE, fix_torso_bug)

function birdo_on_set_action(m)
    m.marioBodyState.allowPartRotation = 0
    m.marioBodyState.torsoAngle.x = 0
    m.marioBodyState.torsoAngle.y = 0
    m.marioBodyState.torsoAngle.z = 0
    m.marioBodyState.headAngle.y = 0
    if m.action == ACT_HOLD_WALKING then -- switch to custom hold action
        m.marioBodyState.allowPartRotation = 1
        set_mario_action(m, ACT_BIRDO_HOLD_WALKING, 0)
    end
end

function birdo_before_action(m, action)
    if ((action == ACT_PUNCHING and m.action ~= ACT_CROUCHING) or action == ACT_MOVE_PUNCHING or action == ACT_JUMP_KICK) and m.controller.buttonDown & A_BUTTON == 0 then
        local e = gStateExtras[m.playerIndex]
        e.framesSinceShoot = 0
        if e.spitTimer == 0 then
            e.flameCharge = 0
        end

        local canShoot = true
        local eggCount = 0
        local gIndex = network_global_index_from_local(m.playerIndex)
        local egg = obj_get_first_with_behavior_id(id_bhvBirdoEgg)
        while egg do
            if egg.oAction == 0 and egg.oHeldState == HELD_FREE and egg.globalPlayerIndex == gIndex then
                eggCount = eggCount + 1
                if eggCount >= 3 then -- max of 3 eggs/fireballs per player
                    canShoot = false
                    break
                end
            end
            egg = obj_get_next_with_same_behavior_id(egg)
        end

        if m.action == ACT_BIRDO_SPIT_EGG or e.spitTimer ~= 0 or not canShoot then
            return 1
        elseif action == ACT_MOVE_PUNCHING then
            m.marioObj.header.gfx.animInfo.animFrame = 1
            return ACT_BIRDO_SPIT_EGG_WALK
        elseif action == ACT_JUMP_KICK then
            m.marioObj.header.gfx.animInfo.animFrame = 1
            return ACT_BIRDO_SPIT_EGG_AIR
        else
            m.marioObj.header.gfx.animInfo.animFrame = 1
            return ACT_BIRDO_SPIT_EGG
        end
    end
end

function birdo_on_interact(m, o, intType)
    local e = gStateExtras[m.playerIndex]
    if intType == INTERACT_GRABBABLE and e.framesSinceShoot == 0 and e.flameCharge == 0 and (m.action == ACT_BIRDO_SPIT_EGG or m.action == ACT_BIRDO_SPIT_EGG_WALK) and o.oInteractionSubtype & INT_SUBTYPE_NOT_GRABBABLE == 0 then
        set_mario_action(m, ACT_MOVE_PUNCHING, 1)
        return
    end
end

function birdo_before_phys_step(m)
    local hScale = 1.0
    local vScale = 1.0

    -- faster ground movement and slower, floaty air movement
    if (m.action & ACT_FLAG_MOVING) ~= 0 and m.action ~= ACT_BUBBLED then
        hScale = hScale * 1.12 -- not as fast as toad
    elseif m.action & ACT_FLAG_AIR ~= 0 then
        hScale = hScale * 0.94
        if m.vel.y < 0 then
            vScale = vScale * 0.98
        end
    end

    m.vel.x = m.vel.x * hScale
    m.vel.y = m.vel.y * vScale
    m.vel.z = m.vel.z * hScale
end

-- allow shooting in first person
function birdo_before_update(m)
    if m.action == ACT_FIRST_PERSON and m.controller.buttonPressed & B_BUTTON ~= 0 then
        local e = gStateExtras[m.playerIndex]
        e.framesSinceShoot = 0
        if e.spitTimer == 0 then
            e.flameCharge = 0
        end
        m.controller.buttonPressed = m.controller.buttonPressed & ~B_BUTTON
    end
end

-- interactions for birdo's fireball
function birdo_fireball_interaction(o, egg)
    if obj_has_behavior_id(o, id_bhvMrBlizzard) ~= 0 then
        o.oFaceAngleRoll = 0x3000
        o.oMrBlizzardHeldObj = nil
        o.prevObj = o.oMrBlizzardHeldObj
        o.oAction = MR_BLIZZARD_ACT_DEATH
        o.oMrBlizzardDizziness = 0
        o.oMrBlizzardChangeInDizziness = 0
        o.oTimer = 30
        return true
    end

    if obj_has_behavior_id(o, id_bhvBowser) ~= 0 then
        if o.oAction ~= 4 and o.oAction ~= 5 and o.oAction ~= 6 and o.oAction ~= 12 and o.oAction ~= 19 and o.oAction ~= 20 and math.abs(o.oVelY) <= 2 then
            o.oAction = 1
        end
        return true
    end

    if (o.oInteractType & INTERACT_BULLY) ~= 0 then
        o.oForwardVel = 50
        o.oMoveAngleYaw = obj_angle_to_object(o, egg) + 0x8000
        return true
    end
end

-------------------
-- Rosalina Spin --
-------------------

_G.ACT_SPINJUMP = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ATTACKING)
E_MODEL_SPIN_ATTACK = smlua_model_util_get_id("spin_attack_geo")

---@param o Object
local function bhv_spin_attack_init(o)
    o.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE -- Allows you to change the position and angle
end

---@param o Object
local function bhv_spin_attack_loop(o)
    cur_obj_set_pos_relative_to_parent(0, 20, 0) -- Makes it move to its parent's position

    o.oFaceAngleYaw = o.oFaceAngleYaw + 0x2000 -- Rotates it

    pM = gMarioStates[network_local_index_from_global(o.globalPlayerIndex)] -- Parent MarioState

    if pM.action ~= ACT_SPINJUMP then -- Deletes itself once the action changes
        obj_mark_for_deletion(o)
    end
end

local id_bhvSpinAttack = hook_behavior(nil, OBJ_LIST_GENACTOR, true, bhv_spin_attack_init, bhv_spin_attack_loop)

gPlayerSyncTable[0].canSpin = true -- Determines if you can spin
gPlayerSyncTable[0].canGrab = false -- Determines if you're near a grabbable

-- Spinable actions, these are actions you can spin out of
local spinWhiteList = {
    [ACT_LONG_JUMP] = true,
    [ACT_BACKFLIP]  = true
}

-- Spin overridable actions, these are overriden instantly
local spinOverridableActs = {
    [ACT_PUNCHING]      = true,
    [ACT_MOVE_PUNCHING] = true,
    [ACT_JUMP_KICK]     = true,
    [ACT_DIVE]          = true
}

local ROSALINA_SOUND_SPIN = audio_sample_load("spin_attack.ogg") -- Load audio sample

---@param m MarioState
function act_spinjump(m)
    if m.actionTimer >= 15 then
        return set_mario_action(m, ACT_FREEFALL, 0) -- End the action
    end

    if m.actionTimer == 0 then
        play_character_sound(m, CHAR_SOUND_HELLO) -- Plays the character sound
        audio_sample_play(ROSALINA_SOUND_SPIN, m.pos, 1) -- Plays the spin sound sample
        m.particleFlags = m.particleFlags | ACTIVE_PARTICLE_SPARKLES -- Spawns sparkle particles

        m.vel.y = 30 -- Initial upward velocity
        m.marioObj.hitboxRadius = 100 -- Damage hitbox

        -- Spawn the spin effect
        spawn_non_sync_object(id_bhvSpinAttack, E_MODEL_SPIN_ATTACK, m.pos.x, m.pos.y, m.pos.z,
        function (o)
            o.parentObj = m.marioObj
            o.globalPlayerIndex = m.marioObj.globalPlayerIndex
        end)

    else
        m.marioObj.hitboxRadius = 37 -- Reset the hitbox after initial hit
    end

    common_air_action_step(m, ACT_FREEFALL_LAND, CHAR_ANIM_BEND_KNESS_RIDING_SHELL, AIR_STEP_NONE)

    m.marioBodyState.handState = MARIO_HAND_PEACE_SIGN -- Hand State

    -- Increments the action timer
    m.actionTimer = m.actionTimer + 1
end

---@param m MarioState
---@param o Object
---@param intType InteractionType
local function rosalina_on_interact(m, o, intType)
    local p = gPlayerSyncTable[m.playerIndex]
    if intType == INTERACT_GRABBABLE and o.oInteractionSubtype & INT_SUBTYPE_NOT_GRABBABLE == 0 then
        p.canGrab = true
    end
end

---@param m MarioState
local function rosalina_update(m)
    local p = gPlayerSyncTable[m.playerIndex]

    if p.canSpin and spinWhiteList[m.action] and m.controller.buttonPressed & B_BUTTON ~= 0 then
        p.canSpin = false
        return set_mario_action(m, ACT_SPINJUMP, 0)
    end

    if m.action & ACT_FLAG_AIR == 0 and m.playerIndex == 0 then
        p.canSpin = true
    end

    if m.action ~= ACT_SPINJUMP and m.marioObj.hitboxRadius ~= 37 then
        m.marioObj.hitboxRadius = 37
    end
end

---@param m MarioState
local function rosalina_before_action(m, nextAct)
    local p = gPlayerSyncTable[m.playerIndex]

    if p.canSpin and (not p.canGrab) and spinOverridableActs[nextAct] and m.input & (INPUT_Z_DOWN | INPUT_A_DOWN) == 0 then
        p.canSpin = false
        return ACT_SPINJUMP
    end

    if not nextAct then return end -- So bitwise operations don't fail

    if nextAct & ACT_FLAG_AIR == 0 then
        if not p.canSpin then
            play_sound_with_freq_scale(SOUND_GENERAL_COIN_SPURT_EU, m.marioObj.header.gfx.cameraToObject, 1.6)
            spawn_non_sync_object(id_bhvSparkle, E_MODEL_SPARKLES_ANIMATION, m.pos.x, m.pos.y + 200, m.pos.z, function (o)
                obj_scale(o, 0.75)
            end)
        end
        p.canGrab = false
        p.canSpin = true
    end
end

hook_mario_action(ACT_SPINJUMP, act_spinjump, INT_KICK)

-------------------------
-- Wapeach Axe Attacks --
-------------------------


_G.ACT_AXECHOP      = allocate_mario_action(ACT_GROUP_STATIONARY | ACT_FLAG_STATIONARY)
_G.ACT_AXESPIN      = allocate_mario_action(ACT_GROUP_MOVING | ACT_FLAG_MOVING | ACT_FLAG_ATTACKING)
_G.ACT_AXESPINAIR   = allocate_mario_action(ACT_FLAG_ATTACKING | ACT_FLAG_AIR | ACT_GROUP_AIRBORNE)
_G.ACT_AXESPINDIZZY = allocate_mario_action(ACT_GROUP_MOVING | ACT_FLAG_MOVING)

---@param o Object
local function bhv_axe_attack_init(o)
    o.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE | OBJ_FLAG_SET_FACE_ANGLE_TO_MOVE_ANGLE

    o.oDamageOrCoinValue = 2
    o.oNumLootCoins = 0
    o.oHealth = 0
    o.hitboxRadius = 60
    o.hitboxHeight = 80
    o.hurtboxRadius = 60
    o.hurtboxHeight = 80
    o.hitboxDownOffset = 0
    o.oInteractType = 0

    cur_obj_scale(1)
    cur_obj_become_tangible()

    network_init_object(o, true, {})
end

---@param o Object
local function bhv_axe_attack_loop(o)
    local m = gMarioStates[network_local_index_from_global(o.globalPlayerIndex)]

    local handPos = table.copy(m.pos)
    get_mario_anim_part_pos(m, MARIO_ANIM_PART_RIGHT_HAND, handPos)

    local dist = 185

    local axeDir = table.copy(handPos)
    vec3f_sub(axeDir, m.pos)
    vec3f_normalize(axeDir)
    vec3f_mul(axeDir, 120)

    o.oPosX = handPos.x + sins(m.faceAngle.y) * coss(m.faceAngle.x) * dist
    o.oPosY = handPos.y - axeDir.y
    o.oPosZ = handPos.z + coss(m.faceAngle.y) * coss(m.faceAngle.x) * dist

    obj_process_attacks(o, bhvWapeachAxeAttacks)

    if o.oTimer == 15 then
        obj_mark_for_deletion(o)
    end
end

local id_bhvAxeAttack = hook_behavior(nil, OBJ_LIST_DESTRUCTIVE, true, bhv_axe_attack_init, bhv_axe_attack_loop)


---@param m MarioState
---@param o Object
---@param intType integer
local function allow_interact(m, o, intType)
    if obj_has_behavior_id(o, id_bhvAxeAttack) ~= 0 and o.globalPlayerIndex == m.marioObj.globalPlayerIndex then
        return false
    end
end
---@param m MarioState
local function act_wapeach_axechop(m)
    local slope = -find_floor_slope(m, 0)
    m.faceAngle.x = slope
    m.marioObj.header.gfx.angle.x = slope

    if m.actionTimer == 0 then
        set_character_animation(m, CHAR_ANIM_BREAKDANCE)
        smlua_anim_util_set_animation(m.marioObj, 'wapeach_axechop')
        play_character_sound(m, CHAR_SOUND_YAHOO_WAHA_YIPPEE)
    end

    --if m.actionTimer >= 14 and m.actionTimer <= 40 then m.marioBodyState.handState = 2 end

    if m.actionTimer == 17 then
        play_sound(SOUND_OBJ_POUNDING_LOUD, m.marioObj.header.gfx.cameraToObject)
        if m.playerIndex == 0 then
            local handPos = table.copy(m.pos)
            get_mario_anim_part_pos(m, MARIO_ANIM_PART_RIGHT_HAND, handPos)
            spawn_sync_object(id_bhvAxeAttack, E_MODEL_NONE, handPos.x, handPos.y + 25, handPos.z, function(o)
                o.globalPlayerIndex = m.marioObj.globalPlayerIndex
            end)
        end
        -- shakey cam if you are close enough to petey (based on local player's camera)
        if vec3f_length(m.marioObj.header.gfx.cameraToObject) < 2000 then
            set_camera_shake_from_hit(SHAKE_SMALL_DAMAGE)
        end
    end

    if is_anim_at_end(m) ~= 0 then
        set_mario_action(m, ACT_IDLE, 0)
    end

    local step = perform_ground_step(m)

    if step == GROUND_STEP_LEFT_GROUND then
        return set_mario_action(m, ACT_FREEFALL, 0)
    end

    m.actionTimer = m.actionTimer + 1
end
hook_mario_action(ACT_AXECHOP, act_wapeach_axechop)

---@param m MarioState
local function act_wapeach_axespin(m)
    if m.actionTimer == 0 then
        play_character_sound(m, CHAR_SOUND_YAHOO_WAHA_YIPPEE)
        m.forwardVel = clamp(m.forwardVel + 21, 0, 850)
    end

    if m.controller.buttonPressed & B_BUTTON ~= 0 then
        m.forwardVel = clamp(m.forwardVel + 7, 0, 850)
    end

    set_character_anim_with_accel(m, CHAR_ANIM_SLIDE_KICK, clamp(m.forwardVel * 0x500, 0, 0x1F000))
    smlua_anim_util_set_animation(m.marioObj, 'wapeach_axespin')
    set_mario_particle_flags(m, PARTICLE_DUST, 0)
    if is_anim_past_frame(m, 1) ~= 0 then
        play_sound(SOUND_ACTION_SPIN, m.marioObj.header.gfx.cameraToObject)
    end

    apply_slope_accel(m)
    if m.intendedMag > 1 then
        m.faceAngle.y = approach_s16_symmetric(m.faceAngle.y, m.intendedYaw, 0x200)
    end

    m.forwardVel = m.forwardVel - 1.0
    mario_set_forward_vel(m, m.forwardVel)

    local step = perform_ground_step(m)
    if m.forwardVel < 20 and m.actionTimer >= 15 then
        return set_mario_action(m, ACT_AXESPINDIZZY, 0)
    end
    if m.forwardVel >= 100 and m.actionState == 0 then
        play_character_sound(m, CHAR_SOUND_TWIRL_BOUNCE)
        m.actionState = 1
    end
    if step == GROUND_STEP_HIT_WALL then
        set_mario_particle_flags(m, PARTICLE_TRIANGLE, 0)
        mario_bonk_reflection(m, 0)
        play_sound(SOUND_ACTION_HIT_3, m.marioObj.header.gfx.cameraToObject)

        return set_mario_action(m, ACT_AXESPINDIZZY, 0)
    end
    if step == GROUND_STEP_LEFT_GROUND then
        return set_mario_action(m, ACT_AXESPINAIR, 0)
    end

    local gfx = m.marioObj.header.gfx
    local floorAngle = atan2s(m.floor.normal.z, m.floor.normal.x)
    local floorSlope = radians_to_sm64(math.acos(m.floor.normal.y))
    local speedTilt = clamp(m.forwardVel * 0x80, -0x500, 0x500)
    gfx.angle.x = floorSlope * coss(floorAngle - m.faceAngle.y) + speedTilt
    gfx.angle.z = floorSlope * -sins(floorAngle - m.faceAngle.y)

    m.actionTimer = m.actionTimer + 1
end
hook_mario_action(ACT_AXESPIN, act_wapeach_axespin)

local function act_wapeach_axespin_air(m)
    update_air_with_turn(m)
    m.vel.y = m.vel.y + 2

    set_character_anim_with_accel(m, CHAR_ANIM_SLIDE_KICK, clamp(m.forwardVel * 0x500, 0, 0x1F000))
    smlua_anim_util_set_animation(m.marioObj, 'wapeach_axespin')
    if is_anim_past_frame(m, 1) ~= 0 then
        play_sound(SOUND_ACTION_SPIN, m.marioObj.header.gfx.cameraToObject)
    end

    if m.intendedMag > 1 then
        m.faceAngle.y = approach_s16_symmetric(m.faceAngle.y, m.intendedYaw, 0x200)
    end

    m.forwardVel = clamp(m.forwardVel - 0.7, 0, 850)
    mario_set_forward_vel(m, m.forwardVel)

    local step = perform_air_step(m, 0)
    if m.forwardVel < 20 and m.actionTimer >= 10 then
        set_mario_action(m, ACT_THROWN_FORWARD, 0)
        return
    end
    if m.forwardVel >= 100 and m.actionState == 0 then
        play_character_sound(m, CHAR_SOUND_TWIRL_BOUNCE)
        m.actionState = 1
    end
    if step == AIR_STEP_LANDED then
        return set_mario_action(m, ACT_AXESPIN, 0)
    end
    if step == AIR_STEP_HIT_WALL then
        mario_bonk_reflection(m, 1)
        return set_mario_action(m, ACT_THROWN_BACKWARD, 0)
    end

    m.actionTimer = m.actionTimer + 1
end
hook_mario_action(ACT_AXESPINAIR, act_wapeach_axespin_air)

E_MODEL_DIZZYCIRCLE = smlua_model_util_get_id("dizzy_circle_geo")


---@param o Object
local function bhv_dizzycircle_init(o)
    o.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE -- Allows you to change the position and angle
end

---@param o Object
local function bhv_dizzycircle_loop(o)
    smlua_anim_util_set_animation(o, 'dizzycircle_idle')
    local m = nearest_mario_state_to_object(o)

    o.oPosX = m.marioBodyState.headPos.x
    o.oPosY = m.marioBodyState.headPos.y + 50

    o.oPosZ = m.marioBodyState.headPos.z


    --pM = gMarioStates[network_local_index_from_global(o.globalPlayerIndex)]

    if o.oTimer > 42 then -- Deletes itself once the action changes
        obj_mark_for_deletion(o)
    end
end

local id_bhvDizzyCircle = hook_behavior(nil, OBJ_LIST_GENACTOR, true, bhv_dizzycircle_init, bhv_dizzycircle_loop)


local function act_wapeach_axespin_dizzy(m)
    if m.actionTimer == 1 then
        play_character_sound(m, CHAR_SOUND_WHOA)
        -- Spawn the spin effect
        spawn_non_sync_object(id_bhvDizzyCircle, E_MODEL_DIZZYCIRCLE, m.marioBodyState.headPos.x,
            m.marioBodyState.headPos.y, m.marioBodyState.headPos.z,
            function(o)
                o.parentObj = m.marioObj
                o.globalPlayerIndex = m.marioObj.globalPlayerIndex
            end)
    end
    if m.actionTimer >= 42 then
        m.marioBodyState.eyeState = MARIO_EYES_DEAD
        set_character_animation(m, CHAR_ANIM_LAND_ON_STOMACH)
        smlua_anim_util_set_animation(m.marioObj, 'wapeach_flop')
        if m.actionTimer == 52 then
            play_sound(SOUND_ACTION_PAT_BACK, m.marioObj.header.gfx.cameraToObject)
            play_character_sound(m, CHAR_SOUND_OOOF2)
        end
        if m.actionTimer > 52 and m.actionTimer < 111 then
            apply_slope_accel(m)
            m.forwardVel = m.forwardVel * 0.95
            if m.forwardVel <= 0 then
                m.forwardVel = 0
            else
                set_mario_particle_flags(m, PARTICLE_DUST, 0)
                play_sound(SOUND_AIR_ROUGH_SLIDE, m.marioObj.header.gfx.cameraToObject)
            end
        elseif m.actionTimer >= 111 then
            m.forwardVel = 0
            if m.controller.buttonPressed & B_BUTTON ~= 0 or m.controller.buttonPressed & A_BUTTON ~= 0 then
                set_mario_action(m, ACT_FORWARD_ROLLOUT, 0)
            end
        end
    else
        apply_slope_accel(m)
        m.forwardVel = clamp(m.forwardVel, 0, 21)
        if is_anim_past_frame(m, 1) ~= 0 then
            play_sound(SOUND_ACTION_SPIN, m.marioObj.header.gfx.cameraToObject)
        end
        set_character_animation(m, CHAR_ANIM_BREAKDANCE)
        smlua_anim_util_set_animation(m.marioObj, 'wapeach_dizzy')
    end

    mario_set_forward_vel(m, m.forwardVel)
    local step = perform_ground_step(m)
    if step == GROUND_STEP_LEFT_GROUND then
        set_mario_action(m, ACT_THROWN_FORWARD, 0)
    end

    local gfx        = m.marioObj.header.gfx
    local floorAngle = atan2s(m.floor.normal.z, m.floor.normal.x)
    local floorSlope = radians_to_sm64(math.acos(m.floor.normal.y))
    gfx.angle.x      = floorSlope * coss(floorAngle - m.faceAngle.y)
    gfx.angle.z      = floorSlope * -sins(floorAngle - m.faceAngle.y)

    m.actionTimer    = m.actionTimer + 1
end
hook_mario_action(ACT_AXESPINDIZZY, act_wapeach_axespin_dizzy)

---@param m MarioState
---@param incomingAct integer
local function wapeach_before_action(m, incomingAct)
    if (incomingAct == ACT_PUNCHING or incomingAct == ACT_MOVE_PUNCHING) and m.controller.buttonDown & Z_TRIG ~= 0 then
        return ACT_AXECHOP
    end
    if (incomingAct == ACT_SLIDE_KICK) then
        return ACT_AXESPIN
    end
end

-------------------------
-- Donkey Kong Moveset --
-------------------------

--- @param m MarioState
--- Applies gravity to donkey kong
function apply_donkey_kong_gravity(m)
    if m.action == ACT_TWIRLING and m.vel.y < 0.0 then
        apply_twirl_gravity(m)
    elseif m.action == ACT_SHOT_FROM_CANNON then
        m.vel.y = math.max(-75, m.vel.y - 1.5)
    elseif m.action == ACT_LONG_JUMP or m.action == ACT_SLIDE_KICK or m.action == ACT_BBH_ENTER_SPIN then
        m.vel.y = math.max(-75, m.vel.y - 3.0)
    elseif m.action == ACT_LAVA_BOOST or m.action == ACT_FALL_AFTER_STAR_GRAB then
        m.vel.y = math.max(-65, m.vel.y - 4.8)
    elseif m.action == ACT_GETTING_BLOWN then
        m.vel.y = math.max(-75, m.vel.y - (1.5 * m.unkC4))
    elseif should_strengthen_gravity_for_jump_ascent(m) ~= 0 then
        m.vel.y = m.vel.y / 4.0
    elseif m.action & ACT_FLAG_METAL_WATER ~= 0 then
        m.vel.y = math.max(-16, m.vel.y - 2.4)
    elseif m.flags & MARIO_WING_CAP ~= 0 and m.vel.y < 0.0 and m.input & INPUT_A_DOWN ~= 0 then
        m.marioBodyState.wingFlutter = 1

        m.vel.y = m.vel.y - 3.0
        if m.vel.y < -37.5 then
            m.vel.y = math.min(-37.5, m.vel.y + 4)
        end
    else
        if m.vel.y < 0 then
            m.vel.y = math.max(-75, m.vel.y - 6)
        else
            m.vel.y = math.max(-75, m.vel.y - 4.25)
        end
    end
end

--- @param m MarioState
--- @param stepArg integer
--- @return integer
--- Performs an air step for donkey kong
function perform_donkey_kong_air_step(m, stepArg)
    local intendedPos = gVec3fZero()
    local quarterStepResult
    local stepResult = AIR_STEP_NONE

    m.wall = nil

    for i = 0, 4 do
        local step = gVec3fZero()
        step = {
            x = m.vel.x / 4.0,
            y = m.vel.y / 4.0,
            z = m.vel.z / 4.0,
        }

        intendedPos.x = m.pos.x + step.x
        intendedPos.y = m.pos.y + step.y
        intendedPos.z = m.pos.z + step.z

        vec3f_normalize(step)
        vec3f_copy(gFindWallDirection, step)

        gFindWallDirectionActive = true
        gFindWallDirectionAirborne = true
        quarterStepResult = perform_air_quarter_step(m, intendedPos, stepArg)
        gFindWallDirectionAirborne = false
        gFindWallDirectionActive = false

        --! On one qf, hit OOB/ceil/wall to store the 2 return value, and continue
        -- getting 0s until your last qf. Graze a wall on your last qf, and it will
        -- return the stored 2 with a sharply angled reference wall. (some gwks)

        if (quarterStepResult ~= AIR_STEP_NONE) then
            stepResult = quarterStepResult
        end

        if (quarterStepResult == AIR_STEP_LANDED or quarterStepResult == AIR_STEP_GRABBED_LEDGE
            or quarterStepResult == AIR_STEP_GRABBED_CEILING
            or quarterStepResult == AIR_STEP_HIT_LAVA_WALL) then
            break
        end
    end

    if (m.vel.y >= 0.0) then
        m.peakHeight = m.pos.y
    end

    m.terrainSoundAddend = mario_get_terrain_sound_addend(m)

    if (m.action ~= ACT_FLYING and m.action ~= ACT_BUBBLED) then
        apply_donkey_kong_gravity(m)
    end
    apply_vertical_wind(m)

    vec3f_copy(m.marioObj.header.gfx.pos, m.pos)
    vec3s_set(m.marioObj.header.gfx.angle, 0, m.faceAngle.y, 0)

    return stepResult
end

function before_donkey_kong_phys_step(m, stepType, stepArg)

    if stepType == STEP_TYPE_GROUND then
        -- return perform_donkey_kong_ground_step(m) -- TBA
    elseif stepType == STEP_TYPE_AIR then
        return perform_donkey_kong_air_step(m, stepArg)
    elseif stepType == STEP_TYPE_WATER then
        -- return perform_donkey_kong_water_step(m) -- TBA
    elseif stepType == STEP_TYPE_HANG then
        -- return perform_donkey_kong_hanging_step(m) -- TBA
    end
end

-------------------
-- Sonic Moveset --
-------------------

---@param m MarioState
---@param stopSpeed number
---@return boolean
--[[
Updates Sonic's spin dashing state each frame, applying additional friction or acceleration based on the surface's slipperiness.
Also checks if speed has slowed below a threshold to end the slide.
Returns `true` if spin dashing has stopped
]]
function update_spin_dashing(m, stopSpeed)
    local lossFactor
    local accel
    local oldSpeed
    local newSpeed

    local stopped = false

    local intendedDYaw = m.intendedYaw - m.slideYaw
    local forward = coss(intendedDYaw)
    local sideward = sins(intendedDYaw)

    if (forward < 0.0 and m.forwardVel >= 0.0) then
        forward = forward * (0.5 + 0.5 * m.forwardVel / 100.0)
    end

    accel = 4.0
    lossFactor = math.min(m.intendedMag / 32.0 * forward/100 + 0.98, 1)

    oldSpeed = math.sqrt(m.slideVelX * m.slideVelX + m.slideVelZ * m.slideVelZ)

    --! This is attempting to use trig derivatives to rotate Sonic's speed.
    -- It is slightly off/asymmetric since it uses the new X speed, but the old
    -- Z speed.
    m.slideVelX = m.slideVelX + m.slideVelZ * (m.intendedMag / 32.0) * sideward * 0.05
    m.slideVelZ = m.slideVelZ - m.slideVelX * (m.intendedMag / 32.0) * sideward * 0.05

    newSpeed = math.sqrt(m.slideVelX * m.slideVelX + m.slideVelZ * m.slideVelZ)

    if (oldSpeed > 0.0 and newSpeed > 0.0) then
        m.slideVelX = m.slideVelX * oldSpeed / newSpeed
        m.slideVelZ = m.slideVelZ * oldSpeed / newSpeed
    end

    update_sliding_angle(m, accel, lossFactor)

    if (m.playerIndex == 0 and not mario_floor_is_slope(m) and m.forwardVel ^ 2 < stopSpeed ^ 2) then
        mario_set_forward_vel(m, 0.0)
        stopped = true
    end

    return stopped
end

_G.ACT_SPIN_JUMP        = allocate_mario_action( ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_CONTROL_JUMP_HEIGHT | ACT_FLAG_AIR | ACT_GROUP_AIRBORNE | ACT_FLAG_ATTACKING )
_G.ACT_SPIN_DASH_CHARGE = allocate_mario_action( ACT_FLAG_STATIONARY | ACT_GROUP_STATIONARY | ACT_FLAG_SHORT_HITBOX )
_G.ACT_SPIN_DASH        = allocate_mario_action( ACT_FLAG_MOVING | ACT_GROUP_MOVING | ACT_FLAG_SHORT_HITBOX | ACT_FLAG_ATTACKING )

local sonicActionOverride = {
    [ACT_JUMP]        = ACT_SPIN_JUMP,
    [ACT_DOUBLE_JUMP] = ACT_SPIN_JUMP,
    [ACT_TRIPLE_JUMP] = ACT_SPIN_JUMP,
    [ACT_BACKFLIP]    = ACT_SPIN_JUMP,
    [ACT_SIDE_FLIP]   = ACT_SPIN_JUMP,
    [ACT_STEEP_JUMP]  = ACT_SPIN_JUMP,
    [ACT_LONG_JUMP]   = ACT_SPIN_JUMP,
}

---@param m MarioState
local function act_spin_jump(m)

    m.vel.y = math.max(m.vel.y - 2, -75)

    play_mario_sound(m, SOUND_ACTION_TERRAIN_JUMP, 0)

    local stepResult = common_air_action_step(m, ACT_JUMP_LAND, CHAR_ANIM_A_POSE, AIR_STEP_CHECK_LEDGE_GRAB | AIR_STEP_CHECK_HANG)

    if stepResult ~= AIR_STEP_NONE then
        m.faceAngle.x = 0
    else
        m.faceAngle.x = m.faceAngle.x + 0x2000
        m.marioObj.header.gfx.angle.x = m.faceAngle.x
    end

    if (m.controller.buttonDown & Z_TRIG) ~= 0 then
        if stepResult == AIR_STEP_LANDED then
            set_mario_action(m, ACT_SPIN_DASH, 0)
        elseif (m.controller.buttonPressed & B_BUTTON) ~= 0 then
            return set_mario_action(m, ACT_GROUND_POUND, 0)
        end
    end

    m.actionTimer = m.actionTimer + 1
end

---@param m MarioState
local function act_spin_dash_charge(m)

    local e = gStateExtras[m.playerIndex]

    if m.input & INPUT_B_PRESSED ~= 0 then
        e.spinCharge = math.min(e.spinCharge + 1, 8)
    end

    set_mario_animation(m, CHAR_ANIM_A_POSE)
    stationary_ground_step(m)

    m.faceAngle.x = m.faceAngle.x + 0x500 * e.spinCharge
    m.marioObj.header.gfx.angle.x = m.faceAngle.x

    m.marioObj.header.gfx.pos.y = m.pos.y + 50

    if m.input & INPUT_Z_DOWN == 0 then
        mario_set_forward_vel(m, 32 * e.spinCharge)
        e.spinCharge = 0
        return set_mario_action(m, ACT_SPIN_DASH, 0)
    end

end

---@param m MarioState
local function act_spin_dash(m)

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_JUMP, 0)
    end

    set_mario_animation(m, CHAR_ANIM_A_POSE)
    local stepResult = perform_ground_step(m)

    if stepResult == GROUND_STEP_HIT_WALL then
        set_mario_particle_flags(m, ACTIVE_PARTICLE_H_STAR, 0)
        return slide_bonk(m, ACT_GROUND_BONK, ACT_GROUND_BONK)
    elseif stepResult == GROUND_STEP_LEFT_GROUND then
        return set_mario_action(m, ACT_JUMP, 0)
    end

    update_spin_dashing(m, 0)

    m.faceAngle.x = m.faceAngle.x + 0x2000 * m.forwardVel / 32
    m.marioObj.header.gfx.angle.x = m.faceAngle.x

    m.marioObj.header.gfx.pos.y = m.pos.y + 50

    m.actionTimer = m.actionTimer + 1
end

---@param m MarioState
---@param action integer
local function before_set_sonic_action(m, action)
    if sonicActionOverride[action] then
        if action == ACT_LONG_JUMP then
            set_mario_y_vel_based_on_fspeed(m, 64, 0.25)
            mario_set_forward_vel(m, 48)
        else
            set_mario_y_vel_based_on_fspeed(m, 72, 0.25)
        end
        return sonicActionOverride[action]
    end
end

local function on_set_sonic_action(m)
    if m.action == ACT_PUNCHING and m.actionArg == 9 then
        set_mario_action(m, ACT_SPIN_DASH_CHARGE, 0)
    end

    if m.action == ACT_CROUCH_SLIDE then
        set_mario_action(m, ACT_SPIN_DASH, 0)
    end
end

hook_mario_action(ACT_SPIN_JUMP,        act_spin_jump)
hook_mario_action(ACT_SPIN_DASH_CHARGE, act_spin_dash_charge)
hook_mario_action(ACT_SPIN_DASH,        act_spin_dash)

------------
--  Main  --
------------

local function on_character_select_load()
    
    local _ENV = setmetatable(charSelect, { __index = _ENV }) -- The CS environment
    
    -- Character Types Enum --

    _G.CT_TOADETTE    = extraCharacters[1].tablePos  --- @type CharacterType
    _G.CT_PEACH       = extraCharacters[2].tablePos  --- @type CharacterType
    _G.CT_DAISY       = extraCharacters[3].tablePos  --- @type CharacterType
    _G.CT_YOSHI       = extraCharacters[4].tablePos  --- @type CharacterType
    _G.CT_BIRDO       = extraCharacters[5].tablePos  --- @type CharacterType
    _G.CT_PAULINE     = extraCharacters[7].tablePos  --- @type CharacterType
    _G.CT_ROSALINA    = extraCharacters[8].tablePos  --- @type CharacterType
    _G.CT_WAPEACH     = extraCharacters[9].tablePos  --- @type CharacterType
    _G.CT_DONKEY_KONG = extraCharacters[10].tablePos --- @type CharacterType
    _G.CT_SONIC       = extraCharacters[11].tablePos --- @type CharacterType

    -- Toadette
    character_hook_moveset(CT_TOADETTE, HOOK_MARIO_UPDATE, toadette_update)
    character_hook_moveset(CT_TOADETTE, HOOK_ON_SET_MARIO_ACTION, toadette_on_set_action)
    character_hook_moveset(CT_TOADETTE, HOOK_BEFORE_PHYS_STEP, toadette_before_phys_step)
    -- Peach
    character_hook_moveset(CT_PEACH, HOOK_MARIO_UPDATE, peach_update)
    -- Daisy
    character_hook_moveset(CT_DAISY, HOOK_MARIO_UPDATE, daisy_update)
    -- Yoshi
    character_hook_moveset(CT_YOSHI, HOOK_MARIO_UPDATE, yoshi_update)
    -- Birdo
    character_hook_moveset(CT_BIRDO, HOOK_MARIO_UPDATE, birdo_update)
    character_hook_moveset(CT_BIRDO, HOOK_ON_SET_MARIO_ACTION, birdo_on_set_action)
    character_hook_moveset(CT_BIRDO, HOOK_BEFORE_SET_MARIO_ACTION, birdo_before_action)
    character_hook_moveset(CT_BIRDO, HOOK_ON_INTERACT, birdo_on_interact)
    character_hook_moveset(CT_BIRDO, HOOK_BEFORE_PHYS_STEP, birdo_before_phys_step)
    character_hook_moveset(CT_BIRDO, HOOK_BEFORE_MARIO_UPDATE, birdo_before_update)
    -- Pauline
    if not OmmEnabled then
        hook_event(HOOK_ON_SET_MARIO_ACTION, pauline_init_action) -- Must run for every character
        character_hook_moveset(CT_PAULINE, HOOK_BEFORE_SET_MARIO_ACTION, pauline_before_action)
        character_hook_moveset(CT_PAULINE, HOOK_BEFORE_MARIO_UPDATE, pauline_cancel_action)
        hook_event(HOOK_MARIO_UPDATE, pauline_update) -- Must run for every character
    end
    -- Rosalina
    character_hook_moveset(CT_ROSALINA, HOOK_MARIO_UPDATE, rosalina_update)
    -- charSelect.character_hook_moveset(CT_ROSALINA, HOOK_ON_PVP_ATTACK, rosalina_on_pvp_attack)
    character_hook_moveset(CT_ROSALINA, HOOK_ON_INTERACT, rosalina_on_interact)
    character_hook_moveset(CT_ROSALINA, HOOK_BEFORE_SET_MARIO_ACTION, rosalina_before_action)
    -- Wapeach
    character_hook_moveset(CT_WAPEACH, HOOK_BEFORE_SET_MARIO_ACTION, wapeach_before_action)
    hook_event(HOOK_ALLOW_INTERACT, allow_interact) -- dont moveset hook this
    -- Donkey Kong
    character_hook_moveset(CT_DONKEY_KONG, HOOK_BEFORE_PHYS_STEP, before_donkey_kong_phys_step)
    -- Sonic
    character_hook_moveset(CT_SONIC, HOOK_BEFORE_SET_MARIO_ACTION, before_set_sonic_action)
    character_hook_moveset(CT_SONIC, HOOK_ON_SET_MARIO_ACTION, on_set_sonic_action)
end

hook_event(HOOK_ON_MODS_LOADED, on_character_select_load)
