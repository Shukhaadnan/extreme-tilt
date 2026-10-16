-- Map: builds the whole world in code (sky lobby island, the giant plate on its golden needle, ocean, floating
-- islands, clouds, lighting). Everything lives in workspace.TiltWorld; Map.build() is idempotent.
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Map = {}
Map.world = nil :: Folder?
Map.plateModel = nil :: Model?
Map.plateCore = nil :: BasePart?
Map.alignPos = nil :: AlignPosition?
Map.alignRot = nil :: AlignOrientation?
Map.lobbySpawn = nil :: BasePart?

local C = {
	-- calm two-tone look: white marble + one warm gold accent + charcoal; nature in muted greens/stone
	rim = Color3.fromRGB(232, 229, 222),
	rimDark = Color3.fromRGB(150, 146, 140),
	trim = Color3.fromRGB(200, 148, 46),
	face = Color3.fromRGB(246, 244, 239),
	stripe = Color3.fromRGB(226, 222, 214),
	emblem = Color3.fromRGB(44, 44, 48),
	gold = Color3.fromRGB(200, 148, 46),
	grass = Color3.fromRGB(104, 150, 84),
	grassDark = Color3.fromRGB(86, 128, 70),
	rock = Color3.fromRGB(140, 134, 126),
	rockDark = Color3.fromRGB(112, 107, 101),
	wood = Color3.fromRGB(110, 84, 64),
	leaf = Color3.fromRGB(88, 136, 78),
	leaf2 = Color3.fromRGB(110, 150, 92),
	path = Color3.fromRGB(205, 198, 186),
	spoke = Color3.fromRGB(214, 208, 198),
	cloud = Color3.fromRGB(250, 251, 253),
}
Map.COLORS = C

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end
Map.part = part

-- horizontal disc (cylinder axis = world Y) with its TOP face at `topY`
local function disc(parent, name, center: Vector3, radius: number, thick: number, topY: number, color: Color3, mat)
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thick, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, topY - thick / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = mat or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end
Map.disc = disc

local function weldTo(root: BasePart, p: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
end

---------------------------------------------------------------- lighting / sky
function Map.lighting()
	-- late-afternoon sun: longer soft shadows + warm light on the marble, still a calm palette
	Lighting.ClockTime = 15.7
	Lighting.Brightness = 3.1
	Lighting.Ambient = Color3.fromRGB(84, 86, 104)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 146, 168)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GeographicLatitude = 36
	Lighting.ShadowSoftness = 0.25
	Lighting.FogEnd = 100000
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:GetAttribute("TiltFx") then
			c:Destroy()
		end
	end
	local function fx(className, props)
		local e = Instance.new(className)
		for k, v in pairs(props) do
			(e :: any)[k] = v
		end
		e:SetAttribute("TiltFx", true)
		e.Parent = Lighting
		return e
	end
	fx("Atmosphere", {
		Density = 0.27,
		Offset = 0.08,
		Color = Color3.fromRGB(205, 222, 240),
		Decay = Color3.fromRGB(110, 140, 185),
		Glare = 0.4,
		Haze = 1.1,
	})
	fx("BloomEffect", { Intensity = 0.4, Size = 28, Threshold = 1.85 })
	fx("SunRaysEffect", { Intensity = 0.09, Spread = 0.55 })
	fx("ColorCorrectionEffect", { Saturation = -0.03, Contrast = 0.13, Brightness = 0.01, TintColor = Color3.fromRGB(255, 249, 240) })
	-- only far things go soft (islands, mountains): reads as a big world, never blurs the plate
	fx("DepthOfFieldEffect", { FarIntensity = 0.14, FocusDistance = 150, InFocusRadius = 120, NearIntensity = 0 })
	local sky = fx("Sky", { SunAngularSize = 14, MoonAngularSize = 9, StarCount = 1500 })
	sky.Name = "TiltSky"
end

---------------------------------------------------------------- ocean + clouds
function Map.ocean()
	local t = Workspace.Terrain
	pcall(function()
		t:Clear()
		t.WaterColor = Color3.fromRGB(38, 98, 128)
		t.WaterTransparency = 0.3
		t.WaterWaveSize = 0.35
		t.WaterWaveSpeed = 8
		t.WaterReflectance = 0.35
		t.Decoration = false
		t:FillBlock(CFrame.new(0, -8, 0), Vector3.new(2048, 16, 2048), Enum.Material.Water)
		-- a few tropical islands poking out of the sea far below
		local spots = { Vector3.new(-260, 0, -180), Vector3.new(300, 0, 140), Vector3.new(120, 0, -380), Vector3.new(-340, 0, 320) }
		for i, s in ipairs(spots) do
			local r = 40 + (i % 3) * 18
			t:FillBall(s + Vector3.new(0, -r * 0.55, 0), r, Enum.Material.Sand)
			t:FillBall(s + Vector3.new(0, -r * 0.45, 0), r * 0.82, Enum.Material.Grass)
		end
		-- the rock the golden needle stands on
		t:FillBall(Vector3.new(0, -26, 0), 44, Enum.Material.Sand)
		t:FillBall(Vector3.new(0, -14, 0), 30, Enum.Material.Rock)
		t:FillBall(Vector3.new(4, -8, -3), 18, Enum.Material.Slate)
		-- calm hazy mountains far out on the horizon (the atmosphere fades them into the sky)
		local hills = {
			{ 760, 0.4, 150, 70 }, { 820, 1.3, 130, 55 }, { 700, 2.3, 120, 50 },
			{ 880, 3.2, 170, 80 }, { 760, 4.2, 140, 60 }, { 840, 5.3, 120, 45 },
		}
		for _, h in ipairs(hills) do
			local d, a, r, up = h[1], h[2], h[3], h[4]
			local c = Vector3.new(math.cos(a) * d, up - r, math.sin(a) * d)
			t:FillBall(c, r, Enum.Material.Rock)
			t:FillBall(c + Vector3.new(r * 0.25, 8, -r * 0.2), r * 0.85, Enum.Material.Ground)
		end
	end)
	pcall(function()
		local clouds = t:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		clouds.Cover = 0.58
		clouds.Density = 0.55
		clouds.Color = Color3.fromRGB(255, 255, 255)
		clouds.Parent = t
	end)
end

---------------------------------------------------------------- the plate rings (shrinking plate)
-- radii()[1] = centre disc radius; ring k spans radii()[k] .. radii()[k+1]; the last value is PLATE_RADIUS.
function Map.radii(): { number }
	local rs = {}
	for _, st in ipairs(Config.SHRINK_STEPS) do
		table.insert(rs, st.r)
	end
	table.sort(rs)
	table.insert(rs, Config.PLATE_RADIUS)
	return rs
end

Map.rings = {} :: { [number]: { BasePart } } -- ring index -> its parts (segments + edge)

local function plateLocalCF(core: BasePart, x: number, yTop: number, z: number, yaw: number): CFrame
	-- yTop = height above the plate's top surface
	return core.CFrame * CFrame.new(x, Config.PLATE_THICK / 2 + yTop, z) * CFrame.Angles(0, yaw, 0)
end

local function weldDeco(core: BasePart, p: BasePart, collide: boolean)
	p.Anchored = false
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.Massless = not collide
	p.CastShadow = collide
	local w = Instance.new("WeldConstraint")
	w.Part0 = core
	w.Part1 = p
	w.Parent = p
end

-- gold line just inside radius r (decoration)
function Map.edgeRing(model: Model, core: BasePart, r: number, name: string, list: { BasePart }?)
	local N = math.max(24, math.floor(2 * math.pi * r / 4))
	local seg = 2 * math.pi * r / N + 0.25
	for i = 0, N - 1 do
		local a = (i + 0.5) * math.pi * 2 / N
		local rr = r - 0.35
		local p = part({
			Name = name,
			Size = Vector3.new(seg, 0.5, 0.6),
			CFrame = plateLocalCF(core, math.cos(a) * rr, 0.05, math.sin(a) * rr, -a + math.pi / 2),
			Color = C.trim,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.03,
			Parent = model,
		})
		weldDeco(core, p, false)
		if list then
			table.insert(list, p)
		end
	end
end

-- (re)build every ring that is missing (round start)
function Map.buildRings()
	local core, model = Map.plateCore, Map.plateModel
	if not core or not model then
		return
	end
	local rs = Map.radii()
	for k = 1, #rs - 1 do
		local alive = Map.rings[k] and #Map.rings[k] > 0 and Map.rings[k][1].Parent == model
		if not alive then
			local list = {}
			local r1, r2 = rs[k], rs[k + 1]
			local N = math.max(24, math.floor(2 * math.pi * r2 / 6))
			local w = 2 * r2 * math.tan(math.pi / N) + 0.15
			local depth = r2 - r1
			local color = (k % 2 == 1) and C.stripe or C.face
			for i = 0, N - 1 do
				local a = (i + 0.5) * math.pi * 2 / N
				local rm = (r1 + r2) / 2 - 0.3 -- reaches 0.6 under the inner disc/ring: no cracks to trip on
				local p = part({
					Name = "RingSeg",
					Size = Vector3.new(w, Config.PLATE_THICK, depth + 0.6),
					CFrame = plateLocalCF(core, math.cos(a) * rm, -Config.PLATE_THICK / 2, math.sin(a) * rm, -a + math.pi / 2),
					Color = color,
					Material = Enum.Material.Marble,
					Parent = model,
				})
				p:SetAttribute("Ring", k)
				p.CustomPhysicalProperties = PhysicalProperties.new(20, 0.6, 0, 1, 1)
				weldDeco(core, p, true)
				table.insert(list, p)
			end
			Map.edgeRing(model, core, r2, "RingEdge", list)
			-- polished gold band around the outside of the ring: the plate reads as a crafted object
			for i = 0, N - 1 do
				local a = (i + 0.5) * math.pi * 2 / N
				local rb = r2 + 0.12
				local p = part({
					Name = "RingBand",
					Size = Vector3.new(w + 0.05, Config.PLATE_THICK + 0.3, 0.4),
					CFrame = plateLocalCF(core, math.cos(a) * rb, -Config.PLATE_THICK / 2 + 0.1, math.sin(a) * rb, -a + math.pi / 2),
					Color = C.gold,
					Material = Enum.Material.SmoothPlastic,
					Reflectance = 0.03,
					Parent = model,
				})
				weldDeco(core, p, false)
				table.insert(list, p)
			end
			for _, p in ipairs(list) do
				p:SetAttribute("BaseColor", p.Color)
			end
			Map.rings[k] = list
		end
	end
end

-- ring k flashes as a warning (server toggles every 0.25 s; replicated as a clear blink)
function Map.warnRing(k: number, seconds: number)
	local list = Map.rings[k]
	if not list then
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		local on = false
		while os.clock() - t0 < seconds do
			on = not on
			for _, p in ipairs(list) do
				if p.Parent and p.Name == "RingSeg" then
					p.Color = on and Color3.fromRGB(235, 96, 84) or (p:GetAttribute("BaseColor") or p.Color)
				end
			end
			task.wait(math.max(0.12, 0.3 - (os.clock() - t0) * 0.06))
		end
	end)
end

-- ring k breaks off and tumbles down into the sea
function Map.crumble(k: number)
	local list = Map.rings[k]
	Map.rings[k] = nil
	if not list then
		return
	end
	local core = Map.plateCore
	local c = core and core.Position or Vector3.new(0, Config.PLATE_Y, 0)
	local rng = Random.new()
	for i, p in ipairs(list) do
		if p.Parent then
			local w = p:FindFirstChildOfClass("WeldConstraint")
			if w then
				w:Destroy()
			end
			p.CanCollide = false
			p.CanQuery = false
			p.Massless = false
			p.Color = p:GetAttribute("BaseColor") or p.Color
			p.Parent = Map.world
			local out = Vector3.new(p.Position.X - c.X, 0, p.Position.Z - c.Z)
			out = out.Magnitude > 0.1 and out.Unit or Vector3.new(1, 0, 0)
			-- staggered: pieces drop one after another around the ring, like it's cracking apart
			local delayT = (i % 7) * 0.035
			task.delay(delayT, function()
				if p.Parent then
					p.AssemblyLinearVelocity = out * rng:NextNumber(6, 16) + Vector3.new(0, rng:NextNumber(-4, 10), 0)
					p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-1, 1), rng:NextNumber(-3, 3))
					pcall(function()
						p:SetNetworkOwner(nil)
					end)
				end
			end)
			game:GetService("Debris"):AddItem(p, 6)
		end
	end
end

---------------------------------------------------------------- the plate
function Map.buildPlate(world: Folder)
	local R = Config.PLATE_RADIUS
	local T = Config.PLATE_THICK
	local topY = Config.PLATE_Y
	local center = Vector3.new(0, topY, 0)

	local model = Instance.new("Model")
	model.Name = "Plate"

	local core = part({
		Name = "PlateCore",
		Size = Vector3.new(4, T, 4),
		CFrame = CFrame.new(0, topY - T / 2, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	core.Anchored = false
	core.CustomPhysicalProperties = PhysicalProperties.new(20, 0.5, 0, 1, 1)

	-- the centre disc never crumbles; the rings around it do (see Map.buildRings / Map.crumble)
	local base = disc(model, "Surface", center, Map.radii()[1], T, topY, C.face, Enum.Material.Marble)
	base.Anchored = false
	base.CustomPhysicalProperties = PhysicalProperties.new(20, 0.6, 0, 1, 1)
	weldTo(core, base)

	-- decoration (welded, massless, no collision)
	local function deco(p: BasePart)
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		weldTo(core, p)
		return p
	end
	-- thin spokes so you can SEE the tilt direction
	local inner = Map.radii()[1]
	for i = 0, 7 do
		local a = i * math.pi / 4
		local len = inner - 9
		local s = part({
			Name = "Stripe",
			Size = Vector3.new(len, 0.2, 0.5),
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * (len / 2 + 7.5), 0.08, math.sin(a) * (len / 2 + 7.5))) * CFrame.Angles(0, -a, 0),
			Color = C.spoke,
			Material = Enum.Material.Marble,
			Parent = model,
		})
		deco(s)
	end
	local er = deco(disc(model, "EmblemRing", center, 6, 0.2, topY + 0.2, C.trim, Enum.Material.SmoothPlastic))
	er.Reflectance = 0.03
	deco(disc(model, "Emblem", center, 5.2, 0.2, topY + 0.26, C.face, Enum.Material.Marble))
	-- 8-point compass star (two squares, one turned 45 degrees) + marble cap
	for k = 0, 1 do
		local st = part({
			Name = "EmblemStar",
			Size = Vector3.new(5.4, 0.12, 5.4),
			CFrame = CFrame.new(center + Vector3.new(0, 0.32, 0)) * CFrame.Angles(0, k * math.pi / 4, 0),
			Color = C.gold,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.03,
			Parent = model,
		})
		deco(st)
	end
	deco(disc(model, "EmblemCap", center, 1.6, 0.14, topY + 0.42, C.emblem, Enum.Material.Marble))
	-- gold line around the centre disc
	Map.edgeRing(model, core, inner, "CenterEdge", nil)
	-- underside: a stepped marble dish with a gold seam, ending in the socket that sits on the needle's ball
	local yb = topY - T
	deco(disc(model, "Underside", center, inner - 2, 1.5, yb, C.rimDark, Enum.Material.Marble))
	local seam = deco(disc(model, "UnderSeam", center, inner - 9.4, 0.5, yb - 1.5, C.gold, Enum.Material.SmoothPlastic))
	seam.Reflectance = 0.03
	deco(disc(model, "Underside2", center, inner - 10, 1.6, yb - 2, C.rim, Enum.Material.Marble))
	deco(disc(model, "Socket", center, 7, 1.6, yb - 3.6, C.emblem, Enum.Material.Marble))

	model.PrimaryPart = core
	model.Parent = world

	-- keep the plate pinned at its centre; the server only turns it
	local pivot = part({
		Name = "Pivot",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, topY - T / 2, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = world,
	})
	local att = Instance.new("Attachment")
	att.Name = "CoreAtt"
	att.Parent = core
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.RigidityEnabled = true
	ap.Position = pivot.Position
	ap.Parent = core
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = true
	ao.CFrame = CFrame.identity
	ao.Parent = core
	pcall(function()
		core:SetNetworkOwner(nil)
	end)

	-- the golden needle the plate balances on (no collision: nobody can land on it)
	-- the ball joint sits in the plate's socket; the needle runs all the way down to its rock in the sea
	local ballY = topY - T - 6
	local needleTop = ballY - 3
	local needleBottom = -2
	local needleLen = needleTop - needleBottom
	local function needlePart(props)
		props.CanCollide = false
		props.CanQuery = false
		props.CanTouch = false
		props.Parent = world
		return part(props)
	end
	needlePart({
		Name = "Needle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(needleLen, 3.4, 3.4),
		CFrame = CFrame.new(0, needleBottom + needleLen / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.gold,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.03,
	})
	needlePart({
		Name = "NeedleBall",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(8.4, 8.4, 8.4),
		CFrame = CFrame.new(0, ballY, 0),
		Color = C.gold,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.03,
	})
	-- collar under the ball + charcoal bands down the shaft + a wide foot on the rock
	needlePart({
		Name = "NeedleCollar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 5.2, 5.2),
		CFrame = CFrame.new(0, ballY - 5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.emblem,
		Material = Enum.Material.Metal,
	})
	for i = 1, 6 do
		needlePart({
			Name = "NeedleRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 4.4, 4.4),
			CFrame = CFrame.new(0, needleTop - 20 - i * 40, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = C.emblem,
			Material = Enum.Material.Metal,
		})
	end
	needlePart({
		Name = "NeedleFoot",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 12, 12),
		CFrame = CFrame.new(0, 12, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.gold,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.03,
	})
	needlePart({
		Name = "NeedleFootRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 13, 13),
		CFrame = CFrame.new(0, 15.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.emblem,
		Material = Enum.Material.Metal,
	})

	Map.plateModel = model
	Map.plateCore = core
	Map.alignPos = ap
	Map.alignRot = ao
	Map.buildRings()
	return model
end

---------------------------------------------------------------- lobby island
local function tree(parent, pos: Vector3, scale: number, leafColor: Color3)
	local trunkH = 7 * scale
	part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkH, 1.4 * scale, 1.4 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, trunkH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.wood,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local top = pos + Vector3.new(0, trunkH, 0)
	for _, o in ipairs({ Vector3.new(0, 1.5, 0), Vector3.new(2, 0.2, 0.6), Vector3.new(-1.6, 0.4, -1.4), Vector3.new(0.3, 3, -0.4) }) do
		part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (5.2 * scale),
			CFrame = CFrame.new(top + o * scale),
			Color = leafColor,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})
	end
end
Map.tree = tree

local function flowers(parent, center: Vector3, n: number, rng: Random)
	local palette = { Color3.fromRGB(245, 243, 236), Color3.fromRGB(235, 230, 215) }
	for _ = 1, n do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, 3.5)
		local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		part({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.8, 0.8, 0.8),
			CFrame = CFrame.new(p + Vector3.new(0, 0.45, 0)),
			Color = palette[rng:NextInteger(1, #palette)],
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = parent,
		})
	end
end

local function sign(parent, cf: CFrame, size: Vector2, lines: { string })
	local board = part({
		Name = "Sign",
		Size = Vector3.new(size.X, size.Y, 0.6),
		CFrame = cf,
		Color = C.emblem,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 6)
	list.Parent = gui
	for i, txt in ipairs(lines) do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, -30, 0, i == 1 and 120 or 56)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = i == 1 and C.gold or Color3.new(1, 1, 1)
		l.Text = txt
		l.LayoutOrder = i
		l.Parent = gui
	end
	-- posts
	for _, x in ipairs({ -size.X / 2 + 1, size.X / 2 - 1 }) do
		local bottom = cf * CFrame.new(x, -size.Y / 2, 0.8)
		local h = 7
		part({
			Name = "SignPost",
			Size = Vector3.new(0.8, h, 0.8),
			CFrame = CFrame.new(bottom.Position - Vector3.new(0, h / 2 - 0.5, 0)),
			Color = C.wood,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end
	return board
end

function Map.buildLobby(world: Folder)
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	local L = Config.LOBBY_CENTER
	local LR = Config.LOBBY_RADIUS
	local rng = Random.new(7)

	-- floating island: grass top + layered rock underneath
	disc(lobby, "Grass", L, LR, 4, L.Y, C.grass, Enum.Material.Grass)
	disc(lobby, "GrassEdge", L, LR + 1.2, 1.2, L.Y - 3.2, C.grassDark, Enum.Material.Grass)
	local y = L.Y - 4
	local layers = { { LR - 1, 6 }, { LR - 6, 7 }, { LR - 13, 8 }, { LR - 20, 8 }, { LR - 26, 7 }, { 4, 6 } }
	for i, ly in ipairs(layers) do
		disc(lobby, "Rock", L + Vector3.new((i % 2) * 1.5, 0, ((i + 1) % 2) * -1.2), ly[1], ly[2], y, (i % 2 == 0) and C.rock or C.rockDark, Enum.Material.Slate)
		y -= ly[2]
	end
	-- rocky "roots" hanging under the island so it looks carved out of a cliff, not a stack of discs
	for i = 0, 9 do
		local a = i * math.pi * 2 / 10 + 0.3
		local rr = LR - 10 - (i % 3) * 5
		local sz = 9 + (i % 4) * 3
		part({
			Name = "Rock",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(sz, sz * 1.5, sz),
			CFrame = CFrame.new(L + Vector3.new(math.cos(a) * rr, -12 - (i % 3) * 7, math.sin(a) * rr)),
			Color = (i % 2 == 0) and C.rock or C.rockDark,
			Material = Enum.Material.Slate,
			CanCollide = false,
			CanQuery = false,
			Parent = lobby,
		})
	end
	-- cobble path toward the plate
	for i = 0, 6 do
		disc(lobby, "Path", L + Vector3.new(0, 0, -6 - i * 4), 2.2, 0.2, L.Y + 0.1, C.path, Enum.Material.Cobblestone)
	end
	-- spawn: invisible block (reliable spawning) + decorative pink pad
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "LobbySpawn"
	spawnPad.Size = Vector3.new(10, 1, 10)
	spawnPad.CFrame = CFrame.new(L.X, L.Y - 0.4, L.Z + 6)
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.Transparency = 1
	spawnPad.CanCollide = false
	spawnPad.CanQuery = false
	spawnPad.CanTouch = false
	spawnPad.Parent = lobby
	local decal = spawnPad:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	disc(lobby, "SpawnPad", L + Vector3.new(0, 0, 6), 6, 0.4, L.Y + 0.2, C.face, Enum.Material.Marble)
	disc(lobby, "SpawnPadRing", L + Vector3.new(0, 0, 6), 7, 0.3, L.Y + 0.1, C.trim)
	Map.lobbySpawn = spawnPad

	-- trees + flowers around the edge (not on the plate-facing side)
	for i = 0, 9 do
		local a = math.rad(-30 + i * 24) -- angles from +X going round the back (away from the plate at -Z)
		local r = LR - 5 - (i % 2) * 3
		local pos = L + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		tree(lobby, pos, 0.9 + (i % 3) * 0.2, (i % 4 == 0) and C.leaf2 or C.leaf)
	end
	-- (no flower clusters: small white balls read as stones/eggs from the player camera)
	local _ = flowers
	-- low bushes + a few mossy stones near the fence (soft shapes, same greens)
	for i = 0, 13 do
		local a = math.rad(-40 + i * 19 + rng:NextNumber(-4, 4))
		local r = LR - 3.2
		local pos = L + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local s = rng:NextNumber(2.2, 3.4)
		part({
			Name = (i % 4 == 3) and "Stone" or "Bush",
			Shape = Enum.PartType.Ball,
			Size = (i % 4 == 3) and Vector3.new(s * 1.2, s * 0.7, s) or Vector3.new(s * 1.3, s, s * 1.3),
			CFrame = CFrame.new(pos + Vector3.new(0, s * 0.3, 0)),
			Color = (i % 4 == 3) and C.rock or ((i % 2 == 0) and C.leaf or C.grassDark),
			Material = (i % 4 == 3) and Enum.Material.Slate or Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
			Parent = lobby,
		})
	end

	-- fence (low posts) + invisible wall so nobody falls off the lobby
	local wallH = 16
	local N = 40
	for i = 0, N - 1 do
		local a = (i + 0.5) * math.pi * 2 / N
		local pos = L + Vector3.new(math.cos(a) * (LR - 0.6), 0, math.sin(a) * (LR - 0.6))
		part({
			Name = "Wall",
			Size = Vector3.new(2 * math.pi * LR / N + 0.6, wallH, 1),
			CFrame = CFrame.new(pos + Vector3.new(0, wallH / 2, 0)) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Transparency = 1,
			CanQuery = false,
			Parent = lobby,
		})
		if i % 2 == 0 then
			part({
				Name = "FencePost",
				Size = Vector3.new(0.8, 3, 0.8),
				CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)),
				Color = Color3.fromRGB(255, 250, 240),
				Parent = lobby,
			})
		end
	end
	-- fence rail
	for i = 0, N - 1 do
		local a = (i + 0.5) * math.pi * 2 / N
		local pos = L + Vector3.new(math.cos(a) * (LR - 0.6), 2.4, math.sin(a) * (LR - 0.6))
		part({
			Name = "FenceRail",
			Size = Vector3.new(2 * math.pi * LR / N + 0.2, 0.5, 0.4),
			CFrame = CFrame.new(pos) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = Color3.fromRGB(255, 250, 240),
			CanCollide = false,
			Parent = lobby,
		})
	end

	-- how-to-play sign facing the spawn, title arch
	local signPos = L + Vector3.new(16, 6.5, 14)
	sign(
		lobby,
		CFrame.lookAt(signPos, Vector3.new(L.X, signPos.Y, L.Z + 6)),
		Vector2.new(13, 8),
		{ "EXTREME TILT!", "1. The plate tilts - stay on!", "2. PUSH people off (miss = you trip)", "3. DODGE their pushes", "Last one standing = WIN" }
	)
	-- arch over the path toward the plate
	local archZ = L.Z - 22
	for _, x in ipairs({ -7, 7 }) do
		part({
			Name = "ArchPillar",
			Size = Vector3.new(1.6, 12, 1.6),
			CFrame = CFrame.new(L.X + x, L.Y + 6, archZ),
			Color = C.rim,
			Material = Enum.Material.Marble,
			Parent = lobby,
		})
	end
	local beam = part({
		Name = "ArchBeam",
		Size = Vector3.new(17, 3.2, 1.6),
		CFrame = CFrame.new(L.X, L.Y + 13.4, archZ) * CFrame.Angles(0, math.pi, 0),
		Color = C.emblem,
		Parent = lobby,
	})
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 30
		g.LightInfluence = 0
		g.Parent = beam
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.6
		t.Text = "TILT"
		t.Parent = g
	end

	lobby.Parent = world
	return lobby
end

---------------------------------------------------------------- scenery around
function Map.buildScenery(world: Folder)
	local f = Instance.new("Folder")
	f.Name = "Scenery"
	local rng = Random.new(42)
	local spots = {
		Vector3.new(-120, 270, -60), Vector3.new(135, 255, -40), Vector3.new(-90, 240, 120), Vector3.new(110, 285, 150),
		Vector3.new(0, 230, -150), Vector3.new(-170, 300, 40), Vector3.new(175, 305, 60), Vector3.new(60, 265, -170),
	}
	for i, s in ipairs(spots) do
		local r = 9 + (i % 3) * 4
		disc(f, "IsleTop", s, r, 2.5, s.Y, C.grass, Enum.Material.Grass)
		disc(f, "IsleRock", s + Vector3.new(0, 0, 0), r - 2, 5, s.Y - 2.5, C.rockDark, Enum.Material.Slate)
		disc(f, "IsleRock2", s, math.max(2, r - 6), 5, s.Y - 7.5, C.rock, Enum.Material.Slate)
		part({
			Name = "IsleTip",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(math.max(4, r - 5), r * 1.3, math.max(4, r - 5)),
			CFrame = CFrame.new(s + Vector3.new(0, -12 - r * 0.3, 0)),
			Color = C.rockDark,
			Material = Enum.Material.Slate,
			CanCollide = false,
			CanQuery = false,
			Parent = f,
		})
		tree(f, s + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)), 0.8 + (i % 2) * 0.3, (i % 3 == 0) and C.leaf2 or C.leaf)
	end
	-- soft cloud banks below the plate: you're clearly high up in the sky
	local clouds = Instance.new("Folder")
	clouds.Name = "Clouds"
	clouds.Parent = f
	local crng = Random.new(11)
	for i = 1, 0 do -- (cloud puffs removed: part clouds read as cotton balls; the sky's own clouds are enough)
		local a = (i / 14) * math.pi * 2 + crng:NextNumber(-0.15, 0.15)
		local d = crng:NextNumber(150, 380)
		local c = Vector3.new(math.cos(a) * d, crng:NextNumber(150, 200), math.sin(a) * d)
		-- keep clear of the lobby island and the needle
		if (Vector3.new(c.X, 0, c.Z) - Vector3.new(Config.LOBBY_CENTER.X, 0, Config.LOBBY_CENTER.Z)).Magnitude > 70 then
			local m = Instance.new("Model")
			m.Name = "Cloud"
			local sc = crng:NextNumber(1.6, 2.6)
			for k = 1, 9 do
				local off = Vector3.new(crng:NextNumber(-22, 22), crng:NextNumber(-1, 3) * (k <= 3 and 2 or 1), crng:NextNumber(-12, 12)) * sc
				local sz = crng:NextNumber(14, 24) * sc * (k <= 3 and 1.15 or 0.85)
				part({
					Name = "Puff",
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(sz * 1.25, sz * 0.42, sz),
					CastShadow = false,
					Transparency = 0.06,
					CFrame = CFrame.new(c + off),
					Color = C.cloud,
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
					Parent = m,
				})
			end
			m.Parent = clouds
		end
	end
	f.Parent = world
	return f
end

function Map.build(): Folder
	local old = Workspace:FindFirstChild("TiltWorld")
	if old then
		old:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "TiltWorld"
	world.Parent = Workspace
	Map.world = world
	Map.lighting()
	Map.ocean()
	Map.buildLobby(world)
	Map.buildScenery(world)
	Map.buildPlate(world)
	local objects = Instance.new("Folder")
	objects.Name = "Objects"
	objects.Parent = world
	local markers = Instance.new("Folder")
	markers.Name = "Markers"
	markers.Parent = world
	return world
end

-- a spot in the lobby (ring around the spawn pad) for returning player i
function Map.lobbySpot(i: number?): Vector3
	local L = Config.LOBBY_CENTER
	local k = i or math.random(1, 12)
	local a = k * 2.4
	local r = 6 + (k % 3) * 4
	return L + Vector3.new(math.cos(a) * r, 3.5, 4 + math.sin(a) * r)
end

-- start spot on the plate (ring) for participant i of n
function Map.plateSpot(i: number, n: number): Vector3
	local a = (i / math.max(n, 1)) * math.pi * 2
	local r = (n <= 1) and 0 or math.min(16, 6 + n * 0.6)
	return Vector3.new(math.cos(a) * r, Config.PLATE_Y + 3.5, math.sin(a) * r)
end

return Map
