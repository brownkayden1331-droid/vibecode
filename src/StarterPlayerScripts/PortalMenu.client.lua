-- PortalMenu
-- StarterPlayerScripts (LocalScript)
-- Portal 2 boot loading screen, main menu, pause menu, option dialogs, chapters (acts), save / load,
-- co-op (invite a friend / quick match), Aperture community + Workshop screens, challenge leaderboards,
-- achievements list, editor settings, team building invites, and the hooks for Robot Enrichment + the test chamber editor.
-- Needs: ReplicatedStorage.PortalConfig (ModuleScript) and ServerScriptService.PortalServer (Script).
--
-- Other scripts can listen for menu buttons:
--   player.PlayerGui:WaitForChild("PortalMenu"):WaitForChild("MenuAction").Event:Connect(function(action, arg) ... end)
-- and ask the menu for things through ...:WaitForChild("MenuRequest"):Fire(kind, arg)
--   kinds: "CloseEnrichment", "EnrichmentScreen" (arg = screen name), "Sound" (arg = CFG key, e.g. "SOUND_HOVER"),
--          "TileSound" (one throttled rollover tick for your own tile flips), "ExitToMain"
--   (functions can't be sent through a BindableEvent, so never pass a callback)
--
-- Player attributes this script sets:
--   InMenu, InEnrichment, MenuMode ("main" | "pause" | "loading" | "none"), Setting_<key>, MusicVolume, FieldOfView
--   (the editor reads its settings from Setting_ed*)
--
-- Controls: mouse, keyboard, gamepad and touch.
--   Gamepad: D-pad / left stick move, A select, B back, Start pause, and X / Y / LB / RB press the footer buttons
--   (their glyphs show on the buttons while you're using a controller).
--   Touch: tap to pick, drag lists to scroll, the round II button pauses.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local GuiService = game:GetService("GuiService")

local getRobloxSettings = settings -- the local `settings` table below shadows the global function

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(ReplicatedStorage:WaitForChild("PortalConfig"))
if Config.VERSION ~= 3 then
	warn("[PortalMenu] ReplicatedStorage.PortalConfig is out of date (version " .. tostring(Config.VERSION) .. ", need 3). Replace it with the new PortalConfig - things will break until you do.")
end

-- ==========================================
-- SETTINGS + LOOK
-- ==========================================

local CFG = {
	SHOW_MAIN_MENU_ON_JOIN = true,
	PAUSE_KEYS = { [Enum.KeyCode.Backquote] = true, [Enum.KeyCode.ButtonStart] = true },

	LOGO_IMAGE = "rbxassetid://104610735087742",
	LOADING_LOGO = "rbxassetid://75074251728778",
	MENU_BACKGROUND_IMAGE = "rbxassetid://117187717558489", -- default; a chapter can override it with `background` in PortalConfig.CHAPTERS
	MENU_CAMERA_PART = "MenuCamera",
	LOADING_BACKGROUNDS = {},
	LOADING_TIME = 2.5,       -- minimum time a loading screen stays up
	BOOT_LOADING_TIME = 3,    -- the loading screen you get when you join, before the main menu
	CROSSHAIR_GUI = "Overlay",
	LOCK_FIRST_PERSON = true, -- lock the camera to first person while you're playing a chapter / challenge / workshop chamber / editor playtest

	SOUND_BARCHANGE = "rbxassetid://84142589851859",
	SOUND_HOVER = "rbxassetid://121974475057097",
	SOUND_INVALID = "rbxassetid://136396251761745",
	SOUND_ROLLOVER = { "rbxassetid://101229474950511", "rbxassetid://90291640659329" }, -- tile flips only
	SOUND_CLICK = "rbxassetid://75225441420673",
	SOUND_BACK = "rbxassetid://77267928169568",
	TILE_SOUND_GAP = 0.018,   -- min seconds between two tile flip ticks (stops the cascade turning into noise)
	TILE_SOUND_VOLUME = 0.32,

	APERTURE_LOGO_IMAGE = "rbxassetid://52186422",
	DECOR_TURRET_IMAGE = "rbxassetid://78815995687185", -- only used if the Turret model can't be found for the viewport
	DECOR_BUTTON_ASSET = "Button",   -- model names (PortalAssets) shown in the Aperture screens' viewports
	DECOR_TURRET_ASSET = "Turret",
	EMPLOYEE_TITLE = "Test Chamber Designer",

	EXTRAS = {
		{ "Perpetual Testing Initiative", "ExtrasPTI", "" },
		{ "Meet the Bots", "ExtrasMeetTheBots", "" },
		{ "Glados Wakes", "ExtrasGladosWakes", "" },
		{ "Bot Trust", "ExtrasBotTrust", "" },
		{ "Panels", "ExtrasPanels", "" },
		{ "Turrets", "ExtrasTurrets", "" },
		{ "Credits", "ExtrasCredits", "" },
	},

	-- Workshop list sources (label, sort sent to the server)
	SOURCES = {
		{ "My Queue", "Queue" },
		{ "Top Rated", "TopRated" },
		{ "Most Recent", "MostRecent" },
		{ "Most Popular", "MostPopular" },
		{ "Friends' Creations", "FriendsCreations" },
		{ "Friends' Top Rated", "FriendsTopRated" },
		{ "Followed's Most Recent", "FollowedMostRecent" },
	},

	TEXT = {
		EXIT = "Any progress since your last save will be lost. Are you sure you want to exit to the main menu?",
		COMMENTARY = "Commentary nodes play notes from the people who built this game. Aim at a speech bubble and press USE to start or stop one. You can't save in commentary mode.",
		PLAY_ONLINE = "Co-op is best with a friend. Are you sure you want to be matched with a random partner?",
		QUIT = "Are you sure you want to quit the game?",
		OVERWRITE = "Are you sure you want to overwrite this saved game?",
		DELETE = "Are you sure you want to delete this saved game?",
	},

	FONT_FAMILY = "rbxasset://fonts/families/RobotoCondensed.json",

	GRID = 112, ROW = 54, PAD_TOP = 56, PAD_BOTTOM = 4, PANEL_X = 225, PANEL_BOTTOM = 910,
	FOOT_GAP = 28, FOOT_H = 33, MAIN_X = 198, MAIN_Y = 445, MAIN_STEP = 67, BLOCK = 56, SLIDER_W = 293,
}

local function font(weight) return Font.new(CFG.FONT_FAMILY, weight) end
local F_MAIN = font(Enum.FontWeight.Medium)
local F_ROW = font(Enum.FontWeight.Bold)
local F_SET = font(Enum.FontWeight.Medium)
local F_TITLE = font(Enum.FontWeight.Bold)

local function rgb(r, g, b) return Color3.fromRGB(r, g or r, b or r) end

local COL = {
	MAIN_TEXT = rgb(172), MAIN_HI_TEXT = rgb(255), MAIN_HI_BG = rgb(125),
	PANEL = rgb(217), PANEL_TAB = rgb(217), GRID = rgb(204),
	ROW_TEXT = rgb(22), ROW_HI = rgb(60), DISABLED = rgb(158),
	CYAN = Color3.fromRGB(38, 178, 214), DOT_OFF = rgb(150),
	DARK = rgb(91, 94, 96), DARK_TAB = rgb(81, 83, 86), DARK_GRID = rgb(110, 114, 117),
	DARK_TEXT = rgb(205), DARK_TITLE = rgb(155, 168, 165), YELLOW = rgb(173, 170, 119),
	RATING = rgb(79, 167, 170), BLUE_BTN = rgb(77, 128, 151),
	GLASS = rgb(70, 77, 75), GLASS_TEXT = rgb(240, 246, 244), GLASS_HI = rgb(253, 250, 181), GLASS_BTN = rgb(209, 216, 214),
	INFO_TEXT = rgb(128),
}

-- gamepad glyph colours (Xbox layout)
local GLYPH_COLORS = {
	A = Color3.fromRGB(96, 176, 64), B = Color3.fromRGB(206, 66, 56), X = Color3.fromRGB(56, 118, 206),
	Y = Color3.fromRGB(216, 176, 36), LB = rgb(60), RB = rgb(60),
}

-- ==========================================
-- HELPERS
-- ==========================================

local function new(class, props)
	local o = Instance.new(class)
	local parent
	for k, v in pairs(props) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	if parent then o.Parent = parent end
	return o
end

local function px(x, y) return UDim2.fromOffset(x, y) end

local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local widthCache = {}
local function textWidth(text, fnt, size)
	local key = text .. "|" .. size .. "|" .. tostring(fnt.Weight)
	if widthCache[key] then return widthCache[key] end
	local ok, b = pcall(function()
		local p = Instance.new("GetTextBoundsParams")
		p.Text, p.Font, p.Size, p.Width = text, fnt, size, 3000
		return TextService:GetTextBoundsAsync(p)
	end)
	local w = ok and b.X or #text * size * 0.5
	widthCache[key] = w
	return w
end

local function triangle(parent, dir, size, color)
	local horizontal = dir == "left" or dir == "right"
	local clip = new("Frame", {
		BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 3,
		Size = horizontal and px(size / 2, size) or px(size, size / 2), Parent = parent,
	})
	local cx, cy
	if dir == "left" then cx, cy = size / 2, size / 2
	elseif dir == "right" then cx, cy = 0, size / 2
	elseif dir == "down" then cx, cy = size / 2, 0
	else cx, cy = size / 2, size / 2 end
	local d = size / math.sqrt(2)
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = px(cx, cy), Size = px(d, d), Rotation = 45,
		BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 3, Parent = clip,
	})
	return clip
end

local function blob(parent, x, y, w, h, rot, color, round, z)
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = px(x, y), Size = px(w, h), Rotation = rot or 0,
		BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z or 3, Parent = parent,
	})
	new("UICorner", { CornerRadius = round or UDim.new(0.5, 0), Parent = f })
	return f
end

local function fmtTime(sec)
	sec = math.floor(sec or 0)
	return string.format("%d:%02d", sec // 60, sec % 60)
end

-- "Sunday, Oct 4 4:20 PM" (local time)
local function stamp(t)
	local d = os.date("*t", t)
	return os.date("%A, %b ", t) .. d.day .. " " .. ((d.hour - 1) % 12 + 1) .. os.date(":%M ", t) .. (d.hour < 12 and "AM" or "PM")
end

-- is the player on a controller right now?
local function padActive()
	return string.find(UserInputService:GetLastInputType().Name, "Gamepad", 1, true) ~= nil
end

-- ==========================================
-- NETWORK + PROFILE CACHE
-- ==========================================

local Net = {}
function Net.folder()
	return ReplicatedStorage:FindFirstChild("PortalNet") or ReplicatedStorage:WaitForChild("PortalNet", 15)
end
function Net.call(action, arg)
	local f = Net.folder()
	if not f then return false, "The PortalServer script isn't running." end
	local ok, a, b = pcall(function() return f.Request:InvokeServer(action, arg) end)
	if not ok then return false, tostring(a) end
	return a, b
end

-- profile mirror (filled from the server at boot, kept up to date by replies / pushes)
local P = {
	settings = {}, saves = {}, maxChapter = 1, achievements = {}, progress = {},
	inventory = {}, equipped = { blue = {}, orange = {} }, queue = {}, follows = {},
}
-- misc client state
local S = { enrichment = false, menuOpen = false, friendIds = nil, lb = {}, maps = {}, names = {} }

-- ==========================================
-- SOUND ROUTING
-- ==========================================

local masterGroup = SoundService:FindFirstChild("PortalMaster")
	or new("SoundGroup", { Name = "PortalMaster", Volume = 1, Parent = SoundService })
local musicGroup = masterGroup:FindFirstChild("PortalMusic")
	or new("SoundGroup", { Name = "PortalMusic", Volume = 1, Parent = masterGroup })
local sfxGroup = masterGroup:FindFirstChild("PortalSFX")
	or new("SoundGroup", { Name = "PortalSFX", Volume = 1, Parent = masterGroup })
local uiGroup = SoundService:FindFirstChild("PortalUI")
	or new("SoundGroup", { Name = "PortalUI", Volume = 1, Parent = SoundService })

local function isMusic(s)
	return s:GetAttribute("Music") == true or string.find(string.lower(s.Name), "music", 1, true) ~= nil
end
local function route(s)
	if s:IsA("Sound") and s.SoundGroup == nil then
		s.SoundGroup = isMusic(s) and musicGroup or sfxGroup
	end
end
for _, c in ipairs({ workspace, SoundService, playerGui }) do
	for _, d in ipairs(c:GetDescendants()) do route(d) end
	c.DescendantAdded:Connect(route)
end

local function uiSound(id, vol, pitch)
	if type(id) == "table" then
		if #id == 0 then return end
		id = id[math.random(#id)]
	end
	if not id or id == "" or id == "rbxassetid://" then return end
	local s = new("Sound", { SoundId = id, Volume = vol or 0.6, PlaybackSpeed = pitch or 1, SoundGroup = uiGroup, Parent = SoundService })
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(5, function() if s.Parent then s:Destroy() end end)
end

-- rollover = the tile flip tick. Every tile asks for one; the gap keeps it a crisp cascade like Portal 2.
local lastTileSound = 0
local function tileSound()
	local now = os.clock()
	if now - lastTileSound < CFG.TILE_SOUND_GAP then return end
	lastTileSound = now
	uiSound(CFG.SOUND_ROLLOVER, CFG.TILE_SOUND_VOLUME, 0.94 + math.random() * 0.12)
end

local settings, DEFAULTS, mode, loadingNow, refreshTouchPause, publishMode, setMode, setCrosshair, ASPECTS, updateAspect, updateWindow, rescale, bindDisplay, applySetting, onSettingChanged, loadSettingsFromProfile
do
-- ==========================================
-- GAME SETTINGS (player attributes "Setting_<key>", saved on the server)
-- ==========================================

settings = {
	master = 1, music = 1, sfx = 1,
	brightness = 0.5, aspect = "Native", resolution = "Native", quality = "Auto", textureQuality = "High", shadows = "Enabled",
	fov = 70, crosshair = "Enabled", motionBlur = "Disabled", blurStrength = 0.5, viewBob = "Enabled",
	display = "Full Screen",
	voice = "Enabled", cc = "None", ccSize = "Normal",
	mouseSens = 0.5, reverseMouse = "Disabled", rawMouse = "Disabled", mouseAccel = "Disabled", accelAmount = 0.75,
	bindBlue = "MouseButton1", bindOrange = "MouseButton2", bindReset = "R", bindUse = "E", bindJump = "Space", bindPause = "Backquote",
	-- test chamber editor (PortalMapEditor reads these from the Setting_<key> attributes)
	edAutoHide = "Enabled", edOrbitSens = 0.5, edInvertY = "Disabled", edZoomSpeed = 0.5, edCamSmooth = 0.5,
	edSfx = 1, edDrone = 1, edHover = "Enabled", edPadCursor = 0.5, edTouchBar = "Auto", edTeamNames = "Enabled",
	edMode = "Simple", -- Simple (Items) | Intermediate (+ Textures, Meshes) | Advanced (+ My Chips, labels, nudging)
	toasts = "Enabled", -- toast notifications (achievements, saves, chamber messages...)
	tutorial = "Enabled", -- tutorial cards when a level starts
}
DEFAULTS = table.clone(settings)

local brightnessFX = new("ColorCorrectionEffect", { Name = "PortalMenuBrightness", Parent = Lighting })
local motionBlurFX = new("BlurEffect", { Name = "PortalMotionBlur", Size = 0, Enabled = false, Parent = Lighting })

mode = "none"      -- "none" | "main" | "pause"
loadingNow = false
-- (declared above the do block) local refreshTouchPause
local syncCameraLock

local function updateMute()
	local silent = loadingNow or mode == "main"
	masterGroup.Volume = silent and 0 or settings.master
end

publishMode = function()
	player:SetAttribute("MenuMode", loadingNow and "loading" or mode)
	updateMute()
	if refreshTouchPause then refreshTouchPause() end
	if syncCameraLock then syncCameraLock() end
end
setMode = function(m)
	mode = m
	publishMode()
end

-- First-person lock: on while you're actually playing (the server sets Chapter / ChallengeChamber / WorkshopMap /
-- CoopPartner / EditorPlaytest), off on the main menu and while building in the editor.
local function inGameplay()
	if loadingNow or mode == "main" then return false end
	if player:GetAttribute("InEditor") then return player:GetAttribute("EditorPlaytest") == true end
	return player:GetAttribute("Chapter") ~= nil or player:GetAttribute("ChallengeChamber") ~= nil
		or player:GetAttribute("WorkshopMap") ~= nil or player:GetAttribute("CoopPartner") ~= nil
end
syncCameraLock = function()
	if not CFG.LOCK_FIRST_PERSON then return end
	local want = inGameplay() and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
	if player.CameraMode ~= want then player.CameraMode = want end
end
for _, attr in ipairs({ "Chapter", "ChallengeChamber", "WorkshopMap", "CoopPartner", "InEditor", "EditorPlaytest" }) do
	player:GetAttributeChangedSignal(attr):Connect(syncCameraLock)
end

setCrosshair = function()
	local o = playerGui:FindFirstChild(CFG.CROSSHAIR_GUI)
	if o and o:IsA("ScreenGui") then
		o.Enabled = mode == "none" and settings.crosshair == "Enabled"
	end
end

-- ----- aspect ratio bars -----
local aspectGui = new("ScreenGui", { Name = "PortalAspect", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 500, Parent = playerGui })
local bars = {}
for i = 1, 2 do
	bars[i] = new("Frame", { BackgroundColor3 = rgb(0), BorderSizePixel = 0, Visible = false, Active = false, Parent = aspectGui })
end
ASPECTS = { ["Widescreen 16:9"] = 16 / 9, ["Widescreen 16:10"] = 16 / 10, ["Normal 4:3"] = 4 / 3 }
updateAspect = function()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	bars[1].Visible, bars[2].Visible = false, false
	local target = ASPECTS[settings.aspect]
	if not target or vp.Y < 10 then return end
	local cur = vp.X / vp.Y
	if cur > target + 0.01 then
		local w = (vp.X - vp.Y * target) / 2
		bars[1].Position, bars[1].Size = px(0, 0), px(w, vp.Y)
		bars[2].Position, bars[2].Size = px(vp.X - w, 0), px(w, vp.Y)
		bars[1].Visible, bars[2].Visible = true, true
	elseif cur < target - 0.01 then
		local h = (vp.Y - vp.X / target) / 2
		bars[1].Position, bars[1].Size = px(0, 0), px(vp.X, h)
		bars[2].Position, bars[2].Size = px(0, vp.Y - h), px(vp.X, h)
		bars[1].Visible, bars[2].Visible = true, true
	end
end

-- ----- display mode -----
local ugs = UserSettings():GetService("UserGameSettings")
local winParts = {}
for i = 1, 4 do
	winParts[i] = new("Frame", { BackgroundColor3 = rgb(0), BorderSizePixel = 0, Visible = false, Active = false, Parent = aspectGui })
end
local winTitle = new("Frame", { BackgroundColor3 = rgb(46, 48, 52), BorderSizePixel = 0, Visible = false, Active = false, Parent = aspectGui })
new("TextLabel", {
	Size = UDim2.new(1, -120, 1, 0), Position = px(12, 0), BackgroundTransparency = 1, Text = "Portal 2 - Aperture Science",
	FontFace = F_SET, TextSize = 16, TextColor3 = rgb(200), TextXAlignment = Enum.TextXAlignment.Left, Parent = winTitle,
})
new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = px(90, 28), BackgroundTransparency = 1,
	Text = "_    []    X", FontFace = F_TITLE, TextSize = 16, TextColor3 = rgb(200), Parent = winTitle,
})
local realWindowed = false
updateWindow = function()
	for _, f in ipairs(winParts) do f.Visible = false end
	winTitle.Visible = false
	if settings.display ~= "Windowed" or realWindowed then return end
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	if vp.Y < 10 then return end
	local mx, my, tb = math.floor(vp.X * 0.05), math.floor(vp.Y * 0.08), 28
	winParts[1].Position, winParts[1].Size = px(0, 0), px(vp.X, my)
	winParts[2].Position, winParts[2].Size = px(0, vp.Y - my + tb), px(vp.X, my - tb)
	winParts[3].Position, winParts[3].Size = px(0, my), px(mx, vp.Y - 2 * my + tb)
	winParts[4].Position, winParts[4].Size = px(vp.X - mx, my), px(mx, vp.Y - 2 * my + tb)
	winTitle.Position, winTitle.Size = px(mx, my - tb), px(vp.X - 2 * mx, tb)
	for _, f in ipairs(winParts) do f.Visible = true end
	winTitle.Visible = true
end
local function applyDisplay()
	local wantWindowed = settings.display == "Windowed"
	realWindowed = false
	local ok = pcall(function()
		if ugs:InFullScreen() == wantWindowed then ugs:ToggleFullscreen() end
	end)
	realWindowed = ok and wantWindowed
	updateWindow()
end

-- ----- voice chat -----
local pttHeld = false
local function applyVoiceTo(inp)
	local v = settings.voice
	if v == "Enabled" then return end
	local mine = inp:IsDescendantOf(player)
	pcall(function()
		if v == "Disabled" then inp.Muted = true
		elseif mine then inp.Muted = not pttHeld
		else inp.Muted = false end
	end)
end
local function applyVoice()
	for _, d in ipairs(Players:GetDescendants()) do
		if d:IsA("AudioDeviceInput") then
			if settings.voice == "Enabled" then pcall(function() d.Muted = false end) else applyVoiceTo(d) end
		end
	end
end
Players.DescendantAdded:Connect(function(d)
	if d:IsA("AudioDeviceInput") then task.defer(applyVoiceTo, d) end
end)
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.K and settings.voice == "Push To Talk (K)" and not UserInputService:GetFocusedTextBox() then
		pttHeld = true
		applyVoice()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.K and pttHeld then
		pttHeld = false
		applyVoice()
	end
end)

-- ----- apply -----
local QUALITY = {
	Auto = Enum.QualityLevel.Automatic, Low = Enum.QualityLevel.Level03,
	Medium = Enum.QualityLevel.Level08, High = Enum.QualityLevel.Level15,
}
local originalShadows = Lighting.GlobalShadows
local fovTouched = false
local sensViaDelta = false

local function setResample(d)
	pcall(function()
		local pixelated = settings.textureQuality == "Pixelated" or settings.textureQuality == "Low"
		d.ResampleMode = pixelated and Enum.ResamplerMode.Pixelated or Enum.ResamplerMode.Default
	end)
end
local function applyTextureQuality()
	for _, container in ipairs({ playerGui, workspace }) do
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("ImageLabel") or d:IsA("ImageButton") then setResample(d) end
		end
	end
end
playerGui.DescendantAdded:Connect(function(d)
	if d:IsA("ImageLabel") or d:IsA("ImageButton") then
		task.defer(function() if d.Parent then setResample(d) end end)
	end
end)

-- (declared above the do block) local rescale -- forward

bindDisplay = function(name)
	local aliases = { MouseButton1 = "MOUSE1", MouseButton2 = "MOUSE2", MouseButton3 = "MOUSE3", Backquote = "TILDE", Space = "SPACE" }
	return aliases[name] or string.upper(name or "")
end

-- initial = true on startup: options that would overwrite the player's own engine settings are skipped
applySetting = function(key, initial)
	local v = settings[key]
	player:SetAttribute("Setting_" .. key, v)
	if key == "master" then
		updateMute()
		uiGroup.Volume = v
	elseif key == "music" then
		musicGroup.Volume = v
		player:SetAttribute("MusicVolume", v)
	elseif key == "sfx" then
		sfxGroup.Volume = v
	elseif key == "brightness" then
		brightnessFX.Brightness = (v - 0.5) * 0.4
	elseif key == "fov" then
		player:SetAttribute("FieldOfView", v)
		if not initial then fovTouched = true end
	elseif key == "crosshair" then
		setCrosshair()
	elseif key == "aspect" or key == "resolution" then
		if rescale then rescale() end
	elseif key == "textureQuality" then
		applyTextureQuality()
	elseif initial then
		return
	elseif key == "mouseSens" then
		local s = 2 ^ ((v - 0.5) * 4)
		local ok = pcall(function() ugs.MouseSensitivity = s end)
		sensViaDelta = not ok
		if not ok then UserInputService.MouseDeltaSensitivity = s end
	elseif key == "quality" then
		pcall(function() getRobloxSettings().Rendering.QualityLevel = QUALITY[v] end)
	elseif key == "shadows" then
		Lighting.GlobalShadows = v == "Enabled" and (originalShadows or true) or false
	elseif key == "display" then
		applyDisplay()
	elseif key == "voice" then
		applyVoice()
	end
end
for k in pairs(settings) do applySetting(k, true) end
updateMute()

-- settings go to the server a couple of seconds after the last change
local settingsSaveQueued = false
local optionsAchievement = false
onSettingChanged = function()
	if not optionsAchievement then
		optionsAchievement = true
		task.spawn(Net.call, "ClientAchievement", "OPTIONS")
	end
	if settingsSaveQueued then return end
	settingsSaveQueued = true
	task.delay(2, function()
		settingsSaveQueued = false
		Net.call("SetSettings", settings)
	end)
end

loadSettingsFromProfile = function()
	for k, v in pairs(P.settings or {}) do
		if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) and settings[k] ~= v then
			settings[k] = v
			applySetting(k, false)
		end
	end
end

-- ----- field of view -----
RunService:BindToRenderStep("PortalMenuFOV", Enum.RenderPriority.Camera.Value + 4, function()
	if not fovTouched then return end
	if player:GetAttribute("InEditor") and not player:GetAttribute("EditorPlaytest") then return end -- the editor runs its own camera
	local cam = workspace.CurrentCamera
	if cam and cam.FieldOfView ~= settings.fov then cam.FieldOfView = settings.fov end
end)

-- ----- motion blur -----
-- Roblox gives scripts no shader / velocity buffer, so true per-pixel blur isn't possible. This is the closest thing:
-- it runs AFTER every camera script (so it sees the real final camera), measures how fast the view turns and moves
-- each frame, ignores teleports / portal jumps / cutscene cuts, and drives a blur that ramps up fast and settles smoothly.
do
	local lastCF, lastEpoch, amt = nil, nil, 0
	RunService:BindToRenderStep("PortalMotionBlur", Enum.RenderPriority.Last.Value + 10, function(dt)
		local cam = workspace.CurrentCamera
		if not cam or dt <= 0 then return end
		local cf = cam.CFrame
		local epoch = cam:GetAttribute("PortalViewEpoch")
		if epoch ~= lastEpoch then lastEpoch = epoch lastCF = nil end
		local want = 0
		local editing = player:GetAttribute("InEditor") and not player:GetAttribute("EditorPlaytest")
		if settings.motionBlur == "Enabled" and mode == "none" and not loadingNow and lastCF and not editing then
			local ang = math.acos(math.clamp(cf.LookVector:Dot(lastCF.LookVector), -1, 1))
			local moved = (cf.Position - lastCF.Position).Magnitude
			if ang < 0.9 and moved < 30 then -- bigger than this in one frame is a cut, not motion
				local turn = ang / dt          -- rad/s
				local speed = moved / dt       -- studs/s
				local k = 0.4 + settings.blurStrength * 1.6
				want = (math.max(turn - 0.5, 0) * 3.4 + math.max(speed - 35, 0) * 0.06) * k
			end
		end
		lastCF = cf
		want = math.min(want, 24)
		local rate = want > amt and 28 or 9
		amt += (want - amt) * (1 - math.exp(-dt * rate))
		motionBlurFX.Size = amt
		motionBlurFX.Enabled = amt > 0.15
	end)
end

-- ----- mouse look: Reverse Mouse / Raw Mouse Input / Mouse Acceleration -----
do
	local ROBLOX_YAW, ROBLOX_PITCH = 0.002 * math.pi, 0.0015 * math.pi
	local MAX_PITCH = math.rad(80)
	RunService:BindToRenderStep("PortalMouseLook", Enum.RenderPriority.Camera.Value - 1, function(dt)
		if mode ~= "none" or loadingNow or dt <= 0 then return end
		local reverse = settings.reverseMouse == "Enabled"
		local raw = settings.rawMouse == "Enabled"
		local accel = settings.mouseAccel == "Enabled" and not raw
		if not (reverse or raw or accel) then return end
		if UserInputService.MouseBehavior == Enum.MouseBehavior.Default then return end
		local cam = workspace.CurrentCamera
		if not cam or cam.CameraType ~= Enum.CameraType.Custom then return end
		local d = UserInputService:GetMouseDelta()
		if d.X == 0 and d.Y == 0 then return end
		local robloxSens = 1
		pcall(function() robloxSens = ugs.MouseSensitivity end)
		local baseYaw, basePitch = d.X * ROBLOX_YAW * robloxSens, d.Y * ROBLOX_PITCH * robloxSens
		local tYaw, tPitch = baseYaw, basePitch
		if raw then
			local ours = sensViaDelta and 1 or 2 ^ ((settings.mouseSens - 0.5) * 4)
			tYaw, tPitch = d.X * ROBLOX_YAW * ours, d.Y * ROBLOX_PITCH * ours
		end
		if accel then
			local f = 1 + settings.accelAmount * math.clamp(d.Magnitude / dt / 1200, 0, 3)
			tYaw, tPitch = tYaw * f, tPitch * f
		end
		if reverse then tPitch = -tPitch end
		local eYaw, ePitch = tYaw - baseYaw, tPitch - basePitch
		local cf = cam.CFrame
		local rot = CFrame.Angles(0, -eYaw, 0) * cf.Rotation
		local pitch = math.asin(math.clamp(rot.LookVector.Y, -1, 1))
		local newPitch = math.clamp(pitch - ePitch, -MAX_PITCH, MAX_PITCH)
		rot = rot * CFrame.Angles(newPitch - pitch, 0, 0)
		cam.CFrame = CFrame.new(cf.Position) * rot
	end)
end

-- ----- captions -----
do
	local ccGui = new("ScreenGui", { Name = "PortalCaptions", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60, Parent = playerGui })
	local label = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90), Size = px(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = rgb(0), BackgroundTransparency = 0.35,
		Text = "", FontFace = F_SET, TextSize = 28, TextColor3 = rgb(255), TextWrapped = true, Visible = false, Parent = ccGui,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = label })
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = label })
	new("UISizeConstraint", { MaxSize = Vector2.new(1000, 400), Parent = label })

	local voiceIds = {}
	local assets = ReplicatedStorage:FindFirstChild("PortalAssets")
	local voiceFolder = assets and assets:FindFirstChild("GLaDOSVL")
	if voiceFolder then
		for _, sd in ipairs(voiceFolder:GetDescendants()) do
			if sd:IsA("Sound") then voiceIds[sd.SoundId] = true end
		end
	end
	local active = {}
	local function humanize(name)
		name = string.gsub(name, "[_%-]+", " ")
		name = string.gsub(name, "(%l)(%u)", "%1 %2")
		return name
	end
	local function add(text, dur)
		for i = #active, 1, -1 do
			if active[i].text == text then table.remove(active, i) end
		end
		table.insert(active, { text = text, untilT = os.clock() + dur })
		while #active > 3 do table.remove(active, 1) end
	end
	local function onPlay(sd)
		if settings.cc == "None" or mode == "main" or loadingNow then return end
		local dur = sd.TimeLength > 0 and math.max(sd.TimeLength / math.max(sd.PlaybackSpeed, 0.1), 2) or 4
		local dialogue = sd:GetAttribute("Dialogue") == true or voiceIds[sd.SoundId]
		local caption = sd:GetAttribute("Caption")
		if dialogue or (type(caption) == "string" and caption ~= "") then
			add(type(caption) == "string" and caption ~= "" and caption or ("GLaDOS: " .. humanize(sd.Name)), dur)
		elseif settings.cc == "Closed Captions" then
			local sfxText = sd:GetAttribute("SFXCaption")
			if type(sfxText) == "string" and sfxText ~= "" then add("[" .. sfxText .. "]", dur) end
		end
	end
	local hooked = setmetatable({}, { __mode = "k" })
	local function hook(d)
		if not d:IsA("Sound") or hooked[d] then return end
		hooked[d] = true
		d:GetPropertyChangedSignal("Playing"):Connect(function()
			if d.Playing then onPlay(d) end
		end)
		if d.IsPlaying then onPlay(d) end
	end
	for _, c in ipairs({ workspace, SoundService, playerGui }) do
		for _, d in ipairs(c:GetDescendants()) do hook(d) end
		c.DescendantAdded:Connect(function(d) task.defer(hook, d) end)
	end
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for i = #active, 1, -1 do
			if active[i].untilT < now then table.remove(active, i) end
		end
		if #active == 0 or settings.cc == "None" or mode == "main" or loadingNow then
			label.Visible = false
			return
		end
		local lines = {}
		for _, a in ipairs(active) do table.insert(lines, a.text) end
		label.Text = table.concat(lines, "\n")
		label.TextSize = settings.ccSize == "Large" and 36 or 28
		label.Visible = true
	end)
end

end
-- ==========================================
-- GUI ROOTS
-- ==========================================

for _, n in ipairs({ "PortalMenu", "PortalLoading", "PortalTransition" }) do
	local old = playerGui:FindFirstChild(n)
	if old then old:Destroy() end
end

local gui = new("ScreenGui", {
	Name = "PortalMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false, Parent = playerGui,
})
local menuAction = new("BindableEvent", { Name = "MenuAction", Parent = gui })
local menuRequest = new("BindableEvent", { Name = "MenuRequest", Parent = gui })

-- ==========================================
-- TOASTS (Options > Gameplay / Editor / Advanced Video > Toast Notifications turns them off)
-- ==========================================
-- Same look as the "Achievement Unlocked!" popup (PortalAchievementToast), but they slide DOWN out of the top right
-- corner. Up to TOAST.MAX stack under each other, the rest wait their turn.
-- Other scripts: MenuRequest:Fire("Toast", { title = "...", text = "...", kind = "info" | "good" | "bad" | "locked" | "chip", icon = "rbxassetid://..." })
-- The server: Push "Toast" { text, title, kind }
local TOAST = {
	SOUND = "rbxassetid://78959439349986", -- played when one pops (blank = silent)
	HOLD = 4.5,                            -- seconds on screen
	WIDTH = 460, HEIGHT = 120,             -- card size at 1080p
	MARGIN = 28,                           -- gap to the screen corner
	GAP = 10,                              -- gap between stacked toasts
	MAX = 3,                               -- on screen at once
	SCALE = 1,                             -- overall size multiplier
}
local toast
do
	local toastGui = new("ScreenGui", {
		Name = "PortalToasts", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 590,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui,
	})
	local W, H, PAD = TOAST.WIDTH, TOAST.HEIGHT, 16
	local stack = new("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TOAST.MARGIN, 0, TOAST.MARGIN),
		Size = UDim2.fromOffset(W, (H + TOAST.GAP) * TOAST.MAX), BackgroundTransparency = 1, Parent = toastGui,
	})
	new("UIListLayout", { Padding = UDim.new(0, TOAST.GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = stack })
	local toastScale = new("UIScale", { Parent = stack })
	local function rescaleToasts()
		local c = workspace.CurrentCamera
		local s = c and math.clamp(c.ViewportSize.Y / 1080, 0.7, 2) or 1
		toastScale.Scale = s * TOAST.SCALE
		-- clear of Roblox's own top bar buttons
		local top = math.max(TOAST.MARGIN, GuiService.TopbarInset.Max.Y + 10)
		stack.Position = UDim2.new(1, -TOAST.MARGIN * s, 0, top)
	end
	local function hookToastCamera()
		local c = workspace.CurrentCamera
		if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleToasts) end
		rescaleToasts()
	end
	hookToastCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookToastCamera)
	pcall(function() GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(rescaleToasts) end)

	local GOTHAM = "rbxasset://fonts/families/GothamSSm.json"
	local ACCENT = {
		info = rgb(38, 178, 214), good = rgb(110, 210, 90), bad = rgb(230, 90, 70), locked = rgb(240, 150, 50),
		achievement = rgb(240, 205, 70), chip = rgb(170, 110, 255),
	}
	local GLYPH = { info = "i", good = "+", bad = "!", locked = "!", achievement = "A", chip = "C" }
	local queue, live, order = {}, 0, 0
	local recent = {}

	local function popSound()
		if TOAST.SOUND == "" then return end
		local s = new("Sound", { SoundId = TOAST.SOUND, Volume = 0.6, Parent = SoundService })
		local ui = SoundService:FindFirstChild("PortalUI")
		if ui then s.SoundGroup = ui end
		s:Play()
		s.Ended:Once(function() s:Destroy() end)
	end

	local showNext
	local function showOne(t)
		live += 1
		order += 1
		-- a clipping slot in the stack; the card slides down into it from above, and back up out of it
		local slot = new("Frame", { Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, ClipsDescendants = true, LayoutOrder = order, Parent = stack })
		local card = new("Frame", { Position = UDim2.fromScale(0, -1), Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255), BorderSizePixel = 0, Parent = slot })
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(30, 32, 35), rgb(14, 42, 64)), Parent = card })
		new("UIStroke", { Color = rgb(70, 90, 110), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })
		local accent = ACCENT[t.kind or "info"] or ACCENT.info
		local ICON = H - PAD * 2
		local iconBox = new("Frame", { Position = UDim2.fromOffset(PAD, PAD), Size = UDim2.fromOffset(ICON, ICON), BackgroundColor3 = rgb(30),
			BorderSizePixel = 0, Parent = card })
		new("UIStroke", { Color = accent, Thickness = 2, Parent = iconBox })
		if type(t.icon) == "string" and t.icon ~= "" then
			new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = t.icon, ScaleType = Enum.ScaleType.Fit, Parent = iconBox })
		else
			new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = GLYPH[t.kind or "info"] or "i",
				FontFace = Font.new(GOTHAM, Enum.FontWeight.Bold), TextSize = 44, TextColor3 = accent, Parent = iconBox })
		end
		local textX = PAD * 2 + ICON
		local textW = W - textX - PAD
		new("TextLabel", {
			Position = UDim2.fromOffset(textX, PAD - 4), Size = UDim2.fromOffset(textW, 30), BackgroundTransparency = 1,
			Text = (t.title and t.title ~= "") and t.title or "Notice", FontFace = Font.new(GOTHAM, Enum.FontWeight.Medium), TextSize = 24,
			TextColor3 = rgb(255), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card,
		})
		local desc = new("TextLabel", {
			Position = UDim2.fromOffset(textX, PAD + 30), Size = UDim2.fromOffset(textW, H - PAD * 2 - 30), BackgroundTransparency = 1, Text = t.text,
			FontFace = Font.new(GOTHAM, Enum.FontWeight.Regular), TextSize = 19, TextWrapped = true, TextScaled = true,
			TextColor3 = rgb(205), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = card,
		})
		new("UITextSizeConstraint", { MaxTextSize = 19, MinTextSize = 12, Parent = desc })
		popSound()
		TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
		task.delay(0.45 + TOAST.HOLD, function()
			local out = TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Position = UDim2.fromScale(0, -1) })
			out:Play()
			out.Completed:Wait()
			slot:Destroy()
			live -= 1
			showNext()
		end)
	end
	showNext = function()
		while live < TOAST.MAX and #queue > 0 do showOne(table.remove(queue, 1)) end
	end

	toast = function(text, title, kind, iconImage)
		if settings.toasts == "Disabled" or type(text) ~= "string" or text == "" then return end
		local key = tostring(title) .. "|" .. text
		if recent[key] and os.clock() - recent[key] < 1.5 then return end -- the same toast twice in a row
		recent[key] = os.clock()
		if #queue >= 8 then table.remove(queue, 1) end
		table.insert(queue, { text = text, title = title, kind = kind, icon = iconImage })
		showNext()
	end
end

-- ==========================================
-- TUTORIALS (a card bottom left when a level starts; Options > Gameplay > Tutorials turns them off)
-- ==========================================
-- Every chapter, challenge, Workshop chamber, co-op game, the editor and editor playtests get one (PortalConfig
-- C.TUTORIALS, or a chapter's own `tutorial` list). Enter = next, Backspace = skip. Other scripts can show one with
-- MenuRequest:Fire("Tutorial", "editor") (forces it even if it was already seen this session).
local showTutorial
do
	local tutGui = new("ScreenGui", {
		Name = "PortalTutorial", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 425,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false, Parent = playerGui,
	})
	local card = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -90), Size = UDim2.fromOffset(460, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(28, 32, 34), BackgroundTransparency = 0.1, BorderSizePixel = 0, Parent = tutGui,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = card })
	new("UIStroke", { Color = COL.CYAN, Thickness = 2, Transparency = 0.3, Parent = card })
	new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), Parent = card })
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
	local tutScale = new("UIScale", { Parent = card })
	local head = new("TextLabel", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = "TUTORIAL", FontFace = F_SET, TextSize = 15,
		TextColor3 = COL.CYAN, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = card })
	local title = new("TextLabel", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Text = "", FontFace = F_TITLE, TextSize = 26,
		TextColor3 = Color3.fromRGB(240, 246, 244), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Parent = card })
	local body = new("TextLabel", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = "",
		FontFace = F_SET, TextSize = 20, TextWrapped = true, TextColor3 = Color3.fromRGB(220, 228, 226), TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3, Parent = card })
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 4, Parent = card })
	local function btn(x, w, text, fn, blue)
		local b = new("TextButton", { Position = UDim2.fromOffset(x, 2), Size = UDim2.fromOffset(w, 28), BorderSizePixel = 0, AutoButtonColor = true,
			BackgroundColor3 = blue and COL.BLUE_BTN or Color3.fromRGB(70, 76, 78), Text = text, FontFace = F_ROW, TextSize = 16,
			TextColor3 = Color3.fromRGB(240, 244, 244), Parent = row })
		new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = b })
		b.MouseButton1Click:Connect(function() uiSound(CFG.SOUND_CLICK) fn() end)
		return b
	end
	local hint = new("TextLabel", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = "ENTER  next      BACKSPACE  skip", FontFace = F_SET,
		TextSize = 13, TextColor3 = Color3.fromRGB(150, 160, 158), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 5, Parent = card })
	local steps, idx, token = nil, 1, 0
	local seen = {}
	local nextBtn

	local function close()
		token += 1
		tutGui.Enabled = false
		steps = nil
	end
	local function render()
		if not steps then return end
		local st = steps[idx]
		head.Text = ("TUTORIAL  %d / %d"):format(idx, #steps)
		title.Text = st[1] or ""
		body.Text = st[2] or ""
		nextBtn.Text = idx >= #steps and "DONE" or "NEXT"
		hint.Visible = not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled
		token += 1
		local my = token
		-- moves on by itself if you're busy playing (the mouse is locked in first person)
		task.delay(12, function()
			if my == token and steps then
				if idx < #steps then idx += 1 render() else close() end
			end
		end)
	end
	local function nextStep()
		if not steps then return end
		if idx < #steps then idx += 1 render() else close() end
	end
	btn(0, 90, "BACK", function() if steps and idx > 1 then idx -= 1 render() end end)
	nextBtn = btn(98, 90, "NEXT", nextStep, true)
	btn(196, 70, "SKIP", close)
	btn(274, 150, "TURN OFF TUTORIALS", function()
		close()
		settings.tutorial = "Disabled"
		applySetting("tutorial")
		onSettingChanged()
		toast("Turn them back on in Options > Gameplay.", "Tutorials off", "info")
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if not steps or gpe or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.Return then nextStep()
		elseif input.KeyCode == Enum.KeyCode.Backspace then close() end
	end)
	player:GetAttributeChangedSignal("Setting_tutorial"):Connect(function()
		if settings.tutorial == "Disabled" then close() end
	end)

	showTutorial = function(key, list, force)
		if type(list) ~= "table" or #list == 0 then return end
		if not force and (settings.tutorial == "Disabled" or seen[key]) then return end
		seen[key] = true
		task.spawn(function()
			-- wait for the loading screen / menus to get out of the way
			local t0 = os.clock()
			while (loadingNow or mode ~= "none") and os.clock() - t0 < 30 do task.wait(0.25) end
			task.wait(0.8)
			if loadingNow or mode ~= "none" then return end
			local c = workspace.CurrentCamera
			tutScale.Scale = math.clamp((c and c.ViewportSize.Y or 1080) / 1080, 0.6, 1.4)
			steps, idx = list, 1
			tutGui.Enabled = true
			render()
		end)
	end

	-- which tutorial goes with what you're doing now
	local function chapterSteps(n)
		local ch = Config.Chapter(n)
		if ch and type(ch.tutorial) == "table" then return ch.tutorial end
		local basics = Config.TUTORIALS.chapter or {}
		if n == 1 then return basics end
		-- later chapters: the chapter's name and one reminder
		local tip = basics[((n - 2) % math.max(#basics, 1)) + 1]
		local list = { { ("Chapter %d: %s"):format(n, ch and ch.title or ""), "New chamber, new tricks. Look for what opens the exit door." } }
		if tip then table.insert(list, tip) end
		return list
	end
	local function check()
		local T = Config.TUTORIALS or {}
		if player:GetAttribute("InEditor") then
			if player:GetAttribute("EditorPlaytest") then showTutorial("playtest", T.playtest)
			else showTutorial("editor", T.editor) end
		elseif player:GetAttribute("ChallengeChamber") then
			showTutorial("challenge", T.challenge)
		elseif player:GetAttribute("WorkshopMap") then
			showTutorial("workshop", T.workshop)
		elseif type(player:GetAttribute("Chapter")) == "number" then
			local n = player:GetAttribute("Chapter")
			showTutorial("chapter" .. n, chapterSteps(n))
		end
		if player:GetAttribute("CoopPartner") then showTutorial("coop", T.coop) end
	end
	for _, attr in ipairs({ "Chapter", "ChallengeChamber", "WorkshopMap", "CoopPartner", "InEditor", "EditorPlaytest" }) do
		player:GetAttributeChangedSignal(attr):Connect(function() task.defer(check) end)
	end
end

local loadGui = new("ScreenGui", {
	Name = "PortalLoading", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 420,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false, Parent = playerGui,
})
local loadGroup = new("CanvasGroup", {
	Name = "Group", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(0), BorderSizePixel = 0,
	GroupTransparency = 1, Parent = loadGui,
})
local loadImage = new("ImageLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Crop,
	Visible = false, Parent = loadGroup,
})

-- the black tile flips live in their own layer ABOVE the menu and Robot Enrichment, so a flip can cover anything
local transGui = new("ScreenGui", {
	Name = "PortalTransition", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 450,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui,
})

local backdrop = new("Frame", {
	Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(10, 12, 16),
	BorderSizePixel = 0, ClipsDescendants = true, Parent = gui,
})
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(28, 32, 40), rgb(5, 6, 9)), Parent = backdrop })

-- Background, two layers so it is never chopped:
--  * menuBackgroundFill: the same picture cropped to cover the whole screen and darkened (fills any letterbox bars)
--  * menuBackground: the whole picture with ScaleType.Fit, so nothing is cut off, no fade
local menuBackgroundFill = new("ImageLabel", {
	BackgroundTransparency = 1, Image = CFG.MENU_BACKGROUND_IMAGE, ScaleType = Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1),
	ImageColor3 = rgb(80, 84, 92), Visible = CFG.MENU_BACKGROUND_IMAGE ~= "", Parent = backdrop,
})
local menuBackground = new("ImageLabel", {
	BackgroundTransparency = 1, Image = CFG.MENU_BACKGROUND_IMAGE, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(1, 1),
	ImageColor3 = rgb(175, 180, 190), Visible = CFG.MENU_BACKGROUND_IMAGE ~= "", Parent = backdrop,
})
local vignette = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(0), BorderSizePixel = 0, Parent = gui })
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.45, 0.85), NumberSequenceKeypoint.new(1, 0.55),
	}),
	Parent = vignette,
})
local modal = new("TextButton", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Modal = true, AutoButtonColor = false, Selectable = false, Parent = gui,
})

-- Background fit. Both layers always cover the full screen; Fit keeps the whole picture visible.
local function fitBackground()
	for _, img in ipairs({ menuBackground, menuBackgroundFill }) do
		img.Size = UDim2.fromScale(1, 1)
		img.Position = UDim2.fromScale(0, 0)
	end
end

local function scaledRoot(parent)
	local r = new("Frame", { Name = "Root", BackgroundTransparency = 1, Parent = parent })
	local s = new("UIScale", { Parent = r })
	return r, s
end

local root, uiScale = scaledRoot(gui)
local loadRoot, loadScale = scaledRoot(loadGroup)
local transRoot, transScale = scaledRoot(transGui)

local RESOLUTIONS = {
	["1920 x 1080"] = Vector2.new(1920, 1080), ["1600 x 900"] = Vector2.new(1600, 900),
	["1280 x 720"] = Vector2.new(1280, 720), ["1024 x 576"] = Vector2.new(1024, 576),
}

local function getTargetCanvas(vp)
	local selected = RESOLUTIONS[settings.resolution]
	local design = selected and Vector2.new(selected.X, selected.Y) or Vector2.new(vp.X * (1080 / vp.Y), 1080)
	local targetAspect = ASPECTS[settings.aspect]
	if targetAspect then design = Vector2.new(design.Y * targetAspect, design.Y) end
	return design
end

local camConn
rescale = function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	if vp.Y < 10 or vp.X < 10 then return end
	local design = getTargetCanvas(vp)
	local scale = math.min(vp.X / design.X, vp.Y / design.Y)
	for _, pair in ipairs({ { root, uiScale }, { loadRoot, loadScale }, { transRoot, transScale } }) do
		pair[1].AnchorPoint = Vector2.new(0.5, 0.5)
		pair[1].Position = UDim2.fromScale(0.5, 0.5)
		pair[1].Size = px(design.X, design.Y)
		pair[2].Scale = scale
	end
	fitBackground()
	updateAspect()
	updateWindow()
end
local function hookCamera()
	if camConn then camConn:Disconnect() end
	local cam = workspace.CurrentCamera
	if cam then camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale) end
	rescale()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
hookCamera()

-- ==========================================
-- MAIN MENU LOGO
-- ==========================================

local function makeLogo(parent, pos, size)
	local holder = new("Frame", { Position = pos, Size = px(size * 4.6, size * 1.35), BackgroundTransparency = 1, Parent = parent })
	if CFG.LOGO_IMAGE ~= "" then
		new("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = CFG.LOGO_IMAGE, ScaleType = Enum.ScaleType.Fit, Parent = holder,
		})
		return holder
	end
	local txt = new("TextLabel", {
		Position = px(0, size * 0.1), Size = px(size * 3.75, size * 1.1), BackgroundTransparency = 1,
		Text = "PORTAL 2", FontFace = F_TITLE, TextSize = size, TextColor3 = rgb(255),
		TextXAlignment = Enum.TextXAlignment.Left, Parent = holder,
	})
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(246)), ColorSequenceKeypoint.new(0.5, rgb(206)),
			ColorSequenceKeypoint.new(0.52, rgb(170)), ColorSequenceKeypoint.new(1, rgb(128)),
		}),
		Parent = txt,
	})
	return holder
end
makeLogo(root, px(222, 72), 100)

-- ==========================================
-- LAYERS
-- ==========================================

local mainHolder = new("Frame", {
	Position = px(CFG.MAIN_X, CFG.MAIN_Y), Size = px(640, 6 * CFG.MAIN_STEP + 70), BackgroundTransparency = 1,
	Visible = false, Parent = root,
})
local panelLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5, Parent = root })

-- ==========================================
-- BLACK TILE FLIP TRANSITION
-- flipIn covers a rect with black tiles (and waits), flipOut removes them again.
-- ==========================================

local function flipIn(rx, ry, rw, rh)
	local size = (rw * rh > 450000) and CFG.GRID or CFG.BLOCK
	local spread = (rw * rh > 900000) and 0.2 or 0.14
	local blocks = {}
	for c = 0, math.ceil(rw / size) - 1 do
		for r = 0, math.ceil(rh / size) - 1 do
			local bw = math.min(size, rw - c * size)
			local bh = math.min(size, rh - r * size)
			local g = math.random(0, 16)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = px(rx + c * size + bw / 2, ry + r * size + bh / 2),
				Size = px(0, bh), BackgroundColor3 = rgb(g), BorderSizePixel = 0, Parent = transRoot,
			})
			table.insert(blocks, { f = f, w = bw, h = bh })
			task.delay(math.random() * spread, function()
				tileSound()
				tween(f, 0.07, { Size = px(bw + 1, bh) })
			end)
		end
	end
	task.wait(spread + 0.08)
	blocks.spread = spread
	return blocks
end

local function flipOut(blocks)
	local spread = blocks.spread or 0.14
	for _, b in ipairs(blocks) do
		task.delay(math.random() * spread, function()
			tileSound()
			tween(b.f, 0.07, { Size = px(0, b.h) }).Completed:Once(function() b.f:Destroy() end)
		end)
	end
	task.wait(spread + 0.09)
end

local function flipBlocks(rx, ry, rw, rh, midway)
	local b = flipIn(rx, ry, rw, rh)
	if midway then midway() end
	flipOut(b)
end

local function fullRect()
	return 0, 0, transRoot.Size.X.Offset, transRoot.Size.Y.Offset
end

-- ==========================================
-- PANELS
-- ==========================================

-- black overlay strip faded with a gradient (used for the darkened panel edges)
local function shade(f, x, y, w, h, rot, t0, t1)
	if w <= 0 or h <= 0 then return end
	local o = new("Frame", { Position = px(x, y), Size = px(w, h), BackgroundColor3 = rgb(0), BorderSizePixel = 0, Parent = f })
	new("UIGradient", { Rotation = rot, Transparency = NumberSequence.new(t0, t1), Parent = o })
end

-- Real Portal 2 panels (measured from screenshots): flat ~217 grey, faint 204 grid, edges fall off to ~160,
-- top edge to ~164 and the bottom 45% darkens to ~122. Title tabs share the colour so tab + body read as one shape.
-- opts.tab = this is the title tab (no bottom shade), opts.topFrom = start the top shade here (right of the tab)
local function surface(f, dark, opts)
	opts = opts or {}
	f.BorderSizePixel = 0
	f.ClipsDescendants = true
	if dark == "glass" then
		-- see-through grey with faint white grid (in-game pause / playtest pause)
		f.BackgroundColor3, f.BackgroundTransparency = COL.GLASS, 0.38
		local w, h = f.Size.X.Offset, f.Size.Y.Offset
		for x = CFG.GRID, w - 1, CFG.GRID + 11 do
			new("Frame", { Position = px(x, 0), Size = px(2, h), BackgroundColor3 = rgb(255), BackgroundTransparency = 0.82, BorderSizePixel = 0, Parent = f })
		end
		for y = CFG.GRID + 11, h - 1, CFG.GRID + 11 do
			new("Frame", { Position = px(0, y), Size = px(w, 2), BackgroundColor3 = rgb(255), BackgroundTransparency = 0.82, BorderSizePixel = 0, Parent = f })
		end
		shade(f, 0, 0, 120, h, 0, 0.8, 1)
		shade(f, w - 120, 0, 120, h, 0, 1, 0.8)
		return
	end
	f.BackgroundColor3 = dark and (opts.tab and COL.DARK_TAB or COL.DARK) or COL.PANEL
	local gc = dark and COL.DARK_GRID or COL.GRID
	local w, h = f.Size.X.Offset, f.Size.Y.Offset
	local x = CFG.GRID
	while x < w do
		new("Frame", { Position = px(x, 0), Size = px(2, h), BackgroundColor3 = gc, BackgroundTransparency = dark and 0.4 or 0, BorderSizePixel = 0, Parent = f })
		x += CFG.GRID
	end
	local y = CFG.GRID
	while y < h do
		new("Frame", { Position = px(0, y), Size = px(w, 2), BackgroundColor3 = gc, BackgroundTransparency = dark and 0.4 or 0, BorderSizePixel = 0, Parent = f })
		y += CFG.GRID
	end
	local side = math.floor(math.min(90, w * 0.2))
	shade(f, 0, 0, side, h, 0, 0.72, 1)
	shade(f, w - side, 0, side, h, 0, 1, 0.72)
	local topFrom = opts.topFrom or 0
	shade(f, topFrom, 0, w - topFrom, math.min(70, h), 90, 0.76, 1)
	if not opts.tab then
		local bh = math.floor(h * 0.45)
		shade(f, 0, h - bh, w, bh, 90, 1, 0.56)
	end
end

local busy = false
local stack = {}
local function current() return stack[#stack] end

local goBack, startGame, resume, openMain, openPause, openPanel, replaceTop -- forward declarations
local Panels = {}

local LIGHT_BTN = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(101)), ColorSequenceKeypoint.new(0.5, rgb(131)), ColorSequenceKeypoint.new(1, rgb(101)) })
local LIGHT_BTN_HI = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(130)), ColorSequenceKeypoint.new(0.5, rgb(168)), ColorSequenceKeypoint.new(1, rgb(130)) })

-- controller glyph badges on the footer buttons (shown only while a controller is the last input)
local padBadges = setmetatable({}, { __mode = "k" })
local function refreshBadges()
	local on = padActive()
	for b in pairs(padBadges) do
		if b.Parent then b.Visible = on end
	end
end
UserInputService.LastInputTypeChanged:Connect(refreshBadges)

local function footerButton(parent, text, x, y, fn, dark, isBack, glyph)
	local w = math.floor(textWidth(text, F_TITLE, 24) + 52)
	local b = new("TextButton", {
		Position = px(x, y), Size = px(w, CFG.FOOT_H), BackgroundColor3 = dark and rgb(90, 93, 96) or rgb(255),
		BorderSizePixel = 0, AutoButtonColor = false, Text = text, FontFace = F_TITLE, TextSize = 24,
		TextColor3 = dark and rgb(164) or rgb(0), Selectable = false, Parent = parent,
	})
	if glyph then
		local wide = #glyph > 1
		local badge = new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = px(4, 2), Size = px(wide and 34 or 26, 26),
			BackgroundColor3 = GLYPH_COLORS[glyph] or rgb(40), BorderSizePixel = 0, Text = glyph, FontFace = F_TITLE,
			TextSize = wide and 15 or 18, TextColor3 = rgb(255), ZIndex = 6, Visible = padActive(), Parent = b,
		})
		new("UICorner", { CornerRadius = UDim.new(wide and 0.3 or 1, 0), Parent = badge })
		new("UIStroke", { Color = rgb(20), Thickness = 1.5, Parent = badge })
		padBadges[badge] = true
	end
	local grad
	if dark == "glass" then
		b.BackgroundColor3, b.TextColor3 = rgb(255), rgb(20)
		grad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(150, 156, 154)), ColorSequenceKeypoint.new(0.35, COL.GLASS_BTN), ColorSequenceKeypoint.new(1, rgb(218, 224, 222)) }), Parent = b })
		local base = grad.Color
		b.MouseEnter:Connect(function() grad.Color = ColorSequence.new(rgb(240), rgb(250)) uiSound(CFG.SOUND_HOVER) end)
		b.MouseLeave:Connect(function() grad.Color = base end)
		b.MouseButton1Click:Connect(function()
			if busy then return end
			uiSound(isBack and CFG.SOUND_BACK or CFG.SOUND_CLICK)
			fn()
		end)
		return b, w
	elseif dark then
		new("UIStroke", { Color = rgb(70), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	else
		grad = new("UIGradient", { Rotation = 90, Color = LIGHT_BTN, Parent = b })
		new("UIStroke", { Color = rgb(131), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	end
	b.MouseEnter:Connect(function()
		if dark then b.BackgroundColor3, b.TextColor3 = rgb(116, 120, 123), rgb(235)
		else grad.Color = LIGHT_BTN_HI end
		uiSound(CFG.SOUND_HOVER)
	end)
	b.MouseLeave:Connect(function()
		if dark then b.BackgroundColor3, b.TextColor3 = rgb(90, 93, 96), rgb(164)
		else grad.Color = LIGHT_BTN end
	end)
	b.MouseButton1Click:Connect(function()
		if busy then return end
		uiSound(isBack and CFG.SOUND_BACK or CFG.SOUND_CLICK)
		fn()
	end)
	return b, w
end

local function setHi(panel, idx, quiet)
	if panel.hi == idx then return end
	local old = panel.items[panel.hi]
	if old then old.refresh(false) end
	panel.hi = idx
	local it = panel.items[idx]
	if it then
		if panel.ensureVisible then panel.ensureVisible(idx) end
		it.refresh(true)
		if panel.onHi then panel.onHi(idx) end
		if not quiet then uiSound(CFG.SOUND_HOVER) end
	end
end

local function moveHi(panel, dir)
	local n = #panel.items
	if n == 0 then return end
	local i = panel.hi
	for _ = 1, n do
		i = ((i - 1 + dir) % n) + 1
		if panel.items[i] and panel.items[i].enabled then
			setHi(panel, i)
			return
		end
	end
end

local function rowHeight(row)
	if row.h then return row.h end
	if row.kind == "text" then return CFG.ROW * (row.rows or 1) end
	return CFG.ROW
end

local function thumbnail(userId, cb)
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and img then cb(img) end
	end)
end

-- A real 3D model in a ViewportFrame (used for the turret / button decor on the Aperture screens).
-- The clone is stripped of every script, sound, prompt and Humanoid (so a turret's server/client script never runs
-- in the viewport) and of CollectionService tags (so TestElementsClient etc. don't try to drive the copy).
local function decorViewport(parent, panel, assetName, size, pos, spin)
	local template = Config.FindAsset(assetName)
	if not template then return nil end
	local CS = game:GetService("CollectionService")
	local model = Instance.new("Model")
	template:Clone().Parent = model
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ProximityPrompt") or d:IsA("Humanoid") then
			d:Destroy()
		else
			for _, t in ipairs(CS:GetTags(d)) do CS:RemoveTag(d, t) end
			if d:IsA("BasePart") then d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false end
		end
	end
	if not model:FindFirstChildWhichIsA("BasePart", true) then model:Destroy() return nil end
	for _, t in ipairs(CS:GetTags(model)) do CS:RemoveTag(model, t) end

	local vpf = new("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = size, BackgroundTransparency = 1,
		Ambient = rgb(185), LightColor = rgb(255), LightDirection = Vector3.new(-1, -1.5, -1), Parent = parent,
	})
	model.Parent = vpf
	local cf, sz = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() - cf.Position) -- bounding box centre at the origin
	local base = model:GetPivot()
	local cam = new("Camera", { FieldOfView = 30, Parent = vpf })
	vpf.CurrentCamera = cam
	local r = sz.Magnitude / 2
	local half = math.atan(math.tan(math.rad(15)) * math.min(1, size.X.Offset / size.Y.Offset))
	cam.CFrame = CFrame.lookAt(Vector3.new(0, r * 0.3, r / math.sin(half)), Vector3.zero)
	if spin and spin > 0 then
		local t = 0
		table.insert(panel.conns, RunService.RenderStepped:Connect(function(dt)
			t += dt * spin
			model:PivotTo(CFrame.Angles(0, t, 0) * base)
		end))
	end
	return vpf
end

local function makeRow(panel, body, i, yPos, row, w, dark)
	local selectable = row.kind ~= "info" and row.kind ~= "text" and not row.disabled
	local isBtn = row.kind == "button" or row.kind == "list" or row.kind == "cycler"
	local glass = panel.def.glass
	local normalText = row.disabled and COL.DISABLED or row.color or (glass and COL.GLASS_TEXT) or (dark and COL.DARK_TEXT or COL.ROW_TEXT)
	local hiText = (dark or glass) and rgb(12) or rgb(255)
	local h = rowHeight(row)
	local textSize = row.size or (row.kind == "text" and 26 or 30)
	local indent = row.indent or (row.kind == "cycler" and 52) or (row.glyph == "play" and 68) or 22

	local b = new("TextButton", {
		Position = px(0, yPos), Size = px(w, h), BackgroundColor3 = glass and COL.GLASS_HI or (dark and COL.YELLOW or COL.ROW_HI),
		BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 2, Selectable = false, Parent = body,
	})
	local label = new("TextLabel", {
		Position = px(indent, 0), Size = UDim2.new(1, -indent - 22, 1, 0), BackgroundTransparency = 1,
		Text = row.text or "", FontFace = isBtn and F_ROW or F_SET, TextSize = textSize, TextColor3 = normalText,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = row.kind == "text", RichText = row.rich == true,
		ZIndex = 3, Parent = b,
	})
	if row.kind == "text" and (row.rows or 1) > 1 and not row.center then
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Position = px(indent, row.textTop or 12)
		label.LineHeight = row.lineHeight or 1
	end

	local item = { enabled = selectable, button = b, hiNow = false }
	local valueLabel, track, fill, triL, triR, marker, statusLabel
	if row.right then
		-- small right-aligned note ("Local" / "Published")
		statusLabel = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = px(200, h), BackgroundTransparency = 1,
			Text = row.right, FontFace = F_SET, TextSize = 26, TextColor3 = normalText, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, Parent = b,
		})
	end

	local function getValue()
		if row.key then return settings[row.key] end
		if type(row.value) == "function" then return row.value() end
		return row.value
	end
	local function setValue(v)
		if row.key then
			if settings[row.key] == v then return end
			settings[row.key] = v
			applySetting(row.key)
			onSettingChanged()
		elseif row.onChange then
			row.onChange(v)
		end
	end

	if row.kind == "choice" or row.kind == "info" or row.kind == "slider" or row.kind == "bind" then
		valueLabel = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 0), Size = px(w * 0.55, CFG.ROW),
			BackgroundTransparency = 1, Text = "", FontFace = F_SET, TextSize = 30, TextColor3 = normalText,
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, Parent = b,
		})
	end
	if row.kind == "choice" then
		triL = triangle(b, "left", 16, rgb(255))
		triR = triangle(b, "right", 16, rgb(255))
		triR.Position = px(w - 30, CFG.ROW / 2 - 8)
		triL.Visible, triR.Visible = false, false
	elseif row.kind == "cycler" then
		-- dark panels: "< My Queue >" with arrows both sides. light panels: a dark bar with one arrow on the right
		triL = triangle(b, "left", 20, rgb(235))
		triR = triangle(b, "right", 20, rgb(235))
		triL.Position = px(15, h / 2 - 10)
		triR.Position = px(w - 26, h / 2 - 10)
		triL.Visible = dark == true and not row.oneArrow
		if row.oneArrow then label.Position = px(row.indent or 59, 0) end
		label.TextColor3 = rgb(240)
		if not dark then label.Position = px(57, 0) end
	elseif row.glyph == "play" then
		local box = new("Frame", {
			Position = px(22, 5), Size = px(224, 44),
			BackgroundColor3 = rgb(108, 111, 114), BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 2, Parent = b,
		})
		triangle(box, "right", 34, rgb(150)).Position = px(8, 5)
		label.Position = px(76, 5)
		label.Size = px(170, 44)
		label.FontFace = F_SET
	end
	if row.kind == "slider" then
		track = new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0.5, 4), Size = px(CFG.SLIDER_W, 14),
			BackgroundColor3 = rgb(170), BorderSizePixel = 0, ZIndex = 3, Parent = b,
		})
		fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = rgb(10), BorderSizePixel = 0, ZIndex = 4, Parent = track })
		local mn, mx = row.min or 0, row.max or 1
		local dv = row.key and DEFAULTS[row.key] or mn
		marker = triangle(track, "down", 12, rgb(135))
		marker.Position = px(math.clamp((dv - mn) / (mx - mn), 0, 1) * CFG.SLIDER_W - 6, -11)
		valueLabel.Position = UDim2.new(1, -22 - CFG.SLIDER_W - 14, 0, 0)
	end
	if row.kind == "friend" then
		label.Position, label.Size = px(212, 2), px(w - 230, 44)
		label.TextSize, label.FontFace = 36, F_SET
		statusLabel = new("TextLabel", {
			Position = px(212, 44), Size = px(w - 230, 28), BackgroundTransparency = 1, Text = row.status or "",
			FontFace = F_SET, TextSize = 24, TextColor3 = normalText, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3, Parent = b,
		})
		local av = new("ImageLabel", {
			Position = px(120, 5), Size = px(68, 68), BackgroundColor3 = rgb(90), BorderSizePixel = 0, Image = "", ZIndex = 3, Parent = b,
		})
		if row.userId then thumbnail(row.userId, function(img) if av.Parent then av.Image = img end end) end
		-- envelope
		local env = new("Frame", { Position = px(44, 22), Size = px(52, 34), BackgroundTransparency = 1, ZIndex = 3, Parent = b })
		new("UIStroke", { Color = rgb(135), Thickness = 3, Parent = env })
		blob(env, 14, 9, 32, 3, 33, rgb(135), UDim.new(0, 0), 3)
		blob(env, 38, 9, 32, 3, -33, rgb(135), UDim.new(0, 0), 3)
	end

	item.refresh = function(hi)
		item.hiNow = hi
		local tc = hi and hiText or normalText
		if row.kind == "cycler" then
			b.BackgroundColor3 = dark and rgb(130, 134, 138) or rgb(60)
			b.BackgroundTransparency = dark and (hi and 0.55 or 1) or (hi and 0.1 or 0)
			label.Text = tostring(getValue())
			return
		end
		b.BackgroundTransparency = hi and 0 or 1
		label.TextColor3 = tc
		if valueLabel then valueLabel.TextColor3 = tc end
		if statusLabel then statusLabel.TextColor3 = tc end
		local v = getValue()
		if row.kind == "choice" then
			local s = tostring(v)
			valueLabel.Text = s
			valueLabel.Position = UDim2.new(1, hi and -52 or -22, 0, 0)
			triL.Visible, triR.Visible = hi, hi
			if hi then triL.Position = px(w - 74 - textWidth(s, F_SET, 30), CFG.ROW / 2 - 8) end
		elseif row.kind == "info" then
			valueLabel.Text = tostring(v or "")
		elseif row.kind == "bind" then
			local waiting = panel.waitingBind == i
			valueLabel.Text = waiting and "PRESS A KEY..." or bindDisplay(tostring(v or ""))
			valueLabel.TextColor3 = waiting and COL.CYAN or tc
		elseif row.kind == "slider" then
			local mn, mx = row.min or 0, row.max or 1
			local a = math.clamp((v - mn) / math.max(mx - mn, 1e-9), 0, 1)
			fill.Size = UDim2.fromScale(a, 1)
			fill.BackgroundColor3 = hi and rgb(255) or rgb(10)
			track.BackgroundColor3 = hi and rgb(150) or rgb(170)
			valueLabel.Text = row.format and row.format(v) or ""
		end
	end

	local function cycle(dir)
		local opts = row.options
		local idx = table.find(opts, getValue()) or 1
		uiSound(CFG.SOUND_CLICK)
		setValue(opts[((idx - 1 + dir) % #opts) + 1])
		item.refresh(item.hiNow)
	end
	local function nudge(dir)
		local mn, mx = row.min or 0, row.max or 1
		local step = row.step or (mx - mn) / 20
		local before = getValue()
		setValue(math.clamp(before + dir * step, mn, mx))
		if getValue() ~= before then uiSound(CFG.SOUND_BARCHANGE) else uiSound(CFG.SOUND_INVALID) end
		item.refresh(item.hiNow)
	end

	if row.kind == "button" or row.kind == "list" or row.kind == "friend" then
		item.activate = function()
			uiSound(CFG.SOUND_CLICK)
			if row.action then row.action() end
		end
	elseif row.kind == "choice" or row.kind == "cycler" then
		item.activate = function() cycle(1) end
		item.left = function() cycle(-1) end
		item.right = function() cycle(1) end
	elseif row.kind == "bind" then
		item.activate = function()
			if busy then return end
			panel.waitingBind = i
			setHi(panel, i, true)
			item.refresh(true)
			uiSound(CFG.SOUND_CLICK)
		end
	elseif row.kind == "slider" then
		item.left = function() nudge(-1) end
		item.right = function() nudge(1) end
		local dragging, dragInput, lastTick = false, nil, 0
		local function fromX(x)
			local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			local mn, mx = row.min or 0, row.max or 1
			local v = mn + (mx - mn) * a
			if row.step then v = math.floor(v / row.step + 0.5) * row.step end
			local before = getValue()
			setValue(math.clamp(v, mn, mx))
			if getValue() ~= before and os.clock() - lastTick > 0.05 then
				lastTick = os.clock()
				uiSound(CFG.SOUND_BARCHANGE, 0.45)
			end
			item.refresh(item.hiNow)
		end
		b.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) and not busy then
				dragging, dragInput = true, input
				panel.sliderDrag = true
				setHi(panel, i, true)
				fromX(input.Position.X)
			end
		end)
		table.insert(panel.conns, UserInputService.InputChanged:Connect(function(input)
			if not dragging then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or (input.UserInputType == Enum.UserInputType.Touch and input == dragInput) then
				fromX(input.Position.X)
			end
		end))
		table.insert(panel.conns, UserInputService.InputEnded:Connect(function(input)
			if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging, dragInput = false, nil
				panel.sliderDrag = false
			end
		end))
	end

	if selectable then
		b.MouseEnter:Connect(function()
			if not busy then setHi(panel, i) end
		end)
		b.MouseButton1Click:Connect(function()
			if busy or not item.activate then return end
			if panel.touchScrolled then return end -- that touch was a list scroll, not a tap
			local touch = UserInputService:GetLastInputType() == Enum.UserInputType.Touch
			if touch and row.kind == "list" and panel.def.listW and panel.hi ~= i then
				setHi(panel, i, true)
				return
			end
			setHi(panel, i, true)
			item.activate()
		end)
	elseif row.disabled then
		b.MouseButton1Click:Connect(function()
			if not busy then uiSound(CFG.SOUND_INVALID) end
		end)
	end

	item.refresh(false)
	panel.items[i] = item
end

--[[ def = {
	title, subtitle, cells, minBodyCells, padTop,
	rows = { { kind = button|list|choice|cycler|slider|info|text|friend|bind, text, ... } },
	footer = "BACK" | false, play = "PLAY", defaults = true, onBack,
	buttons = { { label, fn, isBack }, ... }   (replaces the default footer)
	dark, backdrop = "aperture", decor, card, rowW,
	listW + maxVisible (+ rowH, fixedTop) list on the left; preview on the right unless noPreview
	previewW / previewH / captionH, info = true (blue "i" dialog), spinner = true,
	onBuilt = function(panel, body, holder) for custom right-hand sides
} ]]
local function buildPanel(def)
	local w = (def.cells or 5) * CFG.GRID
	local titleH = def.title and CFG.GRID or 0
	local padTop = def.padTop or CFG.PAD_TOP
	local rowH = def.rowH or CFG.ROW
	local fixed = math.min(def.fixedTop or 0, #def.rows)
	local fixedH = 0
	for i = 1, fixed do fixedH += rowHeight(def.rows[i]) end
	local nScroll = #def.rows - fixed
	local contentH = 0
	if def.maxVisible then
		contentH = fixedH + (def.listGap or 0) + math.min(nScroll, def.maxVisible) * rowH
	else
		for _, r in ipairs(def.rows) do contentH += rowHeight(r) end
	end
	local bodyCells = math.max(def.minBodyCells or 1, math.ceil((padTop + contentH + CFG.PAD_BOTTOM) / CFG.GRID))
	local bodyH = bodyCells * CFG.GRID
	local total = titleH + bodyH
	local x = def.x or CFG.PANEL_X
	local y = def.y or (CFG.PANEL_BOTTOM - total)
	local hasFooter = def.buttons ~= nil or def.footer ~= false
	local footH = hasFooter and (CFG.FOOT_GAP + CFG.FOOT_H + 4) or 0

	local panel = { items = {}, hi = 0, def = def, x = x, y = y, w = w, conns = {}, scroll = 0, padMap = {} }
	local holder = new("Frame", {
		Position = px(x, y), Size = px(w, total + footH), BackgroundTransparency = 1, Visible = false, ZIndex = 2, Parent = panelLayer,
	})
	panel.frame = holder

	if def.backdrop == "aperture" then
		local bd = new("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255), BorderSizePixel = 0, Visible = false, ZIndex = 1,
			ClipsDescendants = true, Parent = panelLayer,
		})
		new("UIGradient", { Rotation = 35, Color = ColorSequence.new(rgb(244), rgb(184)), Parent = bd })
		for k = -9, 9 do
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = px(960, 540 + k * 200), Size = px(4200, 2),
				Rotation = 26, BackgroundColor3 = rgb(172), BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = bd,
			})
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = px(960 + k * 300, 540), Size = px(4200, 2),
				Rotation = 58, BackgroundColor3 = rgb(172), BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = bd,
			})
		end
		local logo = new("Frame", { Position = px(CFG.PANEL_X, 88), Size = px(520, 110), BackgroundTransparency = 1, Parent = bd })
		if CFG.APERTURE_LOGO_IMAGE ~= "" and CFG.APERTURE_LOGO_IMAGE ~= "rbxassetid://" then
			new("ImageLabel", {
				Size = UDim2.fromOffset(430, 110), BackgroundTransparency = 1, Image = CFG.APERTURE_LOGO_IMAGE, ScaleType = Enum.ScaleType.Fit, Parent = logo,
			})
		else
			local ring = new("Frame", { Size = px(84, 84), BackgroundTransparency = 1, Parent = logo })
			new("UIStroke", { Color = rgb(78), Thickness = 15, Parent = ring })
			new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
			new("TextLabel", {
				Position = px(92, -2), Size = px(430, 62), BackgroundTransparency = 1, Text = "APERTURE",
				FontFace = F_TITLE, TextSize = 66, TextColor3 = rgb(78), TextXAlignment = Enum.TextXAlignment.Left, Parent = logo,
			})
			new("TextLabel", {
				Position = px(98, 58), Size = px(420, 26), BackgroundTransparency = 1, Text = "L A B O R A T O R I E S",
				FontFace = F_SET, TextSize = 21, TextColor3 = rgb(78), TextXAlignment = Enum.TextXAlignment.Left, Parent = logo,
			})
		end
		if def.decor == "button" or def.decor == "turret" then
			local isBtn = def.decor == "button"
			local vp = decorViewport(bd, panel, isBtn and CFG.DECOR_BUTTON_ASSET or CFG.DECOR_TURRET_ASSET,
				isBtn and px(420, 280) or px(360, 480),
				isBtn and UDim2.new(1, -288, 0, 868) or UDim2.new(1, -230, 0, 800),
				isBtn and 0.4 or 0.6)
			if not vp then
				if isBtn then
					-- no Button model found: the old drawn button
					local d = new("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -288, 0, 868), Size = px(340, 220), BackgroundTransparency = 1, Parent = bd,
					})
					blob(d, 170, 126, 330, 150, 0, rgb(70, 76, 82), UDim.new(0.5, 0))
					blob(d, 170, 118, 292, 128, 0, rgb(188, 196, 200), UDim.new(0.5, 0))
					blob(d, 170, 112, 250, 110, 0, rgb(44, 168, 204), UDim.new(0.5, 0))
					blob(d, 170, 104, 232, 98, 0, rgb(205, 76, 88), UDim.new(0.5, 0), 4)
					blob(d, 170, 96, 200, 78, 0, rgb(220, 98, 108), UDim.new(0.5, 0), 5)
				elseif CFG.DECOR_TURRET_IMAGE ~= "" and CFG.DECOR_TURRET_IMAGE ~= "rbxassetid://" then
					-- no Turret model found: the old picture
					new("ImageLabel", {
						AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -230, 0, 800), Size = px(330, 440),
						BackgroundTransparency = 1, Image = CFG.DECOR_TURRET_IMAGE, ScaleType = Enum.ScaleType.Fit, Parent = bd,
					})
				end
			end
		end
		panel.backdrop = bd
		panel.rect = { 0, 0, root.Size.X.Offset, 1080 }
	end

	local tabW = 0
	if def.title then
		local ts = def.titleSize or 52
		local tw = math.min(w, math.max(2, math.ceil((textWidth(def.title, F_TITLE, ts) + 44) / CFG.GRID)) * CFG.GRID)
		tabW = tw
		local tb = new("Frame", { Size = px(tw, CFG.GRID + 2), Parent = holder })
		surface(tb, def.dark, { tab = true })
		new("TextLabel", {
			Position = px(22, def.subtitle and 14 or 0), Size = px(tw - 30, def.subtitle and 56 or CFG.GRID), BackgroundTransparency = 1,
			Text = def.title, FontFace = F_TITLE, TextSize = ts, TextColor3 = def.dark and COL.DARK_TITLE or rgb(16),
			TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, ZIndex = 2, Parent = tb,
		})
		if def.subtitle then
			new("TextLabel", {
				Position = px(22, 66), Size = px(tw - 30, 28), BackgroundTransparency = 1, Text = def.subtitle,
				FontFace = F_TITLE, TextSize = 24, TextColor3 = rgb(236), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2, Parent = tb,
			})
		end
	end

	local body = new("Frame", { Position = px(0, titleH), Size = px(w, bodyH), Parent = holder })
	surface(body, def.glass and "glass" or def.dark, { topFrom = tabW })
	panel.body = body

	-- blue "i" icon for message dialogs
	if def.info then
		local icon = new("Frame", { Position = px(22, 32), Size = px(66, 66), BackgroundColor3 = rgb(255), BorderSizePixel = 0, ZIndex = 3, Parent = body })
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = icon })
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(196, 226, 240)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(151, 193, 212)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 170, 205)),
		}), Parent = icon })
		new("UIStroke", { Color = Color3.fromRGB(90, 130, 150), Thickness = 1.5, Transparency = 0.3, Parent = icon })
		new("TextLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "i", FontFace = F_TITLE, TextSize = 46,
			TextColor3 = rgb(10), ZIndex = 4, Parent = icon,
		})
	end

	-- loading badge with a turning ring of segments (Searching for Friends...)
	if def.spinner then
		local cx, cy = 112, bodyH / 2
		if CFG.LOADING_LOGO ~= "" then
			new("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = px(cx, cy), Size = px(96, 96), BackgroundTransparency = 1,
				Image = CFG.LOADING_LOGO, ScaleType = Enum.ScaleType.Fit, ZIndex = 3, Parent = body,
			})
		end
		local segs = {}
		for k = 1, 14 do
			local a = (k / 14) * math.pi * 2
			segs[k] = blob(body, cx + math.sin(a) * 78, cy - math.cos(a) * 78, 26, 9, math.deg(a), rgb(180), UDim.new(0, 1), 3)
		end
		local t = 0
		table.insert(panel.conns, RunService.RenderStepped:Connect(function(dt)
			t += dt * 9
			for k, s in ipairs(segs) do
				local d = (t - k) % 14
				s.BackgroundColor3 = rgb(math.floor(110 + math.clamp(d, 0, 5) * 14))
			end
		end))
	end

	-- rows
	local scrollable = def.maxVisible and nScroll > def.maxVisible
	local rowW = def.rowW or (def.listW and (def.listW - (scrollable and 27 or 0))) or w
	local cursor = padTop
	for i, row in ipairs(def.rows) do
		makeRow(panel, body, i, cursor, row, (i <= fixed and def.listW) or rowW, def.dark)
		cursor += rowHeight(row)
	end

	-- list + preview (New Game, Load Game, Save Game, Extras, Achievements)
	if def.listW and not def.noPreview then
		local px0 = def.listW + 27
		local pw, ph = def.previewW or 506, def.previewH or 342
		local pf = new("Frame", { Position = px(px0, 33), Size = px(pw, ph), BackgroundColor3 = rgb(0), BorderSizePixel = 0, Parent = body })
		local pi = new("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "",
			ScaleType = def.previewFit and Enum.ScaleType.Fit or Enum.ScaleType.Crop, Parent = pf,
		})
		local tag = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = px(260, 36), BackgroundTransparency = 1,
			Text = "", FontFace = F_TITLE, TextSize = 30, TextColor3 = rgb(240), TextXAlignment = Enum.TextXAlignment.Right,
			TextStrokeTransparency = 0.6, Visible = false, ZIndex = 2, Parent = pf,
		})
		local cap = new("TextLabel", {
			Position = px(px0, 33 + ph + 4), Size = px(pw, def.captionH or 40), BackgroundTransparency = 1, Text = "",
			FontFace = F_SET, TextSize = 30, TextColor3 = def.dark and COL.DARK_TEXT or COL.ROW_TEXT, RichText = true, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = body,
		})
		panel.onHi = function(idx)
			local r = def.rows[idx]
			if not r then return end
			pi.Image = r.preview or ""
			pf.BackgroundColor3 = r.previewColor or rgb(0)
			tag.Text = r.tag or ""
			tag.Visible = r.tag ~= nil
			cap.Text = r.caption or ""
		end
	end

	-- scrolling (fixedTop rows stay put, the rest scroll inside maxVisible)
	if def.maxVisible then
		local thumb
		local listTop = padTop + fixedH + (def.listGap or 0)
		if scrollable then
			triangle(body, "up", 12, rgb(10)).Position = px(def.listW - 21, listTop + 6)
			triangle(body, "down", 12, rgb(10)).Position = px(def.listW - 21, listTop + def.maxVisible * rowH - 12)
			thumb = new("Frame", { BackgroundColor3 = rgb(10), BorderSizePixel = 0, ZIndex = 3, Parent = body })
		end
		local function layout()
			local fy = padTop
			for i, it in ipairs(panel.items) do
				if i <= fixed then
					it.button.Visible = true
					it.button.Position = px(0, fy)
					fy += rowHeight(def.rows[i])
				else
					local j = i - fixed
					it.button.Visible = j > panel.scroll and j <= panel.scroll + def.maxVisible
					it.button.Position = px(0, listTop + (j - 1 - panel.scroll) * rowH)
				end
			end
			if thumb then
				local vis = def.maxVisible
				local trackH = vis * rowH - 48
				local th = math.max(24, trackH * vis / nScroll)
				local maxScroll = nScroll - vis
				local ty = listTop + 24 + (trackH - th) * (maxScroll > 0 and panel.scroll / maxScroll or 0)
				thumb.Size = px(13, th)
				thumb.Position = px(def.listW - 21, ty)
			end
		end
		panel.ensureVisible = function(idx)
			if idx > fixed then
				local j = idx - fixed
				if j <= panel.scroll then panel.scroll = j - 1
				elseif j > panel.scroll + def.maxVisible then panel.scroll = j - def.maxVisible end
			end
			layout()
		end
		layout()
		if scrollable then
			table.insert(panel.conns, UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseWheel and current() == panel and not busy then
					panel.scroll = math.clamp(panel.scroll - input.Position.Z, 0, nScroll - def.maxVisible)
					layout()
				end
			end))
			-- touch: drag the list up / down
			local dragTouch, dragY, dragMoved = nil, 0, 0
			table.insert(panel.conns, UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.Touch or current() ~= panel or busy or panel.sliderDrag then return end
				local pos = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
				local ap, as = body.AbsolutePosition, body.AbsoluteSize
				if pos.X >= ap.X and pos.X <= ap.X + as.X and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y then
					dragTouch, dragY, dragMoved = input, input.Position.Y, 0
					panel.touchScrolled = false
				end
			end))
			table.insert(panel.conns, UserInputService.InputChanged:Connect(function(input)
				if input ~= dragTouch then return end
				local step = rowH * uiScale.Scale
				local dy = input.Position.Y - dragY
				dragMoved += math.abs(input.Delta.Y)
				if dragMoved > 12 then panel.touchScrolled = true end
				while math.abs(dy) >= step do
					panel.scroll = math.clamp(panel.scroll + (dy > 0 and -1 or 1), 0, nScroll - def.maxVisible)
					dragY += dy > 0 and step or -step
					dy = input.Position.Y - dragY
				end
				layout()
			end))
			table.insert(panel.conns, UserInputService.InputEnded:Connect(function(input)
				if input == dragTouch then
					dragTouch = nil
					task.delay(0.05, function() panel.touchScrolled = false end)
				end
			end))
		end
	end

	-- employee badge (Welcome screen)
	if def.card then
		local cardX, cardY = 687, 67
		local card = new("Frame", { Position = px(cardX, cardY), Size = px(303, 473), BackgroundColor3 = rgb(255), BorderSizePixel = 0, ZIndex = 6, Parent = holder })
		new("UICorner", { CornerRadius = UDim.new(0, 16), Parent = card })
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(236), rgb(176)), Parent = card })
		new("UIStroke", { Color = rgb(120), Thickness = 2, Transparency = 0.2, Parent = card })
		local slot = new("Frame", { Position = px(98, 20), Size = px(84, 13), BackgroundColor3 = rgb(244), BorderSizePixel = 0, ZIndex = 7, Parent = card })
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = slot })
		new("UIStroke", { Color = rgb(110), Thickness = 1.5, Parent = slot })
		local photoFrame = new("Frame", { Position = px(16, 50), Size = px(268, 267), BackgroundColor3 = rgb(20), BorderSizePixel = 0, ZIndex = 7, Parent = card })
		local photo = new("ImageLabel", {
			Position = px(3, 3), Size = px(262, 261), BackgroundColor3 = rgb(70, 90, 110), BorderSizePixel = 0,
			ScaleType = Enum.ScaleType.Crop, Image = "", ZIndex = 8, Parent = photoFrame,
		})
		thumbnail(player.UserId, function(img) if photo.Parent then photo.Image = img end end)
		new("TextLabel", {
			Position = px(16, 340), Size = px(270, 44), BackgroundTransparency = 1, Text = player.Name,
			FontFace = F_TITLE, TextSize = 32, TextColor3 = rgb(10), TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = card,
		})
		local ring = new("Frame", { Position = px(16, 404), Size = px(40, 40), BackgroundTransparency = 1, ZIndex = 7, Parent = card })
		new("UIStroke", { Color = rgb(110), Thickness = 7, Parent = ring })
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
		new("TextLabel", {
			Position = px(62, 398), Size = px(220, 30), BackgroundTransparency = 1, Text = "APERTURE",
			FontFace = F_TITLE, TextSize = 29, TextColor3 = rgb(96), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = card,
		})
		new("TextLabel", {
			Position = px(cardX + 16, cardY + 473 + 14), Size = px(300, 32), BackgroundTransparency = 1, Text = CFG.EMPLOYEE_TITLE,
			FontFace = F_SET, TextSize = 27, TextColor3 = rgb(178, 184, 186), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = holder,
		})
	end

	-- footer buttons (+ controller glyphs: back = B, the rest X / Y / LB / RB; A when it does the same as A)
	local footW = 0
	if hasFooter then
		local btns = {}
		if def.buttons then
			for _, bt in ipairs(def.buttons) do table.insert(btns, bt) end
		else
			if def.play then
				table.insert(btns, { def.play, function()
					local it = panel.items[panel.hi]
					if it and it.activate then it.activate() end
				end })
			end
			table.insert(btns, { type(def.footer) == "string" and def.footer or "BACK", function() (def.onBack or goBack)() end, true })
			if def.defaults then
				table.insert(btns, { "USE DEFAULTS", function()
					for _, r in ipairs(def.rows) do
						if r.key then
							settings[r.key] = DEFAULTS[r.key]
							applySetting(r.key)
						end
					end
					onSettingChanged()
					for _, it in ipairs(panel.items) do it.refresh(it.hiNow) end
				end })
			end
		end
		local hasRows = false
		for _, it in ipairs(panel.items) do
			if it.enabled then hasRows = true break end
		end
		local extra, gi, usedA = { "X", "Y", "LB", "RB" }, 0, false
		local fx = 0
		for i, f in ipairs(btns) do
			local g
			if f[3] then
				g = "B"
			elseif (def.play and i == 1) or (not hasRows and not usedA and i == 1) then
				g = "A"
				usedA = true
			else
				gi += 1
				g = extra[gi]
			end
			if g and g ~= "A" and g ~= "B" then panel.padMap[g] = f[2] end
			local _, bw = footerButton(holder, f[1], fx, total + CFG.FOOT_GAP, f[2], def.glass and "glass" or def.dark, f[3], g)
			fx += bw + 27
		end
		footW = fx
		panel.buttons = btns
	end

	if def.onBuilt then def.onBuilt(panel, body, holder) end

	panel.setVisible = function(v)
		holder.Visible = v
		if panel.backdrop then panel.backdrop.Visible = v end
	end
	panel.destroy = function()
		for _, c in ipairs(panel.conns) do c:Disconnect() end
		holder:Destroy()
		if panel.backdrop then panel.backdrop:Destroy() end
	end
	panel.rect = panel.rect or { x, y, math.max(w, footW), total + footH }
	return panel
end

local function firstEnabled(panel)
	local start = panel.def.startHi
	if start and panel.items[start] and panel.items[start].enabled then return start end
	for i, it in ipairs(panel.items) do
		if it.enabled then return i end
	end
	return 0
end

-- simple message dialog with the blue "i" (Exit, Play Online, Developer Commentary, errors ...)
-- buttons = { { "OK", fn }, { "CANCEL", fn, true } }
function Panels.dialog(title, text, buttons, lines)
	return buildPanel({
		title = title, cells = 9, info = true, padTop = 40, buttons = buttons or { { "OK", function() goBack() end, true } },
		rows = { { kind = "text", text = text, rows = lines or 3, indent = 124, color = COL.INFO_TEXT, size = 31, textTop = 8, lineHeight = 1.45 } },
	})
end

function Panels.spinner(text, onCancel)
	return buildPanel({
		-- the real one has no buttons; Backspace / B cancels
		cells = 7, minBodyCells = 2, padTop = 0, spinner = true, footer = false, onBack = onCancel,
		rows = { { kind = "text", text = text, indent = 247, h = 2 * CFG.GRID, size = 32, color = rgb(142), center = true } },
	})
end

-- ==========================================
-- MAIN MENU LIST
-- ==========================================

local mainButtons = {}
local mainHi = 0

local function setMainHi(i, quiet)
	if mainHi == i then return end
	local old = mainButtons[mainHi]
	if old then
		old.BackgroundTransparency = 1
		old.TextColor3 = COL.MAIN_TEXT
	end
	mainHi = i
	local b = mainButtons[i]
	if b then
		b.BackgroundTransparency = 0.45
		b.TextColor3 = COL.MAIN_HI_TEXT
		if not quiet then uiSound(CFG.SOUND_HOVER) end
	end
end

local MAIN_RECT = { CFG.MAIN_X, CFG.MAIN_Y, 640, 6 * CFG.MAIN_STEP + 70 }

-- ==========================================
-- NAVIGATION
-- ==========================================

openPanel = function(builder)
	if busy then return end
	busy = true
	local ok, p = pcall(builder)
	if not ok then
		warn("[PortalMenu] panel build failed:", p)
		busy = false
		return
	end
	local cur = current()
	task.spawn(function()
		if cur then
			flipBlocks(cur.rect[1], cur.rect[2], cur.rect[3], cur.rect[4], function() cur.setVisible(false) end)
		elseif mode == "main" and mainHolder.Visible then
			flipBlocks(MAIN_RECT[1], MAIN_RECT[2], MAIN_RECT[3], MAIN_RECT[4], function() mainHolder.Visible = false end)
		end
		flipBlocks(p.rect[1], p.rect[2], p.rect[3], p.rect[4], function() p.setVisible(true) end)
		table.insert(stack, p)
		setHi(p, firstEnabled(p), true)
		busy = false
	end)
end

-- swap the top panel for a rebuilt one (list source changed, friends finished loading, save deleted ...)
replaceTop = function(builder)
	if busy then return end
	busy = true
	local ok, p = pcall(builder)
	if not ok then
		warn("[PortalMenu] panel build failed:", p)
		busy = false
		return
	end
	local cur = current()
	task.spawn(function()
		if cur then
			flipBlocks(cur.rect[1], cur.rect[2], cur.rect[3], cur.rect[4], function() cur.setVisible(false) end)
			table.remove(stack)
			cur.destroy()
		end
		flipBlocks(p.rect[1], p.rect[2], p.rect[3], p.rect[4], function() p.setVisible(true) end)
		table.insert(stack, p)
		setHi(p, firstEnabled(p), true)
		busy = false
	end)
end

local function clearStack()
	for _, p in ipairs(stack) do p.destroy() end
	table.clear(stack)
end

goBack = function()
	if busy then return end
	local cur = current()
	if not cur then return end
	if #stack == 1 and mode == "pause" then
		resume()
		return
	end
	busy = true
	task.spawn(function()
		flipBlocks(cur.rect[1], cur.rect[2], cur.rect[3], cur.rect[4], function() cur.setVisible(false) end)
		table.remove(stack)
		cur.destroy()
		local prev = current()
		if prev then
			flipBlocks(prev.rect[1], prev.rect[2], prev.rect[3], prev.rect[4], function() prev.setVisible(true) end)
			for _, it in ipairs(prev.items) do it.refresh(false) end
			prev.hi = 0
			setHi(prev, firstEnabled(prev), true)
		elseif mode == "main" then
			flipBlocks(MAIN_RECT[1], MAIN_RECT[2], MAIN_RECT[3], MAIN_RECT[4], function() mainHolder.Visible = true end)
		end
		busy = false
	end)
end

local controls, menuCamPart, camT, setMenuOpen, applyJumpBinding, restoreCamera, setEffects
do
-- ==========================================
-- MENU STATE (mouse, controls, camera, effects)
-- ==========================================

-- (declared above the do block) local controls
task.spawn(function()
	local scripts = player:WaitForChild("PlayerScripts", 10)
	local module = scripts and scripts:WaitForChild("PlayerModule", 5)
	if module then
		local ok, pm = pcall(require, module)
		if ok and pm and pm.GetControls then
			controls = pm:GetControls()
			if mode ~= "none" or loadingNow then controls:Disable() end
		end
	end
end)

local SINK_KEYS = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
	Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
	Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.KeyCode.Thumbstick1,
}
local function sinkAction() return Enum.ContextActionResult.Sink end

local pauseCC = new("ColorCorrectionEffect", { Name = "PortalPauseFX", Enabled = false, Parent = Lighting })
local menuBlur = new("BlurEffect", { Name = "PortalMenuBlur", Size = 0, Enabled = false, Parent = Lighting })

local savedIcon = UserInputService.MouseIconEnabled
-- (declared above the do block) local menuCamPart
camT = 0

setMenuOpen = function(open)
	gui.Enabled = open
	modal.Visible = open
	player:SetAttribute("InMenu", open)
	if controls then
		if open then controls:Disable() elseif not (player:GetAttribute("InEditor") and not player:GetAttribute("EditorPlaytest")) then controls:Enable() end
	end
	setCrosshair()
	if open == S.menuOpen then return end
	S.menuOpen = open
	if open then
		savedIcon = UserInputService.MouseIconEnabled
		GuiService.SelectedObject = nil -- the menu runs its own controller navigation
		ContextActionService:BindActionAtPriority("PortalMenuSink", sinkAction, false, 5000, table.unpack(SINK_KEYS))
		RunService:BindToRenderStep("PortalMenuMouse", Enum.RenderPriority.Last.Value + 5, function(dt)
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = not padActive()
			if mode == "main" and menuCamPart then
				camT += dt
				local cam = workspace.CurrentCamera
				cam.CameraType = Enum.CameraType.Scriptable
				cam.CFrame = menuCamPart.CFrame * CFrame.Angles(math.sin(camT * 0.21) * 0.012, math.sin(camT * 0.13) * 0.02, 0)
			end
		end)
	else
		ContextActionService:UnbindAction("PortalMenuSink")
		RunService:UnbindFromRenderStep("PortalMenuMouse")
		UserInputService.MouseIconEnabled = savedIcon
	end
end

local function jumpAction()
	if player:GetAttribute("InMenu") or loadingNow then return Enum.ContextActionResult.Sink end
	if (settings.bindJump or "Space") == "Space" then return Enum.ContextActionResult.Pass end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.Jump = true end
	return Enum.ContextActionResult.Sink
end

applyJumpBinding = function()
	ContextActionService:UnbindAction("PortalCustomJump")
	ContextActionService:UnbindAction("PortalOldJumpSink")
	local bind = settings.bindJump or "Space"
	if bind ~= "Space" then
		ContextActionService:BindActionAtPriority("PortalOldJumpSink", sinkAction, false, 6000, Enum.KeyCode.Space)
	end
	local ok, key = pcall(function() return Enum.KeyCode[bind] end)
	if ok and key then
		ContextActionService:BindActionAtPriority("PortalCustomJump", jumpAction, false, 6001, key)
	end
end

restoreCamera = function()
	if not menuCamPart then return end
	menuCamPart = nil
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
end

setEffects = function(kind)
	if kind == "pause" then
		pauseCC.Enabled = true
		menuBlur.Enabled = true
		tween(pauseCC, 0.3, { Saturation = -1, Brightness = -0.06, Contrast = 0.05 })
		tween(menuBlur, 0.3, { Size = 6 })
	elseif kind == "main" then
		pauseCC.Enabled = true
		menuBlur.Enabled = true
		pauseCC.Saturation, pauseCC.Brightness, pauseCC.Contrast = -0.35, -0.08, 0.05
		menuBlur.Size = 10
	else
		tween(pauseCC, 0.25, { Saturation = 0, Brightness = 0, Contrast = 0 }).Completed:Once(function()
			if mode == "none" then pauseCC.Enabled = false end
		end)
		tween(menuBlur, 0.25, { Size = 0 }).Completed:Once(function()
			if mode == "none" then menuBlur.Enabled = false end
		end)
	end
end

end
-- ==========================================
-- LOADING SCREEN (round "2" badge top-right, 15 dots bottom-right)
-- ==========================================

if CFG.LOADING_LOGO ~= "" then
	new("ImageLabel", {
		Name = "LoadingLogo", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -29, 0, 30), Size = px(135, 135),
		BackgroundTransparency = 1, Image = CFG.LOADING_LOGO, ScaleType = Enum.ScaleType.Fit, Parent = loadRoot,
	})
end
local dots = {}
for k = 1, 15 do
	dots[k] = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -27 - (15 - k) * 24, 0, 1046), Size = px(15, 15),
		BackgroundColor3 = COL.DOT_OFF, BorderSizePixel = 0, Parent = loadRoot,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dots[k] })
end

-- work() runs while the loading screen is up (it may yield, e.g. a server call). progressFn() can report 0..1.
-- Returns whatever work() returned.
local function runLoading(work, minTime, progressFn, instant)
	loadingNow = true
	publishMode()
	if controls then controls:Disable() end
	if #CFG.LOADING_BACKGROUNDS > 0 then
		loadImage.Image = CFG.LOADING_BACKGROUNDS[math.random(#CFG.LOADING_BACKGROUNDS)]
		loadImage.Visible = true
	else
		loadImage.Visible = false
	end
	loadGui.Enabled = true
	for _, d in ipairs(dots) do d.BackgroundColor3 = COL.DOT_OFF end
	if instant then
		loadGroup.GroupTransparency = 0
	else
		loadGroup.GroupTransparency = 1
		tween(loadGroup, 0.25, { GroupTransparency = 0 })
		task.wait(0.27)
	end
	local done, results = false, {}
	task.spawn(function()
		results = table.pack(pcall(work or function() end))
		if not results[1] then warn("[PortalMenu] loading work failed:", results[2]) end
		done = true
	end)
	minTime = minTime or CFG.LOADING_TIME
	local t, shown = 0, 0
	while true do
		local dt = task.wait()
		t += dt
		local target = math.min(t / minTime, 1)
		if progressFn then target = math.min(target, progressFn()) end
		if not done then target = math.min(target, 0.9) end
		shown += (target - shown) * math.min(dt * 8, 1)
		if done and t >= minTime then shown = 1 end
		local lit = math.floor(shown * #dots + 0.5)
		for k, d in ipairs(dots) do d.BackgroundColor3 = k <= lit and COL.CYAN or COL.DOT_OFF end
		if done and t >= minTime then break end
	end
	task.wait(0.15)
	tween(loadGroup, 0.45, { GroupTransparency = 1 })
	task.wait(0.46)
	loadGui.Enabled = false
	loadingNow = false
	publishMode()
	if controls and mode == "none" and not (player:GetAttribute("InEditor") and not player:GetAttribute("EditorPlaytest")) then controls:Enable() end
	if results[1] then return table.unpack(results, 2, results.n) end
	return false, "Loading failed."
end

local closeAll, exitToMain, showAnywhere
do
-- ==========================================
-- OPEN / CLOSE
-- ==========================================

-- menu art follows the chapter you last played (newest save), else the furthest unlocked chapter.
-- A chapter's `background` (PortalConfig.CHAPTERS) overrides CFG.MENU_BACKGROUND_IMAGE; "" = use the default.
local function setBackground()
	local best, bt = nil, -1
	for _, s in ipairs(P.saves or {}) do
		if (s.time or 0) > bt then best, bt = s, s.time or 0 end
	end
	local ch = Config.Chapter(best and best.chapter or P.maxChapter or 1)
	local img = (ch and ch.background and ch.background ~= "") and ch.background or CFG.MENU_BACKGROUND_IMAGE
	menuBackground.Image = img
	menuBackgroundFill.Image = img
	menuBackground.Visible = img ~= ""
	menuBackgroundFill.Visible = img ~= ""
end

openMain = function()
	clearStack()
	setMode("main")
	camT = 0
	local part = workspace:FindFirstChild(CFG.MENU_CAMERA_PART)
	menuCamPart = (part and part:IsA("BasePart")) and part or nil
	setBackground()
	if menuBackground.Image ~= "" or not menuCamPart then
		backdrop.BackgroundTransparency = 0
		backdrop.Visible = true
	else
		backdrop.Visible = false
		setEffects("main")
	end
	fitBackground()
	vignette.Visible = true
	vignette.BackgroundTransparency = 0
	setMenuOpen(true)
	mainHolder.Visible = false
	setMainHi(0, true)
	busy = true
	task.spawn(function()
		flipBlocks(MAIN_RECT[1], MAIN_RECT[2], MAIN_RECT[3], MAIN_RECT[4], function() mainHolder.Visible = true end)
		busy = false
		if padActive() and mainHi == 0 then setMainHi(1, true) end -- controllers start on the first item
	end)
end

closeAll = function()
	clearStack()
	mainHolder.Visible = false
	setMode("none")
	restoreCamera()
	setEffects("none")
	setMenuOpen(false)
end

local function showError(msg)
	task.defer(function()
		if mode == "none" then return end
		openPanel(function()
			return Panels.dialog("Error", tostring(msg or "Couldn't reach the server."), nil, 2)
		end)
	end)
end

-- runs a server action under the loading screen; on success the menu closes and you're in the game
startGame = function(action, arg)
	if busy then return end
	busy = true
	menuAction:Fire(action, arg)
	task.spawn(function()
		local ok, err = runLoading(function()
			local ok, res = Net.call(action, arg)
			if ok then closeAll() end
			return ok, res
		end)
		busy = false
		if not ok then showError(err) end
	end)
end

resume = function()
	if mode ~= "pause" or busy then return end
	busy = true
	local cur = current()
	task.spawn(function()
		if cur then
			flipBlocks(cur.rect[1], cur.rect[2], cur.rect[3], cur.rect[4], function() cur.setVisible(false) end)
		end
		closeAll()
		busy = false
	end)
end

exitToMain = function()
	if busy then return end
	busy = true
	menuAction:Fire("ExitToMainMenu")
	task.spawn(function()
		runLoading(function()
			Net.call("ExitToMainMenu")
			closeAll()
			busy = false
			openMain()
		end, 1.2)
		busy = false
	end)
end

-- shows a dialog whatever state we're in (in game it opens over a pause screen)
showAnywhere = function(builder)
	task.spawn(function()
		local t0 = os.clock()
		while (busy or loadingNow or S.enrichment) and os.clock() - t0 < 8 do task.wait(0.1) end
		if busy or loadingNow then return end
		if mode == "none" then openPause(builder) else openPanel(builder) end
	end)
end

end
-- ==========================================
-- ROBOT ENRICHMENT (roll to black, then RobotEnrichment script takes over)
-- ==========================================

local function openEnrichment()
	if busy or S.enrichment then return end
	busy = true
	task.spawn(function()
		local blocks = flipIn(fullRect())
		S.enrichment = true
		player:SetAttribute("InEnrichment", true)
		menuAction:Fire("RobotEnrichment")
		task.spawn(Net.call, "ClientAchievement", "ENRICHMENT")
		task.wait(0.06)
		flipOut(blocks)
		busy = false
	end)
end

menuRequest.Event:Connect(function(kind, arg)
	if kind == "Tutorial" then
		local T = Config.TUTORIALS or {}
		if type(arg) == "string" and T[arg] then showTutorial(arg, T[arg], true) end
		return
	elseif kind == "Toast" then
		if type(arg) == "table" then toast(arg.text, arg.title, arg.kind, arg.icon) else toast(tostring(arg)) end
		return
	elseif kind == "SetSetting" then
		-- other scripts changing a setting (the editor's File > Editor mode): saved like any other option
		if type(arg) == "table" and type(arg.key) == "string" and DEFAULTS[arg.key] ~= nil and type(arg.value) == type(DEFAULTS[arg.key]) then
			settings[arg.key] = arg.value
			applySetting(arg.key)
			onSettingChanged()
		end
		return
	end
	if kind == "Sound" then
		uiSound(CFG[arg] or arg)
	elseif kind == "TileSound" then
		tileSound()
	elseif kind == "ExitToMain" then
		exitToMain()
	elseif kind == "CloseEnrichment" or kind == "EnrichmentScreen" then
		if busy then return end
		busy = true
		task.spawn(function()
			local blocks = flipIn(fullRect())
			if kind == "CloseEnrichment" then
				S.enrichment = false
				player:SetAttribute("InEnrichment", false)
				menuAction:Fire("EnrichmentHide")
			else
				menuAction:Fire("EnrichmentScreen", arg)
			end
			task.wait(0.06)
			flipOut(blocks)
			busy = false
		end)
	end
end)

local friendIds
do
-- ==========================================
-- DIALOGS / PANELS
-- ==========================================

function Panels.Audio()
	return buildPanel({
		title = "Audio", cells = 7, defaults = true, minBodyCells = 4,
		rows = {
			{ kind = "slider", text = "Master Volume", key = "master", min = 0, max = 1, step = 0.05 },
			{ kind = "slider", text = "Music Volume", key = "music", min = 0, max = 1, step = 0.05 },
			{ kind = "slider", text = "Effects Volume", key = "sfx", min = 0, max = 1, step = 0.05 },
			{ kind = "choice", text = "Closed Captioning", key = "cc", options = { "None", "Subtitles (dialogue only)", "Closed Captions" } },
			{ kind = "choice", text = "Caption Size", key = "ccSize", options = { "Normal", "Large" } },
			{ kind = "choice", text = "Enable Voice", key = "voice", options = { "Enabled", "Disabled", "Push To Talk (K)" } },
		},
	})
end

function Panels.AdvancedVideo()
	return buildPanel({
		title = "Advanced Video", cells = 7, defaults = true, minBodyCells = 4,
		rows = {
			{ kind = "slider", text = "Field of View", key = "fov", min = 60, max = 100, step = 1, format = function(v) return tostring(math.floor(v + 0.5)) end },
			{ kind = "choice", text = "Show Crosshair", key = "crosshair", options = { "Enabled", "Disabled" } },
			{ kind = "choice", text = "Motion Blur", key = "motionBlur", options = { "Disabled", "Enabled" } },
			{ kind = "slider", text = "Motion Blur Amount", key = "blurStrength", min = 0, max = 1, step = 0.05 },
			{ kind = "choice", text = "Weapon Bob", key = "viewBob", options = { "Enabled", "Disabled" } },
			{ kind = "choice", text = "Toast Notifications", key = "toasts", options = { "Enabled", "Disabled" } },
		},
	})
end

function Panels.Video()
	return buildPanel({
		title = "Video", cells = 7, defaults = true, minBodyCells = 5,
		rows = {
			{ kind = "slider", text = "Brightness", key = "brightness", min = 0, max = 1, step = 0.05 },
			{ kind = "choice", text = "Aspect Ratio", key = "aspect", options = { "Native", "Widescreen 16:9", "Widescreen 16:10", "Normal 4:3" } },
			{ kind = "choice", text = "Resolution", key = "resolution", options = { "Native", "1920 x 1080", "1600 x 900", "1280 x 720", "1024 x 576" } },
			{ kind = "choice", text = "Display Mode", key = "display", options = { "Full Screen", "Windowed" } },
			{ kind = "choice", text = "Graphics Quality", key = "quality", options = { "Auto", "Low", "Medium", "High" } },
			{ kind = "choice", text = "Texture Quality", key = "textureQuality", options = { "High", "Medium", "Low", "Pixelated" } },
			{ kind = "choice", text = "Shadows", key = "shadows", options = { "Enabled", "Disabled" } },
			{ kind = "button", text = "ADVANCED VIDEO", action = function() openPanel(Panels.AdvancedVideo) end },
		},
	})
end

function Panels.KeyBinds()
	return buildPanel({
		title = "Edit Keys/Buttons", cells = 7, footer = "DONE",
		rows = {
			{ kind = "bind", text = "Fire Blue Portal", key = "bindBlue" },
			{ kind = "bind", text = "Fire Orange Portal", key = "bindOrange" },
			{ kind = "bind", text = "Reset Portals", key = "bindReset" },
			{ kind = "bind", text = "Use / Pick Up", key = "bindUse" },
			{ kind = "bind", text = "Jump", key = "bindJump" },
			{ kind = "bind", text = "Pause", key = "bindPause" },
		},
	})
end

function Panels.Keyboard()
	return buildPanel({
		title = "Keyboard/Mouse", cells = 7, minBodyCells = 4, footer = "DONE", defaults = true,
		rows = {
			{ kind = "button", text = "EDIT KEYS/BUTTONS", action = function() openPanel(Panels.KeyBinds) end },
			{ kind = "choice", text = "Reverse Mouse", key = "reverseMouse", options = { "Disabled", "Enabled" } },
			{ kind = "slider", text = "Mouse Sensitivity", key = "mouseSens", min = 0, max = 1, step = 0.01 },
			{ kind = "choice", text = "Raw Mouse Input", key = "rawMouse", options = { "Disabled", "Enabled" } },
			{ kind = "choice", text = "Mouse Acceleration", key = "mouseAccel", options = { "Disabled", "Enabled" } },
			{ kind = "slider", text = "Acceleration Amount", key = "accelAmount", min = 0, max = 1, step = 0.05 },
		},
	})
end

function Panels.Controller()
	return buildPanel({
		title = "Controller", cells = 7, footer = "DONE", minBodyCells = 3,
		rows = {
			{ kind = "info", text = "Controller", value = UserInputService.GamepadEnabled and "Connected" or "Not Detected" },
			{ kind = "info", text = "Touch Controls", value = UserInputService.TouchEnabled and "Available" or "Not Detected" },
			{ kind = "info", text = "Fire Blue / Orange", value = "LT / RT" },
			{ kind = "info", text = "Use / Pick Up", value = "X" },
			{ kind = "info", text = "Reset Portals", value = "Y" },
			{ kind = "info", text = "Pause", value = "START" },
			{ kind = "info", text = "Editor: Select / Menu", value = "A / X" },
			{ kind = "info", text = "Editor: Items / Play", value = "Y / BACK" },
		},
	})
end

-- test chamber editor settings (also reachable from the editor's pause menu)
function Panels.EditorSettings()
	local pct = function(v) return tostring(math.floor(v * 100 + 0.5)) .. "%" end
	return buildPanel({
		title = "Editor", cells = 8, defaults = true, minBodyCells = 5, maxVisible = 9, listW = 8 * CFG.GRID, noPreview = true, padTop = 30,
		rows = {
			{ kind = "choice", text = "Editor Mode", key = "edMode", options = { "Simple", "Intermediate", "Advanced" } },
			{ kind = "choice", text = "Toast Notifications", key = "toasts", options = { "Enabled", "Disabled" } },
			{ kind = "choice", text = "Tutorials", key = "tutorial", options = { "Enabled", "Disabled" } },
			{ kind = "choice", text = "Hide Items Palette", key = "edAutoHide", options = { "Enabled", "Disabled" } },
			{ kind = "slider", text = "Orbit Speed", key = "edOrbitSens", min = 0, max = 1, step = 0.05 },
			{ kind = "choice", text = "Invert Orbit", key = "edInvertY", options = { "Disabled", "Enabled" } },
			{ kind = "slider", text = "Zoom Speed", key = "edZoomSpeed", min = 0, max = 1, step = 0.05 },
			{ kind = "slider", text = "Camera Smoothing", key = "edCamSmooth", min = 0, max = 1, step = 0.05 },
			{ kind = "slider", text = "Editor Sounds", key = "edSfx", min = 0, max = 1, step = 0.05, format = pct },
			{ kind = "slider", text = "Ambient Drone", key = "edDrone", min = 0, max = 1, step = 0.05, format = pct },
			{ kind = "choice", text = "Highlight Hovered Tile", key = "edHover", options = { "Enabled", "Disabled" } },
			{ kind = "slider", text = "Controller Cursor Speed", key = "edPadCursor", min = 0, max = 1, step = 0.05 },
			{ kind = "choice", text = "Touch Toolbar", key = "edTouchBar", options = { "Auto", "Always", "Never" } },
			{ kind = "choice", text = "Team Builder Names", key = "edTeamNames", options = { "Enabled", "Disabled" } },
		},
	})
end

function Panels.Gameplay()
	return buildPanel({
		title = "Gameplay", cells = 7, defaults = true, minBodyCells = 3,
		rows = {
			{ kind = "choice", text = "Tutorials", key = "tutorial", options = { "Enabled", "Disabled" } },
			{ kind = "choice", text = "Toast Notifications", key = "toasts", options = { "Enabled", "Disabled" } },
		},
	})
end

function Panels.Options()
	return buildPanel({
		title = "OPTIONS",
		rows = {
			{ kind = "button", text = "AUDIO", action = function() openPanel(Panels.Audio) end },
			{ kind = "button", text = "VIDEO", action = function() openPanel(Panels.Video) end },
			{ kind = "button", text = "KEYBOARD/MOUSE", action = function() openPanel(Panels.Keyboard) end },
			{ kind = "button", text = "CONTROLLER", action = function() openPanel(Panels.Controller) end },
			{ kind = "button", text = "GAMEPLAY", action = function() openPanel(Panels.Gameplay) end },
			{ kind = "button", text = "EDITOR", action = function() openPanel(Panels.EditorSettings) end },
		},
	})
end

-- ----- chapters (acts) -----
local function chapterCaption(i)
	local ch = Config.Chapter(i)
	return ch and ("Chapter %d - <b>%s</b>"):format(i, ch.title) or ""
end

function Panels.NewGame()
	local rows = {}
	for i, ch in ipairs(Config.CHAPTERS) do
		local locked = i > (P.maxChapter or 1)
		table.insert(rows, {
			kind = "list", text = locked and "???" or ch.title, disabled = locked,
			preview = ch.preview, caption = chapterCaption(i),
			action = function() startGame("NewGame", i) end,
		})
	end
	return buildPanel({ title = "NEW GAME", cells = 9, listW = 4 * CFG.GRID, maxVisible = 6, minBodyCells = 4, play = "PLAY", rows = rows })
end

-- ----- saves -----
local function sortedSaves(manualOnly)
	local list = {}
	for _, s in ipairs(P.saves or {}) do
		if not (manualOnly and s.auto) then table.insert(list, s) end
	end
	table.sort(list, function(a, b) return (a.time or 0) > (b.time or 0) end)
	return list
end

local function saveRow(s, action)
	local ch = Config.Chapter(s.chapter or 1)
	return {
		kind = "list", text = stamp(s.time or os.time()), preview = ch and ch.preview or "",
		tag = s.auto and "AUTO SAVE" or nil, caption = chapterCaption(s.chapter or 1), save = s, action = action,
	}
end

function Panels.Load()
	local rows = {}
	for _, s in ipairs(sortedSaves(false)) do
		table.insert(rows, saveRow(s, function() startGame("LoadGame", s.id) end))
	end
	if #rows == 0 then table.insert(rows, { kind = "list", text = "No Saved Games", disabled = true }) end
	local panel
	panel = buildPanel({
		title = "LOAD GAME", cells = 9, listW = 4 * CFG.GRID, maxVisible = 6, minBodyCells = 4, rows = rows,
		buttons = {
			{ "LOAD", function() local it = panel.items[panel.hi] if it and it.activate then it.activate() end end },
			{ "BACK", function() goBack() end, true },
			{ "DELETE", function()
				local r = rows[panel.hi]
				if not (r and r.save) then uiSound(CFG.SOUND_INVALID) return end
				openPanel(function()
					return Panels.dialog("Delete Saved Game?", CFG.TEXT.DELETE, {
						{ "DELETE", function()
							local ok, list = Net.call("DeleteSave", r.save.id)
							if ok then P.saves = list end
							goBack()
							task.delay(0.6, function() replaceTop(Panels.Load) end)
						end },
						{ "CANCEL", function() goBack() end, true },
					}, 2)
				end)
			end },
		},
	})
	return panel
end

local function doSave(id)
	if busy then return end
	busy = true
	task.spawn(function()
		local ok, res = Net.call("SaveGame", id)
		busy = false
		if ok then
			P.saves = res
			menuAction:Fire("SaveGame", id)
			resume()
		else
			openPanel(function() return Panels.dialog("Unable To Save", tostring(res), nil, 2) end)
		end
	end)
end

function Panels.Save()
	local rows = { { kind = "list", text = "New Saved Game Slot", action = function() doSave(nil) end } }
	for _, s in ipairs(sortedSaves(true)) do
		table.insert(rows, saveRow(s, function()
			openPanel(function()
				return Panels.dialog("Overwrite Saved Game?", CFG.TEXT.OVERWRITE, {
					{ "OVERWRITE", function() doSave(s.id) end },
					{ "CANCEL", function() goBack() end, true },
				}, 2)
			end)
		end))
	end
	return buildPanel({ title = "SAVE GAME", cells = 9, listW = 4 * CFG.GRID, maxVisible = 6, minBodyCells = 4, play = "SAVE", rows = rows })
end

function Panels.Commentary()
	return Panels.dialog("Developer Commentary", CFG.TEXT.COMMENTARY, {
		{ "OK", function() startGame("DeveloperCommentary") end },
		{ "CANCEL", function() goBack() end, true },
	}, 4)
end

function Panels.SinglePlayer()
	return buildPanel({
		title = "SINGLE PLAYER",
		rows = {
			{ kind = "button", text = "CONTINUE GAME", disabled = #(P.saves or {}) == 0, action = function() startGame("ContinueGame") end },
			{ kind = "button", text = "NEW GAME", action = function() openPanel(Panels.NewGame) end },
			{ kind = "button", text = "LOAD GAME", action = function() openPanel(Panels.Load) end },
			{ kind = "button", text = "CHALLENGE MODE", action = function() openPanel(function() return Panels.Leaderboards(false, 1) end) end },
			{ kind = "button", text = "DEVELOPER COMMENTARY", action = function() openPanel(Panels.Commentary) end },
		},
	})
end

-- ----- co-op -----
local function fetchFriends()
	local list, online = {}, {}
	local ok, res = pcall(function() return player:GetFriendsOnline(200) end)
	if ok and res then
		for _, f in ipairs(res) do online[f.VisitorId] = f end
	end
	local okP, pages = pcall(function() return Players:GetFriendsAsync(player.UserId) end)
	if okP and pages then
		while true do
			for _, f in ipairs(pages:GetCurrentPage()) do
				local o = online[f.Id]
				local status = "Offline"
				if Players:GetPlayerByUserId(f.Id) then status = "In This Server"
				elseif o then status = (o.PlaceId == game.PlaceId) and "In Game" or "Online" end
				table.insert(list, { id = f.Id, name = f.DisplayName or f.Username, status = status })
			end
			if pages.IsFinished or #list >= 200 then break end
			if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
		end
	end
	local rank = { ["In This Server"] = 0, ["In Game"] = 1, Online = 2, Offline = 3 }
	table.sort(list, function(a, b)
		if rank[a.status] ~= rank[b.status] then return rank[a.status] < rank[b.status] end
		return a.name:lower() < b.name:lower()
	end)
	S.friendIds = {}
	for _, f in ipairs(list) do table.insert(S.friendIds, f.id) end
	return list
end

local function inviteFriend(f)
	if f.status == "In This Server" then
		local ok, err = Net.call("CoopInvite", f.id)
		openPanel(function()
			return Panels.dialog("Invite Sent", ok and (f.name .. " has been invited. Waiting for them to accept...") or tostring(err), nil, 2)
		end)
		return
	end
	-- not in this server: send a real Roblox game invite
	local okCan, can = pcall(function() return SocialService:CanSendGameInviteAsync(player, f.id) end)
	if okCan and can then
		pcall(function()
			local opts = Instance.new("ExperienceInviteOptions")
			opts.InviteUser = f.id
			opts.PromptMessage = "Come test with me!"
			SocialService:PromptGameInvite(player, opts)
		end)
	else
		openPanel(function() return Panels.dialog("Can't Invite", "Roblox won't let you invite " .. f.name .. " right now.", nil, 2) end)
	end
end

function Panels.Invite(list)
	local rows = {}
	for _, f in ipairs(list) do
		table.insert(rows, { kind = "friend", text = f.name, status = f.status, userId = f.id, h = 78, action = function() inviteFriend(f) end })
	end
	if #rows == 0 then table.insert(rows, { kind = "text", text = "No friends found.", color = COL.INFO_TEXT }) end
	return buildPanel({
		title = "INVITE FRIENDS", cells = 7, listW = 7 * CFG.GRID, noPreview = true, maxVisible = 7, rowH = 78,
		minBodyCells = 5, padTop = 8, rows = rows,
		buttons = {
			{ "BACK", function() goBack() end, true },
			{ "FIND A PARTNER ONLINE", function() openPanel(Panels.PlayOnline) end },
			{ "ROBOT ENRICHMENT", function() openEnrichment() end },
		},
	})
end

function Panels.SearchFriends()
	local p = Panels.spinner("Searching for Friends...", function() goBack() end)
	task.spawn(function()
		local list = fetchFriends()
		while busy do task.wait() end
		if current() == p then replaceTop(function() return Panels.Invite(list) end) end
	end)
	return p
end

function Panels.Matchmaking()
	return Panels.spinner("Searching for a partner...", function()
		task.spawn(Net.call, "CoopCancel")
		goBack()
	end)
end

function Panels.PlayOnline()
	return Panels.dialog("Play Online", CFG.TEXT.PLAY_ONLINE, {
		{ "OK", function()
			task.spawn(Net.call, "CoopQuickMatch")
			replaceTop(Panels.Matchmaking)
		end },
		{ "CANCEL", function() goBack() end, true },
	}, 2)
end

function Panels.Coop()
	return buildPanel({
		title = "CO-OP MODE",
		rows = {
			{ kind = "button", text = "ONLINE: INVITE A FRIEND", action = function() openPanel(Panels.SearchFriends) end },
			{ kind = "button", text = "ONLINE: QUICK MATCH", action = function() openPanel(Panels.PlayOnline) end },
			{ kind = "button", text = "CHALLENGE MODE CO-OP", action = function() openPanel(function() return Panels.Leaderboards(true, 1) end) end },
			{ kind = "button", text = "ROBOT ENRICHMENT", action = function() openEnrichment() end },
		},
	})
end

-- ----- leaderboards (challenge mode) -----
local function nameOf(userId)
	if S.names[userId] then return S.names[userId] end
	local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	S.names[userId] = ok and n or ("#" .. tostring(userId))
	return S.names[userId]
end

function Panels.Leaderboards(coop, courseIdx)
	local courses = {}
	for _, c in ipairs(Config.COURSES) do
		if (c.coop == true) == coop then table.insert(courses, c) end
	end
	local course = courses[courseIdx] or courses[1]
	local titles = {}
	for _, c in ipairs(courses) do table.insert(titles, c.title) end
	local rows = {
		{ kind = "cycler", text = course and course.title or "No Courses", options = titles,
			value = function() return course and course.title or "No Courses" end,
			onChange = function(v)
				local i = table.find(titles, v) or 1
				task.defer(replaceTop, function() return Panels.Leaderboards(coop, i) end)
			end },
	}
	for _, ch in ipairs(course and course.chambers or {}) do
		table.insert(rows, { kind = "list", text = ch.name, chamber = ch.id,
			action = function() startGame(coop and "CoopChallenge" or "ChallengeMode", ch.id) end })
	end
	local kind = "portals"
	local panel
	local toggleKind
	panel = buildPanel({
		title = "LEADERBOARDS", titleSize = 60, cells = 10, listW = 5 * CFG.GRID, noPreview = true, maxVisible = 7, fixedTop = 1, startHi = 2,
		minBodyCells = 5, padTop = 22, listGap = 34, rowH = 56, rows = rows,
		buttons = {
			{ "CONTINUE", function() local it = panel.items[panel.hi] if it and it.activate then it.activate() end end },
			{ "BACK", function() goBack() end, true },
			{ "PORTALS / TIME", function() if toggleKind then toggleKind() end end },
		},
		onBuilt = function(p, body)
			local x0 = 5 * CFG.GRID + 9
			local rw = body.Size.X.Offset - x0 - 3
			new("TextLabel", {
				Position = px(x0, 10), Size = px(rw, 40), BackgroundTransparency = 1, Text = "COMMUNITY STATS",
				FontFace = F_SET, TextSize = 32, TextColor3 = rgb(20), TextXAlignment = Enum.TextXAlignment.Right, Parent = body,
			})
			local hist = new("Frame", { Position = px(x0, 53), Size = px(rw, 172), BackgroundColor3 = rgb(206), BorderSizePixel = 0, Parent = body })
			local lo = new("TextLabel", { Position = px(4, 136), Size = px(80, 34), BackgroundTransparency = 1, Text = "0", FontFace = F_SET, TextSize = 28, TextColor3 = rgb(20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3, Parent = hist })
			local hi = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 136), Size = px(80, 34), BackgroundTransparency = 1, Text = "", FontFace = F_SET, TextSize = 28, TextColor3 = rgb(20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, Parent = hist })
			local barsF = {}
			for k = 1, 40 do
				barsF[k] = new("Frame", {
					AnchorPoint = Vector2.new(0, 1), Position = UDim2.new((k - 1) / 40, 0, 1, 0), Size = UDim2.new(1 / 40, 1, 0, 0),
					BackgroundColor3 = Color3.fromRGB(140, 172, 204), BorderSizePixel = 0, ZIndex = 2, Parent = hist,
				})
			end
			local toggle = new("TextButton", {
				Position = px(x0 + 52, 231), Size = px(rw - 60, 40), BackgroundTransparency = 1, Text = "", RichText = true,
				FontFace = F_TITLE, TextSize = 30, TextColor3 = rgb(20), TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, Selectable = false, Parent = body,
			})
			triangle(body, "right", 22, rgb(20)).Position = px(x0 + rw - 14, 240)
			local cards = {}
			for k = 1, 3 do
				local c = new("Frame", { Position = px(x0 + 19, 300 + (k - 1) * 86), Size = px(rw - 30, 80), BackgroundColor3 = rgb(214), BorderSizePixel = 0, Visible = false, Parent = body })
				local av = new("ImageLabel", { Position = px(6, 4), Size = px(70, 70), BackgroundColor3 = rgb(90), BorderSizePixel = 0, Parent = c })
				local nm = new("TextLabel", { Position = px(86, 0), Size = px(rw - 120, 40), BackgroundTransparency = 1, FontFace = F_SET, TextSize = 32, TextColor3 = rgb(10), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", Parent = c })
				local sc = new("TextLabel", { Position = px(86, 40), Size = px(150, 34), BackgroundTransparency = 1, FontFace = F_SET, TextSize = 28, TextColor3 = rgb(10), TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = c })
				local tg = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 42), Size = px(200, 32), BackgroundTransparency = 1, FontFace = F_TITLE, TextSize = 26, TextColor3 = rgb(10), TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = c })
				cards[k] = { frame = c, av = av, name = nm, score = sc, tag = tg }
			end
			local function fmt(v) return kind == "time" and fmtTime((v or 0) / 100) or tostring(v or 0) end
			local token = 0
			local function show(idx)
				local r = rows[idx]
				if not (r and r.chamber) then return end
				toggle.Text = kind == "portals" and "PORTALS <font color=\"#8a8a8a\" weight=\"regular\">/ TIME</font>"
					or "<font color=\"#8a8a8a\" weight=\"regular\">PORTALS /</font> TIME"
				token += 1
				local my = token
				task.spawn(function()
					local key = r.chamber .. kind
					local data = S.lb[key]
					if not data or os.clock() - data.t > 30 then
						local ok, res = Net.call("GetLeaderboard", { chamber = r.chamber, kind = kind })
						data = { t = os.clock(), res = ok and res or { top = {} } }
						S.lb[key] = data
					end
					if my ~= token or not body.Parent then return end
					local top = data.res.top or {}
					-- histogram of the top scores
					local mn, mx = math.huge, -math.huge
					for _, e in ipairs(top) do mn = math.min(mn, e.value) mx = math.max(mx, e.value) end
					local counts, peak = {}, 1
					for k = 1, 40 do counts[k] = 0 end
					if #top > 0 then
						for _, e in ipairs(top) do
							local b = math.clamp(math.floor((e.value - mn) / math.max(mx - mn, 1) * 39) + 1, 1, 40)
							counts[b] += 1
							peak = math.max(peak, counts[b])
						end
					end
					for k = 1, 40 do barsF[k].Size = UDim2.new(1 / 40, 1, counts[k] / peak * 0.95, 0) end
					lo.Text = #top > 0 and fmt(mn) or "0"
					hi.Text = #top > 0 and fmt(mx) or ""
					local entries = {}
					if top[1] then table.insert(entries, { userId = top[1].userId, value = top[1].value, tag = "Top Score" }) end
					if top[2] then table.insert(entries, { userId = top[2].userId, value = top[2].value, tag = "Score To Beat" }) end
					table.insert(entries, { userId = player.UserId, value = data.res.mine, tag = data.res.mine and "You" or "No Score" })
					for k, cd in ipairs(cards) do
						local e = entries[k]
						cd.frame.Visible = e ~= nil
						if e then
							cd.name.Text = e.userId == player.UserId and player.DisplayName or "..."
							cd.score.Text = e.value and fmt(e.value) or ""
							cd.tag.Text = e.tag
							cd.av.Image = ""
							thumbnail(e.userId, function(img) if cd.av.Parent then cd.av.Image = img end end)
							if e.userId ~= player.UserId then
								task.spawn(function()
									local n = nameOf(e.userId)
									if cd.name.Parent then cd.name.Text = n end
								end)
							end
						end
					end
				end)
			end
			toggleKind = function()
				kind = kind == "portals" and "time" or "portals"
				uiSound(CFG.SOUND_CLICK)
				show(p.hi)
			end
			toggle.MouseButton1Click:Connect(toggleKind)
			p.onHi = show
		end,
	})
	return panel
end

-- ----- community / workshop -----
local function ratingOf(m)
	local up, down = m.up or 0, m.down or 0
	return up + down, up + down > 0 and (up / (up + down)) * 5 or 0
end

local function renderChamber(vpf, data)
	vpf:ClearAllChildren()
	if type(data) ~= "table" or not data.air or #data.air == 0 then return end
	local cam = new("Camera", { FieldOfView = 40, Parent = vpf })
	vpf.CurrentCamera = cam
	local dir = Vector3.new(-0.75, 0.95, 1).Unit
	local model = Config.BuildChamber(data, vpf, Vector3.zero, { editor = true, maxFaces = 2500, cullToward = dir })
	if #model:GetChildren() == 0 then return end
	local cf, size = model:GetBoundingBox()
	local dist = size.Magnitude * 1.05 + 10
	cam.CFrame = CFrame.lookAt(cf.Position + dir * dist, cf.Position)
end

local function getMap(id, cb)
	if S.maps[id] ~= nil then cb(S.maps[id]) return end
	task.spawn(function()
		local ok, data = Net.call("WorkshopGetMap", id)
		S.maps[id] = ok and data or false
		cb(S.maps[id])
	end)
end

friendIds = function()
	if not S.friendIds then
		S.friendIds = {}
		pcall(function()
			local pages = Players:GetFriendsAsync(player.UserId)
			for _, f in ipairs(pages:GetCurrentPage()) do table.insert(S.friendIds, f.Id) end
		end)
	end
	return S.friendIds
end

-- Single Player / Cooperative Chambers screen: Quick Play, a list source you flip through (My Queue, Top Rated ...),
-- chambers with a 3D preview, author badge, ratings.
function Panels.Chambers(coop, srcIdx)
	srcIdx = srcIdx or 1
	local src = CFG.SOURCES[srcIdx]
	local ok, list = Net.call("WorkshopBrowse", { sort = src[2], coop = coop, friends = friendIds() })
	list = ok and type(list) == "table" and list or {}
	local action = coop and "CommunityCoop" or "CommunitySingle"
	local labels = {}
	for _, s in ipairs(CFG.SOURCES) do table.insert(labels, s[1]) end
	local rows = {
		{ kind = "button", glyph = "play", text = "Quick Play", h = 71, action = function()
			if list[1] then startGame(action, list[math.random(#list)].id) else uiSound(CFG.SOUND_INVALID) end
		end },
		{ kind = "cycler", text = src[1], h = 56, options = labels, value = function() return src[1] end,
		onChange = function(v)
			local i = table.find(labels, v) or 1
			task.defer(replaceTop, function() return Panels.Chambers(coop, i) end)
		end },
	}
	for _, m in ipairs(list) do
		table.insert(rows, { kind = "list", text = m.title or "Untitled", meta = m, action = function() startGame(action, m.id) end })
	end
	if #list == 0 then
		table.insert(rows, { kind = "text", text = ok and "No test chambers here yet." or "Couldn't reach the Workshop.", color = COL.DARK_TEXT })
	end
	local isQueue = src[2] == "Queue"
	local panel
	local function hiMeta()
		local r = panel and rows[panel.hi]
		return r and r.meta
	end
	panel = buildPanel({
		title = coop and "COOPERATIVE CHAMBERS" or "SINGLE PLAYER CHAMBERS", titleSize = 62, cells = 10, listW = 5 * CFG.GRID, noPreview = true,
		maxVisible = 7, fixedTop = 2, startHi = 3, minBodyCells = 5, padTop = 14, rowH = 56, dark = true, backdrop = "aperture", decor = coop and "turret" or "button",
		rows = rows,
		buttons = {
			{ "PLAY", function() local it = panel.items[panel.hi] if it and it.activate then it.activate() end end },
			{ "BACK", function() goBack() end, true },
			{ isQueue and "REMOVE" or "ADD TO QUEUE", function()
				local m = hiMeta()
				if not m then uiSound(CFG.SOUND_INVALID) return end
				local okQ, q = Net.call(isQueue and "QueueRemove" or "QueueAdd", m.id)
				if okQ then P.queue = q end
				if isQueue then replaceTop(function() return Panels.Chambers(coop, srcIdx) end) end
			end },
			{ "BROWSE THE WORKSHOP", function()
				menuAction:Fire("CommunityWorkshop")
				replaceTop(function() return Panels.Chambers(coop, 4) end)
			end },
			{ "FOLLOW AUTHOR", function()
				local m = hiMeta()
				if m then task.spawn(Net.call, "Follow", m.authorId) else uiSound(CFG.SOUND_INVALID) end
			end },
			{ "QUICK PLAY", function() if panel.items[1] then panel.items[1].activate() end end },
			{ coop and "SINGLE PLAYER" or "CO-OP", function() replaceTop(function() return Panels.Chambers(not coop, srcIdx) end) end },
		},
		onBuilt = function(p, body)
			local x0 = 5 * CFG.GRID + 33
			local vpf = new("ViewportFrame", {
				Position = px(x0, 22), Size = px(508, 285), BackgroundColor3 = rgb(214), BorderSizePixel = 0,
				Ambient = rgb(200), LightColor = rgb(255), LightDirection = Vector3.new(-1, -2, -1), Parent = body,
			})
			new("UIStroke", { Color = rgb(40), Thickness = 1, Parent = vpf })
			local by = new("TextLabel", { Position = px(x0, 321), Size = px(330, 40), BackgroundTransparency = 1, Text = "", FontFace = F_TITLE, TextSize = 32, TextColor3 = rgb(245), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = body })
			local nr = new("TextLabel", { Position = px(x0, 377), Size = px(330, 30), BackgroundTransparency = 1, Text = "", FontFace = F_SET, TextSize = 25, TextColor3 = rgb(196), TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
			local dotF = {}
			for k = 1, 5 do
				local holderDot = new("Frame", { Position = px(x0 + (k - 1) * 28, 414), Size = px(19, 19), BackgroundColor3 = rgb(110), BorderSizePixel = 0, Parent = body })
				new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = holderDot })
				local fillDot = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = COL.RATING, BorderSizePixel = 0, Parent = holderDot })
				new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fillDot })
				dotF[k] = fillDot
			end
			-- author badge
			local badge = new("Frame", { Position = px(x0 + 353, 232), Size = px(124, 192), BackgroundColor3 = rgb(230), BorderSizePixel = 0, ZIndex = 4, Visible = false, Parent = body })
			new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = badge })
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(240), rgb(176)), Parent = badge })
			new("UIStroke", { Color = rgb(120), Thickness = 1.5, Parent = badge })
			local bav = new("ImageLabel", { Position = px(8, 18), Size = px(108, 108), BackgroundColor3 = rgb(60), BorderSizePixel = 0, ZIndex = 5, Parent = badge })
			new("TextLabel", { Position = px(8, 150), Size = px(108, 24), BackgroundTransparency = 1, Text = "APERTURE", FontFace = F_TITLE, TextSize = 20, TextColor3 = rgb(90), ZIndex = 5, Parent = badge })
			local token = 0
			p.onHi = function(idx)
				local r = rows[idx]
				local m = r and r.meta
				if not m then return end
				token += 1
				local my = token
				by.Text = "by " .. tostring(m.author or "?")
				local n, score = ratingOf(m)
				nr.Text = n .. " rating(s)"
				for k = 1, 5 do dotF[k].Size = UDim2.fromScale(math.clamp(score - (k - 1), 0, 1), 1) end
				badge.Visible = true
				bav.Image = ""
				thumbnail(m.authorId, function(img) if my == token and bav.Parent then bav.Image = img end end)
				vpf:ClearAllChildren()
				getMap(m.id, function(data)
					if my == token and vpf.Parent then renderChamber(vpf, data) end
				end)
			end
		end,
	})
	return panel
end

function Panels.MyWorkshop()
	local ok, list = Net.call("WorkshopBrowse", { sort = "Mine" })
	list = ok and type(list) == "table" and list or {}
	local rows = {}
	for _, m in ipairs(list) do
		local n, score = ratingOf(m)
		table.insert(rows, {
			kind = "list", text = m.title or "Untitled", previewColor = rgb(214),
			caption = ("<b>%s</b>\n%s  -  %d plays  -  %d rating(s), %.1f / 5"):format(m.title or "", m.coop and "Co-op" or "Single Player", m.plays or 0, n, score),
			action = function() startGame(m.coop and "CommunityCoop" or "CommunitySingle", m.id) end,
		})
	end
	if #rows == 0 then table.insert(rows, { kind = "list", text = "Nothing published yet", disabled = true }) end
	return buildPanel({
		title = "MY WORKSHOP", cells = 10, listW = 5 * CFG.GRID, maxVisible = 7, minBodyCells = 5, previewH = 285,
		captionH = 120, dark = true, backdrop = "aperture", play = "PLAY", rows = rows,
	})
end

function Panels.Community()
	return buildPanel({
		title = "WELCOME", subtitle = "Employee #" .. tostring(player.UserId),
		cells = 10, minBodyCells = 5, rowW = 6 * CFG.GRID, padTop = 70, titleSize = 62,
		dark = true, backdrop = "aperture", decor = "turret", card = true,
		rows = {
			{ kind = "button", text = "Play Community Test Chambers", size = 34, action = function() openPanel(function() return Panels.Chambers(false, 1) end) end },
			{ kind = "button", text = "Create Test Chambers", size = 34, action = function() openPanel(function() return Panels.MyChambers(1) end) end },
			{ kind = "button", text = "View My Workshop", size = 34, action = function() openPanel(Panels.MyWorkshop) end },
		},
	})
end

-- ----- my test chambers (Create Test Chambers) -----
local CHAMBER_SORTS = { "By status", "By name", "By date" }
function Panels.MyChambers(sortIdx)
	sortIdx = sortIdx or 1
	S.drafts = {} -- previews may have changed since last time
	local ok, list = Net.call("EditorList")
	list = ok and type(list) == "table" and list or {}
	table.sort(list, function(a, b)
		if sortIdx == 1 and (a.publishedId ~= nil) ~= (b.publishedId ~= nil) then return a.publishedId == nil end
		if sortIdx == 2 then return (a.title or ""):lower() < (b.title or ""):lower() end
		return (a.modified or 0) > (b.modified or 0)
	end)
	local rows = {
		{ kind = "cycler", oneArrow = true, h = 56, text = CHAMBER_SORTS[sortIdx], options = CHAMBER_SORTS,
			value = function() return CHAMBER_SORTS[sortIdx] end,
			onChange = function(v)
				local i = table.find(CHAMBER_SORTS, v) or 1
				task.defer(replaceTop, function() return Panels.MyChambers(i) end)
			end },
		{ kind = "list", text = "New Test Chamber...", isNew = true, action = function() startGame("CommunityCreate") end },
	}
	for _, d in ipairs(list) do
		table.insert(rows, { kind = "list", text = d.title or "Untitled Chamber", right = d.publishedId and "Published" or "Local", draft = d,
			action = function() startGame("CommunityCreate", d.id) end })
	end
	return buildPanel({
		title = "MY TEST CHAMBERS", titleSize = 62, cells = 10, listW = 5 * CFG.GRID, noPreview = true, maxVisible = 7,
		fixedTop = 1, startHi = 2, padTop = 20, listGap = 38, rowH = 56, minBodyCells = 5, dark = true, backdrop = "aperture",
		rows = rows,
		buttons = {
			{ "NEW", function() startGame("CommunityCreate") end },
			{ "BACK", function() goBack() end, true },
		},
		onBuilt = function(p, body)
			local x0 = 593
			local vpf = new("ViewportFrame", {
				Position = px(x0, 40), Size = px(528, 295), BackgroundColor3 = rgb(214, 221, 217), BorderSizePixel = 0,
				Ambient = rgb(170), LightColor = rgb(255), LightDirection = Vector3.new(0.4, -1, -0.6), Parent = body,
			})
			local name = new("TextLabel", { Position = px(x0, 352), Size = px(528, 42), BackgroundTransparency = 1, Text = "", FontFace = F_TITLE, TextSize = 34, TextColor3 = rgb(236), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = body })
			local values = {}
			for k, lbl in ipairs({ "Rating", "Created", "Last Modified", "Last Published" }) do
				local y = 412 + (k - 1) * 34
				new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = px(826, y), Size = px(220, 32), BackgroundTransparency = 1, Text = lbl, FontFace = F_SET, TextSize = 26, TextColor3 = rgb(196), TextXAlignment = Enum.TextXAlignment.Right, Parent = body })
				values[k] = new("TextLabel", { Position = px(846, y), Size = px(270, 32), BackgroundTransparency = 1, Text = "", FontFace = F_SET, TextSize = 26, TextColor3 = rgb(220), TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
			end
			local dotF = {}
			for k = 1, 5 do
				local hd = new("Frame", { Position = px(848 + (k - 1) * 28, 418), Size = px(19, 19), BackgroundColor3 = rgb(104, 108, 110), BorderSizePixel = 0, Parent = body })
				new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hd })
				dotF[k] = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = COL.RATING, BorderSizePixel = 0, Parent = hd })
				new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dotF[k] })
			end
			local function date(t) return t and os.date("%b %d, %Y", t) or "" end
			local token = 0
			S.drafts = S.drafts or {}
			p.onHi = function(idx)
				local r = rows[idx]
				if not r or r.kind ~= "list" then return end
				token += 1
				local my = token
				vpf:ClearAllChildren()
				for _, d in ipairs(dotF) do d.Size = UDim2.fromScale(0, 1) end
				if r.isNew then
					name.Text = "New Test Chamber..."
					for k = 2, 4 do values[k].Text = "" end
					renderChamber(vpf, Config.DefaultChamber())
					return
				end
				local d = r.draft
				name.Text = d.title or ""
				values[2].Text, values[3].Text, values[4].Text = date(d.created), date(d.modified), d.publishedAt and date(d.publishedAt) or "Never"
				local n = (d.up or 0) + (d.down or 0)
				local score = n > 0 and (d.up or 0) / n * 5 or 0
				for k = 1, 5 do dotF[k].Size = UDim2.fromScale(math.clamp(score - (k - 1), 0, 1), 1) end
				task.spawn(function()
					local data = S.drafts[d.id]
					if data == nil then
						local okG, res = Net.call("EditorGet", d.id)
						data = okG and res or false
						S.drafts[d.id] = data
					end
					if my == token and vpf.Parent and data then renderChamber(vpf, data) end
				end)
			end
		end,
	})
end

-- ----- achievements -----
function Panels.Achievements()
	local rows = {}
	local got = 0
	for _, a in ipairs(Config.ACHIEVEMENTS) do
		local when = P.achievements and P.achievements[a.id]
		if when then got += 1 end
		local secret = a.hidden and not when
		local status
		if when then
			status = "Unlocked " .. os.date("%b %d, %Y", when)
		elseif a.goal then
			status = ("%d / %d"):format(math.min((P.progress and P.progress[a.id]) or 0, a.goal), a.goal)
		else
			status = "Locked"
		end
		table.insert(rows, {
			kind = "list", text = secret and "???" or a.name, color = not when and COL.DISABLED or nil,
			preview = a.icon, previewColor = when and rgb(255) or rgb(70), previewFit = true,
			caption = ("<b>%s</b>\n%s\n<font color=\"#666666\">%s</font>"):format(secret and "Hidden Achievement" or a.name, secret and "Keep testing to find out." or a.desc, status),
		})
	end
	return buildPanel({
		title = ("ACHIEVEMENTS  %d/%d"):format(got, #Config.ACHIEVEMENTS), cells = 9, listW = 5 * CFG.GRID,
		maxVisible = 7, minBodyCells = 5, previewW = 240, previewH = 240, previewFit = true, captionH = 160, rows = rows,
	})
end

function Panels.Extras()
	local rows = { { kind = "list", text = "Achievements", caption = "Your achievements", action = function() openPanel(Panels.Achievements) end } }
	for _, e in ipairs(CFG.EXTRAS) do
		table.insert(rows, { kind = "list", text = e[1], caption = e[1], preview = e[3], action = function() menuAction:Fire(e[2]) end })
	end
	return buildPanel({ title = "EXTRAS", cells = 9, listW = 4 * CFG.GRID, maxVisible = 6, minBodyCells = 4, play = "PLAY", rows = rows })
end

function Panels.Quit()
	return Panels.dialog("Quit", CFG.TEXT.QUIT, {
		{ "QUIT GAME", function() player:Kick("Thank you for participating in this Aperture Science computer-aided enrichment activity.") end },
		{ "CANCEL", function() goBack() end, true },
	}, 1)
end

function Panels.Exit()
	return Panels.dialog("Exit To Main Menu?", CFG.TEXT.EXIT, {
		{ "EXIT", function() exitToMain() end },
		{ "CANCEL", function() goBack() end, true },
	}, 3)
end

local function editorRequest(kind)
	local g = playerGui:FindFirstChild("PortalEditor")
	local e = g and g:FindFirstChild("EditorRequest")
	if e then e:Fire(kind) end
end

-- resume, then tell the editor to do something once the menu is gone
local function resumeThen(kind)
	resume()
	task.delay(0.35, editorRequest, kind)
end

local function isTeamGuest()
	local host = player:GetAttribute("EditorTeam")
	return host ~= nil and host ~= player.UserId
end

function Panels.Pause()
	local rows
	if player:GetAttribute("EditorPlaytest") then
		rows = {
			{ kind = "button", text = "RETURN TO GAME", action = function() resume() end },
			{ kind = "button", text = "RESTART LEVEL", action = function() resumeThen("Restart") end },
			{ kind = "button", text = "REBUILD...", action = function() resumeThen("Rebuild") end },
			{ kind = "button", text = "OPTIONS", action = function() openPanel(Panels.Options) end },
			{ kind = "button", text = "EDITOR SETTINGS", action = function() openPanel(Panels.EditorSettings) end },
			{ kind = "button", text = "EXIT TO EDITOR", action = function() resumeThen("ExitToEditor") end },
		}
	elseif player:GetAttribute("InEditor") then
		rows = {
			{ kind = "button", text = "RETURN TO EDITOR", action = function() resume() end },
			{ kind = "button", text = "BUILD AND PLAY", action = function() resumeThen("Rebuild") end },
			{ kind = "button", text = "SAVE", action = function() editorRequest("Save") resume() end },
			{ kind = "button", text = isTeamGuest() and "LEAVE TEAM" or "INVITE TEAM BUILDER", action = function()
				if isTeamGuest() then openPanel(Panels.Exit) else resumeThen("Invite") end
			end },
			{ kind = "button", text = "OPTIONS", action = function() openPanel(Panels.Options) end },
			{ kind = "button", text = "EDITOR SETTINGS", action = function() openPanel(Panels.EditorSettings) end },
			{ kind = "button", text = "EXIT TO MAIN MENU", action = function() editorRequest("Save") openPanel(Panels.Exit) end },
		}
	else
		rows = {
			{ kind = "button", text = "RETURN TO GAME", action = function() resume() end },
			{ kind = "button", text = "SAVE GAME", disabled = player:GetAttribute("Chapter") == nil, action = function() openPanel(Panels.Save) end },
			{ kind = "button", text = "LOAD GAME", action = function() openPanel(Panels.Load) end },
			{ kind = "button", text = "LOAD LAST SAVE", disabled = #(P.saves or {}) == 0, action = function()
				menuAction:Fire("LoadLastSave")
				startGame("LoadLastSave")
			end },
			{ kind = "button", text = "OPTIONS", action = function() openPanel(Panels.Options) end },
			{ kind = "button", text = "EXIT TO MAIN MENU", action = function() openPanel(Panels.Exit) end },
		}
	end
	for _, r in ipairs(rows) do r.size = 32 end
	return buildPanel({ footer = "DONE", glass = true, minBodyCells = 4, padTop = 52, onBack = function() resume() end, rows = rows })
end

openPause = function(firstBuilder)
	if mode ~= "none" or busy or loadingNow then return end
	setMode("pause")
	backdrop.Visible = false
	vignette.Visible = true
	vignette.BackgroundTransparency = 0.25
	mainHolder.Visible = false
	setEffects("pause")
	setMenuOpen(true)
	openPanel(firstBuilder or Panels.Pause)
end

end
do
-- ==========================================
-- TOUCH: on-screen pause button
-- ==========================================

local touchPauseGui = new("ScreenGui", { Name = "PortalTouchPause", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50, Enabled = false, Parent = playerGui })
local touchPauseBtn = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(52, 52),
	BackgroundColor3 = rgb(0), BackgroundTransparency = 0.45, Text = "II", TextColor3 = rgb(255),
	TextSize = 24, Font = Enum.Font.GothamBold, AutoButtonColor = true, Selectable = false, Parent = touchPauseGui,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = touchPauseBtn })
new("UIStroke", { Color = rgb(255), Transparency = 0.6, Thickness = 2, Parent = touchPauseBtn })
touchPauseBtn.MouseButton1Click:Connect(function()
	if mode == "none" and not loadingNow and not busy then openPause() end
end)
refreshTouchPause = function()
	touchPauseGui.Enabled = UserInputService.TouchEnabled and mode == "none" and not loadingNow
	-- in the editor the toolbar lives at the top centre: move out of its way (top right)
	local editing = player:GetAttribute("InEditor") and not player:GetAttribute("EditorPlaytest")
	touchPauseBtn.Position = editing and UDim2.new(1, -46, 0, 70) or UDim2.new(0.5, 0, 0, 10)
end
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refreshTouchPause)
player:GetAttributeChangedSignal("InEditor"):Connect(refreshTouchPause)
player:GetAttributeChangedSignal("EditorPlaytest"):Connect(refreshTouchPause)
refreshTouchPause()

end
-- ==========================================
-- BUILD MAIN LIST
-- ==========================================

local MAIN_ITEMS = {
	{ "PLAY SINGLE PLAYER", function() openPanel(Panels.SinglePlayer) end },
	{ "PLAY COOPERATIVE GAME", function() openPanel(Panels.Coop) end },
	{ "COMMUNITY TEST CHAMBERS", function() openPanel(Panels.Community) end },
	{ "OPTIONS", function() openPanel(Panels.Options) end },
	{ "EXTRAS", function() openPanel(Panels.Extras) end },
	{ "QUIT", function() openPanel(Panels.Quit) end },
}

for i, def in ipairs(MAIN_ITEMS) do
	local b = new("TextButton", {
		Position = px(0, (i - 1) * CFG.MAIN_STEP), Size = px(630, 56), BackgroundColor3 = COL.MAIN_HI_BG,
		BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = def[1],
		FontFace = F_MAIN, TextSize = 37, TextColor3 = COL.MAIN_TEXT, TextXAlignment = Enum.TextXAlignment.Left, Selectable = false, Parent = mainHolder,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 24), Parent = b })
	mainButtons[i] = b
	b.MouseEnter:Connect(function()
		if not busy and current() == nil then setMainHi(i) end
	end)
	b.MouseButton1Click:Connect(function()
		if busy or current() ~= nil then return end
		setMainHi(i, true)
		uiSound(CFG.SOUND_CLICK)
		def[2]()
	end)
end

-- "Robot Enrichment" link: white atom; on hover the orbits brighten and glowing cyan electrons race around them
do
	local re = new("TextButton", {
		Position = px(24, 6 * CFG.MAIN_STEP + 6), Size = px(360, 44), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Selectable = false, Parent = mainHolder,
	})
	local A, Bax = 17, 6.5 -- orbit ellipse radii
	local atom = new("Frame", { Position = px(0, 5), Size = px(34, 34), BackgroundTransparency = 1, Parent = re })
	local strokes, electrons = {}, {}
	for k = 0, 2 do
		local o = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = px(A * 2, Bax * 2),
			Rotation = k * 60, BackgroundTransparency = 1, Parent = atom,
		})
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = o })
		strokes[k + 1] = new("UIStroke", { Color = COL.MAIN_TEXT, Thickness = 1.6, Parent = o })
		local trail = {}
		for j = 1, 6 do
			local s = 7 - (j - 1) * 0.8
			local d = blob(atom, 17, 17, s, s, 0, Color3.fromRGB(110, 215, 255), UDim.new(1, 0), 6)
			d.BackgroundTransparency = (j - 1) * 0.15
			d.Visible = false
			trail[j] = d
		end
		local glow = blob(atom, 17, 17, 16, 16, 0, COL.CYAN, UDim.new(1, 0), 5)
		glow.BackgroundTransparency = 0.6
		glow.Visible = false
		electrons[k + 1] = { trail = trail, glow = glow, phase = k * 2.09 + k * 0.7, rot = math.rad(k * 60), speed = 5.2 + k * 0.35 }
	end
	local core = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = px(6, 6),
		BackgroundColor3 = COL.MAIN_TEXT, BorderSizePixel = 0, ZIndex = 4, Parent = atom,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = core })
	local lbl = new("TextLabel", {
		Position = px(46, 0), Size = px(310, 44), BackgroundTransparency = 1, Text = "Robot Enrichment",
		FontFace = F_SET, TextSize = 29, TextColor3 = COL.MAIN_TEXT, TextXAlignment = Enum.TextXAlignment.Left, Parent = re,
	})
	local t, conn = 0, nil
	local function place(e)
		for j, d in ipairs(e.trail) do
			local ang = t * e.speed + e.phase - (j - 1) * 0.17
			local x, y = A * math.cos(ang), Bax * math.sin(ang)
			local cr, sr = math.cos(e.rot), math.sin(e.rot)
			d.Position = px(17 + x * cr - y * sr, 17 + x * sr + y * cr)
			if j == 1 then e.glow.Position = d.Position end
		end
	end
	local function setHover(on)
		lbl.TextColor3 = on and rgb(255) or COL.MAIN_TEXT
		core.BackgroundColor3 = on and rgb(255) or COL.MAIN_TEXT
		for _, s in ipairs(strokes) do s.Color = on and rgb(240) or COL.MAIN_TEXT end
		for _, e in ipairs(electrons) do
			e.glow.Visible = on
			for _, d in ipairs(e.trail) do d.Visible = on end
		end
		if on and not conn then
			conn = RunService.RenderStepped:Connect(function(dt)
				t += dt
				for _, e in ipairs(electrons) do place(e) end
			end)
		elseif not on and conn then
			conn:Disconnect()
			conn = nil
		end
	end
	re.MouseEnter:Connect(function()
		if busy or current() ~= nil then return end
		setHover(true)
		uiSound(CFG.SOUND_HOVER)
	end)
	re.MouseLeave:Connect(function() setHover(false) end)
	re.MouseButton1Click:Connect(function()
		if busy or current() ~= nil then return end
		uiSound(CFG.SOUND_CLICK)
		setHover(false)
		openEnrichment()
	end)
end

do
-- ==========================================
-- INPUT
-- ==========================================

local function inputToBind(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then return "MouseButton1" end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then return "MouseButton2" end
	if input.UserInputType == Enum.UserInputType.MouseButton3 then return "MouseButton3" end
	if input.KeyCode ~= Enum.KeyCode.Unknown then return input.KeyCode.Name end
	return nil
end

local function handleBindInput(input)
	local p = current()
	if not p or not p.waitingBind or mode == "none" then return false end
	local idx = p.waitingBind
	local it = p.items[idx]
	local row = p.def.rows[idx]
	if input.KeyCode == Enum.KeyCode.Escape then
		p.waitingBind = nil
		it.refresh(it.hiNow)
		return true
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then return false end
	local bind = inputToBind(input)
	if not bind or not row or not row.key then return true end
	settings[row.key] = bind
	player:SetAttribute("Setting_" .. row.key, bind)
	if row.key == "bindJump" then applyJumpBinding() end
	onSettingChanged()
	p.waitingBind = nil
	uiSound(CFG.SOUND_CLICK)
	for _, x in ipairs(p.items) do x.refresh(x.hiNow) end
	return true
end

local function handleNav(kind)
	if mode == "none" or busy or S.enrichment then return end
	local p = current()
	if kind == "back" then
		if p then
			uiSound(CFG.SOUND_BACK)
			local backBtn
			for _, bt in ipairs(p.buttons or {}) do if bt[3] then backBtn = bt end end
			if backBtn then backBtn[2]()
			elseif p.def.onBack then p.def.onBack()
			else goBack() end
		end
		return
	end
	if p then
		if kind == "up" then moveHi(p, -1)
		elseif kind == "down" then moveHi(p, 1)
		else
			local it = p.items[p.hi]
			if not it then
				-- dialogs with no selectable rows: Enter / A = first footer button
				if kind == "ok" and p.buttons and p.buttons[1] then
					uiSound(CFG.SOUND_CLICK)
					p.buttons[1][2]()
				end
				return
			end
			if kind == "ok" and it.activate then it.activate()
			elseif kind == "left" and it.left then it.left()
			elseif kind == "right" and it.right then it.right() end
		end
	elseif mode == "main" then
		if kind == "up" then setMainHi(((mainHi - 2) % #mainButtons) + 1)
		elseif kind == "down" then setMainHi((mainHi % #mainButtons) + 1)
		elseif kind == "ok" and MAIN_ITEMS[mainHi] then
			uiSound(CFG.SOUND_CLICK)
			MAIN_ITEMS[mainHi][2]()
		end
	end
end

local NAV_KEYS = {
	[Enum.KeyCode.Up] = "up", [Enum.KeyCode.DPadUp] = "up", [Enum.KeyCode.W] = "up",
	[Enum.KeyCode.Down] = "down", [Enum.KeyCode.DPadDown] = "down", [Enum.KeyCode.S] = "down",
	[Enum.KeyCode.Left] = "left", [Enum.KeyCode.DPadLeft] = "left", [Enum.KeyCode.A] = "left",
	[Enum.KeyCode.Right] = "right", [Enum.KeyCode.DPadRight] = "right", [Enum.KeyCode.D] = "right",
	[Enum.KeyCode.Return] = "ok", [Enum.KeyCode.KeypadEnter] = "ok", [Enum.KeyCode.ButtonA] = "ok",
	[Enum.KeyCode.Backspace] = "back", [Enum.KeyCode.ButtonB] = "back",
}
-- the footer buttons a controller can press directly (glyph shown on each button)
local PAD_SHORTCUTS = {
	[Enum.KeyCode.ButtonX] = "X", [Enum.KeyCode.ButtonY] = "Y", [Enum.KeyCode.ButtonL1] = "LB", [Enum.KeyCode.ButtonR1] = "RB",
}

local function togglePause()
	if S.enrichment then return end
	if mode == "none" and not loadingNow then
		openPause()
	elseif mode == "pause" and not busy then
		if #stack > 1 then goBack() else resume() end
	end
end

UserInputService.InputBegan:Connect(function(input)
	if UserInputService:GetFocusedTextBox() then return end
	if handleBindInput(input) then return end
	local kc = input.KeyCode
	-- Start always pauses on a controller, whatever the keyboard pause key is bound to
	if kc == Enum.KeyCode.ButtonStart or inputToBind(input) == settings.bindPause
		or (CFG.PAUSE_KEYS[kc] and settings.bindPause == "Backquote") then
		togglePause()
		return
	end
	local nav = NAV_KEYS[kc]
	if nav then handleNav(nav) return end
	local g = PAD_SHORTCUTS[kc]
	if g and mode ~= "none" and not busy and not S.enrichment then
		local p = current()
		local fn = p and p.padMap and p.padMap[g]
		if fn then
			uiSound(CFG.SOUND_CLICK)
			fn()
		end
	end
end)

local stickNext = 0
UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.Thumbstick1 or mode == "none" then return end
	local now = os.clock()
	if now < stickNext then return end
	local p = input.Position
	local kind
	if p.Y > 0.6 then kind = "up"
	elseif p.Y < -0.6 then kind = "down"
	elseif p.X < -0.6 then kind = "left"
	elseif p.X > 0.6 then kind = "right" end
	if kind then
		stickNext = now + 0.22
		handleNav(kind)
	end
end)

player.CharacterAdded:Connect(function()
	if (mode ~= "none" or loadingNow) and controls then
		task.defer(function() controls:Disable() end)
	end
end)

end
-- ==========================================
-- SERVER PUSHES
-- ==========================================

local Push = {}
function Push.Achievement(d)
	P.achievements[d.id] = os.time()
end
function Push.ChapterUnlocked(d)
	local new = (d.maxChapter or 1) > (P.maxChapter or 1)
	P.maxChapter = d.maxChapter
	local ch = new and Config.Chapter(d.maxChapter)
	if ch then toast(("Chapter %d: %s"):format(d.maxChapter, ch.title), "Chapter unlocked", "good") end
end
function Push.Toast(d) toast(d.text, d.title, d.kind) end
function Push.Inventory(d) P.inventory = d.inventory end
function Push.LoadChapter(d) startGame("NewGame", d.chapter) end
function Push.SkipMenu() if mode ~= "none" then closeAll() end end
function Push.Autosaved()
	toast("Your progress was saved.", "Autosave", "info")
	task.spawn(function()
		local ok, prof = Net.call("GetProfile")
		if ok then P.saves = prof.saves end
	end)
end
function Push.CoopInvite(d)
	showAnywhere(function()
		return Panels.dialog("Co-op Invite", d.name .. " wants you to join them in co-op. Play together?", {
			{ "ACCEPT", function()
				goBack()
				task.spawn(Net.call, "CoopRespond", { from = d.from, accept = true })
			end },
			{ "DECLINE", function()
				task.spawn(Net.call, "CoopRespond", { from = d.from, accept = false })
				goBack()
			end, true },
		}, 2)
	end)
end
function Push.CoopDeclined(d)
	showAnywhere(function() return Panels.dialog("Invite Declined", d.name .. " can't play right now.", nil, 1) end)
end
function Push.CoopEnded(d)
	showAnywhere(function() return Panels.dialog("Partner Left", d.partner .. " has left the game.", nil, 1) end)
end
-- team building: someone wants help with their test chamber (the editor itself shows declines / team changes)
function Push.TeamInvite(d)
	showAnywhere(function()
		return Panels.dialog("Team Building", d.name .. " wants you to help build their test chamber. Join them in the editor?", {
			{ "JOIN", function()
				goBack()
				task.spawn(function()
					local t0 = os.clock()
					while busy and os.clock() - t0 < 3 do task.wait() end
					startGame("TeamRespond", { from = d.from, accept = true })
				end)
			end },
			{ "DECLINE", function()
				task.spawn(Net.call, "TeamRespond", { from = d.from, accept = false })
				goBack()
			end, true },
		}, 2)
	end)
end
function Push.CoopStart(d)
	if d.partner then toast(("Playing with %s (you're %s)."):format(tostring(d.partner), tostring(d.color or "")), "Co-op", "good") end
	task.spawn(function()
		local t0 = os.clock()
		while busy and os.clock() - t0 < 5 do task.wait() end
		busy = true
		runLoading(function()
			task.wait(2.2) -- the server loads the co-op hub
			closeAll()
		end, 2.5)
		busy = false
	end)
end
function Push.ChamberComplete(d)
	if d.editor then return end -- the editor shows its own message
	toast(("Solved in %s."):format(fmtTime(d.time)), "Chamber complete", "good")
	if d.mapId then
		showAnywhere(function()
			return Panels.dialog("Chamber Complete", ("Solved in %s. What did you think of this test chamber?"):format(fmtTime(d.time)), {
				{ "RATE UP", function() task.spawn(Net.call, "WorkshopRate", { id = d.mapId, up = true }) exitToMain() end },
				{ "RATE DOWN", function() task.spawn(Net.call, "WorkshopRate", { id = d.mapId, up = false }) exitToMain() end },
				{ "KEEP PLAYING", function() resume() end, true },
			}, 2)
		end)
	elseif d.chamber then
		showAnywhere(function()
			return Panels.dialog("Challenge Complete", ("Portals: %d    Time: %s"):format(d.portals or 0, fmtTime(d.time)), {
				{ "RESTART", function() startGame(player:GetAttribute("CoopPartner") and "CoopChallenge" or "ChallengeMode", d.chamber) end },
				{ "EXIT", function() exitToMain() end },
				{ "CONTINUE", function() resume() end, true },
			}, 1)
		end)
	end
end
function Push.GameFinished()
	showAnywhere(function() return Panels.dialog("Testing Complete", "You've finished every chapter. Thanks for playing!", { { "MAIN MENU", function() exitToMain() end } }, 1) end)
end

task.spawn(function()
	local f = Net.folder()
	if not f then return end
	f:WaitForChild("Push").OnClientEvent:Connect(function(kind, data)
		local fn = Push[kind]
		if fn then task.spawn(fn, data or {}) end
	end)
end)

-- ==========================================
-- START: boot loading screen -> main menu
-- ==========================================

publishMode()
applyJumpBinding()
task.defer(function()
	busy = true
	if CFG.SHOW_MAIN_MENU_ON_JOIN then
		setMode("main")
		setMenuOpen(true)
	end
	-- preload menu art and grab the profile while the loading screen is up
	local list = {}
	for _, id in ipairs({ CFG.LOADING_LOGO, CFG.MENU_BACKGROUND_IMAGE, CFG.LOGO_IMAGE, CFG.SOUND_HOVER, CFG.SOUND_CLICK, CFG.SOUND_BACK, CFG.SOUND_BARCHANGE }) do
		if id ~= "" and id ~= "rbxassetid://" then table.insert(list, id) end
	end
	for _, id in ipairs(CFG.SOUND_ROLLOVER) do table.insert(list, id) end
	for _, ch in ipairs(Config.CHAPTERS) do
		if ch.preview ~= "" then table.insert(list, ch.preview) end
		if ch.background and ch.background ~= "" then table.insert(list, ch.background) end
	end
	local loaded, profileDone = 0, false
	runLoading(function()
		task.spawn(function()
			local ok, prof = Net.call("GetProfile")
			if ok and type(prof) == "table" then
				for k, v in pairs(prof) do P[k] = v end
				loadSettingsFromProfile()
			else
				warn("[PortalMenu] profile:", prof)
			end
			profileDone = true
		end)
		pcall(function()
			ContentProvider:PreloadAsync(list, function() loaded += 1 end)
		end)
		local t0 = os.clock()
		while not profileDone and os.clock() - t0 < 20 do task.wait() end
	end, CFG.BOOT_LOADING_TIME, function()
		return (#list > 0 and loaded / #list or 1) * 0.6 + (profileDone and 0.4 or 0)
	end, true)
	busy = false
	if CFG.SHOW_MAIN_MENU_ON_JOIN then
		openMain()
	else
		closeAll()
	end
end)
