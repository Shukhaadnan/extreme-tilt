-- Objects: the things that fall onto the plate. Every object is a small welded Model built from parts (no assets,
-- so nothing can fail to load). Attributes on the model: Weight (tilt weight), Label, Kind.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))

local Objects = {}

-- weight = tilt weight (players weigh 1). chance = relative pick chance. min = earliest round second it may appear.
Objects.KINDS = {
	{ kind = "Watermelon", label = "A WATERMELON", weight = 1.5, chance = 10, min = 0 },
	{ kind = "Cake", label = "A GIANT CAKE", weight = 2, chance = 9, min = 0 },
	{ kind = "Duck", label = "A RUBBER DUCK", weight = 2, chance = 8, min = 0 },
	{ kind = "Anvil", label = "AN ANVIL", weight = 3, chance = 7, min = 10 },
	{ kind = "Cow", label = "A COW", weight = 3.5, chance = 7, min = 15 },
	{ kind = "Piano", label = "A PIANO", weight = 4, chance = 5, min = 25 },
	{ kind = "Meteor", label = "A METEOR", weight = 4.5, chance = 3, min = 40 },
	-- ghost junk (never picked by random events: chance 0)
	{ kind = "Boot", label = "A BOOT", weight = 1.2, chance = 0, min = 0 },
	{ kind = "Fish", label = "A FISH", weight = 1, chance = 0, min = 0 },
}

local function P(model: Model, props): Part
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = model
	return p
end

-- weld every part to the root; only the root collides (an invisible-or-visible BOX hull, never a ball, so nothing
-- rolls) with very high friction so objects stay where they land even at max tilt (tan(32 deg) < 1.5)
local function finish(model: Model, root: BasePart, kindInfo)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
		end
	end
	root.CanCollide = true
	root.CanTouch = false
	pcall(function()
		root.CollisionGroup = "TiltObjects"
	end)
	root.CustomPhysicalProperties = PhysicalProperties.new(0.35, 1.5, 0.1, 100, 1)
	model.PrimaryPart = root
	model.Name = kindInfo.kind
	model:SetAttribute("Weight", kindInfo.weight)
	model:SetAttribute("Label", kindInfo.label)
	model:SetAttribute("Kind", kindInfo.kind)
	return model
end

local B = {}

function B.Watermelon(m: Model)
	local root = P(m, { Name = "Root", Size = Vector3.new(4.4, 4.6, 4.4), Transparency = 1 })
	P(m, { Name = "Melon", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), CFrame = root.CFrame, Color = Color3.fromRGB(60, 160, 70) })
	for i = 0, 5 do
		local a = i * math.pi / 3
		P(m, {
			Name = "Stripe",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, 5.05, 5.05),
			CFrame = root.CFrame * CFrame.Angles(0, a, 0),
			Color = Color3.fromRGB(30, 110, 45),
			Transparency = 0.1,
		})
	end
	P(m, { Name = "Stem", Size = Vector3.new(0.3, 0.8, 0.3), CFrame = root.CFrame * CFrame.new(0, 2.7, 0), Color = Color3.fromRGB(110, 80, 40) })
	return root
end

function B.Cake(m: Model)
	local root = P(m, { Name = "Root", Size = Vector3.new(8, 5.4, 8), Transparency = 1 })
	local cf = root.CFrame
	local function layer(r, h, y, col)
		P(m, {
			Name = "Layer",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h, r * 2, r * 2),
			CFrame = cf * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = col,
		})
	end
	layer(4, 2.2, -1.6, Color3.fromRGB(92, 58, 40))
	layer(4.1, 0.4, -0.4, Color3.fromRGB(248, 244, 236))
	layer(3, 1.8, 0.7, Color3.fromRGB(92, 58, 40))
	layer(3.1, 0.35, 1.7, Color3.fromRGB(255, 255, 255))
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		P(m, {
			Name = "Candle",
			Size = Vector3.new(0.35, 1, 0.35),
			CFrame = cf * CFrame.new(math.cos(a) * 1.8, 2.3, math.sin(a) * 1.8),
			Color = Color3.fromRGB(248, 244, 236),
		})
		P(m, {
			Name = "Flame",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.4, 0.4, 0.4),
			CFrame = cf * CFrame.new(math.cos(a) * 1.8, 3, math.sin(a) * 1.8),
			Color = Color3.fromRGB(255, 200, 60),
			Material = Enum.Material.Neon,
		})
	end
	P(m, { Name = "Cherry", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1), CFrame = cf * CFrame.new(0, 2.4, 0), Color = Color3.fromRGB(220, 30, 50) })
	return root
end

function B.Duck(m: Model)
	local root = P(m, { Name = "Root", Size = Vector3.new(6, 6, 7.5), Transparency = 1 })
	local cf = root.CFrame
	local yellow = Color3.fromRGB(255, 214, 40)
	P(m, { Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 4.6, 7.4), CFrame = cf * CFrame.new(0, -0.6, 0.3), Color = yellow })
	P(m, { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(3.6, 3.6, 3.6), CFrame = cf * CFrame.new(0, 1.8, -1.9), Color = yellow })
	P(m, { Name = "Beak", Size = Vector3.new(1.6, 0.6, 1.6), CFrame = cf * CFrame.new(0, 1.5, -3.8), Color = Color3.fromRGB(255, 130, 30) })
	for _, x in ipairs({ -1, 1 }) do
		P(m, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = cf * CFrame.new(x * 0.9, 2.3, -3.5), Color = Color3.fromRGB(20, 20, 20) })
	end
	P(m, { Name = "Tail", Size = Vector3.new(1.6, 1.4, 1.2), CFrame = cf * CFrame.new(0, 0.6, 3.6) * CFrame.Angles(math.rad(30), 0, 0), Color = yellow })
	return root
end

function B.Anvil(m: Model)
	local root = P(m, { Name = "Root", Size = Vector3.new(7, 4.4, 3.4), Transparency = 1 })
	local cf = root.CFrame
	local metal = Color3.fromRGB(70, 74, 84)
	P(m, { Name = "Base", Size = Vector3.new(4.4, 1.2, 3.2), CFrame = cf * CFrame.new(0, -1.6, 0), Color = metal, Material = Enum.Material.Metal })
	P(m, { Name = "Waist", Size = Vector3.new(2.4, 1.8, 2.2), CFrame = cf * CFrame.new(0, -0.1, 0), Color = metal, Material = Enum.Material.Metal })
	P(m, { Name = "Top", Size = Vector3.new(5.6, 1.4, 3.2), CFrame = cf * CFrame.new(-0.3, 1.5, 0), Color = metal, Material = Enum.Material.Metal })
	P(m, {
		Name = "Horn",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.2, 1.3, 1.3),
		CFrame = cf * CFrame.new(3.2, 1.6, 0),
		Color = metal,
		Material = Enum.Material.Metal,
	})
	P(m, { Name = "Label", Size = Vector3.new(2.6, 0.9, 0.1), CFrame = cf * CFrame.new(-0.3, 1.5, -1.62), Color = Color3.fromRGB(255, 255, 255) })
	return root
end

function B.Cow(m: Model)
	local root = P(m, { Name = "Root", Size = Vector3.new(4.4, 6.6, 9), Transparency = 1 })
	local cf = root.CFrame
	local white = Color3.fromRGB(250, 250, 250)
	local black = Color3.fromRGB(30, 30, 34)
	local pink = Color3.fromRGB(255, 170, 180)
	P(m, { Name = "Body", Size = Vector3.new(4.2, 3.6, 7), CFrame = cf * CFrame.new(0, 0.4, 0.5), Color = white })
	for _, s in ipairs({ { 2.11, 0.8, -0.6, 0.1, 1.6, 2 }, { -2.11, 0.2, 1.8, 0.1, 1.8, 2.4 }, { 0.6, 2.21, 1.2, 2, 0.1, 2.2 } }) do
		P(m, { Name = "Spot", Size = Vector3.new(s[4], s[5], s[6]), CFrame = cf * CFrame.new(s[1], s[2], s[3]), Color = black })
	end
	P(m, { Name = "Head", Size = Vector3.new(2.8, 2.6, 2.6), CFrame = cf * CFrame.new(0, 1.6, -4), Color = white })
	P(m, { Name = "Snout", Size = Vector3.new(2.6, 1.3, 0.8), CFrame = cf * CFrame.new(0, 0.9, -5.5), Color = pink })
	for _, x in ipairs({ -1, 1 }) do
		P(m, { Name = "Eye", Size = Vector3.new(0.45, 0.45, 0.1), CFrame = cf * CFrame.new(x * 0.7, 2.2, -5.32), Color = black })
		P(m, { Name = "Horn", Size = Vector3.new(0.35, 1, 0.35), CFrame = cf * CFrame.new(x * 1, 3.3, -4), Color = Color3.fromRGB(240, 230, 200) })
		P(m, { Name = "Ear", Size = Vector3.new(1, 0.4, 0.6), CFrame = cf * CFrame.new(x * 1.8, 2.5, -3.9), Color = black })
	end
	for _, o in ipairs({ { -1.4, -2.2 }, { 1.4, -2.2 }, { -1.4, 3 }, { 1.4, 3 } }) do
		P(m, { Name = "Leg", Size = Vector3.new(0.9, 2, 0.9), CFrame = cf * CFrame.new(o[1], -2.2, o[2]), Color = white })
		P(m, { Name = "Hoof", Size = Vector3.new(0.95, 0.5, 0.95), CFrame = cf * CFrame.new(o[1], -3.05, o[2]), Color = black })
	end
	P(m, { Name = "Udder", Size = Vector3.new(1.4, 0.8, 1.4), CFrame = cf * CFrame.new(0, -1.6, 1.8), Color = pink })
	P(m, { Name = "Tail", Size = Vector3.new(0.3, 2.2, 0.3), CFrame = cf * CFrame.new(0, 0.6, 4.1), Color = white })
	return root
end

function B.Piano(m: Model)
	local root = P(m, { Name = "Root", Size = Vector3.new(9, 6, 4.4), Transparency = 1 })
	local cf = root.CFrame
	local body = Color3.fromRGB(25, 25, 30)
	P(m, { Name = "Case", Size = Vector3.new(9, 4.6, 3), CFrame = cf * CFrame.new(0, 0.6, 0.7), Color = body, Material = Enum.Material.Glass, Reflectance = 0.15 })
	P(m, { Name = "KeyBed", Size = Vector3.new(8.4, 0.5, 1.6), CFrame = cf * CFrame.new(0, -0.2, -1.4), Color = body })
	P(m, { Name = "Keys", Size = Vector3.new(8, 0.2, 1.3), CFrame = cf * CFrame.new(0, 0.15, -1.45), Color = Color3.fromRGB(250, 250, 245) })
	for i = 0, 13 do
		if i % 7 ~= 2 and i % 7 ~= 6 then
			P(m, { Name = "BlackKey", Size = Vector3.new(0.28, 0.2, 0.8), CFrame = cf * CFrame.new(-3.75 + i * 0.57, 0.3, -1.25), Color = body })
		end
	end
	for _, x in ipairs({ -4, 4 }) do
		P(m, { Name = "Leg", Size = Vector3.new(0.6, 2.4, 0.6), CFrame = cf * CFrame.new(x, -1.8, -1.4), Color = body })
	end
	P(m, { Name = "Plinth", Size = Vector3.new(9, 0.6, 3), CFrame = cf * CFrame.new(0, -2.7, 0.7), Color = body })
	return root
end

function B.Meteor(m: Model)
	local root = P(m, { Name = "Root", Size = Vector3.new(7, 7.4, 7), Transparency = 1 })
	P(m, { Name = "Rock", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), CFrame = root.CFrame, Color = Color3.fromRGB(90, 70, 60), Material = Enum.Material.Basalt })
	for _, o in ipairs({ Vector3.new(2.6, 1.6, 0), Vector3.new(-2, 2.2, 1.5), Vector3.new(0.5, -1, -2.9), Vector3.new(-2.2, -1.5, -1) }) do
		P(m, {
			Name = "Lava",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.2, 2.2, 2.2),
			CFrame = root.CFrame * CFrame.new(o * 0.95),
			Color = Color3.fromRGB(255, 120, 30),
			Material = Enum.Material.Neon,
		})
	end
	local fire = Instance.new("Fire")
	fire.Size = 9
	fire.Heat = 12
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = root
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Range = 24
	light.Brightness = 2
	light.Parent = root
	return root
end

function B.Boot(m: Model)
	local root = P(m, { Name = "Root", Size = Vector3.new(2.6, 2.8, 4.2), Transparency = 1 })
	local brown = Color3.fromRGB(96, 66, 44)
	P(m, { Name = "Shaft", Size = Vector3.new(2.2, 2.6, 1.9), CFrame = root.CFrame * CFrame.new(0, 0.1, -1.05), Color = brown })
	P(m, { Name = "Foot", Size = Vector3.new(2.2, 1.2, 4), CFrame = root.CFrame * CFrame.new(0, -0.8, 0), Color = brown })
	P(m, { Name = "Sole", Size = Vector3.new(2.3, 0.3, 4.1), CFrame = root.CFrame * CFrame.new(0, -1.35, 0), Color = Color3.fromRGB(40, 36, 34) })
	return root
end

function B.Fish(m: Model)
	local root = P(m, { Name = "Root", Size = Vector3.new(1.8, 1.8, 4.4), Transparency = 1 })
	local c = Color3.fromRGB(150, 168, 180)
	P(m, { Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.8, 3.4), CFrame = root.CFrame * CFrame.new(0, 0, 0.3), Color = c })
	P(m, { Name = "Body2", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.6, 1.6), CFrame = root.CFrame * CFrame.new(0, 0, -1.0), Color = c })
	P(m, { Name = "Tail", Size = Vector3.new(0.2, 1.6, 1), CFrame = root.CFrame * CFrame.new(0, 0, -2), Color = Color3.fromRGB(120, 138, 150) })
	for _, x in ipairs({ -0.75, 0.75 }) do
		P(m, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), CFrame = root.CFrame * CFrame.new(x, 0.25, 1.45), Color = Color3.fromRGB(20, 20, 24) })
	end
	return root
end

function Objects.info(kind: string)
	for _, k in ipairs(Objects.KINDS) do
		if k.kind == kind then
			return k
		end
	end
	return nil
end

function Objects.build(kind: string): Model?
	local info = Objects.info(kind)
	local builder = B[kind]
	if not info or not builder then
		return nil
	end
	local m = Instance.new("Model")
	local root = builder(m)
	return finish(m, root, info)
end

function Objects.pick(rng: Random, roundSecond: number): string
	local total = 0
	for _, k in ipairs(Objects.KINDS) do
		if roundSecond >= k.min then
			total += k.chance
		end
	end
	local r = rng:NextNumber(0, total)
	for _, k in ipairs(Objects.KINDS) do
		if roundSecond >= k.min then
			r -= k.chance
			if r <= 0 then
				return k.kind
			end
		end
	end
	return Objects.KINDS[1].kind
end

-- where a model's root sits when resting on the plate at plate-local (x, z) with yaw (shared by server + client so the
-- client's fall animation ends exactly where the server places the real object)
function Objects.restCF(plateCF: CFrame, root: BasePart, x: number, z: number, yaw: number): CFrame
	return plateCF * CFrame.new(x, Config.PLATE_THICK / 2 + root.Size.Y / 2, z) * CFrame.Angles(0, yaw, 0)
end

-- red warning circle that sits on the plate where the object will land (welded to the plate so it tilts with it)
function Objects.warn(plateCore: BasePart, localPos: Vector3, radius: number, seconds: number, parent: Instance)
	local ring = Instance.new("Part")
	ring.Name = "DropWarning"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.Color = Color3.fromRGB(255, 60, 60)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Massless = true
	ring.CastShadow = false
	ring.Anchored = false
	ring.CFrame = plateCore.CFrame * CFrame.new(localPos.X, Config.PLATE_THICK / 2 + 0.35, localPos.Z) * CFrame.Angles(0, 0, math.rad(90))
	local w = Instance.new("WeldConstraint")
	w.Part0 = plateCore
	w.Part1 = ring
	w.Parent = ring
	ring.Parent = parent
	-- pulse
	task.spawn(function()
		local t0 = os.clock()
		while ring.Parent and os.clock() - t0 < seconds do
			ring.Transparency = 0.25 + 0.35 * (0.5 + 0.5 * math.sin((os.clock() - t0) * 14))
			task.wait(0.05)
		end
	end)
	Debris:AddItem(ring, seconds + 0.2)
	return ring
end

-- spawn `kind` high above the plate point `localPos` (x, z offsets from the plate centre), falling fast
function Objects.drop(kind: string, plateCore: BasePart, localPos: Vector3, parent: Instance, rng: Random): Model?
	local m = Objects.build(kind)
	if not m then
		return nil
	end
	local surface = plateCore.CFrame * CFrame.new(localPos.X, Config.PLATE_THICK / 2, localPos.Z)
	local start = surface.Position + Vector3.new(0, 70, 0)
	m:PivotTo(CFrame.new(start) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	m:SetAttribute("Born", os.clock())
	m.Parent = parent
	local root = m.PrimaryPart :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	root.AssemblyLinearVelocity = Vector3.new(0, -95, 0)
	root.AssemblyAngularVelocity = Vector3.new(0, rng:NextNumber(-2, 2), 0)
	-- trail while falling
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = root
	Sfx.play("fastWhoosh", root, 0.7)
	return m
end

-- puff of "smoke" + pop when an object is removed
function Objects.poof(m: Model)
	local root = m.PrimaryPart
	if root then
		local pos = root.Position
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(1, 1, 1)
		p.CFrame = CFrame.new(pos)
		p.Name = "PoofFx"
		p.Parent = Workspace
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		e.Size = NumberSequence.new(4, 8)
		e.Transparency = NumberSequence.new(0.2, 1)
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Speed = NumberRange.new(8, 14)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 0
		e.Parent = p
		e:Emit(18)
		Sfx.play("pop", pos, 0.6)
		Debris:AddItem(p, 1.5)
	end
	m:Destroy()
end

-- the landed object a character is standing on (short ray down from its root), or nil
local underParams = RaycastParams.new()
underParams.FilterType = Enum.RaycastFilterType.Include
function Objects.under(root: BasePart): Model?
	local world = workspace:FindFirstChild("TiltWorld")
	local folder = world and world:FindFirstChild("Objects")
	if not folder then
		return nil
	end
	underParams.FilterDescendantsInstances = { folder }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), underParams)
	if not hit then
		return nil
	end
	local m = hit.Instance:FindFirstAncestorOfClass("Model")
	while m and m.Parent ~= folder do
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return m
end

-- slide velocity (studs/s, horizontal) for a body on the plate. Shared by the server (bots) and the client (you).
-- Standing on a landed object is NOT a safe spot: it slides you faster and its top pushes you off.
function Objects.slideVelocity(root: BasePart, core: BasePart, Config, TiltMath, plateR: number): Vector3
	local lp = core.CFrame:PointToObjectSpace(root.Position) - Vector3.new(0, Config.PLATE_THICK / 2, 0)
	local r = math.sqrt(lp.X * lp.X + lp.Z * lp.Z)
	if r > plateR + 3 or lp.Y < -1.5 then
		return Vector3.zero
	end
	local obj = Objects.under(root)
	if not obj and lp.Y >= 6 then
		return Vector3.zero
	end
	if obj and lp.Y >= Config.get("SLIDE_TOP") then
		return Vector3.zero
	end
	local up = core.CFrame.UpVector
	local ang = TiltMath.angleFromNormal(up.Y)
	local maxS = Config.get("SLIDE_MAX")
	local speed = TiltMath.slideSpeed(ang, Config.get("SLIDE_DEADZONE"), Config.get("SLIDE_K"), maxS)
	local dir = Vector3.new(up.X, 0, up.Z)
	local v = Vector3.zero
	if speed > 0 and dir.Magnitude > 1e-4 then
		v = dir.Unit * speed
	end
	if obj then
		local mult = Config.get("OBJ_SLIDE_MULT")
		v *= mult
		local root2 = obj.PrimaryPart
		if root2 then
			local out = Vector3.new(root.Position.X - root2.Position.X, 0, root.Position.Z - root2.Position.Z)
			if out.Magnitude < 0.2 then
				out = dir.Magnitude > 1e-4 and dir or Vector3.new(1, 0, 0)
			end
			v += out.Unit * Config.get("OBJ_SLIP")
		end
	end
	return v
end

return Objects
