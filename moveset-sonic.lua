-------------------
-- Sonic Moveset --
-------------------

local TEX_HOMING_CURSOR = get_texture_info("homing-cursor")

local prevVelY
local prevHeight

local physTimer = 0
local lastforwardPos = gVec3fZero()
local realFVel = 0 -- Velocity calculated in realtime so that walls count.
local l = gLakituState

--- @param m MarioState
--- @param accel number
--- @param lossFactor number
--- Not used yet.
local function update_spin_dash_angle(m, accel, lossFactor)
    local newFacingDYaw
    local facingDYaw

    local floor = m.floor
    local slopeAngle = atan2s(floor.normal.z, floor.normal.x)
    local steepness = math.sqrt(floor.normal.x ^ 2 + floor.normal.z ^ 2)

    m.slideVelX = m.slideVelX + accel * steepness * sins(slopeAngle)
    m.slideVelZ = m.slideVelZ + accel * steepness * coss(slopeAngle)

    m.slideVelX = m.slideVelX * lossFactor
    m.slideVelZ = m.slideVelZ * lossFactor

    m.slideYaw = atan2s(m.slideVelZ, m.slideVelX)

    facingDYaw = math.s16(m.faceAngle.y - m.slideYaw)
    newFacingDYaw = facingDYaw

    --! -0x4000 not handled - can slide down a slope while facing perpendicular to it

    if (newFacingDYaw > 0 and newFacingDYaw <= 0x4000) then
        newFacingDYaw = newFacingDYaw - 0x200
        if (newFacingDYaw < 0) then newFacingDYaw = 0 end
    elseif (newFacingDYaw > -0x4000 and newFacingDYaw < 0) then
        newFacingDYaw = newFacingDYaw + 0x200
        if (newFacingDYaw > 0) then newFacingDYaw = 0 end
    elseif (newFacingDYaw > 0x4000 and newFacingDYaw < 0x8000) then
        newFacingDYaw = newFacingDYaw + 0x200
        if (newFacingDYaw > 0x8000) then newFacingDYaw = 0x8000 end
    elseif (newFacingDYaw > -0x8000 and newFacingDYaw < -0x4000) then
        newFacingDYaw = newFacingDYaw - 0x200
        if (newFacingDYaw < -0x8000) then newFacingDYaw = -0x8000 end
    end

    m.faceAngle.y = m.slideYaw + newFacingDYaw

    m.vel.x = m.slideVelX
    m.vel.y = 0.0
    m.vel.z = m.slideVelZ

    mario_update_moving_sand(m)
    mario_update_windy_ground(m)

    m.forwardVel = math.sqrt(m.slideVelX ^ 2 + m.slideVelZ ^ 2)
    if m.forwardVel > 256.0 then -- still dunno what we should be replacin' this with
        m.slideVelX = m.slideVelX * 256.0 / m.forwardVel
        m.slideVelZ = m.slideVelZ * 256.0 / m.forwardVel
    end

    if math.abs(newFacingDYaw) > 0x4000 then
        m.forwardVel = m.forwardVel * -1.0
    end
end

---@param m MarioState
---@param stopSpeed number
---@return integer
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

    local stopped = 0

    local intendedDYaw = m.intendedYaw - m.slideYaw
    local forward = coss(intendedDYaw)
    local sideward = sins(intendedDYaw)

    if (forward < 0.0 and m.forwardVel >= 0.0) then
        forward = forward * (0.5 + 0.5 * m.forwardVel / 100.0)
    end

    accel = 4.0
    lossFactor = math.min(m.intendedMag / 32.0 * forward / 100 + 0.98, 1)

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

    update_spin_dash_angle(m, accel, lossFactor)

    if (m.playerIndex == 0 and mario_floor_is_slope(m) == 0 and math.abs(m.forwardVel) < stopSpeed) then
        mario_set_forward_vel(m, 0.0)
        stopped = 1
    end

    return stopped
end

--- @param m MarioState
local function sonic_update_air(m)
    local dragThreshold = 32
    local speedAngle = atan2s(m.vel.z, m.vel.x)

    local accel = 2
    local targetSpeed = dragThreshold
    local fVel = math.sqrt(m.vel.x ^ 2 + m.vel.z ^ 2)

    local intendedDYaw = m.faceAngle.y - speedAngle
    local intendedMag = m.intendedMag / 32

    if math.abs(intendedDYaw) > 0x4000 then
        fVel = fVel * -1
    end

    m.forwardVel = fVel

    if (check_horizontal_wind(m)) == 0 then

        if m.pos.y < m.waterLevel then
            accel = 1
        end

        if (m.input & INPUT_NONZERO_ANALOG) ~= 0 then
            m.faceAngle.y = m.intendedYaw
            if fVel > dragThreshold then
                targetSpeed = fVel
            else
                targetSpeed = dragThreshold
            end

            m.vel.x = approach_f32_symmetric(m.vel.x, targetSpeed * sins(m.intendedYaw) * intendedMag, accel)
            m.vel.z = approach_f32_symmetric(m.vel.z, targetSpeed * coss(m.intendedYaw) * intendedMag, accel)
        end

        local airDrag = (fVel / 0.125) / 256

        if m.vel.y > 0 and m.vel.y < 32 then
            m.vel.x = approach_f32_symmetric(m.vel.x, 0, airDrag)
            m.vel.z = approach_f32_symmetric(m.vel.z, 0, airDrag)
        end

        --djui_chat_message_create(tostring(math.abs(speed) * sins(m.intendedYaw) * intendedMag))
    end
end

local function update_sonic_running_speed(m)
    local e = gCharacterStates[m.playerIndex]
    local maxTargetSpeed = 0
    local targetSpeed = 0
    local accel = 1.05

    if (m.floor and m.floor.type == SURFACE_SLOW) then
        maxTargetSpeed = 48
    else
        maxTargetSpeed = 64
    end

    if m.intendedMag < 24 then
        targetSpeed = m.intendedMag
    else
        targetSpeed = maxTargetSpeed
    end

    if m.pos.y < m.waterLevel then
        targetSpeed = targetSpeed / 2
        accel = 1.025
    end

    if (m.quicksandDepth > 10.0) then
        targetSpeed = targetSpeed * (6.25 / m.quicksandDepth)
    end

    if (m.forwardVel <= 0.0) then
        m.forwardVel = m.forwardVel + accel
    elseif (m.forwardVel <= targetSpeed) then
        m.forwardVel = m.forwardVel + (accel - m.forwardVel / targetSpeed)
        --elseif (m.floor and m.floor.normal.y >= 0.95) then
        --m.forwardVel = m.forwardVel - 1.0
    end

    if m.forwardVel > 250 then
        m.forwardVel = 250
    end

    m.faceAngle.y = m.intendedYaw - approach_s32(math.s16(m.intendedYaw - m.faceAngle.y), 0, 0x800, 0x800)

    apply_slope_accel(m)
end


function set_sonic_jump_vel(m, jumpForce, initialVelY)
    local velY = 0

    if initialVelY then velY = initialVelY end

    m.vel.x = m.vel.x + jumpForce * m.floor.normal.x
    m.vel.z = m.vel.z + jumpForce * m.floor.normal.z

    m.vel.y = velY + jumpForce * m.floor.normal.y
end

-- mfw align_with_floor(m) aligns with walls
local function align_with_floor_but_better(m)
    if not m.floor then return end
    m.marioObj.header.gfx.angle.x = find_floor_slope(m, 0x8000)
    m.marioObj.header.gfx.angle.z = find_floor_slope(m, 0x4000)
end

CUSTOM_CHAR_ANIM_SONIC_RUN = 'sonic_running_2'
CUSTOM_CHAR_ANIM_SONIC_SPRING_RISE = 'sonic_spring'
CUSTOM_CHAR_ANIM_SONIC_SPRING_FALL = 'sonic_spring_fall'

--- @param m MarioState
--- @param walkCap number
--- @param jogCap number
--- @param runCap number
local function sonic_anim_and_audio_for_walk(m, walkCap, jogCap, runCap)
    local val14 = 0
    local val0C = true
    local val04 = 4.0

    if val14 < 4 then
        val14 = 4
    end

    if m.forwardVel > 2 then
        val04 = math.abs(m.forwardVel)
    else
        val04 = 5
    end

    if (m.quicksandDepth > 50.0) then
        val14 = (val04 / 4.0 * 0x10000)
        set_mario_anim_with_accel(m, MARIO_ANIM_MOVE_IN_QUICKSAND, val14)
        play_step_sound(m, 19, 93)
        m.actionTimer = 0
    else
        if val0C then
            if m.actionTimer == 0 then
                if (val04 > 8.0) then
                    m.actionTimer = 2
                else
                    --(Speed Crash) If Mario's speed is more than 2^17.
                    if (val14 < 0x1000) then
                        val14 = 0x1000
                    else
                        val14 = (val04 / 4.0 * 0x10000)
                    end
                    set_mario_animation(m, MARIO_ANIM_START_TIPTOE)
                    play_step_sound(m, 7, 22)
                    if (is_anim_past_frame(m, 23)) then
                        m.actionTimer = 2
                    end

                    val0C = false
                end
            elseif m.actionTimer == 1 then
                if (val04 > 8.0) or m.intendedMag > 8.0 then
                    m.actionTimer = 2
                else
                    -- (Speed Crash) If Mario's speed is more than 2^17.
                    if (val14 < 0x1000) then
                        val14 = 0x1000
                    else
                        val14 = (val04 / 4.0 * 0x10000)
                    end
                    set_mario_animation(m, MARIO_ANIM_TIPTOE)
                    play_step_sound(m, 14, 72)

                    val0C = false
                end
            elseif m.actionTimer == 2 then
                if (val04 < 5.0) then
                    m.actionTimer = 1
                elseif (val04 > walkCap) then
                    m.actionTimer = 3
                else
                    set_mario_anim_with_accel(m, MARIO_ANIM_WALKING, 2.0 * 0x10000)
                    play_step_sound(m, 10, 49)

                    val0C = false
                end
            elseif m.actionTimer == 3 then
                if (val04 <= walkCap) then
                    m.actionTimer = 2
                else
                    if m.forwardVel > runCap then
                        play_step_sound(m, 11, 22)
                        set_mario_anim_with_accel(m, MARIO_ANIM_RUNNING_UNUSED, m.forwardVel/8 * 0x8000)
                    elseif m.forwardVel > jogCap then
                        play_step_sound(m, 14, 29)
                        play_custom_anim(m, CUSTOM_CHAR_ANIM_SONIC_RUN, m.forwardVel/8 * 0x8000)
                    else
                        play_step_sound(m, 26, 58)
                        set_mario_anim_with_accel(m, MARIO_ANIM_RUNNING, m.forwardVel/2.0 * 0x8000)
                    end
                    if jogCap - val04 <= 30 and math.sign(jogCap - val04) == 1 then
                        m.marioBodyState.allowPartRotation = true
                        m.marioBodyState.torsoAngle.x = degrees_to_sm64(30 - (jogCap - val04))
                    else
                        m.marioBodyState.torsoAngle.x = 0
                        m.marioBodyState.allowPartRotation = false
                    end

                    val0C = false
                end
            end
        end
    end

    --marioObj.oMarioWalkingPitch = math.s16(approach_s32(marioObj.oMarioWalkingPitch, find_floor_slope(m, 0x8000), 0x800, 0x800))
    align_with_floor_but_better(m)
end

function badnik_bounce(m, prevHeightInput, currentGravity)
    local targetVel = math.sqrt(currentGravity * 2 * math.abs(prevHeightInput - m.pos.y))
    local trueTargetVel = 0

    if targetVel ^ 2 > m.vel.y ^ 2 then
        trueTargetVel = targetVel
    else
        trueTargetVel = math.abs(m.vel.y)
    end

    if (m.action & ACT_FLAG_AIR) ~= 0 then
        m.vel.y = trueTargetVel
    end
end

function move_with_current(m)
    if (m.flags & MARIO_METAL_CAP) ~= 0 then
        return
    end
    local step = gVec3fZero()
    vec3f_copy(m.marioObj.header.gfx.pos, m.pos)

    apply_water_current(m, step)

    m.pos.x = m.pos.x + step.x
    m.pos.y = m.pos.y + step.y
    m.pos.z = m.pos.z + step.z
end

--- @param m MarioState
--- @param landAction integer
--- @param animation MarioAnimID
--- @param stepArg integer
--- @param bonking? boolean
--- @return integer
function sonic_air_action_step(m, landAction, animation, stepArg, bonking)
    local stepResult = perform_air_step(m, stepArg)

    if (m.action == ACT_BUBBLED and stepResult == AIR_STEP_HIT_LAVA_WALL) then
        stepResult = AIR_STEP_HIT_WALL
    end

    if stepResult == AIR_STEP_NONE then
        set_mario_animation(m, animation)
    end

    if stepResult == AIR_STEP_LANDED then

        if (check_fall_damage_or_get_stuck(m, ACT_HARD_BACKWARD_GROUND_KB) == 0) then
            if math.abs(m.forwardVel) > 1 then
                m.faceAngle.y = atan2s(m.vel.z, m.vel.x)
                mario_set_forward_vel(m, math.sqrt(m.vel.x ^ 2 + m.vel.z ^ 2))
                return set_mario_action(m, ACT_SONIC_RUNNING, 0)
            else
                m.faceAngle.y = m.faceAngle.y
                set_mario_action(m, landAction, 0)
            end
        end

    elseif stepResult == AIR_STEP_HIT_WALL and bonking then
        set_mario_animation(m, animation)

        if (m.forwardVel > 16.0) then
            queue_rumble_data_mario(m, 5, 40)
            mario_bonk_reflection(m, 0)
            m.faceAngle.y = m.faceAngle.y + 0x8000

            if (m.wall) then
                set_mario_action(m, ACT_AIR_HIT_WALL, 0)
            else
                if (m.vel.y > 0.0) then
                    m.vel.y = 0.0
                end

                --! Hands-free holding. Bonking while no wall is referenced
                -- sets Mario's action to a non-holding action without
                -- dropping the object, causing the hands-free holding
                -- glitch. This can be achieved using an exposed ceiling,
                -- out of bounds, grazing the bottom of a wall while
                -- falling such that the final quarter step does not find a
                -- wall collision, or by rising into the top of a wall such
                -- that the final quarter step detects a ledge, but you are
                -- not able to ledge grab it.
                if (m.forwardVel >= 38.0) then
                    set_mario_particle_flags(m, PARTICLE_VERTICAL_STAR, 0)
                    set_mario_action(m, ACT_BACKWARD_AIR_KB, 0)
                else
                    if (m.forwardVel > 8.0) then
                        m.forwardVel = -8.0
                    end
                    return set_mario_action(m, ACT_SOFT_BONK, 0)
                end
            end
        else
            m.forwardVel = 0.0
        end
    elseif stepResult == AIR_STEP_GRABBED_LEDGE then
        set_mario_animation(m, MARIO_ANIM_IDLE_ON_LEDGE)
        drop_and_set_mario_action(m, ACT_LEDGE_GRAB, 0)
    elseif stepResult == AIR_STEP_GRABBED_CEILING then
        set_mario_action(m, ACT_START_HANGING, 0)
    elseif stepResult == AIR_STEP_HIT_LAVA_WALL then
        lava_boost_on_wall(m)
    end

    sonic_update_air(m)

    return stepResult
end

--- @param m MarioState
--- @param target Object
--- @return integer
--- Target above the enemy.
function sonic_pitch_to_object(m, target)
    if not (m and target) then return 0 end
    local a, b, c, d
    a = target.oPosX - m.pos.x
    c = target.oPosZ - m.pos.z
    a = math.sqrt(a ^ 2 + c ^ 2)

    b = -m.pos.y
    d = -(target.oPosY + target.hitboxHeight)

    return atan2s(a, d - b)
end

_G.ACT_SPIN_JUMP          = allocate_mario_action(ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_CONTROL_JUMP_HEIGHT | ACT_FLAG_AIR | ACT_GROUP_AIRBORNE | ACT_FLAG_ATTACKING)
_G.ACT_SONIC_FALL         = allocate_mario_action(ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_AIR | ACT_GROUP_AIRBORNE)
_G.ACT_AIR_SPIN           = allocate_mario_action(ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_AIR | ACT_FLAG_ATTACKING | ACT_GROUP_AIRBORNE)
_G.ACT_HOMING_ATTACK      = allocate_mario_action(ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION | ACT_FLAG_AIR | ACT_FLAG_ATTACKING | ACT_GROUP_AIRBORNE)
_G.ACT_SPIN_DASH_CHARGE   = allocate_mario_action(ACT_FLAG_STATIONARY | ACT_GROUP_STATIONARY | ACT_FLAG_SHORT_HITBOX)
_G.ACT_BOUNCE_LAND        = allocate_mario_action(ACT_FLAG_STATIONARY | ACT_GROUP_STATIONARY | ACT_FLAG_SHORT_HITBOX | ACT_FLAG_ATTACKING)
_G.ACT_SPIN_DASH          = allocate_mario_action(ACT_FLAG_MOVING | ACT_GROUP_MOVING | ACT_FLAG_SHORT_HITBOX | ACT_FLAG_ATTACKING)
_G.ACT_SONIC_RUNNING      = allocate_mario_action(ACT_FLAG_MOVING | ACT_GROUP_MOVING)

local SOUND_SPIN_JUMP           = audio_sample_load("spinjump.ogg")   -- Load audio sample
local SOUND_SPIN_CHARGE         = audio_sample_load("spincharge.ogg") -- Load audio sample
local SOUND_SPIN_RELEASE        = audio_sample_load("spinrelease.ogg") -- Load audio sample
local SOUND_ROLL                = audio_sample_load("spinroll.ogg")   -- Load audio sample
local SOUND_SONIC_BOUNCE        = audio_sample_load("sonicbounce.ogg")   -- Load audio sample
local SOUND_SONIC_HOMING        = audio_sample_load("sonic_homing_select.ogg")   -- Load audio sample
local SOUND_SONIC_INSTA         = audio_sample_load("sonicinstashield.ogg")   -- Load audio sample
local SOUND_SONIC_ELECTRIC_JUMP = audio_sample_load("sonicelectricjump.ogg")   -- Load audio sample

local sonicActionOverride = {
    [ACT_JUMP]         = ACT_SPIN_JUMP,
    [ACT_DOUBLE_JUMP]  = ACT_SPIN_JUMP,
    [ACT_BACKFLIP]     = ACT_SPIN_JUMP,
    [ACT_SIDE_FLIP]    = ACT_SPIN_JUMP,
    [ACT_STEEP_JUMP]   = ACT_SPIN_JUMP,
    [ACT_LONG_JUMP]    = ACT_SPIN_JUMP,
    [ACT_WALKING]      = ACT_SONIC_RUNNING,
    [ACT_CROUCH_SLIDE] = ACT_SPIN_DASH,
}

--- @param o Object
--- @return boolean
--- Checks if `o` is a treasure chest
local function obj_is_treasure_chest(o)
    return obj_has_behavior_id(o, id_bhvTreasureChestBottom) == 1 and o.oAction == 0
end

local breakableObjects = {
    id_bhvBreakableBox,
    id_bhvHiddenObject,
}

--- @param o Object
--- @return boolean
--- Checks if `o` is breakable
local function obj_is_breakable(o)
    local breakable = false
    for _, id_bhv in ipairs(breakableObjects) do
        breakable = obj_has_behavior_id(o, id_bhv) ~= 0
        if breakable then return breakable end
    end
end

local function sonic_is_obj_targetable(obj)
    local targetable = (obj_is_treasure_chest(obj) or obj_is_exclamation_box(obj) or obj_is_bully(obj) or obj_is_breakable(obj) or obj_is_attackable(obj)) and obj_is_valid_for_interaction(obj)
    return targetable
end

local sonicHomingLists = {
    OBJ_LIST_DEFAULT,
    OBJ_LIST_LEVEL,
    OBJ_LIST_SURFACE,
    OBJ_LIST_PUSHABLE,
    OBJ_LIST_GENACTOR,
    OBJ_LIST_DESTRUCTIVE,
}

--- @param m MarioState
--- @param distmax number
--- @return Object
--- Finds the closest target to MarioState `m` within the `distmax` units
function sonic_find_homing_target(m, distmax)
    local target
    local distmin = distmax
    local pos = gVec3fZero()
    vec3f_copy(pos, m.pos)
    for _, objList in pairs(sonicHomingLists) do
        local obj = obj_get_first(objList)
        while obj do
            if sonic_is_obj_targetable(obj) then
                local distToObj = math.sqrt((pos.x - obj.oPosX)^2 + (pos.y - obj.oPosY)^2 + (pos.z - obj.oPosZ)^2) - (m.marioObj.hitboxRadius + obj.hitboxRadius)
                local angleToObj = obj_angle_to_object(m.marioObj, obj)

                if distToObj < distmin and math.abs(m.faceAngle.y - angleToObj) < 0x3800 then
                    distmin = distToObj
                    target = obj
                end
            end
            obj = obj_get_next(obj)
        end
    end
    return target
end


--- @param m MarioState
--- @return integer
local function perform_sonic_a_action(m)
    local o = sonic_find_homing_target(m, 1000)
    local dist = dist_between_objects(m.marioObj, o)
    local e = gCharacterStates[m.playerIndex]

    if m.pos.y < m.waterLevel then
        m.action = ACT_SPIN_JUMP
        m.vel.y = 30
    else

        if not e.sonic.actionADone and e.sonic.instashieldTimer <= 0 then
            if o and dist < 1000 then
                return set_mario_action(m, ACT_HOMING_ATTACK, 0)
            else
                return set_mario_action(m, ACT_AIR_SPIN, 1)
            end
        end
    end
end

--- @param m MarioState
--- @return integer
local function perform_sonic_b_action(m)
    local e = gCharacterStates[m.playerIndex]

    if (m.controller.buttonDown & Z_TRIG) ~= 0 then
        if e.sonic.bounced then return end
        set_mario_action(m, ACT_GROUND_POUND, 0)
        e.sonic.bounced = true
    else
        if e.sonic.actionBDone then return end
        
        if (m.flags & MARIO_METAL_CAP) ~= 0 then
            audio_sample_play(SOUND_SONIC_ELECTRIC_JUMP, m.pos, 1)
            set_mario_action(m, ACT_AIR_SPIN, 0)
            m.vel.y = 52
        else
            audio_sample_play(SOUND_SONIC_INSTA, m.pos, 1)
            e.sonic.instashieldTimer = 7
        end

        e.sonic.actionBDone = true
    end
end

---@param m MarioState
local function act_spin_jump(m)
    local e = gCharacterStates[m.playerIndex]
    if m.actionTimer == 0 then
        audio_sample_play(SOUND_SPIN_JUMP, m.pos, 1)
        play_character_sound_if_no_flag(m, CHAR_SOUND_YAH_WAH_HOO, MARIO_ACTION_SOUND_PLAYED)

        e.sonic.prevForwardVel = m.forwardVel
    end

    local spinSpeed = math.max(0.5, e.sonic.prevForwardVel / 32)
    
    if e.sonic.instashieldTimer > 0 then spinSpeed = 1.5 end

    set_character_animation(m, CHAR_ANIM_A_POSE)
    local stepResult = sonic_air_action_step(m, ACT_DOUBLE_JUMP_LAND, CHAR_ANIM_A_POSE, AIR_STEP_CHECK_HANG)
    m.marioObj.header.gfx.animInfo.animID = -1

    m.faceAngle.x = m.faceAngle.x + (0x2000 * spinSpeed)
    m.marioObj.header.gfx.angle.x = m.faceAngle.x

    if (m.controller.buttonDown & Z_TRIG) ~= 0 then
        if stepResult == AIR_STEP_LANDED then
            audio_sample_play(SOUND_ROLL, m.pos, 1)
            set_mario_action(m, ACT_SPIN_DASH, 0)
        end
    end

    if (m.controller.buttonPressed & A_BUTTON) ~= 0 and m.actionTimer > 0 then
        return perform_sonic_a_action(m)
    end

    if (m.controller.buttonPressed & B_BUTTON) ~= 0 then
        perform_sonic_b_action(m)
    end


    m.actionTimer = m.actionTimer + 1
end

-- The air dash and air roll are grouped into this.
local function act_air_spin(m)
    local e = gCharacterStates[m.playerIndex]

    local spinSpeed = math.max(0.5, e.sonic.prevForwardVel / 32)
    
    if e.sonic.instashieldTimer > 0 then spinSpeed = 1.5 end

    set_character_animation(m, CHAR_ANIM_A_POSE)
    local stepResult = sonic_air_action_step(m, ACT_DOUBLE_JUMP_LAND, CHAR_ANIM_A_POSE, AIR_STEP_CHECK_HANG)
    m.marioObj.header.gfx.animInfo.animID = -1

    m.faceAngle.x = m.faceAngle.x + (0x2000 * spinSpeed)
    m.marioObj.header.gfx.angle.x = m.faceAngle.x

    if (m.input & INPUT_A_PRESSED) ~= 0 and m.actionTimer > 0 then
        return perform_sonic_a_action(m)
    end

    if (m.controller.buttonPressed & B_BUTTON) ~= 0 then
        return perform_sonic_b_action(m)
    end

    if m.actionArg == 1 then -- Air dash and wall bounce.
        if not e.sonic.actionADone then
            e.sonic.prevForwardVel = m.forwardVel
            audio_sample_play(SOUND_SPIN_RELEASE, m.pos, 1)
            m.vel.y = 0

            if m.forwardVel < 0 then
                m.vel.x = m.vel.x + 30 * sins(m.faceAngle.y)
                m.vel.z = m.vel.z + 30 * coss(m.faceAngle.y)
            elseif m.forwardVel < 72 then
                m.vel.x = m.vel.x + 20 * sins(m.faceAngle.y)
                m.vel.z = m.vel.z + 20 * coss(m.faceAngle.y)
            end

            m.particleFlags = m.particleFlags + PARTICLE_VERTICAL_STAR
            e.sonic.actionADone = true
        end

        if m.actionTimer < 10 then

            local dist = 80
            local ray = collision_find_surface_on_ray(m.pos.x, m.pos.y + 30, m.pos.z,
            sins(m.faceAngle.y) * dist, 0, coss(m.faceAngle.y) * dist)

            if ray.surface and ray.surface.normal.y <= 0.01 then

                local wallAngle = wall_bounce(m, ray.surface.normal)
                audio_sample_play(SOUND_SONIC_BOUNCE, m.pos, 1)

                if m.actionTimer < 2 then
                    m.vel.y = 30 * math.abs(realFVel) / 24

                    m.vel.x = math.abs(realFVel / 2) * sins(wallAngle)
                    m.vel.z = math.abs(realFVel / 2) * coss(wallAngle)
                else
                    m.vel.y = 20 * math.abs(realFVel) / 32

                    m.vel.x = math.abs(realFVel) * sins(wallAngle)
                    m.vel.z = math.abs(realFVel) * coss(wallAngle)
                end

                m.actionArg = 0
                e.sonic.actionADone = false
            end

        end

    end

    if (m.controller.buttonDown & Z_TRIG) ~= 0 then
        if stepResult == AIR_STEP_LANDED then
            audio_sample_play(SOUND_ROLL, m.pos, 1)
            set_mario_action(m, ACT_SPIN_DASH, 0)
        end
    end

    m.actionTimer = m.actionTimer + 1
end

--- @param m MarioState
local function act_homing_attack(m)
    local e = gCharacterStates[m.playerIndex]
    local spinSpeed = math.max(0.5, e.sonic.prevForwardVel / 32)
    local o = sonic_find_homing_target(m, 1000)
    local yaw, pitch

    if o and sonic_is_obj_targetable(o) then
        yaw = obj_angle_to_object(m.marioObj, o)
        pitch = sonic_pitch_to_object(m, o) - degrees_to_sm64(5)
        if o.collisionData then
            pitch = sonic_pitch_to_object(m, o) + degrees_to_sm64(5)
        end
    end

    if m.actionTimer <= 0 then
        audio_sample_play(SOUND_SPIN_RELEASE, m.pos, 1)
        m.particleFlags = m.particleFlags + PARTICLE_VERTICAL_STAR
        local totalVel = math.sqrt(m.forwardVel ^ 2 + m.vel.y ^ 2)

        if totalVel < 100 then
            m.forwardVel = 100
        elseif totalVel >= 100 and totalVel < 172 then
            m.forwardVel = totalVel + 20
        end

        m.vel.y = math.abs(m.forwardVel) * sins(-pitch)
        m.vel.x = math.abs(m.forwardVel) * sins(yaw) * coss(pitch)
        m.vel.z = math.abs(m.forwardVel) * coss(yaw) * coss(pitch)

        m.faceAngle.y = yaw
    end

    set_character_animation(m, CHAR_ANIM_A_POSE)
    m.particleFlags = m.particleFlags + PARTICLE_DUST
    m.marioObj.header.gfx.animInfo.animID = -1

    local stepResult = perform_air_step(m, 0)
    if stepResult == AIR_STEP_LANDED then
        if (m.controller.buttonDown & Z_TRIG) ~= 0 then
            audio_sample_play(SOUND_ROLL, m.pos, 1)
            set_mario_action(m, ACT_SPIN_DASH, 0)
        else

            if (check_fall_damage_or_get_stuck(m, ACT_HARD_BACKWARD_GROUND_KB) == 0) then
                m.faceAngle.y = atan2s(m.vel.z, m.vel.x)
                mario_set_forward_vel(m, math.sqrt(m.vel.x ^ 2 + m.vel.z ^ 2))
                set_mario_action(m, ACT_SONIC_RUNNING, 0)
            end
        end

    end

    m.faceAngle.x = m.faceAngle.x + (0x2000 * spinSpeed)
    m.marioObj.header.gfx.angle.x = m.faceAngle.x

    if o == nil then
        set_mario_action(m, ACT_AIR_SPIN, 0)
        e.actionADone = true
    end

    m.actionTimer = m.actionTimer + 1
end

-- Code nabbed from Shell Rush.
function wall_bounce(m, normal)
    -- figure out direction
    local v = gVec3fZero()
    v.x = m.vel.x
    v.z = m.vel.z

    -- projection
    local parallel = vec3f_project(gVec3fZero(), v, normal)
    local perpendicular = { x = v.x - parallel.x, y = v.y - parallel.y, z = v.z - parallel.z }

    -- reflect velocity along normal
    local reflect = {
        x = perpendicular.x - parallel.x,
        y = perpendicular.y - parallel.y,
        z = perpendicular.z - parallel.z
    }

    return atan2s(reflect.z, reflect.x)
end

---@param m MarioState
local function act_spin_dash_charge(m)
    local e = gCharacterStates[m.playerIndex]
    local MINDASH = 4
    local MAXDASH = 128
    local decel = (e.sonic.spinCharge / 0.125) / 256

    if (m.controller.buttonPressed & B_BUTTON) ~= 0 then
        audio_sample_play(SOUND_SPIN_CHARGE, m.pos, 1)
        e.sonic.spinCharge = math.min(e.sonic.spinCharge + 32, MAXDASH)
    else
        e.sonic.spinCharge = approach_f32_symmetric(e.sonic.spinCharge, MINDASH, decel)
    end

    set_mario_animation(m, CHAR_ANIM_A_POSE)
    m.marioObj.header.gfx.animInfo.animID = -1
    stationary_ground_step(m)

    if math.floor(e.sonic.spindashState) > 7 then
        e.sonic.spindashState = 0
    end

    m.marioObj.header.gfx.pos.y = m.pos.y + 60

    if m.input & INPUT_Z_DOWN == 0 then
        audio_sample_play(SOUND_SPIN_RELEASE, m.pos, 1)
        mario_set_forward_vel(m, e.sonic.spinCharge)
        e.sonic.spinCharge = 0
        return set_mario_action(m, ACT_SPIN_DASH, 0)
    end
    e.sonic.spindashState = e.sonic.spindashState + e.sonic.spinCharge / 50
end

---@param m MarioState
local function act_spin_dash(m)
    local e = gCharacterStates[m.playerIndex]

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        return set_mario_action(m, ACT_JUMP, 0)
    end

    set_mario_animation(m, CHAR_ANIM_A_POSE)
    m.marioObj.header.gfx.animInfo.animID = -1
    local stepResult = perform_ground_step(m)

    if stepResult == GROUND_STEP_HIT_WALL then
        if m.forwardVel > 16 then
            set_mario_particle_flags(m, ACTIVE_PARTICLE_H_STAR, 0)
            return slide_bonk(m, ACT_GROUND_BONK, ACT_GROUND_BONK)
        else
            return set_mario_action(m, ACT_CROUCHING, 0)
        end
    elseif stepResult == GROUND_STEP_LEFT_GROUND then
        m.vel.y = e.sonic.groundYVel
        set_mario_action(m, ACT_AIR_SPIN, 0)
    end

    local spinPhys = update_spin_dashing(m, 3)

    if spinPhys ~= 0 then
        return set_mario_action(m, ACT_CROUCHING, 0)
    end

    m.faceAngle.x = m.faceAngle.x + 0x2000 * m.forwardVel / 32
    m.marioObj.header.gfx.angle.x = m.faceAngle.x

    m.marioObj.header.gfx.pos.y = m.pos.y + 60

    m.actionTimer = m.actionTimer + 1
end

--- @param m MarioState
local function act_sonic_running(m)
    local e = gCharacterStates[m.playerIndex]
    mario_drop_held_object(m)

    m.actionState = 0
    update_sonic_running_speed(m)
    local stepResult = perform_ground_step(m)

    if stepResult == GROUND_STEP_LEFT_GROUND then
        m.vel.y = e.sonic.groundYVel
        set_mario_action(m, ACT_FREEFALL, 0)
        set_mario_animation(m, MARIO_ANIM_GENERAL_FALL)
    elseif stepResult == GROUND_STEP_NONE then
        sonic_anim_and_audio_for_walk(m, 10, 40, 70)
        if (m.intendedMag - m.forwardVel) > 16 then
            set_mario_particle_flags(m, PARTICLE_DUST, 0)
        end
    elseif stepResult == GROUND_STEP_HIT_WALL then
        push_or_sidle_wall(m, m.pos)
        m.actionTimer = 0
    end

    check_ledge_climb_down(m)

    if should_begin_sliding(m) ~= 0 then
        return set_mario_action(m, ACT_BEGIN_SLIDING, 0)
    end

    if (m.input & INPUT_Z_PRESSED) ~= 0 then
        audio_sample_play(SOUND_ROLL, m.pos, 1)
        return set_mario_action(m, ACT_CROUCH_SLIDE, 0)
    end

    if (m.input & INPUT_FIRST_PERSON) ~= 0 then
        return begin_braking_action(m)
    end

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        return set_jump_from_landing(m)
    end

    if (check_ground_dive_or_punch(m)) ~= 0 then
        return true
    end

    if (m.input & INPUT_ZERO_MOVEMENT) ~= 0 then
        mario_set_forward_vel(m, approach_f32_symmetric(m.forwardVel, 0, 1))
        if m.forwardVel <= 0 then
            set_mario_action(m, ACT_IDLE, 0)
        end
    end

    if analog_stick_held_back(m) ~= 0 then
        return set_mario_action(m, ACT_TURNING_AROUND, 0)
    end

    return 0
end

function act_sonic_fall(m)
    local animation = 0
    local landAction = 0
    local e = gCharacterStates[m.playerIndex]

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        return perform_sonic_a_action(m)
    end

    if (m.input & INPUT_B_PRESSED) ~= 0 then
        set_mario_action(m, ACT_AIR_SPIN, 0)
        return perform_sonic_b_action(m)
    end
    
    if not m.heldObj then
        if m.actionArg == 0 then
            animation = CHAR_ANIM_GENERAL_FALL
            m.faceAngle.x = 0
        elseif m.actionArg == 1 then
            animation = CHAR_ANIM_FALL_FROM_SLIDE
            m.faceAngle.x = 0
        elseif m.actionArg == 2 then
            animation = CHAR_ANIM_FALL_FROM_SLIDE_KICK
            m.faceAngle.x = 0
        elseif m.actionArg == 3 then
            if m.vel.y > 0 then
                animation = CHAR_ANIM_DOUBLE_JUMP_RISE
            else
                animation = CHAR_ANIM_DOUBLE_JUMP_FALL
            end
            m.faceAngle.x = 0
        elseif m.actionArg == 4 then
            if m.vel.y > 0 then
                animation = CHAR_ANIM_DOUBLE_JUMP_RISE
                smlua_anim_util_set_animation(m.marioObj, CUSTOM_CHAR_ANIM_SONIC_SPRING_RISE)
            else
                animation = CHAR_ANIM_DOUBLE_JUMP_FALL
                smlua_anim_util_set_animation(m.marioObj, CUSTOM_CHAR_ANIM_SONIC_SPRING_FALL)
            end
            m.faceAngle.x = 0
        end
        landAction = ACT_FREEFALL_LAND
    else
        animation = MARIO_ANIM_FALL_WITH_LIGHT_OBJ
        landAction = ACT_HOLD_FREEFALL_LAND
    end

    sonic_air_action_step(m, landAction, animation, AIR_STEP_CHECK_LEDGE_GRAB, true)

    m.actionTimer = m.actionTimer + 1

    return 0
end

local function act_bounce_land(m)
    m.actionState = 1
    if (m.input & INPUT_UNKNOWN_10) ~= 0 then
        return drop_and_set_mario_action(m, ACT_SHOCKWAVE_BOUNCE, 0)
    end

    if (m.input & INPUT_OFF_FLOOR) ~= 0 then
        return set_mario_action(m, ACT_FREEFALL, 0)
    end

    stationary_ground_step(m)
    
    audio_sample_play(SOUND_SONIC_BOUNCE, m.pos, 1)
    set_sonic_jump_vel(m, 85)
    return set_mario_action(m, ACT_AIR_SPIN, 0)
end

local waterActions = {
    [ACT_WATER_PLUNGE]          = true,
    [ACT_WATER_IDLE]            = true,
    [ACT_FLUTTER_KICK]          = true,
    [ACT_SWIMMING_END]          = true,
    [ACT_WATER_ACTION_END]      = true,
    [ACT_HOLD_WATER_IDLE]       = true,
    [ACT_HOLD_WATER_JUMP]       = true,
    [ACT_HOLD_WATER_ACTION_END] = true,
    [ACT_BREASTSTROKE]          = true
}

local instashieldActions = {
    [ACT_SPIN_JUMP]        = true,
    [ACT_AIR_SPIN]         = true,
}

---@param m MarioState
---@param action integer
function before_set_sonic_action(m, action, actionArg)
    local e = gCharacterStates[m.playerIndex]

    if waterActions[action] then -- Prevent swimming in the air.
        return ACT_SPIN_JUMP
    end
    
    if sonicActionOverride[action] then
        set_sonic_jump_vel(m, 64, e.sonic.groundYVel)
        return sonicActionOverride[action]
    end

    if action == ACT_PUNCHING and actionArg == 9 then
        return ACT_SPIN_DASH_CHARGE
    end

    if action == ACT_GROUND_POUND_LAND then
        return ACT_BOUNCE_LAND
    end
end

function on_set_sonic_action(m)
    if m.faceAngle.x ~= 0 then
        m.faceAngle.x = 0
    end

    if m.marioObj.header.gfx.angle.x ~= 0 then
        m.marioObj.header.gfx.angle.x = 0
    end

    if m.action == ACT_FREEFALL then
        set_mario_action(m, ACT_SONIC_FALL, m.actionArg)
    end

    if m.action == ACT_TRIPLE_JUMP then
        set_mario_action(m, ACT_SONIC_FALL, 4)
    end
end

--- @param m MarioState
function sonic_update(m)
    local e = gCharacterStates[m.playerIndex]
    
    local groundMovingActions = {
        [ACT_SONIC_RUNNING] = 1,
        [ACT_SPIN_DASH] = 1,
        [ACT_DECELERATING] = 1,
        [ACT_BUTT_SLIDE] = 1
    }

    if groundMovingActions[m.action] then
        e.sonic.groundYVel = -math.sqrt(m.vel.x ^ 2 + m.vel.z ^ 2) * sins(find_floor_slope(m, 0x8000))
    else
        e.sonic.groundYVel = 0
    end

    if (m.action & ACT_FLAG_AIR) ~= 0 and m.action ~= ACT_GROUND_POUND then
        if m.vel.y >= 0 then
            prevHeight = m.pos.y
        end
    end

    -- Bounce attack that's just a modified ground pound.
    if m.action == ACT_GROUND_POUND then
        smlua_anim_util_set_animation(m.marioObj, 'sonic_before_ground_pound')
        if m.actionTimer > 15 then
            set_character_animation(m, CHAR_ANIM_A_POSE)
            m.marioObj.header.gfx.animInfo.animID = -1
            m.faceAngle.x = m.faceAngle.x + 0x4000
            m.marioObj.header.gfx.angle.x = m.faceAngle.x
            m.particleFlags = m.particleFlags + PARTICLE_DUST
        end
        
        if m.pos.y < m.waterLevel then
            m.vel.y = -60
        else
            m.vel.y = -100
        end
        m.actionTimer = m.actionTimer + 1
    end

    if (m.action & ACT_FLAG_AIR) == 0 and m.action ~= ACT_BOUNCE_LAND then
        e.sonic.actionADone = false
        e.sonic.actionBDone = false
        e.sonic.bounced = false
        e.sonic.instashieldTimer = 0
    end

    -- Splash.
    if m.pos.y <= m.waterLevel and m.pos.y >= m.waterLevel - math.abs(m.vel.y) then
        if math.abs(m.vel.y) > 40 then
            m.particleFlags = m.particleFlags + PARTICLE_WATER_SPLASH
            play_sound(SOUND_ACTION_UNKNOWN430, m.marioObj.header.gfx.cameraToObject)
        elseif math.abs(m.vel.y) > 0 then
            m.particleFlags = m.particleFlags + PARTICLE_SHALLOW_WATER_SPLASH
        end
    end

    -- Fall damage delay.
    if e.sonic.peakHeight - m.pos.y < 2000 then m.peakHeight = m.pos.y end
    if m.vel.y >= 0 or m.pos.y == m.floorHeight then e.sonic.peakHeight = m.pos.y end

    -- Insta-shield attack. The best way I can do it for now.
    if e.sonic.instashieldTimer > 0 and instashieldActions[m.action] then
		for objList = 0, NUM_OBJ_LISTS - 1 do
			local obj = obj_get_first(objList)
			while obj ~= nil do
				if (obj_is_attackable(obj) or obj_is_breakable_object(obj) or obj_has_behavior_id(obj, id_bhvBobomb) ~= 0) then
					if (dist_between_objects(m.marioObj, obj) <= 280 and obj_is_valid_for_interaction(obj)) then
						obj.oInteractStatus = ATTACK_KICK_OR_TRIP + (INT_STATUS_INTERACTED | INT_STATUS_WAS_ATTACKED)
					end
				end
				obj = obj_get_next(obj)
			end
		end
    end
    
    e.sonic.instashieldTimer = e.sonic.instashieldTimer - 1

    -- Drowning. Should it be added back?
    --[[if m.pos.y < m.waterLevel then
        m.health = m.health - 1
        return false
    end]]
end

local bounceTypes = {
    [INTERACT_BOUNCE_TOP]  = true,
    [INTERACT_BOUNCE_TOP2] = true,
    [INTERACT_KOOPA]       = true
}

function sonic_allow_interact(m, o, intType)
    local e = gCharacterStates[m.playerIndex]
    
    if e.sonic.instashieldTimer > 0 and instashieldActions[m.action] then
        return false
    end
        

    if bounceTypes[intType] then
        prevVelY = m.vel.y
    end

    if bounceTypes[intType] and (o.oInteractionSubtype & INT_SUBTYPE_TWIRL_BOUNCE) == 0 then
        if m.action == ACT_HOMING_ATTACK then
            if m.vel.y < 0 then
                m.vel.y = math.abs(m.vel.y)
            end
            set_mario_action(m, ACT_SONIC_FALL, 3)
            o.oInteractStatus = ATTACK_GROUND_POUND_OR_TWIRL + (INT_STATUS_INTERACTED | INT_STATUS_WAS_ATTACKED)
            return false
        end
    end

end

local badnikBounceActions = {
    [ACT_SPIN_JUMP] = true,
    [ACT_SONIC_FALL] = true,
    [ACT_AIR_SPIN] = true,
    [ACT_GROUND_POUND] = true,
}

function sonic_on_interact(m, o, intType)
    if (m.action == ACT_SONIC_RUNNING) and not m.heldObj then
        if obj_has_behavior_id(o, id_bhvDoorWarp) ~= 0 then
            set_mario_action(m, ACT_DECELERATING, 0)
            interact_warp_door(m, 0, o)
        elseif obj_has_behavior_id(o, id_bhvDoor) ~= 0 or obj_has_behavior_id(o, id_bhvStarDoor) ~= 0 then
            set_mario_action(m, ACT_DECELERATING, 0)
            interact_door(m, 0, o)
        end
    end

    if bounceTypes[intType] and (o.oInteractionSubtype & INT_SUBTYPE_TWIRL_BOUNCE) == 0 then
        if prevVelY < 0 and m.pos.y > o.oPosY then
            if badnikBounceActions[m.action] then
                if m.action == ACT_GROUND_POUND then
                    set_mario_particle_flags(m, PARTICLE_HORIZONTAL_STAR, 0)
                    play_sound(SOUND_ACTION_HIT_2, m.marioObj.header.gfx.cameraToObject)
                    set_mario_action(m, ACT_AIR_SPIN, 0)
                end
                
                o.oInteractStatus = ATTACK_FROM_ABOVE + (INT_STATUS_INTERACTED | INT_STATUS_WAS_ATTACKED)
                badnik_bounce(m, prevHeight, 4)
            end
        end
    end

    if intType == INTERACT_BREAKABLE then
        if m.action == ACT_HOMING_ATTACK then
            set_mario_action(m, ACT_AIR_SPIN, 0)
        end
    end
end

function sonic_before_phys_step(m)
    if m.playerIndex ~= 0 then return end
    if m.pos.y < m.waterLevel then
        move_with_current(m)
        if (m.action & ACT_FLAG_AIR) ~= 0 then
            m.vel.y = m.vel.y + 2
        end
    end

    if physTimer > 0 then
        realFVel = math.sqrt((m.pos.x - lastforwardPos.x) ^ 2 + (m.pos.z - lastforwardPos.z) ^ 2)
        local speedAngle = atan2s(m.vel.z, m.vel.x)
        local intendedDYaw = m.faceAngle.y - speedAngle

        if math.abs(intendedDYaw) > 0x4000 then
            realFVel = realFVel * -1
        end

        vec3f_copy(lastforwardPos, m.pos)

        physTimer = 0
    end

    --djui_chat_message_create(tostring(m.floor.normal.x) .. ", " .. tostring(m.floor.normal.y) .. ", " .. tostring(m.floor.normal.z))
    physTimer = physTimer + 1
end

local homingActs = {
    [ACT_SPIN_JUMP]     = true,
    [ACT_AIR_SPIN]      = true,
    [ACT_SONIC_FALL]    = true,
    [ACT_HOMING_ATTACK] = true,
}

local scaleTimer = 0
local prevScale = 1
local prevHudPos = gVec3fZero()
local hudPos = gVec3fZero()
local prevTarget

function sonic_homing_hud()
    djui_hud_set_resolution(RESOLUTION_N64)
    local color = network_player_get_palette_color(gNetworkPlayers[0], EMBLEM)
    djui_hud_set_color(color.r, color.g, color.b, 255)
    local m = gMarioStates[0]
    local e = gCharacterStates[m.playerIndex]

    if homingActs[m.action] then
        local o = sonic_find_homing_target(m, 995)

        if o and not e.sonic.actionADone then
            local pos = gVec3fZero()
            scaleTimer = scaleTimer + 1

            if prevTarget ~= o then
                prevTarget = o
                audio_sample_play(SOUND_SONIC_HOMING, l.pos, 3)
            end

            object_pos_to_vec3f(pos, o)
            local onScreen = djui_hud_world_pos_to_screen_pos(pos, hudPos)
            if onScreen then
                local scale = (((math.sin(scaleTimer / 5) / 16) + 1)) * (-300 / hudPos.z * djui_hud_get_fov_coeff())
                djui_hud_render_texture_interpolated(TEX_HOMING_CURSOR, prevHudPos.x - 64 * prevScale, prevHudPos.y - 64 * prevScale, 8 * prevScale, 8 * prevScale, hudPos.x - 64 * scale, hudPos.y - 64 * scale, 8 * scale, 8 * scale)
                vec3f_copy(prevHudPos, hudPos)
                prevScale = scale
            end
        else
            scaleTimer = 0
            prevTarget = nil
        end
    else
        scaleTimer = 0
        prevTarget = nil
    end
end

-- Removes Sonic's defacto speed on slopes.

function sonic_defacto_fix(m)
    if get_options_status(6) == 0 or are_movesets_restricted() or character_get_current_number() ~= CT_SONIC then return end
    local floorNormal = m.floor.normal.y
    local floorDYaw = m.floorAngle - m.faceAngle.y

    if (m.floor.normal.y < 0.9 and (math.abs(floorDYaw) <= 0x4500 and math.abs(floorDYaw) >= 0x3500)) then
        floorNormal = math.max(math.abs(sins(floorDYaw)), m.floor.normal.y)
    end

    return floorNormal
end

hook_mario_action(ACT_SPIN_JUMP, act_spin_jump)
hook_mario_action(ACT_SPIN_DASH_CHARGE, act_spin_dash_charge, INT_FAST_ATTACK_OR_SHELL)
hook_mario_action(ACT_SPIN_DASH, act_spin_dash, INT_FAST_ATTACK_OR_SHELL)
hook_mario_action(ACT_SONIC_RUNNING, act_sonic_running)
hook_mario_action(ACT_SONIC_FALL, act_sonic_fall)
hook_mario_action(ACT_AIR_SPIN, act_air_spin)
hook_mario_action(ACT_HOMING_ATTACK, { every_frame = act_homing_attack, gravity = function () end }, (INT_FAST_ATTACK_OR_SHELL | INT_KICK | INT_HIT_FROM_ABOVE))
hook_mario_action(ACT_BOUNCE_LAND, act_bounce_land, INT_GROUND_POUND_OR_TWIRL)

hook_event(HOOK_MARIO_OVERRIDE_PHYS_STEP_DEFACTO_SPEED, sonic_defacto_fix)