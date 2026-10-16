-- FX: the cool stuff that only needs to look good on each screen.
--  * falling objects: a target marker that tightens on the landing spot, then the object drops from high up,
--    accelerating, tumbling, with a speed streak and a growing shadow, and lands exactly when the server places it
--  * impacts: shockwave ring, dust burst, flying chunks, flash for big ones
--  * shove: F key / gamepad X / on-screen PUSH button (mobile)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Objects = require(ReplicatedStorage:WaitForChild("Objects"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local fxFolder = Instance.new("Folder")
fxFolder.Name = "TiltFX_" .. player.UserId
fxFolder.Parent = Workspace

local function plateCore(): BasePart?
	local w = Workspace:FindFirstChild("TiltWorld")
	local p = w and w:FindFirstChild("Plate")
	return p and p:FindFirstChild("PlateCore") :: BasePart?
end
local function now(): number
	return Workspace:GetServerTimeNow()
end

local function fxPart(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = fxFolder
	return p
end

local RED = Color3.fromRGB(235, 80, 70)
local WHITE = Color3.fromRGB(255, 255, 255)
local DUST = {
	Watermelon = Color3.fromRGB(230, 90, 90),
	Cake = Color3.fromRGB(250, 240, 230),
	Duck = Color3.fromRGB(255, 220, 90),
	Anvil = Color3.fromRGB(200, 200, 205),
	Cow = Color3.fromRGB(240, 240, 240),
	Piano = Color3.fromRGB(220, 220, 225),
	Meteor = Color3.fromRGB(255, 150, 60),
}

---------------------------------------------------------------- falling objects
local falls = {} -- id -> fall record

local function anchorAll(m: Model)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

local function startFall(data)
	local core = plateCore()
	if not core or type(data) ~= "table" or type(data.kind) ~= "string" then
		return
	end
	local m = Objects.build(data.kind)
	if not m then
		return
	end
	anchorAll(m)
	local root = m.PrimaryPart :: BasePart
	local size = math.max(root.Size.X, root.Size.Z)
	local rec = {
		id = data.id,
		kind = data.kind,
		x = data.x,
		z = data.z,
		yaw = data.yaw or 0,
		landAt = data.landAt,
		warn = data.warn or Config.WARN_TIME,
		model = m,
		root = root,
		radius = size / 2 + 1.5,
		spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit * (math.random() * 4 + 3),
		shown = false,
	}
	-- target marker: a filled disc that grows + darkens, an outer ring, and a pulsing centre dot
	rec.shadow = fxPart({ Name = "FallShadow", Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(20, 20, 24), Transparency = 1, Size = Vector3.new(0.05, 1, 1) })
	rec.ring = fxPart({ Name = "FallRing", Shape = Enum.PartType.Cylinder, Color = RED, Material = Enum.Material.Neon, Transparency = 0.2, Size = Vector3.new(0.06, 1, 1) })
	rec.ringIn = fxPart({ Name = "FallRingIn", Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(246, 244, 239), Transparency = 0, Size = Vector3.new(0.07, 1, 1) })
	rec.dot = fxPart({ Name = "FallDot", Shape = Enum.PartType.Cylinder, Color = RED, Material = Enum.Material.Neon, Size = Vector3.new(0.08, 1.4, 1.4) })
	-- speed streak behind the object
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, root.Size.Y * 0.35, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -root.Size.Y * 0.35, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.18
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Color = ColorSequence.new(data.kind == "Meteor" and Color3.fromRGB(255, 160, 70) or WHITE)
	trail.Transparency = NumberSequence.new(0.45, 1)
	trail.LightEmission = data.kind == "Meteor" and 0.8 or 0.2
	trail.Parent = root
	falls[data.id] = rec
end

local function clearFall(rec)
	falls[rec.id] = nil
	for _, k in ipairs({ "shadow", "ring", "ringIn", "dot" }) do
		if rec[k] then
			rec[k]:Destroy()
		end
	end
	if rec.model then
		rec.model:Destroy()
	end
end

local function flatDisc(cf: CFrame, diameter: number, y: number): CFrame
	return cf * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
end

RunService.RenderStepped:Connect(function()
	local core = plateCore()
	if not core then
		return
	end
	local t = now()
	local fallTime = Config.FALL_TIME
	for id, rec in pairs(falls) do
		local left = rec.landAt - t
		local spot = core.CFrame * CFrame.new(rec.x, Config.PLATE_THICK / 2, rec.z)
		-- marker: grows in, then tightens
		local k = math.clamp(1 - left / rec.warn, 0, 1) -- 0 -> 1 over the warning
		local r = rec.radius
		local pulse = 0.5 + 0.5 * math.sin(t * 16)
		local ringD = r * 2 * (1.6 - 0.6 * k)
		rec.ring.Size = Vector3.new(0.06, ringD, ringD)
		rec.ring.CFrame = flatDisc(spot, ringD, 0.18)
		rec.ring.Transparency = 0.15 + 0.25 * pulse
		local innerD = math.max(0.5, ringD - 1.1)
		rec.ringIn.Size = Vector3.new(0.07, innerD, innerD)
		rec.ringIn.CFrame = flatDisc(spot, innerD, 0.19)
		rec.ringIn.Color = core.Color
		local w = Workspace:FindFirstChild("TiltWorld")
		local surf = w and w:FindFirstChild("Plate") and w.Plate:FindFirstChild("Surface") :: BasePart?
		rec.ringIn.Color = surf and surf.Color or Color3.fromRGB(246, 244, 239)
		local shD = r * 2 * (0.35 + 0.65 * k)
		rec.shadow.Size = Vector3.new(0.05, shD, shD)
		rec.shadow.CFrame = flatDisc(spot, shD, 0.2)
		rec.shadow.Transparency = 1 - 0.45 * k
		rec.dot.CFrame = flatDisc(spot, 1.4, 0.21)
		rec.dot.Transparency = 0.6 - 0.6 * pulse
		-- the object itself: drops during the last FALL_TIME seconds, accelerating (h = H * (1 - u^2))
		if left <= fallTime then
			local u = math.clamp(1 - left / fallTime, 0, 1)
			local h = Config.FALL_HEIGHT * (1 - u * u)
			local rest = Objects.restCF(core.CFrame, rec.root, rec.x, rec.z, rec.yaw)
			-- tumble while high, settle into the landing pose near the ground
			local tumble = (1 - u) ^ 2
			local spin = CFrame.fromAxisAngle(rec.spin.Unit, rec.spin.Magnitude * tumble * 1.2)
			local cf = CFrame.new(rest.Position + Vector3.new(0, h, 0)) * (rest - rest.Position) * spin
			if not rec.shown then
				rec.shown = true
				rec.model.Parent = fxFolder
				Sfx.play("fastWhoosh", rest.Position + Vector3.new(0, 30, 0), 0.6)
			end
			rec.model:PivotTo(cf)
		end
		-- landed: hide our copy as soon as the real one is there (or after a short grace)
		if left <= 0 then
			local folder = w and w:FindFirstChild("Objects")
			local real = false
			if folder then
				for _, m in ipairs(folder:GetChildren()) do
					if m:GetAttribute("FallId") == id then
						real = true
						break
					end
				end
			end
			if real or left < -0.6 then
				clearFall(rec)
			end
		end
	end
end)

---------------------------------------------------------------- impacts
local function shockwave(pos: Vector3, up: Vector3, size: number, color: Color3)
	local ring = fxPart({ Name = "Shockwave", Shape = Enum.PartType.Cylinder, Color = color, Material = Enum.Material.Neon, Transparency = 0.25 })
	local base = CFrame.lookAt(pos, pos + up) * CFrame.Angles(0, math.rad(90), 0)
	ring.Size = Vector3.new(0.15, size * 0.6, size * 0.6)
	ring.CFrame = base
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, size * 3.2, size * 3.2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.5)
end

local function dust(pos: Vector3, color: Color3, amount: number)
	local p = fxPart({ Name = "Dust", Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(14, 26)
	e.SpreadAngle = Vector2.new(80, 10)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, -12, 0)
	e.Drag = 4
	e.Rate = 0
	e.LockedToPart = false
	e.Parent = p
	e:Emit(amount)
	Debris:AddItem(p, 1.4)
end

local function chunks(pos: Vector3, color: Color3, n: number, power: number)
	for _ = 1, n do
		local s = math.random() * 0.6 + 0.35
		local c = fxPart({ Name = "Chunk", Size = Vector3.new(s, s, s), Color = color, CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)) })
		c.Anchored = false
		c.Massless = true
		local a = math.random() * math.pi * 2
		c.AssemblyLinearVelocity = Vector3.new(math.cos(a), 0, math.sin(a)) * (math.random() * 14 + 10) * power + Vector3.new(0, math.random() * 26 + 18, 0)
		c.AssemblyAngularVelocity = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5)
		TweenService:Create(c, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.1) }):Play()
		Debris:AddItem(c, 1)
	end
end

local function flash(pos: Vector3, size: number, color: Color3)
	local b = fxPart({ Name = "ImpactFlash", Shape = Enum.PartType.Ball, Color = color, Material = Enum.Material.Neon, Transparency = 0.1, Size = Vector3.one * size * 0.5, CFrame = CFrame.new(pos) })
	TweenService:Create(b, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * size * 1.8, Transparency = 1 }):Play()
	Debris:AddItem(b, 0.35)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = size * 4
	l.Brightness = 4
	l.Parent = b
end

local function onImpact(data)
	if type(data) ~= "table" or typeof(data.pos) ~= "Vector3" then
		return
	end
	local core = plateCore()
	local up = core and core.CFrame.UpVector or Vector3.yAxis
	local power = math.clamp((data.power or 2) / 3, 0.5, 1.6)
	local color = DUST[data.kind or ""] or WHITE
	local ground = data.pos - up * 2.2
	shockwave(ground + up * 0.3, up, 6 + power * 4, WHITE)
	dust(ground + up * 0.6, color, math.floor(10 + power * 10))
	chunks(ground + up * 0.5, color, math.floor(4 + power * 4), power)
	if data.kind == "Meteor" then
		flash(data.pos, 10, Color3.fromRGB(255, 160, 70))
		chunks(ground + up * 0.5, Color3.fromRGB(255, 120, 40), 6, 1.3)
	elseif data.kind == "Anvil" or data.kind == "Piano" then
		flash(data.pos, 7, WHITE)
	end
end

---------------------------------------------------------------- shrinking plate (local rumble + crack line)
local function onShrinkWarn(data)
	local core = plateCore()
	if not core or type(data) ~= "table" or type(data.r) ~= "number" then
		return
	end
	-- a red crack line drawn at the break radius for the warning time
	local N = 40
	local parts = {}
	for i = 0, N - 1 do
		local a = (i + 0.5) * math.pi * 2 / N
		local seg = 2 * math.pi * data.r / N + 0.2
		local p = fxPart({ Name = "Crack", Size = Vector3.new(seg, 0.1, 0.5), Color = RED, Material = Enum.Material.Neon, Transparency = 0.1 })
		table.insert(parts, { p = p, a = a })
	end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local c = plateCore()
		local e = os.clock() - t0
		if not c or e > (data.seconds or 3) then
			conn:Disconnect()
			for _, x in ipairs(parts) do
				x.p:Destroy()
			end
			return
		end
		for _, x in ipairs(parts) do
			x.p.CFrame = c.CFrame * CFrame.new(math.cos(x.a) * data.r, Config.PLATE_THICK / 2 + 0.22, math.sin(x.a) * data.r) * CFrame.Angles(0, -x.a + math.pi / 2, 0)
			x.p.Transparency = 0.5 - 0.45 * math.sin(e * 18)
		end
	end)
end

---------------------------------------------------------------- events
Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(kind: string, data)
	if kind == "Fall" then
		startFall(data)
	elseif kind == "Impact" then
		onImpact(data)
	elseif kind == "ShrinkWarn" then
		onShrinkWarn(data)
	elseif kind == "Shoved" and type(data) == "table" and typeof(data.pos) == "Vector3" then
		dust(data.pos - Vector3.new(0, 2, 0), WHITE, 8)
	elseif kind == "RoundStart" or kind == "Result" then
		for _, rec in pairs(falls) do
			clearFall(rec)
		end
	end
end)
