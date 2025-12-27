-------------------------
-- Donkey Kong Moveset --
-------------------------

if not charSelect then return end

DONKEY_KONG_ROLL_SPEED = 60
DONKEY_KONG_ROLL_DECAY_PERCENT = 0.98
DONKEY_KONG_ROLL_DECAY_TIME = 10
DONKEY_KONG_ROLL_STARTUP = 4
DONKEY_KONG_ROLL_END = 25


----------------
-- DK Gravity --
----------------

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
--- TODO: this prevents DK from ledge grabbing. Is this fixable?
function perform_donkey_kong_air_step(m, stepArg)
    local intendedPos = gVec3fZero()
    local quarterStepResult
    local stepResult = AIR_STEP_NONE

    m.wall = nil

    for i = 0, 3 do
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
        set_find_wall_direction(step, true, true)

        quarterStepResult = perform_air_quarter_step(m, intendedPos, stepArg)
        set_find_wall_direction(step, false, false)

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

function donkey_kong_before_phys_step(m, stepType, stepArg)
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

function donkey_kong_before_action(m, action, actionArg)
    if (action == ACT_DIVE or action == ACT_MOVE_PUNCHING) and m.action & ACT_FLAG_AIR == 0 and m.input & INPUT_A_DOWN == 0 and m.forwardVel >= 20 then
        m.vel.y = 20
        m.faceAngle.x = 0
        return ACT_DONKEY_KONG_ROLL
    elseif (action == ACT_PUNCHING and actionArg == 9) then
        return ACT_DONKEY_KONG_POUND
    end
end

function donkey_kong_on_interact(m, o, type, value)
    -- allow donkey kong to grab objects with the roll
    if type == INTERACT_GRABBABLE and m.action == ACT_DONKEY_KONG_ROLL then
        if ((o.oInteractionSubtype & INT_SUBTYPE_NOT_GRABBABLE) == 0) then
            m.interactObj = o
            m.input = m.input | INPUT_INTERACT_OBJ_GRABBABLE
            if (o.oSyncID ~= 0) then network_send_object(o, false) end
            return 1
        end
    end
end

function on_attack_object(m, o, interaction)
    -- speed up when hitting enemies with roll
    if (m.action == ACT_DONKEY_KONG_ROLL or m.action == ACT_DONKEY_KONG_ROLL_AIR) and (interaction & INT_FAST_ATTACK_OR_SHELL ~= 0) then
        if o.oInteractType == INTERACT_BULLY then
            mario_set_forward_vel(m, -25)
            m.actionTimer = DONKEY_KONG_ROLL_DECAY_TIME
            m.actionArg = 1
        else
            local newForwardVel = math.min(m.forwardVel * 1.1, 70)
            mario_set_forward_vel(m, newForwardVel)
            m.actionTimer = 0
            m.actionArg = 0
        end
    end
	
	-- Bounce code
	if (CT_DONKEY_KONG ~= _G.charSelect.character_get_current_number(m.playerIndex)) then return end
    if (_G.charSelect.get_options_status(6) ~= 0) then
        if (interaction == INT_HIT_FROM_ABOVE and m.framesSinceA < 5) then
            m.actionTimer = 0
            if (m.action == ACT_DONKEY_KONG_BOUNCE) then
                set_mario_action(m, ACT_DONKEY_KONG_BOUNCE, m.actionArg + 1)
            else
                set_mario_action(m, ACT_DONKEY_KONG_BOUNCE, 1)
            end
        end
    end
end
hook_event(HOOK_ON_ATTACK_OBJECT, on_attack_object)

_G.ACT_DONKEY_KONG_ROLL = allocate_mario_action(ACT_GROUP_MOVING | ACT_FLAG_ATTACKING | ACT_FLAG_MOVING)
_G.ACT_DONKEY_KONG_ROLL_AIR = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_ATTACKING | ACT_FLAG_AIR | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION)
_G.ACT_DONKEY_KONG_POUND = allocate_mario_action(ACT_GROUP_STATIONARY | ACT_FLAG_ATTACKING)
_G.ACT_DONKEY_KONG_POUND_HIT = allocate_mario_action(ACT_GROUP_STATIONARY | ACT_FLAG_ATTACKING)
_G.ACT_DONKEY_KONG_BOUNCE = (ACT_GROUP_AIRBORNE | ACT_FLAG_MOVING | ACT_FLAG_AIR | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION)

---------------
-- DK Bounce --
---------------

--- SwagSkeleton95
--- Allows the player to bounce across enemies with well-timed A presses. Spawns coins when chained across multiple enemies. Credit to baconator2558 for the vast majority of this code.
--- action

local bounceSounds = {
	audio_sample_load("z_sfx_dk_bounce1.ogg"),
	audio_sample_load("z_sfx_dk_bounce2.ogg"),
	audio_sample_load("z_sfx_dk_bounce3.ogg")
}

local coinObj = nil

function act_dk_bounce(m)
	if (m.actionTimer == 0) then
		set_character_animation(m, CHAR_ANIM_FORWARD_SPINNING)
		set_anim_to_frame(m, 0)
		m.forwardVel = 0
		m.vel.x = 0
		m.vel.y = 80
		play_character_sound(m, CHAR_SOUND_YAHOO_WAHA_YIPPEE)
		m.vel.z = 0
		m.slideVelX = 0
		m.slideVelZ = 0
		m.faceAngle.y = m.intendedYaw
		if (m.actionArg >= 3) then
			coinObj = spawn_non_sync_object(id_bhvBlueCoinJumping, E_MODEL_SPARKLES, m.pos.x, m.pos.y, m.pos.z, nil)
		end
		audio_sample_play(bounceSounds[math.min(m.actionArg,3)], m.pos, 0.5)
		-- plays a random sound from a table ('bounceSounds') of 3 sound files.
		-- I didn't include them here because I ripped them straight from DKCR myself
		-- and I'm under the impression that this mod mainly uses self-made sound effects
        set_mario_particle_flags(m, PARTICLE_HORIZONTAL_STAR, 0)
	end

	if (m.actionTimer >= 1 and coinObj ~= nil) then
		coinObj.oPosX = m.pos.x
		coinObj.oPosY = m.pos.y
		coinObj.oPosZ = m.pos.z
		interact_coin(m, INTERACT_COIN, coinObj)
		coinObj = nil
	end

	if (m.actionTimer > 5 and m.marioObj.header.gfx.animInfo.animID == CHAR_ANIM_FORWARD_SPINNING) then
		set_character_animation(m, CHAR_ANIM_TRIPLE_JUMP)
		set_anim_to_frame(m, 21)
	end
	
	m.forwardVel = math.min(m.forwardVel, 95)

	update_air_without_turn(m)
	if (m.actionTimer > 20) then
		update_air_without_turn(m)
	end

	if (m.vel.y < 10) then
		update_air_without_turn(m)
		if (m.vel.y < -10) then
			update_air_without_turn(m)
			update_air_without_turn(m)
			update_air_without_turn(m)
			update_air_without_turn(m)
			update_air_without_turn(m)
		end
	end

	local stepResult = perform_air_step(m, AIR_STEP_CHECK_HANG | AIR_STEP_CHECK_LEDGE_GRAB)

	if (stepResult == AIR_STEP_LANDED) then
		set_character_animation(m, CHAR_ANIM_FORWARD_SPINNING)
		set_anim_to_frame(m, 0)
		return set_mario_action(m, ACT_DOUBLE_JUMP_LAND, 0)
	elseif (stepResult == AIR_STEP_GRABBED_LEDGE) then
		set_character_animation(m, CHAR_ANIM_IDLE_ON_LEDGE)
		return drop_and_set_mario_action(m, ACT_LEDGE_GRAB, 0)
	elseif (stepResult == AIR_STEP_GRABBED_CEILING) then
		return set_mario_action(m, ACT_START_HANGING, 0);
	end

	m.faceAngle.y = approach_s16_symmetric(m.faceAngle.y, m.intendedYaw, (abs_angle_diff(m.faceAngle.y, m.intendedYaw) / (25 * m.actionTimer + 1)) + 750)
	update_air_without_turn(m)
	m.actionTimer = m.actionTimer + 1
	if (check_kick_or_dive_in_air(m) ~= 0) then
		return 1
	end
	
    return 0
end

hook_mario_action(ACT_DONKEY_KONG_BOUNCE, act_dk_bounce, INT_HIT_FROM_ABOVE)

--- Roll

---@param m MarioState
local function act_donkey_kong_roll(m)
    if (not m) then return 0 end

    local isSliding = (mario_floor_is_slippery(m)) ~= 0
    if isSliding then
        if update_sliding(m, 4) ~= 0 or m.actionState == 0 then
            return set_mario_action(m, ACT_DECELERATING, 0)
        end
    end

    if mario_check_object_grab(m) ~= 0 then
        set_character_animation(m, CHAR_ANIM_FIRST_PUNCH)
        set_anim_to_frame(m, 2)
        return 1
    end

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        m.faceAngle.x = 0
        m.marioObj.header.gfx.angle.x = m.faceAngle.x
        local result = set_jumping_action(m, ACT_JUMP, 0)
        if not isSliding then
            m.forwardVel = m.forwardVel / 0.8 - 5 -- conserve all jump momentum minus 5
        end
        return result
    end

    local doSpinAnim = true
    m.actionTimer = m.actionTimer + 1
    
    set_character_animation(m, CHAR_ANIM_START_CROUCHING)
    if m.actionState == 0 then
        doSpinAnim = false
        local newForwardVel = m.forwardVel
        newForwardVel = DONKEY_KONG_ROLL_SPEED * (m.actionTimer / DONKEY_KONG_ROLL_STARTUP)
        if m.actionTimer >= DONKEY_KONG_ROLL_STARTUP then
            newForwardVel = DONKEY_KONG_ROLL_SPEED
            m.actionState = 1
        end
        mario_set_forward_vel(m, newForwardVel)
    elseif m.actionTimer >= DONKEY_KONG_ROLL_DECAY_TIME and not isSliding then
        -- slow down after a time
        local newForwardVel = m.forwardVel
        newForwardVel = newForwardVel * DONKEY_KONG_ROLL_DECAY_PERCENT
        mario_set_forward_vel(m, newForwardVel)
    end

    -- influence direction slightly
    m.marioObj.oMoveAngleYaw = m.faceAngle.y
    cur_obj_rotate_yaw_toward(m.intendedYaw, 0x100)
    m.faceAngle.y = m.marioObj.oMoveAngleYaw
    
    local result = perform_ground_step(m)
    if result == GROUND_STEP_LEFT_GROUND then
        if m.actionState == 0 then
            mario_set_forward_vel(m, DONKEY_KONG_ROLL_SPEED)
        end
        return set_mario_action(m, ACT_DONKEY_KONG_ROLL_AIR, 0)
    elseif result == GROUND_STEP_HIT_WALL then
        if (m.wall or gServerSettings.bouncyLevelBounds == BOUNCY_LEVEL_BOUNDS_OFF) then
            set_mario_particle_flags(m, PARTICLE_VERTICAL_STAR, 0);
            slide_bonk(m, ACT_GROUND_BONK, ACT_WALKING)
            return
        end
    end

    if doSpinAnim then
        local prevFaceAngleX = m.faceAngle.x
        m.faceAngle.x = m.faceAngle.x + 0x60 * m.forwardVel
        m.marioObj.header.gfx.angle.x = m.faceAngle.x
        m.marioObj.header.gfx.pos.y = m.marioObj.header.gfx.pos.y + 50
        if prevFaceAngleX <= 0 and m.faceAngle.x > 0 then
            play_sound(SOUND_ACTION_SPIN, m.marioObj.header.gfx.cameraToObject)
        end
    end

    -- end roll
    if m.actionTimer > DONKEY_KONG_ROLL_END then
        return set_mario_action(m, ACT_WALKING, 0)
    end

    return 0
end

hook_mario_action(ACT_DONKEY_KONG_ROLL, { every_frame = act_donkey_kong_roll }, INT_FAST_ATTACK_OR_SHELL)

---@param m MarioState
local function act_donkey_kong_roll_air(m)
    if (not m) then return 0 end

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        m.terrainSoundAddend = 0
        m.faceAngle.x = 0
        m.marioObj.header.gfx.angle.x = m.faceAngle.x
        local result = set_mario_action(m, ACT_JUMP, 0)
        m.forwardVel = m.forwardVel / 0.8 - 5 -- conserve all jump momentum minus 5
        return result
    end

    m.actionTimer = m.actionTimer + 1

    -- influence direction slightly
    m.marioObj.oMoveAngleYaw = m.faceAngle.y
    cur_obj_rotate_yaw_toward(m.intendedYaw, 0x100)
    m.faceAngle.y = m.marioObj.oMoveAngleYaw
    mario_set_forward_vel(m, m.forwardVel)

    local result = perform_air_step(m, AIR_STEP_CHECK_LEDGE_GRAB)
    if result == AIR_STEP_LANDED then
        if (check_fall_damage_or_get_stuck(m, ACT_HARD_BACKWARD_GROUND_KB) == 0) then
            set_mario_action(m, ACT_DONKEY_KONG_ROLL, 0)
            m.actionState = 1
            return 1
        end
    elseif result == AIR_STEP_HIT_WALL then
        if (m.wall or gServerSettings.bouncyLevelBounds == BOUNCY_LEVEL_BOUNDS_OFF) then
            mario_bonk_reflection(m, 1);
            if (m.vel.y > 0) then m.vel.y = 0 end

            set_mario_particle_flags(m, PARTICLE_VERTICAL_STAR, 0);
            drop_and_set_mario_action(m, ACT_BACKWARD_AIR_KB, 0);
            return 1
        end
    elseif result == AIR_STEP_HIT_LAVA_WALL then
        lava_boost_on_wall(m)
        return 1
    end

    local prevFaceAngleX = m.faceAngle.x
    m.faceAngle.x = m.faceAngle.x + 0x60 * m.forwardVel
    m.marioObj.header.gfx.angle.x = m.faceAngle.x
    m.marioObj.header.gfx.pos.y = m.marioObj.header.gfx.pos.y + 50
    if prevFaceAngleX <= 0 and m.faceAngle.x > 0 then
        play_sound(SOUND_ACTION_SPIN, m.marioObj.header.gfx.cameraToObject)
    end

    if m.actionTimer > DONKEY_KONG_ROLL_END then
        return set_mario_action(m, ACT_FREEFALL, 0)
    end

    return 0
end

hook_mario_action(ACT_DONKEY_KONG_ROLL_AIR, { every_frame = act_donkey_kong_roll_air }, INT_FAST_ATTACK_OR_SHELL)

local function act_donkey_kong_pound(m)
    if (not m) then return 0 end

    mario_set_forward_vel(m, 0)
    if (mario_floor_is_slippery(m)) ~= 0 then
        return set_mario_action(m, ACT_BEGIN_SLIDING, 0)
    end

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        local result = set_jumping_action(m, ACT_JUMP, 0)
        return result
    elseif (m.input & INPUT_B_PRESSED) ~= 0 and m.actionTimer ~= 0 then
        m.actionState = 1
    end

    m.actionTimer = m.actionTimer + 1
    if m.actionTimer == 1 then
        play_mario_heavy_landing_sound(m, SOUND_ACTION_TERRAIN_HEAVY_LANDING)
        set_mario_particle_flags(m, (PARTICLE_MIST_CIRCLE | PARTICLE_HORIZONTAL_STAR), 0)
        m.action = ACT_DONKEY_KONG_POUND_HIT
    elseif m.action == ACT_DONKEY_KONG_POUND_HIT then
        m.action = ACT_DONKEY_KONG_POUND
    elseif m.actionTimer >= 8 then
        if m.actionState ~= 0 then
            -- pound again
            m.actionTimer = 0
            m.actionState = 0
        elseif m.input & INPUT_Z_DOWN ~= 0 then
            set_mario_action(m, ACT_START_CROUCHING, 0)
        else
            set_mario_action(m, ACT_IDLE, 0)
        end
    end

    --set_character_anim_with_accel(m, CHAR_ANIM_PLACE_LIGHT_OBJ, 0x20000)
    -- 28 anim frames in 16 frames
    if m.marioObj.header.gfx.animInfo.animFrame > 15 and m.actionTimer == 0 then
        --djui_chat_message_create(tostring(m.marioObj.header.gfx.animInfo.animFrame))
        set_anim_to_frame(m, 0)
    end
    play_custom_anim(m, "donkey_ground_slap", 0x10000 * 28 // 16)
    --[[set_anim_to_frame(m, m.marioObj.header.gfx.animInfo.animFrame)
    if m.controller.buttonPressed & L_TRIG ~= 0 then
        set_anim_to_frame(m, m.marioObj.header.gfx.animInfo.animFrame + 1)
    end]]
    local result = perform_ground_step(m)
    if result == GROUND_STEP_LEFT_GROUND then
        return set_mario_action(m, ACT_FREEFALL, 0)
    end
end
hook_mario_action(ACT_DONKEY_KONG_POUND, { every_frame = act_donkey_kong_pound })

hook_mario_action(ACT_DONKEY_KONG_POUND_HIT, { every_frame = act_donkey_kong_pound }, INT_GROUND_POUND) -- same action but with ground pound interaction