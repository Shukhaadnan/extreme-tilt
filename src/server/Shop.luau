-- Shop: Robux products (paid drops incl. the NUKE, Second Chance, coin packs), the VIP pass, coins earned by surviving,
-- and coin cosmetics (trails, victory dances). All rules are server-side; clients only ask.
--
-- Paid drops are bought as TOKENS (Robux -> token in the profile, saved). Using a token during a round does the drop.
-- If you buy one outside a round, it waits in your inventory: nothing is ever lost.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))
local Data = require(script.Parent.Data)
local Game = require(script.Parent.Game)
local Map = require(script.Parent.Map)

local Shop = {}
Shop.lastNuke = -math.huge
Shop.lastDrop = {} :: { [number]: number }
Shop.vipCache = {} :: { [number]: boolean }
Shop.log = {}

local function logEvent(s)
	if Workspace:GetAttribute("TiltDebug") == true then
		print("[TiltShop] " .. s)
	end
	table.insert(Shop.log, s)
	if #Shop.log > 100 then
		table.remove(Shop.log, 1)
	end
end

---------------------------------------------------------------- state replication (player attributes)
function Shop.publish(p)
	local plr = p and p.player
	if not plr or not plr.Parent then
		return
	end
	plr:SetAttribute("Coins", p.d.Coins)
	for _, prod in ipairs(ShopConfig.PRODUCTS) do
		if prod.kind == "token" then
			plr:SetAttribute("Tok_" .. prod.key, p.d.Tokens[prod.key] or 0)
		end
	end
	local owned = {}
	for id, v in pairs(p.d.Owned) do
		if v then
			table.insert(owned, id)
		end
	end
	table.sort(owned)
	plr:SetAttribute("Owned", table.concat(owned, ","))
	plr:SetAttribute("EqTrail", p.d.Equipped.trail or "")
	plr:SetAttribute("EqDance", p.d.Equipped.dance or "")
	plr:SetAttribute("VIP", Shop.isVip(plr))
end

---------------------------------------------------------------- VIP
function Shop.isVip(plr: Player?): boolean
	if not plr then
		return false
	end
	local cached = Shop.vipCache[plr.UserId]
	if cached ~= nil then
		return cached
	end
	return false
end

function Shop.refreshVip(plr: Player)
	if ShopConfig.VIP.passId == 0 then
		Shop.vipCache[plr.UserId] = plr:GetAttribute("TestVIP") == true
		return
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, ShopConfig.VIP.passId)
	end)
	if ok then
		Shop.vipCache[plr.UserId] = owns
	end
end

local function vipTag(ch: Model, on: boolean)
	local head = ch:FindFirstChild("Head")
	local old = head and head:FindFirstChild("VipTag")
	if old then
		old:Destroy()
	end
	if not on or not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "VipTag"
	bb.Size = UDim2.new(0, 70, 0, 24)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 80
	bb.Parent = head
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
	l.BackgroundTransparency = 0.25
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(226, 190, 112)
	l.Text = "VIP"
	l.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = l
end

---------------------------------------------------------------- cosmetics
local function applyTrail(ch: Model, id: string?)
	local root = ch:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, n in ipairs({ "CosTrail", "CosA0", "CosA1" }) do
		local o = root:FindFirstChild(n)
		if o then
			o:Destroy()
		end
	end
	local c = id and ShopConfig.cosmetic(id)
	if not c or c.kind ~= "trail" then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "CosA0"
	a0.Position = Vector3.new(0, 0.8, 0.4)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "CosA1"
	a1.Position = Vector3.new(0, -0.9, 0.4)
	a1.Parent = root
	local t = Instance.new("Trail")
	t.Name = "CosTrail"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = 0.45
	t.MinLength = 0.1
	t.FaceCamera = true
	t.LightEmission = c.kind == "trail" and (c.id == "TrailFire" and 0.6 or 0.1) or 0
	t.Color = c.color2 and ColorSequence.new(c.color, c.color2) or ColorSequence.new(c.color)
	t.Transparency = NumberSequence.new(0.25, 1)
	t.WidthScale = NumberSequence.new(1, 0.2)
	t.Parent = root
end

function Shop.applyLook(plr: Player)
	local p = Data.get(plr)
	local ch = plr.Character
	if not p or not ch then
		return
	end
	applyTrail(ch, p.d.Equipped.trail)
	vipTag(ch, Shop.isVip(plr))
end

function Shop.buyCosmetic(plr: Player, id: string): (boolean, string)
	local p = Data.get(plr)
	local c = ShopConfig.cosmetic(id)
	if not p or not p.loaded then
		return false, "Still loading, try again"
	end
	if not c then
		return false, "Unknown item"
	end
	if p.d.Owned[id] then
		return Shop.equip(plr, id)
	end
	if p.d.Coins < c.price then
		return false, "Not enough coins"
	end
	p.d.Coins -= c.price
	p.d.Owned[id] = true
	p.d.Equipped[c.kind] = id
	Data.changed(p)
	Shop.publish(p)
	Shop.applyLook(plr)
	logEvent("cosmetic " .. id)
	return true, "Bought " .. c.name
end

function Shop.equip(plr: Player, id: string): (boolean, string)
	local p = Data.get(plr)
	local c = ShopConfig.cosmetic(id)
	if not p or not c or not p.d.Owned[id] then
		return false, "You don't own that"
	end
	if p.d.Equipped[c.kind] == id then
		p.d.Equipped[c.kind] = nil -- tap again to unequip
	else
		p.d.Equipped[c.kind] = id
	end
	Data.changed(p)
	Shop.publish(p)
	Shop.applyLook(plr)
	return true, p.d.Equipped[c.kind] and ("Equipped " .. c.name) or ("Unequipped " .. c.name)
end

function Shop.victoryDance(plr: Player)
	local p = Data.get(plr)
	local ch = plr.Character
	local id = p and p.d.Equipped.dance
	local c = id and ShopConfig.cosmetic(id)
	if not ch or not c then
		return
	end
	pcall(function()
		local hum = ch:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://" .. c.anim
		local t = animator:LoadAnimation(a)
		t.Priority = Enum.AnimationPriority.Action
		t:Play(0.2)
		task.delay(Config.get("RESULTS_TIME"), function()
			pcall(function()
				t:Stop(0.3)
			end)
		end)
	end)
end

---------------------------------------------------------------- coins
-- called by Game at the end of each round with all participants
function Shop.payRound(participants)
	for _, rec in ipairs(participants) do
		if rec.kind == "player" and rec.player then
			local p = Data.get(rec.player) -- nil once they've left (profile removed)
			if p then
				local secs = rec.aliveTime or 0
				local coins = math.floor(secs / ShopConfig.COINS_PER_SECONDS)
				if rec.alive then
					coins += ShopConfig.SURVIVE_BONUS
				end
				if Shop.isVip(rec.player) then
					coins *= ShopConfig.VIP_MULT
				end
				if coins > 0 then
					Data.addCoins(p, coins)
					Shop.publish(p)
					Game.notify(rec.player, "Coins", { amount = coins })
				end
				if rec.alive then
					Shop.victoryDance(rec.player)
				end
			end
		end
	end
end

---------------------------------------------------------------- paid drops + nuke
local function participantOf(plr: Player)
	for _, rec in ipairs(Game.participants) do
		if rec.player == plr then
			return rec
		end
	end
	return nil
end

-- the falling bomb (parts only, calm charcoal + one gold band)
function Shop.buildBomb(): Model
	local m = Instance.new("Model")
	m.Name = "Nuke"
	local function part(name, shape, size, cf, color, mat)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = m
		return p
	end
	local dark = Color3.fromRGB(46, 48, 54)
	local up = CFrame.Angles(0, 0, math.pi / 2) -- cylinders along Y
	local body = part("Body", Enum.PartType.Cylinder, Vector3.new(9, 5, 5), CFrame.new() * up, dark)
	part("Band", Enum.PartType.Cylinder, Vector3.new(1.4, 5.15, 5.15), CFrame.new(0, 1.2, 0) * up, Color3.fromRGB(226, 190, 112))
	part("Nose", Enum.PartType.Ball, Vector3.new(5, 5, 5), CFrame.new(0, -4.5, 0), dark)
	for i = 0, 3 do
		local a = i * math.pi / 2
		part("Fin" .. i, Enum.PartType.Block, Vector3.new(0.35, 3, 3.2), CFrame.new(0, 5, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.6), dark)
	end
	m.PrimaryPart = body
	return m
end

-- big flash + boom + everyone except `except` is blasted outward off the plate
function Shop.nuke(by: Player?)
	local core = Map.plateCore
	if not core then
		return 0
	end
	Shop.lastNuke = os.clock()
	local center = core.Position + Vector3.new(0, Config.PLATE_THICK / 2, 0)
	Game.notifyAll("Nuke", { by = by and by.DisplayName or "Someone", byId = by and by.UserId or 0 })
	Sfx.play("airhorn", nil, 0.6)
	local bomb = Shop.buildBomb()
	local top = center + Vector3.new(0, 140, 0)
	local fallTime = 1.8
	bomb:PivotTo(CFrame.new(top))
	bomb.Parent = Workspace
	Debris:AddItem(bomb, 6)
	-- shield bubble on the buyer so they can see they're safe
	local bubble
	local rec = by and participantOf(by)
	local broot = rec and rec.alive and Game.recRoot(rec)
	if broot then
		bubble = Instance.new("Part")
		bubble.Name = "NukeShield"
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.new(9, 9, 9)
		bubble.Material = Enum.Material.ForceField
		bubble.Color = Color3.fromRGB(226, 190, 112)
		bubble.CanCollide = false
		bubble.CanQuery = false
		bubble.CanTouch = false
		bubble.Massless = true
		bubble.CFrame = broot.CFrame
		local w = Instance.new("WeldConstraint")
		w.Part0 = bubble
		w.Part1 = broot
		w.Parent = bubble
		bubble.Parent = broot.Parent
		Debris:AddItem(bubble, fallTime + 2.5)
	end
	local t0 = os.clock()
	while os.clock() - t0 < fallTime do
		local k = (os.clock() - t0) / fallTime
		local now = core.Position + Vector3.new(0, Config.PLATE_THICK / 2, 0)
		bomb:PivotTo(CFrame.new(now:Lerp(now + Vector3.new(0, 140, 0), 1 - k * k)) * CFrame.Angles(0, k * 6, 0))
		task.wait()
	end
	center = core.Position + Vector3.new(0, Config.PLATE_THICK / 2, 0)
	bomb:Destroy()
	if Game.phase ~= "Round" and not Game.forceBotRounds then
		return 0 -- round ended while it fell: fizzle, never knock winners off
	end
	local flash = Instance.new("Part")
	flash.Name = "NukeFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 236, 200)
	flash.Size = Vector3.new(6, 6, 6)
	flash.CFrame = CFrame.new(center + Vector3.new(0, 4, 0))
	flash.Parent = Workspace
	local ring = Instance.new("Part")
	ring.Name = "NukeRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = Color3.fromRGB(235, 235, 235)
	ring.Size = Vector3.new(1, 10, 10)
	ring.CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = Workspace
	task.spawn(function()
		for i = 1, 18 do
			flash.Size = Vector3.one * (6 + i * 8)
			flash.Transparency = i / 18
			ring.Size = Vector3.new(1, 10 + i * 9, 10 + i * 9)
			ring.Transparency = 0.2 + i / 22
			task.wait(0.035)
		end
		flash:Destroy()
		ring:Destroy()
	end)
	Debris:AddItem(flash, 3)
	Debris:AddItem(ring, 3)
	Sfx.play("explosion", center, 1)
	Game.notifyAll("Impact", { pos = center, power = 14 })
	local hit = 0
	for _, rec in ipairs(Game.participants) do
		local root = rec.alive and Game.recRoot(rec)
		if root and (by == nil or rec.player ~= by) then
			local d = root.Position - center
			local flat = Vector3.new(d.X, 0, d.Z)
			local dir = flat.Magnitude > 0.5 and flat.Unit or Vector3.new(math.cos(hit), 0, math.sin(hit))
			local vel = dir * 135 + Vector3.new(0, 70, 0)
			if rec.kind == "player" then
				Game.notify(rec.player, "Knock", { push = Vector3.new(0, 2, 0), vel = vel })
			else
				-- a grounded humanoid cancels a plain velocity set (some bots barely moved): go limp + hold the blast
				-- the blasted bot must not ram the buyer (crowded around them at the centre): no collisions for the burst
				local parts = {}
				for _, d in ipairs(rec.model:GetDescendants()) do
					if d:IsA("BasePart") and d.CanCollide then
						d.CanCollide = false
						table.insert(parts, d)
					end
				end
				task.delay(0.6, function()
					for _, d in ipairs(parts) do
						if d.Parent then
							d.CanCollide = true
						end
					end
				end)
				rec.model:PivotTo(rec.model:GetPivot() + Vector3.new(0, 2, 0))
				Game.knockDown(rec.model, 1.6)
				root.AssemblyLinearVelocity = vel
				Game.burst(root, vel, 0.35)
			end
			hit += 1
		end
	end
	logEvent("nuke hit " .. hit)
	return hit
end

-- use a token: returns ok, message
function Shop.useToken(plr: Player, key: string): (boolean, string)
	local p = Data.get(plr)
	if not p or not p.loaded then
		return false, "Still loading, try again"
	end
	local prod = ShopConfig.product(key)
	if not prod or prod.kind ~= "token" then
		return false, "Unknown item"
	end
	if key == "Revive" then
		return Shop.revive(plr, p) -- checks tokens itself (VIPs get one free)
	end
	if (p.d.Tokens[key] or 0) <= 0 then
		return false, "You don't have any"
	end
	if Game.phase ~= "Round" then
		return false, "Wait for the round to start"
	end
	local t = os.clock()
	if t - (Shop.lastDrop[plr.UserId] or -math.huge) < ShopConfig.DROP_COOLDOWN then
		return false, "Wait a second"
	end
	if key == "Nuke" then
		if t - Shop.lastNuke < ShopConfig.NUKE_COOLDOWN then
			return false, "A nuke just went off. Wait " .. math.ceil(ShopConfig.NUKE_COOLDOWN - (t - Shop.lastNuke)) .. "s"
		end
		Shop.lastDrop[plr.UserId] = t
		Data.addToken(p, key, -1)
		Shop.publish(p)
		logEvent("use Nuke")
		task.spawn(Shop.nuke, plr)
		return true, "NUKE INCOMING!"
	end
	Shop.lastDrop[plr.UserId] = t
	Data.addToken(p, key, -1)
	Shop.publish(p)
	-- drop it on the biggest crowd that ISN'T the buyer
	local spot = Game.crowdSpot()
	local rec = participantOf(plr)
	local root = rec and rec.alive and Game.recRoot(rec)
	if root then
		local mine = Game.plateLocal(root.Position)
		if (Vector3.new(mine.X, 0, mine.Z) - spot).Magnitude < 12 then
			spot = Vector3.new(-spot.X, 0, -spot.Z)
		end
	end
	Game.dropObject(key, spot, nil, plr.DisplayName)
	logEvent("use " .. key)
	return true, prod.name .. "!"
end

-- Second Chance: put a fallen player back on the plate (once per round, within the window, while the round runs)
function Shop.revive(plr: Player, p): (boolean, string)
	if Game.phase ~= "Round" then
		return false, "Only during a round"
	end
	local rec = participantOf(plr)
	if not rec then
		return false, "You're not in this round"
	end
	if rec.alive then
		return false, "You're still on the plate!"
	end
	if os.clock() - (rec.outAt or 0) > ShopConfig.REVIVE_WINDOW then
		return false, "Too late for this round"
	end
	if (rec.revives or 0) >= ShopConfig.REVIVES_PER_ROUND then
		return false, "Already used this round"
	end
	local ch = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not ch or not hum or hum.Health <= 0 or ch ~= rec.model then
		return false, "Can't revive right now"
	end
	local free = rec.freeRevive == true
	if not free then
		if (p.d.Tokens.Revive or 0) <= 0 then
			return false, "You don't have any"
		end
		Data.addToken(p, "Revive", -1)
	else
		rec.freeRevive = false
	end
	rec.revives = (rec.revives or 0) + 1
	rec.offered = false
	rec.alive = true
	rec.sent = false
	rec.outAt = nil
	rec.aliveSince = os.clock()
	local pos = Vector3.new(0, Config.PLATE_Y + 4, 0)
	local core = Map.plateCore
	if core then
		pos = core.CFrame:PointToWorldSpace(Vector3.new(0, Config.PLATE_THICK / 2 + 3.5, 0))
	end
	ch:PivotTo(CFrame.new(pos))
	Game.zeroVelocity(ch)
	Game.setFrozen(hum, false, false)
	Game.publishCounts()
	Game.notifyAll("Revived", { name = plr.DisplayName, userId = plr.UserId })
	Game.notify(plr, "Lobby", {})
	if Game.onRevived then
		pcall(Game.onRevived, rec)
	end
	Sfx.play("sparkle", Game.recRoot(rec), 0.8)
	Shop.publish(p)
	logEvent("revive " .. plr.Name .. (free and " (vip)" or ""))
	return true, free and "VIP Second Chance!" or "Second Chance!"
end

---------------------------------------------------------------- Robux purchases
function Shop.grant(p, prod)
	if prod.kind == "coins" then
		Data.addCoins(p, prod.amount)
	else
		Data.addToken(p, prod.key, 1)
	end
	Shop.publish(p)
end

local function processReceipt(info)
	local plr = Players:GetPlayerByUserId(info.PlayerId)
	local p = plr and Data.get(plr)
	if not p or not p.loaded or p.noSave and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local prod = ShopConfig.productById(info.ProductId)
	if not prod then
		warn("[Tilt] unknown product " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if Data.hasReceipt(p, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	Shop.grant(p, prod)
	Data.addReceipt(p, info.PurchaseId)
	if not Data.save(p) then
		-- roll back so the retry doesn't double-grant
		if prod.kind == "coins" then
			p.d.Coins = math.max(0, p.d.Coins - prod.amount)
		else
			p.d.Tokens[prod.key] = math.max(0, (p.d.Tokens[prod.key] or 0) - 1)
		end
		table.remove(p.d.Receipts, #p.d.Receipts)
		Shop.publish(p)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Game.notify(plr, "Bought", { name = prod.name })
	logEvent("receipt " .. prod.key)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
Shop.processReceipt = processReceipt

---------------------------------------------------------------- remotes
function Shop.start()
	local remotes = Game.remotes or Game.setupRemotes()
	local rf = remotes:FindFirstChild("ShopAction")
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = "ShopAction"
		rf.Parent = remotes
	end
	local busy = {}
	rf.OnServerInvoke = function(plr: Player, action: any, arg: any)
		if type(action) ~= "string" or (arg ~= nil and type(arg) ~= "string") then
			return false, "Bad request"
		end
		if busy[plr] then
			return false, "Slow down"
		end
		busy[plr] = true
		local ok, a, b = pcall(function()
			if action == "Use" then
				return Shop.useToken(plr, arg)
			elseif action == "BuyCosmetic" then
				return Shop.buyCosmetic(plr, arg)
			elseif action == "Equip" then
				return Shop.equip(plr, arg)
			elseif action == "BuyRobux" then
				-- prompts the real Robux purchase; in Studio before publishing (id 0) grant directly for testing
				local prod = ShopConfig.product(arg)
				if prod then
					-- DEMO/test only: Studio + TiltDebug (test projects) grants directly instead of the purchase prompt
					local demoGrant = RunService:IsStudio() and workspace:GetAttribute("TiltDebug") == true
					if prod.productId ~= 0 and not demoGrant then
						MarketplaceService:PromptProductPurchase(plr, prod.productId)
						return true, ""
					elseif RunService:IsStudio() then
						local p = Data.get(plr)
						if p then
							Shop.grant(p, prod)
							return true, "(Studio test) got " .. prod.name
						end
					end
					return false, "Coming soon"
				elseif arg == "VIP" then
					if ShopConfig.VIP.passId ~= 0 then
						MarketplaceService:PromptGamePassPurchase(plr, ShopConfig.VIP.passId)
						return true, ""
					elseif RunService:IsStudio() then
						plr:SetAttribute("TestVIP", true)
						Shop.refreshVip(plr)
						Shop.applyLook(plr)
						local p = Data.get(plr)
						if p then
							Shop.publish(p)
						end
						return true, "(Studio test) VIP on"
					end
					return false, "Coming soon"
				end
				return false, "Unknown item"
			end
			return false, "Unknown action"
		end)
		busy[plr] = nil
		if not ok then
			warn("[Tilt] shop error: " .. tostring(a))
			return false, "Something went wrong"
		end
		return a, b
	end

	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, bought)
		if bought and passId == ShopConfig.VIP.passId then
			Shop.vipCache[plr.UserId] = true
			Shop.applyLook(plr)
			local p = Data.get(plr)
			if p then
				Shop.publish(p)
			end
			Game.notify(plr, "Bought", { name = "VIP" })
		end
	end)

	-- hooks into the round loop
	Game.onProfileLoaded = function(p)
		if p.player then
			Shop.refreshVip(p.player)
			Shop.publish(p)
			Shop.applyLook(p.player)
		end
	end
	Game.onCharacter = function(plr, _ch)
		task.wait(0.5)
		Shop.applyLook(plr)
	end
	Game.onResults = function(participants)
		Shop.payRound(participants)
	end
	Game.onRoundStart = function(participants)
		for _, rec in ipairs(participants) do
			if rec.kind == "player" and Shop.isVip(rec.player) then
				rec.freeRevive = true
			end
		end
	end
	-- keep the round going while a fallen player can still take their Second Chance
	Game.reviveHold = function()
		local now = os.clock()
		for _, rec in ipairs(Game.participants) do
			if rec.kind == "player" and not rec.alive and rec.outAt and rec.offered
				and now - rec.outAt < ShopConfig.REVIVE_WINDOW and (rec.revives or 0) < ShopConfig.REVIVES_PER_ROUND
				and rec.player and Data.get(rec.player) ~= nil then
				return true
			end
		end
		return false
	end
	Game.onOut = function(rec, why)
		logEvent(string.format("onOut kind=%s why=%s phase=%s revives=%s", tostring(rec.kind), tostring(why), tostring(Game.phase), tostring(rec.revives)))
		-- offer a Second Chance to a player who just fell (client shows the button for REVIVE_WINDOW seconds)
		if rec.kind ~= "player" or why == "left" or why == "respawn" or Game.phase ~= "Round" then
			return
		end
		if (rec.revives or 0) >= ShopConfig.REVIVES_PER_ROUND then
			return
		end
		rec.offered = true
		logEvent("offer revive " .. rec.player.Name .. " why=" .. tostring(why))
		Game.notify(rec.player, "ReviveOffer", { seconds = ShopConfig.REVIVE_WINDOW, free = rec.freeRevive == true })
	end
	Players.PlayerRemoving:Connect(function(plr)
		Shop.vipCache[plr.UserId] = nil
		Shop.lastDrop[plr.UserId] = nil
	end)
end

return Shop
