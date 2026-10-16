-- Sfx: shared sound helper (ReplicatedStorage.Sfx). Every call is pcall-safe:
-- a missing or broken sound never throws.
--   Sfx.play(name, partOrAttachmentOrPosition?, volume?, pitch?) -> Sound?   one-shot, Debris-cleaned
--   Sfx.loop(name, target?, volume?, pitch?, props?) -> Sound?              persistent looping sound
--   Sfx.music(name) -> Sound?                                                client-only background music
--   Sfx.setMuted(bool) / Sfx.toggleMuted()                                   client master mute
-- On the server, a 2D play (no target) is forwarded to every client via the "PlaySfx" RemoteEvent.
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sfx = {}

-- Verified public audio (Roblox / ProSoundEffects / APM) + meme sounds found in the public toolbox
-- search. Every id is checked in Studio by SelfTest (PreloadAsync + TimeLength > 0).
Sfx.IDS = {
	-- memes
	metalPipe = 6729922069,
	fahhh = 137533276939300,
	vineBoom = 139557908315922,
	bruh = 140007222940724,
	ohNo = 138503230526760,
	airhorn = 5671650124,
	boing = 2772396665,
	bonk = 3765689841,
	yeet = 525743689,
	wilhelm = 160718677,
	explosion = 139771888058836,
	-- effects
	windLoop = 84289423099646,
	windWhoosh = 9120698415,
	scream = 9125652432,
	splat = 12222152,
	rocketLaunch = 12222065,
	oof = 79348298352567,
	coin = 127645268874265,
	uiClick = 15675059323,
	notify = 17208361335,
	victory = 12222253,
	swoosh = 12222200,
	rocketWhoosh = 12222095,
	fastWhoosh = 9126229255,
	sparkle = 9126073001,
	chimes = 9116395089,
	pop = 9113263649,
	fireworks = 9114447104,
	crowdCheer = 9120974911,
	buzzer = 9113085764,
	cashRegister = 9113728049,
	zap = 9120985853,
	-- v12 sound pass (ProSoundEffects / Roblox, each checked by ear-proxy: onset, length, loudness)
	punch = 9117969687, -- Punch Kit Beefy Hit 2: a push landing
	punch2 = 9117969878, -- Punch Kit Beefy Hit 4 (variation)
	swing = 9120742716, -- Whoosh Thick Quick 2: the push swing
	dash = 9126047550, -- Synth Air Whoosh karate swish: dodge
	slideWhistle = 9119198140, -- Slide Whistle 4 (falls 1.2k -> 400 Hz): missed push
	thud = 9113480915, -- Body Fall Thud 2: face-plant
	birds = 9113844972, -- cartoon chirps while dizzy
	creak = 9125407239, -- wood creak: the plate groans before a lurch
	quake = 9114221443, -- Earthquake Debris 6
	rockBreak = 9118614718, -- Rock Impact 1: plate edge breaks off
	beep = 9117060548, -- countdown beep
	ghostGiggle = 9114571613, -- you became a ghost
	musicHappyAdventure = 9047876673,
	musicHappySong = 1843404009,
}

-- Backup ids (SelfTest reports which of these load, so a broken primary can be swapped quickly)
Sfx.ALT = {
	metalPipe = { 139562015239082, 135804355522741, 132108923310487, 140400702305693 },
	fahhh = { 139259088251978, 117345482811000, 116069970994133, 74089268579262 },
	vineBoom = { 118531391229948, 115718732840987, 132889984353619, 140367458608473 },
	bruh = { 133319559387398, 120732085616463 },
	ohNo = { 80953537348100 },
	airhorn = { 130363373001396, 132821740351790, 125565494697481 },
	boing = { 6547434405, 131916027000817, 76707773145268 },
	bonk = { 121281067238166, 132937320140224, 4831249447 },
	yeet = { 107692075593682, 5819197968 },
	wilhelm = { 605536910, 170399891 },
	explosion = { 140278004623742, 138533090376585 },
	windLoop = { 687874741, 6544555787 },
}

-- Sounds that are meant to loop
Sfx.LOOPED = {
	windLoop = true,
	musicHappyAdventure = true,
	musicHappySong = true,
}

Sfx.LIBRARY_NAME = "SfxLibrary"
Sfx.DEFAULT_VOLUME = 0.5
Sfx.MUSIC_VOLUME = 0.25
Sfx.ONE_SHOT_LIFETIME = 20      -- hard Debris cap for one-shot sounds (seconds)
Sfx.ROLLOFF_MIN = 12
Sfx.ROLLOFF_MAX = 200
Sfx.muted = false

local IS_CLIENT = RunService:IsClient()
local library: Folder? = nil
local masterGroup: SoundGroup? = nil
local musicSound: Sound? = nil
local muteListeners = {}

local function warnOnce(msg)
	-- quiet by design; one line in output helps debugging without spamming
	warn("[Sfx] " .. tostring(msg))
end

function Sfx.url(name: string): string?
	local id = Sfx.IDS[name]
	return id and ("rbxassetid://" .. string.format("%d", id)) or nil
end

-- Client-only master SoundGroup (used for the mute toggle)
local function getGroup(): SoundGroup?
	if not IS_CLIENT then
		return nil
	end
	if masterGroup and masterGroup.Parent then
		return masterGroup
	end
	local ok, g = pcall(function()
		local grp = Instance.new("SoundGroup")
		grp.Name = "SfxMaster_Local"
		grp.Volume = Sfx.muted and 0 or 1
		grp.Parent = SoundService
		return grp
	end)
	masterGroup = ok and g or nil
	return masterGroup
end

-- Folder of pre-created template Sounds in SoundService (created once)
function Sfx.getLibrary(): Folder?
	if library and library.Parent then
		return library
	end
	local ok, lib = pcall(function()
		local existing = SoundService:FindFirstChild(Sfx.LIBRARY_NAME)
		if existing then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = Sfx.LIBRARY_NAME
		for name in pairs(Sfx.IDS) do
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = Sfx.url(name)
			s.Volume = Sfx.DEFAULT_VOLUME
			s.Looped = Sfx.LOOPED[name] == true
			s.Parent = folder
		end
		folder.Parent = SoundService
		return folder
	end)
	library = ok and lib or nil
	return library
end

-- Fresh Sound for `name` (clone of the template, or built from the id table)
local function makeSound(name: string): Sound?
	if type(name) ~= "string" or not Sfx.IDS[name] then
		return nil
	end
	local lib = Sfx.getLibrary()
	local template = lib and lib:FindFirstChild(name)
	local sound
	if template and template:IsA("Sound") then
		sound = template:Clone()
	else
		sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = Sfx.url(name)
		sound.Volume = Sfx.DEFAULT_VOLUME
	end
	local g = getGroup()
	if g then
		sound.SoundGroup = g
	end
	return sound
end

-- Parents a sound to its target. Returns the instance to clean up (holder part or the sound).
local function attach(sound: Sound, target): Instance
	local kind = typeof(target)
	if kind == "Instance" and target:IsA("Model") then
		target = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildWhichIsA("BasePart")
		kind = typeof(target)
	end
	if kind == "Instance" and (target:IsA("BasePart") or target:IsA("Attachment")) then
		sound.RollOffMinDistance = Sfx.ROLLOFF_MIN
		sound.RollOffMaxDistance = Sfx.ROLLOFF_MAX
		sound.Parent = target
		return sound
	elseif kind == "Vector3" then
		local holder = Instance.new("Part")
		holder.Name = "SfxEmitter"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.CFrame = CFrame.new(target)
		holder.Parent = workspace
		sound.RollOffMinDistance = Sfx.ROLLOFF_MIN
		sound.RollOffMaxDistance = Sfx.ROLLOFF_MAX
		sound.Parent = holder
		return holder
	end
	sound.Parent = SoundService -- 2D
	return sound
end

local function findRemote(): RemoteEvent?
	local r = ReplicatedStorage:FindFirstChild("PlaySfx", true)
	return (r and r:IsA("RemoteEvent")) and r or nil
end

-- One-shot sound. target: BasePart / Attachment / Model / Vector3 / nil (2D)
function Sfx.play(name: string, target: any?, volume: number?, pitch: number?): Sound?
	local ok, result = pcall(function()
		if type(name) ~= "string" or not Sfx.IDS[name] then
			return nil
		end
		if not IS_CLIENT and target == nil then
			-- Server has no "2D" listener: forward to all clients
			local remote = findRemote()
			if remote then
				remote:FireAllClients(name, nil, volume, pitch)
			end
			return nil
		end
		if IS_CLIENT and Sfx.muted then
			return nil
		end
		local sound = makeSound(name)
		if not sound then
			return nil
		end
		sound.Looped = false
		if type(volume) == "number" then
			sound.Volume = volume
		end
		if type(pitch) == "number" and pitch > 0 then
			sound.PlaybackSpeed = pitch
		end
		local cleanup = attach(sound, target)
		sound.Ended:Once(function()
			pcall(function()
				cleanup:Destroy()
			end)
		end)
		sound:Play()
		Debris:AddItem(cleanup, Sfx.ONE_SHOT_LIFETIME)
		return sound
	end)
	if not ok then
		warnOnce(result)
		return nil
	end
	return result
end

-- Server: ask clients to play a sound locally (respects their mute). player=nil -> everyone
-- (optionally skipping `except`). target may be a Vector3 / Instance for 3D, or nil for 2D.
function Sfx.fire(player: Player?, name: string, target: any?, volume: number?, pitch: number?, except: Player?)
	pcall(function()
		if IS_CLIENT or not Sfx.IDS[name] then
			return
		end
		local remote = findRemote()
		if not remote then
			return
		end
		if player then
			if player.Parent then
				remote:FireClient(player, name, target, volume, pitch)
			end
		else
			for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
				if p ~= except then
					remote:FireClient(p, name, target, volume, pitch)
				end
			end
		end
	end)
end

-- Persistent looping sound (caller owns it; destroy to stop). props: extra Sound properties.
function Sfx.loop(name: string, target: any?, volume: number?, pitch: number?, props: { [string]: any }?): Sound?
	local ok, result = pcall(function()
		local sound = makeSound(name)
		if not sound then
			return nil
		end
		sound.Looped = true
		if type(volume) == "number" then
			sound.Volume = volume
		end
		if type(pitch) == "number" and pitch > 0 then
			sound.PlaybackSpeed = pitch
		end
		attach(sound, target)
		local anySound: any = sound
		for k, v in pairs(props or {}) do
			pcall(function()
				anySound[k] = v
			end)
		end
		sound:Play()
		return sound
	end)
	if not ok then
		warnOnce(result)
		return nil
	end
	return result
end

-- Client-only looping background music at a small volume
function Sfx.music(name: string): Sound?
	if not IS_CLIENT then
		return nil
	end
	local ok, result = pcall(function()
		if musicSound then
			musicSound:Destroy()
			musicSound = nil
		end
		local sound = makeSound(name)
		if not sound then
			return nil
		end
		sound.Name = "BGM"
		sound.Looped = true
		sound.Volume = Sfx.MUSIC_VOLUME
		sound.Parent = SoundService
		sound:Play()
		musicSound = sound
		return sound
	end)
	if not ok then
		warnOnce(result)
		return nil
	end
	return result
end

function Sfx.setMuted(muted: boolean)
	Sfx.muted = muted == true
	pcall(function()
		local g = getGroup()
		if g then
			g.Volume = Sfx.muted and 0 or 1
		end
	end)
	for _, fn in ipairs(muteListeners) do
		task.spawn(pcall, fn, Sfx.muted)
	end
end

function Sfx.toggleMuted(): boolean
	Sfx.setMuted(not Sfx.muted)
	return Sfx.muted
end

function Sfx.onMuteChanged(fn)
	table.insert(muteListeners, fn)
end

-- Client: preload all library sounds in the background
function Sfx.preload()
	task.spawn(function()
		pcall(function()
			local lib = Sfx.getLibrary()
			if lib then
				ContentProvider:PreloadAsync(lib:GetChildren())
			end
		end)
	end)
end

function Sfx.init(): Folder?
	local lib = Sfx.getLibrary()
	getGroup()
	return lib
end

return Sfx
