-- Data: per-player profiles (wins, coins, owned cosmetics, equipped, tokens) saved in a DataStore with UpdateAsync.
-- Robux receipts are recorded inside the same profile so a purchase can never be granted twice.
-- Profile = { userId, name, player = Player?, loaded = bool, dirty = bool, d = { Wins, Coins, Owned = {}, Equipped = {}, Tokens = {}, Receipts = {} } }
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Data = {}
Data.profiles = {} :: { [number]: any } -- userId -> profile
Data.STORE_NAME = "TiltData_v1"
Data.MAX_RECEIPTS = 60
Data.WINS_STORE = "TiltWins_v1" -- OrderedDataStore for the lobby TOP WINS board
Data.KOS_STORE = "TiltKOs_v1" -- ... and TOP KOs

local store = nil
local storeWarned = false
local function getStore()
	if store then
		return store
	end
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(Data.STORE_NAME)
	end)
	if ok then
		store = s
	elseif not storeWarned then
		storeWarned = true
		warn("[Tilt] DataStore unavailable: " .. tostring(s))
	end
	return store
end

local ordered = {} :: { [string]: any }
local orderedTried = {} :: { [string]: boolean }
function Data.ordered(name: string)
	if ordered[name] or orderedTried[name] then
		return ordered[name]
	end
	orderedTried[name] = true
	local ok, s = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		ordered[name] = s
	end
	return ordered[name]
end
function Data.winsStore()
	return Data.ordered(Data.WINS_STORE)
end

function Data.blank()
	return {
		Wins = 0,
		Coins = 0,
		Streak = 0, -- rounds survived in a row (reset when you fall)
		KOs = 0, -- players/bots you pushed off
		BestStreak = 0,
		LastDaily = 0, -- day number (os.time() // 86400) of the last daily reward
		DailyDay = 0, -- 1..7 position on the daily track
		Owned = {},
		Equipped = {},
		Tokens = {},
		Receipts = {},
	}
end

-- merge saved data into a fresh table (tolerates missing / wrong-typed fields)
function Data.sanitize(v)
	local d = Data.blank()
	if type(v) ~= "table" then
		return d
	end
	d.Wins = type(v.Wins) == "number" and math.max(0, math.floor(v.Wins)) or 0
	d.Coins = type(v.Coins) == "number" and math.max(0, math.floor(v.Coins)) or 0
	for _, k in ipairs({ "Streak", "BestStreak", "LastDaily", "DailyDay", "KOs" }) do
		d[k] = type(v[k]) == "number" and math.max(0, math.floor(v[k])) or 0
	end
	d.DailyDay = math.clamp(d.DailyDay, 0, 7)
	for _, k in ipairs({ "Owned", "Equipped", "Tokens" }) do
		if type(v[k]) == "table" then
			for kk, vv in pairs(v[k]) do
				if type(kk) == "string" then
					d[k][kk] = vv
				end
			end
		end
	end
	if type(v.Receipts) == "table" then
		for _, r in ipairs(v.Receipts) do
			if type(r) == "string" then
				table.insert(d.Receipts, r)
			end
		end
	end
	return d
end

-- profile for a fake / test user (SelfTest); never saved
function Data.fake(userId: number, name: string)
	local p = { userId = userId, name = name, player = nil, loaded = true, dirty = false, fake = true, d = Data.blank() }
	Data.profiles[userId] = p
	return p
end

function Data.get(player: Player?)
	return player and Data.profiles[player.UserId] or nil
end

local listeners = {}
function Data.onChanged(fn)
	table.insert(listeners, fn)
end
function Data.changed(p)
	p.dirty = true
	for _, fn in ipairs(listeners) do
		task.spawn(pcall, fn, p)
	end
end

function Data.load(player: Player)
	local p = { userId = player.UserId, name = player.DisplayName, player = player, loaded = false, dirty = false, d = Data.blank() }
	Data.profiles[player.UserId] = p
	local s = getStore()
	if not s or player.UserId <= 0 then
		p.loaded = true
		p.noSave = true
		return p
	end
	for attempt = 1, 3 do
		local ok, v = pcall(function()
			return s:GetAsync("u" .. player.UserId)
		end)
		if ok then
			-- keep anything earned while we were loading
			local loaded = Data.sanitize(v)
			loaded.Wins += p.d.Wins
			loaded.Coins += p.d.Coins
			p.d = loaded
			p.loaded = true
			return p
		end
		warn("[Tilt] DataStore load failed (" .. attempt .. "): " .. tostring(v))
		task.wait(2 * attempt)
	end
	-- could not load: play on, but never overwrite their saved data
	p.loaded = true
	p.noSave = true
	return p
end

-- write the profile; returns true when saved (or when saving isn't possible, e.g. Studio / fake)
function Data.save(p): boolean
	if not p or p.fake or p.noSave then
		return true
	end
	local s = getStore()
	if not s then
		return true
	end
	local snapshot = p.d
	local ok, err = pcall(function()
		s:UpdateAsync("u" .. p.userId, function()
			return snapshot
		end)
	end)
	if ok then
		p.dirty = false
		-- the lobby boards read these ordered stores
		p.board = p.board or {}
		for field, storeName in pairs({ Wins = Data.WINS_STORE, KOs = Data.KOS_STORE }) do
			local v = snapshot[field] or 0
			if v > 0 and p.board[field] ~= v then
				local ws = Data.ordered(storeName)
				if ws and pcall(function()
					ws:SetAsync("u" .. p.userId, v)
				end) then
					p.board[field] = v
				end
			end
		end
		return true
	end
	warn("[Tilt] DataStore save failed: " .. tostring(err))
	return false
end

function Data.hasReceipt(p, purchaseId: string): boolean
	for _, r in ipairs(p.d.Receipts) do
		if r == purchaseId then
			return true
		end
	end
	return false
end

function Data.addReceipt(p, purchaseId: string)
	table.insert(p.d.Receipts, purchaseId)
	while #p.d.Receipts > Data.MAX_RECEIPTS do
		table.remove(p.d.Receipts, 1)
	end
end

function Data.addCoins(p, n: number)
	p.d.Coins = math.max(0, p.d.Coins + math.floor(n))
	Data.changed(p)
end

function Data.addToken(p, key: string, n: number)
	p.d.Tokens[key] = math.max(0, (p.d.Tokens[key] or 0) + n)
	Data.changed(p)
end

function Data.tokens(p, key: string): number
	return p and p.d.Tokens[key] or 0
end

function Data.start()
	Players.PlayerRemoving:Connect(function(player)
		local p = Data.profiles[player.UserId]
		if p then
			Data.profiles[player.UserId] = nil
			Data.save(p)
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		for _, p in pairs(Data.profiles) do
			task.spawn(Data.save, p)
		end
		task.wait(3)
	end)
	task.spawn(function()
		while true do
			task.wait(90)
			for _, p in pairs(Data.profiles) do
				if p.dirty then
					task.spawn(Data.save, p)
				end
			end
		end
	end)
end

return Data
