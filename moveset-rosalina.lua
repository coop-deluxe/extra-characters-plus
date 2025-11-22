----------------------
-- Rosalina Moveset --
----------------------

if not charSelect then return end

_G.ACT_JUMP_TWIRL = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ATTACKING)
E_MODEL_TWIRL_EFFECT = smlua_model_util_get_id("spin_attack_geo")

---@param o Object
local function bhv_spin_attack_init(o)
    o.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE -- Allows you to change the position and angle
end

---@param o Object
local function bhv_spin_attack_loop(o)
    cur_obj_set_pos_relative_to_parent(0, 20, 0) -- Makes it move to its parent's position

    o.oFaceAngleYaw = o.oFaceAngleYaw + 0x2000   -- Rotates it
    local m = get_mario_state_from_object(o.parentObj)

    if m.action ~= ACT_JUMP_TWIRL then -- Deletes itself once the action changes
        obj_mark_for_deletion(o)
    end
end

local id_bhvTwirlEffect = hook_behavior(nil, OBJ_LIST_GENACTOR, true, bhv_spin_attack_init, bhv_spin_attack_loop,
    "bhvTwirlEffect")

-- Spinable actions, these are actions you can spin out of that don't normally allow a kick/dive
local extraSpinActs = {
    [ACT_LONG_JUMP] = true,
    [ACT_BACKFLIP]  = true,
}

-- Spin overridable actions, these are overriden instantly
local spinOverrides = {
    [ACT_PUNCHING]      = true,
    [ACT_MOVE_PUNCHING] = true,
    [ACT_JUMP_KICK]     = true,
    [ACT_DIVE]          = true
}

local ROSALINA_SOUND_SPIN = audio_sample_load("spin_attack.ogg") -- Load audio sample

---@param m MarioState
function act_jump_twirl(m)
    local e = gCharacterStates[m.playerIndex]

    if m.actionTimer >= 15 then
        return set_mario_action(m, ACT_FREEFALL, 0) -- End the action
    end

    if m.actionTimer == 0 then
        m.marioObj.header.gfx.animInfo.animID = -1
        play_character_sound(m, CHAR_SOUND_HELLO)                    -- Plays the character sound
        audio_sample_play(ROSALINA_SOUND_SPIN, m.pos, 1)             -- Plays the spin sound sample
        m.particleFlags = m.particleFlags | ACTIVE_PARTICLE_SPARKLES -- Spawns sparkle particles

        if e.rosalina.canSpin then
            m.vel.y = 30 -- Initial upward velocity
            e.rosalina.canSpin = false
        else
            m.vel.y = max(m.vel.y, 0)
        end
        m.marioObj.hitboxRadius = 100 -- Damage hitbox

        -- Spawn the spin effect
        spawn_sync_object(id_bhvTwirlEffect, E_MODEL_TWIRL_EFFECT, m.pos.x, m.pos.y, m.pos.z, function(o)
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
function rosalina_allow_interact(m, o, intType)
    local e = gCharacterStates[m.playerIndex]
    if m.action == ACT_JUMP_TWIRL and intType == INTERACT_GRABBABLE and o.oInteractionSubtype & INT_SUBTYPE_NOT_GRABBABLE == 0 then
        local angleTo = mario_obj_angle_to_object(m, o)
        if o.oInteractionSubtype & INT_SUBTYPE_GRABS_MARIO ~= 0 and m.pos.y - m.floorHeight < 100
            and abs_angle_diff(m.faceAngle.y, angleTo) < 0x4000 then -- heavy grab objects
            m.action = ACT_MOVE_PUNCHING
            m.actionArg = 1
        elseif not e.rosalina.orbitObjActive then -- light grab objects
            m.usedObj = o
            e.rosalina.orbitObjActive = true
            e.rosalina.orbitObjDist = 160 - m.actionTimer * 2
            e.rosalina.orbitObjAngle = angleTo

            return false
        end
    end
end

---@param m MarioState
function rosalina_update(m)
    local e = gCharacterStates[m.playerIndex]

    if m.controller.buttonPressed & B_BUTTON ~= 0 and extraSpinActs[m.action] then
        return set_mario_action(m, ACT_JUMP_TWIRL, 0)
    end

    --if m.action & ACT_FLAG_AIR == 0 and m.playerIndex == 0 then
    --    e.rosalina.canSpin = true
    --end

    if m.action ~= ACT_JUMP_TWIRL and m.marioObj.hitboxRadius ~= 37 then
        m.marioObj.hitboxRadius = 37
    end

    if e.rosalina.orbitObjActive then
        local o = m.usedObj

        if not o or o.activeFlags == ACTIVE_FLAG_DEACTIVATED then
            e.rosalina.orbitObjActive = false
            o.oIntangibleTimer = 0

            if m.playerIndex == 0 then m.usedObj = nil end
            return
        end

        e.rosalina.orbitObjDist = e.rosalina.orbitObjDist - 6
        if e.rosalina.orbitObjDist >= 90 then
            e.rosalina.orbitObjAngle = e.rosalina.orbitObjAngle + 0x1800
        else
            e.rosalina.orbitObjAngle = approach_s16_asymptotic(e.rosalina.orbitObjAngle, m.faceAngle.y, 4)
        end

        o.oPosX = m.pos.x + sins(e.rosalina.orbitObjAngle) * e.rosalina.orbitObjDist
        o.oPosZ = m.pos.z + coss(e.rosalina.orbitObjAngle) * e.rosalina.orbitObjDist
        o.oPosY = approach_f32_asymptotic(o.oPosY, m.pos.y + 50, 0.25)

        obj_set_vel(o, 0, 0, 0)
        o.oForwardVel = 0
        o.oIntangibleTimer = -1

        if m.playerIndex == 0 and e.rosalina.orbitObjDist <= 80 then
            e.rosalina.orbitObjActive = false
            o.oIntangibleTimer = 0

            if m.action & (ACT_FLAG_INVULNERABLE | ACT_FLAG_INTANGIBLE) ~= 0 or m.action & ACT_GROUP_MASK >= ACT_GROUP_SUBMERGED then
                m.usedObj = nil
            else
                o.oIntangibleTimer = 0
                m.interactObj = o
                m.usedObj = o
                if o.oSyncID ~= 0 then network_send_object(o, true) end

                if m.action & ACT_FLAG_AIR == 0 then
                    set_mario_action(m, ACT_HOLD_IDLE, 0)
                    mario_grab_used_object(m)
                else
                    set_mario_action(m, ACT_HOLD_FREEFALL, 0)
                    mario_grab_used_object(m)
                end
            end
        end
    end
end

---@param m MarioState
function rosalina_before_action(m, action)
    if not action then return end

    local e = gCharacterStates[m.playerIndex]

    if spinOverrides[action] and m.controller.buttonDown & (Z_TRIG | A_BUTTON) == 0 and m.action ~= ACT_STEEP_JUMP then
        return ACT_JUMP_TWIRL
    end

    if action & ACT_FLAG_AIR == 0 and not e.rosalina.canSpin then
        play_sound_with_freq_scale(SOUND_GENERAL_COIN_SPURT_EU, m.marioObj.header.gfx.cameraToObject, 1.6)
        if m.playerIndex == 0 then
            spawn_sync_object(id_bhvSparkle, E_MODEL_SPARKLES_ANIMATION, m.pos.x, m.pos.y + 200, m.pos.z,
                function(o) obj_scale(o, 0.75) end)
        end
        e.rosalina.canSpin = true
    end
end

hook_mario_action(ACT_JUMP_TWIRL, act_jump_twirl, INT_KICK)
