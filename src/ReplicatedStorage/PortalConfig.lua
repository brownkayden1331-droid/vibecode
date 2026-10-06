-- PortalConfig
-- ReplicatedStorage (ModuleScript)  -- name it exactly "PortalConfig"
local C = {}
C.VERSION = 3 -- PortalServer / PortalMenu / PortalMapEditor check this (they need the same version)

C.MAPS_FOLDER = "PortalMaps"
C.LOBBY_SPAWN = "MenuSpawn"
C.COOP_HUB_MAP = "CoopHub"
-- co-op characters (rig names in PortalAssets.Rigs, used by RigChangerServer): blue = Atlas, orange = P-body
C.COOP_RIGS = { Blue = "Atlas", Orange = "PBody" }
C.EDITOR_ORIGIN = Vector3.new(0, 600, 0)

-- ==========================================
-- INSTANCES (every player / co-op pair gets its own spot in the world, FAR away from everyone else)
-- ==========================================
-- Chapters, challenge maps, Workshop chambers and editor playtests are all loaded into
-- workspace.PortalInstances.Slot_<n>, moved out to that slot's spot. Slots sit on a grid around (but never on) the
-- lobby at the world origin. Chapter / challenge maps are moved by InstanceOffset (their own height is kept), built
-- test chambers sit at ChamberOrigin.
C.INSTANCE_SPACING = 6000 -- studs between two neighbouring slots
C.INSTANCE_GRID = 8       -- slots per row (8 x 8 = 64 slots, the furthest is ~21000 studs out)
C.OFFSET_CHAPTER_MAPS = true -- false = chapter / challenge maps stay where they are in ServerStorage (shared spot)
local slotCells -- grid cells, nearest the lobby first (few players = everything stays fairly close to the origin)
function C.InstanceOffset(slot)
	local n = C.INSTANCE_GRID
	if not slotCells then
		slotCells = {}
		local half = (n - 1) / 2 -- half-integer offsets: no slot lands on the lobby
		for gx = 0, n - 1 do
			for gz = 0, n - 1 do table.insert(slotCells, { gx - half, gz - half }) end
		end
		table.sort(slotCells, function(a, b)
			local da, db = a[1] * a[1] + a[2] * a[2], b[1] * b[1] + b[2] * b[2]
			if da ~= db then return da < db end
			return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
		end)
	end
	local i = math.max((slot or 1) - 1, 0)
	local cell = slotCells[i % #slotCells + 1]
	local layer = math.floor(i / #slotCells) -- more players than slots: another grid far below
	return Vector3.new(cell[1] * C.INSTANCE_SPACING, -layer * 2000, cell[2] * C.INSTANCE_SPACING)
end
function C.ChamberOrigin(slot)
	return C.InstanceOffset(slot) + C.EDITOR_ORIGIN
end

C.CHAPTERS = {
	{ title = "The Courtesy Call", map = "Chapter1", preview = "" },
	{ title = "The Cold Boot", map = "Chapter2", preview = "" },
	{ title = "The Return", map = "Chapter3", preview = "" },
	{ title = "The Surprise", map = "Chapter4", preview = "" },
	{ title = "The Escape", map = "Chapter5", preview = "" },
	{ title = "The Fall", map = "Chapter6", preview = "" },
	{ title = "The Reunion", map = "Chapter7", preview = "" },
	{ title = "The Itch", map = "Chapter8", preview = "" },
	{ title = "The Part Where He Kills You", map = "Chapter9", preview = "" },
}

C.COURSES = {
	{ title = "The Cold Boot", coop = false, chambers = {
		{ id = "SP_ColdBoot_01", name = "01 Portal Carousel" },
		{ id = "SP_ColdBoot_02", name = "02 Portal Gun" },
		{ id = "SP_ColdBoot_03", name = "03 Smooth Jazz" },
		{ id = "SP_ColdBoot_04", name = "04 Cube Momentum" },
	} },
	{ title = "Team Building", coop = true, chambers = {
		{ id = "MP_Team_01", name = "01 Doors" },
		{ id = "MP_Team_02", name = "02 Buttons" },
		{ id = "MP_Team_03", name = "03 Lasers" },
		{ id = "MP_Team_04", name = "04 Rat Maze" },
		{ id = "MP_Team_05", name = "05 Laser Crusher" },
		{ id = "MP_Team_06", name = "06 Behind the Scenes" },
	} },
}

C.ACHIEVEMENTS = {
	{ id = "WAKE_UP", name = "Wake Up Call", desc = "Finish the first chapter.", chapter = 1 },
	{ id = "COLD_BOOT", name = "Rebooted", desc = "Finish chapter two.", chapter = 2 },
	{ id = "HALFWAY", name = "Halfway There", desc = "Finish chapter five.", chapter = 5 },
	{ id = "THE_END", name = "Still Alive", desc = "Finish the last chapter.", chapter = 9, hidden = true },
	{ id = "FIRST_SAVE", name = "Insurance Policy", desc = "Save your game for the first time." },
	{ id = "PORTALS_100", name = "Hole Puncher", desc = "Place 100 portals.", goal = 100 },
	{ id = "PORTALS_1000", name = "Swiss Cheese", desc = "Place 1000 portals.", goal = 1000 },
	{ id = "ENRICHMENT", name = "Window Shopper", desc = "Visit Robot Enrichment.", client = true },
	{ id = "EDITOR", name = "Test Chamber Designer", desc = "Open the test chamber editor." },
	{ id = "PUBLISH", name = "Published Author", desc = "Publish a test chamber to the Workshop." },
	{ id = "WORKSHOP_PLAY", name = "Community Spirit", desc = "Finish a Workshop test chamber." },
	{ id = "COOP_FRIEND", name = "Team Player", desc = "Start a co-op game with a partner." },
	{ id = "OPTIONS", name = "Tinkerer", desc = "Change a setting in the options menu.", client = true },
}

C.STORE_CATEGORIES = { "Skins", "Headwear", "Misc", "Gestures", "Bundles" }
C.STORE = {
	{ id = "beanie", name = "Bionic Beanie", category = "Headwear", slot = "head", bots = "both", price = 25, productId = 0, icon = "", preview = "" },
	{ id = "tophat", name = "Top Hat", category = "Headwear", slot = "head", bots = "both", price = 25, productId = 0, icon = "", preview = "" },
	{ id = "glasses", name = "Science Goggles", category = "Headwear", slot = "head", bots = "both", price = 15, productId = 0, icon = "", preview = "" },
	{ id = "moonflag", name = "Moon Flag", category = "Misc", slot = "flag", bots = "both", price = 10, productId = 0, icon = "", preview = "" },
	{ id = "bitflag", name = "Bit.Trip Flag", category = "Misc", slot = "flag", bots = "both", price = 10, productId = 0, icon = "", preview = "" },
	{ id = "military", name = "Military Skins", category = "Skins", slot = "skin", bots = "both", price = 25, was = 60, productId = 0, icon = "", preview = "" },
	{ id = "moonskin", name = "Moon Skins", category = "Skins", slot = "skin", bots = "both", price = 25, was = 60, productId = 0, icon = "", preview = "" },
	{ id = "darkskin", name = "Shadow Skins", category = "Skins", slot = "skin", bots = "both", price = 25, was = 60, productId = 0, icon = "", preview = "" },
	{ id = "sitspin", name = "Sit Spin", category = "Gestures", slot = "gesture", bots = "orange", price = 15, productId = 0, icon = "", preview = "" },
	{ id = "dribble", name = "Dribble", category = "Gestures", slot = "gesture", bots = "blue", price = 15, productId = 0, icon = "", preview = "" },
	{ id = "starter", name = "Starter Bundle", category = "Bundles", price = 50, was = 75, productId = 0, icon = "", preview = "",
		grants = { "beanie", "moonflag", "military" } },
}
C.FEATURED_ITEM = "beanie"
C.BACKPACK_SLOTS = 250

C.MAX_SAVE_SLOTS = 20
C.AUTOSAVE_MINUTES = 5

C.CELL = 10
C.EDITOR_LIMITS = { x = 28, yMin = -4, yMax = 10, z = 28, cells = 4000, ents = 96, chips = 16, chipLen = 3000 }
C.MERGE_PANELS = true -- built chambers join neighbouring identical wall tiles into bigger parts (far fewer parts)
C.DIRS = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }
C.OFFS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
C.SURFACES = {
	white = { color = Color3.fromRGB(232, 236, 230), material = Enum.Material.SmoothPlastic },
	black = { color = Color3.fromRGB(66, 75, 73), material = Enum.Material.SmoothPlastic },
}

-- ==========================================
-- TILE COLOURS (editor: right-click a surface > Tile color, or T to paint the last colour again)
-- data.colors[faceKey] = index into this list. Textures / Decals on your tile assets get tinted too,
-- so white / light grey tile textures give the cleanest colours.
-- ==========================================
C.TILE_COLORS = {
	{ name = "Red", color = Color3.fromRGB(214, 74, 70) },
	{ name = "Orange", color = Color3.fromRGB(236, 140, 52) },
	{ name = "Yellow", color = Color3.fromRGB(236, 206, 70) },
	{ name = "Green", color = Color3.fromRGB(96, 186, 90) },
	{ name = "Cyan", color = Color3.fromRGB(70, 196, 210) },
	{ name = "Blue", color = Color3.fromRGB(66, 120, 220) },
	{ name = "Purple", color = Color3.fromRGB(150, 96, 214) },
	{ name = "Pink", color = Color3.fromRGB(230, 120, 180) },
	{ name = "Brown", color = Color3.fromRGB(140, 98, 66) },
	{ name = "Grey", color = Color3.fromRGB(140, 146, 146) },
}
-- the colour a tile ends up (non-portalable tiles get a darker shade so you can still tell them apart)
function C.TileTint(idx, portalable)
	local t = idx and C.TILE_COLORS[idx]
	if not t then return nil end
	return portalable and t.color or t.color:Lerp(Color3.new(0, 0, 0), 0.45)
end
function C.TintPanel(p, color)
	p.Color = color
	for _, d in ipairs(p:GetChildren()) do
		if d:IsA("Texture") or d:IsA("Decal") then d.Color3 = color end
	end
end

-- ==========================================
-- TEAM BUILDING (several players editing one chamber)
-- ==========================================
C.TEAM_MAX = 4
C.TEAM_COLORS = {
	Color3.fromRGB(70, 170, 255), Color3.fromRGB(255, 150, 40), Color3.fromRGB(110, 220, 90), Color3.fromRGB(235, 80, 170),
	Color3.fromRGB(170, 110, 255), Color3.fromRGB(255, 225, 70), Color3.fromRGB(80, 220, 210), Color3.fromRGB(255, 90, 80),
}

C.DOOR_ASSET = "ChamberLockDoor"
C.DOOR_RECESS = C.CELL -- the wall tile behind a door becomes an alcove this deep (C.CELL = one tile, 0 = no alcove)
C.DOOR_INSET = 0 -- studs from the room's wall surface to the FRONT of the door (0 = the door frame is flush with the wall,
                 -- C.DOOR_RECESS = pushed all the way to the back of the alcove like before)
C.DOOR_OPEN_RADIUS = 14 -- the exit door opens when a player is this close AND it's unlocked
-- The exit door is LOCKED until something opens it: a button / pedestal / laser catcher / gate connected to it, a chip
-- that opens it, or the item option "Open without a button" (e[10].free). Walking up to a locked door does nothing.
-- Doors are turned so their thinnest side faces the room. If yours ends up facing the wall, give the door model in
-- PortalAssets a MountRotation attribute of (0, 180, 0).
--
-- Start / End markers: a Folder (or Model) named "Start" / "End" with a part in it.
--   * inside the door model: used right where it is (Start = where you spawn, End = the finish trigger)
--   * in ReplicatedStorage.PortalAssets (or .EditorAssets), ReplicatedStorage, ServerStorage or workspace: cloned and
--     put in front of the entry / exit door
--   * none: the plain invisible square spawn pad / finish box
C.DOOR_MARKERS = { entry = "Start", exit = "End" }
C.FAITH_PLATE_FLUSH = true -- faith plates sit IN the floor (top flush with the tiles, in a little pit) like Portal 2

-- ALL test elements
--   mount:  "floor" | "ceiling" | "wall" | "any" (floors, walls and ceilings, sticking straight out of the surface)
--   asset:  model name looked up in ReplicatedStorage.PortalAssets (TestElements, TestingAssets, EditorAssets, then anywhere)
--   needsFloor: wall items that must sit on the bottom row of a wall (doors)
--   recess:  studs the item is pushed back into the wall; the wall tile is replaced by an alcove around it
--   flush:   floor items sunk into the floor: their top sits level with the tiles, the tile becomes a pit around them
--   span:    two-ended items (emitter "1" on the wall, emitter "2" across the room). e[9] = length in tiles,
--            nil = reach the opposite wall. Drag the end handle in the editor to change it.
--   fitCell: resize the model to exactly one tile (fitHeight = its thickness)
--   aim:     two attachment names (muzzle, target). The model is turned the least it takes to point that line straight
--            out of the surface (so it keeps the look it has in PortalAssets), then spun by the item's turn.
--   upright: "any" items that stand on the surface like they stand on the floor in PortalAssets (their up = out of the
--            surface): pedestals on walls stick straight out of the wall, on ceilings they hang down.
-- Per-template attributes you can set on the model in PortalAssets to fine-tune placement:
--   MountRotation (Vector3, degrees)  extra rotation after placing
--   MountOffset   (Vector3, studs)    extra offset in the surface's space (X right, Y up, -Z out of the surface)
--   Seat          (bool, default true) false = don't snap the model's bounding box onto the surface
C.ENTITY_TYPES = {
	entry        = { name = "Entry Door",             mount = "wall",    mandatory = true, needsFloor = true, recess = C.DOOR_RECESS, asset = C.DOOR_ASSET },
	exit         = { name = "Exit Door",              mount = "wall",    mandatory = true, needsFloor = true, recess = C.DOOR_RECESS, asset = C.DOOR_ASSET },
	button       = { name = "Weighted Floor Button",  mount = "floor",   asset = "Button" },
	pedestal     = { name = "Pedestal Button",        mount = "any",     upright = true, asset = "PedestalButton" },
	gate         = { name = "Logic Gate",             mount = "any",     asset = "Logic Gate" },
	cube         = { name = "Cube",                   mount = "floor" },
	cubedropper  = { name = "Cube Dropper",           mount = "ceiling", asset = "Cube Dropper" },
	faithplate   = { name = "Faith Plate",            mount = "floor",   flush = C.FAITH_PLATE_FLUSH, asset = "FaithPlate" },
	fizzler      = { name = "Fizzler",                mount = "wall",    span = true, asset = "Fizzler" },
	laser        = { name = "Laser Emitter",          mount = "any",     aim = { "ShootOut", "ShootEnd" }, asset = "Laser Emitter" },
	lasercatcher = { name = "Laser Catcher",          mount = "any",     asset = "Laser Catcher" },
	laserfield   = { name = "Laser Field",            mount = "wall",    span = true, asset = "Laser_Field" },
	lightbridge  = { name = "Hard Light Bridge",      mount = "wall",    asset = "LightBridgeFree" },
	tbeam        = { name = "Excursion Funnel",       mount = "wall",    asset = "TBeam" },
	turret       = { name = "Turret",                 mount = "floor",   asset = "Turret" },
	toxicgoo     = { name = "Toxic Goo",              mount = "floor",   fitCell = true, fitHeight = 0.5, asset = "ToxicGoo" },
	propulsion   = { name = "Propulsion Gel Dropper", mount = "ceiling", asset = "Propulsion Dropper" },
	repulsion    = { name = "Repulsion Gel Dropper",  mount = "ceiling", asset = "Repulsion Dropper" },
	gel_blue     = { name = "Repulsion Gel",          mount = "floor" },
	gel_orange   = { name = "Propulsion Gel",         mount = "floor" },
	gel_white    = { name = "Conversion Gel",         mount = "floor" },
	gel_water    = { name = "Cleansing Gel",          mount = "floor" },
	-- decoration from the editor's Meshes tab: e[7] = a model name in PortalAssets.Meshes or "mesh:<meshId>[:<textureId>]"
	-- e[10]: scale (0.25 - 4), spin (degrees), ox / oy / oz (studs, oy = up off the surface)
	prop         = { name = "Mesh",                   mount = "any",     upright = true, deco = true },
}

-- ==========================================
-- CONNECTIONS (the editor and PortalServer both use these - nothing to keep in sync any more)
-- ==========================================
-- sources drive things; logic gates are both (things go in, the gate drives something else).
-- An item with SEVERAL inputs needs ALL of them on (Portal 2). Put an OR gate in front for "any".
C.LINK_SOURCES = { button = true, pedestal = true, lasercatcher = true, gate = true }
C.LINK_ONLY_SOURCE = { button = true, pedestal = true, lasercatcher = true } -- nothing can drive these
C.LINK_BLOCKED = { cube = true, entry = true, gel_blue = true, gel_orange = true, gel_white = true, gel_water = true, prop = true }
function C.CanSource(kind) return C.LINK_SOURCES[kind] == true end
function C.CanTarget(kind)
	return C.ENTITY_TYPES[kind] ~= nil and not C.LINK_ONLY_SOURCE[kind] and not C.LINK_BLOCKED[kind]
end

-- Linked items: what they do while their inputs are off (the item menu's "Start enabled" overrides this).
-- Inputs on flips it. Funnels flip direction instead, droppers drop a new cube.
C.LINK_DEFAULT_ON = { fizzler = true, laserfield = true, laser = false, lightbridge = false, exit = false }
C.SWITCHABLE = { fizzler = true, laserfield = true, laser = true, lightbridge = true, exit = true }
C.BUTTON_TYPES = { "Weighted", "Cube", "Sphere" } -- floor button: anything / cubes only / spheres only
C.DROPPER_CUBES = { "Normal", "Companion", "Edgeless", "Reflection" } -- used when PortalAssets.Cubes is empty

-- pedestal buttons: the modes PedestalButtonServer has
C.PEDESTAL_TIMER = 3 -- default seconds for Timer mode (the editor's red timer, 1 - 30)
C.PEDESTAL_MODES = { "Timer", "Normal", "HoldDown" }
C.PEDESTAL_LABELS = {
	Timer = "Timer (on for the time below)",
	Normal = "Single press (short pulse)",
	HoldDown = "Toggle (click on, click off)",
}

-- logic gates: output = what the inputs add up to
C.GATE_TYPES = { "AND", "OR", "NOT", "XOR", "NAND", "NOR" }
C.GATE_LABELS = {
	AND = "AND - all inputs on",
	OR = "OR - any input on",
	NOT = "NOT - flips its input",
	XOR = "XOR - an odd number on",
	NAND = "NAND - not all on",
	NOR = "NOR - none on",
}
C.GATE_COLORS = {
	AND = Color3.fromRGB(70, 140, 225), OR = Color3.fromRGB(240, 150, 50), NOT = Color3.fromRGB(220, 70, 70),
	XOR = Color3.fromRGB(165, 95, 225), NAND = Color3.fromRGB(60, 185, 170), NOR = Color3.fromRGB(225, 205, 70),
}
function C.GateResult(mode, on, n)
	if mode == "OR" then return on > 0 end
	if mode == "NOT" or mode == "NOR" then return on == 0 end
	if mode == "XOR" then return on % 2 == 1 end
	if mode == "NAND" then return not (n > 0 and on == n) end
	return n > 0 and on == n -- AND
end

-- item options live in e[10] = { mode = string, startOn = bool, dropOnStart = bool, ... }
function C.Options(e)
	return type(e[10]) == "table" and e[10] or {}
end
function C.StartOn(e, linked)
	local o = C.Options(e)
	if type(o.startOn) == "boolean" then return o.startOn end
	if linked then return C.LINK_DEFAULT_ON[e[1]] == true end
	return true
end
function C.PedestalMode(e)
	local m = C.Options(e).mode
	return table.find(C.PEDESTAL_MODES, m) and m or "Timer"
end
function C.GateMode(e)
	local m = C.Options(e).mode
	return table.find(C.GATE_TYPES, m) and m or "AND"
end
-- exit door set to open without needing a button
function C.ExitFree(e)
	return e[1] == "exit" and C.Options(e).free == true
end

-- sets an attribute on an item and every model inside it (the scripts running the test elements look at the inner model)
function C.SetAll(root, name, value)
	root:SetAttribute(name, value)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Model") then d:SetAttribute(name, value) end
	end
end

-- data.faces[faceKey]: nil = portalable, 0 = not portalable, 2 = portalable with wall tiles, 3 = not portalable with wall tiles
-- (wall tiles only matter on floors / ceilings: they use the Floor / Ceiling tile assets otherwise)
function C.FaceInfo(v)
	return not (v == 0 or v == 3), (v == 2 or v == 3)
end
function C.FaceValue(portalable, wallTiles)
	if portalable then return wallTiles and 2 or nil end
	return wallTiles and 3 or 0
end

-- span items (fizzlers, laser fields) lie along the tile edge they sit on; turn 1 = upright, the way they're placed first
local function effRot(e)
	local def = C.ENTITY_TYPES[e[1]]
	return (e[6] or 0) + ((def and def.span) and 1 or 0)
end
C.EffRot = effRot

-- can an item of this type go on face f? (1/2 = ±X wall, 3 = ceiling, 4 = floor, 5/6 = ±Z wall)
function C.MountOk(def, f)
	if not def or not f then return false end
	if def.mount == "floor" then return f == 4 end
	if def.mount == "ceiling" then return f == 3 end
	if def.mount == "wall" then return f ~= 3 and f ~= 4 end
	return f >= 1 and f <= 6 -- "any"
end

-- how many tiles a span item can reach from its wall (counting its own tile) before hitting the far wall
function C.SpanMax(e, air)
	if not air then return nil end
	local o = C.OFFS[e[5]]
	if not o then return nil end
	local n, x, y, z = 1, e[2], e[3], e[4]
	while n < 60 do
		x, y, z = x - o[1], y - o[2], z - o[3]
		if not air[C.Key(x, y, z)] then break end
		n += 1
	end
	return n
end
function C.SpanLength(e, air)
	local max = C.SpanMax(e, air)
	local want = tonumber(e[9])
	if max then return want and math.clamp(math.floor(want), 1, max) or max end
	return want and math.max(1, math.floor(want)) or nil
end

-- does this item replace its tile (door alcove / faith plate pit)?
function C.MakesHole(kind)
	local def = C.ENTITY_TYPES[kind]
	if not def then return false end
	if (def.recess or 0) > 0 then return true end
	return def.flush == true and C.FindAsset ~= nil and C.FindAsset(def.asset) ~= nil
end
-- tiles that are replaced by a door alcove / faith plate pit
function C.HoleFaces(ents)
	local holes = {}
	for _, e in ipairs(ents or {}) do
		if C.MakesHole(e[1]) then holes[C.Key(e[2], e[3], e[4]) .. "," .. e[5]] = true end
	end
	return holes
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ASSET_FOLDERS = { "TestElements", "TestingAssets", "EditorAssets" }
local function assetFolder(name)
	local assets = ReplicatedStorage:FindFirstChild("PortalAssets")
	return assets and assets:FindFirstChild(name)
end
local function editorAsset(name)
	local f = assetFolder("EditorAssets")
	return f and f:FindFirstChild(name)
end
local function findAsset(name)
	if not name then return nil end
	local assets = ReplicatedStorage:FindFirstChild("PortalAssets")
	if not assets then return nil end
	for _, folderName in ipairs(ASSET_FOLDERS) do
		local folder = assets:FindFirstChild(folderName)
		local t = folder and folder:FindFirstChild(name)
		if t and (t:IsA("Model") or t:IsA("BasePart")) then return t end
	end
	-- anywhere else in PortalAssets, as long as it's a top-level item of some folder (not a part inside another model)
	for _, d in ipairs(assets:GetDescendants()) do
		if d.Name == name and (d:IsA("Model") or d:IsA("BasePart")) and d.Parent and d.Parent:IsA("Folder") then return d end
	end
	return nil
end

C.EditorAsset = editorAsset
C.FindAsset = findAsset

function C.CubeVariants()
	local f = assetFolder("Cubes")
	local list = {}
	if f then
		for _, c in ipairs(f:GetChildren()) do
			if c:IsA("Model") or c:IsA("BasePart") then table.insert(list, c.Name) end
		end
	end
	table.sort(list)
	return list
end

function C.CubeAsset(variant)
	local f = assetFolder("Cubes")
	return f and type(variant) == "string" and f:FindFirstChild(variant) or nil
end

-- ==========================================
-- TEXTURES TAB (data.textures[faceKey] = a name in PortalAssets.Textures or "id:<assetId>")
-- ==========================================
-- PortalAssets.Textures can hold Textures, Decals, or parts with a Texture / Decal on them (sub-folders are fine).
local libraryCache = {} -- [folderName] = { t = os.clock(), list = ... } (building a chamber looks things up a lot)
local function libraryItems(folderName, accept)
	local cached = libraryCache[folderName]
	if cached and os.clock() - cached.t < 3 then return cached.list end
	local f = assetFolder(folderName)
	local list, seen = {}, {}
	if not f then return list end
	local function walk(p, depth)
		for _, c in ipairs(p:GetChildren()) do
			if accept(c) then
				if not seen[c.Name] then
					seen[c.Name] = true
					table.insert(list, { name = c.Name, inst = c, folder = p ~= f and p.Name or nil })
				end
			elseif c:IsA("Folder") and depth < 4 then
				walk(c, depth + 1)
			end
		end
	end
	walk(f, 0)
	table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
	local byName = {}
	for _, it in ipairs(list) do byName[it.name] = it end
	list.byName = byName
	libraryCache[folderName] = { t = os.clock(), list = list }
	return list
end
local function textureOf(inst)
	if inst:IsA("Texture") or inst:IsA("Decal") then return inst end
	if inst:IsA("BasePart") then return inst:FindFirstChildWhichIsA("Texture") or inst:FindFirstChildWhichIsA("Decal") end
	return nil
end
function C.TextureList()
	return libraryItems("Textures", function(c) return textureOf(c) ~= nil end)
end
-- image id for previews
function C.TextureImage(v)
	if type(v) ~= "string" then return "" end
	local id = v:match("^id:(%d+)$")
	if id then return "rbxassetid://" .. id end
	local it = C.TextureList().byName[v]
	local t = it and textureOf(it.inst)
	return t and t.Texture or ""
end
function C.ValidTextureValue(v)
	return type(v) == "string" and #v <= 60 and (v:match("^id:%d+$") ~= nil or v:match("^[%w _%-%.%(%)]+$") ~= nil)
end
function C.TextureTemplate(v)
	if type(v) ~= "string" then return nil end
	local id = v:match("^id:(%d+)$")
	if id then
		local t = Instance.new("Texture")
		t.Texture = "rbxassetid://" .. id
		t.StudsPerTileU, t.StudsPerTileV = C.CELL, C.CELL
		return t
	end
	local it = C.TextureList().byName[v]
	local t = it and textureOf(it.inst)
	return t and t:Clone() or nil
end
-- the side of part p that faces direction dir
function C.NormalTo(p, dir)
	local l = p.CFrame:VectorToObjectSpace(dir)
	local ax, ay, az = math.abs(l.X), math.abs(l.Y), math.abs(l.Z)
	if ax >= ay and ax >= az then return l.X > 0 and Enum.NormalId.Right or Enum.NormalId.Left end
	if ay >= az then return l.Y > 0 and Enum.NormalId.Top or Enum.NormalId.Bottom end
	return l.Z > 0 and Enum.NormalId.Back or Enum.NormalId.Front
end
-- puts the texture on the side of p facing roomDir (replacing the tile asset's own textures)
function C.ApplyTexture(p, v, roomDir)
	local t = C.TextureTemplate(v)
	if not t then return nil end
	for _, d in ipairs(p:GetChildren()) do
		if d:IsA("Texture") or d:IsA("Decal") then d:Destroy() end
	end
	t.Face = C.NormalTo(p, roomDir)
	t.Parent = p
	return t
end

-- ==========================================
-- MESHES TAB (prop items: e[7] = a name in PortalAssets.Meshes or "mesh:<meshId>[:<textureId>]")
-- ==========================================
function C.MeshList()
	return libraryItems("Meshes", function(c) return c:IsA("Model") or c:IsA("BasePart") end)
end
function C.ValidMeshValue(v)
	return type(v) == "string" and #v <= 60 and (v:match("^mesh:%d+$") ~= nil or v:match("^mesh:%d+:%d+$") ~= nil
		or v:match("^asset:%d+$") ~= nil or v:match("^tbmesh:%d+$") ~= nil or v:match("^[%w _%-%.%(%)]+$") ~= nil)
end
-- Meshes tab search: Roblox's Creator Store API, MeshParts only (PortalServer calls it with HttpService).
-- Needs Game Settings > Security > Allow HTTP Requests. If Roblox asks for a key (401 / 403), make an Open Cloud API
-- key with Creator Store read access and store it as an experience secret with this name.
C.CREATOR_STORE_SEARCH_URL = "https://apis.roblox.com/toolbox-service/v2/assets:search"
C.CREATOR_STORE_KEY_SECRET = "CreatorStoreApiKey"

-- models loaded from the Toolbox (Creator Store) by PortalServer live here, named by asset id
C.TOOLBOX_FOLDER = "PortalToolbox"
function C.ToolboxModel(id)
	local f = ReplicatedStorage:FindFirstChild(C.TOOLBOX_FOLDER)
	return f and f:FindFirstChild(tostring(id)) or nil
end
-- name of the MeshPart PortalServer makes from a mesh id (+ texture id)
function C.MeshKey(id, tex)
	return "mesh_" .. tostring(id) .. ((tex and tex ~= "") and ("_" .. tostring(tex)) or "")
end
function C.MeshTemplate(v)
	if type(v) ~= "string" then return nil end
	local aid = v:match("^asset:(%d+)$")
	if aid then return C.ToolboxModel(aid) end
	-- a Toolbox item, cut down to just its MeshParts (PortalServer)
	local tbid = v:match("^tbmesh:(%d+)$")
	if tbid then return C.ToolboxModel("tbmesh_" .. tbid) end
	local mid, tid = v:match("^mesh:(%d+):?(%d*)$")
	-- the real MeshPart once the server has made it; a SpecialMesh stand-in until then
	local real = mid and C.ToolboxModel(C.MeshKey(mid, tid))
	if real then return real end
	if mid then
		-- MeshPart.MeshId can't be set while the game runs, a SpecialMesh can
		local p = Instance.new("Part")
		p.Name = "CustomMesh"
		p.Size = Vector3.new(4, 4, 4)
		p.Anchored = true
		local sm = Instance.new("SpecialMesh")
		sm.MeshType = Enum.MeshType.FileMesh
		sm.MeshId = "rbxassetid://" .. mid
		if tid and tid ~= "" then sm.TextureId = "rbxassetid://" .. tid end
		sm.Parent = p
		return p
	end
	local it = C.MeshList().byName[v]
	return it and it.inst or nil
end

-- ==========================================
-- START / END MARKERS (see C.DOOR_MARKERS)
-- ==========================================
local function markerPartIn(holder)
	if holder:IsA("BasePart") then return holder end
	return holder:FindFirstChildWhichIsA("BasePart", true)
end
-- a Start / End folder somewhere in the game (cloned and put in front of the door)
function C.MarkerTemplate(name)
	local roots = {}
	local assets = ReplicatedStorage:FindFirstChild("PortalAssets")
	if assets then
		table.insert(roots, assets)
		local ea = assets:FindFirstChild("EditorAssets")
		if ea then table.insert(roots, ea) end
	end
	table.insert(roots, ReplicatedStorage)
	pcall(function() table.insert(roots, game:GetService("ServerStorage")) end)
	table.insert(roots, workspace)
	for _, r in ipairs(roots) do
		local f = r:FindFirstChild(name)
		if f and (f:IsA("Folder") or f:IsA("Model") or f:IsA("BasePart")) then
			local p = markerPartIn(f)
			if p then return p end
		end
	end
	return nil
end
-- a Start / End folder inside a built door model (used where it is)
local function markerInside(root, name)
	local want = name:lower()
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("Folder") or d:IsA("Model")) and d.Name:lower() == want then
			local p = markerPartIn(d)
			if p then return p, d end
		end
	end
	return nil
end
C.MarkerInside = markerInside

local function eachPart(inst, fn)
	if inst:IsA("BasePart") then fn(inst) end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then fn(d) end
	end
end
C.EachPart = eachPart

function C.Key(x, y, z) return x .. "," .. y .. "," .. z end
function C.FaceKey(x, y, z, f) return x .. "," .. y .. "," .. z .. "," .. f end

function C.FaceCFrame(origin, x, y, z, f, depth)
	local d = C.DIRS[f]
	local pos = origin + Vector3.new(x, y, z) * C.CELL + d * (C.CELL / 2 + depth)
	local up = math.abs(d.Y) > 0.5 and Vector3.zAxis or Vector3.yAxis
	return CFrame.lookAt(pos, pos - d, up)
end

-- Where an item sits. In this frame -Z (LookVector) always points out of the surface into the room.
--   floor / ceiling: on the surface centre, upright, turned by rot * 90 degrees
--   wall:            bottom edge of the panel (so doors stand on the floor), facing into the room
--   any:             centre of the panel, LookVector straight out of the surface (rot spins it about that axis)
function C.EntityCFrame(origin, e)
	local def = C.ENTITY_TYPES[e[1]]
	local x, y, z, f, rot = e[2], e[3], e[4], e[5], effRot(e)
	local d = C.DIRS[f]
	local center = origin + Vector3.new(x, y, z) * C.CELL
	local surface = center + d * (C.CELL / 2)
	if def and def.upright then
		-- the model's up = straight out of the surface; on the floor that's exactly how it stands in PortalAssets
		local n = -d
		local ref = math.abs(n.Y) > 0.5 and Vector3.zAxis or Vector3.yAxis
		local look = -(ref - n * ref:Dot(n)).Unit
		local spin = def.deco and (tonumber(C.Options(e).spin) or 0) or 0
		return CFrame.lookAt(surface, surface + look, n) * CFrame.Angles(0, math.rad(rot * 90 + spin), 0)
	end
	if def and def.mount == "any" then
		local up = math.abs(d.Y) > 0.5 and Vector3.zAxis or Vector3.yAxis
		return CFrame.lookAt(surface, surface - d, up) * CFrame.Angles(0, 0, math.rad(rot * 90))
	end
	if math.abs(d.Y) > 0.5 then
		return CFrame.new(surface) * CFrame.Angles(0, math.rad(rot * 90), 0)
	end
	if def and def.needsFloor then
		local base = Vector3.new(surface.X, center.Y - C.CELL / 2, surface.Z)
		return CFrame.lookAt(base, base - d)
	end
	-- other wall items sit on one edge of the tile: rot turns them to the next edge (the editor's diamond handles)
	return CFrame.lookAt(surface, surface - d) * CFrame.Angles(0, 0, math.rad(rot * 90)) * CFrame.new(0, -C.CELL / 2, 0)
end

-- the tile frame an item sits in: centre of the panel, -Z out of the surface, Y = the item's "up" after its turn
function C.ItemFrame(origin, e)
	local f, rot = e[5], effRot(e)
	local d = C.DIRS[f]
	local surface = origin + Vector3.new(e[2], e[3], e[4]) * C.CELL + d * (C.CELL / 2)
	local up = math.abs(d.Y) > 0.5 and Vector3.zAxis or Vector3.yAxis
	return CFrame.lookAt(surface, surface - d, up) * CFrame.Angles(0, 0, math.rad(rot * 90))
end

-- min / max corners of an oriented box, measured in cf's local space
local function extentsIn(cf, boxCF, size)
	local rel = cf:ToObjectSpace(boxCF)
	local h = size / 2
	local ax, ay, az = rel.XVector, rel.YVector, rel.ZVector
	local ext = Vector3.new(
		math.abs(ax.X) * h.X + math.abs(ay.X) * h.Y + math.abs(az.X) * h.Z,
		math.abs(ax.Y) * h.X + math.abs(ay.Y) * h.Y + math.abs(az.Y) * h.Z,
		math.abs(ax.Z) * h.X + math.abs(ay.Z) * h.Y + math.abs(az.Z) * h.Z
	)
	return rel.Position - ext, rel.Position + ext
end
local function boundsOf(v)
	if v:IsA("Model") then return v:GetBoundingBox() end
	return v.CFrame, v.Size
end

-- top-level pieces of a model (children, looking inside Folders)
local function piecesOf(root)
	local out = {}
	local function walk(p)
		for _, c in ipairs(p:GetChildren()) do
			if c:IsA("BasePart") or c:IsA("Model") then table.insert(out, c)
			elseif c:IsA("Folder") then walk(c) end
		end
	end
	walk(root)
	return out
end
local function centerOf(inst)
	if inst:IsA("BasePart") then return inst.Position end
	return (inst:GetBoundingBox()).Position
end
-- the two ends of a two-ended item: children "1" / "2", a piece named ...End and the piece furthest from it,
-- two pieces with the same name, or failing that the two pieces furthest apart
local function findEnds(root)
	if not root:IsA("Model") then return nil end
	local a, b = root:FindFirstChild("1"), root:FindFirstChild("2")
	if a and b and (a:IsA("BasePart") or a:IsA("Model")) and (b:IsA("BasePart") or b:IsA("Model")) then return a, b end
	local pieces = piecesOf(root)
	local function farthestFrom(p)
		local best, bd = nil, -1
		for _, q in ipairs(pieces) do
			if q ~= p then
				local d = (centerOf(q) - centerOf(p)).Magnitude
				if d > bd then best, bd = q, d end
			end
		end
		return best
	end
	for _, p in ipairs(pieces) do
		if p.Name:lower():match("end$") then
			local o = farthestFrom(p)
			if o then return o, p end
		end
	end
	local byName = {}
	for _, p in ipairs(pieces) do
		if byName[p.Name] then return byName[p.Name], p end
		byName[p.Name] = p
	end
	local best, bestA, bestB = -1, nil, nil
	for i = 1, #pieces do
		for j = i + 1, #pieces do
			local d = (centerOf(pieces[i]) - centerOf(pieces[j])).Magnitude
			if d > best then best, bestA, bestB = d, pieces[i], pieces[j] end
		end
	end
	return bestA, bestB
end

-- world position of a named attachment / bone in a template (loose attachments in a model are world-space)
local function aimPoint(root, name)
	local want = name:lower():gsub("[^%a]", "")
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Attachment") and d.Name:lower():gsub("[^%a]", "") == want then
			-- bones (and anything under a part or a bone) are relative to their parent: ask for the world position
			if d:IsA("Bone") or (d.Parent and (d.Parent:IsA("BasePart") or d.Parent:IsA("Attachment"))) then
				return d.WorldPosition
			end
			return d.Position -- loose in the model: already world-space
		end
	end
	return nil
end

-- clone a template even if some of its parts have Archivable off. Clone() silently skips those, which is
-- exactly how an item can look fine in Studio and lose bits (turret arms, a button mesh) when it gets built.
local function cloneTemplate(template)
	local off = {}
	for _, d in ipairs(template:GetDescendants()) do
		if not d.Archivable then
			d.Archivable = true
			table.insert(off, d)
		end
	end
	local rootOff = not template.Archivable
	if rootOff then template.Archivable = true end
	local v = template:Clone()
	for _, d in ipairs(off) do d.Archivable = false end
	if rootOff then template.Archivable = false end
	return v
end

-- min / max of the parts you can actually SEE, in cf's space. Invisible hitboxes, vision cones, triggers or a
-- helper part left somewhere in the asset no longer drag the model off its tile / down into the floor.
local function visibleExtents(cf, v)
	local mn, mx
	local function add(p)
		local a, b = extentsIn(cf, p.CFrame, p.Size)
		mn = mn and mn:Min(a) or a
		mx = mx and mx:Max(b) or b
	end
	eachPart(v, function(p) if p.Transparency < 0.98 then add(p) end end)
	if not mn then eachPart(v, add) end
	if not mn then
		local bcf, size = boundsOf(v)
		return extentsIn(cf, bcf, size)
	end
	return mn, mx
end

-- the smallest rotation that turns direction a onto direction b
local function shortestArc(a, b)
	local d = a:Dot(b)
	if d > 0.9999 then return CFrame.new() end
	if d < -0.9999 then
		local axis = math.abs(a.X) < 0.9 and a:Cross(Vector3.xAxis) or a:Cross(Vector3.yAxis)
		return CFrame.fromAxisAngle(axis.Unit, math.pi)
	end
	return CFrame.fromAxisAngle(a:Cross(b).Unit, math.acos(math.clamp(d, -1, 1)))
end

-- ----- span items: keep their beams alive after stretching -----
local function partOf(x)
	if x:IsA("BasePart") then return x end
	return x:FindFirstChildWhichIsA("BasePart", true)
end
-- Beams only draw between attachments that live in a part (or a bone). An attachment sitting loose in a model, one
-- that points outside the model, or one that's missing makes the beam silently vanish while the field still works.
-- Loose ones are moved into the end they're nearest to (same spot), missing ones get a fresh attachment on that end.
local function fixSpanBeams(v, a, b)
	local pa, pb = partOf(a), partOf(b)
	local effects = 0
	for _, d in ipairs(v:GetDescendants()) do
		if d:IsA("ParticleEmitter") then effects += 1 end
		if d:IsA("Beam") then
			effects += 1
			if pa and pb then
				for i, prop in ipairs({ "Attachment0", "Attachment1" }) do
					local att = d[prop]
					local inside = att and att:IsDescendantOf(v)
					local hosted = inside and att.Parent and (att.Parent:IsA("BasePart") or att.Parent:IsA("Attachment"))
					if inside and not hosted then
						local w = att.CFrame -- loose in a model = world space (placeTemplate already moved it)
						local host = ((w.Position - pa.Position).Magnitude <= (w.Position - pb.Position).Magnitude) and pa or pb
						att.Parent = host
						att.WorldCFrame = w
					elseif not inside then
						local host = (i == 1) and pa or pb
						local n = host:FindFirstChild("SpanBeam" .. i)
						if not n then
							n = Instance.new("Attachment")
							n.Name = "SpanBeam" .. i
							n.Parent = host
						end
						d[prop] = n
					end
				end
			end
		end
	end
	return effects
end
-- laser field with no beam / particles at all: a see-through red sheet between the two posts
local function fieldFallback(v, a, b)
	local ca, cb = centerOf(a), centerOf(b)
	local len = (cb - ca).Magnitude
	if len < 0.5 then return end
	local dir = (cb - ca) / len
	local bcf, size = boundsOf(a)
	local best
	for _, ax in ipairs({ { bcf.RightVector, size.X }, { bcf.UpVector, size.Y }, { bcf.LookVector, size.Z } }) do
		local flat = ax[1] - dir * ax[1]:Dot(dir)
		if flat.Magnitude > 0.5 and (not best or ax[2] > best[2]) then best = { flat.Unit, ax[2] } end
	end
	if not best then return end
	local p = Instance.new("Part")
	p.Name = "FieldFallback"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 60, 60)
	p.Transparency = 0.7
	p.Size = Vector3.new(len, math.max(best[2] * 0.85, 1), 0.06)
	p.CFrame = CFrame.fromMatrix((ca + cb) / 2, dir, best[1])
	p.Parent = v
end

-- clone a template and put it on the surface.
-- Returns the clone, how far its front sticks out (local Z, negative = into the room), for span items the far end,
-- and how tall the visible model is (used for the faith plate pit)
local function placeTemplate(template, def, cf, e, opts)
	local v = cloneTemplate(template)
	local target = cf
	local pa, pb
	if def.span and v:IsA("Model") then
		local a, b = findEnds(template)
		if a and b then pa, pb = centerOf(a), centerOf(b) end
	elseif def.aim then
		pa, pb = aimPoint(template, def.aim[1]), aimPoint(template, def.aim[2])
	end
	if def.aim and pa and pb and (pb - pa).Magnitude > 0.01 then
		-- lasers: turn it the LEAST it takes to point the muzzle straight out of the surface, then spin it by the
		-- item's turn. A laser modelled standing on the floor sits on a floor exactly like that and tips over onto
		-- walls; one modelled on a wall hangs on walls like that and lies down on floors.
		local want = cf.LookVector
		local spin = CFrame.fromAxisAngle(want, math.rad(effRot(e) * 90))
		target = CFrame.new(cf.Position) * spin * shortestArc((pb - pa).Unit, want) * template:GetPivot().Rotation
	elseif pa and pb then
		-- span items: 1 -> 2 points straight out of the surface, keeping its up as up
		local T = template:GetPivot()
		local axis = T:VectorToObjectSpace(pb - pa)
		if axis.Magnitude > 0.01 then
			local look = axis.Unit
			local up = T:VectorToObjectSpace(Vector3.yAxis)
			if math.abs(look:Dot(up)) > 0.95 then up = T:VectorToObjectSpace(Vector3.zAxis) end
			up = (up - look * look:Dot(up)).Unit
			local F = CFrame.fromMatrix(Vector3.zero, look:Cross(up).Unit, up, -look)
			target = cf * F:Inverse()
			if def.span then
				-- posts / emitter strips lie along the tile edge the item sits on
				target = cf * CFrame.Angles(0, 0, math.rad(90)) * F:Inverse()
			end
		end
	elseif def.needsFloor then
		-- doors: keep the way the model stands in PortalAssets (up stays up) and turn it so its thinnest horizontal
		-- side (the way you walk through it) points out of the wall
		local T = template:GetPivot()
		local mn0, mx0 = visibleExtents(CFrame.new(T.Position), template)
		local w = mx0 - mn0
		local thin = (w.X < w.Z) and Vector3.xAxis or Vector3.zAxis
		-- which way along that axis is the front: the pivot's facing if it points along it, else -Z
		local look = Vector3.new(T.LookVector.X, 0, T.LookVector.Z)
		local front = -Vector3.zAxis
		if look.Magnitude > 0.1 and math.abs(look.Unit:Dot(thin)) > 0.7 then
			front = thin * (look:Dot(thin) > 0 and 1 or -1)
		elseif thin == Vector3.xAxis then
			front = -Vector3.xAxis
		end
		-- turn about Y so the front points out of the wall (cf's -Z)
		local yaw = CFrame.Angles(0, math.atan2(front.X, -front.Z), 0)
		target = cf * yaw * T.Rotation
	elseif def.upright or def.mount == "floor" or def.mount == "ceiling" then
		-- keep the way the model stands in PortalAssets (so turrets etc. stay upright whatever their pivot is),
		-- only add the item's turn
		target = cf * template:GetPivot().Rotation
	end
	local mr = template:GetAttribute("MountRotation")
	if typeof(mr) == "Vector3" then
		target = target * CFrame.Angles(math.rad(mr.X), math.rad(mr.Y), math.rad(mr.Z))
	end
	v:PivotTo(target)

	-- meshes from the Meshes tab: their scale
	if def.deco then
		local k = math.clamp(tonumber(C.Options(e).scale) or 1, 0.25, 4)
		if math.abs(k - 1) > 0.001 then
			if v:IsA("Model") then
				pcall(function() v:ScaleTo(v:GetScale() * k) end)
			elseif v:IsA("BasePart") then
				local c = v.CFrame
				v.Size *= k
				v.CFrame = c
				local sm = v:FindFirstChildWhichIsA("SpecialMesh")
				if sm then sm.Scale *= k end
			end
		end
	end

	-- exactly one tile (toxic goo etc.)
	local gooOffset = Vector3.zero
	if def.fitCell then
		local o = type(e[10]) == "table" and e[10] or {}
		local x0, x1, z0, z1 = tonumber(o.gx0) or 0, tonumber(o.gx1) or 0, tonumber(o.gz0) or 0, tonumber(o.gz1) or 0
		gooOffset = Vector3.new((x1 - x0) / 2, 0, (z1 - z0) / 2) * C.CELL
		if v:IsA("BasePart") then
			v.Size = Vector3.new(C.CELL * (1 + x0 + x1), def.fitHeight or 1, C.CELL * (1 + z0 + z1))
			v.CFrame = CFrame.new(v.Position)
		elseif v:IsA("Model") then
			local _, sz = v:GetBoundingBox()
			local k = C.CELL / math.max(sz.X, sz.Z, 0.01)
			pcall(function() v:ScaleTo(v:GetScale() * k) end)
		end
	end

	local seatAs = def.upright and "floor" or def.mount
	local mn, mx
	if seatAs == "floor" or seatAs == "ceiling" or def.needsFloor then
		mn, mx = visibleExtents(cf, v) -- turrets, buttons, pedestals, plates, droppers: seat on what you see
	else
		local bcf, size = boundsOf(v)
		mn, mx = extentsIn(cf, bcf, size)
	end
	local shift = Vector3.zero
	if template:GetAttribute("Seat") ~= false then
		local cx, cy, cz = (mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z) / 2
		if seatAs == "floor" then
			if def.flush then
				shift = Vector3.new(-cx, -mx.Y + 0.05, -cz) -- top level with the floor tiles (it sits in a pit)
			else
				shift = Vector3.new(-cx, -mn.Y + 0.05, -cz)
			end
		elseif seatAs == "ceiling" then
			shift = Vector3.new(-cx, -mx.Y - 0.05, -cz)
		elseif def.needsFloor then
			-- doors: stand on the floor, front of the frame C.DOOR_INSET behind the wall surface (sticks back into the alcove)
			shift = Vector3.new(-cx, -mn.Y, -mn.Z + math.clamp(C.DOOR_INSET or 0, 0, math.max(def.recess or 0, 0)))
		elseif seatAs == "wall" then
			shift = Vector3.new(-cx, -mn.Y, -mx.Z) -- stands on the panel's bottom edge, back against the wall
		else
			shift = Vector3.new(-cx, -cy, -mx.Z) -- centred on the panel, back against the surface
		end
	end
	if (def.recess or 0) > 0 and not (def.needsFloor and template:GetAttribute("Seat") ~= false) then shift += Vector3.new(0, 0, def.recess) end
	if def.deco then
		local o = C.Options(e)
		local lim = C.CELL
		shift += Vector3.new(math.clamp(tonumber(o.ox) or 0, -lim, lim), math.clamp(tonumber(o.oy) or 0, -lim, lim), math.clamp(tonumber(o.oz) or 0, -lim, lim))
	end
	if gooOffset ~= Vector3.zero then shift += cf:VectorToObjectSpace(gooOffset) end
	local mo = template:GetAttribute("MountOffset")
	if typeof(mo) == "Vector3" then shift += mo end
	if shift ~= Vector3.zero then v:PivotTo(v:GetPivot() + cf:VectorToWorldSpace(shift)) end

	-- attachments sitting loose in the model (not in a part) are world-space and don't follow PivotTo:
	-- carry them along by hand, otherwise lasers / beams fire from where the asset sits in ReplicatedStorage.
	-- NOT bones: a bone (or attachment) inside another bone is relative to that bone and already moves with the
	-- mesh. Treating those as world-space flung every child bone across the map, and everything skinned to them
	-- (button caps, turret arms...) vanished.
	local loose = {}
	if v:IsA("Model") then
		local P, T = v:GetPivot(), template:GetPivot()
		for _, d in ipairs(v:GetDescendants()) do
			if d:IsA("Attachment") and not d:IsA("Bone")
				and not (d.Parent and (d.Parent:IsA("BasePart") or d.Parent:IsA("Attachment"))) then
				d.CFrame = P * T:ToObjectSpace(d.CFrame)
				table.insert(loose, d)
			end
		end
	end

	-- stretch two-ended items: move emitter 2 (and everything on its side) out to the chosen length,
	-- stretch anything that spans the gap. Beams between attachments follow on their own.
	local spanEnd
	if def.span and v:IsA("Model") then
		local a, b = findEnds(v)
		local L = C.SpanLength(e, opts and opts.air)
		if a and b and L then
			local za = cf:PointToObjectSpace(centerOf(a)).Z
			local zb = cf:PointToObjectSpace(centerOf(b)).Z
			if za < zb then a, b, za, zb = b, a, zb, za end -- a = the end on the wall
			local want = -(L * C.CELL) - za -- b as far from the far wall as a is from this one
			local dz = want - zb
			if math.abs(dz) > 0.01 then
				local sep = math.max(math.abs(za - zb), 0.01)
				local mid = (za + zb) / 2
				local lv = cf.LookVector
				local move = cf:VectorToWorldSpace(Vector3.new(0, 0, dz))
				for _, p in ipairs(piecesOf(v)) do
					local pcf, psize = boundsOf(p)
					local pmn, pmx = extentsIn(cf, pcf, psize)
					if p ~= a and p ~= b and p:IsA("BasePart") and (pmx.Z - pmn.Z) > sep * 0.7 then
						local r, u, l = math.abs(p.CFrame.RightVector:Dot(lv)), math.abs(p.CFrame.UpVector:Dot(lv)), math.abs(p.CFrame.LookVector:Dot(lv))
						local grow = (r >= u and r >= l) and Vector3.new(-dz, 0, 0) or (u >= l and Vector3.new(0, -dz, 0) or Vector3.new(0, 0, -dz))
						local old = p.Size
						local ns = p.Size + grow
						p.Size = Vector3.new(math.max(ns.X, 0.05), math.max(ns.Y, 0.05), math.max(ns.Z, 0.05))
						p.CFrame += move / 2
						-- attachments on a stretched part (beam ends on a field strip) slide out with its ends
						local k = p.Size / Vector3.new(math.max(old.X, 0.01), math.max(old.Y, 0.01), math.max(old.Z, 0.01))
						for _, att in ipairs(p:GetChildren()) do
							if att:IsA("Attachment") then att.Position = att.Position * k end
						end
					elseif p == b or (pmn.Z + pmx.Z) / 2 < mid then
						p:PivotTo(p:GetPivot() + move)
					end
				end
				for _, att in ipairs(loose) do
					if cf:PointToObjectSpace(att.Position).Z < mid then att.CFrame += move end
				end
			end
			spanEnd = centerOf(b)
		end
		if a and b then
			local effects = fixSpanBeams(v, a, b)
			if effects == 0 and e[1] == "laserfield" and not (opts and opts.editor) then fieldFallback(v, a, b) end
		end
	end
	return v, mn.Z + shift.Z, spanEnd, mx.Y - mn.Y
end

-- tile assets in PortalAssets.EditorAssets (names are matched loosely: case, spaces and "_" don't matter)
local TILE_NAMES = {
	wall = { "Wall", "white" },
	npwall = { "NPWall", "black" },
	floor = { "Floor", "FloorTile", "FloorTiles" },
	npfloor = { "NPFloor", "NPFloorTile", "NPFloorTiles" },
	ceiling = { "Ceiling", "Celling", "CeilingTile", "CeilingTiles", "CellingTile", "CellingTiles" },
	npceiling = { "NPCeiling", "NPCelling", "NPCeilingTile", "NPCeilingTiles", "NPCellingTile", "NPCellingTiles" },
}
local function squashName(n) return (n:lower():gsub("[^%a]", "")) end
local function tileAsset(kind)
	local f = assetFolder("EditorAssets")
	if not f then return nil end
	for _, n in ipairs(TILE_NAMES[kind]) do
		local want = squashName(n)
		for _, c in ipairs(f:GetChildren()) do
			if c:IsA("BasePart") and squashName(c.Name) == want then return c end
		end
	end
	return nil
end
C.TileAsset = tileAsset

-- which tile set a face uses: floor / ceiling tiles on floors and ceilings unless the face is set to wall tiles
function C.TileKind(portalable, f, style)
	local surf = "wall"
	if style ~= "wall" then
		if f == 4 then surf = "floor" elseif f == 3 then surf = "ceiling" end
	end
	return (portalable and "" or "np") .. surf
end

-- the side of a tile asset that has its texture faces the room
local FACE_TURN = {
	[Enum.NormalId.Front] = { CFrame.new(), "z" },
	[Enum.NormalId.Back] = { CFrame.Angles(0, math.pi, 0), "z" },
	[Enum.NormalId.Top] = { CFrame.Angles(-math.pi / 2, 0, 0), "y" },
	[Enum.NormalId.Bottom] = { CFrame.Angles(math.pi / 2, 0, 0), "y" },
	[Enum.NormalId.Right] = { CFrame.Angles(0, math.pi / 2, 0), "x" },
	[Enum.NormalId.Left] = { CFrame.Angles(0, -math.pi / 2, 0), "x" },
}
-- place a panel: cf = the face frame (-Z into the room), size = tile width (along cf X), thick = thickness,
-- height = along cf Y (defaults to size: one square tile)
function C.PlacePanel(p, cf, size, thick, height)
	height = height or size
	local turn = FACE_TURN[Enum.NormalId.Front]
	local tex = p:FindFirstChildWhichIsA("Texture") or p:FindFirstChildWhichIsA("Decal")
	if tex then turn = FACE_TURN[tex.Face] or turn end
	if turn[2] == "y" then p.Size = Vector3.new(size, thick, height)
	elseif turn[2] == "x" then p.Size = Vector3.new(thick, height, size)
	else p.Size = Vector3.new(size, height, thick) end
	p.CFrame = cf * turn[1]
end

local function panelPart(portalable, f, style)
	local kind = C.TileKind(portalable, f, style)
	local template = tileAsset(kind) or tileAsset(portalable and "wall" or "npwall")
	if template and template:IsA("BasePart") then return template:Clone() end
	local s = portalable and C.SURFACES.white or C.SURFACES.black
	local p = Instance.new("Part")
	p.Color, p.Material = s.color, s.material
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	return p
end

local function removeNamed(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name and d:IsA("BasePart") then d:Destroy() end
	end
end

-- prints what got built for these kinds (Output window). Set to {} once they look right.
C.DEBUG_BUILD = { turret = true, button = true }
local function debugBuild(kind, template, v)
	local tCount, cCount, bones, hidden, notArch = 0, 0, 0, {}, {}
	eachPart(template, function() tCount += 1 end)
	for _, d in ipairs(template:GetDescendants()) do
		if not d.Archivable then table.insert(notArch, d.Name) end
		if d:IsA("Bone") then bones += 1 end
	end
	eachPart(v, function(p)
		cCount += 1
		if p.Transparency >= 0.98 then table.insert(hidden, p.Name) end
	end)
	print(("[PortalConfig] %s from %s: %d/%d parts, %d bones | invisible: [%s] | Archivable off: [%s]"):format(
		kind, template:GetFullName(), cCount, tCount, bones, table.concat(hidden, ", "), table.concat(notArch, ", ")))
end

function C.BuildEntity(e, origin, opts)
	opts = opts or {}
	local kind = e[1]
	local def = C.ENTITY_TYPES[kind]
	if not def then return nil end
	local cf = C.EntityCFrame(origin, e)
	local o = C.Options(e)
	local m = Instance.new("Model")
	-- neutral name: the test element scripts recognise models by name, and they should only see the real model inside
	m.Name = "PeTIItem"
	m:SetAttribute("Kind", kind)
	local element = m -- the model the test element scripts run (the asset itself when there is one)

	local template
	if kind == "cube" then
		template = C.CubeAsset(e[7])
	elseif kind == "prop" then
		template = C.MeshTemplate(e[7])
	else
		template = findAsset(def.asset)
	end
	if not template and (kind == "entry" or kind == "exit") then
		template = editorAsset(kind) or editorAsset("spawn")
	end

	local front = -1 -- local Z of the item's front face
	local height
	if template then
		local v, fz, spanEnd, h = placeTemplate(template, def, cf, e, opts)
		front, height = fz, h
		v.Parent = m
		if C.DEBUG_BUILD[kind] then debugBuild(kind, template, v) end
		if v:IsA("Model") then element = v end
		if spanEnd then m:SetAttribute("SpanEnd", spanEnd) end
	else
		-- placeholders when the asset is missing
		local function part(props)
			local p = Instance.new("Part")
			p.Anchored = true
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			for k, v in pairs(props) do p[k] = v end
			p.Parent = m
			return p
		end
		if kind == "entry" or kind == "exit" then
			part({ Name = "Door", Size = Vector3.new(7, 9, 1), CFrame = cf * CFrame.new(0, 4.5, -0.5), Color = Color3.fromRGB(60, 64, 66) })
			part({ Name = "Ring", Size = Vector3.new(5, 7, 0.3), CFrame = cf * CFrame.new(0, 4.2, -1.1),
				Color = kind == "entry" and Color3.fromRGB(70, 170, 220) or Color3.fromRGB(240, 140, 50), Material = Enum.Material.Neon })
			front = -1.25
		elseif kind == "button" then
			part({ Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 7, 7),
				CFrame = cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(70, 75, 80) })
			part({ Name = "Pad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 5.6, 5.6),
				CFrame = cf * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(205, 60, 70) })
		elseif kind == "gate" then
			-- a little panel: rim colour = gate type, the light shows its output in game
			local mode = C.GateMode(e)
			part({ Name = "Body", Size = Vector3.new(4.6, 4.6, 0.5), CFrame = cf * CFrame.new(0, 0, -0.25), Color = Color3.fromRGB(46, 50, 52) })
			part({ Name = "Rim", Size = Vector3.new(3.8, 3.8, 0.1), CFrame = cf * CFrame.new(0, 0, -0.53), Color = C.GATE_COLORS[mode] })
			part({ Name = "Light", Size = Vector3.new(2.4, 2.4, 0.1), CFrame = cf * CFrame.new(0, 0, -0.6),
				Color = opts.editor and C.GATE_COLORS[mode]:Lerp(Color3.new(1, 1, 1), 0.35) or C.ANT_OFF, Material = Enum.Material.Neon })
			front = -0.65
		elseif kind == "lasercatcher" then
			part({ Name = "Body", Size = Vector3.new(6, 6, 1.2), CFrame = cf * CFrame.new(0, 0, -0.6), Color = Color3.fromRGB(70, 76, 80) })
			part({ Name = "Lens", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3.6, 3.6),
				CFrame = cf * CFrame.new(0, 0, -1.25) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(110, 30, 30), Material = Enum.Material.Neon })
			front = -1.4
		elseif def.mount == "any" and not def.upright then
			part({ Name = "Body", Size = Vector3.new(4, 4, 2), CFrame = cf * CFrame.new(0, 0, -1), Color = Color3.fromRGB(120, 130, 140) })
			front = -2
		else
			part({ Name = "Body", Size = Vector3.new(4, 4, 4), CFrame = cf * CFrame.new(0, 2, 0), Color = Color3.fromRGB(120, 130, 140) })
		end
	end

	-- doors: the wall tile becomes an alcove (back, sides, floor, top) and the door sits at the back of it
	local R = def.recess or 0
	local CELL = C.CELL
	local function shellWall(name, offset, size)
		local p = panelPart(false, 1)
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cf * CFrame.new(offset)
		p:SetAttribute("Portalable", false)
		p.Parent = m
	end
	if R > 0 then
		shellWall("AlcoveBack", Vector3.new(0, CELL / 2, R + 0.5), Vector3.new(CELL, CELL, 1))
		shellWall("AlcoveLeft", Vector3.new(-(CELL / 2 + 0.5), CELL / 2, R / 2), Vector3.new(1, CELL, R))
		shellWall("AlcoveRight", Vector3.new(CELL / 2 + 0.5, CELL / 2, R / 2), Vector3.new(1, CELL, R))
		shellWall("AlcoveFloor", Vector3.new(0, -0.5, R / 2), Vector3.new(CELL + 2, 1, R))
		shellWall("AlcoveTop", Vector3.new(0, CELL + 0.5, R / 2), Vector3.new(CELL + 2, 1, R))
	end

	-- flush items (faith plates): the floor tile becomes a pit as deep as the model, the model's top is level with
	-- the floor (cf here is the floor frame: Y = up out of the floor)
	if def.flush and template and R == 0 then
		local D = math.max(height or 1, 0.6) + 0.05
		shellWall("PitFloor", Vector3.new(0, -D - 0.5, 0), Vector3.new(CELL, 1, CELL))
		shellWall("PitSideA", Vector3.new(0, -D / 2, CELL / 2 + 0.5), Vector3.new(CELL + 2, D, 1))
		shellWall("PitSideB", Vector3.new(0, -D / 2, -(CELL / 2 + 0.5)), Vector3.new(CELL + 2, D, 1))
		shellWall("PitSideC", Vector3.new(CELL / 2 + 0.5, -D / 2, 0), Vector3.new(1, D, CELL))
		shellWall("PitSideD", Vector3.new(-(CELL / 2 + 0.5), -D / 2, 0), Vector3.new(1, D, CELL))
	end

	if kind == "entry" or kind == "exit" then
		m:AddTag("PortalChamberDoor")
		m:SetAttribute("DoorType", kind)
		m:SetAttribute("Open", false)
		-- exit: locked until a connection / chip opens it, or it's set to open without a button
		if kind == "exit" then m:SetAttribute("Enabled", o.free == true) end
		if kind == "exit" then removeNamed(m, "PlayerSpawn") end
		-- Start / End markers inside the door model: the entry only keeps Start, the exit only End
		local mine = C.DOOR_MARKERS[kind]
		local other = C.DOOR_MARKERS[kind == "entry" and "exit" or "entry"]
		local _, otherHolder = markerInside(m, other)
		if otherHolder then otherHolder:Destroy() end
		local marker, holder = markerInside(m, mine)
		if opts.editor then
			-- the editor doesn't need the helper parts (they'd get in the way of clicking)
			if holder then holder:Destroy() end
		else
			local roomZ = math.min(front, R - 0.5) -- just in front of the door, in the room
			local function fromLibrary()
				local t = C.MarkerTemplate(mine)
				if not t then return nil end
				local p = t:Clone()
				p.Anchored = true
				-- lying in front of the door, turned the way the part is turned in Studio
				local depth = math.max(p.Size.Z, p.Size.X)
				p.CFrame = cf * CFrame.new(0, p.Size.Y / 2 + 0.05, roomZ - depth / 2 - (kind == "entry" and 1.5 or 0.5)) * t.CFrame.Rotation
				p.Parent = m
				return p
			end
			if kind == "entry" then
				if not m:FindFirstChild("PlayerSpawn", true) then
					local spawn = marker or fromLibrary()
					if spawn then
						spawn.Name = "PlayerSpawn"
						spawn.Anchored = true
					else
						spawn = Instance.new("Part")
						spawn.Name = "PlayerSpawn"
						spawn.Size = Vector3.new(4, 0.4, 4)
						spawn.CFrame = cf * CFrame.new(0, 0.2, roomZ - 3.5)
						spawn.Transparency = 1
						spawn.CanCollide = false
						spawn.CanQuery = false
						spawn.CanTouch = false
						spawn.Parent = m
					end
					spawn:SetAttribute("Facing", cf.LookVector) -- spawn looking into the room
				end
			else
				local trig = marker or m:FindFirstChild("Exit", true)
				if not (trig and trig:IsA("BasePart")) then trig = fromLibrary() end
				if not trig then
					trig = Instance.new("Part")
					trig.Name = "Exit"
					-- a generous box right in front of the door (it only counts once the door is unlocked)
					trig.Size = Vector3.new(8, 9, 6)
					trig.CFrame = cf * CFrame.new(0, 4.5, roomZ - 1.5)
					trig.Transparency = 1
					trig.CanCollide = false
					trig.Parent = m
				end
				trig.Name = "Exit"
				trig.Anchored = true
				trig.CanQuery = true
				trig:AddTag("PortalChamberExit")
			end
		end
	elseif kind == "button" then
		local pad = m:FindFirstChild("Pad", true) or element
		pad:AddTag("PortalButton")
		m:AddTag("PeTIFloorButton") -- PortalServer presses it when a player / cube stands on it
	elseif kind == "cube" then
		m:SetAttribute("CubeType", e[7] or nil)
		m:AddTag("PortalCube")
	elseif kind == "cubedropper" then
		element:AddTag("CubeDropper")
	elseif kind == "laser" then
		element:AddTag("LaserEmitter")
	elseif kind == "lasercatcher" then
		element:AddTag("LaserCatcher")
		m:AddTag("PeTIMirror") -- PortalServer copies its "Pressed" up to the item
	elseif kind == "laserfield" then
		element:AddTag("LaserField")
	elseif kind == "fizzler" then
		element:AddTag("Fizzler")
	elseif kind == "lightbridge" then
		element:AddTag("LightBridge")
	elseif kind == "tbeam" then
		element:AddTag("Funnel")
	elseif kind == "pedestal" then
		element:AddTag("PedestalButton")
		m:AddTag("PeTIMirror") -- PedestalButtonServer presses it, PortalServer copies "Pressed" up to the item
	elseif kind == "turret" then
		element:AddTag("Turret")
	elseif kind == "gate" then
		m:AddTag("PeTIGate")
	end

	-- item options (set from the editor's right-click menu)
	if kind == "tbeam" then
		m:SetAttribute("BaseReversed", o.mode == "Reversed")
		C.SetAll(m, "Reversed", o.mode == "Reversed")
	elseif kind == "cubedropper" then
		C.SetAll(m, "CubeType", type(o.mode) == "string" and o.mode or "Normal")
		C.SetAll(m, "DropOnStart", o.dropOnStart ~= false)
	elseif kind == "faithplate" then
		-- FaithPlateServer reads these off the FaithPlate model
		local path = C.FaithPath(e, origin, opts.air)
		element:SetAttribute("StraightUp", path.up == true)
		if path.up then
			element:SetAttribute("UpHeight", path.height)
			element:SetAttribute("AimPoint", nil)
			element:SetAttribute("ApexY", nil)
		else
			element:SetAttribute("AimPoint", path.aim)
			element:SetAttribute("ApexY", path.apexY)
		end
	end
	if kind == "button" then
		m:SetAttribute("ButtonType", type(o.mode) == "string" and o.mode or "Weighted")
	elseif kind == "pedestal" then
		-- PedestalButtonServer's three mode checkboxes (only one on) + the timer length
		local mode = C.PedestalMode(e)
		for _, md in ipairs(C.PEDESTAL_MODES) do element:SetAttribute(md, md == mode) end
		element:SetAttribute("TimerLength", tonumber(o.timer) or C.PEDESTAL_TIMER)
	elseif kind == "gate" then
		m:SetAttribute("GateMode", C.GateMode(e))
		m:SetAttribute("Pressed", false)
	end
	if C.SWITCHABLE[kind] then
		if type(o.startOn) == "boolean" then m:SetAttribute("StartOpt", o.startOn) end
		if kind ~= "exit" then C.SetAll(m, "Enabled", C.StartOn(e, false)) end
	end
	-- the fallback laser sheet follows the field's on / off state
	if kind == "laserfield" and not opts.editor then
		local fb = m:FindFirstChild("FieldFallback", true)
		if fb then
			local function upd() fb.Transparency = (element:GetAttribute("Enabled") == false) and 1 or 0.7 end
			element:GetAttributeChangedSignal("Enabled"):Connect(upd)
			upd()
		end
	end

	if type(e[8]) == "string" then m:SetAttribute("EntId", e[8]) end

	-- parts hanging off a joint (turret arms, button caps, anything rigged) keep the anchoring they have in
	-- PortalAssets so the item's own animations / scripts can still move them. Everything else is anchored.
	local jointed = {}
	if not opts.editor then
		for _, j in ipairs(m:GetDescendants()) do
			if (j:IsA("JointInstance") or j:IsA("WeldConstraint")) and j.Part0 and j.Part1 and j.Part1:IsDescendantOf(m) then
				jointed[j.Part1] = true
			end
		end
	end
	eachPart(m, function(p)
		if opts.editor then
			p.Anchored, p.CanCollide = true, false
		elseif kind == "cube" then
			p.Anchored = false
		elseif not jointed[p] then
			p.Anchored = true
		end
	end)

	-- hidden logic gates: still work, you just can't see them in game
	if kind == "gate" and not opts.editor and o.hide == true then
		eachPart(m, function(p)
			p.Transparency, p.CanCollide, p.CanQuery, p.CanTouch = 1, false, false, false
		end)
		m:SetAttribute("Hidden", true)
	end
	return m
end

-- can neighbouring tiles of this panel be one big part without the look changing? (Textures that repeat every tile:
-- yes. Decals stretch over the whole part: no)
local function mergeable(p)
	for _, d in ipairs(p:GetChildren()) do
		if d:IsA("Decal") and not d:IsA("Texture") then return false end
		if d:IsA("Texture") then
			for _, s in ipairs({ d.StudsPerTileU, d.StudsPerTileV }) do
				if s <= 0 or math.abs(C.CELL / s - math.floor(C.CELL / s + 0.5)) > 0.01 then return false end
			end
		end
	end
	return true
end

function C.BuildChamber(data, parent, origin, opts)
	opts = opts or {}
	local cell = C.CELL
	local model = Instance.new("Model")
	model.Name = "Chamber"
	local air = {}
	for _, c in ipairs(data.air or {}) do air[C.Key(c[1], c[2], c[3])] = true end
	local faces = data.faces or {}
	local colors = type(data.colors) == "table" and data.colors or {}
	local textures = type(data.textures) == "table" and data.textures or {}
	local holes = C.HoleFaces(data.ents)
	opts.air = air -- span items reach to the far wall, faith plates check their target
	local merge = C.MERGE_PANELS and not opts.editor and opts.merge ~= false

	local function makePanel(fk, f, portalable, wallTiles)
		local p = panelPart(portalable, f, wallTiles and "wall" or nil)
		p.Anchored = true
		p.Name = "Panel"
		local tex = textures[fk]
		if tex and C.ValidTextureValue(tex) then
			-- rotated into place below; the side facing the room gets the texture
			p:SetAttribute("CustomTexture", tex)
		end
		return p
	end
	local function finish(p, fk, f, portalable)
		local tex = p:GetAttribute("CustomTexture")
		if tex then C.ApplyTexture(p, tex, -C.DIRS[f]) end
		local tint = C.TileTint(tonumber(colors[fk]), portalable)
		if tint then C.TintPanel(p, tint) end
		p:SetAttribute("Portalable", portalable)
		p:SetAttribute("Face", fk)
		p.Parent = model
	end

	local count = 0
	local planes, sigOk = {}, {} -- merge groups: [plane] = { cells = { [u..","..v] = face }, list = { face } }
	for _, c in ipairs(data.air or {}) do
		for f = 1, 6 do
			local o = C.OFFS[f]
			if not air[C.Key(c[1] + o[1], c[2] + o[2], c[3] + o[3])] then
				local normal = -C.DIRS[f]
				if not holes[C.FaceKey(c[1], c[2], c[3], f)] and not (opts.cullToward and normal:Dot(opts.cullToward) <= 0.01) then
					count += 1
					if opts.maxFaces and count > opts.maxFaces then break end
					local fk = C.FaceKey(c[1], c[2], c[3], f)
					local portalable, wallTiles = C.FaceInfo(faces[fk])
					if opts.editor then
						local p = makePanel(fk, f, portalable, wallTiles)
						p.Size = Vector3.new(cell - 0.35, cell - 0.35, 0.3)
						p.CFrame = C.FaceCFrame(origin, c[1], c[2], c[3], f, 0.15)
						local rim = Instance.new("Part")
						rim.Anchored, rim.Size = true, Vector3.new(cell + 0.6, cell + 0.6, 2.4)
						rim.CFrame = C.FaceCFrame(origin, c[1], c[2], c[3], f, 1.5)
						rim.Color = portalable and Color3.fromRGB(198, 201, 198) or Color3.fromRGB(96, 104, 101)
						rim.Parent = model
						finish(p, fk, f, portalable)
					else
						local sig = table.concat({ f, tostring(portalable), tostring(wallTiles), tostring(colors[fk]), tostring(textures[fk]) }, "|")
						local ok = merge
						if ok and sigOk[sig] == nil then
							local sample = makePanel(fk, f, portalable, wallTiles)
							local tex = sample:GetAttribute("CustomTexture")
							if tex then C.ApplyTexture(sample, tex, -C.DIRS[f]) end
							sigOk[sig] = mergeable(sample)
							sample:Destroy()
						end
						ok = ok and sigOk[sig]
						local fcf = C.FaceCFrame(origin, c[1], c[2], c[3], f, 0.5)
						if ok then
							local cv = Vector3.new(c[1], c[2], c[3])
							local u = math.round(cv:Dot(fcf.RightVector))
							local v = math.round(cv:Dot(fcf.UpVector))
							local w = math.round(cv:Dot(C.DIRS[f]))
							local pk = sig .. "|" .. w
							local pl = planes[pk]
							if not pl then
								pl = { cells = {}, list = {}, f = f, portalable = portalable, wallTiles = wallTiles }
								planes[pk] = pl
							end
							local face = { u = u, v = v, fk = fk, cf = fcf }
							pl.cells[u .. "," .. v] = face
							table.insert(pl.list, face)
						else
							local p = makePanel(fk, f, portalable, wallTiles)
							C.PlacePanel(p, fcf, cell, 1)
							finish(p, fk, f, portalable)
						end
					end
				end
			end
		end
	end

	-- merged walls: greedy rectangles over each plane (max 16 x 16 tiles per part)
	local MAXN = 16
	for _, pl in pairs(planes) do
		table.sort(pl.list, function(a, b) return a.v < b.v or (a.v == b.v and a.u < b.u) end)
		local used = {}
		for _, a in ipairs(pl.list) do
			if not used[a] then
				local wn = 1
				while wn < MAXN do
					local nb = pl.cells[(a.u + wn) .. "," .. a.v]
					if not nb or used[nb] then break end
					wn += 1
				end
				local hn = 1
				while hn < MAXN do
					local rowOk = true
					for du = 0, wn - 1 do
						local nb = pl.cells[(a.u + du) .. "," .. (a.v + hn)]
						if not nb or used[nb] then rowOk = false break end
					end
					if not rowOk then break end
					hn += 1
				end
				for du = 0, wn - 1 do
					for dv = 0, hn - 1 do used[pl.cells[(a.u + du) .. "," .. (a.v + dv)]] = true end
				end
				local far = pl.cells[(a.u + wn - 1) .. "," .. (a.v + hn - 1)]
				local center = (a.cf.Position + far.cf.Position) / 2
				local p = makePanel(a.fk, pl.f, pl.portalable, pl.wallTiles)
				C.PlacePanel(p, CFrame.new(center) * a.cf.Rotation, wn * cell, 1, hn * cell)
				if wn * hn > 1 then p:SetAttribute("Tiles", wn * hn) end
				finish(p, a.fk, pl.f, pl.portalable)
			end
		end
	end

	for i, e in ipairs(data.ents or {}) do
		local ok, ent = pcall(C.BuildEntity, e, origin, opts)
		if ok and ent then
			eachPart(ent, function(p) p:SetAttribute("EntIndex", i) end)
			ent.Parent = model
		elseif not ok then
			warn("[PortalConfig] BuildEntity", e[1], ent)
		end
	end
	model.Parent = parent
	return model
end

-- ==========================================
-- ANTLINES (connection lines along the chamber surfaces)
-- ==========================================
-- Shortest path over the panels from one item's tile to another's (walking across tiles, round inside corners and
-- over outside edges). Returns a list of { a = Vector3, b = Vector3, n = normal } segments, panel centre to tile edge to
-- panel centre, ready to be dotted. lift = how far off the surface.
local function faceExists(air, x, y, z, f)
	local o = C.OFFS[f]
	return air[C.Key(x, y, z)] and not air[C.Key(x + o[1], y + o[2], z + o[3])]
end
local function faceIndex(v)
	for i, d in ipairs(C.DIRS) do
		if d:Dot(v) > 0.9 then return i end
	end
end
function C.AntlinePath(air, a, b, origin, lift)
	lift = lift or 0.15
	if not (faceExists(air, a[1], a[2], a[3], a[4]) and faceExists(air, b[1], b[2], b[3], b[4])) then return nil end
	local function fkey(x, y, z, f) return x .. "," .. y .. "," .. z .. "," .. f end
	local startK, goalK = fkey(a[1], a[2], a[3], a[4]), fkey(b[1], b[2], b[3], b[4])
	local prev, nodes = { [startK] = false }, { [startK] = a }
	local queue, head = { a }, 1
	local found = startK == goalK
	while head <= #queue and not found do
		local cur = queue[head]
		head += 1
		local x, y, z, f = cur[1], cur[2], cur[3], cur[4]
		local d = C.DIRS[f]
		for tf = 1, 6 do
			local t = C.DIRS[tf]
			if math.abs(t:Dot(d)) < 0.5 then
				local o = C.OFFS[tf]
				local nx, ny, nz = x + o[1], y + o[2], z + o[3]
				local nb
				if not air[C.Key(nx, ny, nz)] then
					nb = { x, y, z, tf } -- inside corner: the wall we walked into
				elseif faceExists(air, nx, ny, nz, f) then
					nb = { nx, ny, nz, f } -- same plane
				else
					local fo = C.OFFS[f]
					local wrap = faceIndex(-t)
					nb = { nx + fo[1], ny + fo[2], nz + fo[3], wrap } -- over an outside edge
					if not faceExists(air, nb[1], nb[2], nb[3], nb[4]) then nb = nil end
				end
				if nb then
					local k = fkey(nb[1], nb[2], nb[3], nb[4])
					if prev[k] == nil then
						prev[k] = { from = fkey(x, y, z, f), t = t }
						nodes[k] = nb
						if k == goalK then found = true break end
						table.insert(queue, nb)
					end
				end
			end
		end
		if #queue > 12000 then break end
	end
	if not found then return nil end
	-- walk back
	local chain = {}
	local k = goalK
	while k do
		table.insert(chain, 1, { node = nodes[k], step = prev[k] })
		k = prev[k] and prev[k].from or nil
	end
	local function center(n)
		return origin + Vector3.new(n[1], n[2], n[3]) * C.CELL + C.DIRS[n[4]] * (C.CELL / 2)
	end
	local segs = {}
	for i = 1, #chain - 1 do
		local n1, n2 = chain[i].node, chain[i + 1].node
		local t = chain[i + 1].step.t
		local c1, c2 = center(n1), center(n2)
		local nrm1, nrm2 = -C.DIRS[n1[4]], -C.DIRS[n2[4]]
		local edge = c1 + t * (C.CELL / 2)
		table.insert(segs, { a = c1 + nrm1 * lift, b = edge + nrm1 * lift, n = nrm1 })
		table.insert(segs, { a = edge + nrm2 * lift, b = c2 + nrm2 * lift, n = nrm2 })
	end
	-- join straight runs
	local out = {}
	for _, sg in ipairs(segs) do
		local last = out[#out]
		if last and last.n:Dot(sg.n) > 0.99 and (last.b - sg.a).Magnitude < 0.05
			and (last.b - last.a).Unit:Dot((sg.b - sg.a).Unit) > 0.99 then
			last.b = sg.b
		elseif (sg.b - sg.a).Magnitude > 0.01 then
			table.insert(out, sg)
		end
	end
	return out
end

-- dots along the path: { cf, corner } (corner / ends get the hollow ring look)
C.ANTLINE_SPACING = 1.25
function C.AntlineDots(segs)
	local dots = {}
	for i, sg in ipairs(segs) do
		local len = (sg.b - sg.a).Magnitude
		local dir = (sg.b - sg.a) / math.max(len, 1e-4)
		local n = math.max(math.floor(len / C.ANTLINE_SPACING + 0.5), 1)
		for k = (i == 1) and 0 or 1, n do
			local p = sg.a + dir * (len * k / n)
			local corner = (i == 1 and k == 0) or k == n
			table.insert(dots, { cf = CFrame.lookAt(p, p + sg.n), corner = corner })
		end
	end
	return dots
end

-- one antline dot (a flat disc lying on the surface)
function C.AntlineDot(cf, corner, color, parent)
	local p = Instance.new("Part")
	p.Name = "AntDot"
	p.Shape = Enum.PartType.Cylinder
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	local d = corner and 0.75 or 0.5
	p.Size = Vector3.new(0.04, d, d)
	p.CFrame = cf * CFrame.Angles(0, math.rad(90), 0) -- cylinder axis (X) along the surface normal
	p.Parent = parent
	if corner then -- hollow ring: a darker disc on top
		local hole = p:Clone()
		hole.Name = "AntDotHole"
		hole.Material = Enum.Material.SmoothPlastic
		hole.Color = Color3.fromRGB(235, 240, 238)
		hole.Size = Vector3.new(0.05, d * 0.55, d * 0.55)
		hole.CFrame = cf * CFrame.new(0, 0, -0.01) * CFrame.Angles(0, math.rad(90), 0)
		hole.Parent = parent
		return p, hole
	end
	return p
end

-- signage: a small square sign on the item's tile (frame = C.ItemFrame), the inner square shows the state
function C.BuildSign(frame, parent)
	local m = Instance.new("Model")
	m.Name = "ConnectionSign"
	local cf = frame * CFrame.new(C.CELL * 0.3, C.CELL * 0.3, -0.12)
	local function plate(name, size, color, z)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.SmoothPlastic
		p.Size = Vector3.new(size, size, 0.06)
		p.Color = color
		p.CFrame = cf * CFrame.new(0, 0, z)
		p.Parent = m
		return p
	end
	plate("Plate", 1.8, Color3.fromRGB(240, 242, 240), 0)
	plate("Frame", 1.2, Color3.fromRGB(30, 32, 32), -0.02)
	plate("Light", 0.75, C.ANT_OFF, -0.04).Material = Enum.Material.Neon
	m.Parent = parent
	return m
end
C.ANT_OFF = Color3.fromRGB(80, 200, 220)  -- antline / sign off (Portal 2 blue)
C.ANT_ON = Color3.fromRGB(255, 160, 40)   -- on (orange)

-- ==========================================
-- FAITH PLATES
-- ==========================================
-- e[10]: fx, fy, fz, ff = the panel it throws you at (none = straight up)
--        arc = studs the arc rises above the higher end (straight up: how high it throws you)
C.FAITH_ARC = 20
C.FAITH_LANDING = 3 -- studs off the target panel that the player's middle is aimed at

function C.FaithTarget(e, air)
	local o = C.Options(e)
	local x, y, z, f = tonumber(o.fx), tonumber(o.fy), tonumber(o.fz), tonumber(o.ff)
	if not (x and y and z and f and C.OFFS[f]) then return nil end
	if air then
		local off = C.OFFS[f]
		if not air[C.Key(x, y, z)] or air[C.Key(x + off[1], y + off[2], z + off[3])] then return nil end -- panel's gone
	end
	return x, y, z, f
end

function C.FaithPath(e, origin, air)
	local arc = tonumber(C.Options(e).arc) or C.FAITH_ARC
	local p0 = origin + Vector3.new(e[2], e[3], e[4]) * C.CELL + C.DIRS[e[5]] * (C.CELL / 2) + Vector3.new(0, 1, 0)
	local x, y, z, f = C.FaithTarget(e, air)
	if not x then
		return { up = true, p0 = p0, height = arc, apex = p0 + Vector3.new(0, arc, 0) }
	end
	local d = C.DIRS[f]
	local surface = origin + Vector3.new(x, y, z) * C.CELL + d * (C.CELL / 2)
	local aim = surface - d * C.FAITH_LANDING
	return { p0 = p0, surface = surface, aim = aim, normal = -d, f = f, arc = arc, apexY = math.max(p0.Y, aim.Y) + arc }
end

-- launch velocity from p0 that peaks at apexY and comes down through p1. Also returns flight time / time to the top.
function C.Ballistic(p0, p1, apexY, g)
	g = g or workspace.Gravity
	apexY = math.max(apexY, p0.Y + 0.5, p1.Y + 0.5)
	local vy = math.sqrt(2 * g * (apexY - p0.Y))
	local tUp = vy / g
	local t = tUp + math.sqrt(2 * (apexY - p1.Y) / g)
	return Vector3.new((p1.X - p0.X) / t, vy, (p1.Z - p0.Z) / t), t, tUp
end

-- points along the arc (for the editor's dashed line) and the top of it (the yellow ball)
function C.FaithPoints(path, n, g)
	if path.up then return { path.p0, path.apex }, path.apex end
	g = g or workspace.Gravity
	local v, t, tUp = C.Ballistic(path.p0, path.aim, path.apexY, g)
	local pts = {}
	for i = 0, n do
		local s = t * i / n
		table.insert(pts, path.p0 + v * s - Vector3.new(0, 0.5 * g * s * s, 0))
	end
	table.insert(pts, path.surface)
	local apex = path.p0 + v * tUp - Vector3.new(0, 0.5 * g * tUp * tUp, 0)
	return pts, apex
end

-- ==========================================
-- ITEM LABELS (chips talk about items by label: button1, exit, gate2 ...) - stored in e[10].label
-- ==========================================
C.LABEL_PREFIX = { entry = "entry", exit = "exit", button = "button", pedestal = "pedestal", gate = "gate",
	cubedropper = "dropper", laser = "laser", lasercatcher = "catcher", laserfield = "field", fizzler = "fizzler",
	lightbridge = "bridge", tbeam = "funnel", faithplate = "plate", turret = "turret", prop = "mesh" }
function C.ValidLabel(l)
	return type(l) == "string" and #l >= 1 and #l <= 20 and l:match("^%a[%w_]*$") ~= nil
end
function C.LabelOf(e)
	local l = C.Options(e).label
	return C.ValidLabel(l) and l or nil
end
-- gives every labellable item without a label one (entry / exit get "entry" / "exit"). Returns true if it changed any.
function C.AutoLabel(ents)
	local used, changed = {}, false
	for _, e in ipairs(ents) do
		local l = C.LabelOf(e)
		if l then used[l:lower()] = true end
	end
	for _, e in ipairs(ents) do
		local prefix = C.LABEL_PREFIX[e[1]]
		if prefix and not C.LabelOf(e) then
			local name
			if (e[1] == "entry" or e[1] == "exit") and not used[prefix] then
				name = prefix
			else
				local n = 1
				while used[(prefix .. n):lower()] do n += 1 end
				name = prefix .. n
			end
			used[name:lower()] = true
			local o = table.clone(C.Options(e))
			o.label = name
			e[10] = o
			changed = true
		end
	end
	return changed
end

-- ==========================================
-- CHIPS (Advanced editor, "My Chips" tab): tiny programs that run in the built chamber
-- ==========================================
-- Written either with blocks or as lines. Both are the same program:
--   when button1 pressed        when <item> pressed / released   (buttons, pedestals, laser catchers, gates)
--     add presses 1             when start                       (the chamber was just built / you spawned)
--     if presses >= 3 then open exit                             when every <seconds>
--     say "Pressed {presses} times"
--   when button1 released
--     wait 2
--     close exit
-- Actions: open / close / enable / disable / toggle <item>, drop <dropper>, reverse <funnel>, wait <seconds>,
--          say <text> ({name} shows a variable), set <variable> <value>, add <variable> <number>,
--          if <variable | item> <== != < > <= >=> <value> then <action>
-- Variables are shared by every chip in the chamber and start at 0. An item in an "if" counts as 1 when it's
-- pressed / on / open, else 0. Lines starting with -- or # are comments.
C.CHIP_EVENTS = { "pressed", "released", "start", "every" }
C.CHIP_EVENT_LABELS = { pressed = "is pressed", released = "is released", start = "chamber starts", every = "every ... seconds" }
C.CHIP_ACTIONS = { "open", "close", "toggle", "enable", "disable", "drop", "reverse", "wait", "say", "set", "add", "if" }
C.CHIP_ACTION_LABELS = {
	open = "open", close = "close", toggle = "toggle", enable = "turn on", disable = "turn off",
	drop = "drop a cube from", reverse = "reverse", wait = "wait (seconds)", say = "show message",
	set = "set variable", add = "add to variable", ["if"] = "if ... then",
}
C.CHIP_COMPARE = { "==", "!=", "<", ">", "<=", ">=" }
-- what each line expects (the editor shows it while you type, like a code editor's parameter hints)
C.CHIP_HINTS = {
	when = "when <item> pressed | released   ·   when start   ·   when every <seconds>",
	open = "open <item>   opens a door / turns an item on",
	close = "close <item>   closes a door / turns an item off",
	toggle = "toggle <item>   flips it on / off",
	enable = "enable <item>   turns an item on",
	disable = "disable <item>   turns an item off",
	drop = "drop <dropper>   drops a new cube",
	reverse = "reverse <funnel>   flips an excursion funnel's direction",
	wait = "wait <seconds>   pauses this rule",
	say = "say <text>   shows a message ({name} = a variable's value)",
	set = "set <variable> <number | true | false | variable>",
	add = "add <variable> <number>   (a negative number takes away)",
	["if"] = "if <variable | item> <== != < > <= >=> <value> then <action>",
}
local CHIP_TARGET = { open = true, close = true, toggle = true, enable = true, disable = true, drop = true, reverse = true }
C.CHIP_TARGET = CHIP_TARGET
local CHIP_KEYWORDS = { ["when"] = true, ["then"] = true, ["true"] = true, ["false"] = true, start = true, every = true, pressed = true, released = true }
for _, a in ipairs(C.CHIP_ACTIONS) do CHIP_KEYWORDS[a] = true end
function C.ValidVarName(n)
	return type(n) == "string" and #n <= 24 and n:match("^[%a_][%w_]*$") ~= nil and not CHIP_KEYWORDS[n:lower()]
end
-- which items an event / action can use
function C.ChipSourceOk(kind) return C.LINK_SOURCES[kind] == true end
function C.ChipTargetOk(op, kind)
	if op == "drop" then return kind == "cubedropper" end
	if op == "reverse" then return kind == "tbeam" end
	if CHIP_TARGET[op] then return C.SWITCHABLE[kind] == true end
	return false
end
local COMPARE = {}
for _, c in ipairs(C.CHIP_COMPARE) do COMPARE[c] = true end

-- one action from its words. Returns the action, or nil and an error.
local function parseAction(word, rest, allowIf)
	if word == "wait" then
		local n = tonumber(rest)
		if not n then return nil, "'wait' needs a number of seconds" end
		return { op = "wait", n = math.clamp(n, 0, 60) }
	elseif word == "say" then
		local msg = rest:match('^"(.*)"$') or rest
		return { op = "say", text = msg:sub(1, 120) }
	elseif word == "set" or word == "add" then
		local var, value = rest:match("^(%S+)%s*(%S*)")
		if not C.ValidVarName(var) then return nil, ("'%s' needs a variable name (letters, numbers, _), like '%s score 1'"):format(word, word) end
		if word == "add" and not tonumber(value) then return nil, "'add' needs a number, like 'add score 1'" end
		if word == "set" and value == "" then return nil, "'set' needs a value, like 'set score 0'" end
		return { op = word, var = var, value = value }
	elseif word == "if" then
		if not allowIf then return nil, "an 'if' can't have another 'if' after its 'then'" end
		local lhs, cmp, rhs, inner = rest:match("^(%S+)%s+(%S+)%s+(%S+)%s+[Tt][Hh][Ee][Nn]%s+(.+)$")
		if not lhs then return nil, "write it like 'if score >= 3 then open exit'" end
		if cmp == "~=" then cmp = "!=" elseif cmp == "=" then cmp = "==" end
		if not COMPARE[cmp] then return nil, ("'%s' isn't a comparison: use == != < > <= >="):format(cmp) end
		local w2, r2 = inner:match("^(%S+)%s*(.*)$")
		local act, err = parseAction(w2:lower(), r2, false)
		if not act then return nil, err end
		return { op = "if", lhs = lhs, cmp = cmp, rhs = rhs, act = act }
	elseif CHIP_TARGET[word] then
		local target = rest:match("^(%S+)")
		if not target then return nil, ("'%s' needs an item, like '%s exit'"):format(word, word) end
		return { op = word, target = target }
	end
	return nil, ("I don't know '%s'"):format(word)
end

-- text -> { { ev, src, n, acts = { { op, target, n, text, var, value, lhs, cmp, rhs, act } } } }, errors (list of strings)
function C.ParseChip(src)
	local rules, errs = {}, {}
	if type(src) ~= "string" then return rules, { "No program." } end
	local cur
	local ln = 0
	for line in (src .. "\n"):gmatch("(.-)\r?\n") do
		ln += 1
		local t = line:gsub("^%s+", ""):gsub("%s+$", "")
		if t ~= "" and not t:match("^%-%-") and not t:match("^#") then
			local word, rest = t:match("^(%S+)%s*(.*)$")
			word = word:lower()
			if word == "when" then
				local a, b = rest:match("^(%S+)%s*(%S*)")
				a = a and a:lower()
				if a == "start" then
					cur = { ev = "start", acts = {} }
				elseif a == "every" then
					local n = tonumber(b)
					if not n then table.insert(errs, ("line %d: 'when every' needs a number of seconds"):format(ln)) n = 1 end
					cur = { ev = "every", n = math.clamp(n, 0.5, 600), acts = {} }
				elseif a and (b:lower() == "pressed" or b:lower() == "released") then
					cur = { ev = b:lower(), src = rest:match("^(%S+)"), acts = {} }
				else
					table.insert(errs, ("line %d: write 'when <item> pressed', 'when <item> released', 'when start' or 'when every <seconds>'"):format(ln))
					cur = nil
				end
				if cur then table.insert(rules, cur) end
			elseif not table.find(C.CHIP_ACTIONS, word) then
				table.insert(errs, ("line %d: I don't know '%s'"):format(ln, word))
			elseif not cur then
				table.insert(errs, ("line %d: '%s' has to come after a 'when' line"):format(ln, word))
			else
				local act, err = parseAction(word, rest, true)
				if act then table.insert(cur.acts, act) else table.insert(errs, ("line %d: %s"):format(ln, err)) end
			end
		end
	end
	return rules, errs
end

local function actionText(a)
	if a.op == "wait" then return "wait " .. tostring(a.n or 1) end
	if a.op == "say" then return ('say "%s"'):format((a.text or ""):gsub('"', "'")) end
	if a.op == "set" or a.op == "add" then return ("%s %s %s"):format(a.op, a.var or "?", tostring(a.value or "0")) end
	if a.op == "if" then
		return ("if %s %s %s then %s"):format(a.lhs or "?", a.cmp or "==", a.rhs or "0", a.act and actionText(a.act) or "?")
	end
	return ("%s %s"):format(a.op, a.target or "?")
end
C.ChipActionText = actionText

-- rules -> text
function C.ChipText(rules)
	local out = {}
	for _, r in ipairs(rules or {}) do
		if r.ev == "start" then table.insert(out, "when start")
		elseif r.ev == "every" then table.insert(out, "when every " .. tostring(r.n or 1))
		else table.insert(out, ("when %s %s"):format(r.src or "?", r.ev or "pressed")) end
		for _, a in ipairs(r.acts or {}) do table.insert(out, "    " .. actionText(a)) end
	end
	return table.concat(out, "\n")
end

-- every action, including the one inside an "if"
local function eachAction(rules, fn)
	for _, r in ipairs(rules) do
		for _, a in ipairs(r.acts) do
			fn(a)
			if a.op == "if" and a.act then fn(a.act) end
		end
	end
end
C.ChipEachAction = eachAction

-- the variables a program uses (set / add)
function C.ChipVariables(rules)
	local vars, list = {}, {}
	eachAction(rules, function(a)
		if (a.op == "set" or a.op == "add") and a.var and not vars[a.var:lower()] then
			vars[a.var:lower()] = true
			table.insert(list, a.var)
		end
	end)
	return list
end

-- checks the item names against a chamber's items. kinds = { [label:lower()] = kind }
function C.CheckChip(rules, kinds)
	local errs = {}
	for _, r in ipairs(rules) do
		if r.src then
			local k = kinds[r.src:lower()]
			if not k then table.insert(errs, ("There's no item called '%s'."):format(r.src))
			elseif not C.ChipSourceOk(k) then table.insert(errs, ("'%s' can't be pressed (use a button, pedestal, laser catcher or gate)."):format(r.src)) end
		end
	end
	eachAction(rules, function(a)
		if a.target then
			local k = kinds[a.target:lower()]
			if not k then table.insert(errs, ("There's no item called '%s'."):format(a.target))
			elseif not C.ChipTargetOk(a.op, k) then table.insert(errs, ("Can't '%s' %s."):format(a.op, a.target)) end
		end
		if (a.op == "set" or a.op == "add") and a.var and kinds[a.var:lower()] then
			table.insert(errs, ("'%s' is an item's label, pick another variable name."):format(a.var))
		end
	end)
	return errs
end
function C.LabelKinds(ents)
	local kinds = {}
	for _, e in ipairs(ents or {}) do
		local l = C.LabelOf(e)
		if l then kinds[l:lower()] = e[1] end
	end
	return kinds
end
-- does anything open the exit? (a connection to it, a chip that opens it, or "Open without a button")
function C.ExitCanOpen(data)
	local exitE
	for _, e in ipairs(data.ents or {}) do if e[1] == "exit" then exitE = e end end
	if not exitE then return false end
	if C.ExitFree(exitE) then return true end
	for _, l in ipairs(data.links or {}) do
		if l[2] == exitE[8] then return true end
	end
	local label = (C.LabelOf(exitE) or "exit"):lower()
	local opens = false
	for _, chip in ipairs(type(data.chips) == "table" and data.chips or {}) do
		eachAction(C.ParseChip(chip.src), function(a)
			if (a.op == "open" or a.op == "enable" or a.op == "toggle") and a.target and a.target:lower() == label then opens = true end
		end)
	end
	return opens
end


-- ----- chip LINES view helpers: auto correct + colours -----
local function editDistance(a, b)
	if a == b then return 0 end
	local la, lb = #a, #b
	if math.abs(la - lb) > 3 then return 99 end
	-- Damerau (optimal string alignment): swapped neighbours ("sya" -> "say") count as one edit
	local prev2, prev = nil, {}
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		local cur = { [0] = i }
		local ca = a:sub(i, i)
		for j = 1, lb do
			local cb = b:sub(j, j)
			local cost = (ca == cb) and 0 or 1
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
			if prev2 and i > 1 and j > 1 and ca == b:sub(j - 1, j - 1) and a:sub(i - 1, i - 1) == cb then
				cur[j] = math.min(cur[j], prev2[j - 2] + 1)
			end
		end
		prev2, prev = prev, cur
	end
	return prev[lb]
end
-- the one closest word (nil if nothing is close or two are equally close)
local function closest(word, list, maxD)
	local best, bd, tie = nil, maxD + 1, false
	local lw = word:lower()
	for _, w in ipairs(list) do
		local d = editDistance(lw, w:lower())
		if d < bd then best, bd, tie = w, d, false
		elseif d == bd and w:lower() ~= (best or ""):lower() then tie = true end
	end
	if tie then return nil end
	return best
end
local ACTION_SET = {}
for _, a in ipairs(C.CHIP_ACTIONS) do ACTION_SET[a] = true end
local KEYWORDS = { "when" }
for _, a in ipairs(C.CHIP_ACTIONS) do table.insert(KEYWORDS, a) end
local ACTION_LIST = {}
for _, a in ipairs(C.CHIP_ACTIONS) do if a ~= "if" then table.insert(ACTION_LIST, a) end end

-- fixes typos and capitals in every line: keywords, events, comparisons and item labels. Indents actions under
-- their "when". labels = list of the chamber's labels. Returns the new text and a list of "old -> new" fixes.
function C.ChipAutocorrect(src, labels)
	local fixes = {}
	local lower = {}
	for _, l in ipairs(labels or {}) do lower[l:lower()] = l end
	-- variable names in use, so they aren't "corrected" into labels
	local vars = {}
	for v in (src .. "\n"):gmatch("[Ss][Ee][Tt]%s+([%a_][%w_]*)") do vars[v:lower()] = v end
	for v in (src .. "\n"):gmatch("[Aa][Dd][Dd]%s+([%a_][%w_]*)") do vars[v:lower()] = vars[v:lower()] or v end
	local function fixLabel(w)
		if lower[w:lower()] then return lower[w:lower()] end
		if vars[w:lower()] then return vars[w:lower()] end
		local c = closest(w, labels or {}, #w <= 4 and 1 or 2)
		if c then table.insert(fixes, w .. " -> " .. c) return c end
		return w
	end
	local function fixWord(w, list, maxD)
		local lw = w:lower()
		for _, x in ipairs(list) do if x == lw then return x end end
		local c = closest(w, list, maxD)
		if c then table.insert(fixes, w .. " -> " .. c) return c end
		return w
	end
	-- an action line without its indent ("open exit", "if a > 1 then open exit")
	local function fixAction(first, rest, allowIf)
		first = fixWord(first, allowIf and KEYWORDS or ACTION_LIST, #first <= 3 and 1 or 2)
		if first == "if" and allowIf then
			local lhs, cmp, rhs, thenW, inner = rest:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(.*)$")
			if not lhs then return "if " .. rest end
			lhs = fixLabel(lhs)
			if cmp == "~=" then cmp = "!=" elseif cmp == "=" or cmp == "===" then cmp = "==" elseif cmp == "=>" then cmp = ">=" elseif cmp == "=<" then cmp = "<=" end
			if not rhs:match("^%-?[%d%.]+$") and rhs:lower() ~= "true" and rhs:lower() ~= "false" then rhs = fixLabel(rhs) else rhs = rhs:lower() end
			thenW = fixWord(thenW, { "then" }, 2)
			local w2, r2 = inner:match("^(%S+)%s*(.*)$")
			return ("if %s %s %s %s"):format(lhs, cmp, rhs, thenW) .. (w2 and (" " .. fixAction(w2, r2, false)) or "")
		elseif first == "say" or first == "wait" or not ACTION_SET[first] then
			return first .. (rest ~= "" and (" " .. rest) or "")
		elseif first == "set" or first == "add" then
			return first .. (rest ~= "" and (" " .. rest) or "")
		end
		local target = rest:match("^(%S+)")
		return first .. (target and (" " .. fixLabel(target)) or "")
	end
	local out = {}
	for line in (src .. "\n"):gmatch("(.-)\r?\n") do
		local body = line:gsub("^%s+", ""):gsub("%s+$", "")
		if body == "" or body:match("^%-%-") or body:match("^#") then
			table.insert(out, line)
		else
			local first, rest = body:match("^(%S+)%s*(.*)$")
			local lf = first:lower()
			if lf == "when" or (not ACTION_SET[lf] and closest(first, KEYWORDS, #first <= 3 and 1 or 2) == "when") then
				if lf ~= "when" then table.insert(fixes, first .. " -> when") end
				local w2, w3 = rest:match("^(%S*)%s*(%S*)")
				local lw2 = (w2 or ""):lower()
				if lw2 == "start" or lw2 == "every" then
					w2 = lw2
				elseif w2 ~= "" and not lower[lw2] and (editDistance(lw2, "start") <= 2 or editDistance(lw2, "every") <= 2) then
					w2 = fixWord(w2, { "start", "every" }, 2)
				elseif w2 ~= "" then
					w2 = fixLabel(w2)
					if w3 ~= "" then w3 = fixWord(w3, { "pressed", "released" }, 3) end
				end
				table.insert(out, (("when %s %s"):format(w2 or "", w3 or ""):gsub("%s+$", "")))
			else
				-- (fixAction records its own keyword fix)
				table.insert(out, "    " .. fixAction(first, rest, true))
			end
		end
	end
	return table.concat(out, "\n"), fixes
end

-- the program as RichText with colours (keeps every character where it is, for an overlay on the text box)
C.CHIP_COLORS = {
	when = "#8E44AD", action = "#1F6FD0", event = "#C26A00", number = "#B5522B",
	label = "#2E8B3A", variable = "#0E8A92", unknown = "#D03030", text = "#9A6B1F", comment = "#8A8F8F", op = "#5A5F66",
}
function C.ChipHighlight(src, kinds)
	local function esc(t) return (t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
	local function paint(t, kind) return ('<font color="%s">%s</font>'):format(C.CHIP_COLORS[kind], esc(t)) end
	local EVENTS = { pressed = true, released = true, start = true, every = true }
	local vars = {}
	for v in (src .. "\n"):gmatch("[Ss][Ee][Tt]%s+([%a_][%w_]*)") do vars[v:lower()] = true end
	for v in (src .. "\n"):gmatch("[Aa][Dd][Dd]%s+([%a_][%w_]*)") do vars[v:lower()] = true end
	local out = {}
	for line in (src .. "\n"):gmatch("(.-)\n") do
		local body = line:gsub("^%s+", "")
		if body:match("^%-%-") or body:match("^#") then
			table.insert(out, paint(line, "comment"))
		else
			local parts, idx, prev, isSay = {}, 0, nil, false
			local pos = 1
			while pos <= #line do
				local s, e = line:find("%S+", pos)
				if not s then
					table.insert(parts, esc(line:sub(pos)))
					break
				end
				table.insert(parts, esc(line:sub(pos, s - 1)))
				local w = line:sub(s, e)
				local lw = w:lower()
				idx += 1
				local kind
				if isSay then
					table.insert(parts, paint(line:sub(s), "text"))
					break
				elseif lw == "when" or lw == "if" or lw == "then" then
					kind = "when"
				elseif (idx == 1 or prev == "then") and ACTION_SET[lw] then
					kind = "action"
					isSay = lw == "say"
				elseif EVENTS[lw] then
					kind = "event"
				elseif COMPARE[lw] or lw == "=" or lw == "~=" then
					kind = "op"
				elseif tonumber(w) or lw == "true" or lw == "false" then
					kind = "number"
				elseif kinds and kinds[lw] then
					kind = "label"
				elseif vars[lw] or prev == "set" or prev == "add" then
					kind = "variable"
				else
					kind = "unknown"
				end
				table.insert(parts, paint(w, kind))
				prev = lw
				pos = e + 1
			end
			table.insert(out, table.concat(parts))
		end
	end
	if #out > 0 and out[#out] == "" then table.remove(out) end
	return table.concat(out, "\n")
end

-- what to suggest at the cursor (the editor's autocomplete). line = the line up to the cursor.
-- Returns { { text, kind } ... } and the partial word being typed.
function C.ChipSuggest(line, kinds, varList)
	local words = {}
	for w in line:gmatch("%S+") do table.insert(words, w) end
	local typing = line:match("(%S*)$") or ""
	local n = #words
	if typing == "" then n += 1 end -- starting a new word
	local first = (words[1] or ""):lower()
	local list = {}
	local function add(t, kind) table.insert(list, { t, kind }) end
	local function labelsWhere(ok)
		local ls = {}
		for l, k in pairs(kinds or {}) do if ok(k) then table.insert(ls, l) end end
		table.sort(ls)
		for _, l in ipairs(ls) do add(l, "item") end
	end
	local function actionArgs(op, at)
		if at == 1 then
			if CHIP_TARGET[op] then labelsWhere(function(k) return C.ChipTargetOk(op, k) end)
			elseif op == "set" or op == "add" then for _, v in ipairs(varList or {}) do add(v, "variable") end end
		end
	end
	if n <= 1 then
		add("when", "keyword")
		for _, a in ipairs(C.CHIP_ACTIONS) do add(a, "action") end
	elseif first == "when" then
		if n == 2 then
			add("start", "event") add("every", "event")
			labelsWhere(C.ChipSourceOk)
		elseif n == 3 and kinds and kinds[(words[2] or ""):lower()] then
			add("pressed", "event") add("released", "event")
		end
	elseif first == "if" then
		if n == 2 then
			for _, v in ipairs(varList or {}) do add(v, "variable") end
			labelsWhere(function() return true end)
		elseif n == 3 then
			for _, c in ipairs(C.CHIP_COMPARE) do add(c, "compare") end
		elseif n == 4 then
			add("true", "value") add("false", "value")
			for _, v in ipairs(varList or {}) do add(v, "variable") end
		elseif n == 5 then
			add("then", "keyword")
		elseif n == 6 then
			for _, a in ipairs(C.CHIP_ACTIONS) do if a ~= "if" then add(a, "action") end end
		elseif n == 7 then
			actionArgs((words[6] or ""):lower(), 1)
		end
	else
		actionArgs(first, n - 1)
	end
	-- keep the ones that start with what's typed (or, failing that, contain it)
	if typing ~= "" then
		local lt, starts, contains = typing:lower(), {}, {}
		for _, s in ipairs(list) do
			local ls = s[1]:lower()
			if ls ~= lt then
				if ls:sub(1, #lt) == lt then table.insert(starts, s)
				elseif ls:find(lt, 1, true) then table.insert(contains, s) end
			end
		end
		for _, s in ipairs(contains) do table.insert(starts, s) end
		list = starts
	end
	return list, typing
end

-- the hint for the line being typed (its keyword, or the action after "then")
function C.ChipHintFor(line)
	local first = (line:match("^%s*(%S+)") or ""):lower()
	if first == "if" then
		local after = line:match("[Tt][Hh][Ee][Nn]%s+(%S+)")
		if after and C.CHIP_HINTS[after:lower()] then return C.CHIP_HINTS["if"] .. "      " .. C.CHIP_HINTS[after:lower()] end
	end
	return C.CHIP_HINTS[first]
end

-- ==========================================
-- WIKI (the editor's Help > Wiki). RichText: <b>, <i>, <font color="#..">.
-- ==========================================
C.WIKI = {
	{ "Getting started", [[
<b>The test chamber editor</b> builds a room out of tiles, fills it with test elements and lets you play it.

1. Shape the room: select panels and pull / push them.
2. Drag items in from the palette on the left.
3. Connect a button to the <b>exit door</b> (it's locked until something opens it).
4. Press <b>F9</b> (or the play button) to build and play it.
5. File > Publish puts it in the Workshop.

Help > Tutorial walks you through the screen again.]] },
	{ "Shaping the room", [[
<b>Select</b>: click a panel. Drag across a wall for an area, Shift+click to add everything in between, Ctrl+click to add / remove one, Ctrl+A for all.
<b>Pull / push</b>: <b>+</b> pulls the selected panels toward you (fills cells in), <b>-</b> pushes them away (digs cells out).
<b>Portalable</b>: <b>P</b> switches the selected panels between white (portals stick) and dark metal (they don't).
<b>Colour</b>: right-click > Tile color, or <b>T</b> to paint with the last colour.
<b>Camera</b>: middle-drag orbits, right-drag pans, the wheel zooms, WASD / Q E move.
<b>Game view</b>: <b>Tab</b> shows the chamber the way it will look in game, without building it.]] },
	{ "Items", [[
Open the palette (the strip on the left, or Y on a controller) and drag an item onto a panel. Each item only goes where it fits: floor, wall, ceiling or any.
<b>Move</b>: drag it. <b>Turn</b>: R, or click a diamond handle. <b>Delete</b>: Delete key. <b>Options</b>: right-click it.
Fizzlers and laser fields: drag the triangles to change their length. Faith plates: drag the yellow ball onto a panel to aim, then up / down for the arc. Toxic goo: drag the edge triangles to grow it.
The entry and exit doors can be moved but never deleted.]] },
	{ "Connections + the exit", [[
Buttons, pedestals, laser catchers and logic gates <b>drive</b> other items. Select one, press <b>C</b>, then click the item it should control. Right-click > Remove connections takes them off.
An item with several inputs needs <b>all</b> of them on. Put an OR logic gate in front of it if any one should do.
<b>The exit door is locked</b> until something opens it: a connection, a chip (open exit), or right-click the exit > <b>Open without a button</b>. Build and Play warns you about a locked exit and Publish refuses one.]] },
	{ "Textures", [[
<i>Intermediate and Advanced modes.</i>
Select surfaces in the room, then open the <b>Textures</b> tab and click a texture.
<b>TOOLBOX</b> searches decals, <b>IN GAME</b> lists ReplicatedStorage.PortalAssets.Textures. Or paste an image / decal id and press USE ID.
CLEAR TEXTURE puts the normal tiles back.]] },
	{ "Meshes", [[
<i>Intermediate and Advanced modes.</i>
The <b>Meshes</b> tab places decoration MeshParts. <b>TOOLBOX</b> searches the Creator Store for MeshParts only, <b>IN GAME</b> lists ReplicatedStorage.PortalAssets.Meshes, or paste a Mesh id.
Drag one onto any surface. Right-click it for <b>Size</b>; in Advanced mode also <b>Turn 15°</b> and <b>Nudge</b>.]] },
	{ "Chips", [[
<i>Advanced mode.</i> Chips are little programs that run in your chamber. Open the <b>My Chips</b> tab and press + NEW CHIP.
Build them from <b>BLOCKS</b> (pick everything from menus) or type them as <b>LINES</b>. Both are the same program; switch whenever you like.
In LINES, words are coloured, typos are fixed when you press Enter, suggestions pop up as you type (<b>Tab</b> takes the top one) and the bar at the bottom shows what the line expects.
Items are called by their <b>label</b> (right-click an item to see or change it). <b>TO MY CHIPS</b> saves a chip so you can use it in any chamber.]] },
	{ "Chips: reference", [[
<b>Events</b> (start a rule; the lines under it run when it happens)
  <font color="#8E44AD">when</font> button1 <font color="#C26A00">pressed</font>   /   <font color="#C26A00">released</font>   (buttons, pedestals, laser catchers, gates)
  <font color="#8E44AD">when</font> <font color="#C26A00">start</font>   (the chamber was just built)
  <font color="#8E44AD">when</font> <font color="#C26A00">every</font> 5   (every 5 seconds)

<b>Actions</b>
  <font color="#1F6FD0">open</font> / <font color="#1F6FD0">close</font> <i>item</i>   doors, or turn an item on / off
  <font color="#1F6FD0">enable</font> / <font color="#1F6FD0">disable</font> / <font color="#1F6FD0">toggle</font> <i>item</i>
  <font color="#1F6FD0">drop</font> <i>dropper</i>   a new cube      <font color="#1F6FD0">reverse</font> <i>funnel</i>
  <font color="#1F6FD0">wait</font> 2   pause this rule      <font color="#1F6FD0">say</font> "text"   a message on screen

<b>Variables</b> (shared by every chip in the chamber, start at 0)
  <font color="#1F6FD0">set</font> <font color="#0E8A92">score</font> 0      <font color="#1F6FD0">add</font> <font color="#0E8A92">score</font> 1      <font color="#1F6FD0">add</font> <font color="#0E8A92">score</font> -1
  <font color="#1F6FD0">say</font> "Score: {score}"   shows the value

<b>If</b> (one line)
  <font color="#8E44AD">if</font> <font color="#0E8A92">score</font> &gt;= 3 <font color="#8E44AD">then</font> <font color="#1F6FD0">open</font> exit
  Compare with == != &lt; &gt; &lt;= &gt;=. An item in an if counts as 1 when it's pressed / on / open, else 0: <font color="#8E44AD">if</font> button2 == 1 <font color="#8E44AD">then</font> ...

Lines starting with -- or # are comments.]] },
	{ "Chips: examples", [[
<b>Hold the button to keep the exit open</b>
when button1 pressed
    open exit
when button1 released
    close exit

<b>Press it three times</b>
when start
    set presses 0
when button1 pressed
    add presses 1
    say "{presses} / 3"
    if presses >= 3 then open exit

<b>Two buttons, both needed</b>
when button1 pressed
    if button2 == 1 then open exit
when button2 pressed
    if button1 == 1 then open exit

<b>A cube every 10 seconds</b>
when every 10
    drop dropper1]] },
	{ "Editor modes", [[
Options > Editor > <b>Editor Mode</b>, or File > Editor mode:
<b>Simple</b>: the Items palette.
<b>Intermediate</b>: + Textures and Meshes tabs.
<b>Advanced</b>: + My Chips, item labels, mesh nudging and a coordinates readout under the pointer.]] },
	{ "Editor styles", [[
Options > Editor > <b>Editor Style</b>, or File > Editor style, changes how the editor looks:
<b>Classic</b> the light grey Puzzle Maker look. <b>Dark</b> for night owls. <b>Blueprint</b> blue drafting paper. <b>High Contrast</b> black, white and yellow for the clearest view.]] },
	{ "Controls", [[
<b>Mouse + keyboard</b>: click select, + / - pull / push, P portalable, T paint, C connect, R rotate, Delete delete, Ctrl+Z / Y undo / redo, Ctrl+S save, Tab game view, F9 build and play.
<b>Controller</b>: left stick cursor, A select, X menu, Y items, B cancel, D-pad pull / push / rotate / portalable, L3 connect, R3 game view, Back build and play, LT + sticks move the camera, LB / RB zoom.
<b>Touch</b>: tap to select, drag across a wall for an area, one finger orbits, two pan and zoom, hold for the menu, toolbar along the bottom.]] },
	{ "Publishing + co-op", [[
File > <b>Publish</b> puts the chamber in the Workshop (the exit has to be openable). Chip messages are filtered when you publish.
File > <b>Cooperative puzzle</b> marks it as a co-op chamber. In co-op the blue player is <b>Atlas</b> and the orange player is <b>P-body</b>.
File > <b>Invite team builder</b> lets friends in this server build with you.]] },
}

-- ==========================================
-- TUTORIALS (Options > Gameplay > Tutorials turns them off)
-- ==========================================
-- Shown when a level starts. A chapter can have its own: tutorial = { { title, text }, ... } in C.CHAPTERS.
C.TUTORIALS = {
	chapter = {
		{ "Moving", "WASD to walk, Space to jump, move the mouse to look around." },
		{ "Portals", "Left click fires a blue portal, right click an orange one. Walk into one to come out of the other." },
		{ "Portal surfaces", "Portals only stick to the white (portalable) panels, not the dark metal ones." },
		{ "Carrying", "Press E to pick up a cube, E again to drop it. Cubes hold buttons down." },
		{ "Exits", "The exit door stays locked until you solve the chamber. Find the buttons that open it." },
	},
	challenge = {
		{ "Challenge Mode", "Finish the chamber with as few portals and as fast as you can. Your best times go on the leaderboard." },
	},
	workshop = {
		{ "Community chamber", "Someone built this chamber in the editor. Find what opens the exit door to finish it." },
		{ "Rating", "When you finish you can rate it up or down." },
	},
	coop = {
		{ "Co-op", "You and your partner each have your own pair of portals. Work together - some puzzles need both of you." },
	},
	editor = {
		{ "Welcome to the editor", "Click a panel to select it. Drag across a wall to select an area." },
		{ "Shaping the room", "Press + to pull the selected panels toward you, - to push them away. Middle mouse orbits, right mouse pans, wheel zooms." },
		{ "Items", "Move the mouse to the strip on the left to open the palette, then drag items into the room." },
		{ "The exit door", "The exit stays locked until something opens it. Select a button, press C and click the exit to connect them." },
		{ "Testing", "Press F9 (or the play button at the top) to build and play your chamber. Tab shows how it will look without building." },
		{ "More tools", "Options > Editor > Editor Mode: Intermediate adds Textures and Meshes, Advanced adds My Chips." },
	},
	playtest = {
		{ "Playtesting", "Try to solve your chamber. Pause and pick Exit To Editor to keep building, or press F9 to rebuild." },
	},
}

function C.DefaultChamber()
	local air = {}
	for x = -3, 3 do
		for z = -3, 3 do
			for y = 0, 2 do table.insert(air, { x, y, z }) end
		end
	end
	-- a button wired to the exit: the exit stays locked until something opens it
	return { v = 2, air = air, faces = {}, colors = {}, textures = {}, chips = {}, ents = {
		{ "entry", -3, 0, 0, 2, 0, false, "entry000", false, { label = "entry" } },
		{ "exit", 3, 0, 0, 1, 0, false, "exit0000", false, { label = "exit" } },
		{ "button", 0, 0, 0, 4, 0, false, "button01", false, { label = "button1" } },
	}, links = { { "button01", "exit0000" } } }
end

function C.Chapter(i) return C.CHAPTERS[i] end
function C.Achievement(id)
	for _, a in ipairs(C.ACHIEVEMENTS) do if a.id == id then return a end end
end
function C.Item(id)
	for _, it in ipairs(C.STORE) do if it.id == id then return it end end
end
function C.Chamber(id)
	for _, course in ipairs(C.COURSES) do
		for _, ch in ipairs(course.chambers) do
			if ch.id == id then return ch, course end
		end
	end
end

return C
