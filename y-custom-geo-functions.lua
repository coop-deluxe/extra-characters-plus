-- Custom Geo Functions --

--- @param m MarioState
--- @return integer
--- Returns from directions between 1-8 depending on the camera angle
function mario_yaw_from_camera(m)
    local l = gLakituState
    local tau = math.pi * 2
    local headAngle = m.marioObj.header.gfx.angle.y

    -- vvv Needs fixing later. vvv
    --[[for i = MARIO_ANIM_PART_ROOT, MARIO_ANIM_PART_HEAD + 1 do
        headAngle = headAngle + m.marioBodyState.animPartsRot[i].y
    end]]

    local vector = {X = l.pos.x - m.pos.x, Y = l.pos.y - m.pos.y,  Z = l.pos.z - m.pos.z}
    local r0 = math.rad((headAngle * 360) / 0x10000)
    local r1 = r0 < 0 and tau - math.abs(r0) or r0
    local a0 = math.atan(vector.Z, vector.X) + math.pi * 0.5

    local a1
    a1 = ((a0 < 0 and tau - math.abs(a0) or a0) + r1)

    local a2 = (a1 % tau) * 8 / tau
    local angle = (math.round(a2) % 8) + 1
    return angle
end

-- Sonic Spin/Ball Acts --

local sSonicSpinBallActs = T{
    ACT_SONIC_SPIN_JUMP,
    ACT_SONIC_SPIN_DASH,
    ACT_SONIC_AIR_SPIN,
    ACT_SONIC_HOMING_ATTACK
}

local sSonicInstashieldActs = T{
    ACT_SONIC_SPIN_JUMP,
    ACT_SONIC_AIR_SPIN
}

local sSonicSpinDashActs = T{
    ACT_SONIC_SPIN_DASH_CHARGE
}

--- @param n GraphNode | FnGraphNode
--- Switches between the spin and ball models during a spin/ball actions
function geo_ball_switch(n)
    local switch = cast_graph_node(n)
    local m = geo_get_mario_state()
    local e = gCharacterStates[m.playerIndex].sonic

    if sSonicSpinBallActs[m.action] then
        if sSonicInstashieldActs[m.action] and e.instashieldTimer > 0 then
            switch.selectedCase = 4
        else
            switch.selectedCase = ((m.actionTimer - 1) % 4 // 2 + 1)
        end
    elseif sSonicSpinDashActs[m.action] then
        switch.selectedCase = 3
    elseif m.action == ACT_GROUND_POUND and m.actionTimer > 15 then
        switch.selectedCase = 1
    else
        switch.selectedCase = 0
    end
end

-- SlowDownBoots 

--- @param n GraphNode | FnGraphNode
--- Switches states when SlowDownBoots is true.
function geo_shoe_slowdown_boots(n)
    local switch = cast_graph_node(n)

    switch.selectedCase = sSlowDownBoots and 1 or 0
end

-- Spindash States --

--- @param n GraphNode | FnGraphNode
--- Switches the spindash states
function geo_custom_spindash_states(n)
    local switch = cast_graph_node(n)
    local m = geo_get_mario_state()
    local e = gCharacterStates[m.playerIndex].sonic

    switch.selectedCase = e.spindashState
end

-- Mouth Switch --

SONIC_MOUTH_NORMAL    = 0 --- @type SonicMouthGSCId
SONIC_MOUTH_FROWN     = 1 --- @type SonicMouthGSCId
SONIC_MOUTH_GRIMACING = 2 --- @type SonicMouthGSCId
SONIC_MOUTH_HAPPY     = 3 --- @type SonicMouthGSCId
SONIC_MOUTH_GRIN      = 4 --- @type SonicMouthGSCId
SONIC_MOUTH_ATTACKED  = 5 --- @type SonicMouthGSCId
SONIC_MOUTH_SHOCKED   = 6 --- @type SonicMouthGSCId
SONIC_MOUTH_SURPRISED = 7 --- @type SonicMouthGSCId
SONIC_MOUTH_NEUTRAL   = 8 --- @type SonicMouthGSCId

local sGrimacingActs = T{
    ACT_HOLD_HEAVY_IDLE,
    ACT_SHIVERING,
    ACT_HOLD_HEAVY_WALKING,
    ACT_SHOCKED,
    ACT_HEAVY_THROW
}

local sSurprisedEyeStates = T{
    MARIO_EYES_LOOK_LEFT,
    MARIO_EYES_LOOK_RIGHT,
    MARIO_EYES_LOOK_UP,
    MARIO_EYES_LOOK_DOWN
}

--- @param n GraphNode | FnGraphNode
--- Switches the mouth state
function geo_switch_mario_mouth(n)
    local switch = cast_graph_node(n)
    local m = geo_get_mario_state()
    local body = geo_get_body_state()
    local homingAttacked = m.action == ACT_SONIC_FALL and m.actionArg >= 5
    local frame = m.marioObj.header.gfx.animInfo.animFrame

    if body.eyeState == MARIO_EYES_DEAD then
        switch.selectedCase = SONIC_MOUTH_ATTACKED
    elseif sGrimacingActs[m.action] then
        switch.selectedCase = SONIC_MOUTH_GRIMACING
    elseif m.action == ACT_PANTING then
        switch.selectedCase = SONIC_MOUTH_SURPRISED
    elseif body.eyeState == MARIO_EYES_HALF_CLOSED and m.action == ACT_START_SLEEPING then
        switch.selectedCase = SONIC_MOUTH_SHOCKED
        m.actionTimer = 0
    elseif body.handState == MARIO_HAND_PEACE_SIGN or (homingAttacked and frame <= 22) then
        switch.selectedCase = SONIC_MOUTH_GRIN
    else
        switch.selectedCase = SONIC_MOUTH_NORMAL
    end
end

-- Mouth Side Switch --

SONIC_MOUTH_LEFT  = 0 --- @type SonicMouthSideGSCId
SONIC_MOUTH_RIGHT = 1 --- @type SonicMouthSideGSCId

--- @param n GraphNode | FnGraphNode
--- Switches the side that the mouth is being displayed on
function geo_switch_mario_mouth_side(n)
    local switch = cast_graph_node(n)
    local m = geo_get_mario_state()
    local angle = mario_yaw_from_camera(m)

    switch.selectedCase = (angle <= 4 or m.marioBodyState.handState == MARIO_HAND_PEACE_SIGN)
        and SONIC_MOUTH_RIGHT
        or SONIC_MOUTH_LEFT
end

-- Custom Hand Switch --

-- Hand Params
SONIC_HAND_RIGHT = 0 --- @type HandParam
SONIC_HAND_LEFT  = 1 --- @type HandParam
WAPEACH_HAND_AXE = 2 --- @type HandParam

-- Wapeach Hand
local sWapeachAxeActs = T{
    ACT_AXE_CHOP,
    ACT_AXE_SPIN,
    ACT_AXE_SPIN_AIR,
    ACT_AXE_SPIN_DIZZY
}

-- Sonic Hand
local sSonicHandCopies = T{
    MARIO_HAND_FISTS,
    MARIO_HAND_OPEN,
    MARIO_HAND_HOLDING_CAP,
    MARIO_HAND_HOLDING_WING_CAP,
    MARIO_HAND_RIGHT_OPEN
}

local sSonicHandStateActs = {
    [ACT_STAR_DANCE_EXIT]    = { [SONIC_HAND_LEFT] = MARIO_HAND_PEACE_SIGN, [SONIC_HAND_RIGHT] = MARIO_HAND_FISTS },
    [ACT_STAR_DANCE_NO_EXIT] = { [SONIC_HAND_LEFT] = MARIO_HAND_PEACE_SIGN, [SONIC_HAND_RIGHT] = MARIO_HAND_FISTS },
}

local handCases = {
    {condition = function (frame) return in_between(frame, 9, 19, true) end, hands = {[SONIC_HAND_LEFT] = MARIO_HAND_PEACE_SIGN, [SONIC_HAND_RIGHT] = MARIO_HAND_OPEN}},
    {condition = function (frame) return in_between(frame, 9, 22, true) end, hands = {[SONIC_HAND_LEFT] = MARIO_HAND_OPEN, [SONIC_HAND_RIGHT] = MARIO_HAND_OPEN}},
[4]={condition = function (frame) return frame <= 26 end, hands = {[SONIC_HAND_LEFT] = MARIO_HAND_PEACE_SIGN, [SONIC_HAND_RIGHT] = MARIO_HAND_PEACE_SIGN}},
}

--- @param n GraphNode | FnGraphNode
--- Switches the hand state
function geo_custom_hand_switch(n)
    local switch = cast_graph_node(n)
    local m = geo_get_mario_state()
    local bodyState = geo_get_body_state()
    local param = switch.parameter
    local frame = m.marioObj.header.gfx.animInfo.animFrame

    if param == WAPEACH_HAND_AXE then
        switch.selectedCase = (sWapeachAxeActs[m.action] or m.marioObj.header.gfx.animInfo.animID == CS_ANIM_MENU) and 1 or 0
    else
        if sSonicHandStateActs[m.action] and frame >= 58 then
            switch.selectedCase = sSonicHandStateActs[m.action][param]
        elseif m.action == ACT_SONIC_FALL and m.actionArg >= 5 then
            local animIndex = m.actionArg - 4
            local case = handCases[animIndex]
            switch.selectedCase = case and case.condition(frame) and case.hands[param] or MARIO_HAND_FISTS
        elseif sSonicHandCopies[bodyState.handState] then
            if bodyState.handState == MARIO_HAND_OPEN or bodyState.handState == MARIO_HAND_RIGHT_OPEN then
                if bodyState.handState == MARIO_HAND_OPEN then
                    if param == SONIC_HAND_LEFT then
                        switch.selectedCase = MARIO_HAND_OPEN
                    end
                end
                if bodyState.handState == MARIO_HAND_RIGHT_OPEN then
                    if param == SONIC_HAND_RIGHT then
                        switch.selectedCase = MARIO_HAND_OPEN
                    end
                end
            elseif (bodyState.action & ACT_FLAG_SWIMMING_OR_FLYING) ~= 0 then
                switch.selectedCase = MARIO_HAND_OPEN
            else
                switch.selectedCase = bodyState.handState
            end
        end
    end
end

-- Donkey Kong Angry Acts --

local sDonkeyKongAngryActs = T{
    ACT_DONKEY_KONG_POUND,
    ACT_DONKEY_KONG_POUND_HIT
}

--- @param n GraphNode | FnGraphNode
--- Switches between normal head and angry head during angry actions
function geo_custom_dk_head_switch(n)
    local switch = cast_graph_node(n)
    local m = geo_get_mario_state()
    switch.selectedCase = sDonkeyKongAngryActs[m.action] or 0
end

local sDonkeyKongRollActs = {
    [ACT_DONKEY_KONG_ROLL] = 1,
    [ACT_DONKEY_KONG_ROLL_AIR] = 0
}

--- @param n GraphNode | FnGraphNode
--- Switches between the spin and main model.
function custom_dkroll_switch(n)
    local switch = cast_graph_node(n)
    local m = geo_get_mario_state()

    switch.selectedCase = sDonkeyKongRollActs[m.action] == m.actionState and 1 or 0
end

-- Yoshi Tongue Head Switch --

--- @param n GraphNode | FnGraphNode
--- Switches Yoshi Heads 
function custom_yoshi_heads(n)
    local switch = cast_graph_node(n)
    local m = geo_get_mario_state()
end