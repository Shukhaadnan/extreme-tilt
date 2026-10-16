-- ShopUI: coins counter, SHOP button + panel (Robux items, VIP, coin cosmetics), the in-round drop bar
-- (Cow / Piano / Meteor / NUKE) and the Second Chance popup after you fall. The server decides everything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local Hud = require(ReplicatedStorage:WaitForChild("Hud"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShopAction = Remotes:WaitForChild("ShopAction") :: RemoteFunction

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "TiltShop"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local FONT = Enum.Font.FredokaOne
local PANEL = Color3.fromRGB(22, 22, 26)
local CARD = Color3.fromRGB(38, 38, 44)
local GOLD = Color3.fromRGB(226, 190, 112)
local WHITE = Color3.fromRGB(255, 255, 255)
local GREY = Color3.fromRGB(170, 170, 176)
local RED = Color3.fromRGB(235, 80, 70)
local GREEN = Color3.fromRGB(120, 200, 130)

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = p
end
local function outline(p, col, tr)
	local s = Instance.new("UIStroke")
	s.Thickness = 1.5
	s.Color = col or WHITE
	s.Transparency = tr or 0.75
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = p
	return s
end
local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = WHITE
	l.TextScaled = true
	for k, v in pairs(props) do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end
local function button(parent, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Font = FONT
	b.TextColor3 = WHITE
	b.TextScaled = true
	b.BackgroundColor3 = CARD
	for k, v in pairs(props) do
		(b :: any)[k] = v
	end
	b.Parent = parent
	corner(b, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
	return b
end

---------------------------------------------------------------- toast (small message bottom-centre)
local toast = text(gui, {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -150),
	Size = UDim2.new(0, 420, 0, 30),
	Text = "",
	TextTransparency = 1,
})
Hud.attach(toast)
local toastStroke = Instance.new("UIStroke")
toastStroke.Thickness = 1.5
toastStroke.Transparency = 1
toastStroke.Parent = toast
local toastN = 0
local function say(msg: string?, good: boolean?)
	if not msg or msg == "" then
		return
	end
	toastN += 1
	local my = toastN
	toast.Text = msg
	toast.TextColor3 = good == false and RED or GOLD
	toast.TextTransparency = 0
	toastStroke.Transparency = 0.4
	task.delay(2, function()
		if my == toastN then
			TweenService:Create(toast, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			TweenService:Create(toastStroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
	end)
end

local function ask(action: string, arg: string?): (boolean, string)
	local ok, a, b = pcall(function()
		return ShopAction:InvokeServer(action, arg)
	end)
	if not ok then
		return false, "Try again"
	end
	return a == true, b or ""
end

---------------------------------------------------------------- left column (below the Roblox chat window):
-- coins, SHOP, and during a round the small 2x2 drop grid. One UIScale so phones get it small.
local leftCol = Instance.new("Frame")
leftCol.Name = "LeftCol"
leftCol.BackgroundTransparency = 1
leftCol.Position = UDim2.new(0, 12, 0.36, 0)
leftCol.Size = UDim2.new(0, 150, 0, Hud.LEFT_COL_H)
leftCol.Parent = gui
Hud.attach(leftCol)

local coinBox = Instance.new("Frame")
coinBox.Name = "Coins"
coinBox.Position = UDim2.new(0, 0, 0, 0)
coinBox.Size = UDim2.new(0, 150, 0, 34)
coinBox.BackgroundColor3 = PANEL
coinBox.BackgroundTransparency = 0.3
coinBox.Parent = leftCol
corner(coinBox, 12)
outline(coinBox)
local coinDot = Instance.new("Frame")
coinDot.Size = UDim2.new(0, 18, 0, 18)
coinDot.Position = UDim2.new(0, 9, 0.5, -9)
coinDot.BackgroundColor3 = GOLD
coinDot.Parent = coinBox
corner(coinDot, 10)
local coinText = text(coinBox, { Size = UDim2.new(1, -40, 0, 22), Position = UDim2.new(0, 34, 0.5, -11), Text = "0", TextXAlignment = Enum.TextXAlignment.Left })

local shopBtn = button(leftCol, {
	Name = "ShopButton",
	Position = UDim2.new(0, 0, 0, 40),
	Size = UDim2.new(0, 150, 0, 36),
	BackgroundColor3 = GOLD,
	TextColor3 = PANEL,
	Text = "SHOP",
})

---------------------------------------------------------------- shop panel
local panel = Instance.new("Frame")
panel.Name = "ShopPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.52)
panel.Size = UDim2.new(0.62, 0, 0.66, 0)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = gui
corner(panel, 18)
outline(panel, WHITE, 0.8)
local sizeC = Instance.new("UISizeConstraint")
sizeC.MaxSize = Vector2.new(760, 520)
sizeC.MinSize = Vector2.new(320, 300)
sizeC.Parent = panel
text(panel, { Size = UDim2.new(0.5, 0, 0, 40), Position = UDim2.new(0, 18, 0, 10), Text = "SHOP", TextXAlignment = Enum.TextXAlignment.Left })
local closeBtn = button(panel, { Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -52, 0, 10), Text = "X" })
local tabRobux = button(panel, { Size = UDim2.new(0, 130, 0, 36), Position = UDim2.new(0, 18, 0, 58), Text = "ITEMS" })
local tabCoins = button(panel, { Size = UDim2.new(0, 130, 0, 36), Position = UDim2.new(0, 156, 0, 58), Text = "STYLE" })
local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Position = UDim2.new(0, 14, 0, 104)
list.Size = UDim2.new(1, -28, 1, -116)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -8, 0, 92)
grid.CellPadding = UDim2.new(0, 8, 0, 8)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = list

local tab = "Robux"
local function attr(n)
	return player:GetAttribute(n)
end
local function owned(id: string): boolean
	local s = attr("Owned") or ""
	for x in string.gmatch(s, "[^,]+") do
		if x == id then
			return true
		end
	end
	return false
end

local function card(order: number, title: string, desc: string, btnText: string, btnGold: boolean, onClick)
	local c = Instance.new("Frame")
	c.BackgroundColor3 = CARD
	c.LayoutOrder = order
	c.Parent = list
	corner(c, 12)
	text(c, { Size = UDim2.new(0.62, -10, 0, 26), Position = UDim2.new(0, 12, 0, 10), Text = title, TextXAlignment = Enum.TextXAlignment.Left })
	text(c, {
		Size = UDim2.new(0.62, -10, 0, 40),
		Position = UDim2.new(0, 12, 0, 40),
		Text = desc,
		TextColor3 = GREY,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Gotham,
	})
	local b = button(c, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0.36, 0, 0, 42),
		Text = btnText,
		BackgroundColor3 = btnGold and GOLD or Color3.fromRGB(60, 60, 68),
		TextColor3 = btnGold and PANEL or WHITE,
	})
	b.Activated:Connect(function()
		Sfx.play("uiClick", nil, 0.5)
		onClick()
	end)
	return c
end

local function rebuild()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	tabRobux.BackgroundColor3 = tab == "Robux" and Color3.fromRGB(70, 70, 80) or CARD
	tabCoins.BackgroundColor3 = tab == "Coins" and Color3.fromRGB(70, 70, 80) or CARD
	if tab == "Robux" then
		local vip = attr("VIP") == true
		card(0, "VIP", ShopConfig.VIP.desc, vip and "OWNED" or ("R$ " .. ShopConfig.VIP.robux), not vip, function()
			if not vip then
				local ok, msg = ask("BuyRobux", "VIP")
				say(msg, ok)
			end
		end)
		for i, p in ipairs(ShopConfig.PRODUCTS) do
			local have = p.kind == "token" and (attr("Tok_" .. p.key) or 0) or 0
			local title = p.name .. (have > 0 and ("  (x" .. have .. ")") or "")
			card(i, title, p.desc, "R$ " .. p.robux, true, function()
				local ok, msg = ask("BuyRobux", p.key)
				say(msg, ok)
			end)
		end
	else
		for i, c in ipairs(ShopConfig.COSMETICS) do
			local own = owned(c.id)
			local eq = (attr(c.kind == "trail" and "EqTrail" or "EqDance") or "") == c.id
			local kindTxt = c.kind == "trail" and "Trail" or "Victory dance"
			local btnTxt = eq and "EQUIPPED" or (own and "EQUIP" or (c.price .. " coins"))
			card(i, c.name, kindTxt, btnTxt, not own, function()
				local ok, msg = ask(own and "Equip" or "BuyCosmetic", c.id)
				say(msg, ok)
				if ok and not own then
					Sfx.play("cashRegister", nil, 0.5)
				end
			end)
		end
	end
end

local function openShop(which: string?)
	tab = which or tab
	panel.Visible = true
	rebuild()
end
shopBtn.Activated:Connect(function()
	Sfx.play("uiClick", nil, 0.5)
	if panel.Visible then
		panel.Visible = false
	else
		openShop()
	end
end)
closeBtn.Activated:Connect(function()
	panel.Visible = false
end)
tabRobux.Activated:Connect(function()
	tab = "Robux"
	rebuild()
end)
tabCoins.Activated:Connect(function()
	tab = "Coins"
	rebuild()
end)

panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if panel.Visible then
		rebuild()
	end
end)
gui:GetAttributeChangedSignal("Tab"):Connect(function()
	local t = gui:GetAttribute("Tab")
	if t == "Robux" or t == "Coins" then
		tab = t
		rebuild()
	end
end)

---------------------------------------------------------------- drop grid (left column under SHOP, during the round)
-- small 2x2 grid at the side, never over the middle of the screen (sir: "not on the middle, it's annoying")
local bar = Instance.new("Frame")
bar.Name = "DropBar"
bar.Position = UDim2.new(0, 0, 0, 84)
bar.Size = UDim2.new(0, 150, 0, 98)
bar.BackgroundTransparency = 1
bar.Visible = false
bar.Parent = leftCol
local barLayout = Instance.new("UIGridLayout")
barLayout.CellSize = UDim2.new(0, 72, 0, 46)
barLayout.CellPadding = UDim2.new(0, 6, 0, 6)
barLayout.SortOrder = Enum.SortOrder.LayoutOrder
barLayout.Parent = bar
local barBtns = {}
for i, key in ipairs(ShopConfig.DROP_KEYS) do
	local p = ShopConfig.product(key)
	local b = button(bar, {
		Name = key,
		LayoutOrder = i,
		BackgroundTransparency = 0.15,
		BackgroundColor3 = key == "Nuke" and Color3.fromRGB(70, 40, 40) or CARD,
		Text = "",
		RichText = true,
	})
	if key == "Nuke" then
		outline(b, RED, 0.35)
	end
	b.Activated:Connect(function()
		local have = attr("Tok_" .. key) or 0
		if have > 0 then
			local ok, msg = ask("Use", key)
			say(msg, ok)
		else
			local ok, msg = ask("BuyRobux", key)
			say(msg, ok)
		end
	end)
	barBtns[key] = { b = b, p = p }
end
local function refreshBar()
	for key, x in pairs(barBtns) do
		local have = attr("Tok_" .. key) or 0
		local name = key == "Nuke" and "NUKE" or string.upper(key)
		if have > 0 then
			x.b.Text = string.format('%s<br/><font color="#E2BE70">DROP x%d</font>', name, have)
		else
			x.b.Text = string.format('%s<br/><font color="#E2BE70">R$ %d</font>', name, x.p.robux)
		end
	end
end

---------------------------------------------------------------- Second Chance popup
local revive = Instance.new("Frame")
revive.Name = "Revive"
revive.AnchorPoint = Vector2.new(0.5, 0.5)
revive.Position = UDim2.fromScale(0.5, 0.6)
revive.Size = UDim2.new(0, 320, 0, 120)
revive.BackgroundColor3 = PANEL
revive.BackgroundTransparency = 0.1
revive.Visible = false
revive.Parent = gui
Hud.attach(revive)
corner(revive, 16)
outline(revive, GOLD, 0.3)
local reviveTitle = text(revive, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 10), Text = "SECOND CHANCE?" })
local reviveBtn = button(revive, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.new(1, -40, 0, 54),
	BackgroundColor3 = GOLD,
	TextColor3 = PANEL,
	Text = "",
})
local reviveUntil = 0
local reviveFree = false
local waitingBuy = false
local function closeRevive()
	revive.Visible = false
	reviveUntil = 0
	waitingBuy = false
end
local function tryRevive()
	local ok, msg = ask("Use", "Revive")
	if ok then
		closeRevive()
	end
	say(msg, ok)
	return ok
end
reviveBtn.Activated:Connect(function()
	if reviveFree or (attr("Tok_Revive") or 0) > 0 then
		tryRevive()
	else
		waitingBuy = true
		local ok, msg = ask("BuyRobux", "Revive")
		if msg ~= "" then
			say(msg, ok)
		end
		-- Studio test grant is instant; a real purchase arrives through the Tok_Revive attribute
		if ok and (attr("Tok_Revive") or 0) > 0 then
			tryRevive()
		end
	end
end)
player:GetAttributeChangedSignal("Tok_Revive"):Connect(function()
	if waitingBuy and revive.Visible and os.clock() < reviveUntil + 10 and (attr("Tok_Revive") or 0) > 0 then
		tryRevive()
	end
end)

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(kind: string, data)
	data = data or {}
	if kind == "ReviveOffer" then
		reviveFree = data.free == true
		reviveUntil = os.clock() + (data.seconds or 6)
		revive.Visible = true
		revive.Size = UDim2.new(0, 260, 0, 100)
		TweenService:Create(revive, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Size = UDim2.new(0, 320, 0, 120) }):Play()
		task.spawn(function()
			while revive.Visible and reviveUntil > 0 do
				local left = math.ceil(reviveUntil - os.clock())
				if left <= 0 and not waitingBuy then
					closeRevive()
					break
				elseif left <= -15 then
					closeRevive()
					break
				end
				reviveTitle.Text = "SECOND CHANCE? " .. math.max(0, left)
				local have = attr("Tok_Revive") or 0
				if reviveFree then
					reviveBtn.Text = "FREE (VIP)"
				elseif have > 0 then
					reviveBtn.Text = "USE (x" .. have .. ")"
				else
					reviveBtn.Text = "R$ " .. ShopConfig.product("Revive").robux
				end
				task.wait(0.2)
			end
		end)
	elseif kind == "RoundStart" or kind == "Result" then
		closeRevive()
	end
end)

---------------------------------------------------------------- live updates
local function refreshAll()
	coinText.Text = tostring(attr("Coins") or 0)
	refreshBar()
	if panel.Visible then
		rebuild()
	end
end
player.AttributeChanged:Connect(function(name)
	if name == "Coins" then
		local old = tonumber(coinText.Text) or 0
		local new = attr("Coins") or 0
		if new > old then
			coinBox.Size = UDim2.new(0, 160, 0, 38)
			TweenService:Create(coinBox, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.new(0, 150, 0, 34) }):Play()
		end
	end
	refreshAll()
end)
ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(function()
	bar.Visible = ReplicatedStorage:GetAttribute("Phase") == "Round"
end)
bar.Visible = ReplicatedStorage:GetAttribute("Phase") == "Round"
refreshAll()

-- Robux prompt closed without buying -> drop the "waiting" state
MarketplaceService.PromptProductPurchaseFinished:Connect(function(_userId, _productId, bought)
	if not bought then
		waitingBuy = false
	end
end)
