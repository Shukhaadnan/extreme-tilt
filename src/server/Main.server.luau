-- Main: boots the game. SelfTest (Studio "Run" with no players) sets workspace.RunSelfTest before the loop starts.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Game = require(script.Parent:WaitForChild("Game"))
local Shop = require(script.Parent:WaitForChild("Shop"))
local Rewards = require(script.Parent:WaitForChild("Rewards"))
Shop.start() -- hooks first, so profiles loaded during Game.start are published
Rewards.start() -- daily reward + win streak + TOP WINS board (wraps Shop's hooks)
Game.start()
-- twists, KOs, crown, pickups, ghosts (needs the remotes + map from Game.start)
require(script.Parent:WaitForChild("Extras")).start()

-- In Studio "Run" mode (no player joins) the SelfTest script drives the game instead of the normal loop.
local function selfTestMode(): boolean
	if workspace:GetAttribute("RunSelfTest") == true then
		return true
	end
	if not RunService:IsStudio() then
		return false
	end
	local t = os.clock()
	while os.clock() - t < 5 do
		if #Players:GetPlayers() > 0 then
			return false
		end
		task.wait(0.25)
	end
	return #Players:GetPlayers() == 0
end

if selfTestMode() then
	workspace:SetAttribute("SelfTestMode", true)
	return
end

task.spawn(Game.loop)
