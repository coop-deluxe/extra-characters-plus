----------------------
-- Rosalina Moveset --
----------------------

if not charSelect then return end

require "anims/rosalina"

_G.ACT_ROSA_JUMP_TWIRL = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ATTACKING)
local E_MODEL_TWIRL_EFFECT = smlua_model_util_get_id("spin_attack_geo")

local METER_STATE_IDLE  = 0
local METER_STATE_HIT   = 1
local METER_STATE_BREAK = 2

---@param o Object
function bhv_spin_attack_init(o)
    o.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE -- Allows you to change the position and angle
end

---@param o Object
function bhv_spin_attack_loop(o)
    -- Retrieves the Mario state corresponding to the object
    local m = gMarioStates[o.oBehParams]
    local e = gCharacterStates[m.playerIndex].rosalina
    if not m or not m.marioObj then
        obj_mark_for_deletion(o)
        e.spinObj = nil
        return
    end

    cur_obj_set_pos_relative_to_parent(0, 20, 0) -- Makes it move to its parent's position

    o.oFaceAngleYaw = o.oFaceAngleYaw + 0x2000   -- Rotates it

    if m.action ~= ACT_ROSA_JUMP_TWIRL or o.oTimer > 15 then -- Deletes itself once the action changes
        obj_mark_for_deletion(o)
        e.spinObj = nil
    end
end

local id_bhvTwirlEffect = hook_behavior(nil, OBJ_LIST_GENACTOR, true, bhv_spin_attack_init, bhv_spin_attack_loop,
    "bhvRosalinaTwirlEffect")

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

local ROSALINA_SOUND_SPIN = audio_sample_load("z_sfx_rosalina_spinattack.ogg") -- Load audio sample

---@param m MarioState
function act_jump_twirl(m)
    local e = gCharacterStates[m.playerIndex].rosalina

    if m.actionTimer >= 15 then
        return set_mario_action(m, ACT_FREEFALL, 0) -- End the action
    end

    if m.actionTimer == 0 then
        m.marioObj.header.gfx.animInfo.animID = -1
        play_character_sound(m, CHAR_SOUND_HELLO)                    -- Plays the character sound
        audio_sample_play(ROSALINA_SOUND_SPIN, m.pos, 1)             -- Plays the spin sound sample
        m.particleFlags = m.particleFlags | ACTIVE_PARTICLE_SPARKLES -- Spawns sparkle particles

        if e.canSpin then
            m.vel.y = 30 -- Initial upward velocity
            e.canSpin = false
        else
            m.vel.y = math.max(m.vel.y, 0)
        end
        m.marioObj.hitboxRadius = 100 -- Damage hitbox
    else
        m.marioObj.hitboxRadius = 37 -- Reset the hitbox after initial hit
    end

    -- Spawn the spin effect
    if not e.spinObj or obj_has_behavior_id(e.spinObj, id_bhvTwirlEffect) == 0 then
        e.spinObj = spawn_non_sync_object(id_bhvTwirlEffect, E_MODEL_TWIRL_EFFECT, m.pos.x, m.pos.y, m.pos.z, function(o)
            o.parentObj = m.marioObj
            o.oBehParams = m.playerIndex
        end)
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
    local e = gCharacterStates[m.playerIndex].rosalina

    if m.action == ACT_ROSA_JUMP_TWIRL and intType == INTERACT_GRABBABLE and o.oInteractionSubtype & INT_SUBTYPE_NOT_GRABBABLE == 0 then
        local angleTo = mario_obj_angle_to_object(m, o)
        if (o.oInteractionSubtype & INT_SUBTYPE_GRABS_MARIO ~= 0 or obj_has_behavior_id(o, id_bhvBowser) ~= 0) then -- heavy grab objects
            if m.pos.y - m.floorHeight < 100 and abs_angle_diff(m.faceAngle.y, angleTo) < 0x4000 then
                m.action = ACT_MOVE_PUNCHING
                m.actionArg = 1
            end
        elseif not e.orbitObjActive then -- light grab objects
            m.usedObj = o
            e.orbitObjActive = true
            e.orbitObjDist = 160 - m.actionTimer * 2
            e.orbitObjAngle = angleTo

            return false
        end
    end
end

---@param m MarioState
function rosalina_update(m)
    local e = gCharacterStates[m.playerIndex].rosalina

    if m.controller.buttonPressed & B_BUTTON ~= 0 and extraSpinActs[m.action] then
        return set_mario_action(m, ACT_ROSA_JUMP_TWIRL, 0)
    end

    --if m.action & ACT_FLAG_AIR == 0 and m.playerIndex == 0 then
    --    e.canSpin = true
    --end

    if m.action ~= ACT_ROSA_JUMP_TWIRL and m.marioObj.hitboxRadius ~= 37 then
        m.marioObj.hitboxRadius = 37
    end

    if e.orbitObjActive then
        local o = m.usedObj

        if not o or o.activeFlags == ACTIVE_FLAG_DEACTIVATED then
            e.orbitObjActive = false
            o.oIntangibleTimer = 0

            if m.playerIndex == 0 then m.usedObj = nil end
            return
        end

        e.orbitObjDist = e.orbitObjDist - 6
        if e.orbitObjDist >= 90 then
            e.orbitObjAngle = e.orbitObjAngle + 0x1800
        else
            e.orbitObjAngle = approach_s16_asymptotic(e.orbitObjAngle, m.faceAngle.y, 4)
        end

        o.oPosX = m.pos.x + sins(e.orbitObjAngle) * e.orbitObjDist
        o.oPosZ = m.pos.z + coss(e.orbitObjAngle) * e.orbitObjDist
        o.oPosY = approach_f32_asymptotic(o.oPosY, m.pos.y + 50, 0.25)

        obj_set_vel(o, 0, 0, 0)
        o.oForwardVel = 0
        o.oIntangibleTimer = -1

        if m.playerIndex == 0 and e.orbitObjDist <= 80 then
            e.orbitObjActive = false
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

    if m.hurtCounter > e.lastHurtCounter then
        m.hurtCounter = e.hp > 2 and 10 or 15
        e.meterState = METER_STATE_HIT
        e.meterTimer = 0
        e.hp = math.max(0, e.hp - 1)
    end
    e.lastHurtCounter = m.hurtCounter

    if m.healCounter > e.lastHealCounter then
        if m.healCounter < 15 then
            m.healCounter = e.hp > 2 and 10 or 15
        end
        e.hp = math.min(e.hp + m.healCounter // 10, 3)
    end
    e.lastHealCounter = m.healCounter
end

local meter = {
    label = {
        left  = get_texture_info("char-select-ec-rosalina-meter-left"),
        right = get_texture_info("char-select-ec-rosalina-meter-right"),
    },
    pie = {
        get_texture_info("char_select_custom_meter_pie1"),
        get_texture_info("char_select_custom_meter_pie2"),
        get_texture_info("char_select_custom_meter_pie3"),
        get_texture_info("char_select_custom_meter_pie4"),
        get_texture_info("char_select_custom_meter_pie5"),
        get_texture_info("char_select_custom_meter_pie6"),
        get_texture_info("char_select_custom_meter_pie7"),
        get_texture_info("char_select_custom_meter_pie8"),
    }
}

local TEX_LIFE_LABEL = get_texture_info("char-select-ec-rosa-meter-life")
local specialMeter = {}
local specialMeterNum = {}
for i = 0, 6 do
    specialMeter[i] = get_texture_info("char-select-ec-rosa-meter-"..i)
    specialMeterNum[i] = get_texture_info("char-select-ec-rosa-meter-num-"..i)
end

local function render_rect(prevX, prevY, prevSize, x, y, size)
    djui_hud_render_rect_interpolated(prevX-prevSize/2,prevY-prevSize/2,prevSize,prevSize, x-size/2,y-size/2,size,size)
end
local function render_text_centered_interpolated(t, px, py, pz, x, y, z)
    djui_hud_print_text_interpolated(t, px - djui_hud_measure_text(t) * pz/2, py - 32*pz, pz,
                                         x - djui_hud_measure_text(t) *  z/2,  y - 32* z,  z)
end

function rosalina_health_meter(localIndex, health, prevX, prevY, prevW, prevH, x, y, w, h)
    local m = gMarioStates[localIndex]
    local e = gCharacterStates[m.playerIndex].rosalina

    if gCSPlayers[m.playerIndex].movesetToggle then
        local djuiColor = djui_hud_get_color()

        local timer = e.meterTimer
        w, prevW = w/64, prevW/64
        h, prevH = h/64, prevH/64
        local x2, prevX2, y2, prevY2
            = x , prevX , y , prevY
        if e.meterState == METER_STATE_IDLE then
            local fac = math.pi*((3-e.hp)/6)
            local pulse = 1 + (math.sin(timer*fac))*.1
            local pulsePrev = 1 + (math.sin((timer-1)*fac))*.1
            w, prevW = w * pulse, prevW * pulsePrev
            h, prevH = h * pulse, prevH * pulsePrev

        elseif e.meterState == METER_STATE_HIT then
            local fac = math.pi/12
            local mag = math.sin(fac*math.min(12, timer))*3
            local magPrev = math.sin(fac*math.min(12, timer-1))*3
            local magPrev2 = math.sin(fac*math.min(12, timer-2))*3
            x, prevX = x + sins(timer*0x4000) * mag, prevX + sins((timer-1)*0x4000) * magPrev
            y, prevY = y + coss(timer*0x4000) * mag, prevY + coss((timer-1)*0x4000) * magPrev
            x2, prevX2 = prevX, prevX + sins((timer-2)*0x4000) * magPrev2
            y2, prevY2 = prevY, prevY + coss((timer-2)*0x4000) * magPrev2

            if timer > 13 then
                e.meterState = e.hp > 0 and METER_STATE_IDLE or METER_STATE_BREAK
                e.meterTimer = -1
            end
        end

        e.meterTimer = timer + 1

        djui_hud_set_color(255, 255, 255, 255)

        local meter = specialMeter[math.min(e.hp, 3)]
        local extraMeter = specialMeter[e.hp]
        local num = specialMeterNum[e.hp]

        local xOffset, xOffsetP = 32 * (1-w), 32 * (1-prevW)
        local yOffset, yOffsetP = 32 * (1-h), 32 * (1-prevH)
        djui_hud_render_texture_interpolated(meter, prevX + xOffsetP, prevY + yOffsetP, prevW, prevH, x + xOffset, y + yOffset, w, h)
        djui_hud_render_texture_interpolated(TEX_LIFE_LABEL, prevX2 + xOffsetP, prevY2 + yOffsetP, prevW, prevH, x2 + xOffset, y2 + yOffset, w, h)
        xOffset, xOffsetP = xOffset + w*19, xOffsetP + prevW*19
        yOffset, yOffsetP = yOffset + h*22, yOffsetP + prevH*22
        djui_hud_render_texture_interpolated(num, prevX2 + xOffsetP, prevY2 + yOffsetP, prevW, prevH, x2 + xOffset, y2 + yOffset, w, h)

        -- Clean up after we're done
        djui_hud_set_color(djuiColor.r, djuiColor.g, djuiColor.b, djuiColor.a)

    else
        djui_hud_render_texture_interpolated(meter.label.left, prevX, prevY, prevW, prevH, x, y, w, h)
        djui_hud_render_texture_interpolated(meter.label.right, prevX + 31*prevW, prevY, prevW, prevH, x + 31*w, y, w, h)
        if health > 0 then
            djui_hud_render_texture_interpolated(meter.pie[health >> 8], prevX + 15*prevW, prevY + 16*h, prevW, prevH, x + 15*w, y + 16*h, w, h)
        end
    end
end

---@param m MarioState
function rosalina_before_action(m, action)
    if not action then return end

    local e = gCharacterStates[m.playerIndex].rosalina

    if spinOverrides[action] and m.controller.buttonDown & (Z_TRIG | A_BUTTON) == 0 and m.action ~= ACT_STEEP_JUMP then
        return ACT_ROSA_JUMP_TWIRL
    end

    if action & ACT_FLAG_AIR == 0 and not e.canSpin then
        play_sound_with_freq_scale(SOUND_GENERAL_COIN_SPURT_EU, m.marioObj.header.gfx.cameraToObject, 1.6)
        spawn_non_sync_object(id_bhvSparkle, E_MODEL_SPARKLES_ANIMATION, m.pos.x, m.pos.y + 200, m.pos.z,
            function(o) obj_scale(o, 0.75) end)
        e.canSpin = true
    end
end

hook_mario_action(ACT_ROSA_JUMP_TWIRL, act_jump_twirl, INT_KICK)

return {
    { HOOK_MARIO_UPDATE, rosalina_update },
 -- { HOOK_ON_PVP_ATTACK, rosalina_on_pvp_attack },
    { HOOK_ALLOW_INTERACT, rosalina_allow_interact },
    { HOOK_BEFORE_SET_MARIO_ACTION, rosalina_before_action },
    meter = rosalina_health_meter
}