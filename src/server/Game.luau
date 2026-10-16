-- Game: the round loop + plate physics + eliminations + stats.
--   Intermission (lobby) -> Countdown (on the plate, frozen) -> Round (objects drop, plate tilts) -> Results -> lobby.
-- Replicated state lives in ReplicatedStorage attributes: Phase, PhaseEnds (server time), Alive, Total, Round, TiltDeg.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local TiltMath = require(ReplicatedStorage:WaitForChild("TiltMath"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))
local Map = require(script.Parent.Map)
local Objects = require(ReplicatedStorage:WaitForChild("Objects"))
local Bots = require(script.Parent.Bots)
local Data = require(script.Parent.Data)

local Game = {}
Game.phase = "Idle"
Game.tilt = { x = 0, z = 0 } -- current tilt vector (degrees)
Game.torque = { x = 0, z = 0 }
Game.participants = {} -- array of records
Game.objects = {} -- array of { model, landed, born }
Game.round = 0
Game.rng = Random.new()
Game.forceBotRounds = false -- SelfTest: run rounds with no players
Game.stopLoop = false
Game.started = false
Game.remotes = nil :: Folder?
Game.log = {} -- recent event strings (SelfTest reads these)
Game.roundStart = 0 -- os.clock() when GO happened
Game.lastLand = 0
Game.logT = {} :: { number }
Game.plateR = Config.PLATE_RADIUS -- current standing radius (shrinks during a round)
Game.safeR = Config.PLATE_RADIUS -- radius that will still exist after the next crumble
Game.fallId = 0
Game.shoveAt = {} :: { [any]: number } -- shover key -> last shove time
Game.botActionsOff = false -- SelfTest: bots don't push/dodge on their own during scripted checks
Game.dodgeAt = {} :: { [any]: number } -- dodger key -> last dodge time
Game.shovedAt = {} :: { [any]: number } -- target model -> last time it was shoved

-- object weight multiplier: 1 at GO, WEIGHT_RAMP_END at the end of the round
function Game.weightRamp(): number
	if Game.phase ~= "Round" and Game.phase ~= "Results" then
		return 1
	end
	local t = (os.clock() - Game.roundStart) / math.max(1, Config.get("ROUND_TIME"))
	return TiltMath.lerp(1, Config.get("WEIGHT_RAMP_END"), t)
end

local IMPACT_SFX = {
	Watermelon = "splat",
	Cake = "splat",
	Duck = "boing",
	Anvil = "metalPipe",
	Cow = "bonk",
	Piano = "vineBoom",
	Meteor = "explosion",
}

local function logEvent(s: string)
	if Workspace:GetAttribute("TiltDebug") == true then
		print("[TiltLog] " .. s)
	end
	table.insert(Game.log, s)
	table.insert(Game.logT, os.clock())
	if #Game.log > 400 then
		table.remove(Game.log, 1)
		table.remove(Game.logT, 1)
	end
end

---------------------------------------------------------------- remotes / replicated state
function Game.logEvent(s: string)
	logEvent(s)
end

function Game.setupRemotes()
	local f = ReplicatedStorage:FindFirstChild("Remotes")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Remotes"
		f.Parent = ReplicatedStorage
	end
	for _, n in ipairs({ "PlaySfx", "Notify", "Shove", "Ghost", "Dodge" }) do
		if not f:FindFirstChild(n) then
			local r = Instance.new("RemoteEvent")
			r.Name = n
			r.Parent = f
		end
	end
	Game.remotes = f
	return f
end

local function notifyAll(kind: string, data: any?)
	local r = Game.remotes and Game.remotes:FindFirstChild("Notify")
	if r then
		r:FireAllClients(kind, data)
	end
end
Game.notifyAll = notifyAll

local function notify(player: Player, kind: string, data: any?)
	local r = Game.remotes and Game.remotes:FindFirstChild("Notify")
	if r and player.Parent then
		r:FireClient(player, kind, data)
	end
end

function Game.setPhase(name: string, duration: number)
	Game.phase = name
	ReplicatedStorage:SetAttribute("Phase", name)
	ReplicatedStorage:SetAttribute("PhaseEnds", Workspace:GetServerTimeNow() + duration)
	logEvent("phase " .. name)
end

local function aliveCounts()
	local alive, total, aliveReal, totalReal = 0, 0, 0, 0
	for _, rec in ipairs(Game.participants) do
		total += 1
		if rec.kind == "player" then
			totalReal += 1
		end
		if rec.alive then
			alive += 1
			if rec.kind == "player" then
				aliveReal += 1
			end
		end
	end
	return alive, total, aliveReal, totalReal
end
Game.aliveCounts = aliveCounts

local function publishCounts()
	local alive, total = aliveCounts()
	ReplicatedStorage:SetAttribute("Alive", alive)
	ReplicatedStorage:SetAttribute("Total", total)
end

---------------------------------------------------------------- stats (leaderstats; saved by Data)
local function makeLeaderstats(player: Player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	for _, n in ipairs({ "Wins", "Streak", "KOs", "Coins" }) do
		if not ls:FindFirstChild(n) then
			local v = Instance.new("IntValue")
			v.Name = n
			v.Parent = ls
		end
	end
	return ls
end

function Game.refreshStats(p)
	local player = p and p.player
	if not player or not player.Parent then
		return
	end
	local ls = makeLeaderstats(player)
	ls.Wins.Value = p.d.Wins
	ls.Streak.Value = p.d.Streak or 0
	ls.KOs.Value = p.d.KOs or 0
	ls.Coins.Value = p.d.Coins
end

local function addWin(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	p.d.Wins += 1
	Data.changed(p)
end

local function saveStats(userId: number)
	local p = Data.profiles[userId]
	if p and p.dirty then
		Data.save(p)
	end
end
Game.saveStats = saveStats

---------------------------------------------------------------- bodies
local function setFrozen(hum: Humanoid?, frozen: boolean, isBot: boolean)
	if not hum then
		return
	end
	if frozen then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
	else
		hum.WalkSpeed = isBot and Config.get("BOT_SPEED") or Config.get("WALK_SPEED")
		local jh = Config.get("JUMP_HEIGHT")
		hum.JumpHeight = jh
		hum.JumpPower = 50 * math.sqrt(jh / 7.2)
	end
end

local function zeroVelocity(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local lobbyCounter = 0
local function sendToLobby(model: Model?, player: Player?)
	if not model or not model.Parent then
		return
	end
	lobbyCounter += 1
	local spot = Map.lobbySpot(lobbyCounter)
	local L = Config.LOBBY_CENTER
	pcall(function()
		model:PivotTo(CFrame.lookAt(spot, Vector3.new(L.X, spot.Y, L.Z - 30)))
		zeroVelocity(model)
	end)
	if player then
		notify(player, "Lobby", { pos = spot })
	end
end
Game.sendToLobby = sendToLobby
Game.notify = notify
Game.zeroVelocity = zeroVelocity

local function recRoot(rec): BasePart?
	-- (exposed as Game.recRoot)
	local m = rec.model
	if not m or not m.Parent then
		return nil
	end
	local r = m:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end

local function plateLocal(pos: Vector3): Vector3
	local core = Map.plateCore
	if not core then
		return Vector3.zero
	end
	-- local y measured from the plate's top surface
	return core.CFrame:PointToObjectSpace(pos) - Vector3.new(0, Config.PLATE_THICK / 2, 0)
end
Game.plateLocal = plateLocal
Game.recRoot = recRoot
Game.setFrozen = setFrozen

local function onPlate(lp: Vector3, extraR: number?): boolean
	local r = math.sqrt(lp.X * lp.X + lp.Z * lp.Z)
	return lp.Y > -2 and lp.Y < 14 and r <= Game.plateR + (extraR or 1)
end
Game.onPlate = onPlate

local function markOut(rec, why: string)
	if not rec.alive then
		return
	end
	rec.alive = false
	rec.outAt = os.clock()
	rec.aliveTime = (rec.aliveTime or 0) + (os.clock() - (rec.aliveSince or os.clock()))
	local name = rec.kind == "player" and rec.player.DisplayName or rec.bot.name
	logEvent("out " .. name .. " " .. why)
	local root = recRoot(rec)
	if root then
		Sfx.play(Game.rng:NextNumber() < 0.5 and "wilhelm" or "scream", root, 0.8)
	end
	publishCounts()
	-- KO: the last push on them was recent
	local by = rec.lastShovedBy
	local isKO = why == "fell" and by ~= nil and by ~= rec and os.clock() - (rec.lastShovedAt or -math.huge) <= Config.get("KO_WINDOW")
	local byName = isKO and (by.kind == "player" and by.player.DisplayName or by.bot.name) or nil
	notifyAll("Fell", { name = name, bot = rec.kind == "bot", userId = rec.kind == "player" and rec.player.UserId or 0, by = byName })
	if isKO and Game.onKO then
		task.spawn(pcall, Game.onKO, by, rec)
	end
	if Game.onFell then
		task.spawn(pcall, Game.onFell, rec, why)
	end
	if Game.onOut then
		task.spawn(pcall, Game.onOut, rec, why)
	end
end
Game.markOut = markOut
Game.publishCounts = publishCounts

---------------------------------------------------------------- objects
function Game.clearObjects(poof: boolean)
	for _, o in ipairs(Game.objects) do
		if o.model.Parent then
			if poof then
				Objects.poof(o.model)
			else
				o.model:Destroy()
			end
		end
	end
	Game.objects = {}
	local world = Map.world
	local f = world and world:FindFirstChild("Objects")
	if f then
		for _, c in ipairs(f:GetChildren()) do
			c:Destroy()
		end
	end
end

local function crowdSpot(): Vector3
	local R = Game.safeR
	local sx, sz, n = 0, 0, 0
	for _, rec in ipairs(Game.participants) do
		local root = rec.alive and recRoot(rec)
		if root then
			sx += root.Position.X
			sz += root.Position.Z
			n += 1
		end
	end
	local ang
	if n > 0 and Game.rng:NextNumber() < 0.6 and math.sqrt((sx / n) ^ 2 + (sz / n) ^ 2) > 4 then
		ang = math.atan2(sz / n, sx / n) + Game.rng:NextNumber(-0.6, 0.6)
	else
		ang = Game.rng:NextNumber(0, math.pi * 2)
	end
	local r = Game.rng:NextNumber(math.min(14, R * 0.4), R - 8)
	return Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
end
Game.crowdSpot = crowdSpot

-- `kind` falls onto plate-local `pos`. Clients animate the fall (smooth, synced to server time); exactly at landAt the
-- server places the real object on the plate, welded, and the impact happens. No physics bounces, no misses.
function Game.dropObject(kind: string, pos: Vector3, warnTime: number?, by: string?)
	local core = Map.plateCore
	local folder = Map.world and Map.world:FindFirstChild("Objects")
	if not core or not folder then
		return
	end
	local info = Objects.info(kind)
	local wt = warnTime or Config.get("WARN_TIME")
	Game.fallId += 1
	local id = Game.fallId
	local yaw = Game.rng:NextNumber(0, math.pi * 2)
	notifyAll("Drop", { kind = kind, label = info and info.label or kind, by = by })
	notifyAll("Fall", { id = id, kind = kind, x = pos.X, z = pos.Z, yaw = yaw, landAt = Workspace:GetServerTimeNow() + wt, warn = wt })
	logEvent("drop " .. kind)
	local round = Game.round
	task.delay(wt, function()
		if (Game.phase ~= "Round" and not Game.forceBotRounds) or Game.round ~= round then
			return
		end
		Game.land(kind, pos, yaw, id)
	end)
end

-- place a landed object (also used directly by SelfTest)
function Game.land(kind: string, pos: Vector3, yaw: number, id: number?): Model?
	local core = Map.plateCore
	local folder = Map.world and Map.world:FindFirstChild("Objects")
	if not core or not folder then
		return nil
	end
	-- the spot crumbled away while it was falling: it just misses the plate
	if math.sqrt(pos.X * pos.X + pos.Z * pos.Z) > Game.plateR - 1 then
		logEvent("objmiss " .. kind)
		return nil
	end
	local m = Objects.build(kind)
	if not m then
		return nil
	end
	local root = m.PrimaryPart :: BasePart
	root.Anchored = true
	m:PivotTo(Objects.restCF(core.CFrame, root, pos.X, pos.Z, yaw))
	m:SetAttribute("FallId", id or 0)
	m.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local now = os.clock()
	local o = { model = m, landed = true, born = now, landedAt = now, kind = kind }
	table.insert(Game.objects, o)
	Game.stick(m, root, Vector3.new(pos.X, 0, pos.Z))
	root.Anchored = false
	Sfx.play(IMPACT_SFX[kind] or "bonk", root, 0.9)
	notifyAll("Impact", { pos = root.Position, power = m:GetAttribute("Weight") or 2, kind = kind, id = id })
	logEvent("land " .. kind)
	Game.lastLand = now
	return m
end

function Game.spawnEvent(elapsed: number)
	if Config.get("RANDOM_DROPS") ~= true then
		return -- no random objects any more (sir Oct 15): paid drops + ghost junk only
	end
	local roundTime = Config.get("ROUND_TIME")
	local double = elapsed >= roundTime - Config.get("FINAL_RUSH") or Config.get("MOD_DOUBLE") == true
	local first = crowdSpot()
	Game.dropObject(Objects.pick(Game.rng, elapsed), first)
	if double then
		local a = math.atan2(first.Z, first.X) + math.pi + Game.rng:NextNumber(-0.8, 0.8)
		local r = Game.rng:NextNumber(math.min(14, Game.safeR * 0.4), Game.safeR - 8)
		task.delay(0.7, function()
			Game.dropObject(Objects.pick(Game.rng, elapsed), Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		end)
	end
end

-- weld a landed object onto the plate at plate-local (x, z), sitting on the surface, keeping its spin
function Game.stick(model: Model, root: BasePart, lp: Vector3)
	local core = Map.plateCore
	if not core then
		return
	end
	local rel = core.CFrame:ToObjectSpace(root.CFrame)
	local _, yaw, _ = rel:ToEulerAnglesYXZ()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
			d.Massless = true
		elseif d:IsA("Trail") then
			d.Enabled = false
		end
	end
	root.CFrame = core.CFrame * CFrame.new(lp.X, Config.PLATE_THICK / 2 + root.Size.Y / 2, lp.Z) * CFrame.Angles(0, yaw, 0)
	-- BONK: anyone standing where it lands gets knocked away (never left stuck inside it)
	local reach = math.max(root.Size.X, root.Size.Z) / 2 + 2
	for _, rec in ipairs(Game.participants) do
		local rr = rec.alive and recRoot(rec)
		if rr then
			local d = rr.Position - root.Position
			local flat = Vector3.new(d.X, 0, d.Z)
			if flat.Magnitude < reach then
				local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(1, 0, 0)
				local push = dir * (reach - flat.Magnitude + 3)
				if rec.kind == "player" then
					local r = Game.remotes and Game.remotes:FindFirstChild("Notify")
					if r then
						r:FireClient(rec.player, "Knock", { push = push, vel = dir * 30 + Vector3.new(0, 35, 0) })
					end
				else
					rec.model:PivotTo(rec.model:GetPivot() + push + Vector3.new(0, 1, 0))
					rr.AssemblyLinearVelocity = dir * 30 + Vector3.new(0, 35, 0)
				end
				Sfx.play("bonk", rr, 0.8)
			end
		end
	end
	local w = Instance.new("WeldConstraint")
	w.Name = "StuckToPlate"
	w.Part0 = core
	w.Part1 = root
	w.Parent = root
	pcall(function()
		core:SetNetworkOwner(nil)
	end)
end

---------------------------------------------------------------- chaos (wobble + earthquakes)
-- only inside a real round loop (Game.chaosOn), and never in test rounds that switch random drops off
Game.chaosOn = false
Game.quake = nil :: { x: number, z: number, t0: number, t1: number }?
function Game.chaos(now: number): (number, number, number?)
	if not Game.chaosOn or Config.get("FIRST_EVENT_AT") >= 900 or Workspace:GetAttribute("Cfg_NO_CHAOS") == true then
		return 0, 0, nil
	end
	local frac = math.clamp((now - (Game.roundStart or now)) / Config.get("ROUND_TIME"), 0, 1)
	local amp = TiltMath.lerp(Config.get("WOBBLE_START"), Config.get("WOBBLE_END"), frac)
	amp *= 0.65 + 0.35 * math.noise(now * 0.3, (Game.round or 0) * 1.7)
	local a = (Game.wobbleA or 0) + now * Config.get("WOBBLE_SPIN")
	local wx, wz = math.cos(a) * amp, math.sin(a) * amp
	local q = Game.quake
	if q and now >= q.t0 and now < q.t1 then
		local flip = (now - q.t0) > (q.t1 - q.t0) / 2 and -1 or 1
		return wx + q.x * flip, wz + q.z * flip, Config.get("QUAKE_RATE")
	end
	local l = Game.lurch
	if l and now >= l.t0 and now < l.t1 then
		-- smooth hump: 0 -> full -> 0 over the lurch
		local k = math.sin(math.pi * (now - l.t0) / (l.t1 - l.t0))
		return wx + l.x * k, wz + l.z * k, Config.get("LURCH_RATE")
	end
	return wx, wz, nil
end

-- which way the plate goes DOWN for tilt (x, z): flat world unit vector
function Game.lowSide(x: number, z: number): Vector3
	local kx, kz, ang = TiltMath.axisAngle(x, z)
	if ang <= 0 then
		return Vector3.new(1, 0, 0)
	end
	local up = CFrame.fromAxisAngle(Vector3.new(kx, 0, kz), ang):VectorToWorldSpace(Vector3.yAxis)
	local flat = Vector3.new(up.X, 0, up.Z)
	return flat.Magnitude > 1e-4 and flat.Unit or Vector3.new(1, 0, 0)
end

Game.lurch = nil :: { x: number, z: number, t0: number, t1: number }?
function Game.startLurch()
	local a = Game.rng:NextNumber(0, math.pi * 2)
	local warn = Config.get("LURCH_WARN")
	local now = os.clock()
	local k = Config.get("LURCH_TILT")
	local x, z = math.cos(a) * k, math.sin(a) * k
	Game.lurch = { x = x, z = z, t0 = now + warn, t1 = now + warn + Config.get("LURCH_TIME") }
	local low = Game.lowSide(x, z)
	notifyAll("Lurch", { warn = warn, seconds = Config.get("LURCH_TIME"), dx = low.X, dz = low.Z })
	Sfx.play("creak", nil, 0.75, 0.9 + Game.rng:NextNumber() * 0.2) -- the plate groans before it drops
	logEvent("lurch")
end

function Game.startQuake()
	local a = Game.rng:NextNumber(0, math.pi * 2)
	local warn = Config.get("QUAKE_WARN")
	local now = os.clock()
	local k = Config.get("QUAKE_TILT")
	Game.quake = { x = math.cos(a) * k, z = math.sin(a) * k, t0 = now + warn, t1 = now + warn + Config.get("QUAKE_TIME") }
	notifyAll("Quake", { warn = warn, seconds = Config.get("QUAKE_TIME") })
	Sfx.play("buzzer", nil, 0.4)
	task.delay(warn, function()
		Sfx.play("quake", nil, 0.9)
	end)
	logEvent("quake")
end

---------------------------------------------------------------- per-frame step
-- standing on (or right at the rim of) the plate? Uses plate-local position, not a raycast: at the rim a vertical
-- ray misses the tilted disc while the feet still stand on it, which used to park bodies on the edge forever.
local function onSlideZone(lp: Vector3): boolean
	local r = math.sqrt(lp.X * lp.X + lp.Z * lp.Z)
	return lp.Y > -1.5 and lp.Y < 6 and r <= Game.plateR + 3
end
Game.onSlideZone = onSlideZone

local function slideBot(root: BasePart, dt: number)
	local core = Map.plateCore
	if not core then
		return
	end
	local v = Objects.slideVelocity(root, core, Config, TiltMath, Game.plateR)
	if v.Magnitude > 0 then
		root.CFrame += v * dt
	end
end
Game.slideBot = slideBot

function Game.step(dt: number)
	local core = Map.plateCore
	if not core or not core.Parent then
		return
	end
	local now = os.clock()
	local active = Game.phase == "Round"
	local bodies = {}
	local inRound = {}

	-- participants: weight + elimination (winners are final once the round is over)
	local judging = Game.phase ~= "Results"
	for _, rec in ipairs(Game.participants) do
		local root = recRoot(rec)
		if rec.alive and judging then
			local hum = rec.model and rec.model:FindFirstChildOfClass("Humanoid")
			if not root or not hum or hum.Health <= 0 then
				markOut(rec, "gone")
			else
				local lp = plateLocal(root.Position)
				if lp.Y < -Config.get("OUT_BELOW") then
					markOut(rec, "fell")
				else
					if onPlate(lp) then
						table.insert(bodies, { x = root.Position.X, z = root.Position.Z, w = Config.PLAYER_WEIGHT })
					end
					if rec.kind == "bot" then
						inRound[rec.bot] = true
						if active then
							slideBot(root, dt)
						end
					end
				end
			end
		end
		if not rec.alive and not rec.sent then
			local lp = root and plateLocal(root.Position)
			if not root or now - (rec.outAt or now) >= Config.get("OUT_MAX_SECONDS") or (lp and lp.Y < -Config.get("TELEPORT_BELOW")) then
				rec.sent = true
				if root then
					sendToLobby(rec.model, rec.player)
				end
				if Game.onSent then
					task.spawn(pcall, Game.onSent, rec)
				end
			end
		end
	end

	-- objects: weight, landing, lifetime, cleanup
	local landed = {}
	for i = #Game.objects, 1, -1 do
		local o = Game.objects[i]
		local root = o.model.PrimaryPart
		if not o.model.Parent or not root then
			table.remove(Game.objects, i)
			continue
		end
		local lp = plateLocal(root.Position)
		if lp.Y < -40 then
			logEvent((o.landed and "objfall " or "objmiss ") .. o.kind) -- a miss = bounced off a head / the rim before touching down
			o.model:Destroy()
			table.remove(Game.objects, i)
			continue
		end
		if now - (o.landedAt or o.born) > Config.get("OBJECT_LIFETIME") then
			Objects.poof(o.model)
			table.remove(Game.objects, i)
			continue
		end
		local resting = now - o.born > 3 and lp.Y < 14 and root.AssemblyLinearVelocity.Magnitude < 3
		if not o.landed and onPlate(lp, -1) and (lp.Y <= root.Size.Y / 2 + 1.5 or resting) then
			-- touchdown: snap onto the surface and weld to the plate, so it rides the tilt and never slides off
			-- (objects are the whole point of the game: they must stay where they land until they poof)
			o.landed = true
			o.landedAt = now
			Game.stick(o.model, root, lp)
			Sfx.play(IMPACT_SFX[o.kind] or "bonk", root, 0.9)
			notifyAll("Impact", { pos = root.Position, power = o.model:GetAttribute("Weight") or 2 })
			logEvent("land " .. o.kind)
			Game.lastLand = now
		end
		if o.landed then
			table.insert(bodies, { x = root.Position.X, z = root.Position.Z, w = (o.model:GetAttribute("Weight") or 1) * Game.weightRamp() })
			table.insert(landed, o)
		end
	end
	-- too many objects: poof the oldest landed one
	if #landed > Config.get("MAX_OBJECTS") then
		table.sort(landed, function(a, b)
			return (a.landedAt or 0) < (b.landedAt or 0)
		end)
		Objects.poof(landed[1].model)
	end

	if Game.onStep then
		Game.onStep(dt, now, active)
	end

	-- tilt
	local tx, tz = TiltMath.torque(bodies)
	Game.torque.x, Game.torque.z = tx, tz
	local ax, az = 0, 0
	local rate = active and Config.get("TILT_RATE") or 25 -- after the round the plate swings back level fast
	if active then
		ax, az = TiltMath.target(tx, tz, Config.get("TILT_PER_UNIT"), Config.get("MAX_TILT"))
		-- hectic: the plate never sits still (wobble), and earthquakes jerk it hard
		local wx, wz, qRate = Game.chaos(now)
		ax += wx
		az += wz
		local m = TiltMath.magnitude(ax, az)
		local cap = Config.get("MAX_TILT")
		if m > cap then
			ax, az = ax * cap / m, az * cap / m
		end
		if qRate then
			rate = qRate
		end
	end
	Game.tilt.x, Game.tilt.z = TiltMath.approach(Game.tilt.x, Game.tilt.z, ax, az, rate, dt)
	local kx, kz, ang = TiltMath.axisAngle(Game.tilt.x, Game.tilt.z)
	if Map.alignRot then
		Map.alignRot.CFrame = (ang > 0) and CFrame.fromAxisAngle(Vector3.new(kx, 0, kz), ang) or CFrame.identity
	end
	local tiltNow = TiltMath.magnitude(Game.tilt.x, Game.tilt.z)
	ReplicatedStorage:SetAttribute("TiltDeg", math.floor(tiltNow * 10 + 0.5) / 10)
	if Game.chaosOn then
		Game.maxTiltSeen = math.max(Game.maxTiltSeen or 0, tiltNow)
	end

	-- bots shove sometimes (only a little, see Config.SHOVE_*)
	if active then
		Game.botShoveT = (Game.botShoveT or 0) - dt
		if Game.botShoveT <= 0 then
			Game.botShoveT = 0.4
			for _, rec in ipairs(Game.participants) do
				local me = rec.kind == "bot" and rec.alive and not Game.botActionsOff and recRoot(rec)
				if me then
					local look = Vector3.new(me.CFrame.LookVector.X, 0, me.CFrame.LookVector.Z)
					look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
					-- bots only push when someone is actually in front (a bot never whiffs at thin air)
					if Game.rng:NextNumber() < Config.get("BOT_SHOVE_CHANCE") and Game.shoveTarget(rec, me, look) then
						Game.tryShove(rec)
					elseif Game.rng:NextNumber() < Config.get("BOT_DODGE_CHANCE") then
						-- someone close: sometimes sidestep, toward the middle of the plate
						local near = false
						for _, o in ipairs(Game.participants) do
							local r = o ~= rec and o.alive and recRoot(o)
							if r and (r.Position - me.Position).Magnitude < Config.get("SHOVE_RANGE") + 2 then
								near = true
								break
							end
						end
						if near then
							local lp = plateLocal(me.Position)
							local toMid = Vector3.new(-lp.X, 0, -lp.Z)
							local side = Vector3.new(-look.Z, 0, look.X) * (Game.rng:NextNumber() < 0.5 and -1 or 1)
							local dir = toMid.Magnitude > 1 and (side + toMid.Unit * 0.8) or side
							Game.tryDodge(rec, dir)
						end
					end
				end
			end
		end
	end

	-- bots
	Bots.step(dt, {
		active = active,
		plateCF = core.CFrame,
		torque = Game.torque,
		now = now,
		inRound = inRound,
		lastLand = Game.lastLand,
	})

	-- safety net: anything that ends up far below goes back to the lobby
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		if r and r.Position.Y < Config.get("SAFETY_Y") then
			sendToLobby(ch, p)
		end
	end
	for _, b in pairs(Bots.list) do
		if b.root and b.root.Parent and b.root.Position.Y < Config.get("SAFETY_Y") then
			sendToLobby(b.model, nil)
		end
	end
end

---------------------------------------------------------------- shrinking plate
function Game.setPlateR(r: number)
	Game.plateR = r
	ReplicatedStorage:SetAttribute("PlateR", r)
end
function Game.setSafeR(r: number)
	Game.safeR = r
	ReplicatedStorage:SetAttribute("PlateSafeR", r)
end

-- the ring outside radius `r` flashes for `warn` s, then breaks off (with anything standing / lying on it)
function Game.shrinkTo(r: number, warn: number)
	if r >= Game.plateR then
		return
	end
	local rs = Map.radii()
	local k = table.find(rs, r)
	Game.setSafeR(r)
	-- every ring outside r goes (a 2-player round skips straight to the last ring)
	if k then
		for kk = k, #rs - 1 do
			Map.warnRing(kk, warn)
		end
	end
	notifyAll("ShrinkWarn", { r = r, seconds = warn })
	Sfx.play("buzzer", nil, 0.35)
	local round = Game.round
	task.wait(warn)
	if Game.round ~= round or (Game.phase ~= "Round" and not Game.forceBotRounds) then
		return
	end
	-- objects lying on the ring tumble off with it
	for i = #Game.objects, 1, -1 do
		local o = Game.objects[i]
		local root = o.model.PrimaryPart
		if root and o.model.Parent then
			local lp = plateLocal(root.Position)
			if math.sqrt(lp.X * lp.X + lp.Z * lp.Z) > r - 0.5 then
				local w = root:FindFirstChild("StuckToPlate")
				if w then
					w:Destroy()
				end
				root.Massless = false
				root.CanCollide = false
				root.AssemblyLinearVelocity = Vector3.new(lp.X, 0, lp.Z).Unit * 8
				game:GetService("Debris"):AddItem(o.model, 5)
				table.remove(Game.objects, i)
				logEvent("objcrumble " .. o.kind)
			end
		end
	end
	if k then
		for kk = k, #rs - 1 do
			Map.crumble(kk)
		end
	end
	Game.setPlateR(r)
	Sfx.play("rockBreak", nil, 0.55)
	notifyAll("Shrink", { r = r })
	logEvent("shrink " .. r)
end

-- which shrink steps a round uses, from the number of REAL players (bots don't count; 0 = bot-only test round)
function Game.shrinkPlan(nReal: number)
	if nReal >= 1 and nReal <= 2 then
		return Config.SHRINK_DUO, "duo"
	elseif nReal >= 3 and nReal <= 4 then
		return Config.SHRINK_MID, "mid"
	end
	return Config.SHRINK_STEPS, "normal"
end

---------------------------------------------------------------- shoving
-- smooth forward lunge along `dir` (only the horizontal line is driven, gravity still works)
function Game.lunge(root: BasePart, dir: Vector3, speed: number, seconds: number)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "LungeAtt"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Lunge"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	lv.LineDirection = flat.Unit
	lv.LineVelocity = speed
	lv.MaxForce = 1e5
	lv.Parent = root
	task.delay(seconds, function()
		lv:Destroy()
		att:Destroy()
	end)
end

-- push a character for a moment (LinearVelocity; the humanoid can't cancel it), then let go
function Game.burst(root: BasePart, vel: Vector3, seconds: number)
	local att = Instance.new("Attachment")
	att.Name = "BurstAtt"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Burst"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = vel
	lv.MaxForce = 1e6
	lv.Parent = root
	task.delay(seconds, function()
		lv:Destroy()
		att:Destroy()
	end)
end

-- knocked over for a moment (limp, can't steer), then gets back up. Server side = bots; players do it on their client.
function Game.knockDown(model: Model?, seconds: number, tripDir: Vector3?)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	hum.PlatformStand = true
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		if tripDir and tripDir.Magnitude > 0.01 then
			-- tip forward onto your face: spin about (up x forward)
			root.AssemblyAngularVelocity = Vector3.yAxis:Cross(tripDir.Unit) * 6
		else
			root.AssemblyAngularVelocity = Vector3.new(Game.rng:NextNumber(-6, 6), 0, Game.rng:NextNumber(-6, 6))
		end
	end
	task.delay(seconds, function()
		if hum.Parent then
			hum.PlatformStand = false
			pcall(function()
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end)
		end
	end)
end

-- the body rec would push: nearest one in front within range. Bodies mid-dodge can't be picked
-- (returns nil, dodger when the only one there was dodging).
function Game.shoveTarget(rec, me: BasePart, look: Vector3)
	local now = os.clock()
	local best, bestScore, dodger = nil, math.huge, nil
	for _, other in ipairs(Game.participants) do
		local r = other ~= rec and other.alive and not other.ghost and recRoot(other)
		if r then
			local d = r.Position - me.Position
			local flat = Vector3.new(d.X, 0, d.Z)
			local dist = flat.Magnitude
			if dist <= Config.get("SHOVE_RANGE") and math.abs(d.Y) < 5 then
				local front = dist > 0.1 and flat.Unit:Dot(look) or 1
				if front > Config.get("SHOVE_CONE") or dist < 2.5 then
					if (other.dodgeUntil or 0) > now then
						dodger = dodger or other
					else
						local score = dist - front * 2
						if score < bestScore then
							best, bestScore = other, score
						end
					end
				end
			end
		end
	end
	return best, (best == nil) and dodger or nil
end

-- missed push: lunge forward + fall over for a moment
function Game.whiff(rec, me: BasePart, look: Vector3)
	local vel = look * Config.get("WHIFF_SPEED") + Vector3.new(0, 8, 0)
	if rec.kind == "player" then
		notify(rec.player, "Knock", {
			push = Vector3.new(0, 0.3, 0),
			vel = vel,
			label = "MISSED!",
			burst = Config.get("WHIFF_TIME"),
			stun = Config.get("WHIFF_STUN"),
			trip = look, -- fall forward on your face (not a random spin)
		})
	else
		Game.burst(me, vel, Config.get("WHIFF_TIME"))
		Game.knockDown(rec.model, Config.get("WHIFF_STUN"), look)
	end
	notifyAll("Whiffed", { model = rec.model, stun = Config.get("WHIFF_STUN") }) -- clients play the whiff sounds
	logEvent("whiff " .. (rec.kind == "player" and rec.player.DisplayName or rec.bot.name))
end

-- dodge: quick dash in `dir` (flat); pushes miss you for DODGE_SAFE seconds. Returns ok.
function Game.tryDodge(rec, dir: Vector3?): boolean
	if Game.phase ~= "Round" and not Game.forceBotRounds then
		return false
	end
	if not rec or not rec.alive or rec.ghost then
		return false
	end
	local key = rec.player or rec.bot
	local now = os.clock()
	if now - (Game.dodgeAt[key] or -math.huge) < Config.get("DODGE_COOLDOWN") then
		return false
	end
	local me = recRoot(rec)
	if not me then
		return false
	end
	local flat = typeof(dir) == "Vector3" and Vector3.new(dir.X, 0, dir.Z) or Vector3.zero
	if flat.Magnitude ~= flat.Magnitude or flat.Magnitude < 0.05 then -- NaN / no input: dash where you face
		flat = Vector3.new(me.CFrame.LookVector.X, 0, me.CFrame.LookVector.Z)
	end
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	Game.dodgeAt[key] = now
	rec.dodgeUntil = now + Config.get("DODGE_SAFE")
	local vel = flat * Config.get("DODGE_SPEED") + Vector3.new(0, 4, 0)
	if rec.kind == "player" then
		notify(rec.player, "DodgeGo", { vel = vel, burst = Config.get("DODGE_TIME"), cd = Config.get("DODGE_COOLDOWN") })
	else
		Game.burst(me, vel, Config.get("DODGE_TIME"))
	end
	notifyAll("DodgeFx", { model = rec.model })
	logEvent("dodge " .. (rec.kind == "player" and rec.player.DisplayName or rec.bot.name))
	return true
end

-- rec (player or bot) shoves the nearest body in front of them.
local function tryShoveInner(rec): boolean
	if Game.phase ~= "Round" and not Game.forceBotRounds then
		return false
	end
	if not rec or not rec.alive then
		return false
	end
	local key = rec.player or rec.bot
	local now = os.clock()
	if now - (Game.shoveAt[key] or -math.huge) < Config.get("SHOVE_COOLDOWN") then
		return false
	end
	local me = recRoot(rec)
	if not me then
		return false
	end
	local look = Vector3.new(me.CFrame.LookVector.X, 0, me.CFrame.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	local best, dodged = Game.shoveTarget(rec, me, look)
	if not best then
		-- MISSED (nobody there, or they dodged): you lunge forward and trip over yourself
		-- the miss costs extra: next push only after WHIFF_COOLDOWN (instead of SHOVE_COOLDOWN)
		Game.shoveAt[key] = now + Config.get("WHIFF_COOLDOWN") - Config.get("SHOVE_COOLDOWN")
		Game.whiff(rec, me, look)
		if dodged then
			local dn = dodged.kind == "player" and dodged.player.DisplayName or dodged.bot.name
			notifyAll("Dodged", { by = rec.kind == "player" and rec.player.DisplayName or rec.bot.name, to = dn, toId = dodged.kind == "player" and dodged.player.UserId or 0 })
			logEvent("shove dodged")
		end
		return false
	end
	if now - (Game.shovedAt[best.model] or -math.huge) < Config.get("SHOVE_IMMUNE") then
		return false
	end
	if best.heavyUntil and best.heavyUntil > now then
		-- heavy boots: can't be pushed
		Game.shoveAt[key] = now - Config.get("SHOVE_COOLDOWN") + 0.5
		notifyAll("Blocked", { pos = recRoot(best) and (recRoot(best) :: BasePart).Position, byId = rec.kind == "player" and rec.player.UserId or 0 })
		Sfx.play("metalPipe", recRoot(best), 0.4)
		logEvent("shove blocked (boots)")
		return false
	end
	Game.shoveAt[key] = now
	Game.shovedAt[best.model] = now
	local tr = recRoot(best) :: BasePart
	local d = tr.Position - me.Position
	local dir = Vector3.new(d.X, 0, d.Z)
	dir = dir.Magnitude > 0.1 and dir.Unit or look
	local vel = dir * Config.get("SHOVE_POWER") + Vector3.new(0, Config.get("SHOVE_UP"), 0)
	if best.kind == "player" then
		notify(best.player, "Knock", {
			push = Vector3.new(0, 0.5, 0),
			vel = vel,
			label = "SHOVED!",
			burst = Config.get("SHOVE_TIME"),
			stun = Config.get("SHOVE_STUN"),
		})
	else
		Game.burst(tr, vel, Config.get("SHOVE_TIME"))
		Game.knockDown(best.model, Config.get("SHOVE_STUN"))
	end
	-- the shover lunges a little forward so it reads as a push (smooth, held for a moment)
	if rec.kind == "bot" then
		Game.lunge(me, look, 16, 0.14)
	end
	local by = rec.kind == "player" and rec.player.DisplayName or rec.bot.name
	local to = best.kind == "player" and best.player.DisplayName or best.bot.name
	notifyAll("Shoved", {
		pos = tr.Position,
		from = me.Position,
		by = by,
		to = to,
		byId = rec.kind == "player" and rec.player.UserId or 0,
		byModel = me.Parent, -- every client plays the push animation on this character
		toModel = tr.Parent, -- ... and a flinch on this one
	})
	-- the hit sound / flash / burst play on every client (Push.client, "Shoved"); the server only adds the oof
	task.delay(0.14, function()
		if tr.Parent then
			Sfx.play("oof", tr, 0.35)
		end
	end)
	best.lastShovedBy = rec
	best.lastShovedAt = now
	logEvent("shove " .. by .. " -> " .. to)
	return true
end

-- shove + tell a shoving player how long their cooldown is (drives the PUSH button's cooldown fill)
function Game.tryShove(rec): boolean
	local ok = tryShoveInner(rec)
	if rec and rec.kind == "player" and rec.player then
		local cd = Config.get("SHOVE_COOLDOWN")
		local left = math.max(0, cd - (os.clock() - (Game.shoveAt[rec.player] or -math.huge)))
		notify(rec.player, "ShoveResult", { ok = ok, cd = left, total = math.max(cd, left) })
	end
	return ok
end

function Game.recFor(player: Player)
	for _, rec in ipairs(Game.participants) do
		if rec.player == player then
			return rec
		end
	end
	return nil
end

---------------------------------------------------------------- round flow
local function lobbySpotFn(i: number): Vector3
	return Map.lobbySpot(100 + i)
end

function Game.canStart(): boolean
	if Game.forceBotRounds then
		return true
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and ch:FindFirstChild("HumanoidRootPart") then
			return true
		end
	end
	return false
end

function Game.startRound()
	Game.round += 1
	ReplicatedStorage:SetAttribute("Round", Game.round)
	Game.clearObjects(false)
	Game.participants = {}
	Map.buildRings()
	Game.setPlateR(Config.PLATE_RADIUS)
	Game.setSafeR(Config.PLATE_RADIUS)
	table.clear(Game.shoveAt)
	table.clear(Game.shovedAt)

	-- real players with a live character
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and ch:FindFirstChild("HumanoidRootPart") then
			table.insert(Game.participants, { kind = "player", player = p, model = ch, alive = true })
		end
	end
	local nReal = #Game.participants
	Game.nReal = nReal
	local nBots = math.clamp(Config.get("MIN_BODIES") - nReal, 0, Config.get("MAX_BOTS"))
	Bots.setCount(nBots, lobbySpotFn)
	for i = 1, nBots do
		local b = Bots.list[i]
		if b and b.model.Parent then
			table.insert(Game.participants, { kind = "bot", bot = b, model = b.model, alive = true })
		end
	end

	-- shuffle so players don't always stand in the same place, then place everyone on the plate
	for i = #Game.participants, 2, -1 do
		local j = Game.rng:NextInteger(1, i)
		Game.participants[i], Game.participants[j] = Game.participants[j], Game.participants[i]
	end
	local n = #Game.participants
	for i, rec in ipairs(Game.participants) do
		local pos = Map.plateSpot(i, n)
		pcall(function()
			rec.model:PivotTo(CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)))
			zeroVelocity(rec.model)
		end)
		setFrozen(rec.model:FindFirstChildOfClass("Humanoid"), true, rec.kind == "bot")
		if rec.kind == "bot" then
			Bots.stopMoving(rec.bot)
		end
	end
	publishCounts()
	if Game.onRoundStart then
		pcall(Game.onRoundStart, Game.participants)
	end
	logEvent(string.format("start round %d players=%d bots=%d", Game.round, nReal, nBots))
	notifyAll("RoundStart", { total = n, round = Game.round })
end

function Game.unfreezeAll()
	local t = os.clock()
	for _, rec in ipairs(Game.participants) do
		rec.aliveSince = t
		rec.aliveTime = 0
		if rec.alive and rec.model and rec.model.Parent then
			setFrozen(rec.model:FindFirstChildOfClass("Humanoid"), false, rec.kind == "bot")
		end
	end
end

function Game.runRound()
	local roundTime = Config.get("ROUND_TIME")
	local t0 = os.clock()
	Game.roundStart = t0
	local nextEvent = Config.get("FIRST_EVENT_AT")
	local nextQuake = Config.get("QUAKE_FIRST")
	local nextLurch = Config.get("LURCH_FIRST")
	Game.lurch = nil
	Game.wobbleA = Game.rng:NextNumber(0, math.pi * 2)
	Game.quake = nil
	Game.maxTiltSeen = 0
	Game.chaosOn = true
	local rushSaid = false
	local shrinkIdx = 1
	local plan, planName = Game.shrinkPlan(Game.nReal or 0)
	local steps = (Workspace:GetAttribute("Cfg_NO_SHRINK") ~= true) and plan or nil
	if steps and planName == "duo" then
		notifyAll("PlanNote", { title = "DUEL!", sub = "Small plate soon. Push them off!" })
	end
	local _, _, _, totalReal = aliveCounts()
	Game.participantsAtStart = #Game.participants
	local lastOneAt = nil -- when the plate got down to one body
	local endReason = "time"
	local realOutAt = nil -- when the last real player fell (ghost time starts)
	while true do
		task.wait(0.1)
		if Game.stopLoop then
			endReason = "stopped"
			break
		end
		local elapsed = os.clock() - t0
		if elapsed >= roundTime then
			break
		end
		if Game.onRoundTick and Workspace:GetAttribute("Cfg_NO_CHAOS") ~= true and Config.get("FIRST_EVENT_AT") < 900 then
			Game.onRoundTick(elapsed)
		end
		if elapsed >= nextEvent then
			Game.spawnEvent(elapsed)
			local gap = TiltMath.lerp(Config.get("EVENT_GAP_START"), Config.get("EVENT_GAP_END"), elapsed / roundTime)
			nextEvent += gap * Game.rng:NextNumber(0.85, 1.15)
		end
		if elapsed >= nextQuake and Config.get("FIRST_EVENT_AT") < 900 and Workspace:GetAttribute("Cfg_NO_CHAOS") ~= true then
			nextQuake += Config.get("QUAKE_GAP") * Game.rng:NextNumber(0.8, 1.2)
			if roundTime - elapsed > Config.get("QUAKE_WARN") + Config.get("QUAKE_TIME") then
				Game.startQuake()
			end
		end
		if elapsed >= nextLurch and Config.get("FIRST_EVENT_AT") < 900 and Workspace:GetAttribute("Cfg_NO_CHAOS") ~= true then
			local gap = TiltMath.lerp(Config.get("LURCH_GAP_START"), Config.get("LURCH_GAP_END"), elapsed / roundTime)
			if elapsed >= roundTime - Config.get("FINAL_RUSH") or Config.get("MOD_DOUBLE") == true then
				gap *= 0.6 -- final rush / WILD twist: lurches come much faster
			end
			nextLurch = elapsed + gap * Game.rng:NextNumber(0.8, 1.2)
			local q = Game.quake
			local busy = q ~= nil and os.clock() < q.t1 + 0.3
			if not busy and roundTime - elapsed > Config.get("LURCH_WARN") + Config.get("LURCH_TIME") then
				Game.startLurch()
			end
		end
		local st = steps and steps[shrinkIdx]
		if st and elapsed >= st.at * roundTime - Config.get("SHRINK_WARN") then
			shrinkIdx += 1
			task.spawn(Game.shrinkTo, st.r, Config.get("SHRINK_WARN"))
		end
		if not rushSaid and elapsed >= roundTime - Config.get("FINAL_RUSH") then
			rushSaid = true
			notifyAll("FinalRush", {})
			Sfx.play("airhorn", nil, 0.5)
		end
		local alive, _, aliveReal = aliveCounts()
		-- someone who just fell can still take a Second Chance: keep the round alive for them
		local hold = Game.reviveHold ~= nil and Game.reviveHold() == true
		if alive == 0 and not hold then
			endReason = "all fell"
			break
		end
		-- LAST ONE STANDING (sir Oct 16): once only one body is left on the plate the round is won - they don't
		-- have to survive the tilt alone. Needs 2+ at the start (a solo round can't end at once) and waits a beat.
		if alive == 1 and Game.participantsAtStart and Game.participantsAtStart >= 2 and not hold then
			lastOneAt = lastOneAt or elapsed
			if elapsed - lastOneAt >= Config.get("LAST_ONE_DELAY") then
				endReason = "last one"
				break
			end
		else
			lastOneAt = nil
		end
		if totalReal > 0 and aliveReal == 0 and not hold then
			-- every real player fell, only bots left: don't end at once (the fallen are ghosts now and get to
			-- drop junk on the bots), but don't make them wait the whole round either
			realOutAt = realOutAt or elapsed
			if elapsed - realOutAt >= Config.get("GHOST_GRACE") then
				endReason = "players fell"
				break
			end
		elseif aliveReal > 0 then
			realOutAt = nil -- revived
		end
	end
	Game.chaosOn = false
	Game.quake = nil
	Game.lurch = nil
	logEvent("round end " .. endReason)
	Game.lastEndReason = endReason
	return endReason
end

function Game.results()
	local winners = {}
	local endClock = os.clock()
	for _, rec in ipairs(Game.participants) do
		if rec.alive then
			rec.aliveTime = (rec.aliveTime or 0) + (endClock - (rec.aliveSince or endClock))
		end
	end
	if Game.onResults then
		pcall(Game.onResults, Game.participants)
	end
	for _, rec in ipairs(Game.participants) do
		if rec.alive then
			if rec.kind == "player" then
				table.insert(winners, rec.player.DisplayName)
				addWin(rec.player)
			else
				table.insert(winners, rec.bot.name)
				Bots.cheer(rec.bot)
				Bots.stopMoving(rec.bot)
			end
		end
	end
	local lastOne = Game.lastEndReason == "last one"
	for _, rec in ipairs(Game.participants) do
		if rec.kind == "player" then
			notify(rec.player, "Result", { survived = rec.alive, winners = winners, streak = rec.streak, streakBonus = rec.streakBonus, lostStreak = rec.lostStreak, lastOne = lastOne })
		end
	end
	-- spectators in the lobby see the winners too
	for _, p in ipairs(Players:GetPlayers()) do
		local inRound = false
		for _, rec in ipairs(Game.participants) do
			if rec.player == p then
				inRound = true
				break
			end
		end
		if not inRound then
			notify(p, "Result", { spectator = true, winners = winners })
		end
	end
	logEvent("winners " .. #winners)
	Game.setPhase("Results", Config.get("RESULTS_TIME"))
	-- winners celebrate in place: freeze them so nobody walks off while the plate swings back level
	for _, rec in ipairs(Game.participants) do
		if rec.alive and rec.model and rec.model.Parent then
			setFrozen(rec.model:FindFirstChildOfClass("Humanoid"), true, rec.kind == "bot")
		end
	end
	task.wait(Config.get("RESULTS_TIME"))
	-- back to the lobby
	for _, rec in ipairs(Game.participants) do
		if rec.model and rec.model.Parent then
			setFrozen(rec.model:FindFirstChildOfClass("Humanoid"), false, rec.kind == "bot")
			if rec.alive or not rec.sent then
				sendToLobby(rec.model, rec.player)
			end
		end
		if rec.kind == "bot" then
			Bots.stopMoving(rec.bot)
		end
	end
	if Game.onRoundOver then
		pcall(Game.onRoundOver, Game.participants)
	end
	Game.participants = {}
	publishCounts()
	Game.clearObjects(true)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(saveStats, p.UserId)
	end
	return winners
end

function Game.loop()
	local first = true
	while not Game.stopLoop do
		if not Game.canStart() then
			Game.setPhase("Waiting", 0)
			repeat
				task.wait(0.5)
			until Game.canStart() or Game.stopLoop
			first = true
		end
		if Game.stopLoop then
			break
		end
		local inter = first and Config.get("FIRST_INTERMISSION") or Config.get("INTERMISSION")
		first = false
		Game.setPhase("Intermission", inter)
		task.wait(inter)
		if not Game.canStart() then
			continue
		end
		Game.startRound()
		Game.setPhase("Countdown", Config.get("COUNTDOWN"))
		notifyAll("Countdown", { seconds = Config.get("COUNTDOWN") })
		task.wait(Config.get("COUNTDOWN"))
		Game.unfreezeAll()
		Game.setPhase("Round", Config.get("ROUND_TIME"))
		notifyAll("Go", {})
		Game.runRound()
		Game.results()
	end
	Game.setPhase("Stopped", 0)
end

---------------------------------------------------------------- players
local function onCharacter(player: Player, ch: Model)
	local hum = ch:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	hum.WalkSpeed = Config.get("WALK_SPEED")
	-- a respawned character is never part of the running round
	for _, rec in ipairs(Game.participants) do
		if rec.player == player and rec.model ~= ch then
			if rec.alive then
				markOut(rec, "respawn")
			end
			rec.sent = true
		end
	end
	if Game.onCharacter then
		pcall(Game.onCharacter, player, ch)
	end
end

function Game.start()
	if Game.started then
		return
	end
	Game.started = true
	Game.setupRemotes()
	Game.remotes:WaitForChild("Shove").OnServerEvent:Connect(function(player: Player)
		local rec = Game.recFor(player)
		if rec then
			Game.tryShove(rec)
		end
	end)
	Game.remotes:WaitForChild("Dodge").OnServerEvent:Connect(function(player: Player, dir)
		local rec = Game.recFor(player)
		if rec then
			local ok = Game.tryDodge(rec, typeof(dir) == "Vector3" and dir or nil)
			if not ok then
				local left = math.max(0, Config.get("DODGE_COOLDOWN") - (os.clock() - (Game.dodgeAt[player] or -math.huge)))
				notify(player, "DodgeCd", { cd = left })
			end
		end
	end)
	Sfx.init()
	pcall(function()
		local PhysicsService = game:GetService("PhysicsService")
		if not PhysicsService:IsCollisionGroupRegistered("TiltObjects") then
			PhysicsService:RegisterCollisionGroup("TiltObjects")
		end
		PhysicsService:CollisionGroupSetCollidable("TiltObjects", "TiltObjects", false)
	end)
	Map.build()
	Players.RespawnTime = 2
	Data.start()
	Data.onChanged(Game.refreshStats)
	local function joined(p: Player)
		makeLeaderstats(p)
		p.CharacterAdded:Connect(function(ch)
			onCharacter(p, ch)
		end)
		if p.Character then
			task.spawn(onCharacter, p, p.Character)
		end
		task.spawn(function()
			local prof = Data.load(p)
			Game.refreshStats(prof)
			if Game.onProfileLoaded then
				pcall(Game.onProfileLoaded, prof)
			end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		joined(p)
	end
	Players.PlayerAdded:Connect(joined)
	Players.PlayerRemoving:Connect(function(p)
		for _, rec in ipairs(Game.participants) do
			if rec.player == p and rec.alive then
				markOut(rec, "left")
				rec.sent = true
			end
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(Game.step, dt)
		if not ok then
			warn("[Tilt] step error: " .. tostring(err))
		end
	end)
end

return Game
