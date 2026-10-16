-- SelfTest: runs in Studio "Run" (F8, no player) or when workspace.RunSelfTest == true.
-- Prints "SELFTEST PASS/FAIL: ..." lines and finally "SELFTEST DONE passed=N failed=M".
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

-- wait until Main decides (it sets SelfTestMode after ~5 s with no players)
local t0 = os.clock()
while Workspace:GetAttribute("SelfTestMode") ~= true and os.clock() - t0 < 9 do
	task.wait(0.25)
end
if Workspace:GetAttribute("SelfTestMode") ~= true then
	return
end

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local TiltMath = require(ReplicatedStorage:WaitForChild("TiltMath"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))
local Game = require(script.Parent:WaitForChild("Game"))
local Map = require(script.Parent:WaitForChild("Map"))
local Objects = require(ReplicatedStorage:WaitForChild("Objects"))
local Bots = require(script.Parent:WaitForChild("Bots"))
local Shop = require(script.Parent:WaitForChild("Shop"))
local Data = require(script.Parent:WaitForChild("Data"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))

local passed, failed = 0, 0
local function check(name: string, cond: any, detail: any?)
	if cond then
		passed += 1
		print("SELFTEST PASS: " .. name)
	else
		failed += 1
		print("SELFTEST FAIL: " .. name .. (detail ~= nil and (" :: " .. tostring(detail)) or ""))
	end
end
local function finite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function run(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		check(name .. " (no error)", false, err)
	end
end

-- the scripted checks below need objects to stay put for a while; the real (short) lifetime is tested on its own
-- and the realistic pacing rounds run with it
Workspace:SetAttribute("Cfg_OBJECT_LIFETIME", 15)

---------------------------------------------------------------- 1. world
run("world", function()
	local world = Workspace:FindFirstChild("TiltWorld")
	check("world folder", world ~= nil)
	check("plate model", Map.plateModel and Map.plateModel.Parent == world)
	check("plate core unanchored + aligned", Map.plateCore and not Map.plateCore.Anchored and Map.alignPos and Map.alignRot)
	check("lobby spawn exists", Map.lobbySpawn and Map.lobbySpawn:IsA("SpawnLocation"))
	check("objects folder", world and world:FindFirstChild("Objects"))
	check("lobby has trees", world and world.Lobby and #world.Lobby:GetChildren() > 100, world and world.Lobby and #world.Lobby:GetChildren())
	check("scenery built", world and world:FindFirstChild("Scenery") and #world.Scenery:GetChildren() > 20)
	local surface = Map.plateModel and Map.plateModel:FindFirstChild("Surface")
	check("plate surface collides", surface and surface.CanCollide)
	local nCollide = 0
	for _, d in ipairs(Map.plateModel:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			nCollide += 1
		end
	end
	local nOther = 0
	for _, d in ipairs(Map.plateModel:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide and d.Name ~= "Surface" and d.Name ~= "RingSeg" then
			nOther += 1
		end
	end
	check("only the standing surface (centre + rings) collides on the plate", nOther == 0 and nCollide > 1, nOther .. "/" .. nCollide)
	-- plate surface height
	local top = Map.plateCore.Position.Y + Config.PLATE_THICK / 2
	check("plate top at PLATE_Y", math.abs(top - Config.PLATE_Y) < 0.6, top)
	-- lobby floor raycast under every lobby spot
	local okAll = true
	for i = 1, 30 do
		local p = Map.lobbySpot(i)
		local hit = Workspace:Raycast(p, Vector3.new(0, -12, 0))
		if not hit then
			okAll = false
		end
	end
	check("all lobby spots have ground", okAll)
	-- plate spots stay on the plate
	local okSpots = true
	for n = 1, 20 do
		for i = 1, n do
			local s = Map.plateSpot(i, n)
			if math.sqrt(s.X ^ 2 + s.Z ^ 2) > Config.PLATE_RADIUS - 10 then
				okSpots = false
			end
		end
	end
	check("plate start spots inside the plate", okSpots)
	check("remotes", ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Notify") and ReplicatedStorage.Remotes:FindFirstChild("PlaySfx"))
	check("shop remote", ReplicatedStorage.Remotes:FindFirstChild("ShopAction") and ReplicatedStorage.Remotes.ShopAction:IsA("RemoteFunction"))
end)

---------------------------------------------------------------- 2. maths sanity in-engine
run("math", function()
	local kx, kz, ang = TiltMath.axisAngle(10, 0)
	local cf = CFrame.fromAxisAngle(Vector3.new(kx, 0, kz), ang)
	local p = cf:PointToWorldSpace(Vector3.new(10, 0, 0))
	check("engine rotation: +X dips", p.Y < 0, p.Y)
	check("slideSpeed sane", TiltMath.slideSpeed(32, 7, Config.SLIDE_K) < 20)
end)

---------------------------------------------------------------- 3. objects
run("objects", function()
	for _, k in ipairs(Objects.KINDS) do
		local m = Objects.build(k.kind)
		local okBuild = m and m.PrimaryPart and m:GetAttribute("Weight") == k.weight
		local nColl = 0
		local welded = true
		if m then
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					if d.CanCollide then
						nColl += 1
					end
					if d ~= m.PrimaryPart and not d:FindFirstChildOfClass("WeldConstraint") then
						welded = false
					end
				end
			end
		end
		check("object builds: " .. k.kind, okBuild and nColl == 1 and welded, tostring(nColl) .. " " .. tostring(welded))
		if m then
			m:Destroy()
		end
	end
	local rng = Random.new(1)
	local seen = {}
	for _ = 1, 300 do
		seen[Objects.pick(rng, 0)] = true
	end
	check("early picks never include late objects", not seen.Meteor and not seen.Piano and not seen.Cow)
	local seenLate = {}
	for _ = 1, 600 do
		seenLate[Objects.pick(rng, 80)] = true
	end
	check("late picks can be anything", seenLate.Meteor and seenLate.Piano and seenLate.Cow and seenLate.Watermelon)
end)

---------------------------------------------------------------- 4. sounds
run("sounds", function()
	local used = { "fastWhoosh", "pop", "splat", "boing", "metalPipe", "bonk", "vineBoom", "explosion", "wilhelm", "scream",
		"airhorn", "uiClick", "notify", "fahhh", "victory", "crowdCheer", "musicHappyAdventure", "oof", "punch", "punch2",
		"swing", "dash", "slideWhistle", "thud", "birds", "creak", "quake", "rockBreak", "beep", "ghostGiggle", "sparkle" }
	local snds = {}
	for _, n in ipairs(used) do
		local s = Instance.new("Sound")
		s.SoundId = Sfx.url(n) or ""
		s.Parent = SoundService
		snds[n] = s
	end
	local list = {}
	for _, s in pairs(snds) do
		table.insert(list, s)
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	local tw = os.clock()
	while os.clock() - tw < 6 do
		local all = true
		for _, s in pairs(snds) do
			if s.TimeLength <= 0 then
				all = false
			end
		end
		if all then
			break
		end
		task.wait(0.2)
	end
	for _, n in ipairs(used) do
		check("sound loads: " .. n, snds[n].TimeLength > 0)
		snds[n]:Destroy()
	end
end)

---------------------------------------------------------------- 5. bots rigs
run("bots", function()
	Bots.paused = true
	Game.botActionsOff = true
	Bots.setCount(7, function(i)
		return Map.lobbySpot(200 + i)
	end)
	check("7 bots spawned", Bots.count() == 7, Bots.count())
	local motors, fallback = 0, 0
	for _, b in pairs(Bots.list) do
		local n = 0
		for _, d in ipairs(b.model:GetDescendants()) do
			if d:IsA("Motor6D") then
				n += 1
			end
		end
		if n >= 15 then
			motors += 1
		elseif b.model:FindFirstChild("LeftLeg") then
			fallback += 1
		end
	end
	check("bots have full R15 rigs", motors == 7, "r15=" .. motors .. " block=" .. fallback)
	task.wait(2)
	local stood = 0
	for _, b in pairs(Bots.list) do
		local y = b.root.Position.Y
		if math.abs(y - (Config.LOBBY_CENTER.Y + 3)) < 3 then
			stood += 1
		end
	end
	check("bots stand on the lobby", stood == 7, stood)
	Bots.paused = false
	Game.botActionsOff = false
end)

---------------------------------------------------------------- 6. plate tilts toward a heavy object
run("tilt", function()
	Game.forceBotRounds = true
	Game.round += 1
	Game.participants = {}
	Game.setPhase("Round", 30)
	Game.dropObject("Cow", Vector3.new(35, 0, 0), 0.6)
	local tw = os.clock()
	while os.clock() - tw < 6 do
		if math.abs(Game.tilt.x) > 15 then
			break
		end
		task.wait(0.1)
	end
	check("cow lands", #Game.objects >= 1 and Game.objects[1].landed, #Game.objects)
	check("plate tilts toward +X (cow side)", Game.tilt.x > 10, Game.tilt.x)
	check("tilt capped", math.abs(Game.tilt.x) <= Config.MAX_TILT + 0.01, Game.tilt.x)
	local surface = Map.plateModel.Surface
	local edgeX = surface.CFrame:PointToWorldSpace(Vector3.new(0, 0, 0))
	local _ = edgeX
	local low = Map.plateCore.CFrame:PointToWorldSpace(Vector3.new(40, 0, 0))
	local high = Map.plateCore.CFrame:PointToWorldSpace(Vector3.new(-40, 0, 0))
	check("+X edge physically lower", low.Y < high.Y - 10, low.Y .. " vs " .. high.Y)
	check("plate stays pinned at centre", (Map.plateCore.Position - Vector3.new(0, Config.PLATE_Y - Config.PLATE_THICK / 2, 0)).Magnitude < 0.5, Map.plateCore.Position)
	local m = Game.objects[1] and Game.objects[1].model
	if m and m.PrimaryPart then
		local lp = Game.plateLocal(m.PrimaryPart.Position)
		check("cow rests on the plate (not through it)", lp.Y > -1 and lp.Y < 8, lp.Y)
	end
	-- object lifetime / clear
	Game.clearObjects(true)
	task.wait(3)
	check("plate levels after clear", math.abs(Game.tilt.x) < 1 and math.abs(Game.tilt.z) < 1, Game.tilt.x)
	Game.setPhase("Idle", 0)
	Game.forceBotRounds = false
end)

---------------------------------------------------------------- 7. sliding + elimination
run("slide", function()
	Bots.paused = true
	Game.botActionsOff = true
	Game.forceBotRounds = true
	Game.round += 1
	local b = Bots.list[1]
	Game.participants = { { kind = "bot", bot = b, model = b.model, alive = true } }
	-- off the meteor's line, so it slides past it instead of shoving it off the edge
	b.model:PivotTo(CFrame.new(10, Config.PLATE_Y + 3.5, 24))
	Game.setPhase("Round", 30)
	-- a heavy object at the edge tilts the plate hard; the idle bot must slide off and be sent to the lobby
	Game.dropObject("Meteor", Vector3.new(38, 0, 0), 0.6)
	local tw = os.clock()
	local rec = Game.participants[1]
	local nextInfo = 0
	while os.clock() - tw < 14 and not rec.sent do
		if os.clock() - tw >= nextInfo then
			nextInfo += 1
			local o = Game.objects[1]
			local olp = o and o.model.PrimaryPart and Game.plateLocal(o.model.PrimaryPart.Position)
			local blp = Game.plateLocal(b.root.Position)
			print(string.format("SELFTEST INFO: slide t=%.0f tilt=(%.1f,%.1f) obj=%s landed=%s bot=(%.1f,%.1f,%.1f)", os.clock() - tw,
				Game.tilt.x, Game.tilt.z, olp and string.format("(%.1f,%.1f,%.1f)", olp.X, olp.Y, olp.Z) or "none",
				tostring(o and o.landed), blp.X, blp.Y, blp.Z))
		end
		task.wait(0.1)
	end
	check("idle bot slides off a steep plate", not rec.alive, "alive=" .. tostring(rec.alive) .. " tilt=" .. Game.tilt.x)
	check("fallen bot sent to the lobby", rec.sent and b.root.Position.Y > Config.LOBBY_CENTER.Y - 2, b.root.Position.Y)
	local fellOK = false
	for _, s in ipairs(Game.log) do
		if string.find(s, "^out ") then
			fellOK = true
		end
	end
	check("fall logged", fellOK)
	Game.clearObjects(false)
	Game.participants = {}
	Game.setPhase("Idle", 0)
	Game.forceBotRounds = false
	Bots.paused = false
	Game.botActionsOff = false
	task.wait(3)
end)

---------------------------------------------------------------- 8. full bot round (shortened)
run("round", function()
	Workspace:SetAttribute("Cfg_ROUND_TIME", 30)
	Workspace:SetAttribute("Cfg_RANDOM_DROPS", true) -- this stress test is about drops (live game has none)
	Workspace:SetAttribute("Cfg_FIRST_EVENT_AT", 2)
	Workspace:SetAttribute("Cfg_EVENT_GAP_START", 3)
	Workspace:SetAttribute("Cfg_EVENT_GAP_END", 2)
	Workspace:SetAttribute("Cfg_FINAL_RUSH", 8)
	Workspace:SetAttribute("Cfg_RESULTS_TIME", 2)
	Workspace:SetAttribute("Cfg_LAST_ONE_DELAY", 999) -- stress test measures the plate, not the last-one end
	Game.forceBotRounds = true
	table.clear(Game.log)
	Game.startRound()
	local _, total = Game.aliveCounts()
	check("round has bots (no players -> MAX_BOTS)", total == math.min(Config.MIN_BODIES, Config.MAX_BOTS), total)
	local onPlate = 0
	for _, rec in ipairs(Game.participants) do
		local r = rec.model.PrimaryPart
		if r and math.abs(r.Position.Y - (Config.PLATE_Y + 3)) < 3 and math.sqrt(r.Position.X ^ 2 + r.Position.Z ^ 2) < Config.PLATE_RADIUS then
			onPlate += 1
		end
	end
	check("everyone placed on the plate", onPlate == total, onPlate .. "/" .. total)
	local frozen = Game.participants[1].model.Humanoid.WalkSpeed == 0
	check("frozen during countdown", frozen)
	Game.setPhase("Countdown", 1)
	task.wait(1)
	Game.unfreezeAll()
	check("unfrozen at GO", Game.participants[1].model.Humanoid.WalkSpeed > 0)
	Game.setPhase("Round", 30)
	local maxTilt, nanSeen = 0, false
	local watcher = true
	task.spawn(function()
		while watcher do
			local m = TiltMath.magnitude(Game.tilt.x, Game.tilt.z)
			if not finite(m) then
				nanSeen = true
			end
			maxTilt = math.max(maxTilt, m)
			task.wait(0.1)
		end
	end)
	local reason = Game.runRound()
	watcher = false
	local alive = Game.aliveCounts()
	local drops, lands = 0, 0
	for _, s in ipairs(Game.log) do
		if string.find(s, "^drop ") then
			drops += 1
		elseif string.find(s, "^land ") then
			lands += 1
		end
	end
	check("round ends cleanly", reason == "time" or reason == "all fell" or reason == "last one", reason)
	check("objects dropped during the round", drops >= 4, drops)
	check("objects landed on the plate", lands >= drops * 0.6, lands .. "/" .. drops)
	check("plate tilted during the round", maxTilt > 8, maxTilt)
	check("no NaN tilt", not nanSeen)
	check("plate stayed pinned", (Map.plateCore.Position - Vector3.new(0, Config.PLATE_Y - Config.PLATE_THICK / 2, 0)).Magnitude < 0.5)
	print(string.format("SELFTEST INFO: stress round (drops every 2-3 s): %d/%d survived, max tilt %.1f, %d drops", alive, total, maxTilt, drops))
	local fellObjs = 0
	for _, s in ipairs(Game.log) do
		if string.find(s, "^objfall ") then
			fellObjs += 1
		end
	end
	check("landed objects never slide off the plate", fellObjs == 0, fellObjs)
	local aliveBefore = Game.aliveCounts()
	local fallsBefore = 0
	for _, s in ipairs(Game.log) do
		if string.find(s, "^out ") then
			fallsBefore += 1
		end
	end
	local winners = Game.results()
	local fallsAfter = 0
	for _, s in ipairs(Game.log) do
		if string.find(s, "^out ") then
			fallsAfter += 1
		end
	end
	check("results returns a list", type(winners) == "table")
	check("winners = everyone alive at the end", #winners == aliveBefore, #winners .. " vs " .. aliveBefore)
	check("nobody falls after the round is over", fallsAfter == fallsBefore, fallsAfter - fallsBefore)
	check("participants cleared", #Game.participants == 0)
	check("objects cleared", #Game.objects == 0)
	task.wait(1)
	local inLobby = 0
	for _, b in pairs(Bots.list) do
		if (b.root.Position - Config.LOBBY_CENTER).Magnitude < Config.LOBBY_RADIUS + 4 then
			inLobby += 1
		end
	end
	check("all bots back in the lobby", inLobby == Bots.count(), inLobby .. "/" .. Bots.count())
	for _, k in ipairs({ "ROUND_TIME", "FIRST_EVENT_AT", "EVENT_GAP_START", "EVENT_GAP_END", "FINAL_RUSH", "RESULTS_TIME", "RANDOM_DROPS", "LAST_ONE_DELAY" }) do
		Workspace:SetAttribute("Cfg_" .. k, nil)
	end
	Game.forceBotRounds = false
end)

---------------------------------------------------------------- 8a0. LAST ONE STANDING (sir Oct 16): the round ends when one is left
run("last one standing", function()
	Workspace:SetAttribute("Cfg_ROUND_TIME", 40)
	Workspace:SetAttribute("Cfg_NO_CHAOS", true)
	Workspace:SetAttribute("Cfg_RESULTS_TIME", 1)
	Game.forceBotRounds = true
	Game.startRound()
	local _, total = Game.aliveCounts()
	Game.unfreezeAll()
	Game.setPhase("Round", 40)
	-- knock everyone but the first one out after 2 s
	task.delay(2, function()
		for i, rec in ipairs(Game.participants) do
			if i > 1 then
				Game.markOut(rec, "test")
			end
		end
	end)
	local t0 = os.clock()
	local reason = Game.runRound()
	local took = os.clock() - t0
	local alive = Game.aliveCounts()
	check("last one: round ends when only one is left", reason == "last one", reason)
	check("last one: ends right away (not the full 40 s)", took < 2 + Config.get("LAST_ONE_DELAY") + 1.5, string.format("%.1f s", took))
	check("last one: the survivor is still on", alive == 1, alive .. "/" .. total)
	local winners = Game.results()
	check("last one: exactly one winner", type(winners) == "table" and #winners == 1, type(winners) == "table" and #winners or "?")
	task.wait(1.5)
	-- a solo round (only one body from the start) must NOT end at once
	Workspace:SetAttribute("Cfg_MIN_BODIES", 1)
	Workspace:SetAttribute("Cfg_ROUND_TIME", 4)
	task.wait(1)
	local log0 = #Game.log
	Game.startRound()
	local _, soloTotal = Game.aliveCounts()
	task.wait(0.5) -- let the lone body settle on the plate before GO
	Game.unfreezeAll()
	Game.setPhase("Round", 4)
	local t1 = os.clock()
	local soloReason = Game.runRound()
	local soloTook = os.clock() - t1
	local ev = {}
	for i = log0 + 1, #Game.log do
		table.insert(ev, Game.log[i])
	end
	print("SELFTEST INFO: solo round log: " .. table.concat(ev, " | "))
	-- the rule under test: one body from the start never triggers the last-one end
	check("last one: solo round is never ended by the last-one rule", soloTotal == 1 and soloReason ~= "last one", soloTotal .. " " .. soloReason .. string.format(" %.1f s", soloTook))
	Game.results()
	for _, k in ipairs({ "ROUND_TIME", "NO_CHAOS", "RESULTS_TIME", "MIN_BODIES" }) do
		Workspace:SetAttribute("Cfg_" .. k, nil)
	end
	Game.forceBotRounds = false
	task.wait(1.5)
end)

---------------------------------------------------------------- 8a. shop: data, coins, cosmetics, paid drops, nuke, revive
-- a fake player (plain table, Parent = nil so remotes skip it; uses a bot body as its character)
local function fakePlayer(id: number, name: string, character: Model?)
	local attrs = {}
	return {
		UserId = id,
		Name = name,
		DisplayName = name,
		Parent = nil,
		Character = character,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end,
		GetAttribute = function(_, k)
			return attrs[k]
		end,
	}
end

run("shop data", function()
	local d = Data.sanitize({ Wins = 3.7, Coins = -5, Owned = { TrailGold = true, [5] = true }, Tokens = "bad", Receipts = { "a", 7, "b" } })
	check("sanitize: numbers floored / clamped", d.Wins == 3 and d.Coins == 0, d.Wins .. " " .. d.Coins)
	check("sanitize: bad fields dropped", d.Owned.TrailGold == true and d.Owned[5] == nil and next(d.Tokens) == nil and #d.Receipts == 2)
	check("sanitize: nil -> blank", Data.sanitize(nil).Coins == 0)
	local p = Data.fake(-901, "Buyer")
	local prod = ShopConfig.product("Cow")
	Shop.grant(p, prod)
	Data.addReceipt(p, "R1")
	check("robux product grants a token", Data.tokens(p, "Cow") == 1)
	check("receipt recorded (no double grant)", Data.hasReceipt(p, "R1") and not Data.hasReceipt(p, "R2"))
	Shop.grant(p, ShopConfig.product("Coins300"))
	check("coin pack adds coins", p.d.Coins == 300, p.d.Coins)
	for i = 1, 80 do
		Data.addReceipt(p, "X" .. i)
	end
	check("receipt list capped", #p.d.Receipts == Data.MAX_RECEIPTS, #p.d.Receipts)
	local ids, dup = {}, false
	for _, pr in ipairs(ShopConfig.PRODUCTS) do
		if pr.productId ~= 0 and ids[pr.productId] then
			dup = true
		end
		ids[pr.productId] = true
	end
	check("no duplicate product ids", not dup)
	Data.profiles[-901] = nil
end)

run("shop cosmetics + coins", function()
	local body = Bots.spawn and nil
	local _ = body
	local b = Bots.list and next(Bots.list) and select(2, next(Bots.list))
	local fp = fakePlayer(-902, "Styler", b and b.model)
	local p = Data.fake(-902, "Styler")
	local ok1 = Shop.buyCosmetic(fp :: any, "TrailGold")
	check("can't buy without coins", ok1 == false)
	Data.addCoins(p, 500)
	local ok2 = Shop.buyCosmetic(fp :: any, "TrailGold")
	check("buy cosmetic with coins", ok2 == true and p.d.Coins == 100 and p.d.Owned.TrailGold and p.d.Equipped.trail == "TrailGold", p.d.Coins)
	local root = b and b.model:FindFirstChild("HumanoidRootPart")
	check("trail applied to character", root and root:FindFirstChild("CosTrail") ~= nil)
	local ok3 = Shop.buyCosmetic(fp :: any, "TrailGold")
	check("buying an owned item doesn't charge again", ok3 ~= nil and p.d.Coins == 100, p.d.Coins)
	Shop.equip(fp :: any, "TrailGold")
	if p.d.Equipped.trail == "TrailGold" then
		Shop.equip(fp :: any, "TrailGold")
	end
	check("unequip removes the trail", p.d.Equipped.trail == nil and root and root:FindFirstChild("CosTrail") == nil)
	check("can't buy an unknown item", Shop.buyCosmetic(fp :: any, "Hack") == false)
	-- coins for surviving
	local before = p.d.Coins
	Shop.payRound({ { kind = "player", player = fp, alive = true, aliveTime = 30 }, { kind = "player", player = fakePlayer(-999, "Nobody"), alive = false, aliveTime = 5 } })
	check("round pays coins (30 s alive + survive bonus)", p.d.Coins - before == math.floor(30 / ShopConfig.COINS_PER_SECONDS) + ShopConfig.SURVIVE_BONUS, p.d.Coins - before)
	Data.profiles[-902] = nil
end)

run("shop drops + nuke + revive", function()
	Workspace:SetAttribute("Cfg_ROUND_TIME", 60)
	Workspace:SetAttribute("Cfg_FIRST_EVENT_AT", 999) -- no random drops: only what we buy
	Workspace:SetAttribute("Cfg_RESULTS_TIME", 1)
	Game.forceBotRounds = true
	table.clear(Game.log)
	table.clear(Shop.log)
	Game.startRound()
	local _, total = Game.aliveCounts()
	Game.unfreezeAll()
	Game.setPhase("Round", 60)
	-- turn one bot into our "player": the buyer
	local rec = Game.participants[1]
	local fp = fakePlayer(-903, "Nuker", rec.model)
	local p = Data.fake(-903, "Nuker")
	rec.kind = "player"
	rec.player = fp :: any
	local okNo = Shop.useToken(fp :: any, "Cow")
	check("can't drop without a token", okNo == false)
	Data.addToken(p, "Cow", 1)
	local okCow = Shop.useToken(fp :: any, "Cow")
	check("paid cow drop works", okCow == true and Data.tokens(p, "Cow") == 0)
	task.wait(Config.get("WARN_TIME") + 0.5)
	local dropped = false
	for _, s in ipairs(Game.log) do
		if s == "drop Cow" then
			dropped = true
		end
	end
	check("paid cow actually fell", dropped)
	check("drop cooldown blocks spam", (function()
		Data.addToken(p, "Piano", 1)
		Shop.lastDrop[-903] = os.clock()
		local ok = Shop.useToken(fp :: any, "Piano")
		Shop.lastDrop[-903] = nil
		return ok == false and Data.tokens(p, "Piano") == 1
	end)())
	-- NUKE
	task.wait(1)
	Game.clearObjects(false)
	-- worst case (seen in a recording): everyone crowded around the buyer at the centre when it lands
	do
		local broot = Game.recRoot(rec)
		if broot then
			local k = 0
			for _, r2 in ipairs(Game.participants) do
				local rr = r2 ~= rec and r2.alive and Game.recRoot(r2)
				if rr then
					k += 1
					local a = k * 2 * math.pi / 7
					r2.model:PivotTo(CFrame.new(broot.Position + Vector3.new(math.cos(a) * 2.6, 0.5, math.sin(a) * 2.6)))
				end
			end
		end
	end
	local aliveBefore = Game.aliveCounts()
	Data.addToken(p, "Nuke", 2)
	local okN = Shop.useToken(fp :: any, "Nuke")
	check("nuke launches", okN == true and Data.tokens(p, "Nuke") == 1)
	local okN2, msg2 = Shop.useToken(fp :: any, "Nuke")
	check("second nuke blocked by cooldown (token kept)", okN2 == false and Data.tokens(p, "Nuke") == 1, msg2)
	task.wait(6)
	local aliveAfter = Game.aliveCounts()
	check("nuke blasts the others off", aliveAfter <= 2 and aliveBefore >= total - 1, aliveBefore .. " -> " .. aliveAfter)
	check("nuke buyer is shielded", rec.alive == true)
	local stray = Workspace:FindFirstChild("NukeFlash") or Workspace:FindFirstChild("NukeRing") or Workspace:FindFirstChild("Nuke")
	check("nuke effects clean up", stray == nil)
	print(string.format("SELFTEST INFO: nuke: %d on before -> %d after (buyer safe=%s)", aliveBefore, aliveAfter, tostring(rec.alive)))
	-- REVIVE: knock our player out, then use a Second Chance
	Game.markOut(rec, "test")
	check("fallen player offered a second chance", rec.offered == true)
	check("round waits for the revive window", Game.reviveHold and Game.reviveHold() == true)
	local okR0 = Shop.useToken(fp :: any, "Revive")
	check("revive needs a token", okR0 == false)
	Data.addToken(p, "Revive", 1)
	local okR = Shop.useToken(fp :: any, "Revive")
	local r = rec.model.PrimaryPart
	local lp = r and Game.plateLocal(r.Position)
	check("second chance puts you back on the plate", okR == true and rec.alive and lp and lp.Y > -2 and lp.Y < 8, tostring(lp))
	check("revive token used", Data.tokens(p, "Revive") == 0)
	Game.markOut(rec, "test")
	Data.addToken(p, "Revive", 1)
	local okR2 = Shop.useToken(fp :: any, "Revive")
	check("only one second chance per round", okR2 == false and Data.tokens(p, "Revive") == 1)
	-- VIP free revive
	local rec2 = Game.participants[2]
	local fp2 = fakePlayer(-904, "Vippy", rec2.model)
	Data.fake(-904, "Vippy")
	rec2.kind = "player"
	rec2.player = fp2 :: any
	rec2.alive = true
	rec2.freeRevive = true
	rec2.revives = 0
	if not rec2.model.PrimaryPart or rec2.model.Humanoid.Health <= 0 then
		check("vip test body alive", false)
	else
		Game.markOut(rec2, "test")
		local okV = Shop.useToken(fp2 :: any, "Revive")
		check("VIP gets a free second chance", okV == true and rec2.alive)
	end
	-- too late
	rec2.revives = 0
	Game.markOut(rec2, "test")
	rec2.outAt = os.clock() - ShopConfig.REVIVE_WINDOW - 1
	Data.addToken(Data.profiles[-904], "Revive", 1)
	check("revive refused after the window", Shop.useToken(fp2 :: any, "Revive") == false)
	-- not in a round
	Game.setPhase("Results", 1)
	Data.addToken(p, "Cow", 1)
	check("no drops outside a round", Shop.useToken(fp :: any, "Cow") == false and Data.tokens(p, "Cow") == 1)
	-- put the fake recs back to bots before cleanup
	rec.kind, rec.player = "bot", nil
	rec2.kind, rec2.player = "bot", nil
	Game.results()
	Data.profiles[-903] = nil
	Data.profiles[-904] = nil
	for _, k in ipairs({ "ROUND_TIME", "FIRST_EVENT_AT", "RESULTS_TIME" }) do
		Workspace:SetAttribute("Cfg_" .. k, nil)
	end
	Game.forceBotRounds = false
	task.wait(2)
end)

---------------------------------------------------------------- 8a2. rewards: daily track, streaks, board; plate plan by player count
local Rewards = require(script.Parent:WaitForChild("Rewards"))
run("rewards", function()
	local p = Data.fake(-777, "DailyTester")
	local c0 = p.d.Coins
	local r1, d1 = Rewards.claimDaily(p, 20000)
	check("daily: first claim = day 1 coins", r1 ~= nil and d1 == 1 and p.d.Coins == c0 + Rewards.DAILY[1].coins, p.d.Coins)
	check("daily: second claim same day refused", Rewards.claimDaily(p, 20000) == nil)
	local _, d2 = Rewards.claimDaily(p, 20001)
	check("daily: next day = day 2", d2 == 2, d2)
	Rewards.claimDaily(p, 20002)
	local tok0 = p.d.Tokens.Cow or 0
	local r4, d4 = Rewards.claimDaily(p, 20003)
	check("daily: day 4 gives a free Cow drop", d4 == 4 and r4.token == "Cow" and (p.d.Tokens.Cow or 0) == tok0 + 1, d4)
	local _, dGap = Rewards.claimDaily(p, 20006)
	check("daily: missing a day restarts at day 1", dGap == 1, dGap)
	for day = 20007, 20012 do
		Rewards.claimDaily(p, day)
	end
	local _, dWrap = Rewards.claimDaily(p, 20013)
	check("daily: after day 7 the track starts again", dWrap == 1, dWrap)
	-- streaks
	local q = Data.fake(-778, "StreakTester")
	local b1, s1 = Rewards.applyStreak(q, true)
	local b2, s2 = Rewards.applyStreak(q, true)
	local b3, s3 = Rewards.applyStreak(q, true)
	check("streak counts rounds survived in a row", s1 == 1 and s2 == 2 and s3 == 3, s3)
	check("streak bonus from 2 in a row", b1 == 0 and b2 == 2 * Rewards.STREAK_COINS and b3 == 3 * Rewards.STREAK_COINS, b2 .. "/" .. b3)
	local _, s4, lost = Rewards.applyStreak(q, false)
	check("falling resets the streak (and says which streak was lost)", s4 == 0 and lost == 3 and q.d.BestStreak == 3, lost)
	for _ = 1, 30 do
		Rewards.applyStreak(q, true)
	end
	local bCap = Rewards.applyStreak(q, true)
	check("streak bonus is capped", bCap == Rewards.STREAK_CAP * Rewards.STREAK_COINS, bCap)
	check("saved fields survive sanitize", Data.sanitize(q.d).Streak == q.d.Streak and Data.sanitize(q.d).BestStreak == q.d.BestStreak and Data.sanitize(p.d).DailyDay == p.d.DailyDay)
	check("old saves (no streak fields) load as 0", Data.sanitize({ Wins = 5, Coins = 9 }).Streak == 0 and Data.sanitize({ Wins = 5 }).Wins == 5)
	Data.profiles[-777] = nil
	Data.profiles[-778] = nil
	-- board
	local board = Map.world.Lobby:FindFirstChild("WinsBoard")
	check("TOP WINS board in the lobby", board ~= nil)
	check("TOP KOs board in the lobby", Map.world.Lobby:FindFirstChild("KOBoard") ~= nil)
	Rewards.showRows({ { name = "Alpha", wins = 12 }, { name = "Beta", wins = 7 } })
	local gui = board and board:FindFirstChildOfClass("SurfaceGui")
	check("board shows names + wins, best first", gui and gui.Name1.Text == "Alpha" and gui.Wins1.Text == "12" and gui.Name2.Text == "Beta" and gui.Name3.Text == "-")
	-- plate plan by real player count
	local p1, n1 = Game.shrinkPlan(1)
	local p2, n2 = Game.shrinkPlan(2)
	local p4, n4 = Game.shrinkPlan(4)
	local p0, n0 = Game.shrinkPlan(0)
	check("1-2 players: one early crumble straight to the last ring", n1 == "duo" and n2 == "duo" and #p2 == 1 and p2[1].r == Map.radii()[1] and p2[1].at <= 0.2)
	check("3-4 players: all breaks, sooner", n4 == "mid" and #p4 == 3 and p4[3].at < Config.SHRINK_STEPS[3].at)
	check("5+ / bot-only: normal plan", n0 == "normal" and p0 == Config.SHRINK_STEPS)
	local _ = p1
end)

-- skipping rings: one crumble straight to the last ring takes every outer ring at once
run("duo shrink", function()
	Game.forceBotRounds = true
	Game.round += 1
	Map.buildRings()
	Game.setPlateR(Config.PLATE_RADIUS)
	Game.setSafeR(Config.PLATE_RADIUS)
	Game.setPhase("Round", 20)
	local rs = Map.radii()
	Game.shrinkTo(rs[1], 0.4)
	local gone = true
	for k = 1, #rs - 1 do
		if Map.rings[k] ~= nil then
			gone = false
		end
	end
	check("duo crumble removes every outer ring at once", gone and Game.plateR == rs[1], Game.plateR)
	Map.buildRings()
	Game.setPlateR(Config.PLATE_RADIUS)
	Game.setSafeR(Config.PLATE_RADIUS)
	Game.setPhase("Idle", 0)
	Game.forceBotRounds = false
	task.wait(1)
end)

-- landed objects barely stay (real lifetime)
run("object lifetime", function()
	Workspace:SetAttribute("Cfg_OBJECT_LIFETIME", nil)
	Game.forceBotRounds = true
	Game.round += 1
	Game.setPhase("Round", 20)
	Game.dropObject("Cow", Vector3.new(12, 0, -10), 0.4)
	task.wait(0.4 + 0.5)
	check("object still there right after landing", #Game.objects == 1, #Game.objects)
	task.wait(Config.OBJECT_LIFETIME + 0.4)
	check("object poofs 1-2 s after landing", #Game.objects == 0, #Game.objects)
	check("object lifetime is 1-2 s", Config.OBJECT_LIFETIME >= 1 and Config.OBJECT_LIFETIME <= 2, Config.OBJECT_LIFETIME)
	Game.clearObjects(false)
	Game.setPhase("Idle", 0)
	Game.forceBotRounds = false
	task.wait(2)
end)

---------------------------------------------------------------- 8a3. extras: twists, pickups, KOs, crown, ghosts
local Extras = require(script.Parent:WaitForChild("Extras"))
run("extras", function()
	Bots.paused = true
	Game.botActionsOff = true
	Game.forceBotRounds = true
	Game.round += 1
	Game.clearObjects(false)
	Map.buildRings()
	Game.setPlateR(Config.PLATE_RADIUS)
	Game.setSafeR(Config.PLATE_RADIUS)
	local b1, b2, b3 = Bots.list[1], Bots.list[2], Bots.list[3]
	Game.participants = {
		{ kind = "bot", bot = b1, model = b1.model, alive = true },
		{ kind = "bot", bot = b2, model = b2.model, alive = true },
		{ kind = "bot", bot = b3, model = b3.model, alive = true },
	}
	local r1, r2, r3 = Game.participants[1], Game.participants[2], Game.participants[3]
	b1.model:PivotTo(CFrame.new(-6, Config.PLATE_Y + 3.2, 0))
	b2.model:PivotTo(CFrame.new(6, Config.PLATE_Y + 3.2, 0))
	b3.model:PivotTo(CFrame.new(0, Config.PLATE_Y + 3.2, 14))
	Game.setPhase("Round", 40)
	task.wait(0.5)

	-- twists: each one applies and cleans up
	local g0 = Workspace.Gravity
	for _, k in ipairs(Extras.MOD_ORDER) do
		Extras.applyMod(k, Game.participants)
		local ok = ReplicatedStorage:GetAttribute("Mod") == k
		if k == "ICE" then
			ok = ok and Config.get("SLIDE_K") > Config.SLIDE_K and Map.plateModel.Surface.Material == Enum.Material.Ice
		elseif k == "LOWGRAV" then
			ok = ok and Workspace.Gravity < g0
		elseif k == "GIANTS" then
			ok = ok and math.abs(b1.model:GetScale() - 1.5) < 0.05
		elseif k == "DOUBLE" then
			ok = ok and Config.get("MOD_DOUBLE") == true
		elseif k == "NIGHT" then
			ok = ok and game:GetService("Lighting").ClockTime < 3 and Map.world:FindFirstChild("NightSpot") ~= nil
		elseif k == "BOUNCY" then
			ok = ok and Config.get("JUMP_HEIGHT") > Config.JUMP_HEIGHT
		end
		check("twist " .. k .. " applies", ok)
		Extras.clearMod(Game.participants)
	end
	check("twists clean up (gravity, light, plate, scale, config)", Workspace.Gravity == g0 and game:GetService("Lighting").ClockTime > 10
		and Map.plateModel.Surface.Material ~= Enum.Material.Ice and math.abs(b1.model:GetScale() - 1) < 0.05
		and Config.get("SLIDE_K") == Config.SLIDE_K and Config.get("MOD_DOUBLE") == false and Map.world:FindFirstChild("NightSpot") == nil)
	check("first round of a server is classic", (function()
		local saved = Extras.roundsSeen
		Extras.roundsSeen = 0
		local k = Extras.pickMod()
		Extras.roundsSeen = saved
		return k == nil
	end)())
	b1.model:PivotTo(CFrame.new(-6, Config.PLATE_Y + 3.2, 0))
	task.wait(0.5)

	-- pickups: walk over one = it triggers
	local function at(rec, lx, lz)
		local p = Map.plateCore.CFrame:PointToWorldSpace(Vector3.new(lx, Config.PLATE_THICK / 2 + 3.1, lz))
		rec.model:PivotTo(CFrame.new(p))
	end
	at(r3, 0, 14)
	task.wait(0.3)
	local pk = Extras.spawnPickup("Boots", 0, 14)
	task.wait(0.4)
	check("pickup grabbed by walking over it", pk ~= nil and pk.model.Parent == nil and #Extras.pickups == 0, #Extras.pickups)
	check("heavy boots: holder can't be pushed", (r3.heavyUntil or 0) > os.clock())
	at(r1, 0, 9)
	b1.model:PivotTo(CFrame.lookAt(b1.root.Position, b3.root.Position))
	task.wait(0.2)
	local p3 = b3.root.Position
	table.clear(Game.shoveAt)
	table.clear(Game.shovedAt)
	local pushed = Game.tryShove(r1)
	task.wait(0.5)
	check("push on heavy boots is blocked", not pushed and (b3.root.Position - p3).Magnitude < 4, (b3.root.Position - p3).Magnitude)
	r3.heavyUntil = nil
	at(r2, 20, -10)
	task.wait(0.3)
	local y0 = b2.root.Position.Y
	Extras.spawnPickup("Spring", 20, -10)
	local maxY = y0
	for _ = 1, 15 do
		task.wait(0.05)
		maxY = math.max(maxY, b2.root.Position.Y)
	end
	check("spring launches you up", maxY > y0 + 6, string.format("%.1f", maxY - y0))
	task.wait(1.5)
	at(r2, -20, -12)
	task.wait(0.3)
	local q0 = b2.root.Position
	Extras.spawnPickup("Banana", -20, -12)
	task.wait(0.5)
	check("banana slips you away", (b2.root.Position - q0).Magnitude > 4, string.format("%.1f", (b2.root.Position - q0).Magnitude))
	task.wait(1)
	Extras.clearPickups()
	local before = #Extras.pickups
	Extras.nextPickup = 0
	Extras.roundTick(1)
	check("round tick drops pickups", #Extras.pickups == before + 1, #Extras.pickups)
	Extras.clearPickups()

	-- KO + crown steal
	Extras.giveCrown(r3, "test")
	check("crown is worn", b3.model:FindFirstChild("TiltCrown") ~= nil)
	local kos = 0
	for _, s in ipairs(Game.log) do
		if string.find(s, "^ko ") then
			kos += 1
		end
	end
	r3.lastShovedBy = r1
	r3.lastShovedAt = os.clock()
	Game.markOut(r3, "fell")
	task.wait(0.3)
	local kos2 = 0
	for _, s in ipairs(Game.log) do
		if string.find(s, "^ko ") then
			kos2 += 1
		end
	end
	check("pushed off = KO for the pusher", kos2 == kos + 1, kos2 - kos)
	check("pushing the crown holder off steals the crown", r1.crowned == true and b1.model:FindFirstChild("TiltCrown") ~= nil and b3.model:FindFirstChild("TiltCrown") == nil)
	r2.lastShovedBy = nil
	Game.markOut(r2, "fell")
	task.wait(0.3)
	local kos3 = 0
	for _, s in ipairs(Game.log) do
		if string.find(s, "^ko ") then
			kos3 += 1
		end
	end
	check("falling on your own is not a KO", kos3 == kos2, kos3 - kos2)
	-- results: the surviving holder keeps the crown
	Game.onResults(Game.participants)
	check("survivor with the crown keeps it", Extras.crown ~= nil and Extras.crown.bot == b1)
	Game.onRoundOver(Game.participants)
	check("crown model removed after the round", b1.model:FindFirstChild("TiltCrown") == nil)

	-- ghosts (needs a real player: only checked when one is in the server; else the drop logic is checked on a fake)
	local fakeRec = { kind = "player", player = { DisplayName = "GhostTester", SetAttribute = function() end }, model = b2.model, alive = false, ghost = true, ghostDrops = 0, ghostNext = 0 }
	Game.setPhase("Round", 20)
	b2.model:PivotTo(CFrame.new(5, Config.PLATE_Y + 40 + 3, -5))
	task.wait(0.2)
	local n0 = Game.fallId
	local ok1 = Extras.ghostDrop(fakeRec)
	local ok2 = Extras.ghostDrop(fakeRec)
	check("ghost can drop junk", ok1 == true and Game.fallId == n0 + 1)
	check("ghost drop has a cooldown", ok2 == false)
	fakeRec.ghostNext = 0
	fakeRec.ghostDrops = Config.GHOST_MAX
	check("ghost junk is limited per round", Extras.ghostDrop(fakeRec) == false)
	check("ghost junk kinds exist", Objects.info("Boot") ~= nil and Objects.info("Fish") ~= nil and Objects.build("Boot") ~= nil and Objects.build("Fish") ~= nil)
	check("ghost floor builds high above the plate", Extras.buildGhostFloor().Position.Y > Config.PLATE_Y + 30)
	task.wait(Config.GHOST_WARN + 0.3)
	Game.clearObjects(false)

	Game.participants = {}
	Game.setPhase("Idle", 0)
	Game.forceBotRounds = false
	for i, bt in ipairs(Bots.list) do
		bt.model:PivotTo(CFrame.new(Map.lobbySpot(i)))
		pcall(function()
			bt.model:ScaleTo(1)
		end)
	end
	Bots.paused = false
	Game.botActionsOff = false
	task.wait(1)
end)

---------------------------------------------------------------- 8b. realistic pacing (real drop gaps, 45 s): how many bots last?
local pacing = {}
local chaosStats = {}
for rep = 1, 2 do
run("pacing " .. rep, function()
	-- a full real round (70 s, real drop timing and weight ramp)
	Workspace:SetAttribute("Cfg_RESULTS_TIME", 1)
	Workspace:SetAttribute("Cfg_OBJECT_LIFETIME", nil)
	Workspace:SetAttribute("Cfg_LAST_ONE_DELAY", 999) -- difficulty marks need the full 70 s
	Game.forceBotRounds = true
	Game.startRound()
	local _, total = Game.aliveCounts()
	Game.unfreezeAll()
	Game.setPhase("Round", Config.ROUND_TIME)
	local marks = {}
	for _, t in ipairs({ 15, 30, 45, 60 }) do
		task.delay(t, function()
			marks[t] = Game.aliveCounts()
		end)
	end
	local log0 = #Game.log
	local t0 = os.clock()
	Game.runRound()
	local alive = Game.aliveCounts()
	local ev = {}
	for i = log0 + 1, #Game.log do
		local s = Game.log[i]
		if string.find(s, "^out ") or string.find(s, "^shrink") or string.find(s, "^shove") then
			table.insert(ev, string.format("%.0f:%s", (Game.logT[i] or t0) - t0, s))
		end
	end
	print("SELFTEST INFO: round " .. rep .. " events: " .. table.concat(ev, " | "))
	local quakes, maxT, lurches, drops = 0, 0, 0, 0
	for i = log0 + 1, #Game.log do
		if Game.log[i] == "quake" then
			quakes += 1
		elseif Game.log[i] == "lurch" then
			lurches += 1
		elseif string.find(Game.log[i], "^drop ") then
			drops += 1
		end
	end
	maxT = Game.maxTiltSeen or 0
	print(string.format("SELFTEST INFO: round %d chaos: %d quakes, %d lurches, %d random drops, max tilt %.1f", rep, quakes, lurches, drops, maxT))
	table.insert(chaosStats, { quakes = quakes, maxT = maxT, lurches = lurches, drops = drops })
	print(string.format("SELFTEST INFO: full round %d: on at 15s=%s 30s=%s 45s=%s 60s=%s end=%d (of %d)", rep, tostring(marks[15]), tostring(marks[30]), tostring(marks[45]),
		tostring(marks[60]), alive, total))
	table.insert(pacing, { m20 = marks[15] or 0, m45 = marks[30] or 0, finish = alive, total = total })
	Game.results()
	Workspace:SetAttribute("Cfg_RESULTS_TIME", nil)
	Workspace:SetAttribute("Cfg_LAST_ONE_DELAY", nil)
	Game.forceBotRounds = false
end)
end
do
	local early, mid, fell = 0, 0, 0
	for _, p in ipairs(pacing) do
		early += p.m20
		mid += p.m45
		if p.finish < p.total then
			fell += 1
		end
	end
	-- hectic, fast version (sir Oct 15: "harder", "faster pace", 70 s rounds): most still on at 15 s, some at 30 s
	check("not too hard: on average 5+ of 7 still on at 15 s", early >= 5 * #pacing, early)
	check("not impossible: 2+ bots still on at 30 s across the full rounds (bot-only, noisy)", mid >= 2, mid)
	check("not too easy: people fall in every full round", fell == #pacing, fell)
	local q, mt = 0, 0
	for _, c in ipairs(chaosStats) do
		q += c.quakes
		mt = math.max(mt, c.maxT)
	end
	check("hectic: earthquakes happen in full rounds (1+ per round)", q >= #chaosStats, q)
	local lu, dr = 0, 0
	for _, c in ipairs(chaosStats) do
		lu += c.lurches
		dr += c.drops
	end
	check("the plate lurches on its own (6+ per round)", lu >= 6 * #chaosStats, lu)
	check("no random objects fall in a normal round", dr == 0, dr)
	check("hectic: the plate tilts a lot (30+ degrees seen; no drops now, peak varies 32-40)", mt >= 30, mt)
end

Workspace:SetAttribute("Cfg_OBJECT_LIFETIME", 15)

---------------------------------------------------------------- 8c. shrinking plate + shoving + scripted landing
run("shrink + shove", function()
	Bots.paused = true
	Game.botActionsOff = true
	Game.forceBotRounds = true
	Game.round += 1
	Map.buildRings()
	Game.setPlateR(Config.PLATE_RADIUS)
	Game.setSafeR(Config.PLATE_RADIUS)
	local rs = Map.radii()
	check("plate has rings to break", #rs == #Config.SHRINK_STEPS + 1 and #(Map.rings[#rs - 1] or {}) > 0, #rs)
	local a, b = Bots.list[1], Bots.list[2]
	Game.participants = {
		{ kind = "bot", bot = a, model = a.model, alive = true },
		{ kind = "bot", bot = b, model = b.model, alive = true },
	}
	Game.setPhase("Round", 30)
	Game.unfreezeAll()
	-- shove: a faces b from 3 studs; b gets pushed a little, not flung
	a.model:PivotTo(CFrame.lookAt(Vector3.new(0, Config.PLATE_Y + 3.2, 0), Vector3.new(3, Config.PLATE_Y + 3.2, 0)))
	b.model:PivotTo(CFrame.new(3, Config.PLATE_Y + 3.2, 0))
	task.wait(0.4)
	local p0 = b.root.Position
	local ok = Game.tryShove(Game.participants[1])
	check("bot can shove the one in front", ok)
	check("shove has a cooldown", not Game.tryShove(Game.participants[1]))
	local maxD = 0
	local t0 = os.clock()
	while os.clock() - t0 < 1.5 do
		local d = (Vector3.new(b.root.Position.X, 0, b.root.Position.Z) - Vector3.new(p0.X, 0, p0.Z)).Magnitude
		maxD = math.max(maxD, d)
		task.wait()
	end
	check("shove knocks them well away (9-40 studs; tilt adds slide)", maxD >= 9 and maxD <= 40, string.format("%.1f", maxD))
	local hb = b.model:FindFirstChildOfClass("Humanoid")
	check("shoved bot is knocked over, then gets back up", hb ~= nil and not hb.PlatformStand, hb and hb.PlatformStand)
	check("still on the plate after one shove", Game.onPlate(Game.plateLocal(b.root.Position), 1), Game.plateLocal(b.root.Position))
	-- MISSED push: pushing at nobody = you lunge forward and fall over
	task.wait(Config.SHOVE_COOLDOWN + 0.2)
	-- (pusher in the middle, facing away from b: near the rim it could slide off before the push and skew the check)
	a.model:PivotTo(CFrame.lookAt(Vector3.new(0, Config.PLATE_Y + 3.2, 0), Vector3.new(-10, Config.PLATE_Y + 3.2, 0)))
	b.model:PivotTo(CFrame.new(12, Config.PLATE_Y + 3.2, 0))
	task.wait(0.4)
	Game.shoveAt[a] = nil -- start the miss check from a clean cooldown
	local aliveBefore = Game.participants[1].alive
	local cdLeft = Config.get("SHOVE_COOLDOWN") - (os.clock() - (Game.shoveAt[a] or -math.huge))
	local nearB = (a.root.Position - b.root.Position).Magnitude
	local wa = a.root.Position
	local logW = #Game.log
	local okW = Game.tryShove(Game.participants[1])
	local ha = a.model:FindFirstChildOfClass("Humanoid")
	task.wait(0.1)
	local downW = ha ~= nil and ha.PlatformStand
	task.wait(0.6)
	local moved = (Vector3.new(a.root.Position.X, 0, a.root.Position.Z) - Vector3.new(wa.X, 0, wa.Z)).Magnitude
	local whiffed = false
	for i = logW + 1, #Game.log do
		if string.find(Game.log[i], "^whiff") then
			whiffed = true
		end
	end
	check("missed push: you lunge forward and trip", not okW and whiffed and downW and moved >= 4, string.format("alive %s whiff %s down %s moved %.1f cdLeft %.2f distB %.1f phase %s force %s", tostring(aliveBefore), tostring(whiffed), tostring(downW), moved, cdLeft, nearB, tostring(Game.phase), tostring(Game.forceBotRounds)))
	check("missed push uses the full cooldown", not Game.tryShove(Game.participants[1]))
	task.wait(math.max(0, Config.SHOVE_COOLDOWN - 0.7 + 0.15))
	local logC = #Game.log
	Game.tryShove(Game.participants[1])
	local triedAgain = false
	for i = logC + 1, #Game.log do
		if string.find(Game.log[i], "^whiff") or string.find(Game.log[i], "^shove") then
			triedAgain = true
		end
	end
	check("a miss costs a LONGER wait than a hit (still locked after the normal cooldown)", not triedAgain)
	task.wait(1.2)
	check("tripped bot gets back up", ha ~= nil and not ha.PlatformStand)
	-- DODGE: a dodging body can't be pushed; the pusher whiffs instead
	task.wait(Config.WHIFF_COOLDOWN)
	a.model:PivotTo(CFrame.lookAt(Vector3.new(0, Config.PLATE_Y + 3.2, 0), Vector3.new(3, Config.PLATE_Y + 3.2, 0)))
	b.model:PivotTo(CFrame.new(3, Config.PLATE_Y + 3.2, 0))
	task.wait(0.4)
	table.clear(Game.dodgeAt)
	local d0 = b.root.Position
	local okD = Game.tryDodge(Game.participants[2], Vector3.new(0, 0, 1))
	check("dodge works", okD)
	local okS = Game.tryShove(Game.participants[1])
	check("push on a dodging body misses", not okS)
	task.wait(0.5)
	local dd = (Vector3.new(b.root.Position.X, 0, b.root.Position.Z) - Vector3.new(d0.X, 0, d0.Z)).Magnitude
	check("dodge dashes you a few studs (4-16)", dd >= 4 and dd <= 16, string.format("%.1f", dd))
	check("dodge has a cooldown", not Game.tryDodge(Game.participants[2], Vector3.new(1, 0, 0)))
	task.wait(1.2)
	-- standing on a landed object is no safe spot: it slides you off
	b.model:PivotTo(CFrame.new(-20, Config.PLATE_Y + 3.2, -20))
	Game.dropObject("Cow", Vector3.new(-20, 0, -20), 0.5)
	task.wait(1.2)
	local cow = Game.objects[#Game.objects]
	if cow and cow.model.PrimaryPart then
		local top = cow.model.PrimaryPart.Position + Vector3.new(0.6, cow.model.PrimaryPart.Size.Y / 2 + 3.2, 0.3)
		b.model:PivotTo(CFrame.new(top))
		task.wait(0.15)
		local under = Objects.under(b.root)
		check("a bot on a cow is seen as standing on it", under == cow.model, under and under.Name)
		local v = Objects.slideVelocity(b.root, Map.plateCore, Config, TiltMath, Game.plateR)
		check("standing on an object slides you off even on a flat plate", v.Magnitude >= 4, string.format("%.1f", v.Magnitude))
	else
		check("cow landed for the stand-on test", false)
	end
	-- leave the plate empty for the next tests
	Game.clearObjects(false)
	task.wait(0.3)
	-- scripted landing: lands exactly on the spot, on time
	Game.dropObject("Anvil", Vector3.new(-12, 0, 8), 0.8)
	task.wait(0.3)
	check("not landed before the warning ends", #Game.objects == 0, #Game.objects)
	task.wait(0.8)
	local o = Game.objects[1]
	check("lands when the warning ends", o ~= nil and o.landed)
	if o and o.model.PrimaryPart then
		local lp = Game.plateLocal(o.model.PrimaryPart.Position)
		check("lands on the marked spot", math.abs(lp.X + 12) < 1.5 and math.abs(lp.Z - 8) < 1.5, lp)
		check("fall id tagged for the client animation", (o.model:GetAttribute("FallId") or 0) > 0)
	end
	Game.clearObjects(false)
	-- shrink: outer ring breaks, a bot standing on it falls, the middle stays
	local outer = rs[#rs - 1]
	a.model:PivotTo(CFrame.new(0, Config.PLATE_Y + 3.2, 0))
	b.model:PivotTo(CFrame.new(outer + 3, Config.PLATE_Y + 3.2, 0))
	Game.dropObject("Duck", Vector3.new(outer + 4, 0, -6), 0.3)
	task.wait(0.6)
	check("duck landed on the outer ring", #Game.objects == 1, #Game.objects)
	Game.participants[2].alive = true
	Game.shrinkTo(outer, 1)
	check("plate radius shrank", Game.plateR == outer and ReplicatedStorage:GetAttribute("PlateR") == outer, Game.plateR)
	check("outer ring parts gone from the plate", Map.rings[#rs - 1] == nil)
	check("objects on the broken ring fall with it", #Game.objects == 0, #Game.objects)
	local t1 = os.clock()
	while os.clock() - t1 < 6 and b.root.Position.Y > Config.PLATE_Y - 20 and not Game.participants[2].sent do
		task.wait(0.1)
	end
	check("bot on the broken ring falls", b.root.Position.Y < Config.PLATE_Y - 10 or Game.participants[2].sent, b.root.Position.Y)
	check("bot in the middle is fine", Game.onPlate(Game.plateLocal(a.root.Position), 1), Game.plateLocal(a.root.Position))
	-- a drop aimed at the gone ring misses
	Game.dropObject("Duck", Vector3.new(outer + 4, 0, 0), 0.2)
	task.wait(0.5)
	check("drop on the gone ring misses", #Game.objects == 0, #Game.objects)
	-- next round restores the plate
	Map.buildRings()
	Game.setPlateR(Config.PLATE_RADIUS)
	check("plate rebuilt for the next round", Map.rings[#rs - 1] ~= nil and #Map.rings[#rs - 1] > 0)
	Game.participants = {}
	Game.setPhase("Idle", 0)
	Game.forceBotRounds = false
	for i, bt in ipairs(Bots.list) do
		bt.model:PivotTo(CFrame.new(Map.lobbySpot(i)))
	end
	Bots.paused = false
	Game.botActionsOff = false
end)

---------------------------------------------------------------- 9. stray parts
run("leaks", function()
	task.wait(4) -- poof effects + sound emitters clean themselves up
	local stray = {}
	for _, c in ipairs(Workspace:GetChildren()) do
		if c:IsA("BasePart") and c.Name ~= "Terrain" then
			table.insert(stray, c.Name)
		end
	end
	check("no stray parts in workspace", #stray == 0, table.concat(stray, ","))
	local objs = Map.world.Objects:GetChildren()
	check("objects folder empty", #objs == 0, #objs)
end)

Workspace:SetAttribute("Cfg_OBJECT_LIFETIME", nil)
print(string.format("SELFTEST DONE passed=%d failed=%d", passed, failed))
