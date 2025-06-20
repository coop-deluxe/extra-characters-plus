-- Custom Geo Functions --

-- Sonic Spin/Ball Acts --

local sSonicSpinBallActs = {
    [ACT_SPIN_JUMP]        = true,
    [ACT_SPIN_DASH]        = true,
    [ACT_SPIN_DASH_CHARGE] = true,
}

--- @param n GraphNode | FnGraphNode
--- Switches between the spin and ball models during a spin jump
function geo_ball_switch(n)
    local switch = cast_graph_node(n)
    local m = geo_get_mario_state()
    if sSonicSpinBallActs[m.action] then
        switch.selectedCase = ((m.actionTimer - 1) % 4 // 2 + 1)
    else
        switch.selectedCase = 0
    end
end

-- Wapeach Axe Acts --

local sWapeachAxeActs = {
    [ACT_AXECHOP]      = true,
    [ACT_SPIN]         = true,
    [ACT_SPINAIR]      = true,
    [ACT_AXESPINDIZZY] = true,
}

--- @param n GraphNode | FnGraphNode
--- Switches Wapeach's Hands when using her moveset.
function geo_custom_hand_switch(n)
    local switch = cast_graph_node(n)
    local m = geo_get_mario_state()
    if sWapeachAxeActs[m.action] then
        switch.selectedCase = 1
    else
        switch.selectedCase = 0
    end
end
