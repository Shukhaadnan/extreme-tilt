-- Config: every tunable number in one place (ReplicatedStorage.Config).
-- Workspace attributes named "Cfg_<Key>" override a value at runtime (used by SelfTest / sped-up test rounds).
local Config = {}

-- World layout
Config.PLATE_Y = 300 -- y of the plate's top surface when flat
Config.PLATE_RADIUS = 55
Config.PLATE_THICK = 3
Config.LOBBY_CENTER = Vector3.new(0, 304, 132) -- top surface centre of the lobby island
Config.LOBBY_RADIUS = 34

-- Round flow (seconds)
Config.INTERMISSION = 7
Config.FIRST_INTERMISSION = 5
Config.COUNTDOWN = 3
Config.ROUND_TIME = 70
Config.RESULTS_TIME = 3
Config.MIN_BODIES = 8 -- bots fill the plate up to this many bodies
Config.MAX_BOTS = 7

-- Tilt physics (see TiltMath)
Config.TILT_PER_UNIT = 0.17 -- degrees of tilt per (weight * studs) of torque
Config.MAX_TILT = 40 -- degrees
Config.TILT_RATE = 20 -- max degrees per second the plate can move
Config.SLIDE_K = 20 -- studs/s of slide at sin(angle)=1 above the dead zone; ~12 at max tilt, below walk speed so running uphill always works
Config.SLIDE_DEADZONE = 6 -- degrees: no sliding below this
Config.JUMP_HEIGHT = 7.2 -- normal jump (BOUNCY round raises it)
Config.MOD_DOUBLE = false -- DOUBLE DROPS round
Config.SLIDE_MAX = 10 -- slide never beats running: steep plate looks wild, but you can always run uphill
Config.PLAYER_WEIGHT = 1
-- Standing on a landed object: it's slippery (you slide off faster), so climbing on a cow is no safe spot
Config.OBJ_SLIDE_MULT = 1.8
Config.OBJ_SLIP = 8 -- studs/s pushing you off the object's top, even when the plate is flat
Config.SLIDE_TOP = 18 -- slide applies up to this high above the plate (tall objects included)
Config.WALK_SPEED = 21
Config.DANGER_TILT = 26 -- UI turns red above this

-- Elimination
Config.OUT_BELOW = 12 -- out when this far below the plate surface
Config.TELEPORT_BELOW = 160 -- fallen bodies go back to the lobby when this far below...
Config.OUT_MAX_SECONDS = 1.0 -- ...or this long after going out (fallen players become ghosts right then)
Config.SAFETY_Y = 60 -- anything below this height is sent to the lobby (safety net)
Config.MAX_OBJECTS = 4 -- landed objects on the plate at once (oldest poofs)

-- Events
Config.RANDOM_DROPS = false -- sir Oct 15: no random falling objects; only paid drops + ghost junk fall. The plate tilts itself.
Config.FIRST_EVENT_AT = 1.5
-- Lurch: the plate warns (red arrow), then throws itself hard toward one side and comes back
Config.LURCH_FIRST = 5
Config.LURCH_GAP_START = 6.5 -- seconds between lurches at the start (+-20%)
Config.LURCH_GAP_END = 3.8 -- ... and near the end
Config.LURCH_WARN = 1.0
Config.LURCH_TIME = 2.0
Config.LURCH_TILT = 22 -- extra degrees at the peak
Config.LURCH_RATE = 30 -- the plate may move this fast during a lurch
Config.EVENT_GAP_START = 3.3
Config.EVENT_GAP_END = 2.3
Config.FINAL_RUSH = 18 -- last N seconds: double drops
Config.OBJECT_LIFETIME = 1.5 -- seconds a landed object stays after it hits the plate (sir: "1-2 secs at most"), then it poofs
Config.WARN_TIME = 1.8 -- target marker shows this long before an object lands
Config.FALL_TIME = 1.0 -- the visible fall (last part of the warning): object drops from FALL_HEIGHT and lands on time
Config.FALL_HEIGHT = 120

-- Shrinking plate: at these fractions of the round the outer ring crumbles away (radius after each step)
Config.SHRINK_STEPS = { { at = 0.28, r = 47 }, { at = 0.5, r = 40 }, { at = 0.72, r = 33 } }
Config.SHRINK_WARN = 3 -- seconds of flashing warning before each crumble
-- the plate adapts to how many REAL players are in the round (bots don't count):
-- 1-2 players: early, it skips straight to the last ring (one big crumble); 3-4: all 3 breaks, much sooner; 5+: normal
Config.SHRINK_DUO = { { at = 0.15, r = 33 } }
Config.SHRINK_MID = { { at = 0.18, r = 47 }, { at = 0.34, r = 40 }, { at = 0.5, r = 33 } }

-- Shoving (sir Oct 15: "make the push actually annoying"): ~16 studs + a short knock-down. Not a one-hit kill from the middle.
Config.SHOVE_RANGE = 8
Config.SHOVE_POWER = 50 -- horizontal studs/s (held for SHOVE_TIME)
Config.SHOVE_UP = 14 -- they get lifted a bit
Config.SHOVE_TIME = 0.28 -- seconds the push is held (~14 studs, more with the knock-down)
Config.SHOVE_COOLDOWN = 1.3
Config.SHOVE_IMMUNE = 0.7 -- seconds a shoved body can't be shoved again
Config.SHOVE_STUN = 0.55 -- shoved: knocked over (ragdoll) for this long, can't steer
-- Missed push (sir Oct 15): push at nobody = you lunge forward and trip (can send you off near the edge)
Config.WHIFF_SPEED = 30 -- studs/s forward (held for WHIFF_TIME): ~7 studs
Config.WHIFF_TIME = 0.24
Config.WHIFF_STUN = 0.9 -- on the floor this long
Config.WHIFF_COOLDOWN = 2.2 -- a miss costs you: longer wait before the next push (a hit = SHOVE_COOLDOWN)
Config.SHOVE_CONE = 0.35 -- must be roughly in FRONT of you (dot with your facing); sideways/behind = miss
-- Dodge (Q / gamepad Y / DODGE button): quick dash, pushes miss you for a moment
Config.DODGE_SPEED = 52 -- studs/s (held for DODGE_TIME): ~8 studs
Config.DODGE_TIME = 0.16
Config.DODGE_SAFE = 0.35 -- seconds pushes can't hit you
Config.DODGE_COOLDOWN = 3
Config.BOT_DODGE_CHANCE = 0.05 -- per 0.4 s check while someone is close
Config.BOT_SHOVE_CHANCE = 0.08 -- per 0.4 s check while a bot is right next to someone

-- Difficulty ramp: object weight is multiplied from 1 at the start to this at the end of the round
Config.WEIGHT_RAMP_END = 1.15

-- Wobble: the plate never sits still. A slowly turning sway (degrees) added to the tilt, growing over the round.
Config.WOBBLE_START = 5
Config.WOBBLE_END = 10
Config.WOBBLE_SPIN = 0.55 -- radians per second the sway direction turns

-- Earthquake: a warning, then the plate jerks hard one way and back (the hectic moment of a round)
Config.QUAKE_FIRST = 20 -- seconds into the round
Config.QUAKE_GAP = 18 -- seconds between quakes (+-20%)
Config.QUAKE_WARN = 1.2
Config.QUAKE_TIME = 2.4 -- seconds of shaking (direction flips halfway)
Config.QUAKE_TILT = 12 -- extra degrees while it shakes
Config.QUAKE_RATE = 32 -- the plate may move this fast during a quake

-- Bots
Config.BOT_SPEED = 19
Config.BOT_THINK = 0.35
Config.BOT_REACT_MIN = 0.35 -- seconds a bot needs to notice a new landing
Config.BOT_REACT_MAX = 1.1

-- Round twists (one random twist most rounds; first round of a server is always classic)
Config.MOD_CHANCE = 0.7
-- KOs: a push that makes someone fall within KO_WINDOW seconds counts as a KO for the pusher
Config.KO_WINDOW = 4
Config.KO_COINS = 10
-- Crown: last round's winner wears it; push the holder off to steal it
Config.CROWN_STEAL_COINS = 25
Config.CROWN_KEEP_COINS = 15
-- Pickups lying on the plate: Banana (slip), Boots (can't be pushed), Spring (big jump)
Config.PICKUP_FIRST = 6
Config.PICKUP_GAP = 7 -- seconds between pickups (+-25%)
Config.PICKUP_MAX = 2
Config.PICKUP_LIFE = 12
Config.BOOTS_TIME = 5
Config.SPRING_UP = 75
-- Ghosts: fallen players watch from above and drop junk on the ones still standing
Config.GHOST_GRACE = 20 -- all real players fell but bots are still on: the round runs this much longer so ghosts can play
Config.LAST_ONE_DELAY = 1.2 -- sir Oct 16: the round ENDS when only one is left on the plate (no surviving the tilt alone); short beat so the final KO is seen
Config.GHOST_COOLDOWN = 3
Config.GHOST_MAX = 8 -- drops per round
Config.GHOST_WARN = 1.3

function Config.get(key: string): any
	local ok, v = pcall(function()
		return workspace:GetAttribute("Cfg_" .. key)
	end)
	if ok and v ~= nil then
		return v
	end
	return Config[key]
end

return Config
