-- Bots: fill the plate so the game is fun solo. R15 rigs from HumanoidDescription (free catalog ids proven in our
-- other games) with a manual Motor6D fix, block-rig fallback, default R15 animations.
-- Brain (every Config.BOT_THINK s): run to the spot that balances the plate (opposite the heavy side), each bot with
-- its own angle offset so they spread out, some reaction delay and a few "silly" moments so bots also fall sometimes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local TiltMath = require(ReplicatedStorage:WaitForChild("TiltMath"))
local Anim = require(script.Parent.Anim)

local Bots = {}

-- usable plate radius right now (shrinks during a round; bots move in before the edge crumbles)
local function plateR(): number
	local r = ReplicatedStorage:GetAttribute("PlateR") or Config.PLATE_RADIUS
	local safe = ReplicatedStorage:GetAttribute("PlateSafeR")
	if safe and safe < r then
		r = safe
	end
	return r
end
Bots.list = {} :: { [number]: any } -- index -> bot record
Bots.paused = false

Bots.NAMES = { "Noodle", "Pickle", "Waffles", "Biscuit", "Zoomy", "Muffin", "Pixel", "Tater", "Bloop", "Sprout", "Nugget", "Jelly" }

local R15_JOINTS = {
	{ "LowerTorso", "HumanoidRootPart", "Root", "RootRigAttachment" },
	{ "UpperTorso", "LowerTorso", "Waist", "WaistRigAttachment" },
	{ "Head", "UpperTorso", "Neck", "NeckRigAttachment" },
	{ "LeftUpperArm", "UpperTorso", "LeftShoulder", "LeftShoulderRigAttachment" },
	{ "LeftLowerArm", "LeftUpperArm", "LeftElbow", "LeftElbowRigAttachment" },
	{ "LeftHand", "LeftLowerArm", "LeftWrist", "LeftWristRigAttachment" },
	{ "RightUpperArm", "UpperTorso", "RightShoulder", "RightShoulderRigAttachment" },
	{ "RightLowerArm", "RightUpperArm", "RightElbow", "RightElbowRigAttachment" },
	{ "RightHand", "RightLowerArm", "RightWrist", "RightWristRigAttachment" },
	{ "LeftUpperLeg", "LowerTorso", "LeftHip", "LeftHipRigAttachment" },
	{ "LeftLowerLeg", "LeftUpperLeg", "LeftKnee", "LeftKneeRigAttachment" },
	{ "LeftFoot", "LeftLowerLeg", "LeftAnkle", "LeftAnkleRigAttachment" },
	{ "RightUpperLeg", "LowerTorso", "RightHip", "RightHipRigAttachment" },
	{ "RightLowerLeg", "RightUpperLeg", "RightKnee", "RightKneeRigAttachment" },
	{ "RightFoot", "RightLowerLeg", "RightAnkle", "RightAnkleRigAttachment" },
}

function Bots.ensureR15Joints(model: Model): number
	local made = 0
	for _, j in ipairs(R15_JOINTS) do
		local child, parent = model:FindFirstChild(j[1]), model:FindFirstChild(j[2])
		if child and parent then
			local existing = nil
			for _, c in ipairs(child:GetChildren()) do
				if c.Name == j[3] and c:IsA("Motor6D") then
					existing = c
					break
				end
			end
			if not existing then
				local a1, a0 = child:FindFirstChild(j[4]), parent:FindFirstChild(j[4])
				if a1 and a0 then
					local m = Instance.new("Motor6D")
					m.Name = j[3]
					m.Part0, m.Part1 = parent, child
					m.C0, m.C1 = a0.CFrame, a1.CFrame
					m.Parent = child
					made += 1
				end
			end
		end
	end
	return made
end

-- free Roblox-made catalog assets (verified in secret_game / quiet_place)
Bots.HAIR_IDS = { 376548738, 376526888, 63690008, 376524487, 9244150641, 7193455510, 7193454569, 9244148336,
	2956239660, 376527350, 451221329, 1103003368 }
Bots.SHIRT_IDS = { 398635081, 144076436, 398634295, 382537702, 4047886060, 382538059, 398633584, 3670737444 }
Bots.PANTS_IDS = { 382537569, 144076760, 398634487, 382537806, 382537950, 398635338, 129458426 }
Bots.SKIN = {
	Color3.fromRGB(255, 224, 196), Color3.fromRGB(241, 194, 160), Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66), Color3.fromRGB(141, 85, 36), Color3.fromRGB(105, 67, 40), Color3.fromRGB(255, 219, 172),
}

local templates = {} -- key -> Model | false
local function descRig(key, hair, shirt, pants)
	if templates[key] ~= nil then
		return templates[key] or nil
	end
	local ok, model = pcall(function()
		local d = Instance.new("HumanoidDescription")
		d.HairAccessory = tostring(hair)
		d.Shirt = shirt
		d.Pants = pants
		return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	end)
	if ok and model and model:FindFirstChild("HumanoidRootPart") and model:FindFirstChildOfClass("Humanoid") then
		for _, c in ipairs(model:GetDescendants()) do
			if c:IsA("LocalScript") or c:IsA("Script") then
				c:Destroy()
			end
		end
		Bots.ensureR15Joints(model)
		templates[key] = model
		return model
	end
	if not ok then
		warn("[Bots] HumanoidDescription rig failed (" .. tostring(model) .. "), using block rig")
	end
	templates[key] = false
	return nil
end

local function blockPart(model, name, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.Parent = model
	return p
end

-- offline fallback: simple welded block body
local function blockRig(name: string, skin: Color3, shirtColor: Color3)
	local model = Instance.new("Model")
	model.Name = name
	local root = blockPart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), skin)
	root.Transparency = 1
	root.CanCollide = true
	local torso = blockPart(model, "UpperTorso", Vector3.new(2, 2, 1), shirtColor)
	local head = blockPart(model, "Head", Vector3.new(1.2, 1.2, 1.2), skin)
	local function weld(a, b, c0)
		local w = Instance.new("Weld")
		w.Part0, w.Part1, w.C0 = a, b, c0
		w.Parent = b
	end
	weld(root, torso, CFrame.new())
	weld(torso, head, CFrame.new(0, 1.6, 0))
	for _, x in ipairs({ -0.5, 0.5 }) do
		local leg = blockPart(model, x < 0 and "LeftLeg" or "RightLeg", Vector3.new(0.9, 2, 1), Color3.fromRGB(50, 55, 70))
		weld(root, leg, CFrame.new(x, -2, 0))
	end
	model.PrimaryPart = root
	local hum = Instance.new("Humanoid")
	hum.HipHeight = 3
	hum.RequiresNeck = false
	hum.Parent = model
	return model
end

local SKIN_PARTS = { "Head", "LeftHand", "RightHand", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" }

function Bots.makeRig(index: number, name: string): Model
	local hair = Bots.HAIR_IDS[(index * 7) % #Bots.HAIR_IDS + 1]
	local shirt = Bots.SHIRT_IDS[(index * 3) % #Bots.SHIRT_IDS + 1]
	local pants = Bots.PANTS_IDS[(index * 5) % #Bots.PANTS_IDS + 1]
	local skin = Bots.SKIN[(index * 3) % #Bots.SKIN + 1]
	local tpl = descRig(table.concat({ hair, shirt, pants }, "_"), hair, shirt, pants)
	local model
	if tpl then
		model = tpl:Clone()
		Bots.ensureR15Joints(model)
		for _, n in ipairs(SKIN_PARTS) do
			local p = model:FindFirstChild(n)
			if p and p:IsA("BasePart") then
				p.Color = skin
			end
		end
	else
		model = blockRig(name, skin, Color3.fromHSV((index * 0.17) % 1, 0.6, 0.9))
	end
	model.Name = name
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayName = name
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.NameDisplayDistance = 60
	hum.WalkSpeed = Config.get("BOT_SPEED")
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	end)
	if not hum:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = hum
	end
	model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") :: BasePart
	return model
end

local function folder(): Folder
	local f = Workspace:FindFirstChild("TiltBots")
	if not f then
		f = Instance.new("Folder")
		f.Name = "TiltBots"
		f.Parent = Workspace
	end
	return f :: Folder
end
Bots.folder = folder

function Bots.spawn(index: number, at: Vector3)
	if Bots.list[index] then
		return Bots.list[index]
	end
	local name = Bots.NAMES[(index - 1) % #Bots.NAMES + 1]
	local ok, model = pcall(Bots.makeRig, index, name)
	if not ok or not model then
		warn("[Bots] rig failed: " .. tostring(model))
		return nil
	end
	model:SetAttribute("Bot", true)
	model:SetAttribute("BotIndex", index)
	model:PivotTo(CFrame.new(at))
	model.Parent = folder()
	local root = model.PrimaryPart :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local rng = Random.new(index * 977 + os.time())
	local bot = {
		index = index,
		name = name,
		model = model,
		hum = model:FindFirstChildOfClass("Humanoid"),
		root = root,
		think = 0,
		spread = rng:NextNumber(-0.7, 0.7), -- radians: own angle offset around the balance spot
		skill = rng:NextNumber(0.4, 0.9), -- how well this bot balances
		react = rng:NextNumber(Config.get("BOT_REACT_MIN"), Config.get("BOT_REACT_MAX")),
		goal = nil :: Vector3?,
		silly = 0, -- os.clock() until which the bot does something silly (wanders)
		rng = rng,
		animT = 0,
		stuck = 0,
	}
	Bots.list[index] = bot
	return bot
end

function Bots.despawn(index: number)
	local b = Bots.list[index]
	if not b then
		return
	end
	Bots.list[index] = nil
	pcall(function()
		b.model:Destroy()
	end)
end

function Bots.count(): number
	local n = 0
	for _ in pairs(Bots.list) do
		n += 1
	end
	return n
end

-- keep exactly `n` bots alive (indices 1..n), spawning new ones at `spotFn(i)`
function Bots.setCount(n: number, spotFn)
	for i, _ in pairs(Bots.list) do
		if i > n then
			Bots.despawn(i)
		end
	end
	for i = 1, n do
		if not Bots.list[i] or not Bots.list[i].model.Parent then
			Bots.list[i] = nil
			Bots.spawn(i, spotFn(i))
		end
	end
end

-- brain: called by Game every frame with the plate info
-- ctx = { active = bool, plateCF = CFrame, tilt = {x,z}, torque = {x,z}, now = os.clock(), inRound = {[bot]=true} }
function Bots.step(dt: number, ctx)
	if Bots.paused then
		return
	end
	for _, b in pairs(Bots.list) do
		if not b.model.Parent or not b.root.Parent then
			continue
		end
		b.animT -= dt
		if b.animT <= 0 then
			b.animT = 0.2
			Anim.autoLoco(b.model)
		end
		if not ctx.active or not ctx.inRound[b] then
			continue
		end
		b.think -= dt
		if b.think > 0 then
			continue
		end
		b.think = Config.get("BOT_THINK") * b.rng:NextNumber(0.8, 1.3)
		-- reaction time: a fresh landing isn't noticed straight away (keep doing what we were doing)
		if ctx.lastLand and ctx.now - ctx.lastLand < b.react then
			continue
		end
		-- torque without me
		local pos = b.root.Position
		local myX, myZ = pos.X, pos.Z
		local ox, oz = ctx.torque.x - myX * Config.PLAYER_WEIGHT, ctx.torque.z - myZ * Config.PLAYER_WEIGHT
		local gx, gz
		if ctx.now < b.silly then
			gx, gz = b.goal and b.goal.X or myX, b.goal and b.goal.Z or myZ
		elseif b.rng:NextNumber() > b.skill * 1.05 and b.rng:NextNumber() < 0.08 then
			-- silly moment: wander somewhere random for a bit (makes bots fallible and funny)
			local a = b.rng:NextNumber(0, math.pi * 2)
			local r = b.rng:NextNumber(6, math.max(8, plateR() - 8))
			gx, gz = math.cos(a) * r, math.sin(a) * r
			b.silly = ctx.now + b.rng:NextNumber(1.2, 2.5)
		else
			local maxR = math.max(10, plateR() - 9)
			gx, gz = TiltMath.balanceSpot(ox, oz, b.spread, 8, maxR, 0.03 + 0.08 * b.skill)
			if gx == 0 and gz == 0 then
				-- nothing heavy: mill around the middle
				local a = b.spread * 4 + b.index
				gx, gz = math.cos(a) * 9, math.sin(a) * 9
			end
		end
		-- target on the plate surface (plate-local -> world)
		local localTarget = ctx.plateCF:PointToObjectSpace(Vector3.new(gx, Config.PLATE_Y, gz))
		local world = ctx.plateCF:PointToWorldSpace(Vector3.new(localTarget.X, Config.PLATE_THICK / 2 + 2, localTarget.Z))
		b.goal = world
		b.hum:MoveTo(world)
		-- blocked by a cow / piano: hop over it
		local v = b.root.AssemblyLinearVelocity
		local far = (Vector3.new(world.X, 0, world.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude > 4
		if far and Vector3.new(v.X, 0, v.Z).Magnitude < 2 then
			b.stuck += 1
		else
			b.stuck = 0
		end
		if b.stuck >= 3 or b.rng:NextNumber() < 0.015 then
			b.stuck = 0
			b.hum.Jump = true
		end
	end
end

-- celebrate (dance) or idle
function Bots.cheer(b)
	Anim.play(b.model, b.rng:NextNumber() < 0.5 and "cheer" or "dance1", 1, false)
end

function Bots.stopMoving(b)
	pcall(function()
		b.hum:MoveTo(b.root.Position)
	end)
end

return Bots
