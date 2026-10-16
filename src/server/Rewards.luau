-- Rewards: daily login reward (7-day track), win streaks (survive rounds in a row), and the lobby TOP WINS board.
-- Server only. Hooks into Game.onProfileLoaded / Game.onResults after Shop has set them (call Rewards.start() after Shop.start()).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Game = require(script.Parent:WaitForChild("Game"))
local Data = require(script.Parent:WaitForChild("Data"))
local Map = require(script.Parent:WaitForChild("Map"))

local Rewards = {}

-- 7-day track; missing a day starts you over at day 1. Day 4 and day 7 add a free drop.
Rewards.DAILY = {
	{ coins = 30 },
	{ coins = 50 },
	{ coins = 75 },
	{ coins = 100, token = "Cow" },
	{ coins = 125 },
	{ coins = 150 },
	{ coins = 250, token = "Piano" },
}
Rewards.STREAK_COINS = 5 -- per round of streak (from 2 in a row), capped below
Rewards.STREAK_CAP = 10
Rewards.BOARD_SIZE = 10
Rewards.BOARD_REFRESH = 60

function Rewards.today(): number
	return os.time() // 86400
end

-- pure: decide (and apply) today's daily reward on a profile. Returns the reward table + day, or nil if already claimed.
function Rewards.claimDaily(p, today: number)
	local d = p.d
	if d.LastDaily == today then
		return nil
	end
	if d.LastDaily == today - 1 and d.DailyDay >= 1 then
		d.DailyDay = d.DailyDay % #Rewards.DAILY + 1
	else
		d.DailyDay = 1
	end
	d.LastDaily = today
	local r = Rewards.DAILY[d.DailyDay]
	d.Coins += r.coins
	if r.token then
		d.Tokens[r.token] = (d.Tokens[r.token] or 0) + 1
	end
	Data.changed(p)
	return r, d.DailyDay
end

-- pure: update a profile's streak after a round. Returns (bonus coins, streak now, streak lost or nil)
function Rewards.applyStreak(p, survived: boolean)
	local d = p.d
	if survived then
		d.Streak += 1
		d.BestStreak = math.max(d.BestStreak, d.Streak)
		local bonus = 0
		if d.Streak >= 2 then
			bonus = math.min(d.Streak, Rewards.STREAK_CAP) * Rewards.STREAK_COINS
			d.Coins += bonus
		end
		Data.changed(p)
		return bonus, d.Streak, nil
	end
	local lost = d.Streak >= 2 and d.Streak or nil
	if d.Streak ~= 0 then
		d.Streak = 0
		Data.changed(p)
	end
	return 0, 0, lost
end

---------------------------------------------------------------- lobby boards: TOP WINS + TOP KOs
local nameCache = {} :: { [number]: string }

local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local plr = Players:GetPlayerByUserId(userId)
	if plr then
		nameCache[userId] = plr.DisplayName
		return plr.DisplayName
	end
	local ok, n = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(n) == "string" then
		nameCache[userId] = n
		return n
	end
	return "Player"
end

-- id -> { field, store, title, offset, rows = { {name: TextLabel, wins: TextLabel} } }
Rewards.boards = {
	wins = { field = "Wins", store = Data.WINS_STORE, title = "TOP WINS", offset = Vector3.new(-16, 7.5, 14), name = "WinsBoard" },
	kos = { field = "KOs", store = Data.KOS_STORE, title = "TOP KOs", offset = Vector3.new(0, 7.5, 22), name = "KOBoard" },
}

local function buildOne(b)
	local world = Map.world
	local lobby = world and world:FindFirstChild("Lobby")
	if not lobby or lobby:FindFirstChild(b.name) then
		return
	end
	local C = Map.COLORS
	local L = Config.LOBBY_CENTER
	local pos = L + b.offset
	local W, H = 12, 11
	local board = Map.part({
		Name = b.name,
		Size = Vector3.new(W, H, 0.6),
		CFrame = CFrame.lookAt(pos, Vector3.new(L.X, pos.Y, L.Z + 6)),
		Color = C.emblem,
		Parent = lobby,
	})
	for _, x in ipairs({ -W / 2 + 1, W / 2 - 1 }) do
		local bottom = board.CFrame * CFrame.new(x, -H / 2, 0.8)
		local h = 7.5
		Map.part({
			Name = "SignPost",
			Size = Vector3.new(0.8, h, 0.8),
			CFrame = CFrame.new(bottom.Position - Vector3.new(0, h / 2 - 0.5, 0)),
			Color = C.wood,
			Material = Enum.Material.Wood,
			Parent = lobby,
		})
	end
	Map.part({
		Name = "BoardTrim",
		Size = Vector3.new(W + 0.6, 0.5, 0.8),
		CFrame = board.CFrame * CFrame.new(0, H / 2 + 0.1, 0),
		Color = C.gold,
		Reflectance = 0.03,
		Parent = lobby,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 70)
	title.Position = UDim2.new(0, 0, 0, 14)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = C.gold
	title.Text = b.title
	title.Parent = gui
	b.rows = {}
	for i = 1, Rewards.BOARD_SIZE do
		local y = 100 + (i - 1) * 32
		local rank = Instance.new("TextLabel")
		rank.BackgroundTransparency = 1
		rank.Size = UDim2.new(0, 50, 0, 28)
		rank.Position = UDim2.new(0, 24, 0, y)
		rank.Font = Enum.Font.FredokaOne
		rank.TextScaled = true
		rank.TextColor3 = i <= 3 and C.gold or Color3.fromRGB(200, 200, 205)
		rank.TextXAlignment = Enum.TextXAlignment.Left
		rank.Text = i .. "."
		rank.Parent = gui
		local nm = rank:Clone()
		nm.Size = UDim2.new(0, 290, 0, 28)
		nm.Position = UDim2.new(0, 76, 0, y)
		nm.TextColor3 = Color3.new(1, 1, 1)
		nm.Text = "-"
		nm.Name = "Name" .. i
		nm.Parent = gui
		local wn = rank:Clone()
		wn.Size = UDim2.new(0, 90, 0, 28)
		wn.Position = UDim2.new(1, -114, 0, y)
		wn.TextXAlignment = Enum.TextXAlignment.Right
		wn.TextColor3 = C.gold
		wn.Text = ""
		wn.Name = "Wins" .. i
		wn.Parent = gui
		b.rows[i] = { name = nm, wins = wn }
	end
	b.part = board
end

function Rewards.buildBoard()
	for _, b in pairs(Rewards.boards) do
		buildOne(b)
	end
end

-- rows = { {name, wins} } sorted high to low (wins = the board's number)
function Rewards.showRows(rows, id: string?)
	local b = Rewards.boards[id or "wins"]
	for i, r in ipairs(b.rows or {}) do
		local row = rows[i]
		r.name.Text = row and row.name or "-"
		r.wins.Text = row and tostring(row.wins) or ""
	end
	b.last = rows
end

-- global board from the ordered store; people online always show with their live number
function Rewards.refreshBoard()
	for id, b in pairs(Rewards.boards) do
		local rows = {}
		local ws = Data.ordered(b.store)
		if ws then
			pcall(function()
				local page = ws:GetSortedAsync(false, Rewards.BOARD_SIZE):GetCurrentPage()
				for _, e in ipairs(page) do
					local uid = tonumber(string.sub(e.key, 2))
					if uid and e.value > 0 then
						table.insert(rows, { name = nameOf(uid), wins = e.value, uid = uid })
					end
				end
			end)
		end
		local byUid = {}
		for _, r in ipairs(rows) do
			byUid[r.uid] = r
		end
		for _, p in pairs(Data.profiles) do
			local v = p.d[b.field] or 0
			if not p.fake and p.player and v > 0 then
				local r = byUid[p.userId]
				if r then
					r.wins = math.max(r.wins, v)
				else
					table.insert(rows, { name = p.name, wins = v, uid = p.userId })
				end
			end
		end
		table.sort(rows, function(a, c)
			return a.wins > c.wins
		end)
		Rewards.showRows(rows, id)
	end
end

---------------------------------------------------------------- hooks
function Rewards.start()
	local prevLoaded = Game.onProfileLoaded
	Game.onProfileLoaded = function(p)
		if prevLoaded then
			prevLoaded(p)
		end
		if p.player then
			local r, day = Rewards.claimDaily(p, Rewards.today())
			Game.refreshStats(p)
			if r then
				-- Shop.publish (inside prevLoaded) ran before the reward: publish coins/tokens again
				local Shop = require(script.Parent:WaitForChild("Shop"))
				Shop.publish(p)
				task.delay(3, function()
					if p.player and p.player.Parent then
						Game.notify(p.player, "Daily", { day = day, coins = r.coins, token = r.token, track = Rewards.DAILY })
					end
				end)
			end
		end
	end
	local prevResults = Game.onResults
	Game.onResults = function(participants)
		if prevResults then
			prevResults(participants)
		end
		for _, rec in ipairs(participants) do
			if rec.kind == "player" and rec.player then
				local p = Data.get(rec.player)
				if p then
					local bonus, streak, lost = Rewards.applyStreak(p, rec.alive == true)
					rec.streak = streak
					rec.streakBonus = bonus
					rec.lostStreak = lost
					Game.refreshStats(p)
					if bonus > 0 then
						local Shop = require(script.Parent:WaitForChild("Shop"))
						Shop.publish(p)
					end
				end
			end
		end
		task.defer(Rewards.refreshBoard)
	end
	task.spawn(function()
		while not (Map.world and Map.world:FindFirstChild("Lobby")) do
			task.wait(0.5)
		end
		Rewards.buildBoard()
		while true do
			pcall(Rewards.refreshBoard)
			task.wait(Rewards.BOARD_REFRESH)
		end
	end)
end

return Rewards
