-- PortalMapEditor
-- StarterPlayerScripts (LocalScript)
-- Test chamber editor modelled on Portal 2's Puzzle Maker.
-- The chamber is carved out of solid space: select wall panels and push / pull them, drag items from the
-- Items palette onto the floor, connect buttons to test elements, build and play it, rebuild with F9 while testing.
--
-- UI (measured from Puzzle Maker footage, laid out on a 1918 x 1072 reference canvas and scaled to the screen):
--   * frame chrome (border, File / Edit / Help, play / undo / redo / eye) fades in when the pointer nears an edge,
--     goes over the UI, or while zooming, and fades out while you work on the chamber
--   * Items palette slides out when the pointer touches the left strip, slides away when you move into the room
--   * zoom bar on the right shows while zooming
--   * see-through context menus with the cyan highlight
--   * connecting: a 2D elbow line from the item to the pointer that snaps onto anything it can connect to
--   * the room is real 3D (client-only, far above the map, inside a plain grey box), not a ViewportFrame, so it's drawn
--     at full resolution with real lighting and shadows. Your Lighting is swapped for clean editor lighting while you
--     edit (post effects like blur / depth of field off) and put back when you test or leave.
--
-- Mouse + keyboard
--   LMB on a panel        select it (drag across a wall = area)
--   Shift + LMB           select every panel between your last click and this one (added to the selection)
--   Ctrl + LMB            add / remove a single panel          Ctrl+A   select all
--   + / -                 pull / push the selected panels      P   toggle portalable      T   paint with the last colour
--   MMB drag              orbit (smooth)                       Shift + MMB drag / RMB drag   pan
--   RMB click             context menu (surface or item)       Wheel   zoom      WASD / Q E   move the camera
--   Drag from Items       place an item          LMB drag an item   move it          R   rotate     Del   delete
--   C                     connect the selected item to another item (click the other one, Esc cancels)
--   Faith plate           drag its yellow ball onto a panel to aim it, then up / down for the arc height
--   Ctrl+Z / Ctrl+Y undo / redo   Ctrl+S save   Ctrl+Shift+S save as   Ctrl+N new   Ctrl+O open   Ctrl+Q exit
--   Tab                   game view          F9   build and play / rebuild while testing
--
-- Controller (a cursor you steer with the left stick; menus and the palette also work with the D-pad)
--   Left stick  cursor        Right stick  orbit        LT + sticks  move the camera        LB / RB  zoom out / in
--   A  click / drag (hold)    X  context menu           Y  Items palette                    B  cancel / close / deselect
--   D-pad up / down  pull / push       D-pad left  rotate item       D-pad right  portalable
--   L3  connect      R3  game view      Back / View  build and play      Start  pause menu (editor settings live there)
--
-- Touch
--   Tap a panel / item to select, drag across a wall to select an area, drag an item to move it
--   One finger on empty space orbits, two fingers pan and pinch zoom, long-press opens the context menu
--   The toolbar along the bottom has pull / push / portal / paint / rotate / connect / delete / options / play
--
-- Team building: File > Invite team builder (or the pause menu). Everyone edits the same chamber; teammates show up
-- as coloured circles with their name, which change shade with what they're pointing at so they stay readable on
-- white tiles, black tiles, items or the grey void. Build and Play takes the whole team in.
--
-- Editor modes (Options > Editor > Editor Mode, or File > Editor mode):
--   Simple        the Items palette (the classic editor)
--   Intermediate  + Textures tab (search / asset id, put textures on the selected surfaces)
--                 + Meshes tab (search / mesh id, drag decoration meshes in; right-click > Size)
--   Advanced      + My Chips tab (little programs, built from blocks or typed as lines), item labels, mesh nudging,
--                 a coordinates readout under the pointer
--
-- The exit door is locked until something opens it: connect a button (etc.) to it, open it with a chip, or right-click
-- it > Open without a button. Build and Play warns you, Publish refuses a chamber nobody can finish.
--
-- Connections: buttons, pedestals, laser catchers and logic gates can drive things. An item with several inputs
-- needs ALL of them on (Portal 2). Logic gates (AND / OR / NOT / XOR / NAND / NOR) combine inputs and feed other items
-- or other gates.
--
-- Started by PortalServer (Push "EditorStart"). The playtest pause menu (Restart Level / Rebuild... / Exit To Editor)
-- lives in PortalMenu and talks to this script through PortalEditor.EditorRequest.
-- Editor settings come from PortalMenu as player attributes Setting_ed*.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(ReplicatedStorage:WaitForChild("PortalConfig"))
if Config.VERSION ~= 3 then
	warn("[PortalMapEditor] ReplicatedStorage.PortalConfig is out of date (version " .. tostring(Config.VERSION) .. ", need 3). Replace it with the new PortalConfig - things will break until you do.")
end
local CELL, LIM, DIRS, OFFS = Config.CELL, Config.EDITOR_LIMITS, Config.DIRS, Config.OFFS

local SET = {
	LOADING_LOGO = "rbxassetid://75074251728778",
	APERTURE_LOGO_IMAGE = "rbxassetid://52186422", -- blank = drawn text logo
	LOGO_TRANSPARENCY = 0.55,
	BUILD_TIME = 2.5, -- the Building Test Chamber screen stays up at least this long
	WALL_THICKNESS = 3, -- the dark shell behind each panel (what you see along the cut edges)
	PALETTE_AUTOHIDE = true, -- default for the "Hide Items Palette" editor setting
	SFX_VOLUME = 0.6,
	DRONE_VOLUME = 0.3,
	BACKDROP = Color3.fromRGB(176, 178, 176), -- the grey around the room (Neon shows a bit brighter than this)
	ICONS = { -- all tinted with ImageColor3
		play = "rbxassetid://8517323790",
		undo = "rbxassetid://113997017619565",
		redo = "rbxassetid://133742372514080",
		eye = "rbxassetid://6523858394",
	},
	TIPS = {
		"Use the + and - keys to pull or push the selected surfaces.",
		"Right-click a surface to choose whether portals can be placed on it, or to give it a colour.",
		"The entry and exit doors have to be in every chamber. You can move them, but you can't delete or copy them.",
		"Press F9 while testing to rebuild the chamber with your latest changes.",
		"Drag across a wall to select an area, or click one panel and Shift+click another to select everything between them.",
		"Hold the middle mouse button and drag to orbit. Right-drag pans, scroll zooms.",
		"Select a button and press C, then click an item to make the button control it.",
		"An item with several inputs needs all of them on. Put an OR logic gate in front of it if any one should do.",
		"Logic gates can feed other gates. Right-click one to change it between AND, OR, NOT, XOR, NAND and NOR.",
		"Right-click a pedestal button to switch it between a timer, a single press and a toggle.",
		"Drag a faith plate's yellow ball onto any surface to aim it, then drag the ball up or down to change the arc.",
		"File > Invite team builder lets friends in this server build the chamber with you.",
		"On a controller: Y opens the Items palette, X opens the menu for whatever is under the cursor.",
		"The exit door is locked until something opens it. Connect a button to it, or right-click it > Open without a button.",
		"Switch to Intermediate or Advanced in Options > Editor (or File > Editor mode) for the Textures, Meshes and My Chips tabs.",
		"Textures tab: select surfaces, then click a texture (or paste an asset id) to put it on them.",
		"My Chips (Advanced): build little programs like \"when button1 pressed: open exit\" from blocks, or type them as lines.",
	},
}

local SFX = {
	Drone = { 78774027264390, 88862996062875, 120289031443170, 134274910822673, 103615267650257, 97703584777388, 134279540124301 },
	Tile = { 80508934878843, 110227701414336, 98572574178522, 125353899136641, 98509939256931 },
	TilePick = { 98572574178522, 110227701414336, 80508934878843, 125353899136641, 98509939256931 },
	CarveTile = { 138449951630571, 137754210625364 },
	CarveMetal = { 74471219629644, 119878594888593 },
	CarveWater = { 123585412775904 },
	ExtrudeTile = { 102932554317424, 115986533835601 },
	ExtrudeMetal = { 118117893158345, 91786359008547 },
	ExtrudeWater = { 139866237472121 },
	Error = { 94425407012485 },
	Click = { 120638773720390 },
	SelectStart = { 128562057284674 },
	SelectEnd = { 100760321480534 },
	Correction = { 91934232608097, 105115725939406 },
	Gel = { 90423466815284, 137564016268729, 125603862270494, 97471113724902, 111163652974431, 105977375217575 },
	TurretCollapse = { 119218397453762 },
}

local PALETTE_ORDER = {
	"button", "pedestal", "cube", "cubedropper",
	"faithplate", "fizzler", "laser", "lasercatcher",
	"laserfield", "lightbridge", "tbeam", "turret",
	"toxicgoo", "propulsion", "repulsion", "gate",
	"gel_blue", "gel_orange", "gel_white", "gel_water",
	-- invisible blocks (Intermediate / Advanced editor modes only, see ENTITY_TYPES tier)
	"trigger", "delay", "block", "light", "killzone", "pushzone",
}
local GEL_KINDS = { gel_blue = true, gel_orange = true, gel_white = true, gel_water = true, propulsion = true, repulsion = true }

local function rgb(r, g, b) return Color3.fromRGB(r, g or r, b or r) end

-- colours measured from the Puzzle Maker footage
local C = {
	BG = rgb(205, 207, 204),        -- the room backdrop (inner area)
	OUT = rgb(194, 196, 196),       -- frame border
	STRIP_OPEN = rgb(169, 171, 171), STRIP_SHUT = rgb(185, 187, 184), GRIP = rgb(140, 142, 142),
	MENU_TEXT = rgb(126, 128, 128), MENU_HI = rgb(70, 74, 74),
	ICON = rgb(158, 160, 160), ICON_HI = rgb(96, 100, 100), ICON_ON = rgb(60, 160, 172),
	PAL_BG = rgb(244), PAL_EDGE = rgb(110), TILE = rgb(229, 230, 233), TILE_LINE = rgb(214, 217, 221), TILE_HI = rgb(212, 236, 240),
	WHITE = rgb(232, 236, 230), BLACK = rgb(66, 75, 73), RIM_WHITE = rgb(198, 201, 198),
	RIM_BLACK = rgb(96, 104, 101), SHELL = rgb(88, 94, 92),
	SEL_WHITE = rgb(255, 250, 162), SEL_BLACK = rgb(193, 179, 99), HOVER = rgb(214, 176, 60),
	CTX_BG = rgb(230, 230, 227), CTX_HEAD = rgb(52, 52, 46), CTX_ICONCOL = rgb(190, 190, 188), CTX_EDGE = rgb(100, 100, 98),
	CTX_HI = rgb(201, 246, 236), CTX_HI_EDGE = rgb(0), CTX_ICON = rgb(36, 50, 50), CTX_GLYPH = rgb(63, 221, 200),
	CTX_TEXT = rgb(25), CTX_SHORT = rgb(140), CTX_SEP = rgb(116),
	LINK = rgb(255, 170, 40),
	WALLTILE_WHITE = rgb(220, 228, 236), WALLTILE_BLACK = rgb(58, 66, 76), -- floors / ceilings using wall tiles
}

local function px(x, y) return UDim2.fromOffset(x, y) end
local function new(class, props)
	local o = Instance.new(class)
	local parent
	for k, v in pairs(props) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	if parent then o.Parent = parent end
	return o
end
local function menuRequest(kind, arg)
	local menu = playerGui:FindFirstChild("PortalMenu")
	local req = menu and menu:FindFirstChild("MenuRequest")
	if req then req:Fire(kind, arg) end
end
local function netCall(action, arg)
	local f = ReplicatedStorage:FindFirstChild("PortalNet")
	if not f then return false, "No server." end
	local ok, a, b = pcall(function() return f.Request:InvokeServer(action, arg) end)
	if not ok then return false, tostring(a) end
	return a, b
end
local function newId()
	return game:GetService("HttpService"):GenerateGUID(false):gsub("-", ""):sub(1, 8)
end

-- editor settings (set in PortalMenu > Options > Editor, stored as player attributes)
local function ES(k, default)
	local v = player:GetAttribute("Setting_" .. k)
	if v == nil then return default end
	return v
end
local function curve(v) return 2 ^ (((tonumber(v) or 0.5) - 0.5) * 2) end -- 0..1 slider -> x0.5 .. x2

-- ==========================================
-- SOUNDS
-- ==========================================
local sfx, sound, setDrone
do
	local sfxFolder = game:GetService("SoundService"):FindFirstChild("PortalEditorSounds")
	if sfxFolder then sfxFolder:Destroy() end
	sfxFolder = new("Folder", { Name = "PortalEditorSounds", Parent = game:GetService("SoundService") })
	local lastPick = {}
	local function pickId(name)
		local list = SFX[name]
		if not list or #list == 0 then return nil end
		local i = math.random(#list)
		if #list > 1 and list[i] == lastPick[name] then i = i % #list + 1 end
		lastPick[name] = list[i]
		return "rbxassetid://" .. list[i]
	end
	local lastPlay = {}
	sfx = function(name, vol, minGap)
		local now = os.clock()
		if minGap and lastPlay[name] and now - lastPlay[name] < minGap then return end
		lastPlay[name] = now
		local id = pickId(name)
		if not id then return end
		local volume = (vol or SET.SFX_VOLUME) * (tonumber(ES("edSfx", 1)) or 1)
		if volume <= 0 then return end
		local s = new("Sound", { SoundId = id, Volume = volume, Parent = sfxFolder })
		s.Ended:Connect(function() s:Destroy() end)
		s:Play()
		task.delay(12, function() if s.Parent then s:Destroy() end end)
	end
	-- old keys still used around the script
	sound = function(key)
		if key == "SOUND_HOVER" then menuRequest("Sound", key)
		elseif key == "SOUND_INVALID" then sfx("Error")
		else sfx("Click") end
	end
	task.spawn(function()
		local list = {}
		for name, ids in pairs(SFX) do
			if name ~= "Drone" then
				for _, id in ipairs(ids) do table.insert(list, new("Sound", { SoundId = "rbxassetid://" .. id })) end
			end
		end
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(list) end)
	end)

	-- ambient drones: one after another while you edit
	local drone = new("Sound", { Name = "Drone", Volume = SET.DRONE_VOLUME, Parent = sfxFolder })
	local function droneVolume() drone.Volume = SET.DRONE_VOLUME * (tonumber(ES("edDrone", 1)) or 1) end
	player:GetAttributeChangedSignal("Setting_edDrone"):Connect(droneVolume)
	droneVolume()
	local droneOn = false
	drone.Ended:Connect(function()
		if droneOn then
			drone.SoundId = pickId("Drone")
			drone:Play()
		end
	end)
	setDrone = function(on)
		if on == droneOn then return end
		droneOn = on
		if on then
			droneVolume()
			drone.SoundId = pickId("Drone")
			drone.TimePosition = 0
			drone:Play()
		else
			drone:Stop()
		end
	end
end

local key, faceKey = Config.Key, Config.FaceKey
local function parse(k)
	local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)")
	return tonumber(x), tonumber(y), tonumber(z)
end
local function parseFace(k)
	local x, y, z, f = k:match("^(-?%d+),(-?%d+),(-?%d+),(%d)$")
	return tonumber(x), tonumber(y), tonumber(z), tonumber(f)
end
local function inBounds(x, y, z)
	return math.abs(x) <= LIM.x and math.abs(z) <= LIM.z and y >= LIM.yMin and y <= LIM.yMax
end

local FONT = {}
FONT.UI = Font.new("rbxasset://fonts/families/Arimo.json", Enum.FontWeight.Bold)
FONT.UI_REG = Font.new("rbxasset://fonts/families/Arimo.json", Enum.FontWeight.Regular)
FONT.UI_ITALIC = Font.new("rbxasset://fonts/families/Arimo.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
FONT.P2 = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Bold)
FONT.P2_MED = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Medium)

-- ==========================================
-- STATE
-- ==========================================
local E = {
	active = false, playtest = false, building = false, cancel = false,
	id = nil, title = "Untitled Chamber", coop = false,
	air = {}, faces = {}, colors = {}, textures = {}, ents = {}, links = {}, chips = {},
	sel = {}, selItem = nil, anchor = nil, linking = nil,
	undo = {}, redo = {}, dirty = false, stale = true, gameView = false,
	-- camera: yaw / pitch / dist / target are where it WANTS to be, c* is where it is (smoothed toward the goal)
	yaw = math.rad(-35), pitch = math.rad(-42), dist = 110, target = Vector3.zero,
	cYaw = math.rad(-35), cPitch = math.rad(-42), cDist = 110, cTarget = Vector3.zero,
	faceParts = {}, entModels = {}, drag = nil, carry = nil, rmb = nil, mmb = false, lastCull = nil,
	chromeHold = 0, zoomShow = 0,
	-- pointer: "mouse" | "pad" (virtual cursor) | "touch". pointer = screen position (same space as GetMouseLocation)
	pointerMode = "mouse", pointer = nil, touch = nil, touchOrbit = false, pinch = nil, carryArm = nil, lastColor = 1,
	-- team building
	team = nil, guest = false, rev = 0, sentRev = 0, lastSync = 0, pendingRemote = nil, lastCursorSend = 0,
}
local dialog -- open popup dialog (forward)
local Pal = { open = true, awayT = nil, tab = "items", pages = {}, tabs = {}, built = {} } -- the palette (built below)
local X = {} -- extras: toasts, the coordinates readout
function X.toast(text, title, kind) menuRequest("Toast", { text = text, title = title, kind = kind }) end
local Dlg = {} -- popup dialogs (rename / publish / controls / open / save as / invite / chips)
local controls
task.spawn(function()
	local ps = player:WaitForChild("PlayerScripts", 10)
	local pm = ps and ps:WaitForChild("PlayerModule", 5)
	if pm then
		local ok, m = pcall(require, pm)
		if ok and m then controls = m:GetControls() end
	end
end)

local function shiftDown()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end
local function ctrlDown()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end
local function isPad(input)
	return string.sub(input.UserInputType.Name, 1, 7) == "Gamepad"
end
local function padDown(kc)
	return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, kc)
end

-- ==========================================
-- GUI: VIEWPORT + SCALED CANVAS
-- ==========================================
for _, n in ipairs({ "PortalEditor", "PortalBuilding", "PortalEditorStatus" }) do
	local old = playerGui:FindFirstChild(n)
	if old then old:Destroy() end
end
local gui = new("ScreenGui", { Name = "PortalEditor", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false, Parent = playerGui })
local editorRequest = new("BindableEvent", { Name = "EditorRequest", Parent = gui })

-- The editor room lives in workspace (made on this client only, so nobody else sees it), far up at W, and is only
-- parented while you're editing. cam holds the editor camera; it's copied onto workspace.CurrentCamera every frame.
local W = Vector3.new(0, 4000, 0)
local world = new("Model", { Name = "PortalEditorWorld" })
local cam = new("Camera", { FieldOfView = 45 })
local roomFolder = new("Model", { Name = "Room", Parent = world })
local entFolder = new("Model", { Name = "Items", Parent = world })
local fxFolder = new("Model", { Name = "FX", Parent = world })
local linkFolder = new("Model", { Name = "Links", Parent = world })
local teamFolder = new("Model", { Name = "Team", Parent = world })
-- handles (rotation diamonds, stretch triangles, faith plate ball), item previews (bridges, fields, arcs...)
local H = { model = new("Model", { Name = "Handles", Parent = world }), previewRoot = new("Model", { Name = "Previews", Parent = world }), previews = {} }
local hoverPart = new("Part", { Anchored = true, CanQuery = false, CanCollide = false, Color = C.HOVER, Transparency = 1, Material = Enum.Material.SmoothPlastic, Parent = fxFolder })
local itemBox = new("Part", { Anchored = true, CanQuery = false, CanCollide = false, Color = C.SEL_WHITE, Transparency = 1, Parent = fxFolder })
local shadow = new("Part", { Anchored = true, CanQuery = false, CanCollide = false, Color = rgb(160, 166, 160), Transparency = 0.7, Parent = fxFolder })
local ghost

-- plain grey backdrop all round (Neon = flat colour, no shading), like the Puzzle Maker's empty background
do
	local S, T = 2400, 4
	for _, d in ipairs(DIRS) do
		local size = Vector3.new(math.abs(d.X) > 0.5 and T or S * 2, math.abs(d.Y) > 0.5 and T or S * 2, math.abs(d.Z) > 0.5 and T or S * 2)
		new("Part", { Name = "Backdrop", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Material = Enum.Material.Neon, Color = SET.BACKDROP, Size = size, CFrame = CFrame.new(W + d * S), Parent = world })
	end
end

-- editor lighting: saved / swapped in while editing, put back for testing and when you leave
local setEditing
do
local EDIT_LIGHTING = {
	ClockTime = 14, Brightness = 2, Ambient = rgb(138, 140, 138), OutdoorAmbient = rgb(150, 152, 150),
	FogStart = 0, FogEnd = 100000, GlobalShadows = true, ExposureCompensation = 0,
	EnvironmentDiffuseScale = 0.4, EnvironmentSpecularScale = 0.3,
}
local editing, envSaved = false, nil
setEditing = function(on)
	if on == editing then return end
	editing = on
	local Lighting = game:GetService("Lighting")
	local wcam = workspace.CurrentCamera
	world.Parent = on and workspace or nil
	if on then
		envSaved = { props = {}, effects = {}, fov = wcam and wcam.FieldOfView or 70 }
		for k, v in pairs(EDIT_LIGHTING) do
			local ok, old = pcall(function() return Lighting[k] end)
			if ok then
				envSaved.props[k] = old
				pcall(function() Lighting[k] = v end)
			end
		end
		for _, d in ipairs(Lighting:GetChildren()) do
			if d:IsA("PostEffect") and d.Name ~= "PortalBuildBlur" then
				envSaved.effects[d] = d.Enabled
				d.Enabled = false -- no blur / depth of field / bloom over the editor
			elseif d:IsA("Atmosphere") then
				envSaved.atmo = { d, d.Density, d.Haze }
				d.Density, d.Haze = 0, 0
			end
		end
		-- controller: the Back / View button is Build and Play here, not Roblox's UI selection mode
		pcall(function()
			envSaved.autoSelect = GuiService.AutoSelectGuiEnabled
			GuiService.AutoSelectGuiEnabled = false
		end)
		-- touch: the movement thumbstick / jump button make no sense in the editor
		pcall(function()
			envSaved.touchControls = GuiService.TouchControlsEnabled
			GuiService.TouchControlsEnabled = false
		end)
	elseif envSaved then
		for k, v in pairs(envSaved.props) do pcall(function() Lighting[k] = v end) end
		for d, was in pairs(envSaved.effects) do if d.Parent then d.Enabled = was end end
		if envSaved.atmo and envSaved.atmo[1].Parent then
			envSaved.atmo[1].Density, envSaved.atmo[1].Haze = envSaved.atmo[2], envSaved.atmo[3]
		end
		if wcam then wcam.FieldOfView = envSaved.fov end
		pcall(function() GuiService.AutoSelectGuiEnabled = envSaved.autoSelect ~= false end)
		pcall(function() GuiService.TouchControlsEnabled = envSaved.touchControls ~= false end)
		GuiService.SelectedObject = nil
		UserInputService.MouseIconEnabled = true
		envSaved = nil
	end
end
end

-- everything 2D lives on a 1918 x 1072 reference canvas (the footage size) scaled to the screen height
local REF_H = 1072
local canvas = new("Frame", { Name = "Canvas", BackgroundTransparency = 1, ZIndex = 2, Parent = gui })
local uiScale = new("UIScale", { Parent = canvas })
local function rescaleUI()
	local c = workspace.CurrentCamera
	local vp = c and c.ViewportSize or Vector2.new(1918, 1072)
	uiScale.Scale = math.max(vp.Y, 1) / REF_H
	canvas.Size = px(vp.X / uiScale.Scale, REF_H)
end
do
	local vpConn
	local function hookViewport()
		if vpConn then vpConn:Disconnect() end
		local c = workspace.CurrentCamera
		if c then vpConn = c:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleUI) end
		rescaleUI()
	end
	hookViewport()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookViewport)
end

local function canvasWidth() return canvas.AbsoluteSize.X / uiScale.Scale end

-- where the pointer is on screen (mouse, the controller cursor, or the last touch)
local function pointerScreen()
	if E.pointerMode ~= "mouse" and E.pointer then return E.pointer end
	return UserInputService:GetMouseLocation()
end
local function mouseCanvas()
	local m = pointerScreen() - GuiService:GetGuiInset()
	return (m - canvas.AbsolutePosition) / uiScale.Scale
end
local function viewportSize()
	local c = workspace.CurrentCamera
	return c and c.ViewportSize or Vector2.new(1920, 1080)
end
local function usePad()
	if E.pointerMode ~= "pad" then
		E.pointer = (E.pointerMode == "mouse") and UserInputService:GetMouseLocation() or (E.pointer or viewportSize() / 2)
		E.pointerMode = "pad"
	end
end

-- anything marked EditorUI blocks clicks / hover from reaching the room
local function ui(o) o:SetAttribute("EditorUI", true) return o end
local function isUI(o)
	while o and o ~= gui do
		if o:GetAttribute("EditorUI") then return true end
		o = o.Parent
	end
	return false
end

-- buttons the controller cursor can press (it can't fire real clicks, so clicks are registered here too)
-- and hover effects that also run for controller selection / the controller cursor
local CLICK = setmetatable({}, { __mode = "k" })
local HOVER = setmetatable({}, { __mode = "k" })
local function onClick(b, fn)
	CLICK[b] = fn
	b.MouseButton1Click:Connect(fn)
end
local function hoverable(b, enter, leave)
	HOVER[b] = { enter, leave }
	b.MouseEnter:Connect(enter)
	b.MouseLeave:Connect(leave)
	b.SelectionGained:Connect(enter)
	b.SelectionLost:Connect(leave)
end
local function guiAtPointer(registry)
	local m = pointerScreen() - GuiService:GetGuiInset()
	for _, o in ipairs(playerGui:GetGuiObjectsAtPosition(m.X, m.Y)) do
		if registry[o] and o:IsDescendantOf(gui) and o.Visible then return o end
	end
	return nil
end
-- first button inside root gets the controller selection (menus, dialogs, the palette)
local function focusFirst(root)
	if E.pointerMode ~= "pad" or not root then return end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiButton") and d.Selectable and d.Visible then
			GuiService.SelectedObject = d
			return
		end
	end
end

-- shape helpers: L = from the left, R = x measured from the right edge, M = from the centre
local function L(x, y) return UDim2.fromOffset(x, y) end
local function R(x, y) return UDim2.new(1, -x, 0, y) end
local function M(x, y) return UDim2.new(0.5, x, 0, y) end
local function block(parent, pos, size, color, z)
	return new("Frame", { Position = pos, Size = size, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z or 1, Parent = parent })
end
-- right triangle filling one corner of an s x s square (hard-edged gradient, so it clips cleanly)
local tri
do
	local TRI_SEQ = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.499, 0),
		NumberSequenceKeypoint.new(0.501, 1), NumberSequenceKeypoint.new(1, 1),
	})
	local TRI_ROT = { tl = 45, tr = 135, br = 225, bl = 315 }
	tri = function(parent, pos, s, corner, color, z)
		local f = block(parent, pos, px(s, s), color, z)
		new("UIGradient", { Rotation = TRI_ROT[corner], Transparency = TRI_SEQ, Parent = f })
		return f
	end
end

-- faint logo top-left (always visible)
if SET.APERTURE_LOGO_IMAGE ~= "" then
	new("ImageLabel", { Position = px(17, 42), Size = px(262, 68), BackgroundTransparency = 1, Image = SET.APERTURE_LOGO_IMAGE,
		ImageTransparency = SET.LOGO_TRANSPARENCY, ScaleType = Enum.ScaleType.Fit, ZIndex = 1, Parent = canvas })
else
	local logoCol = rgb(186, 188, 185)
	local logo = new("Frame", { Position = px(17, 42), Size = px(262, 68), BackgroundTransparency = 1, ZIndex = 1, Parent = canvas })
	local ring = new("Frame", { Position = px(4, 4), Size = px(60, 60), BackgroundTransparency = 1, Parent = logo })
	new("UIStroke", { Color = logoCol, Thickness = 9, Parent = ring })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
	new("TextLabel", { Position = px(56, 4), Size = px(206, 40), BackgroundTransparency = 1, Text = "APERTURE", FontFace = FONT.P2, TextSize = 42,
		TextColor3 = logoCol, TextXAlignment = Enum.TextXAlignment.Left, Parent = logo })
	new("TextLabel", { Position = px(60, 44), Size = px(200, 16), BackgroundTransparency = 1, Text = "L A B O R A T O R I E S", FontFace = FONT.P2_MED,
		TextSize = 14, TextColor3 = logoCol, TextXAlignment = Enum.TextXAlignment.Left, Parent = logo })
end

-- ==========================================
-- FRAME CHROME (fades as one piece)
-- ==========================================
local chrome = new("CanvasGroup", { Name = "Chrome", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 0, ZIndex = 3, Parent = canvas })
do
	local O = C.OUT
	-- top: menu area, raised tab, toolbar recess, raised tab, then the thinner right part
	block(chrome, L(0, 0), UDim2.new(1, 0, 0, 8), O)
	tri(chrome, M(-121, 8), 27, "tr", O)
	block(chrome, M(-94, 8), px(188, 28), O)
	tri(chrome, M(94, 8), 27, "tl", O)
	tri(chrome, R(514, 8), 22, "tr", O)
	block(chrome, R(492, 8), px(492, 22), O)
	-- right: two notches
	block(chrome, R(25, 30), px(25, 304), O)
	tri(chrome, R(25, 334), 24, "tr", O)
	tri(chrome, R(17, 382), 16, "br", O)
	block(chrome, R(17, 398), px(17, 284), O)
	tri(chrome, R(17, 682), 16, "tr", O)
	tri(chrome, R(25, 724), 23, "br", O)
	block(chrome, R(25, 747), px(25, REF_H - 747), O)
	-- bottom right
	tri(chrome, R(515, REF_H - 18), 18, "br", O)
	block(chrome, R(497, REF_H - 19), px(497, 19), O)
	-- left (the middle is the palette strip, drawn separately because it never fades)
	block(chrome, L(0, 34), px(9, 111), O)
	tri(chrome, L(9, 34), 16, "tl", O)
	block(chrome, L(0, 936), px(9, REF_H - 936), O)
end

-- File / Edit / Help corner: moves right of Roblox's own top-left buttons so they don't cover it
local menuRow
do
	local menuFill = block(chrome, L(0, 0), px(0, 34), C.OUT)
	menuRow = new("Frame", { Position = L(0, 0), Size = px(300, 34), BackgroundTransparency = 1, ZIndex = 2, Parent = chrome })
	block(menuRow, L(0, 0), px(272, 34), C.OUT)
	tri(menuRow, L(272, 8), 26, "tl", C.OUT)
	local function placeMenuRow()
		local inset = GuiService.TopbarInset
		local x = inset.Min.X > 1 and math.ceil(inset.Min.X / uiScale.Scale) or 0
		menuRow.Position = L(x, 0)
		menuFill.Size = px(x + 1, 34)
	end
	placeMenuRow()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeMenuRow)
	uiScale:GetPropertyChangedSignal("Scale"):Connect(placeMenuRow)
end

-- left palette strip (always visible)
local stripParts = {}
do
	local S = C.STRIP_OPEN
	table.insert(stripParts, block(canvas, L(0, 145), px(9, 17), S, 4))
	table.insert(stripParts, tri(canvas, L(9, 145), 17, "bl", S, 4))
	table.insert(stripParts, block(canvas, L(0, 162), px(26, 757), S, 4))
	table.insert(stripParts, tri(canvas, L(9, 919), 17, "tl", S, 4))
	table.insert(stripParts, block(canvas, L(0, 919), px(9, 17), S, 4))
	for i = 0, 2 do block(canvas, L(10 + i * 3, 528), px(1, 24), C.GRIP, 5) end
end
local leftStrip = ui(new("TextButton", { Position = L(0, 145), Size = px(26, 791), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Selectable = false, ZIndex = 6, Parent = canvas }))

-- tooltip under the toolbar
local tooltip = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = M(0, 44), Size = px(420, 22), BackgroundTransparency = 1, Text = "",
	FontFace = FONT.UI_REG, TextSize = 16, TextColor3 = C.MENU_TEXT, ZIndex = 6, Parent = canvas })

-- zoom bar (right side, shows while zooming)
local zoomBar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = R(62, 540), Size = px(14, 200), BackgroundColor3 = C.STRIP_OPEN,
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4, Parent = canvas })

-- game view: "This view is not current" (bottom left, like the Puzzle Maker)
local staleBox = new("Frame", { Position = UDim2.new(0, 96, 1, -112), Size = px(730, 92), BackgroundColor3 = rgb(0), BackgroundTransparency = 0.4, BorderSizePixel = 0, Visible = false, ZIndex = 5, Parent = canvas })
new("TextLabel", { Position = px(12, 6), Size = px(700, 40), BackgroundTransparency = 1, Text = "This view is not current", FontFace = FONT.P2, TextSize = 36,
	TextColor3 = rgb(244), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = staleBox })
new("TextLabel", { Position = px(12, 50), Size = px(700, 30), BackgroundTransparency = 1, Text = "Rebuild your test chamber to view recent changes", FontFace = FONT.P2_MED, TextSize = 24,
	TextColor3 = rgb(236), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = staleBox })

-- Advanced mode: what's under the pointer (cell, face, item label)
X.coords = new("TextLabel", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 40, 1, -26), Size = px(600, 22), BackgroundTransparency = 1, Text = "",
	FontFace = FONT.UI_REG, TextSize = 16, TextColor3 = rgb(90, 94, 94), TextXAlignment = Enum.TextXAlignment.Left, Visible = false, ZIndex = 6, Parent = canvas })

-- controller cursor + controller hint line
local padCursor = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = px(30, 30), BackgroundTransparency = 1, Visible = false, ZIndex = 80, Parent = canvas })
do
	local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = px(26, 26), BackgroundTransparency = 1, ZIndex = 80, Parent = padCursor })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
	new("UIStroke", { Color = rgb(20), Thickness = 4, Parent = ring })
	local inner = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = px(22, 22), BackgroundTransparency = 1, ZIndex = 81, Parent = padCursor })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = inner })
	new("UIStroke", { Color = rgb(70, 220, 230), Thickness = 2, Parent = inner })
	local dot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = px(5, 5), BackgroundColor3 = rgb(255), BorderSizePixel = 0, ZIndex = 82, Parent = padCursor })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
end
local padHint = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -26), Size = px(1300, 26), BackgroundTransparency = 1,
	Text = "A Select    X Menu    Y Items    D-Pad Pull / Push / Rotate / Portal    LB RB Zoom    LT + Sticks Move    L3 Connect    Back Play    Start Pause",
	FontFace = FONT.UI_REG, TextSize = 17, TextColor3 = rgb(90, 94, 94), Visible = false, ZIndex = 6, Parent = canvas })

-- status / flash text (its own gui so it also shows while playtesting)
local flash
do
	local statusGui = new("ScreenGui", { Name = "PortalEditorStatus", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 415, Parent = playerGui })
	local status = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = px(0, 40), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = rgb(30, 36, 36), BackgroundTransparency = 0.2, Text = "", FontFace = FONT.P2_MED, TextSize = 24,
		TextColor3 = rgb(236, 244, 242), Visible = false, Parent = statusGui,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = status })
	flash = function(text)
		status.Text = tostring(text)
		status.Visible = true
		local t = os.clock()
		status:SetAttribute("T", t)
		task.delay(3, function() if status:GetAttribute("T") == t then status.Visible = false end end)
	end
end

local menuButtons, openMenus, closeMenus, popupMenu, overUI
do
-- ==========================================
-- POPUP MENUS (File / Edit / Help dropdowns and the right-click menus)
-- ==========================================
menuButtons = {}
openMenus = {}
closeMenus = function()
	for _, m in ipairs(openMenus) do m:Destroy() end
	table.clear(openMenus)
	for _, mb in ipairs(menuButtons) do mb.reset() end
	if H.highlight and not E.linking then H.highlight(nil) end
	local so = GuiService.SelectedObject
	if so and (not so.Parent or (so:IsDescendantOf(gui) and not so:GetAttribute("PalTile"))) then GuiService.SelectedObject = nil end
end

-- Context / dropdown menus, laid out like the Puzzle Maker's.
-- popupMenu(x, y, sections): sections = { { title = "ITEM" | nil, items = { ... } }, ... } stacked under each other.
-- item fields: text, shortcut, icon = "check" | "plus" | "minus" | "glyph" | "radio", glyph, checked, disabled, sep,
--   swatch = Color3       a colour square instead of an icon (tile colours)
--   fn()                  click
--   sub() -> items        opens a submenu to the right on hover / click (">" arrow)
--   hover(on)             called when the row is hovered / left (used to highlight an item in the room)
--   timer = { value, set(v), min, max }   the red LED timer row with up / down arrows
-- (declared above the do block) local popupMenu
do
local TextService = game:GetService("TextService")
local subMenu -- the open submenu frame (one level)
local function rowTextWidth(text)
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, 15, Enum.Font.Arial, Vector2.new(1000, 100)).X
	end)
	return ok and v or #text * 8
end

local buildMenuFrame -- forward
local function openSubmenu(x, y, items)
	if subMenu then subMenu:Destroy() subMenu = nil end
	subMenu = buildMenuFrame(x, y, { { items = items } }, true)[1]
	table.insert(openMenus, subMenu)
	return subMenu
end

buildMenuFrame = function(x, y, sections, isSub)
	local frames = {}
	local rowH, timerH, headerH, gap = 29, 64, 21, 10
	if E.pointerMode == "touch" then rowH = 40 end -- bigger rows for fingers
	-- one width for every section, from the longest text
	local w = 201
	for _, sec in ipairs(sections) do
		for _, it in ipairs(sec.items) do
			if it.text then w = math.max(w, 48 + rowTextWidth(it.text) + (it.sub and 48 or 0) + (it.shortcut and 60 or 12)) end
		end
	end
	w = math.ceil(w)
	local cy = y
	for _, sec in ipairs(sections) do
		local hh = sec.title and headerH or 0
		local h = hh + 4
		for _, it in ipairs(sec.items) do h += it.timer and timerH or rowH end
		local frame = ui(new("Frame", { Position = px(x, cy), Size = px(w, h), BackgroundColor3 = C.CTX_BG, BackgroundTransparency = 0.12,
			BorderSizePixel = 0, Active = true, ZIndex = isSub and 50 or 40, SelectionGroup = true, Parent = canvas }))
		local z = frame.ZIndex
		new("UIStroke", { Color = C.CTX_EDGE, Thickness = 1, Transparency = 0.15, Parent = frame })
		new("Frame", { Position = px(0, hh), Size = px(39, h - hh), BackgroundColor3 = C.CTX_ICONCOL, BackgroundTransparency = 0.25,
			BorderSizePixel = 0, ZIndex = z, Parent = frame })
		if sec.title then
			local head = new("Frame", { Size = px(w, hh), BackgroundColor3 = C.CTX_HEAD, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = z + 1, Parent = frame })
			new("TextLabel", { Size = px(w - 7, hh), BackgroundTransparency = 1, Text = string.upper(sec.title), FontFace = FONT.UI_REG, TextSize = 15,
				TextColor3 = rgb(236), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = z + 2, Parent = head })
		end
		local y0 = hh + 2
		for _, it in ipairs(sec.items) do
			if it.timer then
				-- red LED timer with up / down arrows in the icon column
				local tm = it.timer
				local row = new("Frame", { Position = px(2, y0), Size = px(w - 4, timerH - 2), BackgroundTransparency = 1, ZIndex = z + 2, Parent = frame })
				local box = new("Frame", { Position = px(48, 8), Size = px(96, 46), BackgroundColor3 = rgb(34, 30, 30), BorderSizePixel = 0, ZIndex = z + 3, Parent = row })
				new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = box })
				new("UIStroke", { Color = rgb(80, 76, 76), Thickness = 1, Parent = box })
				local led = new("TextLabel", { Position = px(4, 0), Size = px(74, 46), BackgroundTransparency = 1, Text = (":%02d"):format(tm.value),
					Font = Enum.Font.Code, TextSize = 38, TextColor3 = rgb(240, 70, 80), ZIndex = z + 4, Parent = box })
				new("TextLabel", { Position = px(76, 26), Size = px(16, 16), BackgroundTransparency = 1, Text = "◷", Font = Enum.Font.GothamBold, TextSize = 13,
					TextColor3 = rgb(240, 70, 80), ZIndex = z + 4, Parent = box })
				local function arrow(yy, glyph, delta)
					local b = new("TextButton", { Position = px(7, yy), Size = px(20, 20), BackgroundColor3 = C.CTX_ICON, BorderSizePixel = 0, AutoButtonColor = false,
						Text = glyph, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.CTX_GLYPH, ZIndex = z + 4, Parent = row })
					hoverable(b, function() b.BackgroundColor3 = rgb(60, 80, 80) sound("SOUND_HOVER") end, function() b.BackgroundColor3 = C.CTX_ICON end)
					onClick(b, function()
						tm.value = math.clamp(tm.value + delta, tm.min or 1, tm.max or 30)
						led.Text = (":%02d"):format(tm.value)
						sfx("Click")
						tm.set(tm.value)
					end)
				end
				arrow(9, "︿", 1)
				arrow(34, "﹀", -1)
				if it.sep then
					new("Frame", { Position = px(38, timerH - 3), Size = px(w - 44, 1), BackgroundColor3 = C.CTX_SEP, BorderSizePixel = 0, ZIndex = z + 3, Parent = row })
				end
				y0 += timerH
			else
				local b = new("TextButton", { Position = px(2, y0), Size = px(w - 4, rowH - 2), BackgroundColor3 = C.CTX_HI, BackgroundTransparency = 1,
					BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = z + 2, Parent = frame })
				local stroke = new("UIStroke", { Color = C.CTX_HI_EDGE, Thickness = 1, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
				if it.swatch then
					local ic = new("Frame", { Position = px(9, (rowH - 2) / 2 - 9), Size = px(18, 18), BackgroundColor3 = it.swatch, BorderSizePixel = 0, ZIndex = z + 3, Parent = b })
					new("UIStroke", { Color = it.checked and C.CTX_GLYPH or rgb(40), Thickness = it.checked and 2.5 or 1, Parent = ic })
				elseif it.icon == "radio" then
					local ic = new("Frame", { Position = px(9, (rowH - 2) / 2 - 8), Size = px(16, 16), BackgroundColor3 = rgb(70, 74, 74), BorderSizePixel = 0, ZIndex = z + 3, Parent = b })
					new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ic })
					if it.checked then
						new("UIStroke", { Color = C.CTX_GLYPH, Thickness = 2.5, Parent = ic })
						ic.BackgroundColor3 = rgb(30, 50, 50)
					end
				elseif it.icon then
					local ic = new("Frame", { Position = px(9, (rowH - 2) / 2 - 9), Size = px(18, 18), BackgroundColor3 = C.CTX_ICON, BorderSizePixel = 0, ZIndex = z + 3, Parent = b })
					local glyph = it.glyph or (it.icon == "check" and (it.checked and "✓" or "") or (it.icon == "plus" and "+" or (it.icon == "minus" and "−" or "")))
					new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = glyph, FontFace = FONT.UI, TextSize = 17,
						TextColor3 = C.CTX_GLYPH, ZIndex = z + 4, Parent = ic })
				end
				new("TextLabel", { Position = px(46, 0), Size = px(w - 110, rowH - 2), BackgroundTransparency = 1, Text = it.text, FontFace = FONT.UI_REG, TextSize = 15,
					TextColor3 = it.disabled and rgb(160) or C.CTX_TEXT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = z + 3, Parent = b })
				new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = px(70, rowH - 2), BackgroundTransparency = 1,
					Text = it.sub and "›" or (it.shortcut or ""), FontFace = it.sub and FONT.UI or FONT.UI_ITALIC, TextSize = it.sub and 20 or 14,
					TextColor3 = it.sub and rgb(40) or C.CTX_SHORT, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = z + 3, Parent = b })
				if it.sep then
					new("Frame", { Position = px(36, rowH - 1), Size = px(w - 42, 1), BackgroundColor3 = C.CTX_SEP, BorderSizePixel = 0, ZIndex = z + 3, Parent = b })
				end
				local function openSub()
					if isSub or not it.sub then return end
					local pos = (b.AbsolutePosition - canvas.AbsolutePosition) / uiScale.Scale
					return openSubmenu(pos.X + w - 2, pos.Y - 3, it.sub())
				end
				hoverable(b, function()
					if it.disabled then return end
					b.BackgroundTransparency, stroke.Transparency = 0, 0
					sound("SOUND_HOVER")
					if it.hover then it.hover(true) end
					if not isSub then
						if it.sub then
							openSub()
						elseif subMenu then
							subMenu:Destroy()
							subMenu = nil
						end
					end
				end, function()
					b.BackgroundTransparency, stroke.Transparency = 1, 1
					if it.hover then it.hover(false) end
				end)
				onClick(b, function()
					if it.disabled then sfx("Error") return end
					if it.sub then
						-- touch / controller: a tap opens the submenu (there's no hover)
						local sm = openSub()
						if sm then focusFirst(sm) end
						return
					end
					sfx("Click")
					if it.hover then it.hover(false) end
					closeMenus()
					it.fn()
				end)
				y0 += rowH
			end
		end
		table.insert(frames, frame)
		cy += h + gap
	end
	-- keep the whole stack on screen
	local total = cy - gap - y
	local cw = canvasWidth()
	local dx = math.min(0, cw - 14 - (x + w))
	local dy = math.min(0, REF_H - 14 - (y + total))
	if x + dx < 4 then dx = 4 - x end
	if y + dy < 4 then dy = 4 - y end
	for _, f in ipairs(frames) do f.Position += px(dx, dy) end
	return frames
end

popupMenu = function(x, y, sections)
	closeMenus()
	subMenu = nil
	for _, f in ipairs(buildMenuFrame(x, y, sections, false)) do table.insert(openMenus, f) end
	focusFirst(openMenus[1])
end
end

overUI = function()
	if #openMenus > 0 or dialog then return true end
	local m = pointerScreen() - GuiService:GetGuiInset()
	for _, o in ipairs(playerGui:GetGuiObjectsAtPosition(m.X, m.Y)) do
		if o:IsDescendantOf(gui) and isUI(o) then return true end
	end
	return false
end

end
-- ==========================================
-- CHAMBER DATA
-- ==========================================
local function serialize()
	local data = { v = 2, air = {}, faces = {}, colors = {}, textures = {}, ents = {}, links = {}, chips = {}, coop = E.coop }
	for k in pairs(E.air) do
		local x, y, z = parse(k)
		table.insert(data.air, { x, y, z })
	end
	for k, v in pairs(E.faces) do data.faces[k] = v end
	for k, v in pairs(E.colors) do data.colors[k] = v end
	for k, v in pairs(E.textures) do data.textures[k] = v end
	for _, c in ipairs(E.chips) do table.insert(data.chips, { name = c.name, src = c.src }) end
	for _, e in ipairs(E.ents) do
		local c = table.clone(e)
		c[7] = c[7] or false -- no holes in the array (variant is nil for most items)
		if c[10] ~= nil then c[9] = c[9] or false end
		c[8] = c[8] or newId()
		table.insert(data.ents, c)
	end
	for _, l in ipairs(E.links) do table.insert(data.links, { l[1], l[2] }) end
	return data
end

local function snapshot()
	local ents, links = {}, {}
	for i, e in ipairs(E.ents) do ents[i] = table.clone(e) end
	for i, l in ipairs(E.links) do links[i] = table.clone(l) end
	local chips = {}
	for i, c in ipairs(E.chips) do chips[i] = table.clone(c) end
	return { air = table.clone(E.air), faces = table.clone(E.faces), colors = table.clone(E.colors), textures = table.clone(E.textures),
		ents = ents, links = links, chips = chips }
end

local function isFace(x, y, z, f)
	local o = OFFS[f]
	return E.air[key(x, y, z)] and not E.air[key(x + o[1], y + o[2], z + o[3])]
end

-- does placing / moving / deleting this item change the room itself (door alcove, faith plate pit)?
local function needsRoom(kind) return Config.MakesHole(kind) end

local refreshSelection, entById, canSource, canTarget, hasLinks, entLabel, buildEntity, updateCull, rebuildEnts, rebuild, refreshItems, applyCamera
do
-- ==========================================
-- RENDERING
-- ==========================================
local function panelColor(fp)
	if fp.tint then return fp.tint end
	return fp.wallT and (fp.portal and C.WALLTILE_WHITE or C.WALLTILE_BLACK) or (fp.portal and C.WHITE or C.BLACK)
end

refreshSelection = function()
	for fk, fp in pairs(E.faceParts) do
		local sel = E.sel[fk]
		fp.panel.Color = sel and (fp.portal and C.SEL_WHITE or C.SEL_BLACK) or panelColor(fp)
	end
	local m = E.selItem and E.entModels[E.selItem]
	if m then
		local cf, size = m:GetBoundingBox()
		itemBox.CFrame, itemBox.Size, itemBox.Transparency = cf, size + Vector3.new(0.6, 0.6, 0.6), 0.7
	else
		itemBox.Transparency = 1
	end
	if H.update then H.update() end
end

-- ----- item links (sources -> the items they drive) -----
entById = function(id)
	for i, e in ipairs(E.ents) do
		if e[8] == id then return i, e end
	end
end
canSource = function(e) return Config.CanSource(e[1]) end
canTarget = function(e) return Config.CanTarget(e[1]) end
hasLinks = function(e)
	for _, l in ipairs(E.links) do
		if l[1] == e[8] or l[2] == e[8] then return true end
	end
	return false
end
entLabel = function(e)
	local def = Config.ENTITY_TYPES[e[1]]
	if e[1] == "gate" then return Config.GateMode(e) .. " gate" end
	return e[7] or (def and def.name) or e[1]
end

local function pruneLinks()
	for i = #E.links, 1, -1 do
		local l = E.links[i]
		if not (entById(l[1]) and entById(l[2])) then table.remove(E.links, i) end
	end
end

-- connections: antlines (dotted along the panels), signs, or nothing - per source item (Connection visibility)
local function drawLinks()
	linkFolder:ClearAllChildren()
	for _, l in ipairs(E.links) do
		local _, ea = entById(l[1])
		local _, eb = entById(l[2])
		if ea and eb then
			local vis = Config.Options(ea).vis or "Antline"
			if vis == "Antline" then
				local segs = Config.AntlinePath(E.air, { ea[2], ea[3], ea[4], ea[5] }, { eb[2], eb[3], eb[4], eb[5] }, W, 0.25)
				if segs then
					for _, d in ipairs(Config.AntlineDots(segs)) do
						local dot, hole = Config.AntlineDot(d.cf, d.corner, Config.ANT_OFF, linkFolder)
						dot:SetAttribute("N", d.cf.LookVector)
						if hole then hole:SetAttribute("N", d.cf.LookVector) end
					end
				end
			elseif vis == "Signage" then
				for _, e in ipairs({ ea, eb }) do
					local fr = Config.ItemFrame(W, e)
					local sign = Config.BuildSign(fr, linkFolder)
					for _, p in ipairs(sign:GetChildren()) do p:SetAttribute("N", fr.LookVector) end
				end
			end
		end
	end
	E.lastCull = nil
end

-- editor copies: no tags, scripts or sounds, and no model names other scripts react to (TestElementsClient would
-- otherwise start funnel effects / beam hums on the editor's items, pedestal scripts would hook them...)
buildEntity = function(e, opts, origin)
	local ok, m = pcall(Config.BuildEntity, e, origin or W, opts)
	if not ok then
		warn("[PortalMapEditor] BuildEntity", e[1], m)
		return nil
	end
	if m then
		for _, t in ipairs(m:GetTags()) do m:RemoveTag(t) end
		for _, d in ipairs(m:GetDescendants()) do
			for _, t in ipairs(d:GetTags()) do d:RemoveTag(t) end
			if d:IsA("Sound") then
				d:Destroy()
			elseif d:IsA("BaseScript") then
				d.Enabled = false
			elseif d:IsA("Model") then
				d.Name = "EditorPiece"
			end
		end
	end
	return m
end

-- (declared above the do block) local updateCull -- forward (defined after rebuild)

rebuildEnts = function()
	entFolder:ClearAllChildren()
	E.entModels = {}
	for i, e in ipairs(E.ents) do
		local m = buildEntity(e, { editor = true, air = E.air })
		if m then
			Config.EachPart(m, function(p)
				p:SetAttribute("EntIndex", i)
				p:SetAttribute("BaseT", p.Transparency)
				p.CanCollide = false
			end)
			m.Parent = entFolder
			E.entModels[i] = m
		end
	end
	if H.buildPreviews then H.buildPreviews() end
	pruneLinks()
	drawLinks()
	E.lastCull = nil
	refreshSelection()
	if updateCull then updateCull() end
end

local function updateShadow()
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for k in pairs(E.air) do
		local x, y, z = parse(k)
		local v = Vector3.new(x, y, z)
		mn, mx = mn:Min(v), mx:Max(v)
	end
	if mn.X == math.huge then shadow.Transparency = 1 return end
	local size = (mx - mn + Vector3.new(1, 1, 1)) * CELL
	local center = (mn + mx) / 2 * CELL + W
	shadow.Size = Vector3.new(size.X + CELL, 0.2, size.Z + CELL)
	shadow.CFrame = CFrame.new(center.X + CELL * 0.6, W.Y + mn.Y * CELL - CELL / 2 - CELL * 1.6, center.Z + CELL * 0.4)
	shadow.Transparency = 0.72
end

-- Every panel is three flat layers that never poke past its own cell:
--   panel (the visible tile) / rim (the light grid line between tiles) / shell (the dark wall thickness on the cut edge)
rebuild = function()
	if E.gameView and X.buildGameView then X.buildGameView() return end -- game view shows the real chamber instead
	roomFolder:ClearAllChildren()
	E.faceParts = {}
	local camPos = cam.CFrame.Position
	local gap = E.gameView and 0 or 0.35
	local thick = SET.WALL_THICKNESS
	local holes = Config.HoleFaces(E.ents)
	for k in pairs(E.air) do
		local x, y, z = parse(k)
		for f = 1, 6 do
			local o = OFFS[f]
			if not E.air[key(x + o[1], y + o[2], z + o[3])] then
				local fk = faceKey(x, y, z, f)
				local portal, wallT = Config.FaceInfo(E.faces[fk])
				wallT = wallT and (f == 3 or f == 4)
				local tint = Config.TileTint(E.colors[fk], portal)
				local normal = -DIRS[f]
				local pcf = Config.FaceCFrame(W, x, y, z, f, 0.15)
				local show = (camPos - pcf.Position):Dot(normal) > 0
				local hole = holes[fk] == true
				local tr = (show and not hole) and 0 or 1
				local fp = { normal = normal, center = pcf.Position, x = x, y = y, z = z, f = f, portal = portal, wallT = wallT, tint = tint, shown = show, hole = hole }
				local panel = new("Part", {
					Anchored = true, CanCollide = false, CastShadow = false, Size = Vector3.new(CELL - gap, CELL - gap, 0.3), CFrame = pcf,
					Color = panelColor(fp), Material = Enum.Material.SmoothPlastic, Transparency = tr, CanQuery = show and not hole, Parent = roomFolder,
				})
				panel:SetAttribute("Face", fk)
				if E.textures[fk] then
					fp.tex = Config.ApplyTexture(panel, E.textures[fk], normal)
					if fp.tex then fp.tex.Transparency = tr end
				end
				local rim = new("Part", {
					Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false, Size = Vector3.new(CELL, CELL, 0.2),
					CFrame = Config.FaceCFrame(W, x, y, z, f, 0.4), Color = portal and C.RIM_WHITE or C.RIM_BLACK,
					Material = Enum.Material.SmoothPlastic, Transparency = tr, Parent = roomFolder,
				})
				local shell = new("Part", {
					Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false, Size = Vector3.new(CELL, CELL, thick),
					CFrame = Config.FaceCFrame(W, x, y, z, f, 0.5 + thick / 2), Color = C.SHELL,
					Material = Enum.Material.SmoothPlastic, Transparency = tr, Parent = roomFolder,
				})
				fp.panel, fp.parts = panel, { panel, rim, shell }
				E.faceParts[fk] = fp
			end
		end
	end
	for fk in pairs(E.sel) do
		if not E.faceParts[fk] then E.sel[fk] = nil end
	end
	if E.anchor and not E.faceParts[E.anchor.key] then E.anchor = nil end
	rebuildEnts()
	updateShadow()
end

-- after an item change: the whole room if the item cuts into it (doors, faith plates), else just the items
refreshItems = function(kind)
	if kind and needsRoom(kind) then rebuild() else rebuildEnts() end
end

-- cutaway: panels facing away from the camera (the walls nearest you) are hidden, like the Puzzle Maker
updateCull = function()
	local camPos = cam.CFrame.Position
	if E.lastCull and (camPos - E.lastCull).Magnitude < 0.05 then return end
	E.lastCull = camPos
	if E.gameView and X.cullGameView then X.cullGameView(camPos) end
	for _, fp in pairs(E.faceParts) do
		local show = (camPos - fp.center):Dot(fp.normal) > 0
		if show ~= fp.shown then
			fp.shown = show
			if not fp.hole then
				for _, p in ipairs(fp.parts) do p.Transparency = show and 0 or 1 end
				if fp.tex then fp.tex.Transparency = show and 0 or 1 end
				fp.panel.CanQuery = show
			end
		end
	end
	for i, m in pairs(E.entModels) do
		local e = E.ents[i]
		local fp = e and E.faceParts[faceKey(e[2], e[3], e[4], e[5])]
		local show = not fp or fp.shown
		if fp and fp.hole then
			-- the tile under it is gone (pit / alcove): use the facing of the surface it sits on
			show = (camPos - fp.center):Dot(fp.normal) > 0
		end
		if m:GetAttribute("Shown") ~= show then
			m:SetAttribute("Shown", show)
			Config.EachPart(m, function(p)
				p.Transparency = show and (p:GetAttribute("BaseT") or 0) or 1
				p.CanQuery = show
			end)
		end
		local pv = H.previews[i]
		if pv and pv:GetAttribute("Shown") ~= show then
			pv:SetAttribute("Shown", show)
			for _, p in ipairs(pv:GetChildren()) do
				if p:IsA("BasePart") then p.Transparency = show and (p:GetAttribute("BaseT") or 0) or 1 end
			end
		end
	end
	for _, p in ipairs(linkFolder:GetDescendants()) do
		local n = p:IsA("BasePart") and p:GetAttribute("N")
		if n then p.Transparency = ((camPos - p.Position):Dot(n) > 0) and 0 or 1 end
	end
end

applyCamera = function()
	cam.CFrame = CFrame.new(E.cTarget) * CFrame.Angles(0, E.cYaw, 0) * CFrame.Angles(E.cPitch, 0, 0) * CFrame.new(0, 0, E.cDist)
	local wcam = workspace.CurrentCamera
	if wcam and E.active and not E.playtest then
		wcam.CameraType = Enum.CameraType.Scriptable
		wcam.CFrame = cam.CFrame
		wcam.FieldOfView = cam.FieldOfView
	end
end

end
-- ==========================================
-- PICKING (rays through the camera at the pointer)
-- ==========================================
local pick, mouseRay, pickFace
do
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { roomFolder, entFolder, H.model }

	mouseRay = function()
		local m = pointerScreen()
		local r = workspace.CurrentCamera:ViewportPointToRay(m.X, m.Y)
		return r.Origin, r.Direction
	end

	-- only the room panels (dragging a faith plate target)
	local faceParams = RaycastParams.new()
	faceParams.FilterType = Enum.RaycastFilterType.Include
	faceParams.FilterDescendantsInstances = { roomFolder }
	pickFace = function()
		local origin, dir = mouseRay()
		local res = workspace:Raycast(origin, dir * 4000, faceParams)
		local fk = res and res.Instance:GetAttribute("Face")
		if not fk then return nil end
		local x, y, z, f = parseFace(fk)
		return { kind = "face", key = fk, x = x, y = y, z = z, f = f, pos = res.Position }
	end

	pick = function()
		local origin, dir = mouseRay()
		local res = workspace:Raycast(origin, dir * 4000, rayParams)
		if not res then return nil end
		local hk = res.Instance:GetAttribute("Handle")
		if hk then
			local a = res.Instance
			return { kind = "handle", hk = hk, index = a:GetAttribute("Index"), rot = a:GetAttribute("Rot"), side = a:GetAttribute("Side"), pos = res.Position }
		end
		local idx = res.Instance:GetAttribute("EntIndex")
		if idx then return { kind = "ent", index = idx, pos = res.Position } end
		local fk = res.Instance:GetAttribute("Face")
		if fk then
			local x, y, z, f = parseFace(fk)
			return { kind = "face", key = fk, x = x, y = y, z = z, f = f, pos = res.Position }
		end
		return nil
	end
end

-- ==========================================
-- CONNECT LINE (2D, drawn over the room like the Puzzle Maker)
-- ==========================================
-- thin dark elbow from the item's tile to the pointer (hollow square on the pointer). Over something it can connect
-- to, it snaps to that item's tile and turns into a thick bright line with a filled square on each end.
local connectGui = {}
do
	local DIM, LIT = rgb(44, 122, 124), rgb(0, 230, 232)
	local layer = new("Frame", { Name = "ConnectLayer", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = canvas })
	local function piece() return new("Frame", { BorderSizePixel = 0, Visible = false, ZIndex = 2, Parent = layer }) end
	local hBar, vBar, startSq, endSq = piece(), piece(), piece(), piece()
	local endStroke = new("UIStroke", { Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = endSq })

	-- a point in the editor room -> canvas position (nil if it's behind the camera)
	function connectGui.project(p)
		local v = workspace.CurrentCamera:WorldToViewportPoint(p)
		if v.Z <= 0.05 then return nil end
		return (Vector2.new(v.X, v.Y) - GuiService:GetGuiInset() - canvas.AbsolutePosition) / uiScale.Scale
	end

	function connectGui.hide()
		hBar.Visible, vBar.Visible, startSq.Visible, endSq.Visible = false, false, false, false
	end

	-- across from a, then up / down to b
	function connectGui.draw(a, b, lit)
		local t = lit and 4 or 1.5
		local col = lit and LIT or DIM
		hBar.BackgroundColor3, vBar.BackgroundColor3 = col, col
		hBar.Position = px(math.min(a.X, b.X) - t / 2, a.Y - t / 2)
		hBar.Size = px(math.abs(b.X - a.X) + t, t)
		vBar.Position = px(b.X - t / 2, math.min(a.Y, b.Y) - t / 2)
		vBar.Size = px(t, math.abs(b.Y - a.Y) + t)
		startSq.BackgroundColor3 = LIT
		startSq.Size = px(11, 11)
		startSq.Position = px(a.X - 5.5, a.Y - 5.5)
		local s = lit and 17 or 14
		endSq.Size = px(s, s)
		endSq.Position = px(b.X - s / 2, b.Y - s / 2)
		endSq.BackgroundColor3 = LIT
		endSq.BackgroundTransparency = lit and 0 or 1
		endStroke.Color = DIM
		endStroke.Transparency = lit and 1 or 0
		hBar.Visible, vBar.Visible, endSq.Visible, startSq.Visible = true, true, true, lit
	end

	-- the pink heart that pops up on the item you just connected to
	function connectGui.heart(p)
		if not p then return end
		local h = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = px(p.X, p.Y), Size = px(90, 90), BackgroundTransparency = 1,
			Text = "♥", FontFace = FONT.UI, TextSize = 6, TextColor3 = rgb(238, 132, 192), TextStrokeColor3 = rgb(160, 64, 118),
			TextStrokeTransparency = 0.4, ZIndex = 3, Parent = layer })
		TweenService:Create(h, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 72 }):Play()
		task.delay(0.65, function()
			local tw = TweenService:Create(h, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 })
			tw:Play()
			tw.Completed:Wait()
			h:Destroy()
		end)
	end
end

local Team, slotValid
do
-- ==========================================
-- TEAM BUILDERS (markers for everyone else on the team)
-- ==========================================
-- A coloured circle + their name (BillboardGui, always on top) at whatever they're pointing at. The shade follows
-- what's under it: darker on white tiles, lighter on black tiles, full colour + white ring on items, full colour + dark
-- ring out in the grey void. Behind a wall from your view it goes see-through; idle (no pointer) it shrinks.
Team = { markers = {} }
do
local teamBox -- the list in the top right (built below)
local function memberInfo(userId)
	for _, m in ipairs(E.team and E.team.members or {}) do
		if m.id == userId then return m end
	end
end
local function teamSize() return E.team and #E.team.members or 0 end
local function clearMarkers()
	for _, mk in pairs(Team.markers) do mk.part:Destroy() end
	Team.markers = {}
end
local function markerFor(userId)
	local mk = Team.markers[userId]
	if mk then return mk end
	local info = memberInfo(userId)
	if not info then return nil end
	local part = new("Part", { Name = "TeamMarker", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Transparency = 1, Size = Vector3.one * 0.2, Parent = teamFolder })
	local bb = new("BillboardGui", { Adornee = part, Size = px(220, 64), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 100000, ResetOnSpawn = false, Parent = part })
	local dot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 14), Size = px(22, 22), BorderSizePixel = 0, Parent = bb })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
	local stroke = new("UIStroke", { Thickness = 3, Parent = dot })
	local name = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = px(220, 24), BackgroundTransparency = 1,
		Text = info.name, FontFace = FONT.P2, TextSize = 20, TextStrokeTransparency = 0.15, Parent = bb })
	mk = { part = part, bb = bb, dot = dot, stroke = stroke, name = name, pos = nil, want = nil, surf = "none", idle = true, seen = 0, occluded = false, occT = 0 }
	Team.markers[userId] = mk
	return mk
end
local function styleMarker(mk, info)
	local base = Config.TEAM_COLORS[info and info.color or 1] or Config.TEAM_COLORS[1]
	local black, white = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
	local fill, ring, text, textStroke, size
	if mk.play then
		fill, ring, text, textStroke, size = base:Lerp(rgb(150), 0.6), rgb(40), rgb(235), rgb(20), 16
	elseif mk.surf == "white" then
		fill, ring, text, textStroke, size = base:Lerp(black, 0.35), rgb(20), base:Lerp(black, 0.45), white, 22
	elseif mk.surf == "black" then
		fill, ring, text, textStroke, size = base:Lerp(white, 0.35), white, base:Lerp(white, 0.4), black, 22
	elseif mk.surf == "item" then
		fill, ring, text, textStroke, size = base, white, base, black, 26
	else
		fill, ring, text, textStroke, size = base, rgb(20), white, base:Lerp(black, 0.5), 22
	end
	if mk.idle then size = size * 0.7 end
	local fade = mk.occluded and 0.45 or 0
	if os.clock() - mk.seen > 5 then fade = 0.7 end
	mk.dot.BackgroundColor3, mk.stroke.Color, mk.dot.Size = fill, ring, px(size, size)
	mk.dot.BackgroundTransparency, mk.stroke.Transparency = fade, fade
	mk.name.TextColor3, mk.name.TextStrokeColor3 = text, textStroke
	mk.name.TextTransparency = fade
	mk.name.Text = (info and info.name or "?") .. (mk.play and " (testing)" or "")
	mk.name.Visible = ES("edTeamNames", "Enabled") == "Enabled"
end
local occParams = RaycastParams.new()
occParams.FilterType = Enum.RaycastFilterType.Include
occParams.FilterDescendantsInstances = { roomFolder }
local function updateMarkers(dt)
	local camPos = cam.CFrame.Position
	local now = os.clock()
	for userId, mk in pairs(Team.markers) do
		local info = memberInfo(userId)
		if not info then
			mk.part:Destroy()
			Team.markers[userId] = nil
		elseif mk.want then
			mk.pos = mk.pos and mk.pos:Lerp(mk.want, 1 - math.exp(-14 * dt)) or mk.want
			mk.part.CFrame = CFrame.new(mk.pos)
			if now - mk.occT > 0.12 then
				mk.occT = now
				local d = mk.pos - camPos
				local res = d.Magnitude > 0.5 and workspace:Raycast(camPos, d.Unit * math.max(d.Magnitude - 1.5, 0), occParams)
				mk.occluded = res ~= nil and res ~= false
			end
			styleMarker(mk, info)
		end
	end
end

-- top-right list of who's building
teamBox = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = R(46, 40), Size = px(240, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = C.CTX_BG, BackgroundTransparency = 0.2, BorderSizePixel = 0, Visible = false, ZIndex = 6, Parent = canvas })
new("UIStroke", { Color = C.CTX_EDGE, Thickness = 1, Transparency = 0.3, Parent = teamBox })
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = teamBox })
new("UIPadding", { PaddingBottom = UDim.new(0, 4), Parent = teamBox })
local function refreshTeamBox()
	for _, c in ipairs(teamBox:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	if teamSize() < 2 then teamBox.Visible = false return end
	teamBox.Visible = true
	local head = new("Frame", { Size = px(240, 20), BackgroundColor3 = C.CTX_HEAD, BackgroundTransparency = 0.35, BorderSizePixel = 0, LayoutOrder = 0, ZIndex = 7, Parent = teamBox })
	new("TextLabel", { Size = px(232, 20), BackgroundTransparency = 1, Text = "TEAM BUILDERS", FontFace = FONT.UI_REG, TextSize = 14,
		TextColor3 = rgb(236), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 8, Parent = head })
	for i, m in ipairs(E.team.members) do
		local row = new("Frame", { Size = px(240, 26), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 7, Parent = teamBox })
		local d = new("Frame", { Position = px(10, 6), Size = px(14, 14), BackgroundColor3 = Config.TEAM_COLORS[m.color] or Config.TEAM_COLORS[1], BorderSizePixel = 0, ZIndex = 8, Parent = row })
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = d })
		new("UIStroke", { Color = rgb(30), Thickness = 1.5, Parent = d })
		new("TextLabel", { Position = px(32, 0), Size = px(200, 26), BackgroundTransparency = 1,
			Text = m.name .. (m.host and "  (owner)" or "") .. (m.id == player.UserId and "  - you" or ""),
			FontFace = FONT.UI_REG, TextSize = 15, TextColor3 = C.CTX_TEXT, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8, Parent = row })
	end
end
Team.memberInfo = memberInfo
Team.teamSize = teamSize
Team.clearMarkers = clearMarkers
Team.markerFor = markerFor
Team.updateMarkers = updateMarkers
Team.refreshTeamBox = refreshTeamBox
end

local function slotTaken(x, y, z, f, ignore)
	for i, e in ipairs(E.ents) do
		if i ~= ignore and e[2] == x and e[3] == y and e[4] == z and e[5] == f then return true end
	end
	return false
end

-- can an item of this kind sit on this panel?
slotValid = function(kind, hit, ignore)
	if not hit or hit.kind ~= "face" then return false end
	local def = Config.ENTITY_TYPES[kind]
	if not def then return false end
	if not Config.MountOk(def, hit.f) then return false end
	if def.needsFloor and E.air[key(hit.x, hit.y - 1, hit.z)] then return false end -- doors stand on the floor
	return not slotTaken(hit.x, hit.y, hit.z, hit.f, ignore)
end

end
local duplicateItem
local pushUndo, undo, redo, moveSurfaces, togglePortalable, setTileColor, paintSelection, deleteItem, rotateItem, cancelLink, startLink, linkPair, completeLink, selCount, selectRect, selectAll
do
-- ==========================================
-- EDITING
-- ==========================================
-- every change bumps E.rev; the frame loop sends the chamber to the team when it moves on
pushUndo = function(before)
	table.insert(E.undo, before or snapshot())
	if #E.undo > 60 then table.remove(E.undo, 1) end
	table.clear(E.redo)
	E.dirty = true
	E.stale = true
	E.rev += 1
end

local function restore(sn)
	E.air, E.faces, E.colors, E.ents, E.links = sn.air, sn.faces, sn.colors or {}, sn.ents, sn.links or {}
	E.textures, E.chips = sn.textures or {}, sn.chips or {}
	if Pal.refreshChips and Pal.tab == "chips" then Pal.refreshChips() end
	E.sel, E.selItem, E.anchor = {}, nil, nil
	rebuild()
end
undo = function()
	if #E.undo == 0 then sfx("Error") return end
	table.insert(E.redo, snapshot())
	restore(table.remove(E.undo))
	E.dirty, E.stale = true, true
	E.rev += 1
	sfx("Click")
end
redo = function()
	if #E.redo == 0 then sfx("Error") return end
	table.insert(E.undo, snapshot())
	restore(table.remove(E.redo))
	E.dirty, E.stale = true, true
	E.rev += 1
	sfx("Click")
end

-- what the selected surfaces are made of (picks the carve / extrude sound)
local function selectionMaterial()
	for fk in pairs(E.sel) do
		for _, e in ipairs(E.ents) do
			if e[1] == "toxicgoo" and faceKey(e[2], e[3], e[4], e[5]) == fk then return "Water" end
		end
	end
	for fk in pairs(E.sel) do
		if not Config.FaceInfo(E.faces[fk]) then return "Metal" end
	end
	return "Tile"
end

-- + pulls the selected panels toward you (extrude: fills the cell in), - pushes them away (carve: digs the next cell out)
moveSurfaces = function(sign)
	if next(E.sel) == nil then flash("Select a surface first.") sfx("Error") return end
	local mat = selectionMaterial()
	local before = snapshot()
	local newAir = table.clone(E.air)
	local moves = {}
	for fk in pairs(E.sel) do
		local x, y, z, f = parseFace(fk)
		local o = OFFS[f]
		if sign < 0 then
			local nx, ny, nz = x + o[1], y + o[2], z + o[3]
			if not inBounds(nx, ny, nz) then flash("That's the edge of the building area.") sfx("Error") return end
			newAir[key(nx, ny, nz)] = true
			moves[fk] = faceKey(nx, ny, nz, f)
		else
			newAir[key(x, y, z)] = nil
			moves[fk] = faceKey(x - o[1], y - o[2], z - o[3], f)
		end
	end
	if next(newAir) == nil then flash("A chamber can't be filled in completely.") sfx("Error") return end
	local newEnts = {}
	for _, e in ipairs(E.ents) do
		local ne = table.clone(e)
		local mv = moves[faceKey(e[2], e[3], e[4], e[5])]
		if mv then
			local x, y, z = parseFace(mv)
			ne[2], ne[3], ne[4] = x, y, z
		end
		-- a faith plate's target moves with its panel
		local fo = ne[1] == "faithplate" and type(ne[10]) == "table" and ne[10]
		if fo and fo.fx then
			local mvT = moves[faceKey(fo.fx, fo.fy, fo.fz, fo.ff)]
			if mvT then
				fo = table.clone(fo)
				fo.fx, fo.fy, fo.fz = parseFace(mvT)
				ne[10] = fo
			end
		end
		local o = OFFS[ne[5]]
		local def = Config.ENTITY_TYPES[ne[1]]
		local ok = newAir[key(ne[2], ne[3], ne[4])] and not newAir[key(ne[2] + o[1], ne[3] + o[2], ne[4] + o[3])]
		if ok and def.needsFloor and newAir[key(ne[2], ne[3] - 1, ne[4])] then ok = false end
		if ok then
			table.insert(newEnts, ne)
		elseif def.mandatory then
			flash("The entry and exit doors can't be removed. Move them out of the way first.")
			sfx("Error")
			return
		end
	end
	local newFaces, newColors, newTex = {}, {}, {}
	for fk, v in pairs(E.faces) do newFaces[moves[fk] or fk] = v end
	for fk, v in pairs(E.colors) do newColors[moves[fk] or fk] = v end
	for fk, v in pairs(E.textures) do newTex[moves[fk] or fk] = v end
	pushUndo(before)
	E.air, E.ents, E.faces, E.colors, E.textures = newAir, newEnts, newFaces, newColors, newTex
	E.sel, E.selItem, E.anchor = {}, nil, nil
	for _, nk in pairs(moves) do
		local x, y, z, f = parseFace(nk)
		if isFace(x, y, z, f) then E.sel[nk] = true end
	end
	rebuild()
	sfx((sign < 0 and "Carve" or "Extrude") .. mat)
end

togglePortalable = function()
	if next(E.sel) == nil then sfx("Error") return end
	local all = true
	for fk in pairs(E.sel) do if not Config.FaceInfo(E.faces[fk]) then all = false end end
	pushUndo()
	for fk in pairs(E.sel) do
		local _, wallT = Config.FaceInfo(E.faces[fk])
		E.faces[fk] = Config.FaceValue(not all, wallT)
	end
	rebuild()
	sfx("Click")
end

-- tile colours (nil = no colour)
setTileColor = function(idx)
	if next(E.sel) == nil then flash("Select a surface first.") sfx("Error") return end
	pushUndo()
	for fk in pairs(E.sel) do E.colors[fk] = idx end
	if idx then E.lastColor = idx end
	rebuild()
	sfx("Click")
end
paintSelection = function() setTileColor(E.lastColor or 1) end

deleteItem = function()
	local e = E.selItem and E.ents[E.selItem]
	if not e then sfx("Error") return end
	if Config.ENTITY_TYPES[e[1]].mandatory then
		flash("The entry and exit doors can be moved, but they can't be deleted or copied.")
		sfx("Error")
		return
	end
	pushUndo()
	table.remove(E.ents, E.selItem)
	E.selItem = nil
	refreshItems(e[1])
	sfx("Click")
end

-- Ctrl+D / item menu > Duplicate: the same item with the same options on the nearest free panel facing the same way
duplicateItem = function()
	local e = E.selItem and E.ents[E.selItem]
	if not e then flash("Select an item first.") sfx("Error") return end
	if Config.ENTITY_TYPES[e[1]].mandatory then
		flash("The entry and exit doors can be moved, but they can't be deleted or copied.")
		sfx("Error")
		return
	end
	if #E.ents >= LIM.ents then flash("That's the item limit.") sfx("Error") return end
	local best, bestD
	for r = 1, 6 do
		for dx = -r, r do
			for dy = -r, r do
				for dz = -r, r do
					if math.max(math.abs(dx), math.abs(dy), math.abs(dz)) == r then
						local hit = { kind = "face", x = e[2] + dx, y = e[3] + dy, z = e[4] + dz, f = e[5] }
						if isFace(hit.x, hit.y, hit.z, hit.f) and slotValid(e[1], hit) then
							-- nearest first; same height wins ties (copies line up along the floor / wall)
							local d = dx * dx + dz * dz + dy * dy * 1.5
							if not bestD or d < bestD then best, bestD = hit, d end
						end
					end
				end
			end
		end
		if best then break end
	end
	if not best then flash("There's no free panel nearby for a copy.") sfx("Error") return end
	pushUndo()
	local c = table.clone(e)
	c[2], c[3], c[4] = best.x, best.y, best.z
	c[8] = newId()
	if type(c[10]) == "table" then
		local o = table.clone(c[10])
		o.label = nil -- gets its own label (button2, ...)
		c[10] = next(o) and o or nil
	end
	table.insert(E.ents, c)
	Config.AutoLabel(E.ents)
	E.selItem, E.sel = #E.ents, {}
	refreshItems(c[1])
	flash("Copied " .. string.lower(Config.ENTITY_TYPES[c[1]].name) .. ".")
	sfx("Click")
end

rotateItem = function()
	local e = E.selItem and E.ents[E.selItem]
	if not e or Config.ENTITY_TYPES[e[1]].needsFloor then sfx("Error") return end
	pushUndo()
	e[6] = ((e[6] or 0) + 1) % 4
	rebuildEnts()
	sfx("Click")
end

-- ----- connecting items -----
cancelLink = function()
	if not E.linking then return end
	E.linking = nil
	connectGui.hide()
	H.highlight(nil)
	tooltip.Text = ""
end

startLink = function()
	local e = E.selItem and E.ents[E.selItem]
	if not e or not (canSource(e) or canTarget(e)) then
		flash("Select a button, a logic gate or a test element first.")
		sfx("Error")
		return
	end
	E.linking = e[8]
	tooltip.Text = "Click an item to connect (Esc / B cancels)"
	flash("Click the item to connect it to.")
	sfx("Click")
end

local function linked(a, b)
	for _, l in ipairs(E.links) do
		if l[1] == a and l[2] == b then return true end
	end
	return false
end

-- the item you started from drives the one you click, unless only the other way round makes sense
linkPair = function(a, b)
	if canSource(a) and canTarget(b) then return a, b end
	if canSource(b) and canTarget(a) then return b, a end
	return nil
end

completeLink = function(index)
	local b = E.ents[index]
	local _, a = entById(E.linking)
	if not a or not b or a == b then cancelLink() return end
	local src, dst = linkPair(a, b)
	if not src then
		flash("Those two can't be connected. Something has to drive the other one.")
		sfx("Error")
		return
	end
	if linked(src[8], dst[8]) then
		flash("They're already connected.")
		sfx("Error")
		cancelLink()
		return
	end
	if linked(dst[8], src[8]) then
		flash("They're already connected the other way round.")
		sfx("Error")
		cancelLink()
		return
	end
	pushUndo()
	table.insert(E.links, { src[8], dst[8] })
	cancelLink()
	-- like the Puzzle Maker: the item you connected to gets selected and a heart pops up on it
	E.selItem, E.sel = index, { [faceKey(b[2], b[3], b[4], b[5])] = true }
	rebuildEnts()
	local bm = E.entModels[index]
	if bm then connectGui.heart(connectGui.project(bm:GetBoundingBox().Position)) end
	flash(("Connected %s to %s."):format(entLabel(src), entLabel(dst)))
	sfx("Click")
end

selCount = function()
	local n = 0
	for _ in pairs(E.sel) do n += 1 end
	return n
end

-- select the panels of one wall between two panels. additive keeps what is already selected.
selectRect = function(a, b, additive)
	local axis = (a.f <= 2 and 1) or (a.f <= 4 and 2) or 3
	local ca, cb = { a.x, a.y, a.z }, { b.x, b.y, b.z }
	if b.f ~= a.f or ca[axis] ~= cb[axis] then return false end
	local lo, hi = {}, {}
	for i = 1, 3 do lo[i], hi[i] = math.min(ca[i], cb[i]), math.max(ca[i], cb[i]) end
	if not additive then E.sel = {} end
	for fk, fp in pairs(E.faceParts) do
		if fp.f == a.f then
			local c = { fp.x, fp.y, fp.z }
			local inside = c[axis] == ca[axis]
			for i = 1, 3 do
				if i ~= axis and (c[i] < lo[i] or c[i] > hi[i]) then inside = false end
			end
			if inside then E.sel[fk] = true end
		end
	end
	refreshSelection()
	return true
end

selectAll = function()
	E.sel, E.selItem = {}, nil
	for fk in pairs(E.faceParts) do E.sel[fk] = true end
	refreshSelection()
	sfx("SelectEnd")
end

end
-- ==========================================
-- PALETTE (slides in from the left strip): Items / Textures / Meshes / My Chips tabs
-- ==========================================
-- Which tabs you get depends on the editor mode (Options > Editor > Editor Mode, or File > Editor mode):
--   Simple        Items
--   Intermediate  Items, Textures, Meshes
--   Advanced      Items, Textures, Meshes, My Chips (+ item labels and nudging in the item menu)
-- Textures come from ReplicatedStorage.PortalAssets.Textures (Textures / Decals / parts with one) or an asset id.
-- Meshes come from ReplicatedStorage.PortalAssets.Meshes (models / parts) or a mesh asset id (+ optional texture id).
do
	local palWrap = new("Frame", { Name = "Palette", Position = L(0, 0), Size = px(420, REF_H), BackgroundTransparency = 1, ZIndex = 5, Parent = canvas })
	Pal.wrap = palWrap

	local palette = ui(new("Frame", { Position = L(27, 163), Size = px(375, 753), BackgroundColor3 = C.PAL_BG, BorderSizePixel = 0, Active = true, ZIndex = 5, Parent = palWrap }))
	Pal.body = palette
	new("UIStroke", { Color = C.PAL_EDGE, Thickness = 1, Parent = palette })

	local itemName = new("TextLabel", { Position = px(8, 733), Size = px(359, 18), BackgroundTransparency = 1, Text = "", FontFace = FONT.UI_REG,
		TextSize = 12, TextColor3 = rgb(30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = palette })
	Pal.itemName = itemName

	local function page(id)
		local f = new("Frame", { Name = id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = id == "items", ZIndex = 6, Parent = palette })
		Pal.pages[id] = f
		return f
	end

	-- ----- tabs -----
	local TABS = {
		{ id = "items", text = "Items", mode = 1 },
		{ id = "textures", text = "Textures", mode = 2 },
		{ id = "meshes", text = "Meshes", mode = 2 },
		{ id = "chips", text = "My Chips", mode = 3 },
	}
	local MODE_LEVEL = { Simple = 1, Intermediate = 2, Advanced = 3 }
	function Pal.level() return MODE_LEVEL[ES("edMode", "Simple")] or 1 end
	for _, t in ipairs(TABS) do
		local b = ui(new("TextButton", { Size = px(90, 28), BackgroundColor3 = C.PAL_BG, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
			Selectable = false, ZIndex = 5, Parent = palWrap }))
		new("UIStroke", { Color = C.PAL_EDGE, Thickness = 1, Parent = b })
		local cover = new("Frame", { Position = px(0, 26), Size = px(90, 4), BackgroundColor3 = C.PAL_BG, BorderSizePixel = 0, ZIndex = 7, Parent = b })
		local label = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = t.text, FontFace = FONT.UI_REG, TextSize = 15,
			TextColor3 = rgb(40), ZIndex = 7, Parent = b })
		Pal.tabs[t.id] = { button = b, cover = cover, label = label, def = t }
		hoverable(b, function() if Pal.tab ~= t.id then b.BackgroundColor3 = rgb(232) end sound("SOUND_HOVER") end,
			function() if Pal.tab ~= t.id then b.BackgroundColor3 = rgb(206, 208, 206) end end)
		onClick(b, function() Pal.select(t.id) sfx("Click") end)
	end

	function Pal.layoutTabs()
		local lvl = Pal.level()
		local x = 27
		for _, t in ipairs(TABS) do
			local tb = Pal.tabs[t.id]
			local shown = lvl >= t.mode
			tb.button.Visible = shown
			if shown then
				tb.button.Position = L(x, 136)
				x += 94
			end
			local on = Pal.tab == t.id
			tb.button.BackgroundColor3 = on and C.PAL_BG or rgb(206, 208, 206)
			tb.cover.Visible = on
			tb.label.TextColor3 = on and rgb(40) or rgb(105)
		end
		if lvl < (Pal.tabs[Pal.tab] and Pal.tabs[Pal.tab].def.mode or 1) then Pal.select("items") end
	end

	function Pal.select(id)
		if not Pal.pages[id] then return end
		Pal.tab = id
		for pid, f in pairs(Pal.pages) do f.Visible = pid == id end
		itemName.Text = ""
		Pal.layoutTabs()
		if Pal.onShow[id] then Pal.onShow[id]() end
	end
	Pal.onShow = {}

	-- search box at the top of a page: calls filter(query) as you type
	local function searchBox(parent, placeholder, filter)
		local box = new("TextBox", { Position = px(7, 6), Size = px(361, 30), BackgroundColor3 = rgb(255), BorderSizePixel = 0, Text = "",
			PlaceholderText = placeholder, FontFace = FONT.UI_REG, TextSize = 16, TextColor3 = rgb(25), PlaceholderColor3 = rgb(150),
			TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 7, Parent = parent })
		new("UIStroke", { Color = C.TILE_LINE, Thickness = 1, Parent = box })
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = box })
		box:GetPropertyChangedSignal("Text"):Connect(function() filter(box.Text:lower()) end)
		return box
	end
	local function grid(parent, y, h, cellH)
		local sc = new("ScrollingFrame", { Position = px(7, y), Size = px(364, h), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 4, ScrollBarImageColor3 = rgb(170, 176, 172), AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = px(0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y, SelectionGroup = true, ZIndex = 6, Parent = parent })
		new("UIGridLayout", { CellSize = px(90, cellH or 91), CellPadding = px(0, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sc })
		return sc
	end
	local function smallButton(parent, pos, size, text, fn, blue)
		local b = new("TextButton", { Position = pos, Size = size, BackgroundColor3 = blue and rgb(77, 128, 151) or rgb(214, 218, 216), BorderSizePixel = 0,
			AutoButtonColor = true, Text = text, FontFace = FONT.P2, TextSize = 16, TextColor3 = blue and rgb(245) or rgb(25), ZIndex = 7, Parent = parent })
		hoverable(b, function() sound("SOUND_HOVER") end, function() end)
		onClick(b, function() sfx("Click") fn() end)
		return b
	end
	local function inputBox(parent, pos, size, placeholder)
		local b = new("TextBox", { Position = pos, Size = size, BackgroundColor3 = rgb(255), BorderSizePixel = 0, Text = "", PlaceholderText = placeholder,
			FontFace = FONT.UI_REG, TextSize = 15, TextColor3 = rgb(25), PlaceholderColor3 = rgb(150), ClearTextOnFocus = false, ZIndex = 7, Parent = parent })
		new("UIStroke", { Color = C.TILE_LINE, Thickness = 1, Parent = b })
		return b
	end
	local function note(parent, pos, size, text)
		return new("TextLabel", { Position = pos, Size = size, BackgroundTransparency = 1, Text = text, FontFace = FONT.UI_REG, TextSize = 13,
			TextColor3 = rgb(95), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 7, Parent = parent })
	end
	local function frameModel(vp, model)
		local vcam = new("Camera", { FieldOfView = 30, Parent = vp })
		vp.CurrentCamera = vcam
		local cf, size = model:GetBoundingBox()
		local dir = Vector3.new(1, 0.75, 1).Unit
		vcam.CFrame = CFrame.lookAt(cf.Position + dir * (size.Magnitude * 1.9 + 2), cf.Position)
	end
	local function paletteTile(parent, order, name)
		local tile = new("TextButton", { BackgroundColor3 = C.TILE, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = order, ZIndex = 6, Parent = parent })
		tile:SetAttribute("PalTile", true)
		tile:SetAttribute("Search", name:lower())
		new("UIStroke", { Color = C.TILE_LINE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = tile })
		return tile
	end
	local function filterTiles(sc, q)
		for _, c in ipairs(sc:GetChildren()) do
			if c:IsA("GuiButton") and c:GetAttribute("Search") then
				c.Visible = q == "" or string.find(c:GetAttribute("Search"), q, 1, true) ~= nil
			end
		end
	end

	-- ----- ITEMS -----
	local itemsPage = page("items")
	local scroller = grid(itemsPage, 5, 728)
	Pal.scroller = scroller

	local function setPalette(open)
		Pal.awayT = nil
		if Pal.open == open then return end
		Pal.open = open
		if Pal.tween then Pal.tween:Cancel() end
		Pal.tween = TweenService:Create(palWrap, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = L(open and 0 or -430, 0) })
		Pal.tween:Play()
		for _, p in ipairs(stripParts) do p.BackgroundColor3 = open and C.STRIP_OPEN or C.STRIP_SHUT end
		if not open then
			itemName.Text = ""
			local so = GuiService.SelectedObject
			if so and so:IsDescendantOf(palWrap) then GuiService.SelectedObject = nil end
		end
	end
	Pal.set = setPalette
	function Pal.selecting()
		local so = GuiService.SelectedObject
		return so ~= nil and so:IsDescendantOf(palWrap)
	end
	leftStrip.MouseEnter:Connect(function()
		if E.active and not E.carry and not Pal.open and E.pointerMode == "mouse" then setPalette(true) sound("SOUND_HOVER") end
	end)
	onClick(leftStrip, function() setPalette(not Pal.open) sfx("Click") end)

	-- the grip strip on the palette's right side (click to tuck it away)
	local palGrip = ui(new("TextButton", { Position = L(402, 163), Size = px(12, 759), BackgroundColor3 = C.STRIP_OPEN, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "", Selectable = false, ZIndex = 5, Parent = palWrap }))
	for i = 0, 1 do new("Frame", { Position = px(4 + i * 3, 368), Size = px(1, 24), BackgroundColor3 = C.GRIP, BorderSizePixel = 0, ZIndex = 6, Parent = palGrip }) end
	onClick(palGrip, function() setPalette(false) sfx("Click") end)

	function Pal.startCarry(item)
		if E.carry then return end
		E.carry = item
		itemName.Text = string.upper(item.name)
		if E.pointerMode == "pad" or GuiService.SelectedObject ~= nil then
			-- controller: the item now follows the cursor, A places it. The A press that picked it doesn't count.
			usePad()
			E.carryArm = padDown(Enum.KeyCode.ButtonA)
			GuiService.SelectedObject = nil
			setPalette(false)
			local vp = viewportSize()
			if E.pointer.X < vp.X * 0.3 then E.pointer = vp / 2 end
		else
			E.carryArm = nil
		end
	end

	function Pal.togglePad()
		if Pal.selecting() then
			GuiService.SelectedObject = nil
			setPalette(false)
			sfx("Click")
			return
		end
		setPalette(true)
		local first
		local sc = Pal.pages[Pal.tab]
		for _, c in ipairs(sc:GetDescendants()) do
			if c:IsA("GuiButton") and c.Visible and (not first or c.LayoutOrder < first.LayoutOrder) then first = c end
		end
		if first then GuiService.SelectedObject = first end
		sfx("Click")
	end

	-- a tile you pick up and drop in the room (items and meshes)
	local function carryTile(tile, item)
		hoverable(tile, function()
			tile.BackgroundColor3 = C.TILE_HI
			itemName.Text = string.upper(item.name)
			sound("SOUND_HOVER")
		end, function()
			tile.BackgroundColor3 = C.TILE
			if not E.carry then itemName.Text = "" end
		end)
		local function pickUp() Pal.startCarry(item) sfx("Click") end
		tile.MouseButton1Down:Connect(pickUp)
		CLICK[tile] = pickUp -- controller cursor
		tile.Activated:Connect(function() -- controller selection (D-pad + A)
			if not E.carry and (E.pointerMode == "pad" or GuiService.SelectedObject == tile) then pickUp() end
		end)
	end

	function Pal.build()
		for _, c in ipairs(scroller:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		local items = {}
		for _, kind in ipairs(PALETTE_ORDER) do
			local def = Config.ENTITY_TYPES[kind]
			if def and not def.mandatory and (def.tier or 1) <= Pal.level() then
				if kind == "cube" then
					local variants = Config.CubeVariants()
					if #variants == 0 then table.insert(items, { kind = "cube", name = "Weighted Storage Cube" }) end
					for _, v in ipairs(variants) do table.insert(items, { kind = "cube", variant = v, name = v }) end
				else
					table.insert(items, { kind = kind, name = def.name })
				end
			end
		end
		for i, item in ipairs(items) do
			local tile = paletteTile(scroller, i, item.name)
			local mount = Config.ENTITY_TYPES[item.kind].mount
			local face = (mount == "ceiling" and 3) or (mount == "wall" and 2) or 4
			local m = buildEntity({ item.kind, 0, 0, 0, face, 0, item.variant }, { editor = true }, Vector3.zero)
			if m then
				local vp = new("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = rgb(180), LightDirection = Vector3.new(-0.4, -1, -0.6), ZIndex = 7, Parent = tile })
				m.Parent = new("WorldModel", { Parent = vp }) -- rigged / skinned meshes pose properly in a WorldModel
				frameModel(vp, m)
			else
				new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = item.name, FontFace = FONT.UI_REG, TextSize = 12,
					TextColor3 = rgb(40), TextWrapped = true, ZIndex = 7, Parent = tile })
			end
			carryTile(tile, item)
		end
		-- the other tabs fill in when you first open them
		table.clear(Pal.built)
		Pal.layoutTabs()
		if Pal.tab ~= "items" and Pal.onShow[Pal.tab] then Pal.onShow[Pal.tab]() end
	end

	-- ----- TEXTURES + MESHES: Toolbox (Creator Store) search, or what's in PortalAssets -----
	-- each page: search box, TOOLBOX / IN GAME switch, a results grid, then its own id boxes and buttons
	local function sourcePage(id, placeholder, libraryOnly)
		local pg = page(id)
		local st = { src = libraryOnly and "library" or "toolbox", query = "", page = 0, token = 0 }
		st.grid = libraryOnly and grid(pg, 42, 540, 104) or grid(pg, 74, 508, 104)
		st.status = note(pg, px(14, 84), px(340, 80), "")
		st.status.ZIndex = 8
		st.search = searchBox(pg, placeholder, function(q)
			st.query = q
			if st.src == "library" then
				filterTiles(st.grid, q)
			else
				-- the toolbox searches once you stop typing
				st.token += 1
				local my = st.token
				task.delay(0.7, function() if my == st.token and st.src == "toolbox" then st.run(false) end end)
			end
		end)
		st.buttons = {}
		for i, sdef in ipairs(libraryOnly and {} or { { "toolbox", "TOOLBOX" }, { "library", "IN GAME" } }) do
			local b = smallButton(pg, px(7 + (i - 1) * 183, 42), px(178, 26), sdef[2], function()
				if st.src == sdef[1] then return end
				st.src = sdef[1]
				st.paint()
				st.run(false)
			end)
			st.buttons[sdef[1]] = b
		end
		function st.paint()
			for k, b in pairs(st.buttons) do
				b.BackgroundColor3 = k == st.src and rgb(77, 128, 151) or rgb(214, 218, 216)
				b.TextColor3 = k == st.src and rgb(245) or rgb(25)
			end
		end
		function st.clear()
			for _, c in ipairs(st.grid:GetChildren()) do
				if c:IsA("GuiObject") then c:Destroy() end
			end
		end
		st.paint()
		return pg, st
	end

	-- a toolbox result tile: thumbnail + name
	local function toolboxTile(st, order, r, onPick)
		local tile = paletteTile(st.grid, order, r.name)
		new("ImageLabel", { Position = px(10, 4), Size = px(70, 70), BackgroundColor3 = rgb(250), BorderSizePixel = 0,
			Image = ("rbxthumb://type=Asset&id=%d&w=150&h=150"):format(r.id), ScaleType = Enum.ScaleType.Fit, ZIndex = 7, Parent = tile })
		new("TextLabel", { Position = px(3, 76), Size = px(84, 26), BackgroundTransparency = 1, Text = r.name, FontFace = FONT.UI_REG, TextSize = 11,
			TextColor3 = rgb(40), TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = tile })
		hoverable(tile, function()
			tile.BackgroundColor3 = C.TILE_HI
			itemName.Text = string.upper(r.name) .. (r.creator ~= "" and ("  BY " .. string.upper(r.creator)) or "")
			sound("SOUND_HOVER")
		end, function() tile.BackgroundColor3 = C.TILE if not E.carry then itemName.Text = "" end end)
		local function pick() onPick(r) end
		tile.MouseButton1Down:Connect(pick)
		CLICK[tile] = pick
		tile.Activated:Connect(function()
			if E.pointerMode == "pad" or GuiService.SelectedObject == tile then pick() end
		end)
		return tile
	end

	-- runs a toolbox search (more = add the next page)
	local function toolboxSearch(st, kind, more, onPick)
		if more then st.page += 1 else st.page = 0 st.clear() end
		st.token += 1
		local my = st.token
		st.status.Text = "Searching the Toolbox..."
		task.spawn(function()
			local ok, list = netCall("ToolboxSearch", { kind = kind, q = st.query, page = st.page })
			if my ~= st.token then return end
			if not ok then st.status.Text = tostring(list or "The Toolbox search didn't work.") return end
			st.status.Text = (#list == 0 and st.page == 0) and "Nothing found. Try another word." or ""
			local old = st.grid:FindFirstChild("More")
			if old then old:Destroy() end
			local base = st.page * 100
			for i, r in ipairs(list) do toolboxTile(st, base + i, r, onPick) end
			if #list >= 20 then
				local m = paletteTile(st.grid, base + 99, "")
				m.Name = "More"
				new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "MORE...", FontFace = FONT.P2, TextSize = 18,
					TextColor3 = rgb(60), ZIndex = 7, Parent = m })
				onClick(m, function() toolboxSearch(st, kind, true, onPick) end)
			end
		end)
	end

	-- ----- TEXTURES -----
	local texPage, tex = sourcePage("textures", "Search textures (Toolbox)...")
	local texId = inputBox(texPage, px(7, 590), px(220, 30), "Texture asset id")
	note(texPage, px(9, 668), px(359, 60), "Select surfaces in the room, then click a texture to put it on them. IN GAME lists ReplicatedStorage.PortalAssets.Textures.")

	-- puts a texture on every selected surface (nil = back to the normal tiles)
	function Pal.applyTexture(v)
		if next(E.sel) == nil then flash("Select the surfaces to texture first.") sfx("Error") return end
		pushUndo()
		for fk in pairs(E.sel) do E.textures[fk] = v end
		rebuild()
		sfx("Click")
		flash(v and ("Texture applied to %d surface%s."):format(selCount(), selCount() == 1 and "" or "s") or "Textures cleared.")
	end
	-- a decal from the Toolbox: the server looks up the image inside it
	local function pickToolboxTexture(r)
		if next(E.sel) == nil then flash("Select the surfaces to texture first.") sfx("Error") return end
		sfx("Click")
		flash("Loading " .. r.name .. "...")
		task.spawn(function()
			local ok, res = netCall("ToolboxLoad", { kind = "textures", id = r.id })
			if ok and type(res) == "table" and Config.ValidTextureValue(res.value) then
				Pal.applyTexture(res.value)
			else
				flash(tostring(res or "Couldn't load that texture."))
				sfx("Error")
			end
		end)
	end
	smallButton(texPage, px(233, 590), px(135, 30), "USE ID", function()
		local id = texId.Text:match("(%d+)")
		if not id then flash("Paste a texture / decal asset id first.") sfx("Error") return end
		if next(E.sel) == nil then flash("Select the surfaces to texture first.") sfx("Error") return end
		-- decal ids need looking up; if that fails it's probably an image id already
		task.spawn(function()
			local ok, res = netCall("ToolboxLoad", { kind = "textures", id = tonumber(id) })
			Pal.applyTexture((ok and type(res) == "table" and Config.ValidTextureValue(res.value)) and res.value or ("id:" .. id))
		end)
	end, true)
	smallButton(texPage, px(7, 628), px(180, 30), "CLEAR TEXTURE", function() Pal.applyTexture(nil) end)

	function tex.run(more)
		if tex.src == "toolbox" then
			toolboxSearch(tex, "textures", more, pickToolboxTexture)
			return
		end
		tex.token += 1
		tex.clear()
		local list = Config.TextureList()
		tex.status.Text = #list == 0 and "No textures in the game yet. Put Textures / Decals in ReplicatedStorage.PortalAssets.Textures, or use TOOLBOX." or ""
		for i, it in ipairs(list) do
			local tile = paletteTile(tex.grid, i, it.name .. " " .. (it.folder or ""))
			new("ImageLabel", { Position = px(10, 6), Size = px(70, 70), BackgroundColor3 = rgb(250), BorderSizePixel = 0, Image = Config.TextureImage(it.name),
				ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(35, 35), ZIndex = 7, Parent = tile })
			new("TextLabel", { Position = px(3, 78), Size = px(84, 24), BackgroundTransparency = 1, Text = it.name, FontFace = FONT.UI_REG, TextSize = 11,
				TextColor3 = rgb(40), TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = tile })
			hoverable(tile, function() tile.BackgroundColor3 = C.TILE_HI itemName.Text = string.upper(it.name) sound("SOUND_HOVER") end,
				function() tile.BackgroundColor3 = C.TILE itemName.Text = "" end)
			onClick(tile, function() Pal.applyTexture(it.name) end)
		end
		filterTiles(tex.grid, tex.query)
	end
	Pal.onShow.textures = function()
		if Pal.built.textures then return end
		Pal.built.textures = true
		tex.run(false)
	end

	-- ----- MESHES (MeshParts) -----
	-- TOOLBOX: searches the Creator Store's MeshParts only (no models); a pick becomes a real MeshPart.
	-- IN GAME: your own MeshParts in PortalAssets.Meshes. Or paste any Mesh asset id for a real MeshPart.
	local meshPage, mesh = sourcePage("meshes", "Search meshes (Creator Store)...")
	local meshId = inputBox(meshPage, px(7, 590), px(178, 30), "Mesh asset id")
	local meshTex = inputBox(meshPage, px(190, 590), px(178, 30), "Texture id (optional)")
	note(meshPage, px(9, 668), px(359, 60), "TOOLBOX searches MeshParts only. Drag one into the room, right-click it to resize. IN GAME = ReplicatedStorage.PortalAssets.Meshes.")

	-- a Creator Store MeshPart: the server makes it, then you carry it like any item
	local picked = {} -- [asset id] = the value the server gave back ("mesh:<id>" or "tbmesh:<id>")
	local function keyOf(value)
		local mid = value:match("^mesh:(%d+)$")
		if mid then return Config.MeshKey(mid, nil) end
		return "tbmesh_" .. (value:match("^tbmesh:(%d+)$") or "")
	end
	local function pickToolboxMesh(r)
		if E.carry then return end
		local function carry(value) if E.active and not E.carry then Pal.startCarry({ kind = "prop", variant = value, name = r.name }) end end
		local known = picked[r.id]
		if known and Config.ToolboxModel(keyOf(known)) then carry(known) sfx("Click") return end
		flash("Loading " .. r.name .. "...")
		task.spawn(function()
			local ok, res = netCall("ToolboxLoad", { kind = "storemesh", id = r.id })
			if not ok or type(res) ~= "table" or type(res.value) ~= "string" then
				flash(tostring((not ok) and res or "Couldn't load that mesh."))
				sfx("Error")
				return
			end
			picked[r.id] = res.value
			local f = ReplicatedStorage:WaitForChild(Config.TOOLBOX_FOLDER, 10)
			if f and f:WaitForChild(keyOf(res.value), 10) then
				carry(res.value)
				flash("Click in the room to place " .. r.name .. ".")
			end
		end)
	end

	smallButton(meshPage, px(7, 628), px(361, 30), "PICK UP MESH ID", function()
		local id = meshId.Text:match("(%d+)")
		if not id then flash("Paste a Mesh asset id first.") sfx("Error") return end
		local tid = meshTex.Text:match("(%d+)")
		local key = Config.MeshKey(id, tid)
		local variant = "mesh:" .. id .. (tid and (":" .. tid) or "")
		local function carry() if E.active and not E.carry then Pal.startCarry({ kind = "prop", variant = variant, name = "Mesh " .. id }) end end
		if Config.ToolboxModel(key) then carry() return end
		flash("Making the MeshPart...")
		task.spawn(function()
			local ok, res = netCall("ToolboxLoad", { kind = "mesh", id = tonumber(id), tex = tonumber(tid) })
			if not ok then flash(tostring(res or "Couldn't load that mesh.")) sfx("Error") return end
			local f = ReplicatedStorage:WaitForChild(Config.TOOLBOX_FOLDER, 10)
			if f and f:WaitForChild(key, 10) then
				carry()
				flash("Click in the room to place the mesh.")
			end
		end)
	end, true)

	function mesh.run(more)
		if mesh.src == "toolbox" then
			toolboxSearch(mesh, "meshes", more, pickToolboxMesh)
			return
		end
		mesh.token += 1
		mesh.clear()
		local list = Config.MeshList()
		mesh.status.Text = #list == 0 and "No meshes in the game yet. Put MeshParts in ReplicatedStorage.PortalAssets.Meshes, or paste a Mesh id below." or ""
		for i, it in ipairs(list) do
			local tile = paletteTile(mesh.grid, i, it.name .. " " .. (it.folder or ""))
			new("TextLabel", { Position = px(3, 78), Size = px(84, 24), BackgroundTransparency = 1, Text = it.name, FontFace = FONT.UI_REG, TextSize = 11,
				TextColor3 = rgb(40), TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = tile })
			local vp = new("ViewportFrame", { Position = px(5, 2), Size = px(80, 76), BackgroundTransparency = 1, Ambient = rgb(180),
				LightDirection = Vector3.new(-0.4, -1, -0.6), ZIndex = 7, Parent = tile })
			local ok, m = pcall(function()
				local c = it.inst:Clone()
				if c:IsA("BasePart") then
					local holder = Instance.new("Model")
					c.Parent = holder
					c = holder
				end
				return c
			end)
			if ok and m then
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BaseScript") or d:IsA("Sound") then d:Destroy() end
				end
				m.Parent = new("WorldModel", { Parent = vp })
				frameModel(vp, m)
			end
			carryTile(tile, { kind = "prop", variant = it.name, name = it.name })
		end
		filterTiles(mesh.grid, mesh.query)
	end
	Pal.onShow.meshes = function()
		if Pal.built.meshes then return end
		Pal.built.meshes = true
		mesh.run(false)
	end

	-- ----- MY CHIPS -----
	local chipPage = page("chips")
	new("TextLabel", { Position = px(9, 6), Size = px(359, 20), BackgroundTransparency = 1, Text = "CHIPS IN THIS CHAMBER", FontFace = FONT.UI, TextSize = 14,
		TextColor3 = rgb(60), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = chipPage })
	local function chipList(y, h)
		local sc = new("ScrollingFrame", { Position = px(7, y), Size = px(361, h), BackgroundColor3 = rgb(250), BorderSizePixel = 0, ScrollBarThickness = 4,
			AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = px(0, 0), ZIndex = 7, Parent = chipPage })
		new("UIStroke", { Color = C.TILE_LINE, Thickness = 1, Parent = sc })
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = sc })
		return sc
	end
	local here = chipList(28, 250)
	smallButton(chipPage, px(7, 284), px(361, 30), "+ NEW CHIP", function()
		if #E.chips >= (LIM.chips or 16) then flash("That's the chip limit for one chamber.") sfx("Error") return end
		Dlg.chip(nil)
	end, true)
	new("TextLabel", { Position = px(9, 326), Size = px(359, 20), BackgroundTransparency = 1, Text = "MY CHIPS (SAVED, USE THEM IN ANY CHAMBER)", FontFace = FONT.UI, TextSize = 14,
		TextColor3 = rgb(60), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = chipPage })
	local saved = chipList(348, 290)
	note(chipPage, px(9, 646), px(359, 84), "Chips are little programs: \"when button1 pressed\" -> \"open exit\". Build them from blocks or type them as lines. Items are named by their label (right-click an item to see it).")
	local library = {}

	local function chipRow(parent, order, text, buttons)
		local row = new("Frame", { Size = px(355, 34), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 8, Parent = parent })
		new("TextLabel", { Position = px(8, 0), Size = px(355 - 8 - #buttons * 64, 34), BackgroundTransparency = 1, Text = text, FontFace = FONT.UI_REG, TextSize = 15,
			TextColor3 = rgb(25), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8, Parent = row })
		for i, b in ipairs(buttons) do
			local x = 355 - (#buttons - i + 1) * 64
			local btn = smallButton(row, px(x + 2, 3), px(60, 28), b[1], b[2], b[3])
			btn.ZIndex = 9
		end
		new("Frame", { Position = px(0, 33), Size = px(355, 1), BackgroundColor3 = C.TILE_LINE, BorderSizePixel = 0, ZIndex = 8, Parent = row })
	end

	function Pal.refreshChips()
		for _, sc in ipairs({ here, saved }) do
			for _, c in ipairs(sc:GetChildren()) do
				if c:IsA("GuiObject") then c:Destroy() end
			end
		end
		for i, chip in ipairs(E.chips) do
			chipRow(here, i, chip.name, {
				{ "EDIT", function() Dlg.chip(i) end, true },
				{ "✕", function()
					pushUndo()
					table.remove(E.chips, i)
					Pal.refreshChips()
				end },
			})
		end
		if #E.chips == 0 then
			note(here, px(0, 0), px(350, 40), "  No chips yet.").Size = px(350, 30)
		end
		for i, chip in ipairs(library) do
			chipRow(saved, i, chip.name, {
				{ "USE", function()
					if #E.chips >= (LIM.chips or 16) then flash("That's the chip limit for one chamber.") sfx("Error") return end
					Dlg.chip(nil, { name = chip.name, src = chip.src })
				end, true },
				{ "✕", function()
					task.spawn(function()
						local ok, list = netCall("ChipDelete", chip.id)
						if ok and type(list) == "table" then library = list Pal.refreshChips() end
					end)
				end },
			})
		end
		if #library == 0 then
			note(saved, px(0, 0), px(350, 40), "  Save a chip with SAVE TO MY CHIPS to reuse it.").Size = px(350, 30)
		end
	end
	function Pal.setLibrary(list)
		if type(list) == "table" then library = list end
		Pal.refreshChips()
	end
	Pal.onShow.chips = function()
		Pal.refreshChips()
		task.spawn(function()
			local ok, list = netCall("ChipList")
			if ok then Pal.setLibrary(list) end
		end)
	end

	player:GetAttributeChangedSignal("Setting_edMode"):Connect(function()
		Pal.layoutTabs()
		if Pal.build then Pal.build() end -- the invisible blocks come and go with the mode
		if E.active then flash(("Editor mode: %s"):format(ES("edMode", "Simple"))) end
	end)
	Pal.layoutTabs()
end

-- ==========================================
-- POPUP DIALOGS (rename / publish / controls / open / save as / invite)
-- ==========================================
local function closeDialog()
	if dialog then
		local so = GuiService.SelectedObject
		if so and so:IsDescendantOf(dialog) then GuiService.SelectedObject = nil end
		dialog:Destroy()
		dialog = nil
	end
end
local saveDraft -- forward
do
	local function makeDialog(title, h, w)
		w = w or 560
		closeDialog()
		dialog = ui(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = px(w, h), BackgroundColor3 = C.CTX_BG,
			BorderSizePixel = 0, Active = true, SelectionGroup = true, ZIndex = 30, Parent = canvas }))
		new("UIStroke", { Color = C.CTX_EDGE, Thickness = 1, Parent = dialog })
		local head = new("Frame", { Size = px(w, 26), BackgroundColor3 = C.CTX_HEAD, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 31, Parent = dialog })
		new("TextLabel", { Size = px(w - 12, 26), BackgroundTransparency = 1, Text = string.upper(title), FontFace = FONT.UI_REG, TextSize = 15, TextColor3 = rgb(236),
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 32, Parent = head })
		local d = dialog
		task.defer(function() if dialog == d then focusFirst(d) end end) -- after the buttons exist
		return dialog
	end
	local function dialogButton(parent, x, y, text, fn, blue)
		local b = new("TextButton", { Position = px(x, y), Size = px(160, 38), BackgroundColor3 = blue and rgb(77, 128, 151) or rgb(200, 206, 203), BorderSizePixel = 0,
			Text = text, FontFace = FONT.P2, TextSize = 22, TextColor3 = blue and rgb(245) or rgb(20), ZIndex = 32, Parent = parent })
		hoverable(b, function() sound("SOUND_HOVER") end, function() end)
		onClick(b, function() sfx("Click") fn() end)
		return b
	end
	local function dialogBox(parent, y, text, placeholder)
		return new("TextBox", { Position = px(20, y), Size = px(520, 42), BackgroundColor3 = rgb(255), BorderSizePixel = 0, Text = text, PlaceholderText = placeholder or "",
			FontFace = FONT.UI_REG, TextSize = 20, TextColor3 = rgb(20), ClearTextOnFocus = false, ZIndex = 32, Parent = parent })
	end
	local function listRow(sc, text, fn)
		local b = new("TextButton", { Size = px(500, 38), BackgroundColor3 = C.CTX_HI, BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false,
			Text = "  " .. text, FontFace = FONT.UI_REG, TextSize = 19, TextColor3 = rgb(30),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33, Parent = sc })
		hoverable(b, function() b.BackgroundTransparency = 0 sound("SOUND_HOVER") end, function() b.BackgroundTransparency = 1 end)
		onClick(b, function() sfx("Click") fn() end)
		return b
	end
	local function listFrame(d)
		local sc = new("ScrollingFrame", { Position = px(20, 44), Size = px(520, 280), BackgroundColor3 = rgb(250), BorderSizePixel = 0, ScrollBarThickness = 8,
			AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = px(0, 0), ZIndex = 32, Parent = d })
		new("UIListLayout", { Parent = sc })
		return sc
	end

	Dlg.makeDialog, Dlg.dialogButton = makeDialog, dialogButton -- (Export / Import, further down)

	Dlg.publish = function()
		local d = makeDialog("Publish To Workshop", 160)
		local box = dialogBox(d, 50, E.title, "Chamber name")
		dialogButton(d, 20, 108, "PUBLISH", function()
			if not Config.ExitCanOpen(serialize()) then
				flash("Nothing opens the exit door. Connect a button to it, open it with a chip, or right-click it > Open without a button.")
				sfx("Error")
				return
			end
			if box.Text ~= "" then E.title = box.Text:sub(1, 40) end
			closeDialog()
			saveDraft(true)
			local ok, res = netCall("EditorPublish", { id = E.id, data = serialize(), title = E.title, coop = E.coop })
			if ok then
				flash("Published to the Workshop!")
				X.toast(E.title .. " is live in the Workshop.", "Published", "good")
			else
				flash(res)
				sfx("Error")
			end
		end, true)
		dialogButton(d, 196, 108, "CANCEL", closeDialog)
	end

	Dlg.saveAs = function()
		local d = makeDialog("Save As", 160)
		local box = dialogBox(d, 50, E.title .. " copy", "Chamber name")
		dialogButton(d, 20, 108, "OK", function()
			local title = box.Text ~= "" and box.Text:sub(1, 40) or E.title
			closeDialog()
			task.spawn(function()
				local ok, res = netCall("EditorSaveAs", { title = title, data = serialize() })
				if not ok then flash(res) sfx("Error") return end
				saveDraft(true)
				netCall("CommunityCreate", res)
			end)
		end, true)
		dialogButton(d, 196, 108, "CANCEL", closeDialog)
	end

	Dlg.open = function()
		local ok, list = netCall("EditorList")
		if not ok then flash(list) return end
		local d = makeDialog("Open Test Chamber", 420)
		local sc = listFrame(d)
		for _, c in ipairs(list) do
			listRow(sc, c.title .. (c.id == E.id and "  (open)" or ""), function()
				closeDialog()
				if c.id == E.id then return end
				task.spawn(function()
					saveDraft(true)
					local ok2, err = netCall("CommunityCreate", c.id)
					if not ok2 then flash(err) end
				end)
			end)
		end
		if #list == 0 then
			new("TextLabel", { Size = px(500, 40), BackgroundTransparency = 1, Text = "You have no saved test chambers.", FontFace = FONT.UI_REG, TextSize = 19,
				TextColor3 = rgb(110), ZIndex = 33, Parent = sc })
		end
		dialogButton(d, 20, 340, "CANCEL", closeDialog)
	end

	-- team building: invite someone in this server
	Dlg.invite = function()
		if E.guest then flash("Only the chamber's owner can invite people.") sfx("Error") return end
		local d = makeDialog("Invite Team Builder", 420)
		local sc = listFrame(d)
		local n = 0
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= player and not Team.memberInfo(pl.UserId) then
				n += 1
				listRow(sc, pl.DisplayName .. "  (@" .. pl.Name .. ")", function()
					closeDialog()
					task.spawn(function()
						local ok, err = netCall("TeamInvite", { userId = pl.UserId, data = serialize(), title = E.title })
						if ok then flash("Invited " .. pl.DisplayName .. ". Waiting for them to join...") else flash(err) sfx("Error") end
					end)
				end)
			end
		end
		if n == 0 then
			new("TextLabel", { Size = px(500, 40), BackgroundTransparency = 1, Text = "Nobody else is in this server.", FontFace = FONT.UI_REG, TextSize = 19,
				TextColor3 = rgb(110), ZIndex = 33, Parent = sc })
		end
		dialogButton(d, 20, 340, "CANCEL", closeDialog)
	end

	-- Help > Wiki: everything the editor does, one page per topic (PortalConfig C.WIKI)
	-- overlay = true: opens on top of the dialog that's open (the chip editor's ? button) instead of replacing it
	Dlg.wiki = function(pageTitle, overlay)
		local WW, WH = 940, 660
		local d
		if overlay then
			d = ui(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = px(WW, WH), BackgroundColor3 = C.CTX_BG,
				BorderSizePixel = 0, Active = true, ZIndex = 60, Parent = canvas }))
			new("UIStroke", { Color = C.CTX_EDGE, Thickness = 1, Parent = d })
			local head = new("Frame", { Size = px(WW, 26), BackgroundColor3 = C.CTX_HEAD, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 61, Parent = d })
			new("TextLabel", { Size = px(WW - 12, 26), BackgroundTransparency = 1, Text = "WIKI", FontFace = FONT.UI_REG, TextSize = 15, TextColor3 = rgb(236),
				TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 62, Parent = head })
		else
			d = makeDialog("Wiki", WH, WW)
		end
		local list = new("ScrollingFrame", { Position = px(14, 38), Size = px(230, WH - 104), BackgroundColor3 = rgb(250), BorderSizePixel = 0,
			ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = px(0, 0), ZIndex = 32, Parent = d })
		new("UIStroke", { Color = C.CTX_EDGE, Thickness = 1, Parent = list })
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		local pageFrame = new("ScrollingFrame", { Position = px(256, 38), Size = px(WW - 270, WH - 104), BackgroundColor3 = rgb(250), BorderSizePixel = 0,
			ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = px(0, 0), ZIndex = 32, Parent = d })
		new("UIStroke", { Color = C.CTX_EDGE, Thickness = 1, Parent = pageFrame })
		new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), Parent = pageFrame })
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pageFrame })
		local title = new("TextLabel", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Text = "", FontFace = FONT.P2, TextSize = 30,
			TextColor3 = rgb(25), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, ZIndex = 33, Parent = pageFrame })
		local body = new("TextLabel", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = "",
			RichText = true, FontFace = FONT.UI_REG, TextSize = 17, LineHeight = 1.2, TextWrapped = true, TextColor3 = rgb(30),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2, ZIndex = 33, Parent = pageFrame })
		local rows = {}
		local function show(i)
			local pg = Config.WIKI[i]
			if not pg then return end
			title.Text = pg[1]
			body.Text = pg[2]
			pageFrame.CanvasPosition = Vector2.zero
			for j, r in ipairs(rows) do r.BackgroundTransparency = j == i and 0 or 1 end
		end
		local start = 1
		for i, pg in ipairs(Config.WIKI or {}) do
			if pageTitle and pg[1] == pageTitle then start = i end
			local b = new("TextButton", { Size = px(226, 34), BackgroundColor3 = C.CTX_HI, BackgroundTransparency = 1, BorderSizePixel = 0,
				AutoButtonColor = false, Text = "  " .. pg[1], FontFace = FONT.UI_REG, TextSize = 17, TextColor3 = rgb(30),
				TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = i, ZIndex = 33, Parent = list })
			hoverable(b, function() sound("SOUND_HOVER") end, function() end)
			onClick(b, function() sfx("Click") show(i) end)
			rows[i] = b
		end
		show(start)
		dialogButton(d, 14, WH - 54, "CLOSE", function() if overlay then d:Destroy() else closeDialog() end end, true)
	end

	-- Advanced: rename an item's label (chips use it); chips that used the old name follow along
	Dlg.rename = function(index)
		local e = E.ents[index]
		if not e then return end
		local d = makeDialog("Item Label", 196)
		new("TextLabel", { Position = px(20, 34), Size = px(520, 26), BackgroundTransparency = 1, Text = "Chips call this item by its label. Letters, numbers and _, starting with a letter.",
			FontFace = FONT.UI_REG, TextSize = 15, TextColor3 = rgb(60), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 32, Parent = d })
		local box = dialogBox(d, 66, Config.LabelOf(e) or "", "button1")
		dialogButton(d, 20, 136, "OK", function()
			local l = box.Text:gsub("%s", "")
			if not Config.ValidLabel(l) then flash("Use letters, numbers and _, starting with a letter (max 20).") sfx("Error") return end
			for i, other in ipairs(E.ents) do
				if i ~= index and (Config.LabelOf(other) or ""):lower() == l:lower() then flash("Another item already has that label.") sfx("Error") return end
			end
			local old = Config.LabelOf(e)
			closeDialog()
			pushUndo()
			local opt = table.clone(Config.Options(e))
			opt.label = l
			e[10] = opt
			if old and old:lower() ~= l:lower() then
				for _, chip in ipairs(E.chips) do
					local rules, errs = Config.ParseChip(chip.src)
					if #errs == 0 then
						for _, r in ipairs(rules) do
							if r.src and r.src:lower() == old:lower() then r.src = l end
							for _, a in ipairs(r.acts) do
								if a.target and a.target:lower() == old:lower() then a.target = l end
							end
						end
						chip.src = Config.ChipText(rules)
					end
				end
			end
			rebuildEnts()
			flash("Label set to " .. l .. ".")
		end, true)
		dialogButton(d, 196, 136, "CANCEL", closeDialog)
	end

	-- Advanced: the chip editor. Two views of the same program: BLOCKS (pick from menus) and LINES (type it).
	Dlg.chip = function(index, preset)
		local existing = index and E.chips[index]
		local src = (existing and existing.src) or (preset and preset.src) or "when button1 pressed\n    open exit\nwhen button1 released\n    close exit"
		local name = (existing and existing.name) or (preset and preset.name) or ("Chip " .. (#E.chips + 1))
		local DW, DH = 840, 664
		local d = makeDialog(existing and "Edit Chip" or "New Chip", DH, DW)
		local nameBox = new("TextBox", { Position = px(20, 40), Size = px(460, 36), BackgroundColor3 = rgb(255), BorderSizePixel = 0, Text = name,
			PlaceholderText = "Chip name", FontFace = FONT.UI_REG, TextSize = 19, TextColor3 = rgb(20), ClearTextOnFocus = false, ZIndex = 32, Parent = d })
		local body = new("Frame", { Position = px(20, 86), Size = px(800, 470), BackgroundColor3 = rgb(250), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 32, Parent = d })
		new("UIStroke", { Color = C.CTX_EDGE, Thickness = 1, Parent = body })
		local errLabel = new("TextLabel", { Position = px(20, 560), Size = px(800, 40), BackgroundTransparency = 1, Text = "", FontFace = FONT.UI_REG, TextSize = 15,
			TextColor3 = rgb(200, 50, 50), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 32, Parent = d })
		local rules, perrs = Config.ParseChip(src)
		local view = #perrs > 0 and "lines" or "blocks"
		local linesBox
		local render

		-- items a menu can offer, sorted by label
		local function labelsWhere(ok)
			local list = {}
			for _, e in ipairs(E.ents) do
				local l = Config.LabelOf(e)
				if l and ok(e[1]) then table.insert(list, { label = l, name = entLabel(e) }) end
			end
			table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
			return list
		end
		local function pickItems(current, ok, set)
			local list = {}
			for _, it in ipairs(labelsWhere(ok)) do
				table.insert(list, { text = it.label .. "   (" .. it.name .. ")", icon = "radio", checked = current == it.label, fn = function() set(it.label) render() end })
			end
			if #list == 0 then list = { { text = "Nothing in the chamber can do that yet", disabled = true, fn = function() end } } end
			return list
		end
		local function dropdown(parent, x, y, w, text, getItems)
			local b = new("TextButton", { Position = px(x, y), Size = px(w, 30), BackgroundColor3 = rgb(255), BorderSizePixel = 0, AutoButtonColor = true,
				Text = "  " .. text .. "  ▾", FontFace = FONT.UI_REG, TextSize = 16, TextColor3 = rgb(20), TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 35, Parent = parent })
			hoverable(b, function() sound("SOUND_HOVER") end, function() end)
			onClick(b, function()
				sfx("Click")
				local pos = (b.AbsolutePosition - canvas.AbsolutePosition) / uiScale.Scale
				popupMenu(pos.X, pos.Y + 32, { { items = getItems() } })
			end)
			return b
		end
		local function field(parent, x, y, w, value, set, numeric)
			local b = new("TextBox", { Position = px(x, y), Size = px(w, 30), BackgroundColor3 = rgb(255), BorderSizePixel = 0, Text = tostring(value),
				FontFace = FONT.UI_REG, TextSize = 16, TextColor3 = rgb(20), ClearTextOnFocus = false, ZIndex = 35, Parent = parent })
			b.FocusLost:Connect(function()
				if numeric then
					local v = tonumber(b.Text)
					if v then set(v) else b.Text = tostring(value) end
				else
					set(b.Text:sub(1, 120))
				end
			end)
			return b
		end
		local function tinyButton(parent, x, y, w, text, fn, color)
			local b = new("TextButton", { Position = px(x, y), Size = px(w, 30), BackgroundColor3 = color or rgb(240, 240, 236), BorderSizePixel = 0,
				AutoButtonColor = true, Text = text, FontFace = FONT.P2, TextSize = 16, TextColor3 = rgb(25), ZIndex = 35, Parent = parent })
			hoverable(b, function() sound("SOUND_HOVER") end, function() end)
			onClick(b, function() sfx("Click") fn() end)
			return b
		end
		local function label(parent, x, y, w, text, color)
			return new("TextLabel", { Position = px(x, y), Size = px(w, 30), BackgroundTransparency = 1, Text = text, FontFace = FONT.P2, TextSize = 18,
				TextColor3 = color or rgb(30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35, Parent = parent })
		end

		local viewButtons = {}
		render = function()
			for _, c in ipairs(body:GetChildren()) do
				if c:IsA("GuiObject") then c:Destroy() end
			end
			for v, b in pairs(viewButtons) do
				b.BackgroundColor3 = v == view and rgb(77, 128, 151) or rgb(200, 206, 203)
				b.TextColor3 = v == view and rgb(245) or rgb(20)
			end
			if view == "lines" then
				-- the text box underneath, a coloured copy of the same text on top (it lets clicks through)
				linesBox = new("TextBox", { Position = px(0, 0), Size = px(800, 470), BackgroundTransparency = 1, Text = linesBox and linesBox.Text or Config.ChipText(rules),
					MultiLine = true, ClearTextOnFocus = false, Font = Enum.Font.Code, TextSize = 19, TextColor3 = rgb(25), TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = false, ZIndex = 33, Parent = body })
				new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingTop = UDim.new(0, 10), Parent = linesBox })
				local colors = new("TextLabel", { Position = px(0, 0), Size = px(800, 470), BackgroundTransparency = 1, Text = "", RichText = true,
					Font = Enum.Font.Code, TextSize = 19, TextColor3 = rgb(25), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
					TextWrapped = false, Active = false, ZIndex = 34, Parent = body })
				new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingTop = UDim.new(0, 10), Parent = colors })
				local box = linesBox
				local busy, lines = false, select(2, box.Text:gsub("\n", ""))
				local function labels()
					local list = {}
					for _, e in ipairs(E.ents) do
						local l = Config.LabelOf(e)
						if l then table.insert(list, l) end
					end
					return list
				end
				local function showFixes(fx)
					if #fx > 0 then
						errLabel.TextColor3 = rgb(40, 120, 60)
						errLabel.Text = "Auto corrected: " .. table.concat(fx, ", ", 1, math.min(#fx, 6))
					end
				end
				local function paint()
					colors.Text = Config.ChipHighlight(box.Text, Config.LabelKinds(E.ents))
				end

				-- what the line expects (bottom bar) + suggestions at the cursor (Tab or a click takes one)
				local TS = game:GetService("TextService")
				local hintBar = new("TextLabel", { Position = px(0, 446), Size = px(800, 24), BackgroundColor3 = rgb(232, 234, 232), BorderSizePixel = 0,
					Text = "", Font = Enum.Font.Code, TextSize = 15, TextColor3 = rgb(60), TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 36, Parent = body })
				new("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = hintBar })
				local pop = new("Frame", { Size = px(280, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.CTX_BG, BorderSizePixel = 0,
					Visible = false, ZIndex = 37, Parent = body })
				new("UIStroke", { Color = C.CTX_EDGE, Thickness = 1, Parent = pop })
				new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = pop })
				local lineH = TS:GetTextSize("Ag", 19, Enum.Font.Code, Vector2.new(10000, 10000)).Y
				local sugg = {}
				local KIND_COL = { keyword = "#8E44AD", action = "#1F6FD0", event = "#C26A00", item = "#2E8B3A", variable = "#0E8A92",
					compare = "#5A5F66", value = "#B5522B" }
				local showSuggest
				local function accept(i)
					local sg = sugg[i]
					if not sg then return false end
					local cur = box.CursorPosition
					if cur < 1 then return false end
					local before, after = box.Text:sub(1, cur - 1), box.Text:sub(cur)
					local typed = before:match("(%S*)$") or ""
					local ins = sg .. " "
					busy = true
					box.Text = before:sub(1, #before - #typed) .. ins .. after
					box.CursorPosition = #before - #typed + #ins + 1
					busy = false
					lines = select(2, box.Text:gsub("\n", ""))
					paint()
					task.defer(showSuggest)
					return true
				end
				showSuggest = function()
					for _, c in ipairs(pop:GetChildren()) do
						if c:IsA("GuiObject") then c:Destroy() end
					end
					table.clear(sugg)
					local cur = box.CursorPosition
					if not box:IsFocused() or cur < 1 then pop.Visible = false return end
					local before = box.Text:sub(1, cur - 1)
					local lineText = before:match("([^\n]*)$") or ""
					local _, nl = before:gsub("\n", "")
					hintBar.Text = Config.ChipHintFor(lineText) or "Type a line. Tab or click takes a suggestion. Help > Wiki explains everything."
					local list = Config.ChipSuggest(lineText, Config.LabelKinds(E.ents), Config.ChipVariables((Config.ParseChip(box.Text))))
					for i = 1, math.min(#list, 7) do
						local sg = list[i]
						sugg[i] = sg[1]
						local b = new("TextButton", { Size = px(280, 24), BackgroundColor3 = i == 1 and C.CTX_HI or C.CTX_BG, BorderSizePixel = 0,
							AutoButtonColor = true, RichText = true, LayoutOrder = i, ZIndex = 38, Font = Enum.Font.Code, TextSize = 16,
							Text = ('  <font color="%s">%s</font>   <font color="#8A8F8F">%s</font>'):format(KIND_COL[sg[2]] or "#202020",
								sg[1]:gsub("<", "&lt;"):gsub(">", "&gt;"), sg[2]),
							TextXAlignment = Enum.TextXAlignment.Left, Parent = pop })
						b.MouseButton1Down:Connect(function() accept(i) end)
					end
					if #sugg == 0 then pop.Visible = false return end
					local w = TS:GetTextSize(lineText, 19, Enum.Font.Code, Vector2.new(10000, 10000)).X
					pop.Position = px(math.clamp(12 + w, 0, 800 - 284), math.min(10 + (nl + 1) * lineH + 2, 446 - 24 * #sugg))
					pop.Visible = true
				end
				local tabConn = UserInputService.InputBegan:Connect(function(input)
					if input.KeyCode == Enum.KeyCode.Tab and box:IsFocused() and pop.Visible then accept(1) end
				end)
				box.Destroying:Connect(function() tabConn:Disconnect() end)
				box:GetPropertyChangedSignal("CursorPosition"):Connect(function() if not busy then showSuggest() end end)
				box.Focused:Connect(showSuggest)

				box:GetPropertyChangedSignal("Text"):Connect(function()
					if busy then return end
					-- a Tab typed into the box: take the suggestion instead of a tab character
					local tabAt = box.Text:find("\t", 1, true)
					if tabAt then
						busy = true
						box.Text = box.Text:gsub("\t", "")
						box.CursorPosition = tabAt
						busy = false
						if accept(1) then return end
					end
					local n = select(2, box.Text:gsub("\n", ""))
					local cursor = box.CursorPosition
					if n == lines + 1 and cursor > 1 and box.Text:sub(cursor - 1, cursor - 1) == "\n" then
						-- Enter: fix the lines above the cursor, and indent the new line under its "when"
						local before, after = box.Text:sub(1, cursor - 1), box.Text:sub(cursor)
						local fixed, fx = Config.ChipAutocorrect(before:sub(1, -2), labels())
						local indent = (fixed:match("[^\n]*$") or ""):match("^%s*%S") and "    " or ""
						busy = true
						box.Text = fixed .. "\n" .. indent .. after
						box.CursorPosition = #fixed + 2 + #indent
						busy = false
						showFixes(fx)
					end
					lines = select(2, box.Text:gsub("\n", ""))
					paint()
					showSuggest()
				end)
				box.FocusLost:Connect(function()
					task.delay(0.25, function() if not box:IsFocused() then pop.Visible = false end end)
					local fixed, fx = Config.ChipAutocorrect(box.Text, labels())
					if fixed ~= box.Text then
						busy = true
						box.Text = fixed
						busy = false
						lines = select(2, fixed:gsub("\n", ""))
						showFixes(fx)
					end
					paint()
				end)
				paint()
				return
			end
			linesBox = nil
			local sc = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
				AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = px(0, 0), ZIndex = 33, Parent = body })
			new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sc })
			new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = sc })
			-- the op menu for an action (allowIf = false for the action after an "if ... then")
			local function opMenu(a, allowIf)
				return function()
					local list = {}
					for _, op in ipairs(Config.CHIP_ACTIONS) do
						if allowIf or (op ~= "if" and op ~= "repeat") then
							table.insert(list, { text = Config.CHIP_ACTION_LABELS[op], icon = "radio", checked = a.op == op, fn = function()
								a.op = op
								if op == "wait" then a.n = a.n or 1 end
								if op == "say" then a.text = a.text or "Well done!" end
								if op == "set" or op == "add" then
									a.var = a.var or "score"
									a.value = a.value or (op == "add" and "1" or "0")
								end
								if op == "music" or op == "sound" then a.text = (a.text and a.text ~= "") and a.text or (Config.ChipSoundNames(op)[1] or "") end
								if op == "title" then a.text = a.text or "Test complete!" end
								if op == "shake" then a.n = a.n or 1 end
								if op == "tint" then a.text = Config.CHIP_TINTS[a.text or ""] ~= nil and a.text or "blue" end
								if op == "countdown" then a.n = a.n or 30 end
								if op == "random" then a.var, a.lo, a.hi = a.var or "roll", a.lo or 1, a.hi or 6 end
								if op == "repeat" then
									a.n = math.clamp(math.floor(tonumber(a.n) or 3), 1, 50)
									a.act = a.act or { op = "drop" }
								end
								if op == "if" then
									a.lhs, a.cmp, a.rhs = a.lhs or "score", a.cmp or ">=", a.rhs or "1"
									a.act = a.act or { op = "open", target = Config.LabelKinds(E.ents).exit and "exit" or nil }
								end
								if a.target then
									local k = Config.LabelKinds(E.ents)[a.target:lower()]
									if not (k and Config.ChipTargetOk(op, k)) then a.target = nil end
								end
								render()
							end })
						end
					end
					return list
				end
			end
			-- the fields after the op, from x (w = room left)
			local function argFields(row, x, y, a, w)
				if Config.CHIP_TARGET[a.op] then
					dropdown(row, x, y, w, a.target or "pick an item", function()
						return pickItems(a.target, function(k) return Config.ChipTargetOk(a.op, k) end, function(v) a.target = v end)
					end)
				elseif a.op == "wait" then
					field(row, x, y, 90, a.n or 1, function(v) a.n = math.clamp(v, 0, 60) end, true)
					label(row, x + 98, y, 80, "seconds")
				elseif a.op == "say" then
					field(row, x, y, w, a.text or "", function(v) a.text = v end, false)
				elseif a.op == "music" or a.op == "sound" then
					-- a song / sound from the game (menu), or type a name / asset id
					local names = Config.ChipSoundNames(a.op)
					field(row, x, y, w - 46, a.text or "", function(v) a.text = v end, false).PlaceholderText = "name or asset id"
					tinyButton(row, x + w - 40, y, 36, "▾", function()
						local list = {}
						if a.op == "music" then table.insert(list, { text = "stop", icon = "radio", checked = a.text == "stop", fn = function() a.text = "stop" render() end }) end
						for _, n in ipairs(names) do
							table.insert(list, { text = n, icon = "radio", checked = a.text == n, fn = function() a.text = n render() end })
						end
						if #list == 0 then list = { { text = "No sounds in PortalAssets." .. (a.op == "music" and "OST" or "Sounds"), disabled = true, fn = function() end } } end
						local pos = (row.AbsolutePosition - canvas.AbsolutePosition) / uiScale.Scale
						popupMenu(pos.X + x + w - 40, pos.Y + y + 32, { { items = list } })
					end)
				elseif a.op == "title" then
					field(row, x, y, w, a.text or "", function(v) a.text = v end, false)
				elseif a.op == "shake" then
					field(row, x, y, 90, a.n or 1, function(v) a.n = math.clamp(v, 0.1, 5) end, true)
					label(row, x + 98, y, 80, "seconds")
				elseif a.op == "countdown" then
					field(row, x, y, 90, a.n or 30, function(v) a.n = math.clamp(math.floor(v), 0, 600) end, true)
					label(row, x + 98, y, 200, "seconds (0 = stop)")
				elseif a.op == "tint" then
					dropdown(row, x, y, 180, a.text or "none", function()
						local list = {}
						for _, c in ipairs(Config.CHIP_TINT_ORDER) do
							table.insert(list, { text = c, swatch = Config.CHIP_TINTS[c] or nil, icon = Config.CHIP_TINTS[c] and nil or "radio",
								checked = a.text == c, fn = function() a.text = c render() end })
						end
						return list
					end)
				elseif a.op == "random" then
					local nameBox = field(row, x, y, 130, a.var or "roll", function(v)
						v = v:gsub("%s", "")
						if Config.ValidVarName(v) then a.var = v else flash("Variable names: letters, numbers and _, starting with a letter.") render() end
					end, false)
					nameBox.PlaceholderText = "variable"
					label(row, x + 138, y, 50, "from")
					field(row, x + 190, y, 60, a.lo or 1, function(v) a.lo = math.floor(v) end, true)
					label(row, x + 256, y, 24, "to")
					field(row, x + 282, y, 60, a.hi or 6, function(v) a.hi = math.floor(v) end, true)
				elseif a.op == "set" or a.op == "add" then
					local nameBox = field(row, x, y, 130, a.var or "score", function(v)
						v = v:gsub("%s", "")
						if Config.ValidVarName(v) then a.var = v else flash("Variable names: letters, numbers and _, starting with a letter.") render() end
					end, false)
					nameBox.PlaceholderText = "variable"
					label(row, x + 138, y, 40, a.op == "set" and "to" or "+")
					field(row, x + 172, y, 90, a.value or "0", function(v)
						v = v:gsub("%s", "")
						if a.op == "add" and not tonumber(v) then render() return end
						a.value = v ~= "" and v or "0"
					end, false)
				end
			end
			local function rowHeight(a) return (a.op == "if" or a.op == "repeat") and 72 or 34 end

			for ri, r in ipairs(rules) do
				local h = 44 + 40
				for _, a in ipairs(r.acts) do h += rowHeight(a) + 6 end
				local blk = new("Frame", { Size = px(770, h), BackgroundColor3 = rgb(250, 206, 96), BorderSizePixel = 0, LayoutOrder = ri, ZIndex = 34, Parent = sc })
				label(blk, 12, 7, 60, "WHEN")
				local ex = 70
				if r.ev == "pressed" or r.ev == "released" then
					dropdown(blk, 70, 7, 230, r.src or "pick an item", function()
						return pickItems(r.src, Config.ChipSourceOk, function(v) r.src = v end)
					end)
					ex = 310
				elseif r.ev == "cond" then
					-- when <variable | item> <compare> <value>
					field(blk, 70, 7, 120, r.lhs or "score", function(v) v = v:gsub("%s", "") if v ~= "" then r.lhs = v end end, false).PlaceholderText = "variable or item"
					dropdown(blk, 196, 7, 70, r.cmp or ">=", function()
						local list = {}
						for _, c in ipairs(Config.CHIP_COMPARE) do
							table.insert(list, { text = c, icon = "radio", checked = r.cmp == c, fn = function() r.cmp = c render() end })
						end
						return list
					end)
					field(blk, 272, 7, 80, r.rhs or "3", function(v) v = v:gsub("%s", "") if v ~= "" then r.rhs = v end end, false)
					ex = 360
				end
				dropdown(blk, ex, 7, 200, Config.CHIP_EVENT_LABELS[r.ev] or r.ev, function()
					local list = {}
					for _, ev in ipairs(Config.CHIP_EVENTS) do
						table.insert(list, { text = Config.CHIP_EVENT_LABELS[ev], icon = "radio", checked = r.ev == ev, fn = function()
							r.ev = ev
							if ev == "start" or ev == "every" or ev == "cond" then r.src = nil end
							if ev == "every" then r.n = r.n or 5 end
							if ev == "cond" then r.lhs, r.cmp, r.rhs = r.lhs or "score", r.cmp or ">=", r.rhs or "3" end
							render()
						end })
					end
					return list
				end)
				if r.ev == "every" then
					field(blk, ex + 210, 7, 70, r.n or 5, function(v) r.n = math.clamp(v, 0.5, 600) end, true)
					label(blk, ex + 288, 7, 80, "seconds")
				end
				tinyButton(blk, 726, 7, 34, "✕", function() table.remove(rules, ri) render() end)
				local ay = 44
				for ai, a in ipairs(r.acts) do
					local rh = rowHeight(a)
					local row = new("Frame", { Position = px(24, ay), Size = px(736, rh), BackgroundColor3 = rgb(126, 186, 240), BorderSizePixel = 0, ZIndex = 34, Parent = blk })
					ay += rh + 6
					label(row, 10, 2, 40, "DO")
					dropdown(row, 46, 2, (a.op == "if" or a.op == "repeat") and 110 or 200, Config.CHIP_ACTION_LABELS[a.op] or a.op, opMenu(a, true))
					if a.op == "repeat" then
						-- repeat <n> times   /   then <action>
						field(row, 162, 2, 70, a.n or 3, function(v) a.n = math.clamp(math.floor(v), 1, 50) end, true)
						label(row, 238, 2, 60, "times")
						label(row, 46, 38, 60, "THEN")
						a.act = a.act or { op = "drop" }
						dropdown(row, 110, 38, 170, Config.CHIP_ACTION_LABELS[a.act.op] or a.act.op, opMenu(a.act, false))
						argFields(row, 288, 38, a.act, 310)
					elseif a.op == "if" then
						-- if <lhs> <cmp> <rhs>   /   then <action>
						field(row, 162, 2, 120, a.lhs or "score", function(v) v = v:gsub("%s", "") if v ~= "" then a.lhs = v end end, false).PlaceholderText = "variable or item"
						dropdown(row, 288, 2, 70, a.cmp or "==", function()
							local list = {}
							for _, c in ipairs(Config.CHIP_COMPARE) do
								table.insert(list, { text = c, icon = "radio", checked = a.cmp == c, fn = function() a.cmp = c render() end })
							end
							return list
						end)
						field(row, 364, 2, 90, a.rhs or "1", function(v) v = v:gsub("%s", "") if v ~= "" then a.rhs = v end end, false)
						label(row, 46, 38, 60, "THEN")
						a.act = a.act or { op = "open" }
						dropdown(row, 110, 38, 170, Config.CHIP_ACTION_LABELS[a.act.op] or a.act.op, opMenu(a.act, false))
						argFields(row, 288, 38, a.act, 310)
					else
						argFields(row, 256, 2, a, 340)
					end
					tinyButton(row, 610, 2, 34, "▲", function()
						if ai > 1 then r.acts[ai], r.acts[ai - 1] = r.acts[ai - 1], r.acts[ai] render() end
					end)
					tinyButton(row, 650, 2, 34, "▼", function()
						if ai < #r.acts then r.acts[ai], r.acts[ai + 1] = r.acts[ai + 1], r.acts[ai] render() end
					end)
					tinyButton(row, 694, 2, 34, "✕", function() table.remove(r.acts, ai) render() end)
				end
				tinyButton(blk, 24, ay, 120, "+ DO", function()
					table.insert(r.acts, { op = "open", target = Config.LabelKinds(E.ents).exit and "exit" or nil })
					render()
				end, rgb(126, 186, 240))
			end
			local add = new("Frame", { Size = px(770, 34), BackgroundTransparency = 1, LayoutOrder = #rules + 1, ZIndex = 34, Parent = sc })
			tinyButton(add, 0, 2, 200, "+ WHEN PRESSED", function() table.insert(rules, { ev = "pressed", acts = {} }) render() end, rgb(250, 206, 96))
			tinyButton(add, 210, 2, 200, "+ WHEN STARTS", function() table.insert(rules, { ev = "start", acts = {} }) render() end, rgb(250, 206, 96))
			tinyButton(add, 420, 2, 200, "+ EVERY ... SECONDS", function() table.insert(rules, { ev = "every", n = 5, acts = {} }) render() end, rgb(250, 206, 96))
			if Pal.level() >= 3 then
				tinyButton(add, 630, 2, 140, "+ WHEN TRUE", function()
					table.insert(rules, { ev = "cond", lhs = "score", cmp = ">=", rhs = "3", acts = {} })
					render()
				end, rgb(250, 206, 96))
			end
		end

		-- LINES view -> rules (false + message if it doesn't parse)
		local function readLines()
			if view ~= "lines" or not linesBox then return true end
			local r2, e2 = Config.ParseChip(linesBox.Text)
			if #e2 > 0 then
				errLabel.TextColor3 = rgb(200, 50, 50)
				errLabel.Text = table.concat(e2, "    ", 1, math.min(#e2, 3))
				return false
			end
			rules = r2
			return true
		end
		local function setView(v)
			if v == view then return end
			if v == "blocks" and not readLines() then sfx("Error") return end
			errLabel.Text = ""
			if v == "lines" then linesBox = nil end -- regenerate the text from the blocks
			view = v
			render()
		end
		local helpBtn = new("TextButton", { Position = px(DW - 44, 40), Size = px(30, 36), BorderSizePixel = 0, AutoButtonColor = true,
			BackgroundColor3 = rgb(200, 206, 203), Text = "?", FontFace = FONT.P2, TextSize = 22, TextColor3 = rgb(20), ZIndex = 32, Parent = d })
		hoverable(helpBtn, function() sound("SOUND_HOVER") end, function() end)
		-- the language reference, on top of the chip you're editing
		onClick(helpBtn, function() sfx("Click") Dlg.wiki("Chips: reference", true) end)
		for i, v in ipairs({ "blocks", "lines" }) do
			local b = new("TextButton", { Position = px(486 + (i - 1) * 152, 40), Size = px(146, 36), BorderSizePixel = 0, AutoButtonColor = true,
				Text = v == "blocks" and "BLOCKS" or "LINES", FontFace = FONT.P2, TextSize = 20, ZIndex = 32, Parent = d })
			hoverable(b, function() sound("SOUND_HOVER") end, function() end)
			onClick(b, function() sfx("Click") setView(v) end)
			viewButtons[v] = b
		end

		-- the finished chip, or nil (and the problems shown) if it isn't ready
		local function collect()
			if not readLines() then sfx("Error") return nil end
			local problems = {}
			if #rules == 0 then table.insert(problems, "Add at least one WHEN block.") end
			for _, r in ipairs(rules) do
				if (r.ev == "pressed" or r.ev == "released") and not r.src then table.insert(problems, "Pick the item for every 'when ... pressed / released'.") end
			end
			Config.ChipEachAction(rules, function(a)
				if Config.CHIP_TARGET[a.op] and not a.target then table.insert(problems, "Pick an item for every action.") end
			end)
			if #problems == 0 then problems = Config.CheckChip(rules, Config.LabelKinds(E.ents)) end
			if #problems > 0 then
				errLabel.TextColor3 = rgb(200, 50, 50)
				errLabel.Text = table.concat(problems, "    ", 1, math.min(#problems, 3))
				sfx("Error")
				return nil
			end
			local text = (view == "lines" and linesBox) and linesBox.Text or Config.ChipText(rules)
			return { name = nameBox.Text ~= "" and nameBox.Text:sub(1, 30) or "Chip", src = text:sub(1, LIM.chipLen or 3000) }
		end

		dialogButton(d, 20, 610, "SAVE", function()
			local c = collect()
			if not c then return end
			closeDialog()
			pushUndo()
			if index and E.chips[index] then E.chips[index] = c else table.insert(E.chips, c) end
			Pal.refreshChips()
			flash(("Chip \"%s\" saved."):format(c.name))
		end, true)
		dialogButton(d, 196, 610, "TO MY CHIPS", function()
			local c = collect()
			if not c then return end
			task.spawn(function()
				local ok, list = netCall("ChipSave", { name = c.name, src = c.src })
				if ok then
					Pal.setLibrary(list)
					X.toast(("\"%s\" is in My Chips now."):format(c.name), "Chip saved", "chip")
				else
					flash(list or "Couldn't save the chip.")
				end
			end)
		end)
		if existing then
			dialogButton(d, 372, 610, "DELETE", function()
				closeDialog()
				pushUndo()
				table.remove(E.chips, index)
				Pal.refreshChips()
			end)
		end
		dialogButton(d, existing and 548 or 372, 610, "CANCEL", closeDialog)
		render()
	end

	Dlg.controls = function()
		local d = makeDialog("Controls", 600)
		new("TextLabel", { Position = px(20, 40), Size = px(520, 500), BackgroundTransparency = 1, FontFace = FONT.UI_REG, TextSize = 16, TextColor3 = rgb(30),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, LineHeight = 1.15, ZIndex = 32, Parent = d,
			Text = "MOUSE + KEYBOARD\n"
				.. "Click a panel to select it, drag across a wall to select an area. Shift+click selects everything between. Ctrl+click adds / removes one.\n"
				.. "+ / -  pull or push      P  portalable      T  paint with the last colour\n"
				.. "Middle-drag  orbit      Right-drag  pan      Wheel  zoom      WASD / Q E  move the camera\n"
				.. "C  connect      R  rotate      Delete  delete      Ctrl+Z / Y  undo / redo      Tab  game view      F9  build and play\n\n"
				.. "CONTROLLER\n"
				.. "Left stick  cursor      Right stick  orbit      LT + sticks  move camera      LB / RB  zoom\n"
				.. "A  click / drag      X  menu      Y  Items      B  cancel      D-pad  pull / push / rotate / portalable\n"
				.. "L3  connect      R3  game view      Back  build and play      Start  pause\n\n"
				.. "TOUCH\n"
				.. "Tap to select, drag across a wall to select an area, drag an item to move it.\n"
				.. "One finger on empty space orbits, two fingers pan and pinch zoom, hold for the menu.\n"
				.. "Use the toolbar along the bottom for pull / push / portal / paint / rotate / connect / delete." })
		dialogButton(d, 20, 550, "OK", closeDialog, true)
	end
end

-- ==========================================
-- BUILDING TEST CHAMBER SCREEN
-- ==========================================
local showBuilding, hideBuilding
local tipIndex = 0
do
	local buildGui = new("ScreenGui", { Name = "PortalBuilding", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 410, Enabled = false, Parent = playerGui })
	local dim = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(0), BackgroundTransparency = 0.5, BorderSizePixel = 0, Parent = buildGui })
	local bCanvas = new("Frame", { BackgroundTransparency = 1, Parent = buildGui })
	local bScale = new("UIScale", { Parent = bCanvas })
	local function rescaleBuild()
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
		bScale.Scale = vp.Y / 1080
		bCanvas.Size = px(vp.X / bScale.Scale, 1080)
	end
	local buildBlur = new("BlurEffect", { Name = "PortalBuildBlur", Size = 14, Enabled = false, Parent = game:GetService("Lighting") })

	local function gridPanel(x, y, w, h)
		local f = new("Frame", { Position = px(x, y), Size = px(w, h), BackgroundColor3 = rgb(255), BorderSizePixel = 0, ClipsDescendants = true, Parent = bCanvas })
		local grad = new("UIGradient", { Rotation = 90, Parent = f })
		for gx = 122, w - 1, 123 do new("Frame", { Position = px(gx, 0), Size = px(2, h), BackgroundColor3 = rgb(255), BackgroundTransparency = 0.82, BorderSizePixel = 0, Parent = f }) end
		for gy = 122, h - 1, 123 do new("Frame", { Position = px(0, gy), Size = px(w, 2), BackgroundColor3 = rgb(255), BackgroundTransparency = 0.82, BorderSizePixel = 0, Parent = f }) end
		return f, grad
	end
	local bTab, bTabGrad = gridPanel(225, 352, 672, 112)
	local bBody, bBodyGrad = gridPanel(225, 463, 784, 448)
	new("TextLabel", { Position = px(25, 0), Size = px(640, 112), BackgroundTransparency = 1, Text = "BUILDING TEST CHAMBER", FontFace = FONT.P2, TextSize = 58, TextColor3 = rgb(222, 236, 232), TextXAlignment = Enum.TextXAlignment.Left, Parent = bTab })
	new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = px(92, 112), Size = px(100, 100), BackgroundTransparency = 1, Image = SET.LOADING_LOGO, ScaleType = Enum.ScaleType.Fit, Parent = bBody })
	local segs = {}
	for k = 1, 12 do
		local a = math.rad(150 + k * 20)
		segs[k] = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = px(92 + math.sin(a) * 78, 112 - math.cos(a) * 78), Size = px(22, 9), Rotation = math.deg(a) + 90, BackgroundColor3 = rgb(110), BorderSizePixel = 0, Parent = bBody })
	end
	new("TextLabel", { Position = px(225, 40), Size = px(200, 24), BackgroundTransparency = 1, Text = "TIP", FontFace = FONT.P2_MED, TextSize = 20, TextColor3 = rgb(196, 210, 208), TextXAlignment = Enum.TextXAlignment.Left, Parent = bBody })
	local tipText = new("TextLabel", { Position = px(225, 80), Size = px(530, 220), BackgroundTransparency = 1, Text = "", FontFace = FONT.P2_MED, TextSize = 26, TextColor3 = rgb(232, 245, 244), TextWrapped = true, LineHeight = 1.2, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = bBody })
	local cancelBtn = new("TextButton", { Position = px(225, 929), Size = px(148, 34), BorderSizePixel = 0, AutoButtonColor = false, Text = "CANCEL", FontFace = FONT.P2, TextSize = 24, Selectable = false, Parent = bCanvas })
	cancelBtn.MouseEnter:Connect(function() sound("SOUND_HOVER") end)
	cancelBtn.MouseButton1Click:Connect(function()
		sfx("Click")
		E.cancel = true
	end)
	local spinConn

	showBuilding = function(glass)
		rescaleBuild()
		tipIndex = tipIndex % #SET.TIPS + 1
		tipText.Text = SET.TIPS[tipIndex]
		if glass then
			for _, g in ipairs({ bTabGrad, bBodyGrad }) do g.Color = ColorSequence.new(rgb(118, 127, 124), rgb(104, 112, 110)) end
			bTab.BackgroundTransparency, bBody.BackgroundTransparency = 0.25, 0.25
			cancelBtn.BackgroundColor3, cancelBtn.TextColor3 = rgb(209, 216, 214), rgb(20)
			dim.BackgroundTransparency = 0.75
			buildBlur.Enabled = true
		else
			for _, g in ipairs({ bTabGrad, bBodyGrad }) do g.Color = ColorSequence.new(rgb(46, 60, 62), rgb(30, 40, 43)) end
			bTab.BackgroundTransparency, bBody.BackgroundTransparency = 0, 0
			cancelBtn.BackgroundColor3, cancelBtn.TextColor3 = rgb(18, 24, 25), rgb(240)
			dim.BackgroundTransparency = 0.55
		end
		buildGui.Enabled = true
		local t = 0
		spinConn = RunService.RenderStepped:Connect(function(dt)
			t += dt * 10
			for k, s in ipairs(segs) do
				local d = (t - k) % 12
				s.BackgroundColor3 = rgb(math.floor(90 + math.clamp(5 - d, 0, 5) * 26))
			end
		end)
	end
	hideBuilding = function()
		buildGui.Enabled = false
		buildBlur.Enabled = false
		if spinConn then spinConn:Disconnect() spinConn = nil end
	end
end

-- ==========================================
-- TEAM SYNC
-- ==========================================
local syncEvent, cursorEvent
local loadData -- forward

local function sendSync()
	E.sentRev = E.rev
	if not (syncEvent and Team.teamSize() > 1) then return end
	E.lastSync = os.clock()
	syncEvent:FireServer("Data", { data = serialize() })
end

-- a teammate changed the chamber: take their version, keep the camera and (where it still exists) the selection
local function applyRemote(data)
	if type(data) ~= "table" then return end
	if E.drag or E.carry then E.pendingRemote = data return end
	E.pendingRemote = nil
	local selId = E.selItem and E.ents[E.selItem] and E.ents[E.selItem][8]
	local oldSel = E.sel
	loadData(data)
	E.selItem = nil
	if selId then
		for i, e in ipairs(E.ents) do
			if e[8] == selId then E.selItem = i end
		end
	end
	E.sel = oldSel
	table.clear(E.redo)
	E.dirty, E.stale = true, true
	E.sentRev = E.rev
	if E.linking and not entById(E.linking) then cancelLink() end
	rebuild()
end

-- ==========================================
-- SAVE / PLAYTEST / START / STOP
-- ==========================================
saveDraft = function(quiet)
	if not E.id then return end
	local ok, res = netCall("EditorSave", { id = E.id, data = serialize(), title = E.title })
	if ok then
		E.dirty = false
		if type(res) == "string" then E.title = res end
		if not quiet then flash("Test chamber saved.") end
	elseif not quiet then
		flash(res)
	end
end

local editLoopBound = false
local editLoop -- forward

local function enterPlaytest()
	E.playtest = true
	cancelLink()
	closeMenus()
	closeDialog()
	setDrone(false)
	gui.Enabled = false
	setEditing(false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local t0 = os.clock()
	while os.clock() - t0 < 3 do
		local c = player.Character
		if c and c:GetAttribute("HasPortalGun") and c:FindFirstChildOfClass("Humanoid") then break end
		task.wait()
	end
	local wcam = workspace.CurrentCamera
	wcam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then wcam.CameraSubject = hum end
	if controls then controls:Enable() end
	local overlay = playerGui:FindFirstChild("Overlay")
	if overlay then overlay.Enabled = player:GetAttribute("Setting_crosshair") ~= "Disabled" end
end

local function exitPlaytest()
	if not E.playtest then return end
	netCall("EditorEdit")
	E.playtest = false
	gui.Enabled = true
	setEditing(true)
	if controls then controls:Disable() end
	E.lastCull = nil
	E.chromeHold = os.clock() + 2
	if E.pendingRemote then applyRemote(E.pendingRemote) end
	setDrone(true)
end

local function buildAndPlay()
	if not E.active or E.building then return end
	E.building = true
	E.cancel = false
	closeMenus()
	cancelLink()
	local fromPlay = E.playtest
	local data = serialize()
	if not Config.ExitCanOpen(data) then
		-- still builds (so you can look around), but you can't finish it like this
		X.toast("Nothing opens the exit door yet. Connect a button to it (select the button, press C, click the exit), use a chip, or right-click the exit > Open without a button.",
			"Exit door is locked", "locked")
	end
	showBuilding(fromPlay)
	sendSync()
	task.spawn(saveDraft, true)
	local done, ok, err = false, nil, nil
	task.spawn(function()
		ok, err = netCall("EditorTest", { id = E.id, data = data })
		done = true
	end)
	local t0 = os.clock()
	while (not done or os.clock() - t0 < SET.BUILD_TIME) and not E.cancel do task.wait() end
	local cancelled = E.cancel
	E.cancel = false
	hideBuilding()
	E.building = false
	if cancelled then
		if not fromPlay then
			task.spawn(function()
				while not done do task.wait() end
				netCall("EditorEdit")
			end)
		end
		return
	end
	if not ok then
		flash(err)
		sfx("Error")
		return
	end
	E.stale = false
	enterPlaytest()
end

local function restartLevel()
	if not E.playtest then return end
	local ok, err = netCall("EditorTest", { id = E.id, data = serialize() })
	if not ok then flash(err) end
end

local touchBar -- forward (built below)

local function stop(keepServerState)
	if not E.active then return end
	if E.dirty and E.id then task.spawn(saveDraft, true) end
	E.active, E.playtest, E.building, E.linking = false, false, false, nil
	E.mmb, E.rmb, E.carry, E.touch, E.pinch, E.touchOrbit = false, nil, nil, nil, nil, false
	E.team, E.guest, E.pendingRemote = nil, false, nil
	Team.clearMarkers()
	Team.refreshTeamBox()
	connectGui.hide()
	setDrone(false)
	gui.Enabled = false
	setEditing(false)
	hideBuilding()
	closeMenus()
	closeDialog()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	if editLoopBound then RunService:UnbindFromRenderStep("PortalEditor") editLoopBound = false end
	local wcam = workspace.CurrentCamera
	wcam.CameraType = Enum.CameraType.Custom
	if controls then controls:Enable() end
	if not keepServerState then netCall("EditorExit") end
end

local function frameCamera()
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for k in pairs(E.air) do
		local x, y, z = parse(k)
		local v = Vector3.new(x, y, z)
		mn, mx = mn:Min(v), mx:Max(v)
	end
	if mn.X == math.huge then return end
	E.target = (mn + mx) / 2 * CELL + W
	E.dist = math.max(((mx - mn) + Vector3.new(1, 1, 1)).Magnitude * CELL * 2.1, 120)
	E.cYaw, E.cPitch, E.cDist, E.cTarget = E.yaw, E.pitch, E.dist, E.target
end

loadData = function(data)
	E.air, E.faces, E.colors, E.ents, E.links = {}, {}, {}, {}, {}
	E.textures, E.chips = {}, {}
	for k, v in pairs(type(data.textures) == "table" and data.textures or {}) do
		if Config.ValidTextureValue(v) then E.textures[k] = v end
	end
	for _, c in ipairs(type(data.chips) == "table" and data.chips or {}) do
		if type(c) == "table" and type(c.src) == "string" then table.insert(E.chips, { name = tostring(c.name or "Chip"), src = c.src }) end
	end
	E.coop = data.coop == true
	for _, c in ipairs(data.air or {}) do E.air[key(c[1], c[2], c[3])] = true end
	for k, v in pairs(data.faces or {}) do if v == 0 or v == 2 or v == 3 then E.faces[k] = v end end
	for k, v in pairs(type(data.colors) == "table" and data.colors or {}) do
		local idx = tonumber(v)
		if idx and Config.TILE_COLORS[idx] then E.colors[k] = idx end
	end
	for _, e in ipairs(data.ents or {}) do
		local c = table.clone(e)
		if c[7] == false then c[7] = nil end
		if c[9] == false then c[9] = nil end
		if c[10] == false then c[10] = nil end
		c[8] = c[8] or newId()
		table.insert(E.ents, c)
	end
	for _, l in ipairs(data.links or {}) do
		if type(l) == "table" then table.insert(E.links, { l[1], l[2] }) end
	end
	Config.AutoLabel(E.ents) -- chips talk about items by label
end

-- ----- Export / Import: the chamber as text, for Studio (ServerStorage.ChamberStudioTools) or another chamber -----
do
	local HttpService = game:GetService("HttpService")
	local FORMAT = "PortalChamber"
	local function textArea(parent, text, placeholder)
		local sc = new("ScrollingFrame", { Position = px(20, 40), Size = px(620, 300), BackgroundColor3 = rgb(255), BorderSizePixel = 0,
			ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = px(0, 0), ZIndex = 32, Parent = parent })
		local box = new("TextBox", { Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
			Text = text, PlaceholderText = placeholder or "", MultiLine = true, TextWrapped = true, ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Code, TextSize = 14,
			TextColor3 = rgb(25), PlaceholderColor3 = rgb(150), ZIndex = 33, Parent = sc })
		new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), Parent = box })
		return box
	end

	function X.exportText()
		return HttpService:JSONEncode({ format = FORMAT, version = Config.VERSION, title = E.title, coop = E.coop, data = serialize() })
	end

	-- File > Export: copy the text (Ctrl+A, Ctrl+C), paste it into Studio's ChamberImport StringValue
	function X.export()
		local ok, text = pcall(X.exportText)
		if not ok then flash("Couldn't export: " .. tostring(text)) sfx("Error") return end
		local d = Dlg.makeDialog("Export Test Chamber", 420, 660)
		local box = textArea(d, text)
		box.TextEditable = false
		new("TextLabel", { Position = px(20, 344), Size = px(620, 22), BackgroundTransparency = 1, FontFace = FONT.UI_REG, TextSize = 14,
			TextColor3 = rgb(80), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32, Parent = d,
			Text = ("%d characters. Select it all and copy it (Ctrl+A, Ctrl+C), then File > Import here or ChamberStudioTools in Studio."):format(#text) })
		Dlg.dialogButton(d, 20, 372, "SELECT ALL", function()
			box:CaptureFocus()
			box.SelectionStart = 1
			box.CursorPosition = #box.Text + 1
		end, true)
		Dlg.dialogButton(d, 196, 372, "CLOSE", closeDialog)
	end

	-- the data out of an export (or bare chamber data). Returns data, title, coop / nil, error
	function X.readImport(text)
		local ok, t = pcall(HttpService.JSONDecode, HttpService, text)
		if not ok or type(t) ~= "table" then return nil, "That isn't chamber text (it should start with {\"format\":\"PortalChamber\" ...)." end
		local data = (t.format == FORMAT and type(t.data) == "table") and t.data or t
		if type(data.air) ~= "table" or #data.air == 0 then return nil, "There's no room in that text." end
		if #data.air > (LIM.cells or 4000) then return nil, "That chamber is too big for the editor." end
		local doors = {}
		for _, e in ipairs(type(data.ents) == "table" and data.ents or {}) do
			if type(e) == "table" and (e[1] == "entry" or e[1] == "exit") then doors[e[1]] = true end
		end
		if not (doors.entry and doors.exit) then return nil, "That chamber has no entry or exit door." end
		return data, type(t.title) == "string" and t.title or nil, t.coop == true or data.coop == true
	end

	-- File > Import: paste an export; replaces this chamber (Ctrl+Z puts it back)
	function X.import()
		local d = Dlg.makeDialog("Import Test Chamber", 420, 660)
		local box = textArea(d, "", "Paste the text from File > Export or from ChamberStudioTools.Export (ServerStorage.ChamberExport) here")
		local note = new("TextLabel", { Position = px(20, 344), Size = px(620, 22), BackgroundTransparency = 1, FontFace = FONT.UI_REG, TextSize = 14,
			TextColor3 = rgb(80), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32, Parent = d,
			Text = "This replaces the chamber you have open. Ctrl+Z undoes it." })
		Dlg.dialogButton(d, 20, 372, "IMPORT", function()
			local data, err = X.readImport(box.Text)
			if not data then note.Text = err note.TextColor3 = rgb(200, 50, 50) sfx("Error") return end
			closeDialog()
			pushUndo()
			loadData(data)
			E.coop = data.coop == true
			E.sel, E.selItem, E.anchor = {}, nil, nil
			rebuild()
			frameCamera()
			if Pal.refreshChips and Pal.tab == "chips" then Pal.refreshChips() end
			flash("Imported the chamber.")
			X.toast("Imported " .. (#E.ents) .. " items. Ctrl+Z undoes it.", "Import", "good")
		end, true)
		Dlg.dialogButton(d, 196, 372, "CANCEL", closeDialog)
	end
end

local function start(payload)
	stop(true)
	E.active = true
	E.playtest = false
	E.id, E.title = payload.id, payload.title or "Untitled Chamber"
	E.team = type(payload.team) == "table" and payload.team or nil
	E.guest = payload.guest == true
	loadData(payload.data or Config.DefaultChamber())
	E.undo, E.redo, E.sel, E.selItem, E.anchor, E.linking, E.dirty, E.stale = {}, {}, {}, nil, nil, nil, false, true
	E.rev, E.sentRev, E.pendingRemote = 0, 0, nil
	E.gameView = false
	if X.clearGameView then X.clearGameView() end
	E.chromeHold = os.clock() + 2.5
	if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then E.pointerMode = "touch" end
	if string.find(UserInputService:GetLastInputType().Name, "Gamepad", 1, true) then usePad() end
	setEditing(true)
	frameCamera()
	applyCamera()
	rebuild()
	Pal.build()
	Pal.set(E.pointerMode == "mouse")
	-- Toolbox models this chamber uses: ask the server to load them, then redraw the items
	task.spawn(function()
		local want = {}
		for _, e in ipairs(E.ents) do
			local v = e[1] == "prop" and type(e[7]) == "string" and e[7] or ""
			local aid = v:match("^asset:(%d+)$")
			if aid and not Config.ToolboxModel(aid) then want[aid] = { kind = "meshes", id = tonumber(aid), key = aid } end
			local tbid = v:match("^tbmesh:(%d+)$")
			if tbid and not Config.ToolboxModel("tbmesh_" .. tbid) then want[v] = { kind = "toolboxmesh", id = tonumber(tbid), key = "tbmesh_" .. tbid } end
			local mid, tid = v:match("^mesh:(%d+):?(%d*)$")
			tid = tid ~= "" and tid or nil
			if mid and not Config.ToolboxModel(Config.MeshKey(mid, tid)) then
				want[v] = { kind = "mesh", id = tonumber(mid), tex = tonumber(tid), key = Config.MeshKey(mid, tid) }
			end
		end
		local any = false
		for _, w in pairs(want) do
			local ok = netCall("ToolboxLoad", { kind = w.kind, id = w.id, tex = w.tex })
			local f = ok and ReplicatedStorage:WaitForChild(Config.TOOLBOX_FOLDER, 10)
			if f and f:WaitForChild(w.key, 10) then any = true end
		end
		if any and E.active then rebuildEnts() end
	end)
	rescaleUI()
	Team.refreshTeamBox()
	gui.Enabled = true
	setDrone(true)
	if controls then controls:Disable() end
	RunService:BindToRenderStep("PortalEditor", Enum.RenderPriority.Last.Value + 20, editLoop)
	editLoopBound = true
	if E.guest then flash("You joined the team. Everything you build is shared.") end
	task.delay(1.5, function() if E.active and not E.playtest then X.tutorial(false) end end)
	task.spawn(function()
		while E.active do
			task.wait(60)
			if E.active and E.dirty and not E.playtest then saveDraft(true) end
		end
	end)
end

local exitEditor, newChamber, toggleGameView
do
-- ==========================================
-- MENUS (File / Edit / Help + toolbar)
-- ==========================================
exitEditor = function()
	saveDraft(true)
	menuRequest("ExitToMain")
end

newChamber = function()
	task.spawn(function()
		saveDraft(true)
		local ok, err = netCall("CommunityCreate", nil)
		if not ok then flash(err) end
	end)
end

-- GAME VIEW (Tab): the chamber built the way it will look in game (real tiles, textures, item models, antlines),
-- right here in the editor. Nothing is built on the server and you don't leave the editor. Tab again to keep editing.
do
	local preview, panels = nil, {}
	local function editorBits() return { roomFolder, entFolder, H.model, H.previewRoot, fxFolder } end
	function X.clearGameView()
		if preview then preview:Destroy() preview = nil end
		table.clear(panels)
		for _, f in ipairs(editorBits()) do f.Parent = world end
	end
	function X.cullGameView(camPos)
		for _, p in ipairs(panels) do
			if p.part.Parent then
				p.part.LocalTransparencyModifier = ((camPos - p.part.Position):Dot(p.normal) > 0) and 0 or 1
			end
		end
	end
	function X.buildGameView()
		if preview then preview:Destroy() preview = nil end
		table.clear(panels)
		for _, f in ipairs(editorBits()) do f.Parent = nil end
		local ok, m = pcall(Config.BuildChamber, serialize(), nil, W, {})
		if not ok or not m then
			warn("[PortalMapEditor] game view:", m)
			flash("Couldn't draw the game view.")
			return
		end
		-- a still picture: no tags, scripts or sounds, and no names the test element scripts react to
		for _, t in ipairs(m:GetTags()) do m:RemoveTag(t) end
		for _, d in ipairs(m:GetDescendants()) do
			for _, t in ipairs(d:GetTags()) do d:RemoveTag(t) end
			if d:IsA("Sound") then
				d:Destroy()
			elseif d:IsA("BaseScript") then
				d.Enabled = false
			elseif d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery = true, false, false, false
				local fk = d.Name == "Panel" and d:GetAttribute("Face")
				local f = fk and select(4, parseFace(fk))
				if f then table.insert(panels, { part = d, normal = -DIRS[f] }) end
			elseif d:IsA("Model") then
				d.Name = "EditorPiece"
			end
		end
		m.Name = "GameView"
		m.Parent = world
		preview = m
		X.cullGameView(cam.CFrame.Position)
	end
end

local eyeIcon
toggleGameView = function()
	E.gameView = not E.gameView
	if E.gameView then
		cancelLink()
		closeMenus()
		E.sel, E.selItem, E.drag = {}, nil, nil
		refreshSelection()
		X.buildGameView()
		flash("Game view: this is how your chamber will look. Press Tab to keep editing.")
	else
		X.clearGameView()
		rebuild()
	end
	E.lastCull = nil
	if eyeIcon then eyeIcon.ImageColor3 = E.gameView and C.ICON_ON or C.ICON end
	sfx("Click")
end

local MENUS = {
	File = function()
		local g = E.guest
		local items = {
			{ text = "New chamber", shortcut = "Ctrl+N", disabled = g, fn = newChamber },
			{ text = "Open...", shortcut = "Ctrl+O", disabled = g, fn = function() task.spawn(Dlg.open) end },
			{ text = "Save", shortcut = "Ctrl+S", fn = function() task.spawn(saveDraft, false) end },
			{ text = "Save as...", shortcut = "Ctrl+Sh+S", disabled = g, fn = Dlg.saveAs },
			{ text = "Export...", fn = function() X.export() end },
			{ text = "Import...", fn = function() X.import() end },
			{ text = "Cooperative puzzle", icon = "check", checked = E.coop, sep = true, fn = function() E.coop = not E.coop E.dirty = true E.rev += 1 end },
			{ text = E.gameView and "Editor view" or "Game view", shortcut = "Tab", fn = toggleGameView },
			{ text = "Editor style", sub = function()
				local list = {}
				for _, st in ipairs(X.STYLES or { "Classic" }) do
					table.insert(list, { text = st, icon = "radio", checked = ES("edStyle", "Classic") == st, fn = function()
						menuRequest("SetSetting", { key = "edStyle", value = st })
					end })
				end
				return list
			end },
			{ text = "Editor mode", sub = function()
				local list = {}
				for _, m in ipairs({ "Simple", "Intermediate", "Advanced" }) do
					table.insert(list, { text = m, icon = "radio", checked = ES("edMode", "Simple") == m, fn = function()
						menuRequest("SetSetting", { key = "edMode", value = m }) -- saved with the rest of the options
					end })
				end
				return list
			end },
			{ text = "Rebuild...", shortcut = "F9", fn = function() task.spawn(buildAndPlay) end },
			{ text = "Publish...", disabled = g, fn = Dlg.publish, sep = true },
		}
		if g then
			table.insert(items, { text = "Leave team", sep = true, fn = function() menuRequest("ExitToMain") end })
		else
			table.insert(items, { text = "Invite team builder...", sep = Team.teamSize() < 2, fn = Dlg.invite })
			if Team.teamSize() > 1 then
				table.insert(items, { text = "Remove team builder", sep = true, sub = function()
					local list = {}
					for _, m in ipairs(E.team.members) do
						if m.id ~= player.UserId then
							table.insert(list, { text = m.name, fn = function()
								task.spawn(function()
									local ok = netCall("TeamKick", m.id)
									if ok then flash(m.name .. " was removed from the team.") end
								end)
							end })
						end
					end
					return list
				end })
			end
		end
		table.insert(items, { text = "Exit editor", shortcut = "Ctrl+Q", fn = exitEditor })
		return items
	end,
	Edit = function() return {
		{ text = "Undo", shortcut = "Ctrl+Z", icon = "glyph", glyph = "↶", disabled = #E.undo == 0, fn = undo },
		{ text = "Redo", shortcut = "Ctrl+Y", icon = "glyph", glyph = "↷", disabled = #E.redo == 0, fn = redo, sep = true },
		{ text = "Select all", shortcut = "Ctrl+A", fn = selectAll },
		} end,
	Help = function() return {
		{ text = "Tips...", fn = function() tipIndex = tipIndex % #SET.TIPS + 1 flash(SET.TIPS[tipIndex]) end },
		{ text = "Controls...", fn = Dlg.controls },
		{ text = "Tutorial...", fn = function() X.tutorial(true) end },
		{ text = "Wiki...", shortcut = "F1", fn = function() Dlg.wiki() end },
		} end,
}
-- File / Edit / Help: x is where the word starts in the footage
for _, def in ipairs({ { "File", 16, 46 }, { "Edit", 89, 48 }, { "Help", 166, 52 } }) do
	local name, tx, w = def[1], def[2], def[3]
	local b = ui(new("TextButton", { Position = L(tx - 6, 2), Size = px(w + 12, 30), BackgroundTransparency = 1, AutoButtonColor = false,
		Text = name, FontFace = FONT.UI, TextSize = 20, TextColor3 = C.MENU_TEXT, Selectable = false, ZIndex = 4, Parent = menuRow }))
	local open = false
	if name == "File" then X.fileBtn = b end
	table.insert(menuButtons, { reset = function() open = false b.TextColor3 = C.MENU_TEXT end })
	hoverable(b, function() b.TextColor3 = C.MENU_HI sound("SOUND_HOVER") end, function() if not open then b.TextColor3 = C.MENU_TEXT end end)
	onClick(b, function()
		sfx("Click")
		popupMenu(menuRow.Position.X.Offset + tx - 8, 32, { { items = MENUS[name]() } })
		open = true
		b.TextColor3 = C.MENU_HI
	end)
end

-- toolbar in the top recess: cx = centre offset from the middle of the screen
local function toolButton(cx, w, h, image, tip, fn)
	local hit = ui(new("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = M(cx, 18), Size = px(44, 32), BackgroundTransparency = 1,
		AutoButtonColor = false, Text = "", Selectable = false, ZIndex = 4, Parent = chrome }))
	local icon = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = px(w, h), BackgroundTransparency = 1,
		Image = image, ImageColor3 = C.ICON, ScaleType = Enum.ScaleType.Stretch, ZIndex = 5, Parent = hit })
	local function base() return (icon == eyeIcon and E.gameView) and C.ICON_ON or C.ICON end
	hoverable(hit, function()
		icon.ImageColor3 = C.ICON_HI
		tooltip.Text = type(tip) == "function" and tip() or tip
		sound("SOUND_HOVER")
	end, function()
		icon.ImageColor3 = base()
		if not E.linking then tooltip.Text = "" end
	end)
	onClick(hit, function()
		fn()
		if type(tip) == "function" then tooltip.Text = tip() end
	end)
	return icon
end
X.playBtn = toolButton(-73, 23, 19, SET.ICONS.play, "Build and play (F9)", function() sfx("Click") task.spawn(buildAndPlay) end).Parent -- stretched a bit wider
toolButton(-25, 30, 24, SET.ICONS.undo, "Undo (Ctrl+Z)", undo)
toolButton(24, 30, 24, SET.ICONS.redo, "Redo (Ctrl+Y)", redo)
eyeIcon = toolButton(73, 32, 22, SET.ICONS.eye, function() return E.gameView and "Switch to editor view (Tab)" or "Switch to game view (Tab)" end, toggleGameView)
X.eyeBtn = eyeIcon.Parent

-- ==========================================
-- TUTORIAL (points at the real GUI; Options > Gameplay > Tutorials turns it off, Help > Tutorial shows it again)
-- ==========================================
-- Each step outlines what it talks about (the palette, the tabs your editor mode has, play, game view, File) or lights
-- up an item in the room (the exit door). The steps follow the editor mode, so you never get told about tabs you
-- don't have.
do
	local layer = new("Frame", { Name = "Tutorial", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 90, Parent = canvas })
	local ring = new("Frame", { BackgroundTransparency = 1, Visible = false, ZIndex = 91, Parent = layer })
	local ringStroke = new("UIStroke", { Color = rgb(40, 210, 235), Thickness = 4, Parent = ring })
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = ring })
	-- same look as the editor's dialogs: light panel, dark header strip with the title on the right, square corners
	local card = ui(new("Frame", { Size = px(470, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.CTX_BG, BackgroundTransparency = 0.04,
		BorderSizePixel = 0, Active = true, ZIndex = 95, Parent = layer }))
	new("UIStroke", { Color = C.CTX_EDGE, Thickness = 1, Parent = card })
	new("UIPadding", { PaddingLeft = UDim.new(0, 0), PaddingRight = UDim.new(0, 0), PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 14), Parent = card })
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = card })
	local headBar = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = C.CTX_HEAD, BackgroundTransparency = 0.2, BorderSizePixel = 0,
		LayoutOrder = 1, ZIndex = 96, Parent = card })
	local head = new("TextLabel", { Size = UDim2.new(1, -12, 1, 0), BackgroundTransparency = 1, Text = "", FontFace = FONT.UI_REG, TextSize = 15,
		TextColor3 = rgb(236), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 97, Parent = headBar })
	local title = new("TextLabel", { Size = UDim2.new(1, -36, 0, 30), BackgroundTransparency = 1, Text = "", FontFace = FONT.P2, TextSize = 28,
		TextColor3 = C.CTX_TEXT, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, ZIndex = 96, Parent = card })
	local body = new("TextLabel", { Size = UDim2.new(1, -36, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = "",
		FontFace = FONT.UI_REG, TextSize = 18, TextWrapped = true, TextColor3 = rgb(40), TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3, ZIndex = 96, Parent = card })
	local row = new("Frame", { Size = UDim2.new(1, -36, 0, 34), BackgroundTransparency = 1, LayoutOrder = 4, ZIndex = 96, Parent = card })
	local steps, idx, conn = nil, 1, nil
	local shown = false
	local render, close

	local function button(x, w, text, fn, blue)
		-- the editor's dialog buttons
		local b = new("TextButton", { Position = px(x, 4), Size = px(w, 30), BorderSizePixel = 0, AutoButtonColor = true,
			BackgroundColor3 = blue and rgb(77, 128, 151) or rgb(200, 206, 203), Text = text, FontFace = FONT.P2, TextSize = 17,
			TextColor3 = blue and rgb(245) or rgb(20), ZIndex = 97, Parent = row })
		hoverable(b, function() sound("SOUND_HOVER") end, function() end)
		onClick(b, function() sfx("Click") fn() end)
		return b
	end

	-- what the steps point at (functions: the GUI exists by the time a step shows)
	local function tabButton(id) return function() Pal.set(true) return Pal.tabs[id] and Pal.tabs[id].button end end
	local function exitIndex()
		for i, e in ipairs(E.ents) do if e[1] == "exit" then return i end end
	end
	local function buildSteps()
		local lvl = Pal.level()
		local touch = E.pointerMode == "touch"
		local pad = E.pointerMode == "pad"
		local list = {
			{ "The test chamber editor", "You build a test chamber here, then play it. NEXT walks you through the screen, SKIP closes this." },
			{ "Selecting surfaces", touch and "Tap a panel to select it (it turns yellow). Drag across a wall to select an area."
				or pad and "Move the cursor with the left stick, A selects a panel. Hold A and move to select an area."
				or "Click a panel to select it (it turns yellow). Drag across a wall to select an area, Shift+click to add everything in between." },
			{ "Shaping the room", touch and "Use PULL + and PUSH - on the toolbar to move the selected panels. One finger orbits, two fingers pan and zoom."
				or pad and "D-pad up / down pulls or pushes the selected panels. The right stick orbits, LB / RB zoom."
				or "+ pulls the selected panels toward you, - pushes them away. Middle-drag orbits, right-drag pans, the wheel zooms, WASD / Q E move.",
				target = touch and function() return touchBar end or nil },
			{ "Items", (touch and "Tap the strip on the left" or pad and "Press Y" or "Move to the strip on the left")
				.. " to open this palette, then drag an item onto a panel. Right-click an item (X on a controller) for its options.",
				target = function() Pal.set(true) return Pal.body end },
			{ "The exit door", "The exit stays locked until something opens it. Select a button, press C (L3), then click the exit door. Or right-click the exit > Open without a button.",
				item = exitIndex },
		}
		if lvl >= 2 then
			table.insert(list, { "Textures", "Select surfaces in the room, then click a texture here, or paste an image id.", target = tabButton("textures") })
			table.insert(list, { "Meshes", "MeshParts from your game, or paste any Mesh id to make one. Drag it in, right-click it to resize.", target = tabButton("meshes") })
		end
		if lvl >= 3 then
			table.insert(list, { "My Chips", "Little programs: \"when button1 pressed\" -> \"open exit\". Build them from blocks or type them as lines (with colours and auto correct).",
				target = tabButton("chips") })
		else
			table.insert(list, { "More tools", "File > Editor mode (or Options > Editor) switches to Intermediate for Textures and Meshes, or Advanced for My Chips too.",
				target = function() return X.fileBtn end })
		end
		table.insert(list, { "Build and play", "This button (or " .. (pad and "Back / View" or "F9") .. ") builds your chamber and drops you in. Pause > Exit To Editor comes back.",
			target = function() return X.playBtn end })
		table.insert(list, { "Game view", "The eye (or " .. (pad and "R3" or "Tab") .. ") shows how the chamber will look in game, without building it.",
			target = function() return X.eyeBtn end })
		table.insert(list, { "Saving and more", "File has Save, Open, Publish and Editor mode. Help > Tutorial shows this again.",
			target = function() return X.fileBtn end })
		return list
	end

	-- canvas-space rect of a GUI object
	local function rectOf(o)
		local p = (o.AbsolutePosition - canvas.AbsolutePosition) / uiScale.Scale
		local s = o.AbsoluteSize / uiScale.Scale
		return p, s
	end

	local function place()
		if not steps then return end
		local st = steps[idx]
		local target = st.target and st.target()
		local cw = canvasWidth()
		local cs = card.AbsoluteSize / uiScale.Scale
		if target and target.Parent and target.AbsoluteSize.X > 0 then
			local p, s = rectOf(target)
			ring.Visible = true
			ring.Position, ring.Size = px(p.X - 6, p.Y - 6), px(s.X + 12, s.Y + 12)
			-- next to the target: to its right if there's room, else under it, else above it
			local x, y
			if p.X + s.X + 24 + cs.X < cw then
				x, y = p.X + s.X + 24, math.clamp(p.Y, 60, REF_H - cs.Y - 20)
			elseif p.Y + s.Y + 24 + cs.Y < REF_H then
				x, y = math.clamp(p.X, 20, cw - cs.X - 20), p.Y + s.Y + 24
			else
				x, y = math.clamp(p.X, 20, cw - cs.X - 20), math.max(p.Y - cs.Y - 24, 20)
			end
			card.Position = px(x, y)
		else
			ring.Visible = false
			card.Position = px(math.floor((cw - cs.X) / 2), REF_H - cs.Y - 120)
		end
		ringStroke.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 5))
		E.chromeHold = os.clock() + 0.5 -- keep the frame (File, play, eye) visible while it's being pointed at
	end

	close = function()
		steps = nil
		layer.Visible = false
		if conn then conn:Disconnect() conn = nil end
		if H.highlight then H.highlight(nil) end
	end
	render = function()
		local st = steps[idx]
		head.Text = ("TUTORIAL   %d / %d"):format(idx, #steps)
		title.Text = st[1]
		body.Text = st[2]
		X.tutNext.Text = idx >= #steps and "DONE" or "NEXT"
		local item = st.item and st.item()
		if H.highlight then H.highlight(item, rgb(40, 210, 235)) end
		place()
	end
	button(0, 90, "BACK", function() if steps and idx > 1 then idx -= 1 render() end end)
	X.tutNext = button(98, 90, "NEXT", function()
		if not steps then return end
		if idx < #steps then idx += 1 render() else close() end
	end, true)
	button(196, 70, "SKIP", function() close() end)
	button(274, 160, "DON'T SHOW AGAIN", function()
		close()
		menuRequest("SetSetting", { key = "tutorial", value = "Disabled" })
		flash("Tutorials are off. Turn them back on in Options > Gameplay.")
	end)

	-- force = Help > Tutorial (shows even if tutorials are turned off)
	function X.tutorial(force)
		if not E.active or E.playtest then return end
		if not force and (shown or ES("tutorial", "Enabled") == "Disabled") then return end
		shown = true
		closeMenus()
		steps, idx = buildSteps(), 1
		layer.Visible = true
		render()
		if conn then conn:Disconnect() end
		conn = RunService.RenderStepped:Connect(function()
			if not E.active or E.playtest then close() return end
			place()
		end)
	end
	X.closeTutorial = close
	player:GetAttributeChangedSignal("Setting_tutorial"):Connect(function()
		if ES("tutorial", "Enabled") == "Disabled" then close() end
	end)
end

end
-- ==========================================
-- HANDLES / PREVIEWS / HIGHLIGHT
-- ==========================================
do
	local HANDLE_GREY = rgb(118, 122, 120)
	local HANDLE_OLIVE = rgb(150, 150, 62)
	local function tag(p, attrs)
		for k, v in pairs(attrs) do p:SetAttribute(k, v) end
		return p
	end
	-- flat diamond lying on a surface (normal n)
	local function diamond(pos, n, size, color, attrs)
		tag(new("Part", { Anchored = true, CanCollide = false, CastShadow = false, CanQuery = true, Material = Enum.Material.SmoothPlastic,
			Color = color, Size = Vector3.new(size, size, 0.12), CFrame = CFrame.lookAt(pos, pos + n) * CFrame.Angles(0, 0, math.rad(45)),
			Parent = H.model }), attrs)
	end
	-- flat triangle: base centre B, pointing along D, lying in the plane with normal N
	local function arrow(B, D, N, len, width, color, attrs)
		local S = N:Cross(D)
		if S.Magnitude < 1e-3 then return end
		S = S.Unit
		for _, sgn in ipairs({ 1, -1 }) do
			local vY, vZ = S * sgn, -D
			local vX = vY:Cross(vZ)
			tag(new("WedgePart", { Anchored = true, CanCollide = false, CastShadow = false, CanQuery = true, Material = Enum.Material.SmoothPlastic,
				Color = color, Size = Vector3.new(0.12, width / 2, len), CFrame = CFrame.fromMatrix(B + vY * (width / 4) + D * (len / 2), vX, vY, vZ),
				Parent = H.model }), attrs)
		end
	end

	H.update = function()
		H.model:ClearAllChildren()
		local i = E.selItem
		local e = i and E.ents[i]
		local def = e and Config.ENTITY_TYPES[e[1]]
		if not def or E.playtest then return end
		local fp = E.faceParts[faceKey(e[2], e[3], e[4], e[5])]
		if fp and not fp.shown then return end
		-- rotation diamonds: click the one on the edge you want the item on
		if (def.mount == "wall" and not def.needsFloor) or (def.mount == "any" and not def.upright and e[1] ~= "gate" and e[1] ~= "lasercatcher") then
			for r = 0, 3 do
				local probe = table.clone(e)
				probe[6] = r
				local fr = Config.ItemFrame(W, probe)
				local n, down = fr.LookVector, -fr.UpVector
				local cur = (e[6] or 0) % 4 == r
				diamond(fr.Position + down * (CELL * 0.36) + n * 0.35, n, cur and 1.9 or 1.1, cur and HANDLE_GREY or HANDLE_OLIVE, { Handle = "rot", Index = i, Rot = r })
				diamond(fr.Position + down * (CELL * 0.15) + n * 0.35, n, 0.9, HANDLE_OLIVE, { Handle = "rot", Index = i, Rot = r })
			end
		end
		-- stretch triangles on emitter 2 (fizzlers, laser fields)
		local m = E.entModels[i]
		local hp = def.span and m and m:GetAttribute("SpanEnd")
		if hp then
			local fr = Config.ItemFrame(W, e)
			local u = fr.LookVector
			local N = math.abs(u.Y) < 0.9 and Vector3.yAxis or fr.UpVector
			arrow(hp + u * 0.4, u, N, 1.8, 2.2, HANDLE_GREY, { Handle = "span", Index = i })
			arrow(hp - u * 0.4, -u, N, 1.8, 2.2, HANDLE_GREY, { Handle = "span", Index = i })
		end
		-- goo: a pair of triangles on every edge, drag to grow / shrink that side
		if def.fitCell then
			local o = Config.Options(e)
			local x0, x1, z0, z1 = o.gx0 or 0, o.gx1 or 0, o.gz0 or 0, o.gz1 or 0
			local c = W + Vector3.new(e[2], e[3], e[4]) * CELL + DIRS[e[5]] * (CELL / 2) + Vector3.new(0, 1, 0)
			local cx, cz = (x1 - x0) / 2 * CELL, (z1 - z0) / 2 * CELL
			for _, sd in ipairs({
				{ "gx1", Vector3.xAxis, c + Vector3.new(CELL / 2 + x1 * CELL, 0, cz) },
				{ "gx0", -Vector3.xAxis, c + Vector3.new(-(CELL / 2 + x0 * CELL), 0, cz) },
				{ "gz1", Vector3.zAxis, c + Vector3.new(cx, 0, CELL / 2 + z1 * CELL) },
				{ "gz0", -Vector3.zAxis, c + Vector3.new(cx, 0, -(CELL / 2 + z0 * CELL)) },
				}) do
				arrow(sd[3] + sd[2] * 0.3, sd[2], Vector3.yAxis, 1.8, 2.2, HANDLE_GREY, { Handle = "goo", Index = i, Side = sd[1] })
				arrow(sd[3] - sd[2] * 0.3, -sd[2], Vector3.yAxis, 1.8, 2.2, HANDLE_GREY, { Handle = "goo", Index = i, Side = sd[1] })
			end
		end
		-- faith plate: yellow ball at the top of the arc, the bullseye can be grabbed too
		if e[1] == "faithplate" then
			local path = Config.FaithPath(e, W, E.air)
			local _, apex = Config.FaithPoints(path, 2)
			tag(new("Part", { Shape = Enum.PartType.Ball, Anchored = true, CanCollide = false, CastShadow = false, CanQuery = true,
				Material = Enum.Material.SmoothPlastic, Color = rgb(238, 214, 84), Size = Vector3.one * 2.6, CFrame = CFrame.new(apex),
				Parent = H.model }), { Handle = "fpball", Index = i })
			if not path.up then
				tag(new("Part", { Shape = Enum.PartType.Cylinder, Anchored = true, CanCollide = false, CastShadow = false, CanQuery = true,
					Transparency = 1, Size = Vector3.new(0.3, 7.5, 7.5),
					CFrame = CFrame.lookAt(path.surface, path.surface + path.normal) * CFrame.new(0, 0, -0.3) * CFrame.Angles(0, math.rad(90), 0),
					Parent = H.model }), { Handle = "fptarget", Index = i })
			end
		end
	end

	-- faith plate: dashed white arc + bullseye on the target (always shown, like the Puzzle Maker)
	local function fpPart(pm, props)
		props.Anchored, props.CanCollide, props.CanQuery, props.CastShadow = true, false, false, false
		props.Material = props.Material or Enum.Material.SmoothPlastic
		props.Parent = pm
		local p = new("Part", props)
		p:SetAttribute("BaseT", p.Transparency)
		return p
	end
	local function faithPreview(e)
		local pm = new("Model", { Name = "Preview", Parent = H.previewRoot })
		local path = Config.FaithPath(e, W, E.air)
		local pts = Config.FaithPoints(path, 30)
		if path.up then
			local a, b = pts[1], pts[2]
			pts = {}
			for k = 0, 12 do table.insert(pts, a:Lerp(b, k / 12)) end
		end
		for k = 1, #pts - 1, 2 do
			local a, b = pts[k], pts[k + 1]
			local len = (b - a).Magnitude
			if len > 0.05 then
				fpPart(pm, { Size = Vector3.new(0.22, 0.22, len), CFrame = CFrame.lookAt((a + b) / 2, b), Color = rgb(250),
					Material = Enum.Material.Neon, Transparency = 0.15 })
			end
		end
		if not path.up then
			local base = CFrame.lookAt(path.surface, path.surface + path.normal)
			local rings = { { 7, rgb(36, 52, 54) }, { 5.8, rgb(236, 240, 238) }, { 4.4, rgb(36, 52, 54) }, { 3, rgb(236, 240, 238) }, { 1.6, rgb(36, 52, 54) } }
			for n, r in ipairs(rings) do
				fpPart(pm, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, r[1], r[1]), Color = r[2],
					CFrame = base * CFrame.new(0, 0, -(0.2 + n * 0.03)) * CFrame.Angles(0, math.rad(90), 0) })
			end
		end
		pm:SetAttribute("Shown", true)
		return pm
	end

	-- what each emitter will do once built: bridge strip, fizzler / laser field plane, laser line, funnel tube, dropper drop line
	H.buildPreviews = function()
		H.previewRoot:ClearAllChildren()
		H.previews = {}
		for i, e in ipairs(E.ents) do
			local k = e[1]
			local def = Config.ENTITY_TYPES[k]
			if k == "faithplate" then H.previews[i] = faithPreview(e) end
			if def and (k == "lightbridge" or k == "fizzler" or k == "laserfield" or k == "laser" or k == "tbeam" or k == "cubedropper") then
				local fr = Config.ItemFrame(W, e)
				local maxL = Config.SpanMax(e, E.air) or 1
				local len = (def.span and (Config.SpanLength(e, E.air) or maxL) or maxL) * CELL
				local pm = new("Model", { Name = "Preview", Parent = H.previewRoot })
				local function slab(props)
					props.Anchored, props.CanCollide, props.CanQuery, props.CastShadow = true, false, false, false
					props.Material = props.Material or Enum.Material.SmoothPlastic
					props.Parent = pm
					local p = new("Part", props)
					p:SetAttribute("BaseT", p.Transparency)
					return p
				end
				if k == "lightbridge" then
					slab({ Size = Vector3.new(6, 0.15, len), CFrame = fr * CFrame.new(0, -CELL / 2 + 1, -len / 2), Color = rgb(90, 225, 235), Transparency = 0.5 })
				elseif k == "fizzler" or k == "laserfield" then
					slab({ Size = Vector3.new(CELL, 0.12, len), CFrame = fr * CFrame.new(0, -CELL / 2 + 0.6, -len / 2),
						Color = k == "fizzler" and rgb(90, 160, 255) or rgb(255, 70, 70), Transparency = 0.55 })
				elseif k == "laser" then
					slab({ Size = Vector3.new(0.15, 0.15, len), CFrame = fr * CFrame.new(0, 0, -len / 2), Color = rgb(255, 60, 60),
						Material = Enum.Material.Neon, Transparency = 0.3 })
				elseif k == "tbeam" then
					local rev = Config.Options(e).mode == "Reversed"
					slab({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, 7.4, 7.4), CFrame = fr * CFrame.new(0, 0, -len / 2) * CFrame.Angles(0, math.rad(90), 0),
						Color = rev and rgb(255, 140, 40) or rgb(60, 140, 255), Transparency = 0.75 })
				elseif k == "cubedropper" then
					slab({ Size = Vector3.new(0.08, 0.08, len), CFrame = fr * CFrame.new(0, 0, -len / 2), Color = rgb(235, 220, 120), Transparency = 0.35 })
					slab({ Size = Vector3.one * 4.35, CFrame = fr * CFrame.new(0, 0, -len + 2.2), Color = rgb(170, 176, 180), Transparency = 0.55 })
				end
				pm:SetAttribute("Shown", true)
				H.previews[i] = pm
			end
		end
	end

	-- highlight an item (connect target, "Remove connections" hover)
	local hl = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false, Material = Enum.Material.Neon,
		Transparency = 1, Size = Vector3.one, Parent = fxFolder })
	H.highlight = function(index, color)
		local m = index and E.entModels[index]
		if not m then hl.Transparency = 1 return end
		local cf, size = m:GetBoundingBox()
		hl.CFrame, hl.Size, hl.Color, hl.Transparency = cf, size + Vector3.one * 0.8, color or rgb(255, 120, 200), 0.6
	end
end

local surfaceMenu, itemMenu, selectionMenu
do
-- ==========================================
-- CONTEXT MENUS
-- ==========================================
local function toggleWallTiles()
	local all = true
	for fk in pairs(E.sel) do
		local _, _, _, f = parseFace(fk)
		if f == 3 or f == 4 then
			local _, wallT = Config.FaceInfo(E.faces[fk])
			if not wallT then all = false end
		end
	end
	pushUndo()
	for fk in pairs(E.sel) do
		local _, _, _, f = parseFace(fk)
		if f == 3 or f == 4 then
			local portal = Config.FaceInfo(E.faces[fk])
			E.faces[fk] = Config.FaceValue(portal, not all)
		end
	end
	rebuild()
	sfx("Click")
end

-- the SURFACE section for whatever panels are selected
local function surfaceSection()
	local all, anyFloor, allWall = true, false, true
	local color, mixed = nil, false
	local first = true
	for fk in pairs(E.sel) do
		local portal, wallT = Config.FaceInfo(E.faces[fk])
		if not portal then all = false end
		local _, _, _, f = parseFace(fk)
		if f == 3 or f == 4 then
			anyFloor = true
			if not wallT then allWall = false end
		end
		if first then color, first = E.colors[fk], false
		elseif E.colors[fk] ~= color then mixed = true end
	end
	local items = { { text = "Portalable", shortcut = "P", icon = "check", checked = all, fn = togglePortalable, sep = not anyFloor } }
	if anyFloor then
		table.insert(items, { text = "Wall tiles", icon = "check", checked = allWall, fn = toggleWallTiles, sep = true })
	end
	table.insert(items, { text = "Tile color", shortcut = "T", sep = true, sub = function()
		local list = { { text = "No color", icon = "radio", checked = not mixed and color == nil, fn = function() setTileColor(nil) end } }
		for i, tc in ipairs(Config.TILE_COLORS) do
			table.insert(list, { text = tc.name, swatch = tc.color, checked = not mixed and color == i, fn = function() setTileColor(i) end })
		end
		return list
	end })
	table.insert(items, { text = "Pull surface", shortcut = "+", icon = "plus", fn = function() moveSurfaces(1) end })
	table.insert(items, { text = "Push surface", shortcut = "-", icon = "minus", fn = function() moveSurfaces(-1) end })
	return { title = "Surface", items = items }
end

surfaceMenu = function(x, y)
	popupMenu(x, y, { surfaceSection() })
end

-- item options (e[10]): visibility, timer, button / pedestal / gate mode, funnel direction, dropper cube, start enabled,
-- goo size, faith plate target
local function setOption(index, k, v, quiet)
	local e = E.ents[index]
	if not e then return end
	pushUndo()
	local o = table.clone(Config.Options(e)) -- a fresh table, so undo keeps the old one
	o[k] = v
	e[10] = next(o) and o or nil
	rebuildEnts()
	if not quiet then sfx("Click") end
end

local function radios(index, k, list, current, labels)
	local items = {}
	for _, v in ipairs(list) do
		table.insert(items, { text = labels and labels[v] or v, icon = "radio", checked = current == v, fn = function() setOption(index, k, v) end })
	end
	return items
end

itemMenu = function(x, y)
	local index = E.selItem
	local e = E.ents[index]
	local def = e and Config.ENTITY_TYPES[e[1]]
	if not def then return end
	local o = Config.Options(e)
	-- the item's own tile is selected too (yellow), and its SURFACE section goes under the ITEM one
	E.sel = { [faceKey(e[2], e[3], e[4], e[5])] = true }
	refreshSelection()

	local items = {}
	local adv = Pal.level() >= 3
	if adv and Config.LABEL_PREFIX[e[1]] then
		-- chips refer to items by this name
		table.insert(items, { text = "Label: " .. (Config.LabelOf(e) or "(none)"), icon = "glyph", glyph = "✎", sep = true, fn = function() Dlg.rename(index) end })
	end
	if canSource(e) or canTarget(e) then
		table.insert(items, { text = "Connect to...", shortcut = "C", fn = startLink })
	end
	if canSource(e) then
		table.insert(items, { text = "Connection visibility", sub = function()
			return radios(index, "vis", { "Antline", "Signage", "None" }, o.vis or "Antline")
		end })
	end
	if hasLinks(e) then
		table.insert(items, { text = "Remove connections", sub = function()
			local list = {}
			for _, l in ipairs(E.links) do
				local otherId = (l[1] == e[8]) and l[2] or ((l[2] == e[8]) and l[1] or nil)
				local oi, oe = entById(otherId)
				if oe then
					table.insert(list, { text = entLabel(oe), hover = function(on) H.highlight(on and oi or nil) end, fn = function()
						pushUndo()
						for j = #E.links, 1, -1 do
							if E.links[j] == l then table.remove(E.links, j) end
						end
						rebuildEnts()
						sfx("Click")
					end })
				end
			end
			return list
		end })
	end
	if #items > 0 then items[#items].sep = true end

	if e[1] == "button" then
		table.insert(items, { text = "Button type", sep = true, sub = function()
			return radios(index, "mode", Config.BUTTON_TYPES, o.mode or "Weighted")
		end })
	elseif e[1] == "pedestal" then
		local mode = Config.PedestalMode(e)
		table.insert(items, { text = "Pedestal mode", sep = mode ~= "Timer", sub = function()
			return radios(index, "mode", Config.PEDESTAL_MODES, mode, Config.PEDESTAL_LABELS)
		end })
		if mode == "Timer" then
			table.insert(items, { timer = { value = tonumber(o.timer) or Config.PEDESTAL_TIMER, min = 1, max = 30,
				set = function(v) setOption(index, "timer", v, true) end }, sep = true })
		end
	elseif e[1] == "gate" then
		table.insert(items, { text = "Gate type", sub = function()
			return radios(index, "mode", Config.GATE_TYPES, Config.GateMode(e), Config.GATE_LABELS)
		end })
		table.insert(items, { text = "Hidden in game", icon = "check", checked = o.hide == true, sep = true,
			fn = function() setOption(index, "hide", o.hide ~= true or nil) end })
	elseif e[1] == "tbeam" then
		table.insert(items, { text = "Funnel direction", sub = function()
			return radios(index, "mode", { "Forward", "Reversed" }, o.mode == "Reversed" and "Reversed" or "Forward",
			{ Forward = "Blue (forward)", Reversed = "Orange (reversed)" })
		end })
		-- what a connected button does: flip it (Portal 2) or switch it on / off ("auto off" while the button is up)
		table.insert(items, { text = "Button action", sep = true, sub = function()
			return radios(index, "link", Config.FUNNEL_LINK_MODES, Config.FunnelLinkMode(e), Config.FUNNEL_LINK_LABELS)
		end })
	elseif e[1] == "trigger" then
		table.insert(items, { text = "Triggered by", sep = true, sub = function()
			return radios(index, "mode", Config.TRIGGER_MODES, table.find(Config.TRIGGER_MODES, o.mode) and o.mode or "Players", Config.TRIGGER_LABELS)
		end })
	elseif e[1] == "delay" then
		table.insert(items, { text = "Delay (seconds)", disabled = true, fn = function() end })
		table.insert(items, { timer = { value = tonumber(o.timer) or 1, min = 1, max = 30,
			set = function(v) setOption(index, "timer", v, true) end }, sep = true })
	elseif e[1] == "light" then
		table.insert(items, { text = "Light colour", sep = true, sub = function()
			local list = {}
			for _, n in ipairs(Config.LIGHT_ORDER) do
				table.insert(list, { text = n, swatch = Config.LIGHT_COLORS[n], checked = (o.mode or "White") == n, fn = function() setOption(index, "mode", n) end })
			end
			return list
		end })
	elseif e[1] == "pushzone" then
		local labels = {}
		for i, v in ipairs(Config.PUSH_STRENGTHS) do labels[v] = ({ "Gentle", "Normal", "Strong", "Launch" })[i] or tostring(v) end
		table.insert(items, { text = "Push strength", sep = true, sub = function()
			return radios(index, "power", Config.PUSH_STRENGTHS, tonumber(o.power) or Config.PUSH_STRENGTHS[2], labels)
		end })
	elseif e[1] == "cubedropper" then
		local cubes = Config.CubeVariants()
		if #cubes == 0 then cubes = Config.DROPPER_CUBES end
		table.insert(items, { text = "Cube type", sub = function()
			return radios(index, "mode", cubes, type(o.mode) == "string" and o.mode or cubes[1])
		end })
		table.insert(items, { text = "Auto drop first cube", icon = "check", checked = o.dropOnStart ~= false, sep = true,
			fn = function() setOption(index, "dropOnStart", o.dropOnStart == false) end })
	elseif e[1] == "faithplate" then
		local aimed = Config.FaithTarget(e, E.air) ~= nil
		table.insert(items, { text = "Launch straight up", icon = "check", checked = not aimed, sep = true, fn = function()
			if not aimed then return end
			local opt = table.clone(o)
			opt.fx, opt.fy, opt.fz, opt.ff = nil, nil, nil, nil
			pushUndo()
			e[10] = next(opt) and opt or nil
			rebuildEnts()
		end })
	end
	if e[1] == "exit" then
		-- the exit is locked until something opens it; this lets it open by itself (no button needed)
		local free = o.free == true
		table.insert(items, { text = "Open without a button", icon = "check", checked = free, sep = true, fn = function()
			setOption(index, "free", (not free) or nil)
			flash(free and "The exit now needs a button (or a chip) to open." or "The exit opens without a button.")
		end })
	elseif e[1] == "prop" then
		local SIZES = { 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4 }
		local labels = {}
		for _, v in ipairs(SIZES) do labels[v] = "x" .. tostring(v) end
		table.insert(items, { text = "Size", sep = not adv, sub = function()
			return radios(index, "scale", SIZES, tonumber(o.scale) or 1, labels)
		end })
		if adv then
			table.insert(items, { text = "Turn 15°", icon = "glyph", glyph = "↻", fn = function()
				setOption(index, "spin", ((tonumber(o.spin) or 0) + 15) % 360)
			end })
			table.insert(items, { text = "Nudge", sep = true, sub = function()
				local function nudge(k, d)
					return function()
						local v = math.clamp((tonumber(o[k]) or 0) + d, -CELL, CELL)
						setOption(index, k, v ~= 0 and v or nil)
					end
				end
				return {
					{ text = "Up (out of the surface)", fn = nudge("oy", 1) },
					{ text = "Down (into the surface)", fn = nudge("oy", -1) },
					{ text = "Left", fn = nudge("ox", -1) },
					{ text = "Right", fn = nudge("ox", 1) },
					{ text = "Forward", fn = nudge("oz", -1) },
					{ text = "Back", fn = nudge("oz", 1), sep = true },
					{ text = "Reset position", fn = function()
						pushUndo()
						local opt = table.clone(o)
						opt.ox, opt.oy, opt.oz, opt.spin = nil, nil, nil, nil
						E.ents[index][10] = next(opt) and opt or nil
						rebuildEnts()
					end },
				}
			end })
		end
	end
	if Config.SWITCHABLE[e[1]] and e[1] ~= "exit" then
		local on = Config.StartOn(e, hasLinks(e))
		local lingerMenu = Pal.level() >= 2 and hasLinks(e)
		table.insert(items, { text = "Start enabled", icon = "check", checked = on, sep = not lingerMenu, fn = function() setOption(index, "startOn", not on) end })
		if lingerMenu then
			-- keeps the button's effect going for a while after it lets go (a funnel / bridge you can still use)
			local labels = {}
			for _, v in ipairs(Config.LINGER_TIMES) do labels[v] = v == 0 and "Off (switches straight back)" or (v .. " s") end
			table.insert(items, { text = "Stay on after release", sep = true, sub = function()
				return radios(index, "linger", Config.LINGER_TIMES, tonumber(o.linger) or 0, labels)
			end })
		end
	end
	table.insert(items, { text = "Duplicate", shortcut = "Ctrl+D", disabled = def.mandatory == true, fn = duplicateItem })
	table.insert(items, { text = "Delete item", shortcut = "Delete", disabled = def.mandatory == true, fn = deleteItem })
	local title = e[1] == "gate" and (Config.GateMode(e) .. " gate") or "Item"
	if adv and Config.LabelOf(e) then title = Config.LabelOf(e) end
	popupMenu(x, y, { { title = title, items = items }, surfaceSection() })
end

-- the menu for whatever is selected (touch toolbar's OPTIONS)
selectionMenu = function(x, y)
	if E.selItem and E.ents[E.selItem] then itemMenu(x, y)
	elseif next(E.sel) then surfaceMenu(x, y)
	else flash("Select a surface or an item first.") sfx("Error") end
end

end
-- ==========================================
-- TOUCH TOOLBAR (bottom centre)
-- ==========================================
do
	local TOOLS = {
		{ "PULL +", function() moveSurfaces(1) end },
		{ "PUSH −", function() moveSurfaces(-1) end },
		{ "PORTAL", togglePortalable },
		{ "PAINT", paintSelection },
		{ "ROTATE", rotateItem },
		{ "CONNECT", startLink },
		{ "DELETE", deleteItem },
		{ "OPTIONS", function() local m = mouseCanvas() selectionMenu(m.X, REF_H - 420) end },
		{ "PLAY", function() task.spawn(buildAndPlay) end },
	}
	local bw, gapW = 104, 8
	local total = #TOOLS * bw + (#TOOLS - 1) * gapW
	touchBar = ui(new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = px(total, 56),
		BackgroundTransparency = 1, Visible = false, ZIndex = 20, Parent = canvas }))
	for i, t in ipairs(TOOLS) do
		local b = ui(new("TextButton", { Position = px((i - 1) * (bw + gapW), 0), Size = px(bw, 56), BackgroundColor3 = C.CTX_BG, BackgroundTransparency = 0.1,
			BorderSizePixel = 0, AutoButtonColor = true, Text = t[1], FontFace = FONT.P2, TextSize = 20, TextColor3 = rgb(30), Selectable = false, ZIndex = 21, Parent = touchBar }))
		new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = b })
		new("UIStroke", { Color = C.CTX_EDGE, Thickness = 1.5, Parent = b })
		if t[1] == "PLAY" then b.BackgroundColor3, b.TextColor3 = rgb(77, 128, 151), rgb(245) end
		onClick(b, function()
			if not (E.active and not E.playtest and not E.building) then return end
			sfx("Click")
			t[2]()
		end)
	end
end

local canEdit, orbit, zoomBy, cancelCarry, contextAt, pointerMoved
do
-- ==========================================
-- INPUT
-- ==========================================
canEdit = function()
	return E.active and not E.playtest and not E.building and not dialog and not player:GetAttribute("InMenu")
		and not UserInputService:GetFocusedTextBox()
end

local function panCamera(d)
	local scale = 2 * math.tan(math.rad(cam.FieldOfView) / 2) * E.cDist / math.max(workspace.CurrentCamera.ViewportSize.Y, 1)
	local right, up = cam.CFrame.RightVector, cam.CFrame.UpVector
	E.target += (-right * d.X + up * d.Y) * scale
end

-- d in pixels (mouse delta); speed + invert from the editor settings
orbit = function(d)
	local s = 0.006 * curve(ES("edOrbitSens", 0.5))
	local inv = ES("edInvertY", "Disabled") == "Enabled" and -1 or 1
	E.yaw -= d.X * s
	E.pitch = math.clamp(E.pitch - d.Y * s * inv, math.rad(-89), math.rad(89)) -- straight down to straight up
end

zoomBy = function(amount) -- amount > 0 = in
	E.dist = math.clamp(E.dist * (1 - amount * 0.1 * curve(ES("edZoomSpeed", 0.5))), 25, 600)
	E.chromeHold = os.clock() + 0.9
	E.zoomShow = os.clock() + 0.9
end

local function updateGhost(hit)
	local item = E.carry
	if ghost then ghost:Destroy() ghost = nil end
	if not item or not slotValid(item.kind, hit) then return end
	ghost = buildEntity({ item.kind, hit.x, hit.y, hit.z, hit.f, 0, item.variant }, { editor = true })
	if not ghost then return end
	Config.EachPart(ghost, function(p) p.Transparency = math.max(p.Transparency, 0.45) p.CanQuery = false end)
	ghost.Parent = fxFolder
end

cancelCarry = function()
	E.carry, E.carryArm = nil, nil
	Pal.itemName.Text = ""
	if ghost then ghost:Destroy() ghost = nil end
end

-- right-click / X / long-press: the menu for whatever is under the pointer
contextAt = function()
	local hit = pick()
	local m = mouseCanvas()
	if hit and hit.kind == "face" then
		if not E.sel[hit.key] then E.sel, E.selItem = { [hit.key] = true }, nil E.anchor = hit refreshSelection() end
		sfx("Click")
		surfaceMenu(m.X, m.Y)
	elseif hit and (hit.kind == "ent" or hit.kind == "handle") and hit.index and E.ents[hit.index] then
		E.selItem = hit.index
		sfx("Click")
		itemMenu(m.X, m.Y)
	end
end

-- LMB / A / one finger down on the room
local function primaryDown()
	closeMenus()
	if E.carry then return end -- controller: the next A release places it
	if E.linking then
		local hit = pick()
		if hit and hit.kind == "ent" then completeLink(hit.index) else cancelLink() end
		return
	end
	local hit = pick()
	E.chromeHold = 0 -- working on the chamber hides the frame
	if hit and hit.kind == "handle" and E.ents[hit.index] then
		local e = E.ents[hit.index]
		E.selItem = hit.index
		if hit.hk == "rot" then
			if (e[6] or 0) % 4 ~= hit.rot then
				pushUndo()
				e[6] = hit.rot
				rebuildEnts()
				sfx("Click")
			end
		elseif hit.hk == "goo" then
			E.drag = { kind = "goo", index = hit.index, side = hit.side, before = snapshot(), moved = false }
			sfx("SelectStart")
		elseif hit.hk == "fpball" or hit.hk == "fptarget" then
			-- ball: aim it (drag onto a panel) or, once aimed (or with Shift), drag up / down for the arc height
			local aimed = Config.FaithTarget(e, E.air) ~= nil
			local arcDrag = hit.hk == "fpball" and (aimed or shiftDown())
			E.drag = { kind = arcDrag and "fparc" or "fptarget", index = hit.index, before = snapshot(), moved = false }
			sfx("SelectStart")
		else
			E.drag = { kind = "span", index = hit.index, before = snapshot(), moved = false }
			sfx("SelectStart")
		end
	elseif hit and hit.kind == "ent" then
		local he = E.ents[hit.index]
		E.selItem, E.sel = hit.index, { [faceKey(he[2], he[3], he[4], he[5])] = true }
		E.drag = { kind = "move", index = hit.index, before = snapshot(), moved = false }
		sfx("Click")
	elseif hit and hit.kind == "face" then
		E.selItem = nil
		if shiftDown() then
			local a = E.anchor
			if not (a and E.faceParts[a.key] and selectRect(a, hit, true)) then
				E.sel[hit.key] = true
				E.anchor = E.anchor or hit
			end
			E.drag = nil
			sfx("SelectEnd")
		elseif ctrlDown() then
			E.sel[hit.key] = not E.sel[hit.key] or nil
			E.anchor = hit
			E.drag = nil
			sfx("TilePick")
		else
			E.sel = { [hit.key] = true }
			E.anchor = hit
			E.drag = { kind = "rect", start = hit, count = 1, expanded = false }
			sfx("SelectStart")
		end
	else
		if E.pointerMode == "touch" then
			E.touchOrbit = true -- one finger on empty space orbits (a tap deselects on release)
			return
		end
		E.sel, E.selItem = {}, nil
	end
	refreshSelection()
end

-- LMB / A / finger released
local function primaryUp()
	if E.carry then
		if E.carryArm then E.carryArm = false return end -- the press that picked it out of the palette
		local item = E.carry
		cancelCarry()
		local hit = canEdit() and not overUI() and pick()
		if hit and slotValid(item.kind, hit) then
			if #E.ents >= LIM.ents then flash("That's the item limit.") sfx("Error") return end
			pushUndo()
			table.insert(E.ents, { item.kind, hit.x, hit.y, hit.z, hit.f, 0, item.variant, newId() })
			Config.AutoLabel(E.ents)
			E.selItem, E.sel = #E.ents, {}
			refreshItems(item.kind)
			if GEL_KINDS[item.kind] then sfx("Gel")
			elseif item.kind == "turret" then sfx("TurretCollapse")
			else sfx("Click") end
		elseif hit then
			sfx("Correction") -- dropped on a spot it can't go
		end
	end
	if E.drag and E.drag.before and E.drag.moved then pushUndo(E.drag.before) sfx("Click") end
	if E.drag and E.drag.kind == "rect" then sfx(E.drag.expanded and "SelectEnd" or "TilePick") end
	E.drag = nil
end

-- the pointer moved (d = pixels; 0 for the controller cursor, which only matters for drags / hover)
pointerMoved = function(d)
	if E.mmb then
		if shiftDown() then panCamera(d) else orbit(d) end
	elseif E.rmb then
		E.rmb.moved += d.Magnitude
		if E.rmb.moved > 4 then panCamera(d) end
	end
	if E.drag and E.drag.kind == "rect" then
		local hit = pick()
		if hit and hit.kind == "face" and selectRect(E.drag.start, hit, false) then
			local n = selCount()
			if n ~= E.drag.count then
				E.drag.count = n
				E.drag.expanded = E.drag.expanded or n > 1
				sfx("Tile", SET.SFX_VOLUME * 0.7, 0.035)
			end
		end
	elseif E.drag and E.drag.kind == "move" then
		local e = E.ents[E.drag.index]
		local hit = pick()
		if e and hit and hit.kind == "face" and slotValid(e[1], hit, E.drag.index) and (hit.x ~= e[2] or hit.y ~= e[3] or hit.z ~= e[4] or hit.f ~= e[5]) then
			e[2], e[3], e[4], e[5] = hit.x, hit.y, hit.z, hit.f
			E.drag.moved = true
			refreshItems(e[1])
			sfx("TilePick", SET.SFX_VOLUME * 0.6, 0.05)
		end
	elseif E.drag and E.drag.kind == "span" then
		-- slide emitter 2 along the line straight out of the wall: 1 - 2  ->  1 ---- 2
		local e = E.ents[E.drag.index]
		if e then
			local o = OFFS[e[5]]
			local u = -Vector3.new(o[1], o[2], o[3])
			local p0 = W + Vector3.new(e[2], e[3], e[4]) * CELL - u * (CELL / 2) -- the wall surface
			local ro, rd = mouseRay()
			local b = u:Dot(rd)
			local w0 = p0 - ro
			local denom = 1 - b * b
			if denom > 1e-4 then
				local tt = (b * rd:Dot(w0) - u:Dot(w0)) / denom
				local maxL = Config.SpanMax(e, E.air) or 1
				local Lh = math.clamp(math.floor(tt / CELL + 0.5), 1, maxL)
				local cur = Config.SpanLength(e, E.air)
				if Lh ~= cur then
					e[9] = (Lh < maxL) and Lh or nil -- all the way across = follow the far wall
					E.drag.moved = true
					rebuildEnts()
					sfx("Tile", SET.SFX_VOLUME * 0.7, 0.03)
				end
			end
		end
	elseif E.drag and E.drag.kind == "goo" then
		-- grow / shrink toxic goo one tile at a time along the dragged side
		local e = E.ents[E.drag.index]
		if e then
			local side = E.drag.side
			local sx = (side == "gx1" or side == "gx0")
			local u = sx and (side == "gx1" and Vector3.xAxis or -Vector3.xAxis) or (side == "gz1" and Vector3.zAxis or -Vector3.zAxis)
			local p0 = W + Vector3.new(e[2], e[3], e[4]) * CELL + DIRS[e[5]] * (CELL / 2)
			local ro, rd = mouseRay()
			local b = u:Dot(rd)
			local w0 = p0 - ro
			local denom = 1 - b * b
			if denom > 1e-4 then
				local tt = (b * rd:Dot(w0) - u:Dot(w0)) / denom
				-- how far the floor goes that way
				local o = OFFS[e[5]]
				local maxN, x, y, z = 0, e[2], e[3], e[4]
				while maxN < 28 do
					x, y, z = x + math.round(u.X), y, z + math.round(u.Z)
					if not (E.air[key(x, y, z)] and not E.air[key(x + o[1], y + o[2], z + o[3])]) then break end
					maxN += 1
				end
				local n = math.clamp(math.floor(tt / CELL - 0.5 + 0.5), 0, maxN)
				local cur = Config.Options(e)[side] or 0
				if n ~= cur then
					local opt = table.clone(Config.Options(e))
					opt[side] = n > 0 and n or nil
					e[10] = next(opt) and opt or nil
					E.drag.moved = true
					rebuildEnts()
					sfx("Tile", SET.SFX_VOLUME * 0.7, 0.03)
				end
			end
		end
	elseif E.drag and E.drag.kind == "fptarget" then
		-- faith plate: drag the target onto any panel (back onto the plate itself = straight up)
		local e = E.ents[E.drag.index]
		local hit = pickFace()
		if e and hit then
			local opt = table.clone(Config.Options(e))
			local own = hit.x == e[2] and hit.y == e[3] and hit.z == e[4] and hit.f == e[5]
			local now = opt.fx and faceKey(opt.fx, opt.fy, opt.fz, opt.ff) or "up"
			local want = own and "up" or hit.key
			if want ~= now then
				if own then
					opt.fx, opt.fy, opt.fz, opt.ff = nil, nil, nil, nil
				else
					opt.fx, opt.fy, opt.fz, opt.ff = hit.x, hit.y, hit.z, hit.f
				end
				e[10] = next(opt) and opt or nil
				E.drag.moved = true
				rebuildEnts()
				sfx("TilePick", SET.SFX_VOLUME * 0.6, 0.05)
			end
		end
	elseif E.drag and E.drag.kind == "fparc" then
		-- faith plate: drag the ball up / down for how high the arc goes
		local e = E.ents[E.drag.index]
		if e then
			local path = Config.FaithPath(e, W, E.air)
			local _, apex = Config.FaithPoints(path, 2)
			local base = Vector3.new(apex.X, 0, apex.Z)
			local ro, rd = mouseRay()
			local b = rd.Y
			local w0 = base - ro
			local denom = 1 - b * b
			if denom > 1e-4 then
				local y = (b * rd:Dot(w0) - w0.Y) / denom
				local hi = path.up and path.p0.Y or math.max(path.p0.Y, path.aim.Y)
				local arc = math.clamp(math.floor(y - hi + 0.5), 4, 150)
				if arc ~= (tonumber(Config.Options(e).arc) or Config.FAITH_ARC) then
					local opt = table.clone(Config.Options(e))
					opt.arc = arc
					e[10] = opt
					E.drag.moved = true
					rebuildEnts()
					sfx("Tile", SET.SFX_VOLUME * 0.7, 0.03)
				end
			end
		end
	elseif E.carry then
		updateGhost(not overUI() and pick() or nil)
	end
end

do
local function keyAction(kc)
	if ctrlDown() and kc == Enum.KeyCode.S then
		if shiftDown() then if not E.guest then Dlg.saveAs() end else task.spawn(saveDraft, false) end
	elseif ctrlDown() and kc == Enum.KeyCode.N then
		if not E.guest then newChamber() end
	elseif ctrlDown() and kc == Enum.KeyCode.O then
		if not E.guest then task.spawn(Dlg.open) end
	elseif ctrlDown() and kc == Enum.KeyCode.Q then
		exitEditor()
	elseif ctrlDown() and kc == Enum.KeyCode.A then
		selectAll()
	elseif ctrlDown() and kc == Enum.KeyCode.Z then
		undo()
	elseif ctrlDown() and kc == Enum.KeyCode.Y then
		redo()
	elseif ctrlDown() and kc == Enum.KeyCode.D then
		duplicateItem()
	elseif kc == Enum.KeyCode.F1 then
		Dlg.wiki()
	elseif kc == Enum.KeyCode.Tab then
		toggleGameView()
	elseif kc == Enum.KeyCode.Equals or kc == Enum.KeyCode.KeypadPlus then
		moveSurfaces(1)
	elseif kc == Enum.KeyCode.Minus or kc == Enum.KeyCode.KeypadMinus then
		moveSurfaces(-1)
	elseif kc == Enum.KeyCode.P then
		togglePortalable()
	elseif kc == Enum.KeyCode.T and not ctrlDown() then
		paintSelection()
	elseif kc == Enum.KeyCode.Delete then
		deleteItem()
	elseif kc == Enum.KeyCode.R then
		rotateItem()
	elseif kc == Enum.KeyCode.C and not ctrlDown() then
		startLink()
	elseif kc == Enum.KeyCode.Escape then
		cancelLink()
		closeMenus()
		E.sel, E.selItem = {}, nil
		refreshSelection()
	end
end

-- controller buttons
local function padButton(kc, gpe)
	if kc == Enum.KeyCode.ButtonB then
		if #openMenus > 0 then closeMenus() GuiService.SelectedObject = nil
		elseif Pal.selecting() then GuiService.SelectedObject = nil Pal.set(false)
		elseif E.carry then cancelCarry()
		elseif E.linking then cancelLink()
		else keyAction(Enum.KeyCode.Escape) end
		return
	end
	if kc == Enum.KeyCode.ButtonY then Pal.togglePad() return end
	if GuiService.SelectedObject ~= nil or gpe then return end -- the D-pad / A are driving a menu or the palette
	if kc == Enum.KeyCode.ButtonA then
		local b = guiAtPointer(CLICK)
		if b then CLICK[b]() return end -- the cursor is on a button (File, toolbar, a menu row, a palette tile...)
		if overUI() then return end
		primaryDown()
	elseif kc == Enum.KeyCode.ButtonX then
		if not overUI() then contextAt() end
	elseif kc == Enum.KeyCode.DPadUp then
		moveSurfaces(1)
	elseif kc == Enum.KeyCode.DPadDown then
		moveSurfaces(-1)
	elseif kc == Enum.KeyCode.DPadLeft then
		rotateItem()
	elseif kc == Enum.KeyCode.DPadRight then
		togglePortalable()
	elseif kc == Enum.KeyCode.ButtonL3 then
		startLink()
	elseif kc == Enum.KeyCode.ButtonR3 then
		toggleGameView()
	end
end

-- touch
local touches = {}
local function touchPos(input) return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset() end
local function touchCount()
	local n = 0
	for _ in pairs(touches) do n += 1 end
	return n
end
local function touchBegan(input)
	touches[input] = touchPos(input)
	E.pointerMode = "touch"
	if touchCount() == 1 then
		E.pointer = touches[input]
		E.touch = { input = input, t = os.clock(), moved = 0, long = false }
		primaryDown()
	else
		-- second finger: whatever the first one was doing stops, two fingers move the camera
		if E.touch then
			if E.drag and E.drag.before and E.drag.moved then pushUndo(E.drag.before) end
			E.drag = nil
			E.touchOrbit = false
			E.touch = nil
		end
		E.pinch = nil
	end
end
local function touchChanged(input)
	if touches[input] then
		local p = touchPos(input)
		local old = touches[input]
		touches[input] = p
		if E.touch and E.touch.input == input then
			local d = p - old
			E.pointer = p
			E.touch.moved += d.Magnitude
			if E.touchOrbit then orbit(d) else pointerMoved(d) end
		elseif touchCount() >= 2 then
			local list = {}
			for _, v in pairs(touches) do table.insert(list, v) end
			local a, b = list[1], list[2]
			local mid, dist = (a + b) / 2, (a - b).Magnitude
			if E.pinch then
				panCamera(mid - E.pinch.mid)
				if dist > 1 and E.pinch.dist > 1 then
					E.dist = math.clamp(E.dist * E.pinch.dist / dist, 25, 600)
					E.zoomShow = os.clock() + 0.9
				end
			end
			E.pinch = { mid = mid, dist = dist }
		end
	elseif E.carry then
		-- dragging an item out of the palette (that touch started on the GUI)
		E.pointerMode = "touch"
		E.pointer = touchPos(input)
		pointerMoved(Vector2.zero)
	end
end
local function touchEnded(input)
	if touches[input] then
		touches[input] = nil
		E.pinch = nil
		if E.touch and E.touch.input == input then
			local t = E.touch
			E.touch = nil
			E.pointer = touchPos(input)
			if t.long then return end
			if E.touchOrbit then
				E.touchOrbit = false
				if t.moved < 12 then E.sel, E.selItem = {}, nil refreshSelection() end
			else
				primaryUp()
			end
		end
	elseif E.carry then
		E.pointer = touchPos(input)
		primaryUp()
	end
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if not E.active then return end
	local kc, t = input.KeyCode, input.UserInputType
	local pad = isPad(input)
	if pad then usePad() end
	if (kc == Enum.KeyCode.F9 or kc == Enum.KeyCode.ButtonSelect) and not player:GetAttribute("InMenu") and not E.building then
		task.spawn(buildAndPlay)
		return
	end
	if not canEdit() then
		if pad and kc == Enum.KeyCode.ButtonB and dialog then closeDialog() end
		return
	end
	if pad then padButton(kc, gpe) return end
	if t == Enum.UserInputType.Touch then
		if not gpe then touchBegan(input) end
		return
	end
	if t == Enum.UserInputType.MouseButton1 then
		E.pointerMode = "mouse"
		if gpe then return end
		primaryDown()
	elseif t == Enum.UserInputType.MouseButton2 then
		E.pointerMode = "mouse"
		if gpe then return end
		closeMenus()
		E.rmb = { moved = 0 }
	elseif t == Enum.UserInputType.MouseButton3 then
		E.mmb = true
	elseif t == Enum.UserInputType.Keyboard then
		keyAction(kc)
	end
end)

UserInputService.InputChanged:Connect(function(input, gpe)
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch then
		if E.active and (canEdit() or E.carry) then touchChanged(input) end
		return
	end
	if not canEdit() then return end
	if t == Enum.UserInputType.MouseMovement then
		if E.pointerMode ~= "mouse" and input.Delta.Magnitude < 2 then return end -- ignore mouse jitter while on a controller
		E.pointerMode = "mouse"
		pointerMoved(input.Delta)
	elseif t == Enum.UserInputType.MouseWheel and not gpe then
		zoomBy(input.Position.Z)
	elseif isPad(input) and input.Position.Magnitude > 0.35 then
		usePad()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local t, kc = input.UserInputType, input.KeyCode
	if t == Enum.UserInputType.Touch then
		if E.active then touchEnded(input) end
		return
	end
	if t == Enum.UserInputType.MouseButton1 or (kc == Enum.KeyCode.ButtonA and isPad(input)) then
		if not E.active then return end
		primaryUp()
	elseif t == Enum.UserInputType.MouseButton2 then
		local r = E.rmb
		E.rmb = nil
		if r and r.moved <= 4 and canEdit() then contextAt() end
	elseif t == Enum.UserInputType.MouseButton3 then
		E.mmb = false
	end
end)
end

-- the pause menu opens over the editor: give it the controller
player:GetAttributeChangedSignal("InMenu"):Connect(function()
	if player:GetAttribute("InMenu") and E.active then
		closeMenus()
		GuiService.SelectedObject = nil
		if E.drag and E.drag.before and E.drag.moved then pushUndo(E.drag.before) end
		E.drag, E.mmb, E.rmb = nil, false, nil
	end
end)

end
-- ==========================================
-- FRAME LOOP
-- ==========================================
do
local function readSticks()
	local l, r = Vector2.zero, Vector2.zero
	local ok, state = pcall(function() return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) end)
	if ok and state then
		for _, s in ipairs(state) do
			if s.KeyCode == Enum.KeyCode.Thumbstick1 then l = Vector2.new(s.Position.X, s.Position.Y)
			elseif s.KeyCode == Enum.KeyCode.Thumbstick2 then r = Vector2.new(s.Position.X, s.Position.Y) end
		end
	end
	local function dead(v)
		local m = v.Magnitude
		if m < 0.18 then return Vector2.zero end
		return v.Unit * ((m - 0.18) / 0.82)
	end
	return dead(l), dead(r)
end

local lastPadHover
editLoop = function(dt)
	if not E.active or E.playtest then return end
	local inMenu = player:GetAttribute("InMenu")
	local now = os.clock()
	if not inMenu then
		local dragging = E.mmb or (E.rmb and E.rmb.moved > 4)
		UserInputService.MouseBehavior = dragging and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = E.pointerMode == "mouse"
	end
	local overlay = playerGui:FindFirstChild("Overlay")
	if overlay then overlay.Enabled = false end
	local wcam = workspace.CurrentCamera
	wcam.CameraType = Enum.CameraType.Scriptable
	local fwd = Vector3.new(-math.sin(E.yaw), 0, -math.cos(E.yaw))
	local right = Vector3.new(math.cos(E.yaw), 0, -math.sin(E.yaw))
	local moveSpeed = 30 + E.dist * 0.7
	if canEdit() then
		local move = Vector3.zero
		if not ctrlDown() then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += fwd end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= fwd end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
			if UserInputService:IsKeyDown(Enum.KeyCode.E) then move += Vector3.yAxis end
			if UserInputService:IsKeyDown(Enum.KeyCode.Q) then move -= Vector3.yAxis end
		end
		E.target += move * dt * moveSpeed

		-- controller: sticks, shoulder zoom
		if E.pointerMode == "pad" then
			local l, r = readSticks()
			local menuNav = GuiService.SelectedObject ~= nil
			if padDown(Enum.KeyCode.ButtonL2) then
				E.target += (fwd * l.Y + right * l.X + Vector3.yAxis * r.Y) * dt * moveSpeed
				if r.X ~= 0 then orbit(Vector2.new(r.X, 0) * dt * 420) end
			else
				if l.Magnitude > 0 and not menuNav then
					local vp = viewportSize()
					local speed = 900 * curve(ES("edPadCursor", 0.5)) * (vp.Y / 1080)
					local p = E.pointer or vp / 2
					E.pointer = Vector2.new(math.clamp(p.X + l.X * speed * dt, 0, vp.X), math.clamp(p.Y - l.Y * speed * dt, 0, vp.Y))
					pointerMoved(Vector2.zero)
				end
				if r.Magnitude > 0 then orbit(Vector2.new(r.X, -r.Y) * dt * 420) end
			end
			if padDown(Enum.KeyCode.ButtonR1) then zoomBy(dt * 12) end
			if padDown(Enum.KeyCode.ButtonL1) then zoomBy(-dt * 12) end
			-- hover effects under the controller cursor (menus, toolbar, palette)
			local hb = not menuNav and guiAtPointer(HOVER) or nil
			if hb ~= lastPadHover then
				if lastPadHover and HOVER[lastPadHover] and lastPadHover.Parent then HOVER[lastPadHover][2]() end
				lastPadHover = hb
				if hb then HOVER[hb][1]() end
			end
		end

		-- touch: long-press = context menu
		local t = E.touch
		if t and not t.long and not E.carry and t.moved < 12 and now - t.t > 0.55 then
			t.long = true
			E.drag, E.touchOrbit = nil, false
			contextAt()
		end
	end
	local smooth = 18 * 2 ^ ((0.5 - (tonumber(ES("edCamSmooth", 0.5)) or 0.5)) * 2.4)
	local a = 1 - math.exp(-smooth * dt)
	E.cYaw += (E.yaw - E.cYaw) * a
	E.cPitch += (E.pitch - E.cPitch) * a
	E.cDist += (E.dist - E.cDist) * a
	E.cTarget = E.cTarget:Lerp(E.target, a)
	applyCamera()
	updateCull()
	staleBox.Visible = false -- the game view is always current now

	-- a teammate's change that arrived mid-drag
	if E.pendingRemote and not E.drag and not E.carry then applyRemote(E.pendingRemote) end
	-- our changes go to the team (a few times a second at most)
	if E.rev ~= E.sentRev and not E.drag and now - E.lastSync > 0.15 then sendSync() end

	-- frame chrome: in near the edges / over the UI / while zooming, out while you work on the chamber
	local mc = mouseCanvas()
	local cw = canvasWidth()
	local over = overUI()
	local working = E.mmb or (E.rmb and E.rmb.moved > 4) or E.drag ~= nil
	local near = mc.Y < 64 or mc.X < 30 or mc.X > cw - 72 or mc.Y > REF_H - 34
	local showChrome = not working and (near or over or now < E.chromeHold or E.pointerMode == "touch")
	local k = 1 - math.exp(-(showChrome and 12 or 7) * dt)
	chrome.GroupTransparency += ((showChrome and 0 or 1) - chrome.GroupTransparency) * k

	-- palette slides away once you head into the room
	local autoHide = ES("edAutoHide", SET.PALETTE_AUTOHIDE and "Enabled" or "Disabled") == "Enabled"
	if Pal.open and autoHide and #openMenus == 0 and not dialog and not Pal.selecting() then
		if mc.X > (E.carry and 414 or 470) then
			Pal.awayT = Pal.awayT or now
			if now - Pal.awayT > (E.carry and 0.05 or 0.4) then Pal.set(false) end
		else
			Pal.awayT = nil
		end
	end
	-- controller cursor resting on the left strip opens the palette
	if E.pointerMode == "pad" and not Pal.open and not E.carry and mc.X < 26 and mc.Y > 145 and mc.Y < 936 then Pal.set(true) end

	-- controller cursor / hints, touch toolbar
	padCursor.Visible = E.pointerMode == "pad" and GuiService.SelectedObject == nil and not inMenu
	if padCursor.Visible then padCursor.Position = px(mc.X, mc.Y) end
	padHint.Visible = E.pointerMode == "pad" and not inMenu
	local tb = ES("edTouchBar", "Auto")
	touchBar.Visible = tb == "Always" or (tb == "Auto" and (E.pointerMode == "touch" or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)))

	-- zoom bar: longer the further out you are
	local zt = math.clamp((E.cDist - 25) / (600 - 25), 0, 1)
	zoomBar.Size = px(14, 9 + 941 * zt)
	local zk = 1 - math.exp(-10 * dt)
	zoomBar.BackgroundTransparency += ((now < E.zoomShow and 0 or 1) - zoomBar.BackgroundTransparency) * zk

	-- connecting: elbow line from the item's tile to the pointer, snaps to anything it can connect to
	if E.linking then
		local _, se = entById(E.linking)
		if se then
			local pa = connectGui.project(Config.ItemFrame(W, se).Position)
			local h = (not over) and pick() or nil
			local te = h and h.kind == "ent" and E.ents[h.index]
			local ok = te and te ~= se and linkPair(se, te) ~= nil
			H.highlight(ok and h.index or nil, rgb(255, 225, 90))
			local pb = ok and connectGui.project(Config.ItemFrame(W, te).Position) or mc
			if pa and pb then connectGui.draw(pa, pb, ok == true) else connectGui.hide() end
		else
			cancelLink()
		end
	end
	-- hover tile (not for touch: there is no hover)
	local hit = (canEdit() and not E.drag and not E.carry and not over and not E.mmb and E.pointerMode ~= "touch") and pick() or nil
	if hit and hit.kind == "face" and not E.sel[hit.key] and ES("edHover", "Enabled") == "Enabled" then
		hoverPart.Size = Vector3.new(CELL - 0.35, CELL - 0.35, 0.1)
		hoverPart.CFrame = Config.FaceCFrame(W, hit.x, hit.y, hit.z, hit.f, -0.05)
		hoverPart.Transparency = 0.35
	else
		hoverPart.Transparency = 1
	end

	-- Advanced: coordinates of what's under the pointer
	if ES("edMode", "Simple") == "Advanced" and E.pointerMode ~= "pad" then
		local h = hit or ((not over and not E.drag) and pick() or nil)
		local txt = ""
		if h and h.kind == "face" then
			local FACE = { "+X wall", "-X wall", "ceiling", "floor", "+Z wall", "-Z wall" }
			txt = ("cell %d, %d, %d  ·  %s"):format(h.x, h.y, h.z, FACE[h.f] or "?")
			if E.textures[h.key] then txt ..= "  ·  texture " .. tostring(E.textures[h.key]) end
		elseif h and (h.kind == "ent" or h.kind == "handle") and E.ents[h.index or 0] then
			local e = E.ents[h.index]
			txt = ("%s  ·  %s  ·  cell %d, %d, %d"):format(Config.LabelOf(e) or e[1], entLabel(e), e[2], e[3], e[4])
		end
		X.coords.Text = txt
		X.coords.Visible = txt ~= ""
	else
		X.coords.Visible = false
	end

	-- team: send where we're pointing (and what at), move everyone else's markers
	if Team.teamSize() > 1 then
		if cursorEvent and now - E.lastCursorSend > 0.08 then
			E.lastCursorSend = now
			local h = (not over and not inMenu) and (hit or pick()) or nil
			local surf = "none"
			if h then
				if h.kind == "face" then
					local fp = E.faceParts[h.key]
					surf = (fp and not fp.portal) and "black" or "white"
				else
					surf = "item"
				end
			end
			cursorEvent:FireServer({ c = h and (h.pos - W) or nil, t = E.target - W, s = surf })
		end
		Team.updateMarkers(dt)
	end
end
end

-- ==========================================
-- EDITOR STYLES (Options > Editor > Editor Style, or File > Editor style)
-- ==========================================
-- The GUI is always built in the Classic colours; this recolours it to the chosen style as things appear (and when
-- hover effects set a Classic colour again). The room itself (tiles, rims, selection, backdrop) changes too.
-- Add your own style: a new entry in STYLES, { gui = { [Classic colour] = new colour }, room = { C key = colour } }.
do
	local function hex(c) return ("%02x%02x%02x"):format(math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
	local CLASSIC = table.clone(C)
	local CLASSIC_BACKDROP = SET.BACKDROP
	-- GUI colours: Classic colour -> style colour (C keys + the few greys used straight in the code)
	local function guiMap(byKey, literal)
		local m = {}
		for k, v in pairs(byKey) do if CLASSIC[k] then m[hex(CLASSIC[k])] = v end end
		for _, pair in ipairs(literal or {}) do m[hex(pair[1])] = pair[2] end
		return m
	end
	local STYLES = {
		Classic = { gui = {}, room = {} },
		Dark = {
			gui = guiMap({
				OUT = rgb(46, 49, 51), STRIP_OPEN = rgb(62, 66, 68), STRIP_SHUT = rgb(54, 57, 59), GRIP = rgb(110),
				MENU_TEXT = rgb(165), MENU_HI = rgb(240), ICON = rgb(150), ICON_HI = rgb(235), ICON_ON = rgb(90, 205, 220),
				PAL_BG = rgb(38, 41, 43), PAL_EDGE = rgb(18), TILE = rgb(52, 56, 58), TILE_LINE = rgb(66, 70, 72), TILE_HI = rgb(36, 84, 92),
				CTX_BG = rgb(40, 43, 45), CTX_HEAD = rgb(18, 20, 21), CTX_ICONCOL = rgb(55, 58, 60), CTX_EDGE = rgb(14),
				CTX_HI = rgb(28, 96, 102), CTX_TEXT = rgb(228), CTX_SHORT = rgb(150), CTX_SEP = rgb(80),
			}, {
				{ rgb(250), rgb(32, 35, 37) }, { rgb(255), rgb(30, 33, 35) }, { rgb(200, 206, 203), rgb(70, 75, 78) },
				{ rgb(214, 218, 216), rgb(64, 68, 71) }, { rgb(206, 208, 206), rgb(48, 51, 53) }, { rgb(232), rgb(60, 64, 66) },
				{ rgb(240, 240, 236), rgb(70, 75, 78) }, { rgb(232, 234, 232), rgb(30, 33, 35) },
				{ rgb(20), rgb(232) }, { rgb(25), rgb(230) }, { rgb(30), rgb(226) }, { rgb(40), rgb(220) }, { rgb(60), rgb(200) },
				{ rgb(95), rgb(170) }, { rgb(105), rgb(160) }, { rgb(110), rgb(160) }, { rgb(130), rgb(150) }, { rgb(150), rgb(130) },
			}),
			room = { WHITE = rgb(190, 196, 192), BLACK = rgb(44, 50, 49), RIM_WHITE = rgb(150, 156, 152), RIM_BLACK = rgb(64, 70, 68),
				SHELL = rgb(30, 33, 32), BACKDROP = rgb(40, 43, 45) },
		},
		Blueprint = {
			gui = guiMap({
				OUT = rgb(26, 60, 108), STRIP_OPEN = rgb(36, 78, 134), STRIP_SHUT = rgb(30, 68, 120), GRIP = rgb(140, 175, 220),
				MENU_TEXT = rgb(170, 200, 240), MENU_HI = rgb(255), ICON = rgb(160, 190, 230), ICON_HI = rgb(255), ICON_ON = rgb(255, 220, 120),
				PAL_BG = rgb(22, 52, 96), PAL_EDGE = rgb(120, 160, 215), TILE = rgb(30, 66, 118), TILE_LINE = rgb(70, 110, 170), TILE_HI = rgb(50, 100, 170),
				CTX_BG = rgb(24, 56, 104), CTX_HEAD = rgb(14, 36, 70), CTX_ICONCOL = rgb(34, 72, 128), CTX_EDGE = rgb(120, 160, 215),
				CTX_HI = rgb(52, 104, 176), CTX_TEXT = rgb(225, 238, 255), CTX_SHORT = rgb(160, 190, 230), CTX_SEP = rgb(80, 120, 180),
			}, {
				{ rgb(250), rgb(20, 48, 90) }, { rgb(255), rgb(18, 44, 84) }, { rgb(200, 206, 203), rgb(46, 92, 156) },
				{ rgb(214, 218, 216), rgb(40, 82, 142) }, { rgb(206, 208, 206), rgb(28, 62, 112) }, { rgb(232), rgb(44, 88, 150) },
				{ rgb(240, 240, 236), rgb(46, 92, 156) }, { rgb(232, 234, 232), rgb(18, 44, 84) },
				{ rgb(20), rgb(230, 240, 255) }, { rgb(25), rgb(225, 238, 255) }, { rgb(30), rgb(220, 235, 255) }, { rgb(40), rgb(210, 228, 250) },
				{ rgb(60), rgb(190, 212, 240) }, { rgb(95), rgb(160, 190, 230) }, { rgb(105), rgb(150, 182, 225) }, { rgb(110), rgb(150, 182, 225) },
				{ rgb(130), rgb(140, 170, 215) }, { rgb(150), rgb(120, 150, 200) },
			}),
			room = { WHITE = rgb(205, 222, 245), BLACK = rgb(40, 70, 112), RIM_WHITE = rgb(160, 190, 230), RIM_BLACK = rgb(60, 92, 140),
				SHELL = rgb(26, 50, 88), BACKDROP = rgb(30, 70, 130) },
		},
		["High Contrast"] = {
			gui = guiMap({
				OUT = rgb(0), STRIP_OPEN = rgb(30), STRIP_SHUT = rgb(20), GRIP = rgb(255, 220, 0),
				MENU_TEXT = rgb(255), MENU_HI = rgb(255, 220, 0), ICON = rgb(255), ICON_HI = rgb(255, 220, 0), ICON_ON = rgb(255, 220, 0),
				PAL_BG = rgb(255), PAL_EDGE = rgb(0), TILE = rgb(255), TILE_LINE = rgb(0), TILE_HI = rgb(255, 230, 0),
				CTX_BG = rgb(255), CTX_HEAD = rgb(0), CTX_ICONCOL = rgb(230), CTX_EDGE = rgb(0),
				CTX_HI = rgb(255, 230, 0), CTX_TEXT = rgb(0), CTX_SHORT = rgb(40), CTX_SEP = rgb(0),
			}, { { rgb(95), rgb(20) }, { rgb(105), rgb(20) }, { rgb(110), rgb(20) }, { rgb(130), rgb(20) }, { rgb(150), rgb(30) } }),
			room = { WHITE = rgb(255), BLACK = rgb(20), RIM_WHITE = rgb(120), RIM_BLACK = rgb(70), SHELL = rgb(0),
				SEL_WHITE = rgb(255, 230, 0), SEL_BLACK = rgb(255, 170, 0), BACKDROP = rgb(90) },
		},
	}
	X.STYLES = { "Classic", "Dark", "Blueprint", "High Contrast" }

	local PROPS = { "BackgroundColor3", "TextColor3", "ImageColor3", "PlaceholderColor3", "ScrollBarImageColor3" }
	local current = STYLES.Classic
	local touched = setmetatable({}, { __mode = "k" })
	local applying = false

	-- obj's Classic colour for prop: what it was the first time we saw it (or since the code last set it itself)
	local function styleProp(obj, prop)
		local ok, v = pcall(function() return obj[prop] end)
		if not ok or typeof(v) ~= "Color3" then return end
		local base = obj:GetAttribute("StyleBase_" .. prop)
		if not base then
			base = v
			obj:SetAttribute("StyleBase_" .. prop, base)
		end
		local want = current.gui[hex(base)] or base
		if v ~= want then
			applying = true
			obj[prop] = want
			applying = false
		end
	end
	local function styleObj(obj)
		if obj:IsA("GuiObject") then
			for _, prop in ipairs(PROPS) do styleProp(obj, prop) end
			if not touched[obj] then
				touched[obj] = true
				-- hover effects etc. set Classic colours again: restyle them (and remember that as the new base)
				for _, prop in ipairs(PROPS) do
					pcall(function()
						obj:GetPropertyChangedSignal(prop):Connect(function()
							if applying then return end
							-- (signals can arrive late: our own recolour isn't a new base colour)
							local base = obj:GetAttribute("StyleBase_" .. prop)
							if base and obj[prop] == (current.gui[hex(base)] or base) then return end
							obj:SetAttribute("StyleBase_" .. prop, obj[prop])
							styleProp(obj, prop)
						end)
					end)
				end
			end
		elseif obj:IsA("UIStroke") then
			local base = obj:GetAttribute("StyleBase_Color") or obj.Color
			obj:SetAttribute("StyleBase_Color", base)
			obj.Color = current.gui[hex(base)] or base
		end
	end

	function X.applyStyle(name)
		local st = STYLES[name] or STYLES.Classic
		current = st
		-- room colours
		for k, v in pairs(CLASSIC) do
			if typeof(v) == "Color3" and (k == "WHITE" or k == "BLACK" or k:match("^RIM_") or k == "SHELL" or k:match("^SEL_") or k == "HOVER" or k:match("^WALLTILE_")) then
				C[k] = st.room[k] or v
			end
		end
		SET.BACKDROP = st.room.BACKDROP or CLASSIC_BACKDROP
		for _, p in ipairs(world:GetChildren()) do
			if p.Name == "Backdrop" and p:IsA("BasePart") then p.Color = SET.BACKDROP end
		end
		hoverPart.Color, itemBox.Color = C.HOVER, C.SEL_WHITE
		-- GUI
		styleObj(gui)
		for _, d in ipairs(gui:GetDescendants()) do styleObj(d) end
		if E.active and not E.gameView then rebuild() end
	end
	gui.DescendantAdded:Connect(function(d) task.defer(function() if d.Parent then styleObj(d) end end) end)
	player:GetAttributeChangedSignal("Setting_edStyle"):Connect(function()
		X.applyStyle(ES("edStyle", "Classic"))
		if E.active then flash("Editor style: " .. ES("edStyle", "Classic")) end
	end)
	task.defer(function() X.applyStyle(ES("edStyle", "Classic")) end)
end

-- ==========================================
-- HOOKS
-- ==========================================
editorRequest.Event:Connect(function(kind)
	if not E.active then return end
	if kind == "Rebuild" then
		task.spawn(buildAndPlay)
	elseif kind == "Restart" then
		task.spawn(restartLevel)
	elseif kind == "ExitToEditor" then
		task.spawn(exitPlaytest)
	elseif kind == "Save" then
		task.spawn(saveDraft, false)
	elseif kind == "Invite" then
		if not E.playtest then Dlg.invite() end
	end
end)

task.spawn(function()
	local f = ReplicatedStorage:WaitForChild("PortalNet", 30)
	if not f then return end
	f:WaitForChild("Push").OnClientEvent:Connect(function(kind, data)
		if kind == "EditorStart" and type(data) == "table" then
			start(data)
		elseif kind == "ChamberComplete" and type(data) == "table" and data.editor and E.playtest then
			flash(("Test chamber solved in %d seconds!"):format(math.floor(data.time or 0)))
			X.toast(("Solved in %d seconds."):format(math.floor(data.time or 0)), "Test chamber solved", "good")
			task.delay(2.5, function() if E.playtest then exitPlaytest() end end)
		elseif kind == "TeamUpdate" and type(data) == "table" and E.active then
			E.team = data
			Team.refreshTeamBox()
		elseif kind == "TeamDeclined" and type(data) == "table" and E.active then
			flash(tostring(data.name) .. " can't build right now.")
		elseif kind == "TeamEnded" and type(data) == "table" and E.active then
			flash(tostring(data.reason or "The team was closed."))
			E.team = nil
			Team.clearMarkers()
			Team.refreshTeamBox()
			task.delay(1.5, function() menuRequest("ExitToMain") end)
		elseif kind == "TeamPlaytest" and type(data) == "table" and E.active and not E.playtest and not E.building then
			-- a teammate pressed Build and Play: the server is taking us in too
			flash(tostring(data.by) .. " started a test.")
			closeMenus()
			closeDialog()
			cancelCarry()
			E.drag = nil
			E.stale = false
			task.spawn(enterPlaytest)
		end
	end)
	syncEvent = f:WaitForChild("Sync", 15)
	cursorEvent = f:WaitForChild("Cursor", 15)
	if syncEvent then
		syncEvent.OnClientEvent:Connect(function(kind, payload)
			if kind == "Data" and type(payload) == "table" and E.active and E.team then
				if E.playtest then E.pendingRemote = payload.data else applyRemote(payload.data) end
			end
		end)
	end
	if cursorEvent then
		cursorEvent.OnClientEvent:Connect(function(userId, d)
			if not E.active or not E.team or type(d) ~= "table" then return end
			local mk = Team.markerFor(userId)
			if not mk then return end
			local at = typeof(d.c) == "Vector3" and d.c or (typeof(d.t) == "Vector3" and d.t or nil)
			if not at then return end
			mk.want = W + at
			mk.surf = type(d.s) == "string" and d.s or "none"
			mk.idle = typeof(d.c) ~= "Vector3"
			mk.play = d.play == true
			mk.seen = os.clock()
		end)
	end
end)

task.spawn(function()
	local menu = playerGui:WaitForChild("PortalMenu", 30)
	if not menu then return end
	menu:WaitForChild("MenuAction").Event:Connect(function(action)
		if action == "ExitToMainMenu" or action == "NewGame" or action == "LoadGame" or action == "ContinueGame" then
			stop(true)
		end
	end)
end)
