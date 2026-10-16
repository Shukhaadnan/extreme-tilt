-- Ambience (client only, purely visual): a few birds gliding in wide circles around the plate and the cloud banks
-- below slowly drifting. Everything here is local to this client: nothing replicates and the server never sees it.
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local world = Workspace:WaitForChild("TiltWorld", 30)
if not world then
	return
end

local folder = Instance.new("Folder")
folder.Name = "TiltAmbience"
folder.Parent = Workspace.CurrentCamera -- client-only container (never replicated, cleaned with the camera)

---------------------------------------------------------------- birds
local BIRD = Color3.fromRGB(246, 246, 244)
local WING_TIP = Color3.fromRGB(70, 72, 78)
local function mk(name, size, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.Color = color
	p.Parent = parent
	return p
end

local birds = {}
local rng = Random.new(5)
for i = 1, 7 do
	local m = Instance.new("Model")
	m.Name = "Bird"
	local body = mk("Body", Vector3.new(0.7, 0.6, 2), BIRD, m)
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(0.8, 0.8, 0.8)
	local torso = mk("Torso", Vector3.new(0.6, 0.55, 1.9), BIRD, m)
	local lw = mk("WingL", Vector3.new(2.6, 0.12, 0.9), BIRD, m)
	local rw = mk("WingR", Vector3.new(2.6, 0.12, 0.9), BIRD, m)
	local lt = mk("TipL", Vector3.new(1.1, 0.1, 0.7), WING_TIP, m)
	local rt = mk("TipR", Vector3.new(1.1, 0.1, 0.7), WING_TIP, m)
	m.Parent = folder
	-- some circle the plate, some the lobby; different radius, height, speed and direction
	local aroundLobby = i > 5
	local centre = aroundLobby and (Config.LOBBY_CENTER + Vector3.new(0, 26, 0)) or Vector3.new(0, Config.PLATE_Y + rng:NextNumber(26, 48), 0)
	table.insert(birds, {
		parts = { body = body, torso = torso, lw = lw, rw = rw, lt = lt, rt = rt },
		centre = centre,
		radius = aroundLobby and rng:NextNumber(48, 62) or rng:NextNumber(85, 150),
		speed = rng:NextNumber(0.05, 0.09) * (i % 2 == 0 and 1 or -1),
		phase = rng:NextNumber(0, math.pi * 2),
		bob = rng:NextNumber(2, 5),
		flapRate = rng:NextNumber(5.5, 7.5),
		glideSeed = rng:NextNumber(0, 10),
		scale = rng:NextNumber(1.1, 1.6),
	})
end

local function placeBird(b, t)
	local ang = b.phase + t * b.speed
	local pos = b.centre + Vector3.new(math.cos(ang) * b.radius, math.sin(t * 0.4 + b.phase) * b.bob, math.sin(ang) * b.radius)
	-- heading = tangent of the circle; bank slightly into the turn
	local dir = Vector3.new(-math.sin(ang), 0, math.cos(ang)) * math.sign(b.speed)
	local bank = -0.25 * math.sign(b.speed)
	local cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, bank)
	-- flap in bursts, then glide (wings held slightly up)
	local burst = math.sin(t * 0.7 + b.glideSeed) > -0.2
	local flap = burst and math.sin(t * b.flapRate + b.phase) * 0.55 or 0.12
	local s = b.scale
	local p = b.parts
	p.torso.CFrame = cf
	p.body.CFrame = cf * CFrame.new(0, 0.1, -1.05 * s)
	p.torso.Size = Vector3.new(0.6, 0.55, 1.9) * s
	p.body.Size = Vector3.new(0.8, 0.8, 0.8) * s
	local function wing(w, tip, side)
		local root = cf * CFrame.new(0.25 * side * s, 0.12 * s, 0) * CFrame.Angles(0, 0, flap * side)
		w.Size = Vector3.new(2.6, 0.12, 0.9) * s
		w.CFrame = root * CFrame.new(1.3 * side * s, 0, 0)
		tip.Size = Vector3.new(1.1, 0.1, 0.7) * s
		tip.CFrame = root * CFrame.new(2.6 * side * s, 0, 0.05) * CFrame.Angles(0, 0, flap * 0.6 * side) * CFrame.new(0.5 * side * s, 0, 0)
	end
	wing(p.lw, p.lt, -1)
	wing(p.rw, p.rt, 1)
end

---------------------------------------------------------------- cloud drift
local clouds = {}
local scen = world:WaitForChild("Scenery", 20)
local cf = scen and scen:WaitForChild("Clouds", 20)
if cf then
	for _, m in ipairs(cf:GetChildren()) do
		if m:IsA("Model") then
			table.insert(clouds, { model = m, base = m:GetPivot(), speed = 0.6 + (#clouds % 3) * 0.3 })
		end
	end
end

local t0 = os.clock()
RunService.RenderStepped:Connect(function()
	local t = os.clock() - t0
	for _, b in ipairs(birds) do
		placeBird(b, t)
	end
	-- clouds slide slowly along +X and wrap around (local only)
	for _, c in ipairs(clouds) do
		if c.model.Parent then
			local x = ((c.base.Position.X + t * c.speed + 400) % 800) - 400
			local dx = x - c.base.Position.X
			c.model:PivotTo(c.base + Vector3.new(dx, 0, 0))
		end
	end
end)
