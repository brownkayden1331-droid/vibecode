--[[
	MusicDirector  (LocalScript)  —  layered adaptive score
	Put this in StarterPlayer > StarterPlayerScripts.
	Replaces the old music script AND the AirWhoosh / fling-audio script.

	THE RULES (so layering is on purpose, never a pile-up)
	  There are 5 slots. Each slot plays ONE song at a time, and a slot only
	  switches songs after the old one has faded out (no messy crossfades).

	  MENU        the main menu track (PortalMenu sets player attribute MenuMode).
	              Plays alone: everything else fades out while it is up, and PortalMenu
	              mutes every other sound in the game (footsteps, landings, wind included).
	                main     menu track plays, nothing else
	                loading  total silence
	                pause    normal music, muffled + quieter
	                none     normal adaptive music
	              Put the track(s) in ReplicatedStorage > PortalAssets > OST > "Main Menu"
	              (a Folder of Sounds, or a single Sound). They're picked up even if they
	              replicate after this script starts (that's what kept the menu silent before).

	  BACKGROUND  Portal 1 tracks. Only when NOTHING is happening.
	              Fades out completely as soon as any other music starts,
	              comes back after a quiet spell once things calm down.
	                Calm    Self Esteem Fund
	                Neutral Subject Name Here           (you've been busy solving)
	                Tense   4000 Degrees Kelvin, Procedural Jiggle Bone (danger / hurt)

	  BASE        a sustained Short Segment for what you're in the middle of:
	                Turret   turrets around you (before they fire)
	                Bridge   on a LightBridge = true part
	                <zone>   in a MusicCue = "<folder>" area
	                Portal   you're in the flow: placing portals / going through them a lot

	  ACCENT      a short burst ON TOP of the base — this is the layering:
	                Trust Fling  airborne at 110+ studs/s (until you land),
	                             volume + pitch follow speed, wind gust, landing hit
	                JumpIntro    launched upward (until you land)
	                SpeedRamp    sustained fast running
	              While an accent plays, the base keeps going underneath at
	              BASE_UNDER_ACCENT volume, so the two lock together. Pairs you
	              don't want stacked can be blocked in NO_STACK.

	  SOLO        takes over alone, everything else fades out:
	                Combat   "Taste of Blood" while turrets are actually hurting you
	                Pickup   one Portal segment when you grab the portal gun

	  Max 2 songs at once (base + accent), and they're always the same style.

	MIXING
	  Dialogue ducking (GLaDOSVL sounds / Dialogue = true), gunfire sidechain,
	  hurt = muffled, portal traversal filter whoosh, death tape-stop,
	  beat-synced entries (number attribute BPM on a Sound),
	  player attributes MusicVolume (0..1) and Setting_master (0..1) from the menu,
	  pause = muffled + ducked, DEBUG_HUD readout.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

----------------------------------------------------------------- CONFIG
local VOLUME = { Background = 0.35, Base = 0.45, Accent = 0.55, Combat = 0.45, Pickup = 0.5 }
local BASE_UNDER_ACCENT = 0.55        -- base volume multiplier while an accent is stacked on it

local BACKGROUND_FADE_IN, BACKGROUND_FADE_OUT = 4, 1.5
local IDLE_BEFORE_BACKGROUND = 8      -- seconds of no activity music before Portal 1 may return
local SILENCE_MIN, SILENCE_MAX = 20, 60
local FIRST_BACKGROUND_DELAY = 6
local RESPAWN_SILENCE = { 8, 15 }

-- stacks that are NOT allowed (accent = { base = true }); the base fades out under that accent
local NO_STACK = {
	-- SpeedRamp = { Turret = true },
}

-- feelings
local THREAT_RISE, THREAT_FALL = 3.0, 0.25
local FLOW_PER_TRAVERSAL, FLOW_PER_PORTAL, FLOW_FALL = 0.22, 0.12, 0.035
local TURRET_HEAR_RADIUS = 70
local DAMAGE_THREAT_TIME = 4
local COMBAT_ON, COMBAT_OFF = 0.85, 0.4
local TURRET_ON, TURRET_OFF = 0.3, 0.15
local FLOW_ON, FLOW_OFF = 0.55, 0.25
local TENSE_AT = 0.35                 -- background picks Tense above this danger
local NEUTRAL_AT = 0.3                -- background picks Neutral above this flow

-- velocity (AirWhoosh values)
local FLING_MIN_SPEED, FLING_MAX_SPEED = 110, 260
local FLING_MIN_PITCH, FLING_MAX_PITCH = 0.85, 1.4
local FLING_MIN_VOLUME, FLING_MAX_VOLUME = 0.15, 0.9
local FLING_AIR_FLOOR = 0.35
-- high-velocity landing sounds (the heavy/long fall sounds)
local LANDING_MIN_SPEED = 90
local LANDING_IDS = { "rbxassetid://118820685166023", "rbxassetid://125771603953071", "rbxassetid://77472870658169" }

-- normal/low-velocity landing sounds
local LAND_TILE_IDS = {
	"rbxassetid://126927342017651",
	"rbxassetid://125931025736148",
	"rbxassetid://138538110167299",
	"rbxassetid://84350739625452",
	"rbxassetid://139689579179314",
	"rbxassetid://123211546859752",
	"rbxassetid://100297293631489",
}

-- walking/footstep sounds
local WALK_TILE_IDS = {
	"rbxassetid://87329560813224",
	"rbxassetid://99113637693202",
	"rbxassetid://123207454088306",
	"rbxassetid://83844314043806",
	"rbxassetid://101803163348882",
	"rbxassetid://134170741790765",
	"rbxassetid://107025811393682",
	"rbxassetid://84346437834073",
	"rbxassetid://115553436535072",
	"rbxassetid://136354653906067",
	"rbxassetid://96305826348298",
	"rbxassetid://109012106492017",
	"rbxassetid://120860425010005",
	"rbxassetid://90040627887058",
	"rbxassetid://88182324240935",
	"rbxassetid://94051007171162",
	"rbxassetid://92800193922548",
	"rbxassetid://78003907291710",
	"rbxassetid://91415149149693",
	"rbxassetid://97255512709079",
}

-- metal uses its own landing/step set
local METAL_LAND_IDS = {
	"rbxassetid://88272781262588",
	"rbxassetid://99804614410111",
	"rbxassetid://105412548054736",
	"rbxassetid://75621126114383",
	"rbxassetid://108350352824661",
	"rbxassetid://84208126701369",
	"rbxassetid://76793775973605",
	"rbxassetid://100247939551492",
}
local METAL_STEP_IDS = METAL_LAND_IDS

-- wind: the woosh is the sustained high-speed air sound; the gust is the shorter layer
local WIND_WOOSH_ID = "rbxassetid://107589999390784"
local WIND_GUST_ID = "rbxassetid://132957197233320"
local WINDGUST_FADE = 1.0
local WIND_WOOSH_FADE = 0.35

local LOW_LANDING_MIN_SPEED = 12
local FOOTSTEP_MIN_SPEED = 2
local FOOTSTEP_MAX_INTERVAL = 0.42
local FOOTSTEP_MIN_INTERVAL = 0.22
local JUMP_LAUNCH_UP = 60
local SPEED_RAMP_SPEED = 45
local ZONE_RADIUS = 4

-- mixing
local DIALOGUE_DUCK = 0.35
local GUNFIRE_DUCK = 0.8
local GUNFIRE_RADIUS = 45
local HURT_MUFFLE_DB = -22
local HURT_PITCH = 0.94
local PORTAL_WHOOSH_DB = -28
local PORTAL_WHOOSH_TIME = 0.6
local TAPE_STOP_TIME = 1.2
local BEAT_SYNC_MAX_WAIT = 0.8

-- menu integration (PortalMenu sets the player attribute MenuMode)
local MENU_VOLUME = 0.6
local MENU_OTHERS_FADE = 0.8          -- how fast in-game music fades when the main menu / loading screen opens
local PAUSE_MUFFLE_DB = -18
local PAUSE_DUCK = 0.45

--[[ layers
	slot      base / accent / solo / menu
	priority  inside its slot, higher wins
	delay     situation must last this long first      hold  lingers after it ends
	untilLand ends when you touch the ground            once  single play, no loop
	fadeIn / fadeOut seconds                            cooldown rest after it's done ]]
local LAYERS = {
	-- accents (stack on the base)
	TrustFling = { slot = "accent", folder = "Trust Fling", priority = 3, delay = 0,   hold = 0, untilLand = true, fadeIn = 0.4, fadeOut = 1.5, cooldown = 0 },
	JumpIntro  = { slot = "accent", folder = "JumpIntro",   priority = 2, delay = 0,   hold = 0, untilLand = true, fadeIn = 0.8, fadeOut = 2,   cooldown = 25 },
	SpeedRamp  = { slot = "accent", folder = "SpeedRamp",   priority = 1, delay = 1.5, hold = 2, fadeIn = 1.5, fadeOut = 2.5, cooldown = 40 },
	-- bases (sustained)
	Turret     = { slot = "base",   folder = "Turret",      priority = 4, delay = 2,   hold = 6, fadeIn = 2.5, fadeOut = 3,   cooldown = 45 },
	Bridge     = { slot = "base",   folder = "Bridge",      priority = 3, delay = 0.5, hold = 3, fadeIn = 2.5, fadeOut = 3,   cooldown = 15 },
	Portal     = { slot = "base",   folder = "Portal",      priority = 1, delay = 3,   hold = 8, fadeIn = 3,   fadeOut = 4,   cooldown = 20 },
	-- solos (take over)
	Combat     = { slot = "solo",   combat = true,          priority = 2, delay = 0,   hold = 0, fadeIn = 1.5, fadeOut = 3,   cooldown = 0 },
	Pickup     = { slot = "solo",   folder = "Portal",      priority = 1, delay = 0,   hold = 0, fadeIn = 1,   fadeOut = 3,   cooldown = 0, once = true },
	-- main menu (driven by MenuMode, never by gameplay conditions)
	Menu       = { slot = "menu",   menu = true,            priority = 1, delay = 0,   hold = 0, fadeIn = 2.5, fadeOut = 1.5, cooldown = 0 },
}
local ZONE_DEFAULT = { slot = "base", priority = 2, delay = 0.5, hold = 3, fadeIn = 2.5, fadeOut = 3, cooldown = 20 }

local DEBUG = false
local DEBUG_HUD = false
------------------------------------------------------------------------

local assets = ReplicatedStorage:WaitForChild("PortalAssets")
local ost = assets:WaitForChild("OST")
local p1Folder = ost:WaitForChild("Portal 1", 10)
local segFolder = ost:WaitForChild("Short Segments", 10)
local voiceFolder = assets:FindFirstChild("GLaDOSVL")
local portalsFolder = workspace:FindFirstChild("Portals")

local function log(...) if DEBUG then print("[Music]", ...) end end
local function squash(s) return string.lower((string.gsub(s, "[%s_]", ""))) end
local function approach(cur, target, up, down, dt)
	if target > cur then return math.min(cur + up * dt, target) end
	return math.max(cur - down * dt, target)
end

-------------------------------------------------------------- track lists
local bgTracks = { Calm = {}, Neutral = {}, Tense = {} }
local combatTracks = {}
if p1Folder then
	for _, s in ipairs(p1Folder:GetDescendants()) do
		if s:IsA("Sound") then
			local n = string.lower(s.Name)
			if string.find(n, "taste of blood", 1, true) then
				table.insert(combatTracks, s)
			elseif string.find(n, "self esteem", 1, true) then
				table.insert(bgTracks.Calm, s)
			elseif string.find(n, "4000", 1, true) or string.find(n, "kelvin", 1, true)
				or string.find(n, "jiggle", 1, true) or n == "pj" then
				table.insert(bgTracks.Tense, s)
			else
				table.insert(bgTracks.Neutral, s)
			end
		end
	end
end
for _, m in ipairs({ "Calm", "Neutral", "Tense" }) do
	if #bgTracks[m] == 0 then
		bgTracks[m] = (#bgTracks.Neutral > 0 and bgTracks.Neutral) or (#bgTracks.Calm > 0 and bgTracks.Calm) or bgTracks.Tense
	end
end

-- main menu music: ReplicatedStorage > PortalAssets > OST > "Main Menu" (a Folder of Sounds or one Sound).
-- Looked up again whenever the list is empty and whenever something new lands in OST: the menu is the very first
-- thing you hear, so this script usually starts before the OST has finished replicating to the client.
local menuTracks = {}
local function refreshMenuTracks()
	table.clear(menuTracks)
	local menuFolder = ost:FindFirstChild("Main Menu")
	if not menuFolder then
		for _, c in ipairs(ost:GetChildren()) do
			if squash(c.Name) == "mainmenu" then menuFolder = c break end
		end
	end
	if not menuFolder then return end
	if menuFolder:IsA("Sound") then
		table.insert(menuTracks, menuFolder)
	else
		for _, s in ipairs(menuFolder:GetDescendants()) do
			if s:IsA("Sound") then table.insert(menuTracks, s) end
		end
	end
	log("menu tracks", #menuTracks)
end
refreshMenuTracks()
ost.DescendantAdded:Connect(function(d)
	if d:IsA("Sound") or squash(d.Name) == "mainmenu" then task.defer(refreshMenuTracks) end
end)

local segCache = {}
local function segments(folderName)
	local key = squash(folderName)
	if segCache[key] and #segCache[key] > 0 then return segCache[key] end
	local list = {}
	if segFolder then
		for _, f in ipairs(segFolder:GetChildren()) do
			if squash(f.Name) == key then
				for _, s in ipairs(f:GetChildren()) do
					if s:IsA("Sound") then table.insert(list, s) end
				end
			end
		end
	end
	segCache[key] = list
	return list
end

------------------------------------------------------------- mix bus
local musicGroup = SoundService:FindFirstChild("Music")
if not musicGroup then
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "Music"
	musicGroup.Parent = SoundService
end
local eq = musicGroup:FindFirstChild("MusicEQ") or Instance.new("EqualizerSoundEffect")
eq.Name = "MusicEQ"
eq.Priority = 1
eq.Parent = musicGroup

local function makeSound(original, looped)
	local s = original:Clone()
	s.Looped = looped
	s.Volume = 0
	s.SoundGroup = musicGroup -- set before parenting, so PortalMenu's sound routing leaves it alone
	s.Parent = SoundService
	s:SetAttribute("BaseSpeed", original.PlaybackSpeed)
	return s
end

local function pickDifferent(list, last)
	if #list == 0 then return nil end
	if #list == 1 then return list[1] end
	local p
	repeat p = list[math.random(#list)] until p ~= last
	return p
end

------------------------------------------------------------------ slots
-- each slot: one song at a time
local slots = {}
for _, n in ipairs({ "background", "base", "accent", "solo", "menu" }) do
	slots[n] = { name = n, sound = nil, level = 0, owner = nil, last = nil, startAt = nil }
end

-- seconds until the next beat of the loudest slot song that has a BPM attribute
local function beatDelay()
	local best, vol = nil, 0
	for _, S in pairs(slots) do
		local s = S.sound
		if s and s.IsPlaying and s:GetAttribute("BPM") and S.level > vol then best, vol = s, S.level end
	end
	if not best then return 0 end
	local sp = math.max(best.PlaybackSpeed, 0.1)
	local beat = 60 / best:GetAttribute("BPM") / sp
	local w = beat - ((best.TimePosition / sp) % beat)
	return w <= BEAT_SYNC_MAX_WAIT and w or 0
end

local function stopSlot(S)
	if S.sound then
		S.sound:Stop()
		S.sound:Destroy()
	end
	S.sound, S.level, S.owner, S.startAt = nil, 0, nil, nil
end

----------------------------------------------------------- dialogue duck
local voiceIds = {}
if voiceFolder then
	for _, s in ipairs(voiceFolder:GetDescendants()) do
		if s:IsA("Sound") then voiceIds[s.SoundId] = true end
	end
end
local voices = {}
local function considerVoice(s)
	if s:IsA("Sound") and s.SoundGroup ~= musicGroup and (s:GetAttribute("Dialogue") or voiceIds[s.SoundId]) then
		voices[s] = true
	end
end
for _, root in ipairs({ workspace, SoundService }) do
	for _, d in ipairs(root:GetDescendants()) do considerVoice(d) end
	root.DescendantAdded:Connect(function(d) task.defer(considerVoice, d) end)
end
local function voicePlaying()
	for s in pairs(voices) do
		if not s.Parent then voices[s] = nil
		elseif s.IsPlaying and s.Volume > 0.01 then return true end
	end
	return false
end

------------------------------------------------------------------ layers
local layers = {}
local function layer(name)
	local L = layers[name]
	if not L then
		local def = LAYERS[name]
		if not def then def = table.clone(ZONE_DEFAULT); def.folder = name end
		L = { name = name, def = def, since = nil, lastCond = -math.huge, playing = false, restUntil = -math.huge, used = false }
		layers[name] = L
	end
	return L
end
for name in pairs(LAYERS) do layer(name) end
local function sourceList(L)
	if L.def.menu then
		if #menuTracks == 0 then refreshMenuTracks() end
		return menuTracks
	end
	if L.def.combat then return combatTracks end
	return segments(L.def.folder)
end

local cond = {}
local function signal(name) cond[name] = true end

------------------------------------------------------------ world state
local turrets = {}
local function considerTurret(inst)
	if inst:IsA("Model") and inst:GetAttribute("State") ~= nil then turrets[inst] = true end
end
for _, d in ipairs(workspace:GetDescendants()) do considerTurret(d) end
workspace.DescendantAdded:Connect(function(d) task.defer(considerTurret, d) end)

local threat, strain, flow = 0, 0, 0
local lastDamage = -math.huge
local gunPickedUp = false
local whooshT = -math.huge

player:GetAttributeChangedSignal("HasPortalGun"):Connect(function()
	if player:GetAttribute("HasPortalGun") then gunPickedUp = true end
end)
player:GetAttributeChangedSignal("PortalTraversals"):Connect(function()
	flow = math.min(flow + FLOW_PER_TRAVERSAL, 1)
	whooshT = os.clock()
end)
local function hookCamera(c)
	if c then c:GetAttributeChangedSignal("PortalViewEpoch"):Connect(function() whooshT = os.clock() end) end
end
hookCamera(workspace.CurrentCamera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() hookCamera(workspace.CurrentCamera) end)
if portalsFolder then
	portalsFolder.ChildAdded:Connect(function(p)
		task.wait(0.1)
		if p:GetAttribute("OwnerUserId") == player.UserId then flow = math.min(flow + FLOW_PER_PORTAL, 1) end
	end)
end

----------------------------------------------------- per-character sfx
local sfx = {}
local function buildSfx(hrp)
	local folder = Instance.new("Folder")
	folder.Name = "PortalFlingAudio"
	folder.Parent = hrp
	local landing = {}
	for i, id in ipairs(LANDING_IDS) do
		local s = Instance.new("Sound")
		s.Name = "Longfall_" .. i
		s.SoundId = id
		s.Volume = 0.85
		s.RollOffMaxDistance = 160
		s.Parent = folder
		table.insert(landing, s)
	end

	local landTile = {}
	for i, id in ipairs(LAND_TILE_IDS) do
		local s = Instance.new("Sound")
		s.Name = "LandTile_" .. i
		s.SoundId = id
		s.Volume = 0.65
		s.RollOffMaxDistance = 100
		s.Parent = folder
		table.insert(landTile, s)
	end

	local metalLand = {}
	for i, id in ipairs(METAL_LAND_IDS) do
		local s = Instance.new("Sound")
		s.Name = "MetalLand_" .. i
		s.SoundId = id
		s.Volume = 0.65
		s.RollOffMaxDistance = 100
		s.Parent = folder
		table.insert(metalLand, s)
	end

	local walkTile = {}
	for i, id in ipairs(WALK_TILE_IDS) do
		local s = Instance.new("Sound")
		s.Name = "WalkTile_" .. i
		s.SoundId = id
		s.Volume = 0.45
		s.RollOffMaxDistance = 80
		s.Parent = folder
		table.insert(walkTile, s)
	end

	local metalStep = {}
	for i, id in ipairs(METAL_STEP_IDS) do
		local s = Instance.new("Sound")
		s.Name = "MetalStep_" .. i
		s.SoundId = id
		s.Volume = 0.45
		s.RollOffMaxDistance = 80
		s.Parent = folder
		table.insert(metalStep, s)
	end

	local gust = Instance.new("Sound")
	gust.Name = "WindGust"
	gust.SoundId = WIND_GUST_ID
	gust.Volume = 0
	gust.RollOffMaxDistance = 180
	gust.Parent = folder

	local woosh = Instance.new("Sound")
	woosh.Name = "WindWoosh"
	woosh.SoundId = WIND_WOOSH_ID
	woosh.Volume = 0
	woosh.Looped = true
	woosh.RollOffMaxDistance = 180
	woosh.Parent = folder

	return {
		landing = landing,
		landTile = landTile,
		metalLand = metalLand,
		walkTile = walkTile,
		metalStep = metalStep,
		gust = gust,
		woosh = woosh,
		gustLevel = 0,
		wooshLevel = 0,
	}
end

local function onCharacter(char)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hrp or not hum or player.Character ~= char then return end
	sfx = buildSfx(hrp)
	local lastHealth = hum.Health
	hum.HealthChanged:Connect(function(h)
		if player.Character == char and h < lastHealth - 0.5 then lastDamage = os.clock() end
		lastHealth = h
	end)
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end

------------------------------------------------------------------ HUD
local hud
if DEBUG_HUD then
	local g = Instance.new("ScreenGui")
	g.Name = "MusicDebug"
	g.ResetOnSpawn = false
	g.Parent = player:WaitForChild("PlayerGui")
	hud = Instance.new("TextLabel")
	hud.Size = UDim2.fromOffset(360, 230)
	hud.Position = UDim2.fromOffset(10, 120)
	hud.BackgroundTransparency = 0.4
	hud.BackgroundColor3 = Color3.new(0, 0, 0)
	hud.TextColor3 = Color3.new(1, 1, 1)
	hud.Font = Enum.Font.Code
	hud.TextSize = 14
	hud.TextXAlignment = Enum.TextXAlignment.Left
	hud.TextYAlignment = Enum.TextYAlignment.Top
	hud.Parent = g
end
local function bar(x)
	local n = math.floor(x * 20 + 0.5)
	return string.rep("#", n) .. string.rep(".", 20 - n)
end

---------------------------------------------------------------- main loop
local wasAlive, deathT = false, nil
local wasAirborne, peakAirSpeed, flingAlpha = false, 0, 0
local inCombat, inTurret, inFlow = false, false, false
local zoneAcc, zoneHits = 0, {}
local footstepT = 0
local lastWalkSound = nil
local lastLandSound = nil
local zoneParams = OverlapParams.new()
zoneParams.FilterType = Enum.RaycastFilterType.Exclude
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local duck = 1
local pauseAmt = 0
local lastMenuMode = nil
local nextBackgroundAt = os.clock() + FIRST_BACKGROUND_DELAY
local lastActivity = -math.huge

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	table.clear(cond)

	-- menu state from PortalMenu
	local menuMode = player:GetAttribute("MenuMode")
	local inMainMenu = menuMode == "main"
	local inLoading = menuMode == "loading"
	if menuMode ~= lastMenuMode then
		-- coming out of the menus: give the game a moment before Portal 1 background comes back
		if lastMenuMode == "main" or lastMenuMode == "loading" then
			nextBackgroundAt = now + FIRST_BACKGROUND_DELAY
			lastActivity = now
		end
		lastMenuMode = menuMode
	end
	pauseAmt = approach(pauseAmt, menuMode == "pause" and 1 or 0, 4, 2, dt)

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local alive = hum ~= nil and hrp ~= nil and hum.Health > 0

	if alive and not wasAlive then
		deathT = nil
		threat, flow = 0, 0
		nextBackgroundAt = now + math.random(RESPAWN_SILENCE[1], RESPAWN_SILENCE[2])
		for n, S in pairs(slots) do
			if n ~= "menu" then stopSlot(S) end
		end
	elseif not alive and wasAlive then
		deathT = now
	end
	wasAlive = alive

	-------------------------------------------------- feelings + conditions
	local airborne, gunfireNear, threatTarget = false, false, 0
	-- main menu / loading screen: nothing but the menu track. No footsteps, landings, wind or gameplay layers.
	local silenced = inMainMenu or inLoading
	if alive and not silenced then
		local v = hrp.AssemblyLinearVelocity
		local speed = v.Magnitude
		local hSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
		local st = hum:GetState()
		airborne = st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.FallingDown
			or st == Enum.HumanoidStateType.Jumping or hum.FloorMaterial == Enum.Material.Air

		losParams.FilterDescendantsInstances = { char }
		for t in pairs(turrets) do
			if not t.Parent then
				turrets[t] = nil
			else
				local s = t:GetAttribute("State")
				local ok, pivot = pcall(function() return t:GetPivot() end)
				if ok and s ~= "DEAD" then
					local d = (pivot.Position - hrp.Position).Magnitude
					if d < TURRET_HEAR_RADIUS then
						local near = 1 - d / TURRET_HEAR_RADIUS
						if t:GetAttribute("TargetUserId") == player.UserId then
							threatTarget = math.max(threatTarget, 0.75)
							if d < GUNFIRE_RADIUS then gunfireNear = true end
						elseif s == "ATTACK" or s == "TIPPED" then
							threatTarget = math.max(threatTarget, 0.4 + 0.3 * near)
							if d < GUNFIRE_RADIUS then gunfireNear = true end
						elseif s == "SEARCH" or s == "DEPLOY" then
							threatTarget = math.max(threatTarget, 0.35 + 0.25 * near)
						else
							local hit = workspace:Raycast(pivot.Position + Vector3.new(0, 1, 0), hrp.Position - pivot.Position, losParams)
							if not hit or hit.Instance:IsDescendantOf(t) then
								threatTarget = math.max(threatTarget, 0.15 + 0.3 * near)
							end
						end
					end
				end
			end
		end
		-- actually getting hurt is what pushes it into Combat
		if now - lastDamage < DAMAGE_THREAT_TIME then
			threatTarget = math.max(threatTarget, 1 - 0.6 * (now - lastDamage) / DAMAGE_THREAT_TIME)
		end
		threat = approach(threat, threatTarget, THREAT_RISE, THREAT_FALL, dt)
		strain = approach(strain, 1 - hum.Health / math.max(hum.MaxHealth, 1), 2, 0.3, dt)
		flow = math.max(flow - FLOW_FALL * dt, 0)

		-- velocity accents
		if airborne then peakAirSpeed = math.max(peakAirSpeed, speed) end
		if airborne and (speed >= FLING_MIN_SPEED or layer("TrustFling").playing) then
			signal("TrustFling")
			local a = math.clamp((speed - FLING_MIN_SPEED) / (FLING_MAX_SPEED - FLING_MIN_SPEED), 0, 1)
			flingAlpha = a * a * (3 - 2 * a)
		end
		if airborne and (v.Y > JUMP_LAUNCH_UP or layer("JumpIntro").playing) then signal("JumpIntro") end
		if not airborne and hSpeed >= SPEED_RAMP_SPEED then signal("SpeedRamp") end

		if wasAirborne and not airborne then
			-- Heavy fall: use the existing high-velocity landing sounds.
			-- Normal fall/jump: use the regular tile/metal landing sounds instead.
			local material = hum.FloorMaterial
			local isMetal = material == Enum.Material.Metal
			local list

			if peakAirSpeed >= LANDING_MIN_SPEED then
				list = sfx.landing
			elseif peakAirSpeed >= LOW_LANDING_MIN_SPEED then
				list = isMetal and sfx.metalLand or sfx.landTile
			end

			if list and #list > 0 then
				local choices = {}
				for _, sound in ipairs(list) do
					if sound ~= lastLandSound then table.insert(choices, sound) end
				end
				local s = choices[math.random(#choices)]
				lastLandSound = s
				s.TimePosition = 0

				if peakAirSpeed >= LANDING_MIN_SPEED then
					s.Volume = math.clamp(0.55 + (peakAirSpeed - LANDING_MIN_SPEED) / 180, 0.55, 1)
					s.PlaybackSpeed = math.clamp(0.9 + (peakAirSpeed - LANDING_MIN_SPEED) / 400, 0.85, 1.15)
				else
					s.Volume = math.clamp(0.42 + peakAirSpeed / 180, 0.42, 0.7)
					s.PlaybackSpeed = math.clamp(0.92 + peakAirSpeed / 500, 0.9, 1.08)
				end
				s:Play()
			end
			peakAirSpeed = 0
		end

		-- Footsteps: only while actually moving on the ground.
		if not airborne and hum.MoveDirection.Magnitude > 0.1 and hSpeed >= FOOTSTEP_MIN_SPEED then
			local interval = math.clamp(0.48 - hSpeed / 160, FOOTSTEP_MIN_INTERVAL, FOOTSTEP_MAX_INTERVAL)
			footstepT -= dt
			if footstepT <= 0 then
				local list = hum.FloorMaterial == Enum.Material.Metal and sfx.metalStep or sfx.walkTile
				if list and #list > 0 then
					local choices = {}
					for _, sound in ipairs(list) do
						if sound ~= lastWalkSound then table.insert(choices, sound) end
					end
					local s = choices[math.random(#choices)]
					lastWalkSound = s
					s.TimePosition = 0
					s.Volume = math.clamp(0.32 + hSpeed / 120, 0.32, 0.55)
					s.PlaybackSpeed = math.clamp(0.9 + hSpeed / 180, 0.9, 1.15)
					s:Play()
				end
				footstepT = interval
			end
		else
			footstepT = 0
		end

		wasAirborne = airborne

		-- zones
		zoneAcc += dt
		if zoneAcc >= 0.2 then
			zoneAcc = 0
			table.clear(zoneHits)
			zoneParams.FilterDescendantsInstances = { char }
			for _, part in ipairs(workspace:GetPartBoundsInRadius(hrp.Position, ZONE_RADIUS, zoneParams)) do
				local cue = part:GetAttribute("MusicCue")
				if type(cue) == "string" and cue ~= "" then zoneHits[cue] = true
				elseif part:GetAttribute("LightBridge") then zoneHits.Bridge = true end
			end
		end
		for name in pairs(zoneHits) do signal(name) end

		-- feeling-driven layers (hysteresis)
		if inCombat then inCombat = threat > COMBAT_OFF else inCombat = threat >= COMBAT_ON end
		if inTurret then inTurret = threat > TURRET_OFF else inTurret = threat >= TURRET_ON end
		if inFlow then inFlow = flow > FLOW_OFF else inFlow = flow >= FLOW_ON end
		if inCombat then signal("Combat") end
		if inTurret then signal("Turret") end
		if inFlow then signal("Portal") end
		if gunPickedUp then gunPickedUp = false; signal("Pickup") end
	end

	-------------------------------------------------- wind sounds
	if sfx.gust and sfx.woosh then
		local on = alive and not silenced and cond.TrustFling

		-- Shorter gust layer.
		if on and not sfx.gust.IsPlaying then sfx.gust.TimePosition = 0; sfx.gust:Play() end
		sfx.gustLevel = on and (0.35 + 0.3 * flingAlpha) or math.max(sfx.gustLevel - dt / WINDGUST_FADE, 0)
		sfx.gust.Volume = sfx.gustLevel
		if not on and sfx.gustLevel <= 0.001 and sfx.gust.IsPlaying then sfx.gust:Stop() end

		-- Sustained wind woosh follows fling speed and is kept quieter.
		if on and not sfx.woosh.IsPlaying then sfx.woosh.TimePosition = 0; sfx.woosh:Play() end
		sfx.wooshLevel = on and (0.08 + 0.22 * flingAlpha) or math.max(sfx.wooshLevel - dt / WIND_WOOSH_FADE, 0)
		sfx.woosh.Volume = sfx.wooshLevel
		if not on and sfx.wooshLevel <= 0.001 and sfx.woosh.IsPlaying then sfx.woosh:Stop() end
	end

	-------------------------------------------------- layer on/off
	for name in pairs(cond) do layer(name) end
	for name, L in pairs(layers) do
		local def = L.def
		if alive and cond[name] then
			L.since = L.since or now
			L.lastCond = now
		else
			L.since = nil
		end
		if not L.playing then
			if L.since and now - L.since >= def.delay and now >= L.restUntil and #sourceList(L) > 0 then
				L.playing, L.used = true, false
				log("on", name)
			end
		else
			local S = slots[def.slot]
			local over
			if not alive then
				over = true
			elseif def.untilLand then
				over = not airborne
			elseif def.once then
				over = L.used and (S.owner ~= name or not S.sound or not S.sound.IsPlaying)
			else
				over = now - L.lastCond > def.hold
			end
			if over then
				L.playing = false
				L.restUntil = now + def.cooldown
				log("off", name)
			end
		end
	end

	-- who owns each slot
	local want = {}
	for name, L in pairs(layers) do
		if L.playing then
			local cur = want[L.def.slot]
			if not cur or L.def.priority > layers[cur].def.priority then want[L.def.slot] = name end
		end
	end
	local solo, base, accent = want.solo, want.base, want.accent
	if base or accent or solo then lastActivity = now end

	-------------------------------------------------- mix values
	duck = approach(duck, (voicePlaying() and DIALOGUE_DUCK or 1) * (gunfireNear and GUNFIRE_DUCK or 1), 4, 1, dt)
	local tape = 1
	if deathT then
		local a = math.clamp((now - deathT) / TAPE_STOP_TIME, 0, 1)
		tape = 1 - a * a
	end
	if inMainMenu then tape = 1 end
	local hurt = math.clamp((strain - 0.5) / 0.5, 0, 1)
	local whoosh = math.clamp(1 - (now - whooshT) / PORTAL_WHOOSH_TIME, 0, 1)
	eq.HighGain = HURT_MUFFLE_DB * hurt + PORTAL_WHOOSH_DB * whoosh * whoosh + PAUSE_MUFFLE_DB * pauseAmt
	eq.MidGain = -6 * hurt
	eq.LowGain = 2 * hurt
	local pitchMul = (1 - (1 - HURT_PITCH) * hurt) * (0.3 + 0.7 * tape)
	local userVol = player:GetAttribute("MusicVolume")
	local masterVol = player:GetAttribute("Setting_master")
	musicGroup.Volume = (type(userVol) == "number" and math.clamp(userVol, 0, 1) or 1)
		* (type(masterVol) == "number" and math.clamp(masterVol, 0, 1) or 1)
		* duck * tape * (1 - PAUSE_DUCK * pauseAmt)

	-------------------------------------------------- slot targets
	-- desired owner + volume for each slot
	local target = { background = nil, base = nil, accent = nil, solo = nil, menu = nil }
	local vol = { background = 0, base = 0, accent = 0, solo = 0, menu = 0 }
	if inMainMenu then
		target.menu = "Menu"
		vol.menu = MENU_VOLUME
	elseif inLoading then
		-- silence: nothing wants any slot, so everything fades out
	elseif alive then
		if solo then
			target.solo = solo
			vol.solo = layers[solo].def.combat and VOLUME.Combat or VOLUME.Pickup
		else
			if accent then
				target.accent = accent
				vol.accent = accent == "TrustFling"
					and math.max(FLING_MIN_VOLUME + (FLING_MAX_VOLUME - FLING_MIN_VOLUME) * flingAlpha, FLING_AIR_FLOOR)
					or VOLUME.Accent
			end
			if base and not (accent and NO_STACK[accent] and NO_STACK[accent][base]) then
				target.base = base
				vol.base = VOLUME.Base * (accent and BASE_UNDER_ACCENT or 1)
			end
			-- Portal 1 only when nothing else is going on
			if not base and not accent and now - lastActivity >= IDLE_BEFORE_BACKGROUND then
				target.background = "Background"
				vol.background = VOLUME.Background
			end
		end
	end

	-------------------------------------------------- run the slots
	for slotName, S in pairs(slots) do
		local owner = target[slotName]
		local def = owner and layers[owner] and layers[owner].def
		local fadeIn = def and def.fadeIn or BACKGROUND_FADE_IN
		local curDef = S.owner and layers[S.owner] and layers[S.owner].def
		local fadeOut = alive and (curDef and curDef.fadeOut or BACKGROUND_FADE_OUT) or 0.3
		if (inMainMenu or inLoading) and slotName ~= "menu" and S.owner ~= nil then fadeOut = MENU_OTHERS_FADE end

		-- something else wants this slot: fade the current song out first
		if S.sound and S.owner ~= owner then
			S.level = math.max(S.level - math.max(S.level, 0.05) / fadeOut * dt, 0)
			S.sound.Volume = S.level
			if S.level <= 0.001 then stopSlot(S) end
		elseif owner and not S.sound then
			-- slot is free: start the new song (beat-synced unless it's a velocity accent)
			local blocked = false
			if slotName == "base" then
				-- don't put Portal 2 music on top of a Portal 1 track still fading out
				blocked = slots.background.sound ~= nil
			elseif slotName == "solo" then
				-- solos come in alone: wait until everything else has faded
				blocked = slots.background.sound ~= nil or slots.base.sound ~= nil or slots.accent.sound ~= nil
			elseif slotName == "background" then
				blocked = now < nextBackgroundAt
			end
			if not blocked then
				S.startAt = S.startAt or (now + ((def and def.untilLand) and 0 or beatDelay()))
				if now >= S.startAt then
					local list, once
					if slotName == "background" then
						local danger = math.max(threat, strain)
						local mood = danger >= TENSE_AT and "Tense" or (flow >= NEUTRAL_AT and "Neutral" or "Calm")
						list = bgTracks[mood]
						log("background", mood)
					else
						list = sourceList(layers[owner])
						once = def.once
					end
					local original = pickDifferent(list, S.last)
					if original then
						S.last = original
						-- background tracks and once-layers play through; others loop for the moment
						S.sound = makeSound(original, slotName ~= "background" and not once)
						S.owner = owner
						S.level = 0
						S.startAt = nil
						S.sound:Play()
						if owner and layers[owner] then layers[owner].used = true end
						log(slotName, owner, original.Name)
						if slotName == "background" then
							local snd = S.sound
							snd.Ended:Once(function()
								if S.sound == snd then
									stopSlot(S)
									nextBackgroundAt = os.clock() + math.random(SILENCE_MIN, SILENCE_MAX)
								end
							end)
						end
					end
				end
			end
		elseif S.sound then
			-- owner keeps the slot: move toward its volume
			local goal = vol[slotName]
			local full = math.max(goal, S.level, 0.05)
			S.level += math.clamp(goal - S.level, -full / fadeOut * dt, full / fadeIn * dt)
			S.sound.Volume = S.level
		end

		if S.sound then
			local baseSpeed = S.sound:GetAttribute("BaseSpeed") or 1
			local m = (S.owner == "TrustFling") and (FLING_MIN_PITCH + (FLING_MAX_PITCH - FLING_MIN_PITCH) * flingAlpha) or 1
			S.sound.PlaybackSpeed = baseSpeed * m * pitchMul
		end
		if not owner and not S.sound then S.startAt = nil end
	end

	-- background was interrupted: wait a quiet spell before it can come back
	if target.background == nil and slots.background.sound == nil and nextBackgroundAt < now then
		nextBackgroundAt = now + math.random(SILENCE_MIN, SILENCE_MAX) * 0.5
	end

	-------------------------------------------------- HUD
	if hud then
		local lines = {
			("THREAT %s %.2f"):format(bar(threat), threat),
			("STRAIN %s %.2f"):format(bar(strain), strain),
			("FLOW   %s %.2f"):format(bar(flow), flow),
		}
		for _, n in ipairs({ "menu", "background", "base", "accent", "solo" }) do
			local S = slots[n]
			table.insert(lines, tostring(("%-10s %-11s %s %.2f"):format(n, tostring(S.owner or "-"),
				S.sound and S.sound.Name or "", S.level)))
		end
		table.insert(lines, tostring(("duck %.2f hurt %.2f tape %.2f pause %.2f  bg in %ds"):format(duck, hurt, tape, pauseAmt,
			math.max(0, math.floor(nextBackgroundAt - now)))))
		table.insert(lines, "menu mode: " .. tostring(menuMode) .. "   menu tracks: " .. #menuTracks)
		hud.Text = table.concat(lines, "\n")
	end
end)
