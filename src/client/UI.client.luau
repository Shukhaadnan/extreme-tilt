-- UI + local feel: HUD (phase, timer, players left, tilt meter), big centre messages, fall feed, camera shake on
-- impacts, sliding of the local character when the plate is steep, music + mute button.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local TiltMath = require(ReplicatedStorage:WaitForChild("TiltMath"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))
local Hud = require(ReplicatedStorage:WaitForChild("Hud"))
local Objects = require(ReplicatedStorage:WaitForChild("Objects"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "TiltUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local FONT = Enum.Font.FredokaOne
-- calm palette: charcoal panels, white text, ONE gold accent, red only for danger
local PINK = Color3.fromRGB(235, 80, 70) -- danger red (name kept for brevity)
local GOLD = Color3.fromRGB(226, 190, 112)
local BLUE = Color3.fromRGB(255, 255, 255) -- thin panel outline
local PANEL = Color3.fromRGB(22, 22, 26)
local WHITE = Color3.fromRGB(255, 255, 255)

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = p
	return c
end
local function stroke(p, t, col)
	local s = Instance.new("UIStroke")
	s.Thickness = t or 3
	s.Color = col or Color3.fromRGB(20, 20, 40)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = p
	return s
end
local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	for k, v in pairs(props) do
		(l :: any)[k] = v
	end
	l.Parent = parent
	local s = Instance.new("UIStroke")
	s.Thickness = 1.5
	s.Color = Color3.fromRGB(0, 0, 0)
	s.Transparency = 0.45
	s.Parent = l
	return l
end

local showDaily -- defined below (daily reward popup)
local setGhost, ghostLeft -- defined below (ghost mode)
local showLurch -- defined below (lurch warning arrow)

---------------------------------------------------------------- top HUD
local top = Instance.new("Frame")
top.Name = "Top"
top.AnchorPoint = Vector2.new(0.5, 0)
top.Position = UDim2.new(0.5, 0, 0, 8)
top.Size = UDim2.new(0, 300, 0, 54)
top.BackgroundColor3 = PANEL
top.BackgroundTransparency = 0.3
top.Parent = gui
corner(top, 16)
stroke(top, 1.5, BLUE).Transparency = 0.75
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(300, 54)
sizeLimit.Parent = top
Hud.attach(top)
local phaseLabel = label(top, { Name = "Phase", Size = UDim2.new(1, -20, 0.5, 0), Position = UDim2.new(0, 10, 0, 4), Text = "TILT" })
local infoLabel = label(top, {
	Name = "Info",
	Size = UDim2.new(1, -20, 0.38, 0),
	Position = UDim2.new(0, 10, 0.55, 0),
	Text = "",
	TextColor3 = GOLD,
})

-- tilt meter (right side)
local meter = Instance.new("Frame")
meter.Name = "TiltMeter"
meter.AnchorPoint = Vector2.new(1, 0.5)
meter.Position = UDim2.new(1, -14, 0.42, 0)
meter.Size = UDim2.new(0, 26, 0, 170)
meter.BackgroundColor3 = PANEL
meter.BackgroundTransparency = 0.3
meter.Visible = false
meter.Parent = gui
Hud.attach(meter)
corner(meter, 10)
stroke(meter, 1.5, BLUE).Transparency = 0.75
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.AnchorPoint = Vector2.new(0.5, 1)
fill.Position = UDim2.new(0.5, 0, 1, -4)
fill.Size = UDim2.new(1, -8, 0, 0)
fill.BackgroundColor3 = WHITE
fill.Parent = meter
corner(fill, 8)
local dangerLine = Instance.new("Frame")
dangerLine.AnchorPoint = Vector2.new(0.5, 0.5)
dangerLine.Size = UDim2.new(1, 6, 0, 3)
dangerLine.Position = UDim2.new(0.5, 0, 1 - Config.DANGER_TILT / Config.MAX_TILT, 0)
dangerLine.BackgroundColor3 = PINK
dangerLine.BorderSizePixel = 0
dangerLine.Parent = meter
local meterLabel = label(meter, { Size = UDim2.new(0, 56, 0, 22), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 5), Text = "0°" })
local meterTitle = label(meter, { Size = UDim2.new(0, 56, 0, 18), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -5), Text = "TILT" })
local _ = meterTitle

-- red edge glow when the plate is dangerously steep
local danger = Instance.new("Frame")
danger.Name = "Danger"
danger.Size = UDim2.fromScale(1, 1)
danger.BackgroundTransparency = 1
danger.Parent = gui
local dangerStroke = Instance.new("UIStroke")
dangerStroke.Thickness = 18
dangerStroke.Color = PINK
dangerStroke.Transparency = 1
dangerStroke.Parent = danger

---------------------------------------------------------------- centre messages
local big = label(gui, {
	Name = "Big",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.2, 0),
	Size = UDim2.new(0.6, 0, 0.075, 0),
	Text = "",
	TextTransparency = 1,
})
big:FindFirstChildOfClass("UIStroke").Thickness = 2
local bigLimit = Instance.new("UITextSizeConstraint")
bigLimit.MaxTextSize = 58
bigLimit.Parent = big
local sub = label(gui, {
	Name = "Sub",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.26, 0),
	Size = UDim2.new(0.55, 0, 0.038, 0),
	Text = "",
	TextTransparency = 1,
	TextColor3 = GOLD,
})
local subLimit = Instance.new("UITextSizeConstraint")
subLimit.MaxTextSize = 28
subLimit.Parent = sub

local msgToken = 0
local function show(text: string, color: Color3?, subText: string?, seconds: number?)
	msgToken += 1
	local my = msgToken
	big.Text = text
	big.TextColor3 = color or Color3.new(1, 1, 1)
	big.TextTransparency = 0
	big:FindFirstChildOfClass("UIStroke").Transparency = 0.3
	sub.Text = subText or ""
	sub.TextTransparency = subText and 0 or 1
	sub:FindFirstChildOfClass("UIStroke").Transparency = subText and 0.3 or 1
	big.Size = UDim2.new(0.4, 0, 0.05, 0)
	TweenService:Create(big, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0.6, 0, 0.075, 0) }):Play()
	task.delay(seconds or 1.6, function()
		if my ~= msgToken then
			return
		end
		local ti = TweenInfo.new(0.35)
		TweenService:Create(big, ti, { TextTransparency = 1 }):Play()
		TweenService:Create(big:FindFirstChildOfClass("UIStroke"), ti, { Transparency = 1 }):Play()
		TweenService:Create(sub, ti, { TextTransparency = 1 }):Play()
		TweenService:Create(sub:FindFirstChildOfClass("UIStroke"), ti, { Transparency = 1 }):Play()
	end)
end

---------------------------------------------------------------- fall feed (left)
local feed = Instance.new("Frame")
feed.Name = "Feed"
feed.BackgroundTransparency = 1
feed.Position = UDim2.new(0, 12, 0.36, Hud.LEFT_COL_H + 8) -- under coins + SHOP + drop grid
feed.Size = UDim2.new(0, 230, 0, 170)
feed.Parent = gui
Hud.attach(feed)
local function placeFeed()
	feed.Position = UDim2.new(0, 12, 0.36, math.floor((Hud.LEFT_COL_H + 8) * Hud.scale()))
end
Hud.onChange(placeFeed)
placeFeed()
local feedList = Instance.new("UIListLayout")
feedList.VerticalAlignment = Enum.VerticalAlignment.Top
feedList.Padding = UDim.new(0, 4)
feedList.SortOrder = Enum.SortOrder.LayoutOrder
feedList.Parent = feed
local feedN = 0
local FALL_LINES = { "%s slid off!", "%s went for a swim", "%s fell off the plate", "bye %s 👋", "%s took the scenic route down" }
local function addFeed(text: string, color: Color3?)
	feedN += 1
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundColor3 = PANEL
	row.BackgroundTransparency = 0.35
	row.LayoutOrder = -feedN
	row.Parent = feed
	corner(row, 8)
	local l = label(row, { Size = UDim2.new(1, -12, 1, -6), Position = UDim2.new(0, 6, 0, 3), Text = text, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color or Color3.new(1, 1, 1) })
	local _ = l
	local rows = {}
	for _, c in ipairs(feed:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(rows, c)
		end
	end
	if #rows > 5 then
		table.sort(rows, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		rows[#rows]:Destroy()
	end
	task.delay(6, function()
		if row.Parent then
			TweenService:Create(row, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			task.wait(0.4)
			row:Destroy()
		end
	end)
end

---------------------------------------------------------------- mute button
local muteBtn = Instance.new("TextButton")
muteBtn.Name = "Mute"
-- desktop: bottom-right corner; touch: top-right (the bottom-right corner is Roblox's jump button)
muteBtn.AnchorPoint = Hud.touch() and Vector2.new(1, 0) or Vector2.new(1, 1)
muteBtn.Position = Hud.touch() and UDim2.new(1, -12, 0, 12) or UDim2.new(1, -14, 1, -14)
muteBtn.Size = UDim2.new(0, 44, 0, 44)
muteBtn.BackgroundColor3 = PANEL
muteBtn.BackgroundTransparency = 0.3
muteBtn.Font = FONT
muteBtn.TextScaled = true
muteBtn.TextColor3 = Color3.new(1, 1, 1)
muteBtn.Text = "🔊"
muteBtn.Parent = gui
Hud.attach(muteBtn)
corner(muteBtn, 12)
stroke(muteBtn, 1.5, BLUE).Transparency = 0.75
muteBtn.Activated:Connect(function()
	local m = Sfx.toggleMuted()
	muteBtn.Text = m and "🔇" or "🔊"
end)

---------------------------------------------------------------- sounds / music
Sfx.init()
Sfx.preload()
Remotes:WaitForChild("PlaySfx").OnClientEvent:Connect(function(name, target, volume, pitch)
	Sfx.play(name, target, volume, pitch)
end)
task.delay(1, function()
	Sfx.music("musicHappyAdventure")
end)

---------------------------------------------------------------- camera shake
local shakeUntil, shakePower = 0, 0
-- sir Oct 15: "too much screen shake" -> everything is ~1/3 as strong and capped
local SHAKE_SCALE = 0.35
local SHAKE_MAX = 0.3
local function shake(power: number, seconds: number)
	shakePower = math.max(shakePower, math.min(power * SHAKE_SCALE, SHAKE_MAX))
	shakeUntil = math.max(shakeUntil, os.clock() + math.min(seconds, 1.2))
end
local shakeRng = Random.new()

---------------------------------------------------------------- notifications from the server
local inRound = false
---------------------------------------------------------------- ghost mode: fallen players drop junk from above
local ghostOn = false
local ghostCdEnd = 0
local ghostLeftN = 0
local ghostBtn = Instance.new("TextButton")
ghostBtn.Name = "GhostDrop"
ghostBtn.AnchorPoint = Vector2.new(1, 1)
ghostBtn.Position = Hud.touch() and UDim2.new(1, -28, 1, -104) or UDim2.new(1, -70, 1, -14)
ghostBtn.Size = UDim2.new(0, 120, 0, 52)
ghostBtn.BackgroundColor3 = PANEL
ghostBtn.BackgroundTransparency = 0.15
ghostBtn.Font = FONT
ghostBtn.TextScaled = true
ghostBtn.TextColor3 = WHITE
ghostBtn.Text = "👻 DROP (F)"
ghostBtn.Visible = false
ghostBtn.AutoButtonColor = true
ghostBtn.Parent = gui
corner(ghostBtn, 14)
stroke(ghostBtn, 1.5, GOLD)
Hud.attach(ghostBtn)
local ghostTarget: Part? = nil

local function ghostFire()
	if not ghostOn or os.clock() < ghostCdEnd or ghostLeftN <= 0 then
		return
	end
	Remotes:WaitForChild("Ghost"):FireServer()
	Sfx.play("swoosh", nil, 0.4)
end
ghostBtn.Activated:Connect(ghostFire)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not ghostOn then
		return
	end
	if input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonX or input.UserInputType == Enum.UserInputType.MouseButton1 then
		ghostFire()
	end
end)

setGhost = function(on: boolean, data)
	ghostOn = on
	ghostBtn.Visible = on
	if on then
		ghostLeftN = tonumber(data and data.max) or 8
		ghostCdEnd = os.clock() + 1.5
		show("YOU'RE A GHOST 👻", GOLD, "Press F / tap to drop junk on the ones still standing!", 2.6)
		if not ghostTarget then
			local t = Instance.new("Part")
			t.Name = "GhostTarget"
			t.Shape = Enum.PartType.Cylinder
			t.Size = Vector3.new(0.2, 5, 5)
			t.Anchored = true
			t.CanCollide = false
			t.CanQuery = false
			t.CanTouch = false
			t.Material = Enum.Material.Neon
			t.Color = Color3.fromRGB(235, 96, 84)
			t.Transparency = 0.45
			t.Parent = Workspace
			ghostTarget = t
		end
	else
		if ghostTarget then
			ghostTarget:Destroy()
			ghostTarget = nil
		end
	end
end

ghostLeft = function(data)
	ghostLeftN = tonumber(data.left) or ghostLeftN
	ghostCdEnd = os.clock() + (tonumber(data.cd) or 0)
end

local ghostParams = RaycastParams.new()
ghostParams.FilterType = Enum.RaycastFilterType.Include
RunService.RenderStepped:Connect(function()
	if not ghostOn then
		return
	end
	local left = ghostCdEnd - os.clock()
	if ghostLeftN <= 0 then
		ghostBtn.Text = "👻 NO JUNK LEFT"
	elseif left > 0 then
		ghostBtn.Text = string.format("👻 %.1f", left)
	else
		ghostBtn.Text = string.format("👻 DROP x%d", ghostLeftN)
	end
	-- red target on the plate right below you
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local world = Workspace:FindFirstChild("TiltWorld")
	local plate = world and world:FindFirstChild("Plate")
	if ghostTarget and root and plate then
		ghostParams.FilterDescendantsInstances = { plate }
		local hit = Workspace:Raycast(root.Position, Vector3.new(0, -120, 0), ghostParams)
		if hit then
			ghostTarget.Transparency = 0.45
			ghostTarget.CFrame = CFrame.new(hit.Position + hit.Normal * 0.15, hit.Position + hit.Normal * 2) * CFrame.Angles(0, math.pi / 2, 0)
		else
			ghostTarget.Transparency = 1
		end
	end
end)

---------------------------------------------------------------- lurch warning: a red arrow on the plate pointing to the side that's about to drop
showLurch = function(data)
	local dx, dz = tonumber(data.dx) or 1, tonumber(data.dz) or 0
	local warn = tonumber(data.warn) or 1
	local secs = tonumber(data.seconds) or 2
	local dir = Vector3.new(dx, 0, dz)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(1, 0, 0)
	end
	dir = dir.Unit
	local world = Workspace:FindFirstChild("TiltWorld")
	local plate = world and world:FindFirstChild("Plate")
	local surf = plate and plate:FindFirstChild("Surface", true)
	local y = (surf and surf:IsA("BasePart")) and (surf.Position.Y + surf.Size.Y / 2 + 0.4) or 61
	local m = Instance.new("Model")
	m.Name = "LurchArrow"
	local red = Color3.fromRGB(235, 96, 84)
	local function ap(size: Vector3, cf: CFrame)
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = red
		p.Transparency = 0.25
		p.Parent = m
		return p
	end
	local base = CFrame.lookAt(Vector3.new(0, y, 0), Vector3.new(dir.X, y, dir.Z))
	ap(Vector3.new(2.4, 0.3, 12), base * CFrame.new(0, 0, -7))
	-- arrow head: two slanted bars
	ap(Vector3.new(1.6, 0.3, 6.5), base * CFrame.new(-1.9, 0, -13.4) * CFrame.Angles(0, math.rad(-40), 0))
	ap(Vector3.new(1.6, 0.3, 6.5), base * CFrame.new(1.9, 0, -13.4) * CFrame.Angles(0, math.rad(40), 0))
	m.Parent = Workspace
	show("LEAN!", PINK, "The plate is about to lurch", warn + 0.4)
	task.spawn(function()
		local t0 = os.clock()
		while m.Parent and os.clock() - t0 < warn do
			local tr = ((os.clock() - t0) * 6) % 2 < 1 and 0.15 or 0.6
			for _, p in ipairs(m:GetChildren()) do
				(p :: BasePart).Transparency = tr
			end
			task.wait(0.05)
		end
		for _, p in ipairs(m:GetChildren()) do
			(p :: BasePart).Transparency = 0.35
		end
		shake(0.3, secs * 0.4)
	end)
	task.delay(warn + secs, function()
		m:Destroy()
	end)
end

---------------------------------------------------------------- daily reward popup (7-day track, today highlighted)
showDaily = function(data)
	local old = gui:FindFirstChild("Daily")
	if old then
		old:Destroy()
	end
	local track = type(data.track) == "table" and data.track or {}
	local day = tonumber(data.day) or 1
	local box = Instance.new("Frame")
	box.Name = "Daily"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.Size = UDim2.new(0, 520, 0, 210)
	box.BackgroundColor3 = PANEL
	box.BackgroundTransparency = 0.08
	box.ZIndex = 20
	box.Parent = gui
	corner(box, 16)
	stroke(box, 1.5, GOLD)
	local sc = Hud.attach(box)
	label(box, { Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 0, 12), Text = "DAILY REWARD", TextColor3 = GOLD, ZIndex = 21 })
	label(box, {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.new(0, 10, 0, 52),
		Text = "Day " .. day .. " of 7  ·  come back tomorrow for more",
		ZIndex = 21,
	})
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.new(0, 14, 0, 88)
	row.Size = UDim2.new(1, -28, 0, 70)
	row.ZIndex = 21
	row.Parent = box
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.Padding = UDim.new(0, 6)
	lay.Parent = row
	for i, r in ipairs(track) do
		local c = Instance.new("Frame")
		c.Size = UDim2.new(0, 64, 0, 70)
		c.BackgroundColor3 = i == day and GOLD or Color3.fromRGB(44, 44, 50)
		c.BackgroundTransparency = i < day and 0.5 or 0
		c.ZIndex = 21
		c.Parent = row
		corner(c, 10)
		label(c, { Size = UDim2.new(1, -6, 0, 18), Position = UDim2.new(0, 3, 0, 4), Text = "DAY " .. i, ZIndex = 22, TextColor3 = i == day and PANEL or WHITE })
		label(c, {
			Size = UDim2.new(1, -6, 0, 24),
			Position = UDim2.new(0, 3, 0, 24),
			Text = tostring(r.coins or 0),
			ZIndex = 22,
			TextColor3 = i == day and PANEL or GOLD,
		})
		label(c, {
			Size = UDim2.new(1, -6, 0, 16),
			Position = UDim2.new(0, 3, 0, 50),
			Text = r.token and ("+" .. string.upper(r.token)) or "coins",
			ZIndex = 22,
			TextColor3 = i == day and PANEL or WHITE,
		})
	end
	local ok = Instance.new("TextButton")
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position = UDim2.new(0.5, 0, 1, -10)
	ok.Size = UDim2.new(0, 160, 0, 32)
	ok.BackgroundColor3 = GOLD
	ok.Font = FONT
	ok.TextScaled = true
	ok.TextColor3 = PANEL
	ok.Text = "CLAIM +" .. tostring(data.coins or 0)
	ok.ZIndex = 22
	ok.Parent = box
	corner(ok, 10)
	Sfx.play("chimes", nil, 0.6)
	local base = sc.Scale
	sc.Scale = base * 0.6
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = base }):Play()
	local function close()
		if box.Parent then
			Sfx.play("coin", nil, 0.7)
			box:Destroy()
		end
	end
	ok.Activated:Connect(close)
	task.delay(12, close)
end

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(kind: string, data)
	data = data or {}
	if kind == "RoundStart" then
		inRound = true
		show("GET READY", WHITE, "Run away from whatever lands", 1.4)
	elseif kind == "Countdown" then
		task.spawn(function()
			for i = data.seconds or 3, 1, -1 do
				show(tostring(i), Color3.new(1, 1, 1), nil, 0.8)
				Sfx.play("beep", nil, 2.2, 1)
				task.wait(1)
			end
		end)
	elseif kind == "Go" then
		show("GO!", WHITE, "Keep the plate level", 1.2)
		Sfx.play("beep", nil, 2.6, 1.5)
		Sfx.play("notify", nil, 0.5)
	elseif kind == "Drop" then
		if data.by then
			show(string.format("%s IS FALLING!", data.label or "SOMETHING"), WHITE, data.by .. " dropped it! Run!", 1.6)
			addFeed(data.by .. " dropped " .. string.lower(data.label or "something"), GOLD)
		else
			show(string.format("%s!", data.label or "SOMETHING"), WHITE, nil, 1.1)
		end
	elseif kind == "ShrinkWarn" then
		show("THE EDGE IS BREAKING!", PINK, "Move to the middle!", 2.2)
	elseif kind == "Shrink" then
		shake(0.5, 0.6)
		addFeed("The plate got smaller!", GOLD)
	elseif kind == "Shoved" then
		if data.byId == player.UserId then
			addFeed("You shoved " .. tostring(data.to), WHITE)
		end
	elseif kind == "Nuke" then
		if data.byId == player.UserId then
			show("NUKE INCOMING!", GOLD, "You're shielded. Watch them fly!", 2)
		else
			show("NUKE INCOMING!", PINK, (data.by or "Someone") .. " launched a nuke! HOLD ON!", 2)
		end
		addFeed((data.by or "Someone") .. " launched a NUKE", GOLD)
		shake(0.35, 1.8)
	elseif kind == "Coins" then
		addFeed("+" .. tostring(data.amount or 0) .. " coins", GOLD)
		Sfx.play("coin", nil, 0.6)
	elseif kind == "Revived" then
		if data.userId == player.UserId then
			inRound = true
			show("SECOND CHANCE!", GOLD, "Back on the plate", 1.6)
		else
			addFeed((data.name or "?") .. " used a Second Chance", GOLD)
		end
	elseif kind == "Bought" then
		show("THANK YOU!", GOLD, "You got: " .. tostring(data.name or ""), 2)
		Sfx.play("cashRegister", nil, 0.6)
	elseif kind == "Impact" then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local power = data.power or 2
		local dist = (root and data.pos) and (root.Position - data.pos).Magnitude or 200
		if dist < 140 then
			shake(math.clamp(power * 0.12, 0.15, 1) * (1 - dist / 160), 0.35 + power * 0.04)
		end
	elseif kind == "Fell" then
		local line = FALL_LINES[math.random(1, #FALL_LINES)]
		local name = data.name or "?"
		if data.userId == player.UserId then
			inRound = false
			show("YOU FELL!", PINK, nil, 1.6)
			Sfx.play("fahhh", nil, 0.7)
			addFeed(string.format(line, "You"), PINK)
		else
			if data.by then
				addFeed(string.format("%s knocked %s off", tostring(data.by), name), GOLD)
			else
				addFeed(string.format(line, name), data.bot and Color3.fromRGB(210, 210, 214) or WHITE)
			end
		end
	elseif kind == "Mod" then
		task.delay(1.5, function()
			show(tostring(data.title or "TWIST"), GOLD, tostring(data.sub or ""), 2.2)
			Sfx.play("vineBoom", nil, 0.4)
		end)
	elseif kind == "KO" then
		show("KO!", GOLD, string.format("You knocked %s off  ·  +%d", tostring(data.to), tonumber(data.coins) or 0), 1.4)
		Sfx.play("coin", nil, 0.7)
	elseif kind == "CrownSteal" then
		if data.byId == player.UserId then
			show("CROWN STOLEN!", GOLD, string.format("You took it from %s  ·  +%d", tostring(data.from), tonumber(data.coins) or 0), 2)
		else
			addFeed(string.format("👑 %s stole the crown from %s", tostring(data.by), tostring(data.from)), GOLD)
		end
	elseif kind == "CrownNew" or kind == "CrownKept" then
		addFeed(string.format(kind == "CrownNew" and "👑 %s wins the crown" or "👑 %s kept the crown", tostring(data.name)), GOLD)
	elseif kind == "CrownLost" then
		addFeed(string.format("👑 %s dropped the crown", tostring(data.name)), WHITE)
	elseif kind == "Pickup" then
		show(tostring(data.title or ""), GOLD, tostring(data.sub or ""), 1.6)
	elseif kind == "PickupUsed" then
		addFeed(string.format("%s grabbed %s", tostring(data.name), string.lower(tostring(data.kind))), WHITE)
	elseif kind == "Dodged" then
		if data.toId == player.UserId then
			show("DODGED!", GOLD, tostring(data.by) .. " missed you", 1)
		else
			addFeed(string.format("%s dodged %s", tostring(data.to), tostring(data.by)), WHITE)
		end
	elseif kind == "Blocked" then
		if data.byId == player.UserId then
			show("BLOCKED!", WHITE, "They have heavy boots", 0.9)
		end
	elseif kind == "Ghost" then
		setGhost(data.on == true, data)
	elseif kind == "GhostLeft" then
		ghostLeft(data)
	elseif kind == "PlanNote" then
		show(tostring(data.title or ""), GOLD, tostring(data.sub or ""), 2)
	elseif kind == "Daily" then
		showDaily(data)
	elseif kind == "Quake" then
		local warn = tonumber(data.warn) or 1.2
		local secs = tonumber(data.seconds) or 2.4
		show("EARTHQUAKE!", PINK, "Hold on!", warn + 0.6)
		shake(0.25, warn)
		task.delay(warn, function()
			shake(0.9, secs)
		end)
	elseif kind == "FinalRush" then
		show("FINAL RUSH", GOLD, "The plate goes crazy!", 1.6)
	elseif kind == "Lurch" then
		showLurch(data)
	elseif kind == "Result" then
		inRound = false
		local w = data.winners or {}
		if data.spectator then
			show(#w > 0 and "ROUND OVER" or "NOBODY SURVIVED!", GOLD, #w > 0 and (#w .. " survived") or "The plate wins 😈", 3)
		elseif data.survived then
			local st = tonumber(data.streak) or 0
			local head = data.lastOne and "LAST ONE STANDING!" or "YOU SURVIVED!"
			if st >= 2 then
				show(head, GOLD, string.format("🔥 %d WIN STREAK  ·  +%d bonus", st, tonumber(data.streakBonus) or 0), 3)
			else
				show(head, GOLD, "+1 WIN  ·  +coins", 3)
			end
			Sfx.play("victory", nil, 0.7)
			Sfx.play("crowdCheer", nil, 0.5)
		else
			local lost = tonumber(data.lostStreak)
			show(#w > 0 and (#w .. " SURVIVED") or "NOBODY SURVIVED!", GOLD, lost and ("Lost your " .. lost .. " win streak!") or "Next round soon!", 3)
		end
	elseif kind == "Knock" then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and typeof(data.push) == "Vector3" and typeof(data.vel) == "Vector3" then
			root.CFrame += data.push + Vector3.new(0, 1, 0)
			root.AssemblyLinearVelocity = data.vel
			if type(data.burst) == "number" then
				-- shove: hold the push for a moment so the humanoid can't cancel it
				local att = Instance.new("Attachment")
				att.Parent = root
				local lv = Instance.new("LinearVelocity")
				lv.Attachment0 = att
				lv.RelativeTo = Enum.ActuatorRelativeTo.World
				lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
				lv.VectorVelocity = data.vel
				lv.MaxForce = 1e6
				lv.Parent = root
				task.delay(math.clamp(data.burst, 0.05, 0.5), function()
					lv:Destroy()
					att:Destroy()
				end)
			end
			if type(data.stun) == "number" then
				-- knocked over for a moment: limp, can't steer, then back up
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.PlatformStand = true
					if typeof(data.trip) == "Vector3" and data.trip.Magnitude > 0.01 then
						-- missed push: tip forward onto your face
						root.AssemblyAngularVelocity = Vector3.yAxis:Cross(data.trip.Unit) * 6
					else
						root.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
					end
					task.delay(math.clamp(data.stun, 0.1, 1.2), function()
						if hum.Parent then
							hum.PlatformStand = false
							pcall(function()
								hum:ChangeState(Enum.HumanoidStateType.GettingUp)
							end)
						end
					end)
				end
			end
			shake(data.stun and 0.45 or (data.label and 0.3 or 0.5), data.stun and 0.3 or 0.3)
			-- shove / missed-push sounds are played by Push.client for everyone; other knock-downs (ice slip) bonk here
			if data.stun and data.label ~= "SHOVED!" and data.label ~= "MISSED!" then
				Sfx.play("bonk", nil, 0.7)
			end
			show(data.label or "BONK!", (data.label == "MISSED!" and PINK) or (data.label and WHITE) or PINK, data.label == "MISSED!" and "You tripped!" or nil, 0.8)
		end
	elseif kind == "Lobby" then
		-- server moved us; clear any leftover momentum on our side
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end)

---------------------------------------------------------------- per-frame: HUD, slide, shake
local plateModel = nil
local plateCore = nil

local function findPlate()
	if plateCore and plateCore.Parent then
		return
	end
	local world = Workspace:FindFirstChild("TiltWorld")
	plateModel = world and world:FindFirstChild("Plate")
	plateCore = plateModel and plateModel:FindFirstChild("PlateCore")
end

local hudT = 0
RunService.RenderStepped:Connect(function(dt)
	local phase = ReplicatedStorage:GetAttribute("Phase") or "Waiting"
	local ends = ReplicatedStorage:GetAttribute("PhaseEnds") or 0
	local left = math.max(0, ends - Workspace:GetServerTimeNow())
	local tiltDeg = ReplicatedStorage:GetAttribute("TiltDeg") or 0

	hudT -= dt
	if hudT <= 0 then
		hudT = 0.1
		local alive = ReplicatedStorage:GetAttribute("Alive") or 0
		local total = ReplicatedStorage:GetAttribute("Total") or 0
		if phase == "Intermission" then
			phaseLabel.Text = "NEXT ROUND IN " .. math.ceil(left)
			infoLabel.Text = "Get ready to balance!"
		elseif phase == "Countdown" then
			phaseLabel.Text = "GET READY"
			infoLabel.Text = total .. " on the plate"
		elseif phase == "Round" then
			phaseLabel.Text = "SURVIVE " .. TiltMath.clock(left)
			infoLabel.Text = alive .. " / " .. total .. " still on"
		elseif phase == "Results" then
			phaseLabel.Text = "ROUND OVER"
			infoLabel.Text = alive .. " survived"
		else
			phaseLabel.Text = "TILT"
			infoLabel.Text = "Waiting for players…"
		end
		local onPlate = phase == "Round" or phase == "Countdown" or phase == "Results"
		meter.Visible = onPlate
		local frac = math.clamp(tiltDeg / Config.MAX_TILT, 0, 1)
		fill.Size = UDim2.new(1, -8, frac, -8 * frac)
		local dangerous = tiltDeg >= Config.DANGER_TILT
		fill.BackgroundColor3 = dangerous and PINK or (tiltDeg >= Config.SLIDE_DEADZONE and GOLD or WHITE)
		meterLabel.Text = math.floor(tiltDeg + 0.5) .. "°"
	end

	-- danger glow while I'm on a steep plate
	local wantGlow = inRound and tiltDeg >= Config.DANGER_TILT
	local target = wantGlow and (0.35 + 0.25 * math.sin(os.clock() * 10)) or 1
	dangerStroke.Transparency += (target - dangerStroke.Transparency) * math.min(1, dt * 12)

	-- slide my character down the slope when the plate is steep (standing on a landed object slides you even more)
	findPlate()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health > 0 and plateCore and plateModel and phase == "Round" then
		local v = Objects.slideVelocity(root, plateCore, Config, TiltMath, ReplicatedStorage:GetAttribute("PlateR") or Config.PLATE_RADIUS)
		if v.Magnitude > 0 then
			root.CFrame += v * dt
		end
	end

	-- camera shake runs right after the default camera (see BindToRenderStep below)
end)

RunService:BindToRenderStep("TiltShake", Enum.RenderPriority.Camera.Value + 1, function()
	local cam = Workspace.CurrentCamera
	if cam and os.clock() < shakeUntil then
		local p = shakePower * math.clamp((shakeUntil - os.clock()) / 0.5, 0, 1)
		-- smooth noise instead of random jitter every frame: reads as a rumble, not a vibration
		local tt = os.clock() * 18
		cam.CFrame = cam.CFrame
			* CFrame.Angles(math.noise(tt, 1.3) * 0.03 * p, math.noise(tt, 7.1) * 0.03 * p, 0)
			+ Vector3.new(math.noise(tt, 3.7), math.noise(tt, 5.9), 0) * 0.8 * p
	elseif shakePower > 0 then
		shakePower = 0
	end
end)

-- first-time hint
task.delay(2, function()
	show("EXTREME TILT!", WHITE, "Stay on the plate. Run from the heavy side. Press PUSH (F) to shove", 3.5)
end)
