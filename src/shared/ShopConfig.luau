-- ShopConfig: everything players can buy. Robux product / pass ids are filled in at publish time
-- (tools/make_tilt_products.py creates them on the Tilt universe). While an id is 0 the item can't be bought with Robux
-- in a live server; in Studio a test-only remote grants it so everything can be tested before publishing.
local ShopConfig = {}

-- Robux developer products (one-time, can be bought again). kind: "token" adds to Tokens[key]; "coins" adds coins.
ShopConfig.PRODUCTS = {
	{ key = "Cow", name = "Drop a Cow", desc = "Drop it on the crowd", robux = 25, kind = "token", productId = 3718808617 },
	{ key = "Piano", name = "Drop a Piano", desc = "Drop it on the crowd", robux = 49, kind = "token", productId = 3718808666 },
	{ key = "Meteor", name = "Drop a Meteor", desc = "Drop it on the crowd", robux = 75, kind = "token", productId = 3718808717 },
	{ key = "Nuke", name = "NUKE", desc = "Blast everyone off. You're safe", robux = 149, kind = "token", productId = 3718808758 },
	{ key = "Revive", name = "Second Chance", desc = "Fell? Get back on", robux = 25, kind = "token", productId = 3718808821 },
	{ key = "Coins300", name = "300 Coins", desc = "For trails + dances", robux = 25, kind = "coins", amount = 300, productId = 3718808884 },
	{ key = "Coins1500", name = "1,500 Coins", desc = "Best value", robux = 99, kind = "coins", amount = 1500, productId = 3718808940 },
}

-- Robux game pass
ShopConfig.VIP = {
	key = "VIP",
	name = "VIP",
	desc = "2x coins, free Second Chance, gold tag",
	robux = 149,
	passId = 2038334687,
}

-- Cosmetics bought with coins (earned by surviving)
ShopConfig.COSMETICS = {
	{ id = "TrailWhite", kind = "trail", name = "Cloud Trail", price = 100, color = Color3.fromRGB(255, 255, 255) },
	{ id = "TrailShadow", kind = "trail", name = "Shadow Trail", price = 200, color = Color3.fromRGB(40, 40, 46) },
	{ id = "TrailGold", kind = "trail", name = "Gold Trail", price = 400, color = Color3.fromRGB(226, 190, 112) },
	{ id = "TrailFire", kind = "trail", name = "Fire Trail", price = 700, color = Color3.fromRGB(255, 120, 40), color2 = Color3.fromRGB(255, 220, 90) },
	{ id = "DanceCheer", kind = "dance", name = "Cheer", price = 150, anim = 507770677 },
	{ id = "DanceGroove", kind = "dance", name = "Groove", price = 300, anim = 507771019 },
	{ id = "DanceWild", kind = "dance", name = "Wild Dance", price = 500, anim = 507776043 },
	{ id = "DanceRobot", kind = "dance", name = "Robot", price = 800, anim = 507777268 },
}

-- coin income
ShopConfig.COINS_PER_SECONDS = 3 -- +1 coin for every 3 s you stay on during a round
ShopConfig.SURVIVE_BONUS = 20
ShopConfig.VIP_MULT = 2

-- in-round rules
ShopConfig.REVIVE_WINDOW = 6 -- seconds after falling in which a Second Chance can be used
ShopConfig.REVIVES_PER_ROUND = 1
ShopConfig.NUKE_COOLDOWN = 15 -- seconds between nukes in one server
ShopConfig.DROP_COOLDOWN = 3 -- seconds between paid drops by the same player

function ShopConfig.product(key: string)
	for _, p in ipairs(ShopConfig.PRODUCTS) do
		if p.key == key then
			return p
		end
	end
	return nil
end

function ShopConfig.productById(id: number)
	if id == 0 then
		return nil
	end
	for _, p in ipairs(ShopConfig.PRODUCTS) do
		if p.productId == id then
			return p
		end
	end
	return nil
end

function ShopConfig.cosmetic(id: string)
	for _, c in ipairs(ShopConfig.COSMETICS) do
		if c.id == id then
			return c
		end
	end
	return nil
end

ShopConfig.DROP_KEYS = { "Cow", "Piano", "Meteor", "Nuke" }

return ShopConfig
