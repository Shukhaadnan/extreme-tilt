-- Hud: one scale for every HUD piece so phones get small buttons (sir: "make buttons smaller").
-- desktop: clamp(short side / 1080, 0.5, 1); touch: clamp(short side / 560, 0.62, 0.9). Hud.attach(guiObject) adds a UIScale
-- that follows screen size changes. Hud.touch() = phone/tablet (no keyboard).
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Hud = {}

-- height (unscaled px) of the left column built by ShopUI: coins + SHOP + the 2x2 drop grid. The fall feed goes under it.
Hud.LEFT_COL_H = 186

function Hud.touch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Hud.viewport(): Vector2
	local cam = Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

function Hud.scale(): number
	local v = Hud.viewport()
	if Hud.touch() then
		-- phones: viewport is in points (~393 tall on an iPhone). ~0.7 there = about 30% smaller than the old HUD,
		-- while drop buttons stay ~50x32 pt (still easy to tap)
		return math.clamp(math.min(v.X, v.Y) / 560, 0.62, 0.9)
	end
	return math.clamp(math.min(v.X, v.Y) / 1080, 0.5, 1)
end

local scales = {} :: { UIScale }
function Hud.attach(obj: GuiObject): UIScale
	local u = Instance.new("UIScale")
	u.Name = "HudScale"
	u.Scale = Hud.scale()
	u.Parent = obj
	table.insert(scales, u)
	return u
end

local listeners = {} :: { () -> () }
function Hud.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

local function refresh()
	local k = Hud.scale()
	for _, u in ipairs(scales) do
		if u.Parent then
			u.Scale = k
		end
	end
	for _, fn in ipairs(listeners) do
		task.spawn(fn)
	end
end

local function hookCamera()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
task.defer(hookCamera)

return Hud
