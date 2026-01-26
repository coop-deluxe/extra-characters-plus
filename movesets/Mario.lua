require "vanilla-chars"
require "anims/mario"

return {
    { HOOK_MARIO_UPDATE, char_update },
    { HOOK_ON_SET_MARIO_ACTION, char_on_set_action }
}