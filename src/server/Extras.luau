-- Extras: the "more fun" layer on top of the core round (sir Oct 15: "add everything"):
--   * Round twists: ICE, LOW GRAVITY, GIANTS, DOUBLE DROPS, NIGHT, BOUNCY (one random twist most rounds)
--   * KOs: push someone and they fall = +1 KO (+coins), kill feed "X knocked Y off", TOP KOs board
--   * Crown: last round's winner wears it; push the holder off to steal it (+coins)
--   * Pickups on the plate: Banana (slip), Boots (can't be pushed), Spring (big jump)
--   * Ghosts: fallen players float above the plate and drop junk on the ones still standing
-- Server only. Call Extras.start() after Shop.start() and Rewards.start() (it wraps their hooks).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))
local Game = require(script.Parent:WaitForChild("Game"))
local Data = require(script.Parent:WaitForChild("Data"))
local Map = require(script.Parent:WaitForChild("Map"))

local Extras = {}
Extras.rng = Random.new()
Extras.roundsSeen = 0
Extras.mod = nil :: string?

local function nameOf(rec): string
	if not rec then
		return "?"
	end
	return rec.kind == "player" and rec.player.DisplayName or (rec.bot and rec.bot.name) or "?"
end

local function rootOf(rec): BasePart?
	return Game.recRoot(rec)
end

local function shopPublish(p)
	local Shop = require(script.Parent:WaitForChild("Shop"))
	Shop.publish(p)
end

---------------------------------------------------------------- round twists
Extras.MODS = {
	ICE = { title = "ICE PLATE", sub = "Everything slides more!" },
	LOWGRAV = { title = "LOW GRAVITY", sub = "Floaty jumps and floaty pushes" },
	GIANTS = { title = "GIANTS", sub = "Everyone is HUGE" },
	DOUBLE = { title = "WILD PLATE", sub = "It lurches way more often!" },
	NIGHT = { title = "NIGHT", sub = "Stay in the light" },
	BOUNCY = { title = "BOUNCY", sub = "Super jumps, big pushes" },
}
Extras.MOD_ORDER = { "ICE", "LOWGRAV", "GIANTS", "DOUBLE", "NIGHT", "BOUNCY" }

local setAttrs = {} :: { string }
local function cfg(key: string, v: any)
	Workspace:SetAttribute("Cfg_" .. key, v)
	table.insert(setAttrs, key)
end

local saved = {} :: { [string]: any }
local spot: BasePart? = nil

local function plateParts(): { BasePart }
	local list = {}
	local model = Map.plateModel
	if model then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "Surface" or d.Name == "RingSeg") then
				table.insert(list, d)
			end
		end
	end
	return list
end

function Extras.applyMod(key: string, participants)
	Extras.clearMod(participants)
	local m = Extras.MODS[key]
	if not m then
		return
	end
	Extras.mod = key
	ReplicatedStorage:SetAttribute("Mod", key)
	ReplicatedStorage:SetAttribute("ModTitle", m.title)
	ReplicatedStorage:SetAttribute("ModSub", m.sub)
	Game.notifyAll("Mod", { key = key, title = m.title, sub = m.sub })
	if key == "ICE" then
		cfg("SLIDE_K", 34)
		cfg("SLIDE_DEADZONE", 2)
		cfg("SLIDE_MAX", 14)
		for _, p in ipairs(plateParts()) do
			p:SetAttribute("IceColor", p.Color)
			p:SetAttribute("IceMat", p.Material.Name)
			p.Color = Color3.fromRGB(196, 222, 240)
			p.Material = Enum.Material.Ice
			if p:GetAttribute("BaseColor") then
				p:SetAttribute("BaseColor", p.Color)
			end
		end
	elseif key == "LOWGRAV" then
		saved.gravity = Workspace.Gravity
		Workspace.Gravity = 70
	elseif key == "GIANTS" then
		cfg("SHOVE_RANGE", Config.SHOVE_RANGE * 1.4)
		for _, rec in ipairs(participants or {}) do
			if rec.model and rec.model.Parent then
				pcall(function()
					rec.model:ScaleTo(1.5)
				end)
				rec.giant = true
			end
		end
	elseif key == "DOUBLE" then
		cfg("MOD_DOUBLE", true)
	elseif key == "NIGHT" then
		saved.clock = Lighting.ClockTime
		saved.bright = Lighting.Brightness
		saved.amb = Lighting.Ambient
		saved.oamb = Lighting.OutdoorAmbient
		Lighting.ClockTime = 0.3
		Lighting.Brightness = 0.4
		Lighting.Ambient = Color3.fromRGB(26, 28, 40)
		Lighting.OutdoorAmbient = Color3.fromRGB(40, 44, 62)
		local p = Instance.new("Part")
		p.Name = "NightSpot"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(1, 1, 1)
		p.CFrame = CFrame.new(0, Config.PLATE_Y + 70, 0)
		p.Parent = Map.world
		local l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Bottom
		l.Angle = 60
		l.Range = 120
		l.Brightness = 8
		l.Color = Color3.fromRGB(255, 244, 220)
		l.Shadows = true
		l.Parent = p
		spot = p
	elseif key == "BOUNCY" then
		cfg("JUMP_HEIGHT", 18)
		cfg("SHOVE_UP", 30)
	end
	Game.logEvent("mod " .. key)
end

function Extras.clearMod(participants)
	for _, k in ipairs(setAttrs) do
		Workspace:SetAttribute("Cfg_" .. k, nil)
	end
	table.clear(setAttrs)
	for _, p in ipairs(plateParts()) do
		local c = p:GetAttribute("IceColor")
		if c then
			p.Color = c
			if p:GetAttribute("BaseColor") then
				p:SetAttribute("BaseColor", c)
			end
			pcall(function()
				p.Material = Enum.Material[p:GetAttribute("IceMat")]
			end)
			p:SetAttribute("IceColor", nil)
			p:SetAttribute("IceMat", nil)
		end
	end
	if saved.gravity then
		Workspace.Gravity = saved.gravity
		saved.gravity = nil
	end
	if saved.clock then
		Lighting.ClockTime = saved.clock
		Lighting.Brightness = saved.bright
		Lighting.Ambient = saved.amb
		Lighting.OutdoorAmbient = saved.oamb
		saved.clock = nil
	end
	if spot then
		spot:Destroy()
		spot = nil
	end
	for _, rec in ipairs(participants or {}) do
		if rec.giant then
			rec.giant = nil
			if rec.model and rec.model.Parent then
				pcall(function()
					rec.model:ScaleTo(1)
				end)
			end
		end
		-- jump back to normal (BOUNCY) for anyone still around
		local hum = rec.model and rec.model.Parent and rec.model:FindFirstChildOfClass("Humanoid")
		if hum and hum.WalkSpeed > 0 then
			Game.setFrozen(hum, false, rec.kind == "bot")
		end
	end
	Extras.mod = nil
	ReplicatedStorage:SetAttribute("Mod", nil)
	ReplicatedStorage:SetAttribute("ModTitle", nil)
	ReplicatedStorage:SetAttribute("ModSub", nil)
end

function Extras.pickMod(): string?
	Extras.roundsSeen += 1
	if Extras.roundsSeen <= 1 or Extras.rng:NextNumber() > Config.get("MOD_CHANCE") then
		return nil
	end
	-- never the same twist twice in a row
	local options = {}
	for _, k in ipairs(Extras.MOD_ORDER) do
		if k ~= Extras.lastMod then
			table.insert(options, k)
		end
	end
	local k = options[Extras.rng:NextInteger(1, #options)]
	Extras.lastMod = k
	return k
end

---------------------------------------------------------------- crown
Extras.crown = nil :: { userId: number?, bot: any? }?

local function crownKeyOf(rec)
	if rec.kind == "player" then
		return { userId = rec.player.UserId }
	end
	return { bot = rec.bot }
end

local function holds(rec, key): boolean
	if not key then
		return false
	end
	if rec.kind == "player" then
		return key.userId ~= nil and rec.player.UserId == key.userId
	end
	return key.bot ~= nil and rec.bot == key.bot
end

local function removeCrownModel(rec)
	if rec and rec.model then
		local c = rec.model:FindFirstChild("TiltCrown")
		if c then
			c:Destroy()
		end
	end
end

local function putCrown(rec)
	if not rec or not rec.model or not rec.model.Parent then
		return
	end
	removeCrownModel(rec)
	local head = rec.model:FindFirstChild("Head") or rootOf(rec)
	if not head or not head:IsA("BasePart") then
		return
	end
	local m = Instance.new("Model")
	m.Name = "TiltCrown"
	local gold = Map.COLORS.gold
	local function cp(size: Vector3, cf: CFrame)
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = cf
		p.Color = gold
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.03
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		local w = Instance.new("WeldConstraint")
		w.Part0 = head
		w.Part1 = p
		w.Parent = p
		return p
	end
	local top = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.25, 0)
	local band = cp(Vector3.new(0.4, 1.7, 1.7), top * CFrame.Angles(0, 0, math.pi / 2))
	band.Shape = Enum.PartType.Cylinder
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		cp(Vector3.new(0.3, 0.6, 0.3), top * CFrame.new(math.cos(a) * 0.7, 0.45, math.sin(a) * 0.7) * CFrame.Angles(0, -a, math.rad(10)))
	end
	m.Parent = rec.model
end

function Extras.giveCrown(rec, why: string?)
	for _, other in ipairs(Game.participants) do
		removeCrownModel(other)
		other.crowned = nil
	end
	if not rec then
		Extras.crown = nil
		return
	end
	Extras.crown = crownKeyOf(rec)
	rec.crowned = true
	putCrown(rec)
	Game.logEvent("crown " .. nameOf(rec) .. " " .. (why or ""))
end

---------------------------------------------------------------- KOs
function Extras.onKO(byRec, victim)
	Game.logEvent("ko " .. nameOf(byRec) .. " -> " .. nameOf(victim))
	if byRec.kind == "player" then
		local p = Data.get(byRec.player)
		if p then
			p.d.KOs = (p.d.KOs or 0) + 1
			p.d.Coins += Config.get("KO_COINS")
			Data.changed(p)
			Game.refreshStats(p)
			shopPublish(p)
		end
		Game.notify(byRec.player, "KO", { to = nameOf(victim), coins = Config.get("KO_COINS") })
	end
	-- pushed the crown holder off: steal the crown
	if victim.crowned and (byRec.alive ~= false) then
		Extras.giveCrown(byRec, "stolen")
		local bonus = Config.get("CROWN_STEAL_COINS")
		if byRec.kind == "player" then
			local p = Data.get(byRec.player)
			if p then
				p.d.Coins += bonus
				Data.changed(p)
				shopPublish(p)
			end
		end
		Game.notifyAll("CrownSteal", { by = nameOf(byRec), from = nameOf(victim), byId = byRec.kind == "player" and byRec.player.UserId or 0, coins = bonus })
		Sfx.play("vineBoom", rootOf(byRec), 0.5)
	end
end

---------------------------------------------------------------- pickups
Extras.PICKUPS = { "Banana", "Boots", "Spring" }
Extras.pickups = {} :: { { kind: string, model: Model, root: BasePart, born: number } }

local function pickupFolder(): Folder?
	local world = Map.world
	if not world then
		return nil
	end
	local f = world:FindFirstChild("Pickups")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Pickups"
		f.Parent = world
	end
	return f :: Folder
end

local function buildPickup(kind: string): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "Pickup_" .. kind
	local function pp(props)
		local p = Instance.new("Part")
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		for k, v in pairs(props) do
			(p :: any)[k] = v
		end
		p.Parent = m
		return p
	end
	local root = pp({ Name = "Root", Size = Vector3.new(2.6, 0.3, 2.6), Transparency = 1 })
	-- soft gold disc under every pickup so it reads as "grab me"
	pp({
		Name = "Glow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 3.4, 3.4),
		CFrame = root.CFrame * CFrame.Angles(0, 0, math.pi / 2),
		Color = Map.COLORS.gold,
		Transparency = 0.35,
	})
	if kind == "Banana" then
		local y = Color3.fromRGB(236, 206, 72)
		for i = -1, 1 do
			pp({
				Name = "Peel",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.3, 0.7, 0.7),
				CFrame = root.CFrame * CFrame.new(i * 0.95, 0.5 + math.abs(i) * 0.25, 0) * CFrame.Angles(0, 0, -i * 0.5),
				Color = y,
			})
		end
	elseif kind == "Boots" then
		local c = Color3.fromRGB(70, 70, 76)
		for _, x in ipairs({ -0.6, 0.6 }) do
			pp({ Name = "Boot", Size = Vector3.new(0.9, 1.3, 0.9), CFrame = root.CFrame * CFrame.new(x, 0.8, -0.25), Color = c })
			pp({ Name = "Toe", Size = Vector3.new(0.9, 0.6, 1.5), CFrame = root.CFrame * CFrame.new(x, 0.45, 0.2), Color = c })
		end
	else -- Spring
		for i = 0, 3 do
			pp({
				Name = "Coil",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.18, 1.5, 1.5),
				CFrame = root.CFrame * CFrame.new(0, 0.35 + i * 0.32, 0) * CFrame.Angles(0, 0, math.pi / 2),
				Color = Color3.fromRGB(190, 192, 198),
			})
		end
		pp({
			Name = "Pad",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.25, 1.8, 1.8),
			CFrame = root.CFrame * CFrame.new(0, 1.65, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(220, 80, 70),
		})
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
		end
	end
	m.PrimaryPart = root
	return m, root
end

function Extras.spawnPickup(kind: string?, lx: number?, lz: number?)
	local core = Map.plateCore
	local folder = pickupFolder()
	if not core or not folder then
		return nil
	end
	kind = kind or Extras.PICKUPS[Extras.rng:NextInteger(1, #Extras.PICKUPS)]
	local R = (Game.safeR or Config.PLATE_RADIUS) - 6
	if not lx or not lz then
		local a = Extras.rng:NextNumber(0, math.pi * 2)
		local r = Extras.rng:NextNumber(6, math.max(8, R))
		lx, lz = math.cos(a) * r, math.sin(a) * r
	end
	local m, root = buildPickup(kind :: string)
	m:PivotTo(core.CFrame * CFrame.new(lx :: number, Config.PLATE_THICK / 2 + 0.2, lz :: number))
	local w = Instance.new("WeldConstraint")
	w.Part0 = core
	w.Part1 = root
	w.Parent = root
	m.Parent = folder
	local rec = { kind = kind :: string, model = m, root = root, born = os.clock() }
	table.insert(Extras.pickups, rec)
	Sfx.play("pop", root, 0.5)
	Game.logEvent("pickup " .. kind)
	return rec
end

function Extras.clearPickups()
	for _, p in ipairs(Extras.pickups) do
		if p.model.Parent then
			p.model:Destroy()
		end
	end
	table.clear(Extras.pickups)
	local f = Map.world and Map.world:FindFirstChild("Pickups")
	if f then
		f:ClearAllChildren()
	end
end

function Extras.applyPickup(rec, kind: string)
	local root = rootOf(rec)
	if not root then
		return
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	if kind == "Banana" then
		local vel = look * 34 + Vector3.new(0, 6, 0)
		if rec.kind == "player" then
			Game.notify(rec.player, "Knock", { push = Vector3.new(0, 0.3, 0), vel = vel, label = "SLIPPED!", burst = 0.3, stun = 0.8 })
		else
			Game.burst(root, vel, 0.3)
			Game.knockDown(rec.model, 0.8)
		end
		Sfx.play("boing", root, 0.6)
	elseif kind == "Boots" then
		rec.heavyUntil = os.clock() + Config.get("BOOTS_TIME")
		local h = Instance.new("Highlight")
		h.Name = "HeavyBoots"
		h.FillTransparency = 1
		h.OutlineColor = Map.COLORS.gold
		h.OutlineTransparency = 0.2
		h.Parent = rec.model
		task.delay(Config.get("BOOTS_TIME"), function()
			h:Destroy()
		end)
		if rec.kind == "player" then
			Game.notify(rec.player, "Pickup", { title = "HEAVY BOOTS", sub = "Nobody can push you for " .. Config.get("BOOTS_TIME") .. " s" })
		end
		Sfx.play("metalPipe", root, 0.35)
	elseif kind == "Spring" then
		local vel = Vector3.new(0, Config.get("SPRING_UP"), 0) + look * 8
		if rec.kind == "player" then
			Game.notify(rec.player, "Knock", { push = Vector3.new(0, 0.5, 0), vel = vel, label = "BOING!", burst = 0.18 })
		else
			Game.burst(root, vel, 0.18)
		end
		Sfx.play("boing", root, 0.8)
	end
	Game.notifyAll("PickupUsed", { kind = kind, name = nameOf(rec) })
	Game.logEvent("pickup used " .. kind .. " by " .. nameOf(rec))
end

---------------------------------------------------------------- ghosts
Extras.ghostFloor = nil :: BasePart?
Extras.GHOST_Y = 40 -- above the plate top

local function ensureGroups()
	pcall(function()
		for _, g in ipairs({ "Ghosts", "GhostFloor" }) do
			if not PhysicsService:IsCollisionGroupRegistered(g) then
				PhysicsService:RegisterCollisionGroup(g)
			end
		end
		PhysicsService:CollisionGroupSetCollidable("GhostFloor", "Default", false)
		PhysicsService:CollisionGroupSetCollidable("GhostFloor", "TiltObjects", false)
		PhysicsService:CollisionGroupSetCollidable("Ghosts", "Default", false)
		PhysicsService:CollisionGroupSetCollidable("Ghosts", "TiltObjects", false)
		PhysicsService:CollisionGroupSetCollidable("Ghosts", "GhostFloor", true)
	end)
end

function Extras.buildGhostFloor()
	if Extras.ghostFloor and Extras.ghostFloor.Parent then
		return Extras.ghostFloor
	end
	local p = Instance.new("Part")
	p.Name = "GhostFloor"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(1, 120, 120)
	p.CFrame = CFrame.new(0, Config.PLATE_Y + Extras.GHOST_Y - 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2)
	p.Anchored = true
	p.Transparency = 1
	p.CanQuery = false
	p.CanTouch = false
	pcall(function()
		p.CollisionGroup = "GhostFloor"
	end)
	p.Parent = Map.world
	Extras.ghostFloor = p
	return p
end

local function setGhostLook(model: Model, on: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if on then
				if d:GetAttribute("GhostT") == nil then
					d:SetAttribute("GhostT", d.Transparency)
					d:SetAttribute("GhostG", d.CollisionGroup)
				end
				if d.Name ~= "HumanoidRootPart" then
					d.Transparency = math.max(d.Transparency, 0.55)
				end
				pcall(function()
					d.CollisionGroup = "Ghosts"
				end)
			elseif d:GetAttribute("GhostT") ~= nil then
				d.Transparency = d:GetAttribute("GhostT")
				pcall(function()
					d.CollisionGroup = d:GetAttribute("GhostG") or "Default"
				end)
				d:SetAttribute("GhostT", nil)
				d:SetAttribute("GhostG", nil)
			end
		elseif d:IsA("Decal") then
			if on then
				if d:GetAttribute("GhostT") == nil then
					d:SetAttribute("GhostT", d.Transparency)
				end
				d.Transparency = math.max(d.Transparency, 0.55)
			elseif d:GetAttribute("GhostT") ~= nil then
				d.Transparency = d:GetAttribute("GhostT")
				d:SetAttribute("GhostT", nil)
			end
		end
	end
end

function Extras.makeGhost(rec)
	if rec.kind ~= "player" or rec.ghost or not rec.model or not rec.model.Parent then
		return
	end
	if Game.phase ~= "Round" and not Game.forceBotRounds then
		return
	end
	Extras.buildGhostFloor()
	if rec.giant then
		pcall(function()
			rec.model:ScaleTo(1)
		end)
		rec.giant = nil
	end
	rec.ghost = true
	rec.player:SetAttribute("Ghost", true)
	rec.ghostDrops = 0
	rec.ghostNext = os.clock() + 1.5
	setGhostLook(rec.model, true)
	local a = Extras.rng:NextNumber(0, math.pi * 2)
	local pos = Vector3.new(math.cos(a) * 20, Config.PLATE_Y + Extras.GHOST_Y + 3, math.sin(a) * 20)
	pcall(function()
		rec.model:PivotTo(CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)))
		Game.zeroVelocity(rec.model)
	end)
	local hum = rec.model:FindFirstChildOfClass("Humanoid")
	if hum then
		Game.setFrozen(hum, false, false)
	end
	Game.notify(rec.player, "Ghost", { on = true, max = Config.get("GHOST_MAX"), cd = Config.get("GHOST_COOLDOWN") })
	Sfx.fire(rec.player, "ghostGiggle", nil, 1.4)
	Game.logEvent("ghost " .. nameOf(rec))
end

function Extras.unghost(rec, toLobby: boolean)
	if not rec.ghost then
		return
	end
	rec.ghost = nil
	if rec.player then
		rec.player:SetAttribute("Ghost", nil)
	end
	if rec.model and rec.model.Parent then
		setGhostLook(rec.model, false)
		if toLobby then
			Game.sendToLobby(rec.model, rec.player)
		end
	end
	if rec.player then
		Game.notify(rec.player, "Ghost", { on = false })
	end
end

-- a ghost asks to drop junk: it falls straight below them
function Extras.ghostDrop(rec): (boolean, string?)
	if not rec or not rec.ghost then
		return false, "not a ghost"
	end
	if Game.phase ~= "Round" and not Game.forceBotRounds then
		return false, "round over"
	end
	local now = os.clock()
	if now < (rec.ghostNext or 0) then
		return false, "cooldown"
	end
	if (rec.ghostDrops or 0) >= Config.get("GHOST_MAX") then
		return false, "no junk left"
	end
	local root = rootOf(rec)
	if not root then
		return false, "no body"
	end
	local lp = Game.plateLocal(root.Position)
	local r = math.sqrt(lp.X * lp.X + lp.Z * lp.Z)
	local maxR = (Game.safeR or Config.PLATE_RADIUS) - 4
	local x, z = lp.X, lp.Z
	if r > maxR then
		x, z = x * maxR / r, z * maxR / r
	end
	rec.ghostNext = now + Config.get("GHOST_COOLDOWN")
	rec.ghostDrops = (rec.ghostDrops or 0) + 1
	local kind = Extras.rng:NextNumber() < 0.5 and "Boot" or "Fish"
	Game.dropObject(kind, Vector3.new(x, 0, z), Config.get("GHOST_WARN"), "👻 " .. rec.player.DisplayName)
	Game.notify(rec.player, "GhostLeft", { left = Config.get("GHOST_MAX") - rec.ghostDrops, cd = Config.get("GHOST_COOLDOWN") })
	return true, nil
end

---------------------------------------------------------------- per-frame (from Game.step)
function Extras.step(dt: number, now: number, active: boolean)
	if not active then
		return
	end
	-- pickups: lifetime + whoever walks over one grabs it
	for i = #Extras.pickups, 1, -1 do
		local pk = Extras.pickups[i]
		if not pk.model.Parent or now - pk.born > Config.get("PICKUP_LIFE") then
			if pk.model.Parent then
				pk.model:Destroy()
			end
			table.remove(Extras.pickups, i)
			continue
		end
		local pos = pk.root.Position
		local lp = Game.plateLocal(pos)
		if math.sqrt(lp.X * lp.X + lp.Z * lp.Z) > (Game.plateR or Config.PLATE_RADIUS) then
			pk.model:Destroy()
			table.remove(Extras.pickups, i)
			continue
		end
		for _, rec in ipairs(Game.participants) do
			local r = rec.alive and not rec.ghost and rootOf(rec)
			local d = r and (r.Position - pos)
			if r and d and Vector3.new(d.X, 0, d.Z).Magnitude < 3.2 and d.Y > -2 and d.Y < 7 then
				pk.model:Destroy()
				table.remove(Extras.pickups, i)
				Extras.applyPickup(rec, pk.kind)
				break
			end
		end
	end
	-- ghosts that walked off their floor go back on it
	for _, rec in ipairs(Game.participants) do
		if rec.ghost then
			local r = rootOf(rec)
			if r and r.Position.Y < Config.PLATE_Y + Extras.GHOST_Y - 12 then
				pcall(function()
					rec.model:PivotTo(CFrame.new(0, Config.PLATE_Y + Extras.GHOST_Y + 3, 0))
					Game.zeroVelocity(rec.model)
				end)
			end
		end
	end
	-- night: the spotlight sweeps slowly around the plate
	if spot then
		local a = now * 0.35
		spot.CFrame = CFrame.new(math.cos(a) * 18, Config.PLATE_Y + 70, math.sin(a) * 18)
	end
end

-- the round loop also drops pickups now and then
function Extras.roundTick(elapsed: number)
	if elapsed >= (Extras.nextPickup or math.huge) then
		Extras.nextPickup = elapsed + Config.get("PICKUP_GAP") * Extras.rng:NextNumber(0.75, 1.25)
		if #Extras.pickups < Config.get("PICKUP_MAX") then
			Extras.spawnPickup()
		end
	end
end

---------------------------------------------------------------- hooks
local G = Game :: any
local function chain(name: string, fn)
	local prev = G[name]
	G[name] = function(...)
		if prev then
			prev(...)
		end
		fn(...)
	end
end

function Extras.start()
	ensureGroups()
	chain("onRoundStart", function(participants)
		Extras.clearPickups()
		Extras.nextPickup = Config.get("PICKUP_FIRST")
		-- crown: last round's winner wears it
		for _, rec in ipairs(participants) do
			if holds(rec, Extras.crown) then
				rec.crowned = true
				task.defer(putCrown, rec)
			end
		end
		-- twist (real rounds only; SelfTest drives them directly)
		if not Game.forceBotRounds then
			local k = Extras.pickMod()
			if k then
				Extras.applyMod(k, participants)
			end
		end
	end)
	chain("onFell", function(rec, _why)
		if rec.crowned then
			-- fell without being pushed: the crown is up for grabs (winners of this round get it)
			task.defer(function()
				if rec.crowned then
					rec.crowned = nil
					removeCrownModel(rec)
					Game.notifyAll("CrownLost", { name = nameOf(rec) })
				end
			end)
		end
	end)
	chain("onSent", function(rec)
		Extras.makeGhost(rec)
	end)
	chain("onRevived", function(rec)
		Extras.unghost(rec, false)
	end)
	chain("onResults", function(participants)
		-- crown: kept by a surviving holder (+coins), else goes to the survivor who lasted longest
		local holder, best = nil, nil
		for _, rec in ipairs(participants) do
			if rec.alive then
				if rec.crowned then
					holder = rec
				end
				if not best or (rec.aliveTime or 0) > (best.aliveTime or 0) then
					best = rec
				end
			end
		end
		if holder then
			if holder.kind == "player" then
				local p = Data.get(holder.player)
				if p then
					p.d.Coins += Config.get("CROWN_KEEP_COINS")
					Data.changed(p)
					shopPublish(p)
				end
			end
			Extras.crown = crownKeyOf(holder)
			Game.notifyAll("CrownKept", { name = nameOf(holder) })
		elseif best then
			Extras.giveCrown(best, "winner")
			Game.notifyAll("CrownNew", { name = nameOf(best) })
		else
			Extras.giveCrown(nil)
		end
	end)
	chain("onRoundOver", function(participants)
		for _, rec in ipairs(participants) do
			if rec.ghost then
				Extras.unghost(rec, true)
			end
			removeCrownModel(rec)
		end
		Extras.clearMod(participants)
		Extras.clearPickups()
	end)
	Game.onKO = Extras.onKO
	Game.onStep = Extras.step
	Game.onRoundTick = Extras.roundTick
	local remote = Game.remotes and Game.remotes:FindFirstChild("Ghost")
	if remote then
		remote.OnServerEvent:Connect(function(plr: Player)
			local rec = Game.recFor(plr)
			if rec then
				local ok, why = Extras.ghostDrop(rec)
				if not ok and why == "cooldown" then
					Game.notify(plr, "GhostLeft", { cd = math.max(0, (rec.ghostNext or 0) - os.clock()), left = Config.get("GHOST_MAX") - (rec.ghostDrops or 0) })
				end
			end
		end)
	end
end

return Extras
