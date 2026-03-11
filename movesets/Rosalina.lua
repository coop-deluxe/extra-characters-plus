require "anims/rosalina"

-- misc locals
local asin, pi, tau, max = math.asin, math.pi, 2*math.pi, math.max
local IN_SINE, OUT_SINE, INV_OUT_SINE = IN_SINE, OUT_SINE, function (x) return 2 * asin(x) / pi end
local djui_hud_set_color, djui_hud_render_texture_interpolated = djui_hud_set_color, djui_hud_render_texture_interpolated
local sins, coss = sins, coss

_G.ACT_ROSA_JUMP_TWIRL = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ATTACKING)
local E_MODEL_TWIRL_EFFECT = smlua_model_util_get_id("spin_attack_geo")

local METER_STATE_IDLE  = 0
local METER_STATE_HIT   = 1
local METER_STATE_JOIN  = 2
local METER_STATE_BREAK = 3

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
local extraSpinActs = T{
    ACT_LONG_JUMP,
    ACT_BACKFLIP,
}

-- Spin overridable actions, these are overriden instantly
local spinOverrides = T{
    ACT_PUNCHING,
    ACT_MOVE_PUNCHING,
    ACT_JUMP_KICK,
    ACT_DIVE
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
hook_mario_action(ACT_ROSA_JUMP_TWIRL, act_jump_twirl, INT_KICK)

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

    -- if m.playerIndex == 0 then
    --     djui_chat_message_create(("%i, %X (%i)"):format(m.health >> 8, m.health, m.healCounter - m.hurtCounter))
    -- end
    if m.hurtCounter > 0 then
        m.hurtCounter = 0
        e.meterState = METER_STATE_HIT
        e.meterTimer = 1
        e.hp = math.max(e.hp - (m.squishTimer > 0 and 3 or 1), 0)
    end

    if m.healCounter > 0 then
        local prevHP = e.hp
        e.hp = math.min(e.hp + (m.healCounter + 1) // 4, e.hp > 3 and 6 or 3)
        m.healCounter = 0
        if e.hp == 3 and e.hp > prevHP and e.meterState == METER_STATE_IDLE then
            e.meterTimer = 1
        end
    end
    if e.meterState == METER_STATE_BREAK and e.hp > 0 then
        e.meterState = METER_STATE_IDLE
        e.meterTimer = 1
    end

    if m.playerIndex == 0 then
        m.health = (e.hp == 3 and e.meterTimer > 60) and 0x880 or 0x7FF * OUT_SINE(e.hp / 6)
    else
        e.hp = m.health == 0x880 and 3 or INV_OUT_SINE(m.health / 0x7FF) * 6
    end
    m.peakHeight = m.pos.y
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

-- HUD stuff
---@class Particle
---@field x number
---@field y number
---@field z number
---@field vx number
---@field vy number
---@field vz number
---@field t integer
---@field tex TextureInfo
---@field update function

---@return Particle
local Particle = function ()
    return {
        x  = 0, y  = 0, z  = 1,
        vx = 0, vy = 0, vz = 0,
        t = 0
    }
end

local particles = {}
local function create_particle(type, x, y, scale)
    particles[#particles+1] = type(x, y, scale)
end

-- Glass particles
local glassTex = load_textures("char-select-ec-rosa-meter-glass-", 1, 2)
function glass_update(p)
    djui_hud_set_rotation(p.r, 0.5, 0.5)
    if p.z < 0 then p.dead = 1 end
end
local PARTICLE_GLASS = function (x, y, s)
    local p = Particle()
    p.x, p.y = x, y
    p.z = (0.8 + math.random() * 0.4) * s
    p.r = math.random(65536)

    local angle = math.random() * tau
    local force = (1 + 2*math.random()) * s
    p.vx, p.vy = math.sin(angle) * force, math.cos(angle) * force
    p.vz = -s / 10

    p.tex = glassTex[math.random(#glassTex)]
    p.update = glass_update
    return p
end
local emit_shatter = function (x, y, s)
    for i = 1, 18 do
        create_particle(PARTICLE_GLASS, x, y, s)
    end
end
local emit_shatter_extra = function (x, y, s)
    for i = 1, 46 do
        local xO, yO = (8 - 16*math.random())*s, (8 - 16*math.random())*s
        create_particle(PARTICLE_GLASS, x + xO, y + yO, s)
    end
end

function rosalina_health_meter_particles()
    djui_hud_set_resolution(RESOLUTION_N64)
    local i = 1
    while particles[i] do
        local p = particles[i]
        if p.dead then
            particles[i] = particles[#particles]
            particles[#particles] = nil
        else
            p:update()

            local t = p.tex
            local nx, ny, nz = p.x + p.vx, p.y + p.vy, p.z + p.vz
            djui_hud_render_texture_interpolated(t,
                p.x - t.width * p.z/2, p.y - t.height * p.z/2, p.z, p.z,
                 nx - t.width *  nz/2,  ny - t.height *  nz/2,  nz,  nz
            )
            p.x, p.y, p.z = nx, ny, nz
            i = i + 1
        end
    end
end

local vanillaMeter = load_meter("rosalina")
vanillaMeter.pie = load_textures("char_select_custom_meter_pie", 1, 8)

local function render_texture_shadow_interp(tex, xP, yP, wP, hP, x, y, w, h, xSP, ySP, xS, yS)
    local c = djui_hud_get_color()
    djui_hud_set_color(0, 0, 0, c.a // 2)
    djui_hud_render_texture_interpolated(tex,
        xP + xSP, yP + ySP, wP, hP,
        x  + xS,  y  + yS,  w,  h)
    djui_hud_set_color(c.r, c.g, c.b, c.a)
    djui_hud_render_texture_interpolated(tex, xP, yP, wP, hP, x, y, w, h)
end

local TEX_METER = load_textures("char-select-ec-rosa-meter-", 0, 6)
local TEX_METER_NUM = load_textures("char-select-ec-rosa-meter-num-", 0, 6)
local TEX_METER_CRACK = get_texture_info("char-select-ec-rosa-meter-crack")
local TEX_LIFE_LABEL = get_texture_info("char-select-ec-rosa-meter-life")

function rosalina_health_meter(localIndex, health, xP, yP, wP, hP, x, y, w, h)
    local m = gMarioStates[localIndex]
    local e = gCharacterStates[m.playerIndex].rosalina
    w, wP = w/64, wP/64
    h, hP = h/64, hP/64

    if gCSPlayers[m.playerIndex].movesetToggle then
        local timer = e.meterTimer
        local state = e.meterState
        local crack
        local s, sP = 1, 1
        local x2, x2P, y2, y2P
            = x , xP , y , yP

        local extraOffset = 16 * w
        local x3, x3P, y3, y3P

        if state == METER_STATE_IDLE then
            if e.hp < 3 then
                local fac = 0x8000*((3-e.hp)/6)
                s, sP = 1.05 - .05*coss(timer*fac), 1.05 - .05*coss((timer-1)*fac)
                x, xP = x + 32 * w * (1-s), xP + 32 * wP * (1-sP)
                y, yP = y + 32 * h * (1-s), yP + 32 * hP * (1-sP)
                x2, x2P, y2, y2P = x, xP, y, yP
            elseif e.hp > 3 then
                x3, x3P = x - extraOffset, xP - extraOffset
                y3, y3P = y, yP
                x2, x2P, y2, y2P = x3, x3P, y3, y3P
            end

        elseif state == METER_STATE_HIT then
            local extra = e.hp > 2
            local fac = 0x8000/12
            local mag = sins(fac*math.min(12, timer))*3
            local magP = sins(fac*math.min(12, timer-1))*3
            local magPrev2 = sins(fac*math.min(12, timer-2))*3

            if extra then x3, x3P, y3, y3P = x, xP, y, yP end
            x, xP = x + sins(timer*0x4000) * mag, xP + sins((timer-1)*0x4000) * magP
            y, yP = y + coss(timer*0x4000) * mag, yP + coss((timer-1)*0x4000) * magP
            if extra then x, xP = x - extraOffset, xP - extraOffset end
            x2, x2P = xP, xP + sins((timer-2)*0x4000) * magPrev2
            y2, y2P = yP, yP + coss((timer-2)*0x4000) * magPrev2
            if extra then
                x, xP, x3, x3P = x3, x3P, x, xP
                y, yP, y3, y3P = y3, y3P, y, yP
            end

            if timer > 13 then
                if extra and e.hp == 3 then
                    emit_shatter_extra(x3+32*w, y3+32*h, w*1.2)
                end
                e.meterState = e.hp > 0 and METER_STATE_IDLE or METER_STATE_BREAK
            end

        elseif state == METER_STATE_JOIN then
            -- (60hz)
            -- empty meter appears (0)
            x3, x3P = x - extraOffset, xP - extraOffset
            y3, y3P = y, yP

            -- increment life every 5 frames
            if timer % 2 == 1 then
                e.hp = math.min(e.hp + 1, 6)
            end

            -- begin moving (57) (29/30 to 35)
            if timer < 35 then
                local pos = gVec3fZero()
                vec3f_copy(pos, m.pos)
                pos.y = pos.y + 200

                if djui_hud_world_pos_to_screen_pos(pos, pos) ~= 0 then
                    pos.y = pos.y - 64*h
                    local t = IN_SINE((math.max(23, timer) - 23)/12)
                    local tP = IN_SINE((math.max(23, timer-1) - 23)/12)
                    x3, x3P = math.lerp(pos.x, x3, t), math.lerp(pos.x, x3P, tP)
                    y3, y3P = math.lerp(pos.y, y3, t), math.lerp(pos.y, y3P, tP)
                end
            end

            -- 25 frames to reach meter (69)
            if timer == 35 then
                disable_time_stop_including_mario()
            end
            -- 12 frames to settle      (81)
            if timer > 40 then e.meterState = METER_STATE_IDLE end

        elseif state == METER_STATE_BREAK then
            if timer == 10 then
                emit_shatter(x+22*w, y+28*h, w*1.2)
            end
            if timer > 10 then
                crack = 1
            end
        end

        e.meterTimer = e.meterState == state and (timer + 1) or 1
        djui_chat_message_create(e.meterState..", "..e.meterTimer)
        local meter = TEX_METER[math.min(e.hp, 3)]
        local extraMeter = e.hp > 3 and TEX_METER[e.hp] or TEX_METER[0]
        local num = TEX_METER_NUM[e.hp]

        local ws,  wsP,   hs,  hsP
            = w*s, wP*sP, h*s, hP*sP

        djui_hud_set_color(255, 255, 255, 255)

        -- Main Meter
        render_texture_shadow_interp(meter,
            xP, yP, wsP, hsP,
            x,  y,  ws,  hs,
            3*wsP, 2*hsP, 3*ws, 2*hs)

        -- Extra Meter
        if x3 then
            render_texture_shadow_interp(extraMeter,
                x3P, y3P, wsP, hsP,
                x3,  y3,  ws,  hs,
                3*wsP, 2*hsP, 3*ws, 2*hs)
        end

        if crack == 1 then
            djui_hud_render_texture_interpolated(TEX_METER_CRACK,
                xP + 12*wsP, yP + 17*hsP, wsP, hsP,
                x  + 12*ws,  y  + 17*hs,  ws,  hs)
        end

        -- LIFE Label
        djui_hud_render_texture_interpolated(TEX_LIFE_LABEL,
            x2P, y2P, wsP, hsP,
            x2,  y2,  ws,  hs)

        -- Number
        if crack ~= 1 then
            render_texture_shadow_interp(num,
                x2P + 19*wsP, y2P + 22*hsP, wsP, hsP,
                x2  + 19*ws,  y2  + 22*hs,  ws,  hs,
                2*wsP, 2*hsP, 2*ws, 2*hs)
        end

    else
        djui_hud_render_texture_interpolated(vanillaMeter.label.left, xP, yP, wP, hP, x, y, w, h)
        djui_hud_render_texture_interpolated(vanillaMeter.label.right, xP + 31*wP, yP, wP, hP, x + 31*w, y, w, h)
        if health > 0 then
            djui_hud_render_texture_interpolated(vanillaMeter.pie[health >> 8], xP + 15*wP, yP + 16*h, wP, hP, x + 15*w, y + 16*h, w, h)
        end
    end
end

-- Life Mushroom
local mushroomBhvs = {
    id_bhv1Up,
    id_bhv1upJumpOnApproach,
    id_bhv1upRunningAway,
    id_bhv1upSliding,
    id_bhv1upWalking,
    id_bhvHidden1up,
    id_bhvHidden1upInPole
}

function obj_has_behavior_ids(o, ids)
    for _, id in ipairs(ids) do
        if obj_has_behavior_id(o, id) ~= 0 then return true end
    end
end

local lifeMushroomObjs = {}
local E_MODEL_LIFE_MUSHROOM = smlua_model_util_get_id("life_mushroom_geo")

function create_life_mushroom(o)
    if math.random(5) ~= 6 and obj_has_behavior_ids(o, mushroomBhvs) then
        lifeMushroomObjs[o] = 1
        djui_chat_message_create("life mushroom!")
    else lifeMushroomObjs[o] = nil end
end

function replace_life_mushroom_model(o, _, model)
    if lifeMushroomObjs[o] and model == E_MODEL_1UP then
        lifeMushroomObjs[o] = 2
        obj_set_model_extended(o, E_MODEL_LIFE_MUSHROOM)
    end
end

function collect_life_mushroom(o)
    if lifeMushroomObjs[o] == 2 then
        local m = nearest_mario_state_to_object(o)
        if m then
            local i = m.playerIndex
            if obj_check_if_collided_with_object(o, m.marioObj) ~= 0
            and character_get_current_number(i) == CT_ROSALINA then
                local e = gCharacterStates[i].rosalina
                if e.hp < 6 then
                    e.meterTimer = 1
                    e.meterState = METER_STATE_JOIN
                    m.numLives = m.numLives - 1
                    m.health = 0x7FF
                    if i == 0 then enable_time_stop_including_mario() end
                end
            end
        end
    end
    lifeMushroomObjs[o] = nil
end

return {
    { HOOK_MARIO_UPDATE, rosalina_update },
    { HOOK_ALLOW_INTERACT, rosalina_allow_interact },
    { HOOK_BEFORE_SET_MARIO_ACTION, rosalina_before_action },
    { HOOK_ON_OBJECT_LOAD, create_life_mushroom, global = true },
    { HOOK_OBJECT_SET_MODEL, replace_life_mushroom_model, global = true },
    { HOOK_ON_OBJECT_UNLOAD, collect_life_mushroom, global = true },
    { HOOK_ON_HUD_RENDER_BEHIND, rosalina_health_meter_particles, global = true },
    meter = rosalina_health_meter
}