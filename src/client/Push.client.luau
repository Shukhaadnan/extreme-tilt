-- Push: the PUSH button (bottom-right, every device) + F / gamepad X, the cooldown fill, and a smooth two-hand
-- shove animation. The animation is procedural (Motor6D.Transform on top of the normal walk/idle), so it needs no
-- uploaded animation asset and blends with whatever the character is doing. Every client animates every shover
-- (players and bots) from the server's "Shoved" event; your own push plays instantly on press.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local shoveRemote = Remotes:WaitForChild("Shove") :: RemoteEvent

local player = Players.LocalPlayer
local DEBUG = Workspace:GetAttribute("TiltDebug") == true
local GOLD = Color3.fromRGB(226, 190, 112)
local PANEL = Color3.fromRGB(22, 22, 26)
local WHITE = Color3.fromRGB(255, 255, 255)
local FONT = Enum.Font.FredokaOne

---------------------------------------------------------------- the animations
-- Procedural poses on top of the normal walk/idle (Motor6D C0 offsets: no uploaded animation assets needed).
-- Two layers, added together every frame for every character (players + bots), on every client:
--   1) MOVES   - one-shot actions: push, dodge, whiff (missed push), hit (got shoved)
--   2) AMBIENT - always-on body language: lean into a run, arms out for balance when the plate is steep,
--                limp while knocked down, windmill arms + kicking legs while falling off the plate
-- A move is a list of keys { t, { channel = weight }, ease? }. ease = how we arrive at that key:
--   nil = smoothstep, "snap" = explosive start (strikes), "out" = quick then settle
-- Channels: arm (both arms forward), elbow (bend), lean (+ forward), twist (torso turn), stepF / stepB (front / back leg),
--   knee, crouch, sweep (arms swept back), flail (windmill arms), splay (legs apart), recoil (chest + arms flung back),
--   spread (arms out to the sides), head (+ chin down, - head thrown back), kick (legs pedal), wobble (balance sway)
local MOVES = {
	-- PUSH: anticipation (hands to chest, lean back, weight back) -> explosive two-hand shove with a big step -> hold -> recover
	push = {
		dur = 0.62,
		{ 0.00, {} },
		{ 0.11, { arm = 0.7, elbow = 1.0, lean = -0.5, twist = -0.6, stepB = 0.4, knee = 0.4, crouch = 0.25, head = -0.2 }, "out" },
		{ 0.17, { arm = 1.1, elbow = 0.0, lean = 1.05, twist = 0.4, stepF = 1.0, stepB = 0.65, knee = 0.2, head = 0.3 }, "snap" },
		{ 0.32, { arm = 1.0, elbow = 0.1, lean = 0.9, twist = 0.25, stepF = 0.9, stepB = 0.55, knee = 0.15, head = 0.2 } },
		{ 0.62, {} },
	},
	-- DODGE: snap into a low sprinter crouch, arms swept back, then pop back up
	dodge = {
		dur = 0.5,
		{ 0.00, {} },
		{ 0.06, { crouch = 1.0, lean = 0.9, sweep = 1.0, stepF = 0.55, stepB = 0.7, knee = 1.0, head = 0.3 }, "snap" },
		{ 0.28, { crouch = 0.8, lean = 0.7, sweep = 0.85, stepF = 0.4, stepB = 0.5, knee = 0.8, head = 0.2 } },
		{ 0.50, {} },
	},
	-- MISSED PUSH: wind up, over-reach into nothing, arms windmill, head snaps back, legs give out, slow get-up
	whiff = {
		dur = 1.2,
		{ 0.00, {} },
		{ 0.10, { arm = 0.7, elbow = 1.0, lean = -0.4, twist = -0.5, crouch = 0.2 }, "out" },
		{ 0.18, { arm = 1.2, elbow = 0.0, lean = 1.5, stepF = 1.2, stepB = 0.9, head = -0.3 }, "snap" },
		{ 0.34, { arm = 0.6, flail = 1.0, lean = 1.3, stepF = 0.8, stepB = 1.0, splay = 0.6, head = -0.6 } },
		{ 0.85, { arm = 0.3, flail = 0.8, lean = 0.9, splay = 1.0, knee = 0.5, head = -0.3 } },
		{ 1.20, {} },
	},
	-- GOT SHOVED: chest and arms whip back, head snaps back, legs fly apart, then loosen
	hit = {
		dur = 0.6,
		{ 0.00, {} },
		{ 0.05, { recoil = 1.2, spread = 0.5, splay = 0.4, lean = -0.4, head = -1.0 }, "snap" },
		{ 0.25, { recoil = 0.9, spread = 0.8, splay = 0.7, flail = 0.3, lean = -0.3, head = -0.6 } },
		{ 0.60, {} },
	},
}
MOVES.flinch = MOVES.hit -- old name (tests)

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local EASE = {
	snap = function(u: number): number
		return 1 - (1 - u) ^ 4
	end,
	out = function(u: number): number
		return 1 - (1 - u) ^ 2
	end,
}
local EMPTY = {}
local function sampleMove(move, t: number)
	local out = {}
	if t <= 0 or t >= move.dur then
		return out
	end
	for i = 1, #move - 1 do
		local a, b = move[i], move[i + 1]
		if t <= b[1] then
			local x = math.clamp((t - a[1]) / (b[1] - a[1]), 0, 1)
			local e = EASE[b[3] or ""]
			local u = e and e(x) or smooth(x)
			local wa, wb = a[2] or EMPTY, b[2] or EMPTY
			for k, v in pairs(wa) do
				out[k] = v + ((wb[k] or 0) - v) * u
			end
			for k, v in pairs(wb) do
				if out[k] == nil then
					out[k] = v * u
				end
			end
			return out
		end
	end
	return out
end

-- joints per character (R15, with an R6 fallback)
local function joints(model: Model)
	local function m(partName, jointName)
		local p = model:FindFirstChild(partName)
		local j = p and p:FindFirstChild(jointName)
		if not j and p then
			-- newer avatar rigs: the joint is an AnimationConstraint, sometimes under a different parent
			for _, d in ipairs(model:GetDescendants()) do
				if d.Name == jointName and (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) then
					j = d
					break
				end
			end
		end
		return (j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint"))) and j or nil
	end
	if model:FindFirstChild("UpperTorso") then
		return {
			r15 = true,
			rs = m("RightUpperArm", "RightShoulder"),
			ls = m("LeftUpperArm", "LeftShoulder"),
			re = m("RightLowerArm", "RightElbow"),
			le = m("LeftLowerArm", "LeftElbow"),
			waist = m("UpperTorso", "Waist"),
			neck = m("Head", "Neck"),
			rh = m("RightUpperLeg", "RightHip"),
			lh = m("LeftUpperLeg", "LeftHip"),
			rk = m("RightLowerLeg", "RightKnee"),
			lk = m("LeftLowerLeg", "LeftKnee"),
			root = m("LowerTorso", "Root"),
		}
	end
	local torso = model:FindFirstChild("Torso")
	local function t6(name)
		local j = torso and torso:FindFirstChild(name)
		return (j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint"))) and j or nil
	end
	return { r15 = false, rs = t6("Right Shoulder"), ls = t6("Left Shoulder"), rh = t6("Right Hip"), lh = t6("Left Hip") }
end

-- Apply an extra rotation on a joint for this frame, from its saved original.
--  Motor6D: C0 offset (renders reliably even with fixed-step simulation, where Transform writes get lost).
--  AnimationConstraint (new avatar joints): rotate the joint's Attachment0.
-- Local only (every client animates everyone). If the server changes the joint meanwhile (GIANTS rescales bodies),
-- the new value becomes the base, so a scaled body never gets stretched back.
local saved = {} -- Motor6D / Attachment -> original C0 / CFrame
local written = {} -- Motor6D / Attachment -> what we last wrote
pcall(function()
	Workspace.Retargeting = Enum.AnimatorRetargetingMode.Disabled
end)
local function baseOf(obj: any, current: CFrame): CFrame
	local base, last = saved[obj], written[obj]
	if not base or (last and (current.Position - last.Position).Magnitude > 0.01) then
		base = current
		saved[obj] = base
	end
	return base
end
local function rot(joint: Instance?, r: CFrame)
	if not joint then
		return
	end
	if joint:IsA("Motor6D") then
		local c = baseOf(joint, joint.C0) * r
		joint.C0 = c
		written[joint] = c
	elseif joint:IsA("AnimationConstraint") then
		local a0 = joint.Attachment0
		if a0 then
			local c = baseOf(a0, a0.CFrame) * r
			a0.CFrame = c
			written[a0] = c
		end
	end
end
local function restore(j)
	for _, joint in pairs(j) do
		if typeof(joint) == "Instance" and joint:IsA("Motor6D") then
			if saved[joint] then
				joint.C0 = saved[joint]
			end
			saved[joint], written[joint] = nil, nil
		elseif typeof(joint) == "Instance" and joint:IsA("AnimationConstraint") then
			local a0 = joint.Attachment0
			if a0 and saved[a0] then
				a0.CFrame = saved[a0]
			end
			if a0 then
				saved[a0], written[a0] = nil, nil
			end
		end
	end
end

-- per-character animation state
local tracked = {} -- model -> { j, amb = {}, seed, move?, t0?, frozen? }
local retryAt = {} -- model -> os.clock() when to look for its joints again (rig not built yet)
local function stateOf(model: Model)
	local s = tracked[model]
	if s then
		for _, joint in pairs(s.j) do
			if typeof(joint) == "Instance" and not joint.Parent then
				-- rig rebuilt (respawn / new avatar): find the joints again
				restore(s.j)
				s.j = joints(model)
				break
			end
		end
		return s
	end
	if (retryAt[model] or 0) > os.clock() then
		return nil
	end
	local j = joints(model)
	if not j.rs and not j.ls then
		retryAt[model] = os.clock() + 1
		return nil
	end
	retryAt[model] = nil
	s = { j = j, amb = {}, seed = math.random() * 6.28 }
	tracked[model] = s
	return s
end
local function drop(model)
	local s = tracked[model]
	if s then
		restore(s.j)
		tracked[model] = nil
	end
end

local function play(model: Instance?, kind: string)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not MOVES[kind] then
		return
	end
	local s = stateOf(model)
	if not s then
		return
	end
	s.move, s.t0, s.frozen = kind, os.clock(), nil
end

-- ambient body language targets for one character this frame
local plateY = Config.PLATE_Y
local RUNNING = { [Enum.HumanoidStateType.Running] = true, [Enum.HumanoidStateType.RunningNoPhysics] = true }
local AIR = { [Enum.HumanoidStateType.Freefall] = true, [Enum.HumanoidStateType.Jumping] = true }
local function ambient(model: Model, tiltK: number)
	local out = {}
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return out
	end
	local v = root.AssemblyLinearVelocity
	local pos = root.Position
	if pos.Y < plateY - 5 and v.Y < -8 then
		-- falling off: windmill arms, pedal legs, head back (cartoon fall)
		out.flail, out.spread, out.kick, out.head = 1, 0.7, 1, -0.6
		return out
	end
	if hum.PlatformStand then
		-- knocked down: limp, arms loose, legs apart
		out.spread, out.splay, out.knee, out.head = 0.45, 0.5, 0.35, -0.3
		return out
	end
	local st = hum:GetState()
	if RUNNING[st] then
		out.lean = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / 16, 0, 1) * 0.35
	elseif AIR[st] then
		out.spread = 0.3
	end
	-- steep plate: arms out to keep balance, swaying (only while up on the plate)
	if tiltK > 0 and math.abs(pos.Y - plateY) < 9 and Vector3.new(pos.X, 0, pos.Z).Magnitude < Config.PLATE_RADIUS + 4 then
		out.spread = (out.spread or 0) + 0.75 * tiltK
		out.wobble = tiltK
	end
	return out
end

local rad = math.rad
local function pose(j, w, now: number, seed: number)
	local arm, elbow, lean = w.arm or 0, w.elbow or 0, w.lean or 0
	local twist, stepF, stepB, knee = w.twist or 0, w.stepF or 0, w.stepB or 0, w.knee or 0
	local crouch, sweep, flail, splay, recoil = w.crouch or 0, w.sweep or 0, w.flail or 0, w.splay or 0, w.recoil or 0
	local spread, head, kick, wobble = w.spread or 0, w.head or 0, w.kick or 0, w.wobble or 0
	flail = math.min(flail, 1.2)
	spread = math.min(spread, 1)
	-- windmill: the two arms circle out of phase; legs pedal out of phase
	local fr = flail * math.sin(now * 20 + seed) * rad(70)
	local fl = flail * math.sin(now * 20 + seed + math.pi) * rad(70)
	local kk = kick * math.sin(now * 14 + seed) * rad(40)
	local wob = wobble * math.sin(now * 3.1 + seed)
	spread += 0.12 * wob
	if j.r15 then
		-- arms: forward (+X lifts a hanging arm ahead), swept back (-X), out to the side (Z), flung up on a hit
		local rsx = rad(95) * arm - rad(55) * sweep + rad(40) * recoil + fr
		local lsx = rad(95) * arm - rad(55) * sweep + rad(40) * recoil + fl
		rot(j.rs, CFrame.Angles(rsx, rad(12) * arm, rad(25) * recoil + rad(35) * flail + rad(75) * spread))
		rot(j.ls, CFrame.Angles(lsx, rad(-12) * arm, rad(-25) * recoil - rad(35) * flail - rad(75) * spread))
		rot(j.re, CFrame.Angles(rad(85) * elbow + rad(30) * sweep + rad(15) * spread, 0, 0))
		rot(j.le, CFrame.Angles(rad(85) * elbow + rad(30) * sweep + rad(15) * spread, 0, 0))
		rot(j.waist, CFrame.Angles(rad(-24) * lean + rad(24) * recoil, rad(18) * twist, rad(5) * wob))
		rot(j.neck, CFrame.Angles(rad(-22) * head, 0, 0))
		-- legs: front (left) leg steps forward, back (right) leg pushes back; knees bend; legs splay / pedal
		rot(j.lh, CFrame.Angles(rad(38) * stepF + rad(30) * crouch + kk, 0, rad(-22) * splay))
		rot(j.rh, CFrame.Angles(rad(-30) * stepB + rad(30) * crouch - kk, 0, rad(22) * splay))
		rot(j.lk, CFrame.Angles(rad(-40) * knee - rad(20) * stepF - math.abs(kk) * 0.8, 0, 0))
		rot(j.rk, CFrame.Angles(rad(-40) * knee - math.abs(kk) * 0.8, 0, 0))
		-- whole body dips for the crouch / lunge (Root joint: pelvis down and forward-tilted)
		if j.root then
			rot(j.root, CFrame.new(0, -0.45 * crouch - 0.15 * stepF, 0) * CFrame.Angles(rad(-14) * crouch, 0, 0))
		end
	else
		rot(j.rs, CFrame.Angles(0, 0, rad(90) * arm - rad(40) * sweep + fr + rad(40) * recoil))
		rot(j.ls, CFrame.Angles(0, 0, rad(-90) * arm + rad(40) * sweep - fl - rad(40) * recoil))
		rot(j.lh, CFrame.Angles(0, 0, rad(-30) * stepF + kk))
		rot(j.rh, CFrame.Angles(0, 0, rad(30) * stepB + kk))
	end
end

local AMB_RATE = 9 -- how fast ambient body language blends in / out (per second)
local frameModels = {}
RunService.PreSimulation:Connect(function(dt: number)
	-- runs after the Animator has written this frame's pose: we add on top of it
	local now = os.clock()
	local inRound = ReplicatedStorage:GetAttribute("Phase") == "Round"
	local tiltDeg = tonumber(ReplicatedStorage:GetAttribute("TiltDeg")) or 0
	local tiltK = inRound and math.clamp((tiltDeg - Config.SLIDE_DEADZONE) / math.max(1, Config.MAX_TILT - Config.SLIDE_DEADZONE), 0, 1) or 0
	table.clear(frameModels)
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		if ch and p:GetAttribute("Ghost") ~= true then
			frameModels[ch] = true
		end
	end
	local bots = Workspace:FindFirstChild("TiltBots")
	if bots then
		for _, m in ipairs(bots:GetChildren()) do
			if m:IsA("Model") then
				frameModels[m] = true
			end
		end
	end
	for m, s in pairs(tracked) do
		if s.move then
			frameModels[m] = true -- a move always finishes (test rigs, etc.)
		end
	end
	for m in pairs(tracked) do
		if not frameModels[m] or not m.Parent then
			drop(m)
		end
	end
	local k = 1 - math.exp(-AMB_RATE * math.min(dt, 0.1))
	for model in pairs(frameModels) do
		if not model.Parent then
			continue
		end
		-- ambient targets first: an idle body on a flat plate needs no tracking at all
		local s = tracked[model]
		local target = (s and s.frozen) and EMPTY or ambient(model, tiltK)
		if not s and next(target) == nil then
			continue
		end
		s = stateOf(model)
		if not s then
			continue
		end
		local w = EMPTY
		if s.move then
			local move = MOVES[s.move]
			local t = s.frozen or (now - s.t0)
			if not move or (t > move.dur and not s.frozen) then
				s.move = nil
			else
				w = sampleMove(move, t)
			end
		end
		-- ambient layer, smoothed so it never pops (frozen test poses skip it)
		for ch, v in pairs(target) do
			local cur = s.amb[ch] or 0
			s.amb[ch] = cur + (v - cur) * k
		end
		for ch, cur in pairs(s.amb) do
			if target[ch] == nil then
				local nv = cur - cur * k
				s.amb[ch] = math.abs(nv) > 0.002 and nv or nil
			end
		end
		if next(s.amb) then
			if w == EMPTY then
				w = {}
			end
			local mix = s.move and 0.3 or 1 -- a move owns the body; ambient only tints it
			for ch, v in pairs(s.amb) do
				w[ch] = (w[ch] or 0) + v * mix
			end
		end
		if w == EMPTY and not s.move then
			-- nothing to add: put the joints back exactly and stop tracking until needed
			drop(model)
			continue
		end
		pose(s.j, w, now, s.seed)
	end
end)

-- a quick see-through "push wave" in front of the hands
local fxFolder = Workspace:FindFirstChild("TiltFX_" .. player.UserId) or Workspace
local function pushWave(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	task.delay(0.14, function()
		if not root.Parent then
			return
		end
		local cf = root.CFrame * CFrame.new(0, 0.6, -2.4)
		local p = Instance.new("Part")
		p.Name = "PushWave"
		p.Shape = Enum.PartType.Cylinder
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = WHITE
		p.Transparency = 0.55
		p.Size = Vector3.new(0.1, 1.2, 1.2)
		-- cylinder axis = X; turn it to face along the look direction
		p.CFrame = cf * CFrame.Angles(0, math.rad(90), 0)
		p.Parent = fxFolder
		TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.05, 4.2, 4.2),
			CFrame = cf * CFrame.new(0, 0, -1.6) * CFrame.Angles(0, math.rad(90), 0),
			Transparency = 1,
		}):Play()
		Debris:AddItem(p, 0.3)
	end)
end

---------------------------------------------------------------- hit feel (like battlegrounds / slap games): white flash on the
-- body that got hit, a burst at the contact point, speed streaks while it flies, a tiny FOV kick (no screen shake)
local cam = Workspace.CurrentCamera
local fovBase: number? = nil
local fovUntil = 0
local function fovKick(amount: number, seconds: number)
	cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	fovBase = fovBase or cam.FieldOfView
	fovUntil = os.clock() + seconds
	local base = fovBase :: number
	cam.FieldOfView = base + amount
	TweenService:Create(cam, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
	task.delay(seconds + 0.05, function()
		if os.clock() >= fovUntil and cam then
			cam.FieldOfView = base
			fovBase = nil
		end
	end)
end

local function flash(model: Instance?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local h = Instance.new("Highlight")
	h.Name = "HitFlash"
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.FillColor = WHITE
	h.OutlineColor = WHITE
	h.FillTransparency = 0.15
	h.OutlineTransparency = 0.4
	h.Adornee = model
	h.Parent = model
	TweenService:Create(h, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		FillTransparency = 1,
		OutlineTransparency = 1,
	}):Play()
	Debris:AddItem(h, 0.25)
end

local function shard(pos: Vector3, dir: Vector3, len: number)
	local p = Instance.new("Part")
	p.Name = "HitShard"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = WHITE
	p.Size = Vector3.new(0.18, 0.18, len)
	p.CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, -len / 2)
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, -len * 1.6),
		Size = Vector3.new(0.05, 0.05, len * 0.4),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, 0.25)
end

-- burst where the push lands: an expanding ring facing the pusher + white shards flying out
local function impact(pos: Vector3, from: Vector3?)
	local d = from and Vector3.new(pos.X - from.X, 0, pos.Z - from.Z) or Vector3.zero
	local face = d.Magnitude > 0.1 and d.Unit or Vector3.xAxis
	local ring = Instance.new("Part")
	ring.Name = "HitRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = WHITE
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.12, 1, 1)
	-- cylinder axis = X: point it along the push
	local cf = CFrame.lookAt(pos, pos + face) * CFrame.Angles(0, math.rad(90), 0)
	ring.CFrame = cf
	ring.Parent = fxFolder
	TweenService:Create(ring, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.04, 6.5, 6.5),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.3)
	local right = face:Cross(Vector3.yAxis)
	for i = 1, 7 do
		local a = (i / 7) * math.pi * 2 + math.random() * 0.4
		local dir = (right * math.cos(a) + Vector3.yAxis * math.sin(a)) * 0.8 + face * 0.6
		shard(pos, dir.Unit, 1.4 + math.random() * 0.8)
	end
end

-- speed streaks behind a body that's flying from a push
local function streak(model: Instance?, seconds: number)
	local root = typeof(model) == "Instance" and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "StreakA0"
	a0.Position = Vector3.new(0, 1.4, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "StreakA1"
	a1.Position = Vector3.new(0, -1.4, 0)
	a1.Parent = root
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Lifetime = 0.22
	tr.MinLength = 0.05
	tr.Color = ColorSequence.new(WHITE)
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	tr.LightEmission = 0.4
	tr.FaceCamera = true
	tr.Parent = root
	task.delay(seconds, function()
		tr.Enabled = false
		Debris:AddItem(tr, 0.3)
		Debris:AddItem(a0, 0.3)
		Debris:AddItem(a1, 0.3)
	end)
end

-- DEMO/TEST ONLY (TiltDebug): hold one pose frozen at time t so tests can screenshot it
if DEBUG then
	local probe = Instance.new("BindableEvent")
	probe.Name = "TiltAnimProbe"
	probe.Parent = player
	probe.Event:Connect(function(kind: string?, t: number?)
		local ch = player.Character
		if not ch then
			return
		end
		drop(ch)
		if kind then
			play(ch, kind)
			if tracked[ch] then
				tracked[ch].frozen = t
			end
		end
	end)
end

---------------------------------------------------------------- the button
local gui = Instance.new("ScreenGui")
gui.Name = "PushUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local SIZE = touch and 64 or 76 -- touch: ~64 real px, stacked right above Roblox's jump button

local holder = Instance.new("CanvasGroup") -- rounded clip + one transparency for the whole button
holder.Name = "Push"
holder.AnchorPoint = Vector2.new(1, 1)
-- desktop: just left of the mute button; touch: left of the jump button
holder.Position = touch and UDim2.new(1, -28, 1, -104) or UDim2.new(1, -70, 1, -14)
holder.Size = UDim2.new(0, SIZE, 0, SIZE)
holder.BackgroundColor3 = PANEL
holder.BackgroundTransparency = 0.2
holder.GroupTransparency = 1
holder.Visible = false
holder.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = holder
local scale = Instance.new("UIScale")
scale.Parent = holder

-- cooldown fill (dark, drains downward as it recharges)
local fill = Instance.new("Frame")
fill.Name = "Cooldown"
fill.AnchorPoint = Vector2.new(0, 1)
fill.Position = UDim2.new(0, 0, 1, 0)
fill.Size = UDim2.new(1, 0, 0, 0)
fill.BackgroundColor3 = Color3.new(0, 0, 0)
fill.BackgroundTransparency = 0.45
fill.BorderSizePixel = 0
fill.ZIndex = 3
fill.Parent = holder

local icon = Instance.new("TextLabel")
icon.BackgroundTransparency = 1
icon.Size = UDim2.new(1, 0, 0.5, 0)
icon.Position = UDim2.new(0, 0, 0.1, 0)
icon.Font = FONT
icon.Text = "👐"
icon.TextScaled = true
icon.ZIndex = 2
icon.Parent = holder

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Size = UDim2.new(1, 0, 0.24, 0)
label.Position = UDim2.new(0, 0, 0.6, 0)
label.Font = FONT
label.Text = "PUSH"
label.TextColor3 = WHITE
label.TextScaled = true
label.ZIndex = 2
label.Parent = holder

local btn = Instance.new("TextButton")
btn.Name = "Hit"
btn.BackgroundTransparency = 1
btn.Size = UDim2.new(1, 0, 1, 0)
btn.Text = ""
btn.ZIndex = 5
btn.Parent = holder

-- the outline lives outside the CanvasGroup so it isn't clipped
local ring = Instance.new("Frame")
ring.Name = "PushRing"
ring.AnchorPoint = holder.AnchorPoint
ring.Position = holder.Position
ring.Size = holder.Size
ring.BackgroundTransparency = 1
ring.Visible = false
ring.Parent = gui
local rc = Instance.new("UICorner")
rc.CornerRadius = UDim.new(0.5, 0)
rc.Parent = ring
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2.5
stroke.Color = GOLD
stroke.Transparency = 1
stroke.Parent = ring
local ringScale = Instance.new("UIScale")
ringScale.Parent = ring

-- key hint chip (keyboard only)
local key = Instance.new("TextLabel")
key.Name = "Key"
key.AnchorPoint = Vector2.new(0.5, 0.5)
key.Position = UDim2.new(0.5, 0, 0, -4)
key.Size = UDim2.new(0, 26, 0, 22)
key.BackgroundColor3 = GOLD
key.Font = FONT
key.Text = "F"
key.TextColor3 = PANEL
key.TextScaled = true
key.Visible = not touch
key.Parent = ring
local kc = Instance.new("UICorner")
kc.CornerRadius = UDim.new(0, 6)
kc.Parent = key

local cdEnd, cdTotal = 0, Config.SHOVE_COOLDOWN
local lastPress = 0

local function pressAnim()
	scale.Scale = 0.84
	ringScale.Scale = 0.84
	local ti = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(scale, ti, { Scale = 1 }):Play()
	TweenService:Create(ringScale, ti, { Scale = 1 }):Play()
	stroke.Color = WHITE
	TweenService:Create(stroke, TweenInfo.new(0.35), { Color = GOLD }):Play()
end

local function doPush()
	if DEBUG then
	end
	if ReplicatedStorage:GetAttribute("Phase") ~= "Round" or not holder.Visible then
		return
	end
	local now = os.clock()
	if now < cdEnd or now - lastPress < 0.35 then
		-- still recharging: small "no" wiggle
		TweenService:Create(holder, TweenInfo.new(0.05), { Rotation = 6 }):Play()
		task.delay(0.05, function()
			TweenService:Create(holder, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Rotation = 0 }):Play()
		end)
		return
	end
	lastPress = now
	cdEnd = now + 0.5 -- until the server answers
	cdTotal = 0.5
	pressAnim()
	shoveRemote:FireServer()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
	if ch and root then
		play(ch, "push")
		pushWave(ch)
		Sfx.play("swing", nil, 0.5, 0.95 + math.random() * 0.15)
		-- smooth little lunge (held, not a velocity jolt)
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if look.Magnitude > 1e-3 then
			task.delay(0.08, function()
				if not root.Parent then
					return
				end
				local att = Instance.new("Attachment")
				att.Parent = root
				local lv = Instance.new("LinearVelocity")
				lv.Attachment0 = att
				lv.RelativeTo = Enum.ActuatorRelativeTo.World
				lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
				lv.LineDirection = look.Unit
				lv.LineVelocity = 18
				lv.MaxForce = 1e5
				lv.Parent = root
				task.delay(0.13, function()
					lv:Destroy()
					att:Destroy()
				end)
			end)
		end
	end
end

btn.Activated:Connect(doPush)
ContextActionService:BindAction("TiltShove", function(_, state)
	if state == Enum.UserInputState.Begin and ReplicatedStorage:GetAttribute("Phase") == "Round" then
		doPush()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonX)

-- show only during a round while you're up on the plate; fade in/out
local shown = false
local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	if on then
		holder.Visible = true
		ring.Visible = true
		scale.Scale = 0.6
		ringScale.Scale = 0.6
		local ti = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(holder, TweenInfo.new(0.2), { GroupTransparency = 0 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0.15 }):Play()
		TweenService:Create(scale, ti, { Scale = 1 }):Play()
		TweenService:Create(ringScale, ti, { Scale = 1 }):Play()
	else
		TweenService:Create(holder, TweenInfo.new(0.2), { GroupTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 1 }):Play()
		task.delay(0.21, function()
			if not shown then
				holder.Visible = false
				ring.Visible = false
			end
		end)
	end
end

RunService.RenderStepped:Connect(function()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local onPlate = root ~= nil and hum ~= nil and hum.Health > 0 and root.Position.Y > plateY - 8
		and Vector3.new(root.Position.X, 0, root.Position.Z).Magnitude < Config.PLATE_RADIUS + 12
	setShown(ReplicatedStorage:GetAttribute("Phase") == "Round" and onPlate and player:GetAttribute("Ghost") ~= true)
	-- cooldown fill: full when you just pushed, drains to empty
	local left = cdEnd - os.clock()
	if left > 0 then
		fill.Size = UDim2.new(1, 0, math.clamp(left / math.max(0.05, cdTotal), 0, 1), 0)
		label.Text = cdTotal > 0.6 and string.format("%.1f", left) or "PUSH"
		label.TextColor3 = Color3.fromRGB(200, 200, 205)
	else
		if fill.Size.Y.Scale > 0 then
			fill.Size = UDim2.new(1, 0, 0, 0)
			-- ready again: tiny pop
			label.Text = "PUSH"
			label.TextColor3 = WHITE
			ringScale.Scale = 1.12
			TweenService:Create(ringScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end
end)

---------------------------------------------------------------- DODGE button (Q / gamepad Y): quick dash, pushes miss you for a moment
local dodgeRemote = Remotes:WaitForChild("Dodge") :: RemoteEvent
local DSIZE = touch and 52 or 60
local dodge = Instance.new("TextButton")
dodge.Name = "Dodge"
dodge.AnchorPoint = Vector2.new(1, 1)
-- just left of PUSH (bottom-right corner, never the middle of the screen)
dodge.Position = touch and UDim2.new(1, -28 - SIZE - 10, 1, -104) or UDim2.new(1, -70 - SIZE - 12, 1, -14)
dodge.Size = UDim2.new(0, DSIZE, 0, DSIZE)
dodge.BackgroundColor3 = PANEL
dodge.BackgroundTransparency = 0.2
dodge.AutoButtonColor = false
dodge.Font = FONT
dodge.Text = "DODGE"
dodge.TextColor3 = WHITE
dodge.TextScaled = true
dodge.Visible = false
dodge.Parent = gui
local dcorner = Instance.new("UICorner")
dcorner.CornerRadius = UDim.new(0.5, 0)
dcorner.Parent = dodge
local dpad = Instance.new("UIPadding")
dpad.PaddingLeft = UDim.new(0.14, 0)
dpad.PaddingRight = UDim.new(0.14, 0)
dpad.PaddingTop = UDim.new(0.3, 0)
dpad.PaddingBottom = UDim.new(0.3, 0)
dpad.Parent = dodge
local dstroke = Instance.new("UIStroke")
dstroke.Thickness = 2
dstroke.Color = Color3.fromRGB(200, 200, 205)
dstroke.Transparency = 0.2
dstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
dstroke.Parent = dodge
local dfill = Instance.new("Frame")
dfill.Name = "Cooldown"
dfill.AnchorPoint = Vector2.new(0, 1)
dfill.Position = UDim2.new(0, 0, 1, 0)
dfill.Size = UDim2.new(1, 0, 0, 0)
dfill.BackgroundColor3 = Color3.new(0, 0, 0)
dfill.BackgroundTransparency = 0.45
dfill.BorderSizePixel = 0
dfill.Parent = dodge
local dfc = Instance.new("UICorner")
dfc.CornerRadius = UDim.new(0.5, 0)
dfc.Parent = dfill
local dkey = Instance.new("TextLabel")
dkey.AnchorPoint = Vector2.new(0.5, 0.5)
dkey.Position = UDim2.new(0.5, 0, 0, -4)
dkey.Size = UDim2.new(0, 22, 0, 20)
dkey.BackgroundColor3 = Color3.fromRGB(200, 200, 205)
dkey.Font = FONT
dkey.Text = "Q"
dkey.TextColor3 = PANEL
dkey.TextScaled = true
dkey.Visible = not touch
dkey.Parent = dodge
local dkc = Instance.new("UICorner")
dkc.CornerRadius = UDim.new(0, 6)
dkc.Parent = dkey
local dodgeEnd, dodgeTotal, dodgePress = 0, Config.DODGE_COOLDOWN, 0

local function doDodge()
	if ReplicatedStorage:GetAttribute("Phase") ~= "Round" or not dodge.Visible then
		return
	end
	local now = os.clock()
	if now < dodgeEnd or now - dodgePress < 0.3 then
		return
	end
	dodgePress = now
	dodgeEnd = now + 0.4
	dodgeTotal = 0.4
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
	local dir = hum and hum.MoveDirection or Vector3.zero
	if dir.Magnitude < 0.1 and root then
		dir = root.CFrame.LookVector
	end
	dodgeRemote:FireServer(Vector3.new(dir.X, 0, dir.Z))
end
dodge.Activated:Connect(doDodge)
ContextActionService:BindAction("TiltDodge", function(_, state)
	if state == Enum.UserInputState.Begin and ReplicatedStorage:GetAttribute("Phase") == "Round" then
		doDodge()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)

-- short white streak behind a dodging body (every client sees it)
local dust, dizzy
local function dodgeFx(model: Instance?)
	local root = typeof(model) == "Instance" and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	dust(root)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.2, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.2, 0)
	a1.Parent = root
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Lifetime = 0.25
	tr.Color = ColorSequence.new(WHITE)
	tr.Transparency = NumberSequence.new(0.35, 1)
	tr.LightEmission = 0.3
	tr.Parent = root
	task.delay(0.45, function()
		tr:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
end

-- small dust puff at the feet (dodge take-off)
dust = function(root: BasePart)
	for i = 1, 5 do
		local d = Instance.new("Part")
		d.Name = "Dust"
		d.Shape = Enum.PartType.Ball
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		d.Material = Enum.Material.SmoothPlastic
		d.Color = Color3.fromRGB(235, 232, 226)
		d.Transparency = 0.35
		local a = i / 5 * math.pi * 2
		local base = root.Position + Vector3.new(0, -2.6, 0)
		d.Size = Vector3.new(0.8, 0.8, 0.8)
		d.CFrame = CFrame.new(base)
		d.Parent = fxFolder
		TweenService:Create(d, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(base + Vector3.new(math.cos(a) * 2.2, 0.5, math.sin(a) * 2.2)),
			Size = Vector3.new(1.8, 1.8, 1.8),
			Transparency = 1,
		}):Play()
		Debris:AddItem(d, 0.4)
	end
end

-- dizzy stars circling the head (missed push)
dizzy = function(model: Instance?, seconds: number)
	local head = typeof(model) == "Instance" and model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local stars = {}
	for i = 1, 3 do
		local s = Instance.new("Part")
		s.Name = "DizzyStar"
		s.Shape = Enum.PartType.Ball
		s.Anchored = true
		s.CanCollide = false
		s.CanQuery = false
		s.CanTouch = false
		s.CastShadow = false
		s.Material = Enum.Material.Neon
		s.Color = GOLD
		s.Size = Vector3.new(0.45, 0.45, 0.45)
		s.Parent = fxFolder
		stars[i] = s
	end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > seconds + 0.25 or not head.Parent then
			conn:Disconnect()
			for _, s in ipairs(stars) do
				s:Destroy()
			end
			return
		end
		for i, s in ipairs(stars) do
			local a = t * 7 + i * math.pi * 2 / 3
			s.CFrame = CFrame.new(head.Position + Vector3.new(math.cos(a) * 1.3, 1.1 + math.sin(t * 9 + i) * 0.15, math.sin(a) * 1.3))
			s.Transparency = t > seconds and (t - seconds) / 0.25 or 0
		end
	end)
end

RunService.RenderStepped:Connect(function()
	dodge.Visible = holder.Visible and shown
	local left = dodgeEnd - os.clock()
	if left > 0 then
		dfill.Size = UDim2.new(1, 0, math.clamp(left / math.max(0.05, dodgeTotal), 0, 1), 0)
		dodge.TextColor3 = Color3.fromRGB(170, 170, 176)
	else
		dfill.Size = UDim2.new(1, 0, 0, 0)
		dodge.TextColor3 = WHITE
	end
end)

---------------------------------------------------------------- events
Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(kind: string, data)
	if kind == "DodgeGo" and type(data) == "table" then
		local ch = player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and typeof(data.vel) == "Vector3" then
			local att = Instance.new("Attachment")
			att.Parent = root
			local lv = Instance.new("LinearVelocity")
			lv.Attachment0 = att
			lv.RelativeTo = Enum.ActuatorRelativeTo.World
			lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
			lv.VectorVelocity = data.vel
			lv.MaxForce = 1e6
			lv.Parent = root
			task.delay(math.clamp(tonumber(data.burst) or 0.16, 0.05, 0.4), function()
				lv:Destroy()
				att:Destroy()
			end)
		end
		local cd = tonumber(data.cd) or Config.DODGE_COOLDOWN
		dodgeEnd = os.clock() + cd
		dodgeTotal = cd
		return
	elseif kind == "DodgeCd" and type(data) == "table" then
		local cd = tonumber(data.cd) or 0
		dodgeEnd = os.clock() + cd
		dodgeTotal = math.max(cd, 0.4)
		return
	elseif kind == "DodgeFx" and type(data) == "table" then
		play(data.model, "dodge")
		dodgeFx(data.model)
		local r = typeof(data.model) == "Instance" and data.model:FindFirstChild("HumanoidRootPart")
		if r then
			Sfx.play("dash", r, 2.2, 0.95 + math.random() * 0.15)
		end
		return
	elseif kind == "Whiffed" and type(data) == "table" then
		-- missed push: everyone sees the over-reach + windmill + dizzy stars
		local stun = tonumber(data.stun) or 0.9
		play(data.model, "whiff")
		dizzy(data.model, stun)
		local r = typeof(data.model) == "Instance" and data.model:FindFirstChild("HumanoidRootPart")
		if r then
			-- over-reach whoosh -> cartoon slide-whistle down -> face-plant thud -> little birds while dizzy
			Sfx.play("swing", r, 0.45, 0.85)
			Sfx.play("slideWhistle", r, 2.6)
			task.delay(0.38, function()
				if r.Parent then
					Sfx.play("thud", r, 1.0)
					local birds = Sfx.play("birds", r, 1.1, 1.15)
					if birds then
						task.delay(stun + 0.2, function()
							pcall(function()
								TweenService:Create(birds, TweenInfo.new(0.25), { Volume = 0 }):Play()
							end)
						end)
						Debris:AddItem(birds, stun + 0.6)
					end
				end
			end)
		end
		return
	end
	if kind == "ShoveResult" and type(data) == "table" then
		if DEBUG then
		end
		local cd = tonumber(data.cd) or 0
		cdEnd = os.clock() + cd
		cdTotal = cd > 0.6 and (tonumber(data.total) or cd) or cd
		if data.ok then
			-- landed it: tiny FOV kick (impact feel without shaking the screen) + gold flash on the button
			fovKick(-4, 0.22)
			stroke.Color = WHITE
			holder.BackgroundColor3 = GOLD
			TweenService:Create(holder, TweenInfo.new(0.35), { BackgroundColor3 = PANEL }):Play()
		end
	elseif kind == "Shoved" and type(data) == "table" then
		if data.byId ~= player.UserId then
			play(data.byModel, "push") -- my own push already played on press
			if typeof(data.byModel) == "Instance" and data.byModel:IsA("Model") then
				pushWave(data.byModel)
			end
		end
		-- the hit lands with the hands (~0.12 s into the push): flash, burst, sound, streaks, recoil
		task.delay(0.12, function()
			local to = data.toModel
			play(to, "hit")
			flash(to)
			local tr = typeof(to) == "Instance" and to:FindFirstChild("HumanoidRootPart") :: BasePart?
			local at = tr and tr.Position or (typeof(data.pos) == "Vector3" and data.pos or nil)
			if at then
				impact(at + Vector3.new(0, 0.6, 0), typeof(data.from) == "Vector3" and data.from or nil)
				Sfx.play(math.random() < 0.5 and "punch" or "punch2", at, 0.75, 0.92 + math.random() * 0.16)
			end
			streak(to, 0.5)
			if to == player.Character then
				fovKick(6, 0.35)
			end
		end)
	end
end)

-- DEMO/TEST ONLY (TiltDebug): lets a test pilot press PUSH / DODGE exactly like a player would (same code path)
if DEBUG then
	local act = Instance.new("BindableEvent")
	act.Name = "TiltActProbe"
	act.Parent = player
	act.Event:Connect(function(what: string)
		if what == "push" then
			doPush()
		elseif what == "dodge" then
			doDodge()
		end
	end)
end
