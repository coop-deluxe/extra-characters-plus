--- Vars that all movesets use --
ANGLE_QUEUE_SIZE = 9

--- @type CharacterState[]
gCharacterStates = {}
for i = 0, (MAX_PLAYERS - 1) do
    gCharacterStates[i] = {
        mario = gMarioStates[i],
        luigi = {
            scuttle = 0,
            lastHurtCounter = 0
        },
        toad = {
            averageForwardVel = 0
        },
        waluigi = {
            lastHurtCounter = 0,
            swims = 0
        },
        wario = {
            angleDeltaQueue = {},
            lastHurtCounter = 0,
            stickLastAngle = 0,
            spinDirection = 0,
            spinBufferTimer = 0,
            spinInput = 0,
            lastIntendedMag = 0
        },
        toadette = {
            averageForwardVel = 0
        },
        peach = {},
        daisy = {},
        yoshi = {},
        birdo = {
            spitTimer = 0,
            framesSinceShoot = 255,
            flameCharge = 0
        },
        spike = {},
        pauline = {},
        rosalina = {
            hp = 3,
            meterState = 0,
            meterTimer = 0,
            lastHealCounter = 0,
            lastHurtCounter = 0,
            canSpin = true,
            spinObj = nil,
            orbitObjActive = false,
            orbitObjDist = 0,
            orbitObjAngle = 0
        },
        wapeach = {},
        dk = {},
        sonic = {
            spinCharge = 0,
            groundYVel = 0,
            prevForwardVel = 0,
            peakHeight = 0,
            actionADone = false,
            actionBDone = false,
            bounceCooldown = 0,
            spindashState = 0,
            instashieldTimer = 0,
            oxygen = 900, -- 30 seconds
            prevVelY = 0,
            prevHeight = 0,
            physTimer = 0,
            lastforwardPos = gVec3fZero(),
            realFVel = 0,
            wallSpam = 0,
            prevWallAngle = -1
        }
    }
    for j = 1, ANGLE_QUEUE_SIZE do gCharacterStates[i].wario.angleDeltaQueue[j] = 0 end

    gPlayerSyncTable[i].rings = 0
end
