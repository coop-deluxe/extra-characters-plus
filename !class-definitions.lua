--- Don't add any functional code to this file ---
--- @meta

--- @class LuigiState
--- @field public scuttle integer
--- @field public lastHurtCounter integer

--- @class ToadState
--- @field public averageForwardVel number

--- @class WaluigiState
--- @field public lastHurtCounter integer
--- @field public swims integer

--- @class WarioState
--- @field public angleDeltaQueue integer[]
--- @field public lastHurtCounter integer
--- @field public stickLastAngle integer
--- @field public spinDirection integer
--- @field public spinBufferTimer integer
--- @field public spinInput integer
--- @field public lastIntendedMag number

--- @class ToadetteState
--- @field public averageForwardVel number

--- @class PeachState

--- @class DaisyState

--- @class YoshiState

--- @class BirdoState
--- @field public spitTimer integer
--- @field public framesSinceShoot integer
--- @field public flameCharge integer

--- @class SpikeState

--- @class PaulineState

--- @class RosalinaState
--- @field public hp integer
--- @field public meterState integer
--- @field public meterTimer integer
--- @field public lastHealCounter integer
--- @field public lastHurtCounter integer
--- @field public canSpin boolean
--- @field public spinObj Object?
--- @field public orbitObjActive boolean
--- @field public orbitObjDist number
--- @field public orbitObjAngle integer

--- @class WapeachState

--- @class DonkeyKongState

--- @class SonicState
--- @field public spinCharge integer
--- @field public groundYVel integer
--- @field public prevForwardVel integer
--- @field public peakHeight integer
--- @field public actionADone boolean
--- @field public actionBDone boolean
--- @field public bounceCooldown integer
--- @field public spindashState integer
--- @field public instashieldTimer integer
--- @field public oxygen integer
--- @field public prevVelY number
--- @field public prevHeight number
--- @field public physTimer integer
--- @field public lastforwardPos Vec3f
--- @field public realFVel number
--- @field public wallSpam number
--- @field public prevWallAngle number

--- @class CharacterState
--- @field public mario MarioState
--- @field public luigi LuigiState
--- @field public toad ToadState
--- @field public waluigi WaluigiState
--- @field public wario WarioState
--- @field public toadette ToadetteState
--- @field public peach PeachState
--- @field public daisy DaisyState
--- @field public yoshi YoshiState
--- @field public birdo BirdoState
--- @field public spike SpikeState
--- @field public pauline PaulineState
--- @field public rosalina RosalinaState
--- @field public wapeach WapeachState
--- @field public dk DonkeyKongState
--- @field public sonic SonicState

--- @alias SonicMouthGSCId
--- | `SONIC_MOUTH_NORMAL`
--- | `SONIC_MOUTH_FROWN`
--- | `SONIC_MOUTH_GRIMACING`
--- | `SONIC_MOUTH_HAPPY`
--- | `SONIC_MOUTH_GRIN`
--- | `SONIC_MOUTH_ATTACKED`
--- | `SONIC_MOUTH_SHOCKED`
--- | `SONIC_MOUTH_SURPRISED`
--- | `SONIC_MOUTH_NEUTRAL`

--- @alias SonicMouthSideGSCId
--- | `SONIC_MOUTH_LEFT`
--- | `SONIC_MOUTH_RIGHT`

--- @alias HandParam
--- | `SONIC_HAND_RIGHT`
--- | `SONIC_HAND_LEFT`
--- | `WAPEACH_HAND_AXE`
