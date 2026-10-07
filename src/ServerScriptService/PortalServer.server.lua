-- PortalServer
-- ServerScriptService (Script)
-- Back end for PortalMenu: profiles (DataStore), save slots, chapters/acts, achievements, settings,
-- co-op (invites + quick match), Workshop (publish / browse / rate / queue), the test chamber editor,
-- Robot Enrichment store and Challenge Mode leaderboards.
--
-- Talks to clients through ReplicatedStorage.PortalNet:
--   Request (RemoteFunction)  client -> server   Request:InvokeServer(action, arg) -> ok, result
--   Push    (RemoteEvent)     server -> client   Push.OnClientEvent(kind, data)
--
-- Other SERVER scripts can use the API on `shared.PortalData` (see the bottom of this file), e.g. from your portal gun:
--   shared.PortalData.CountPortal(player)
--   shared.PortalData.Unlock(player, "WAKE_UP")
--   shared.PortalData.AddProgress(player, "PORTALS_100", 1)
--   shared.PortalData.RegisterSaveHook("Portals", saveFn(player) -> table, loadFn(player, table))
--
-- Rig changer (gives you the portal gun rig for editor playtests). This script looks for, in order:
--   shared.RigChanger                          a function(player, action, opts) or a table with .Change / [action]
--   a BindableFunction / BindableEvent named "RigChange", "RigChanger" or "RigChangerServer"
--   anywhere in ServerScriptService, ServerStorage or ReplicatedStorage   -> called as (player, action, opts)
-- action is "Equip". Your rig script should set the character attribute "HasPortalGun" = true when it's done.
--
-- Map triggers (CollectionService tags, work inside cloned maps). Detection is overlap-based (not .Touched), so it
-- catches players who fly through fast, land on them, or stand in them:
--   PortalChapterEnd   Part (or Model), number attribute "Chapter". Unlocks the next chapter, autosaves, and loads the
--                      next chapter if bool attribute "AutoAdvance" is true.
--   PortalAutosave     Part. Autosaves when entered (once per part per player).
--   PortalAchievement  Part, string attribute "Achievement".
--   PortalChamberExit  Part. Finishes a Workshop chamber / challenge chamber / editor playtest.
--
-- Instances: every player (a co-op pair shares one) plays in their own spot, workspace.PortalInstances.Slot_<n>, far
-- away from everyone else (PortalConfig "INSTANCES"). Chapters, challenges, Workshop chambers and playtests all load there.
--
-- Chamber doors (ChamberLockDoor, tagged PortalChamberDoor by PortalConfig) get these attributes, kept up to date:
--   Open (bool)        exit door: a player is near AND it's unlocked. entry: false
--   Unlocked (bool)    exit door: its inputs are all on / a chip opened it / it's set to open without a button.
--                      Editor-built exits with nothing connected stay LOCKED, and their finish trigger does nothing.
--   PlayerNear (bool)  someone is within Config.DOOR_OPEN_RADIUS
-- Have your door's own script open / close on the "Open" attribute.
--
-- Connections (editor chambers): buttons, pedestals, laser catchers and logic gates drive the items they're wired to.
-- An item with several inputs needs ALL of them on (Portal 2). Logic gates combine inputs (AND / OR / NOT / XOR / NAND /
-- NOR) and can feed each other. Droppers drop a new cube every time their inputs turn on.
--
-- Studio: turn on Game Settings > Security > "Enable Studio Access to API Services" for DataStores / MemoryStores.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("PortalConfig"))
if Config.VERSION ~= 3 then
	warn("[PortalServer] ReplicatedStorage.PortalConfig is out of date (version " .. tostring(Config.VERSION) .. ", need 3). Replace it with the new PortalConfig - things will break until you do.")
end

-- ==========================================
-- NETWORK
-- ==========================================
local net = ReplicatedStorage:FindFirstChild("PortalNet") or Instance.new("Folder")
net.Name = "PortalNet"
net.Parent = ReplicatedStorage
local Request = net:FindFirstChild("Request") or Instance.new("RemoteFunction")
Request.Name = "Request"
Request.Parent = net
local Push = net:FindFirstChild("Push") or Instance.new("RemoteEvent")
Push.Name = "Push"
Push.Parent = net

-- ==========================================
-- DATASTORES (all wrapped, so the game still runs without API access)
-- ==========================================
local function getStore(name, ordered)
	local ok, s = pcall(function()
		return ordered and DataStoreService:GetOrderedDataStore(name) or DataStoreService:GetDataStore(name)
	end)
	return ok and s or nil
end
local profileStore = getStore("PortalProfile_v1")
local workshopStore = getStore("PortalWorkshop_v1")

local function retry(fn, tries)
	for i = 1, tries or 3 do
		local ok, a, b = pcall(fn)
		if ok then return true, a, b end
		if i < (tries or 3) then task.wait(1.5 * i) else warn("[PortalServer] DataStore:", a) end
	end
	return false
end

local function filterText(text, player)
	local ok, filtered = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	return ok and filtered or nil
end

-- ==========================================
-- PROFILES
-- ==========================================
local profiles = {}
local loadedEvent = {}
local dirty = {}

local function newProfile()
	return {
		v = 1,
		settings = {},
		saves = {},
		maxChapter = 1,
		achievements = {},
		progress = {},
		inventory = {},
		equipped = { blue = {}, orange = {} },
		queue = {},
		follows = {},
		drafts = {},
		published = {},
		chips = {}, -- the My Chips library: { id, name, src }
		stats = { portals = 0, playtime = 0 },
	}
end

local function reconcile(p)
	local template = newProfile()
	for k, v in pairs(template) do
		if p[k] == nil then p[k] = v end
	end
	local drafts = {}
	for _, d in ipairs(p.drafts or {}) do
		-- (any chamber with a room: older drafts are upgraded when they're opened)
		if type(d) == "table" and d.id and type(d.data) == "table" and type(d.data.air) == "table" then table.insert(drafts, d) end
	end
	p.drafts = drafts
	p.equipped.blue = p.equipped.blue or {}
	p.equipped.orange = p.equipped.orange or {}
	return p
end

local function saveProfile(player)
	local p = profiles[player]
	if not p or not profileStore then return end
	dirty[player] = nil
	retry(function()
		profileStore:UpdateAsync("u_" .. player.UserId, function()
			return p
		end)
	end)
end

-- waits for the profile even if the client asks before PlayerAdded has run on the server
local function getProfile(player, timeout)
	if profiles[player] then return profiles[player] end
	local t0 = os.clock()
	while not profiles[player] and player.Parent and os.clock() - t0 < (timeout or 20) do
		task.wait(0.1)
	end
	return profiles[player]
end

local function markDirty(player) dirty[player] = true end

-- ==========================================
-- ACHIEVEMENTS
-- ==========================================
local function unlock(player, id)
	local p = getProfile(player, 5)
	local def = Config.Achievement(id)
	if not p or not def or p.achievements[id] then return false end
	p.achievements[id] = os.time()
	markDirty(player)
	Push:FireClient(player, "Achievement", { id = id })
	return true
end

local function addProgress(player, id, amount)
	local p = getProfile(player, 5)
	local def = Config.Achievement(id)
	if not p or not def then return end
	p.progress[id] = (p.progress[id] or 0) + (amount or 1)
	markDirty(player)
	if def.goal and p.progress[id] >= def.goal then unlock(player, id) end
end

-- ==========================================
-- CHARACTERS
-- ==========================================
local lastPos = {} -- [player] = Vector3, used by trigger detection (cleared on teleports)

local function charRoot(player)
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildWhichIsA("BasePart")
end

local function waitRoot(player, timeout)
	local t0 = os.clock()
	while player.Parent and not charRoot(player) and os.clock() - t0 < (timeout or 5) do task.wait() end
	return charRoot(player)
end

local function placeCharacter(player, cf)
	if not cf then return end
	if not player.Character then player.CharacterAdded:Wait() end
	local root = waitRoot(player, 5)
	if not root then return end
	local char = player.Character
	-- far away (chambers sit thousands of studs out): with StreamingEnabled the floor isn't on the player's client yet,
	-- so they'd drop straight through into the void. Stream it in first and hold them still until it's there.
	local far = (root.Position - cf.Position).Magnitude > 300
	if far then
		root.Anchored = true
		char:PivotTo(cf)
		if workspace.StreamingEnabled then
			pcall(function() player:RequestStreamAroundAsync(cf.Position, 8) end)
		end
		task.wait(0.2)
		root = charRoot(player)
		if not root or player.Character ~= char then return end
	end
	root.Anchored = false
	char:PivotTo(cf)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	lastPos[player] = nil -- don't sweep trigger detection across the teleport
end

local function spawnCF(spawnPart)
	local facing = spawnPart:GetAttribute("Facing") -- built chambers: look into the room
	local look = typeof(facing) == "Vector3" and facing or spawnPart.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	local pos = spawnPart.Position + Vector3.new(0, spawnPart.Size.Y / 2 + 3.5, 0)
	return CFrame.lookAt(pos, pos + flat.Unit)
end

local function findSpawn(root, color)
	if not root then return nil end
	local s = (color and root:FindFirstChild("PlayerSpawn" .. color, true)) or root:FindFirstChild("PlayerSpawn", true)
	return s and s:IsA("BasePart") and s or nil
end

local function sendToLobby(player)
	local s = workspace:FindFirstChild(Config.LOBBY_SPAWN)
	if s and s:IsA("BasePart") then placeCharacter(player, spawnCF(s)) end
end

-- ----- rig changer hook -----
local rigHookCache, rigWarned = nil, false
local RIG_NAMES = { RigChangerEvent = true, RigChange = true, RigChanger = true, RigChangerServer = true }
local function findRigHook()
	local s = shared.RigChanger
	if type(s) == "function" or type(s) == "table" then return s end
	if rigHookCache and rigHookCache.Parent then return rigHookCache end
	rigHookCache = nil
	for _, root in ipairs({ ServerScriptService, ServerStorage, ReplicatedStorage }) do
		for _, d in ipairs(root:GetDescendants()) do
			if RIG_NAMES[d.Name] and (d:IsA("BindableFunction") or d:IsA("BindableEvent")) then
				rigHookCache = d
				return d
			end
		end
	end
	return nil
end

local lastRig = {}
local function rigChange(player, action, opts)
	local hook = findRigHook()
	if not hook then
		if not rigWarned then
			rigWarned = true
			warn("[PortalServer] no rig changer found (shared.RigChanger or a BindableFunction/Event named RigChange) - playtest continues without it")
		end
		return false
	end
	lastRig[player] = os.clock()
	player:SetAttribute("RigWaitFrom", player:GetAttribute("RigChangeDone") or 0)
	local ok, err = pcall(function()
		if type(hook) == "function" then
			hook(player, action, opts)
		elseif type(hook) == "table" then
			if type(hook.Change) == "function" then hook.Change(player, action, opts)
			elseif type(hook[action]) == "function" then hook[action](player, opts) end
		elseif hook:IsA("BindableFunction") then
			hook:Invoke(player, action, opts)
		else
			hook:Fire(player, action, opts)
		end
	end)
	if not ok then warn("[PortalServer] rig changer:", err) end
	return ok
end

-- waits until the rig swap is done: RigChangerServer bumps RigChangeDone when it finishes a request
-- (other rig scripts: a new character, or the old one got HasPortalGun)
local function waitForRig(player, oldChar, timeout)
	local from = player:GetAttribute("RigWaitFrom") or 0
	local t0 = os.clock()
	while player.Parent and os.clock() - t0 < (timeout or 5) do
		local c = player.Character
		local done = (player:GetAttribute("RigChangeDone") or 0) ~= from
			or (c and (c ~= oldChar or c:GetAttribute("HasPortalGun")))
		if done and c and charRoot(player) then return true end
		task.wait()
	end
	return false
end

-- ==========================================
-- MAPS + INSTANCES
-- ==========================================
-- Every player (a co-op pair shares one) gets a slot: workspace.PortalInstances.Slot_<n>, placed far away from every
-- other slot (Config.InstanceOffset). Chapters, challenge maps, Workshop chambers and editor playtests load into the
-- player's own slot, so people playing different things never see / clear / trip each other's maps.
local instancesRoot = workspace:FindFirstChild("PortalInstances") or Instance.new("Folder")
instancesRoot.Name = "PortalInstances"
instancesRoot.Parent = workspace

local slotOf = {}    -- [player] = slot number
local slotUsers = {} -- [slot] = { [player] = true }

local function slotFolder(slot)
	local name = "Slot_" .. slot
	local f = instancesRoot:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f:SetAttribute("Slot", slot)
		f.Parent = instancesRoot
	end
	return f
end

local function joinSlot(player, slot)
	local old = slotOf[player]
	if old == slot then return slot end
	if old and slotUsers[old] then
		slotUsers[old][player] = nil
		if next(slotUsers[old]) == nil then
			slotUsers[old] = nil
			local f = instancesRoot:FindFirstChild("Slot_" .. old)
			if f then f:Destroy() end
		end
	end
	slotOf[player] = slot
	slotUsers[slot] = slotUsers[slot] or {}
	slotUsers[slot][player] = true
	player:SetAttribute("InstanceSlot", slot)
	return slot
end

local function acquireSlot(player)
	if slotOf[player] then return slotOf[player] end
	local n = 1
	while slotUsers[n] do n += 1 end
	return joinSlot(player, n)
end

-- leaves the slot (its maps are cleared once nobody is left in it)
local function leaveSlot(player)
	local old = slotOf[player]
	if not old then return end
	slotOf[player] = nil
	player:SetAttribute("InstanceSlot", nil)
	local users = slotUsers[old]
	if users then
		users[player] = nil
		if next(users) == nil then
			slotUsers[old] = nil
			local f = instancesRoot:FindFirstChild("Slot_" .. old)
			if f then f:Destroy() end
		end
	end
end

local function slotPlayers(slot)
	local list = {}
	for pl in pairs(slotUsers[slot] or {}) do
		if pl.Parent then table.insert(list, pl) end
	end
	return list
end

-- the player's own instance folder (made on demand)
local function activeFolder(player)
	return slotFolder(acquireSlot(player))
end

local function clearActive(player)
	local slot = slotOf[player]
	if not slot then return end
	local f = instancesRoot:FindFirstChild("Slot_" .. slot)
	if f then
		f:ClearAllChildren()
		f:SetAttribute("Map", nil)
	end
end

-- moves a freshly cloned map out to the slot
local function offsetMap(root, offset)
	if offset.Magnitude < 0.01 then return end
	if root:IsA("Model") or root:IsA("BasePart") then
		root:PivotTo(root:GetPivot() + offset)
		return
	end
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("PVInstance") then
			c:PivotTo(c:GetPivot() + offset)
		elseif c:IsA("Folder") then
			offsetMap(c, offset)
		end
	end
end

local function loadMap(name, force, player)
	if not player then
		warn("[PortalServer] loadMap needs the player now (each player has their own instance)")
		return nil
	end
	local folder = activeFolder(player)
	if folder:GetAttribute("Map") == name and not force and #folder:GetChildren() > 0 then
		return folder
	end
	local maps = ServerStorage:FindFirstChild(Config.MAPS_FOLDER)
	local src = maps and maps:FindFirstChild(name)
	clearActive(player)
	if not src then
		warn(("[PortalServer] map '%s' not found in ServerStorage.%s"):format(tostring(name), Config.MAPS_FOLDER))
		return nil
	end
	local clone = src:Clone()
	if Config.OFFSET_CHAPTER_MAPS then offsetMap(clone, Config.InstanceOffset(slotOf[player])) end
	clone.Parent = folder
	folder:SetAttribute("Map", name)
	return folder
end

-- ==========================================
-- SAVE GAMES
-- ==========================================
local saveHooks = {}

local function summarizeSaves(p)
	local list = {}
	for _, s in ipairs(p.saves) do
		table.insert(list, { id = s.id, time = s.time, chapter = s.chapter, auto = s.auto })
	end
	table.sort(list, function(a, b) return a.time > b.time end)
	return list
end

local function makeSave(player, slotId, auto)
	local p = getProfile(player, 5)
	if not p then return nil, "Profile not loaded" end
	local root = charRoot(player)
	local chapter = player:GetAttribute("Chapter")
	if not chapter then return nil, "You can only save while playing a chapter." end
	local entry
	if auto then
		for _, s in ipairs(p.saves) do if s.auto then entry = s end end
	elseif slotId then
		for _, s in ipairs(p.saves) do if s.id == slotId and not s.auto then entry = s end end
	end
	if not entry then
		local manual = 0
		for _, s in ipairs(p.saves) do if not s.auto then manual += 1 end end
		if not auto and manual >= Config.MAX_SAVE_SLOTS then return nil, "All save slots are full. Overwrite one instead." end
		entry = { id = HttpService:GenerateGUID(false), auto = auto or false }
		table.insert(p.saves, entry)
	end
	entry.time = os.time()
	entry.chapter = chapter
	local folder = slotOf[player] and instancesRoot:FindFirstChild("Slot_" .. slotOf[player])
	entry.map = folder and folder:GetAttribute("Map") or nil
	-- stored relative to the player's instance, so it loads back into whatever slot they get next time
	local off = (Config.OFFSET_CHAPTER_MAPS and slotOf[player]) and Config.InstanceOffset(slotOf[player]) or Vector3.zero
	entry.cf = root and { (root.CFrame - off):GetComponents() } or nil
	entry.rel = true
	entry.hooks = {}
	for name, h in pairs(saveHooks) do
		local ok, data = pcall(h.save, player)
		if ok and data ~= nil then entry.hooks[name] = data end
	end
	markDirty(player)
	if not auto then unlock(player, "FIRST_SAVE") end
	task.spawn(saveProfile, player)
	return entry
end

local function latestSave(p)
	local best
	for _, s in ipairs(p.saves) do
		if not best or s.time > best.time then best = s end
	end
	return best
end

local function startChapter(player, index)
	local def = Config.Chapter(index)
	if not def then return false, "That chapter doesn't exist." end
	if def.placeId then
		local ok, err = pcall(function()
			local opts = Instance.new("TeleportOptions")
			opts:SetTeleportData({ action = "NewGame", chapter = index })
			TeleportService:TeleportAsync(def.placeId, { player }, opts)
		end)
		return ok, err
	end
	local root = loadMap(def.map, true, player)
	player:SetAttribute("Chapter", index)
	player:SetAttribute("ChallengeChamber", nil)
	player:SetAttribute("WorkshopMap", nil)
	local s = findSpawn(root)
	if s then placeCharacter(player, spawnCF(s)) end
	return true
end

local function loadSave(player, save)
	if not save then return false, "Save not found." end
	local def = Config.Chapter(save.chapter)
	if not def then return false, "That save's chapter no longer exists." end
	if def.placeId then
		local ok, err = pcall(function()
			local opts = Instance.new("TeleportOptions")
			opts:SetTeleportData({ action = "LoadGame", saveId = save.id })
			TeleportService:TeleportAsync(def.placeId, { player }, opts)
		end)
		return ok, err
	end
	local root = loadMap(save.map or def.map, true, player)
	player:SetAttribute("Chapter", save.chapter)
	player:SetAttribute("ChallengeChamber", nil)
	player:SetAttribute("WorkshopMap", nil)
	if save.cf then
		local off = (save.rel and Config.OFFSET_CHAPTER_MAPS and slotOf[player]) and Config.InstanceOffset(slotOf[player]) or Vector3.zero
		placeCharacter(player, CFrame.new(table.unpack(save.cf)) + off)
	else
		local s = findSpawn(root)
		if s then placeCharacter(player, spawnCF(s)) end
	end
	for name, data in pairs(save.hooks or {}) do
		local h = saveHooks[name]
		if h and h.load then
			local ok, err = pcall(h.load, player, data)
			if not ok then warn("[PortalServer] save hook", name, err) end
		end
	end
	return true
end

local function finishChapter(player, index)
	local p = getProfile(player, 5)
	if not p then return end
	p.maxChapter = math.max(p.maxChapter, math.min(index + 1, #Config.CHAPTERS))
	for _, a in ipairs(Config.ACHIEVEMENTS) do
		if a.chapter == index then unlock(player, a.id) end
	end
	markDirty(player)
	Push:FireClient(player, "ChapterUnlocked", { maxChapter = p.maxChapter })
end

-- ==========================================
-- WORKSHOP
-- ==========================================
local workshopCache = { t = 0, list = {} }
local localWorkshop = {}

local function workshopIndex(force)
	if not force and os.clock() - workshopCache.t < 45 then return workshopCache.list end
	if workshopStore then
		local ok, list = retry(function() return workshopStore:GetAsync("index") end, 2)
		if ok then workshopCache.list = list or {} end
	else
		workshopCache.list = localWorkshop.index or {}
	end
	workshopCache.t = os.clock()
	return workshopCache.list
end

local function updateIndex(fn)
	if workshopStore then
		retry(function()
			workshopStore:UpdateAsync("index", function(list)
				list = list or {}
				fn(list)
				return list
			end)
		end)
	else
		localWorkshop.index = localWorkshop.index or {}
		fn(localWorkshop.index)
	end
	workshopCache.t = 0
end

local function getMapData(id)
	if workshopStore then
		local ok, data = retry(function() return workshopStore:GetAsync("map_" .. id) end, 2)
		return ok and data or nil
	end
	return localWorkshop["map_" .. id]
end

-- validates a chamber coming from a client (and keeps the item ids so connections survive)
local function cleanMap(data)
	if type(data) ~= "table" then return nil, "Bad data." end
	data = Config.UpgradeChamber(table.clone(data)) -- older chambers: exits nothing opens keep opening by themselves
	local L = Config.EDITOR_LIMITS
	local out = { v = 2, fmt = Config.CHAMBER_FORMAT, air = {}, faces = {}, colors = {}, textures = {}, ents = {}, links = {}, chips = {},
		coop = data.coop == true }
	if type(data.air) ~= "table" or #data.air > L.cells then return nil, "That chamber is too big." end
	local air = {}
	for _, c in ipairs(data.air) do
		if type(c) == "table" then
			local x, y, z = math.floor(tonumber(c[1]) or 0), math.floor(tonumber(c[2]) or 0), math.floor(tonumber(c[3]) or 0)
			local k = Config.Key(x, y, z)
			if math.abs(x) <= L.x and math.abs(z) <= L.z and y >= L.yMin and y <= L.yMax and not air[k] then
				air[k] = true
				table.insert(out.air, { x, y, z })
			end
		end
	end
	if #out.air == 0 then return nil, "The chamber is empty." end
	if type(data.faces) == "table" then
		local n = 0
		for k, v in pairs(data.faces) do
			n += 1
			if n > L.cells * 6 then break end
			if type(k) == "string" and (v == 0 or v == 2 or v == 3) and k:match("^%-?%d+,%-?%d+,%-?%d+,[1-6]$") then out.faces[k] = v end
		end
	end
	-- tile colours and textures (Textures tab)
	for _, field in ipairs({ "colors", "textures" }) do
		if type(data[field]) == "table" then
			local n = 0
			for k, v in pairs(data[field]) do
				n += 1
				if n > L.cells * 6 then break end
				if type(k) == "string" and k:match("^%-?%d+,%-?%d+,%-?%d+,[1-6]$") then
					if field == "colors" and Config.ValidTileColor(v) then
						out.colors[k] = tonumber(v) or string.lower(v) -- a palette number or a custom "#rrggbb"
					elseif field == "textures" and Config.ValidTextureValue(v) then
						out.textures[k] = v
					end
				end
			end
		end
	end
	-- the chamber's own audio ids (File > Chamber audio): { n = name, id = number }
	if type(data.audio) == "table" then
		out.audio = {}
		for i, a in ipairs(data.audio) do
			if i > (Config.AUDIO_MAX or 24) then break end
			if type(a) == "table" and type(a.n) == "string" and #a.n >= 1 and #a.n <= 30 and tonumber(a.id) then
				table.insert(out.audio, { n = a.n:gsub("[%c]", ""), id = math.floor(tonumber(a.id)) })
			end
		end
	end
	-- NPC demo (ChamberBotServer): recorded runs, numbers only. tracks = the runs NPCs replay (up to 2),
	-- learn = extra runs the autonomous NPC learns from (up to 6, File > NPC demo > Teach the NPC)
	if type(data.demo) == "table" then
		local function cleanTrack(t, maxFrames)
			if type(t) ~= "table" or type(t.frames) ~= "table" then return nil end
			local frames, portals = {}, {}
			for j2, f in ipairs(t.frames) do
				if j2 > maxFrames then break end
				if type(f) == "table" and tonumber(f[1]) and tonumber(f[2]) and tonumber(f[3]) then
					table.insert(frames, { tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4]) or 0, math.floor(tonumber(f[5]) or 0) % 2 })
				end
			end
			for j2, ev in ipairs(type(t.portals) == "table" and t.portals or {}) do
				if j2 > 300 then break end
				if type(ev) == "table" and tonumber(ev[1]) and (ev[2] == "Blue" or ev[2] == "Orange") then
					local c = { tonumber(ev[1]), ev[2] }
					if tonumber(ev[3]) then
						for k = 3, 13 do c[k] = tonumber(ev[k]) or 0 end
					end
					table.insert(portals, c)
				end
			end
			if #frames < 2 then return nil end
			return { color = (t.color == "Blue" or t.color == "Orange") and t.color or nil,
				t0 = math.clamp(tonumber(t.t0) or 0, 0, 30), dt = math.clamp(tonumber(t.dt) or 0.1, 0.05, 1),
				done = t.done == true, frames = frames, portals = portals }
		end
		local tracks, learn = {}, {}
		for i2, t in ipairs(type(data.demo.tracks) == "table" and data.demo.tracks or {}) do
			if i2 > 2 then break end
			local c = cleanTrack(t, 2400)
			if c then table.insert(tracks, c) end
		end
		for i2, t in ipairs(type(data.demo.learn) == "table" and data.demo.learn or {}) do
			if i2 > 6 then break end
			local c = cleanTrack(t, 900)
			if c then table.insert(learn, c) end
		end
		if #tracks > 0 or #learn > 0 then out.demo = { tracks = tracks, learn = learn } end
	end
	-- chips (My Chips tab): kept as their source text, run by wireLinks
	if type(data.chips) == "table" then
		for i, c in ipairs(data.chips) do
			if i > (L.chips or 16) then break end
			if type(c) == "table" and type(c.src) == "string" then
				table.insert(out.chips, {
					name = type(c.name) == "string" and c.name:sub(1, 30) or ("Chip " .. i),
					src = c.src:sub(1, L.chipLen or 3000),
				})
			end
		end
	end
	local uniques, taken, ids = {}, {}, {}
	if type(data.ents) == "table" then
		for i, e in ipairs(data.ents) do
			if i > L.ents then break end
			local def = type(e) == "table" and Config.ENTITY_TYPES[e[1]]
			if def then
				local x, y, z = math.floor(tonumber(e[2]) or 0), math.floor(tonumber(e[3]) or 0), math.floor(tonumber(e[4]) or 0)
				local f = math.floor(tonumber(e[5]) or 4)
				local k = Config.Key(x, y, z)
				local slot = k .. "," .. f
				local o = Config.OFFS[f]
				local wallOk = o and not air[Config.Key(x + o[1], y + o[2], z + o[3])]
				local mountOk = Config.MountOk(def, f)
				local floorOk = not def.needsFloor or Config.DOORS_ANY_HEIGHT or not air[Config.Key(x, y - 1, z)]
				if air[k] and wallOk and mountOk and floorOk and not taken[slot] and not (def.mandatory and uniques[e[1]]) then
					taken[slot] = true
					uniques[e[1]] = true
					local variant = (e[1] == "cube" and type(e[7]) == "string") and e[7]:sub(1, 50) or false
					if e[1] == "prop" then variant = Config.ValidMeshValue(e[7]) and e[7] or false end
					local id = type(e[8]) == "string" and e[8]:sub(1, 16) or HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 8)
					if ids[id] then id = HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 8) end
					ids[id] = e[1]
					local span = def.span and tonumber(e[9]) and math.clamp(math.floor(tonumber(e[9])), 1, 60) or false
					local oo, opt = type(e[10]) == "table" and e[10] or {}, {}
					if type(oo.mode) == "string" then opt.mode = oo.mode:sub(1, 40) end
					if type(oo.startOn) == "boolean" then opt.startOn = oo.startOn end
					if type(oo.dropOnStart) == "boolean" then opt.dropOnStart = oo.dropOnStart end
					if type(oo.hide) == "boolean" then opt.hide = oo.hide end
					if oo.vis == "Antline" or oo.vis == "Signage" or oo.vis == "None" then opt.vis = oo.vis end
					if type(oo.free) == "boolean" and e[1] == "exit" then opt.free = oo.free end
					if oo.link == "Power" or oo.link == "Reverse" then opt.link = oo.link end
					if table.find(Config.DOOR_OPEN_STYLES, oo.open) and oo.open ~= "Asset" then opt.open = oo.open end
					if tonumber(oo.speed) then opt.speed = math.clamp(math.floor(tonumber(oo.speed)), 2, 40) end
					-- moving panels / crushers / sound blocks
					if tonumber(oo.dist) then opt.dist = math.clamp(math.floor(tonumber(oo.dist)), 1, 3) end
					if tonumber(oo.reach) then opt.reach = math.clamp(math.floor(tonumber(oo.reach)), 1, 4) end
					if type(oo.hold) == "boolean" then opt.hold = oo.hold end
					if type(oo.np) == "boolean" then opt.np = oo.np end
					if tonumber(oo.pitch) then opt.pitch = math.clamp(math.floor(tonumber(oo.pitch)), -24, 24) end
					if tonumber(oo.volume) then opt.volume = math.clamp(tonumber(oo.volume), 0.1, 3) end
					if type(oo.audio) == "string" and #oo.audio <= 80 and not oo.audio:find("[%c]") then opt.audio = oo.audio end
					if tonumber(oo.linger) and table.find(Config.LINGER_TIMES, tonumber(oo.linger)) then opt.linger = tonumber(oo.linger) end
					if tonumber(oo.power) and table.find(Config.PUSH_STRENGTHS, tonumber(oo.power)) then opt.power = tonumber(oo.power) end
					if Config.ValidLabel(oo.label) then opt.label = oo.label end
					if tonumber(oo.scale) then opt.scale = math.clamp(tonumber(oo.scale), 0.25, 4) end
					if tonumber(oo.spin) then opt.spin = math.floor(tonumber(oo.spin)) % 360 end
					for _, ok in ipairs({ "ox", "oy", "oz" }) do
						if tonumber(oo[ok]) then opt[ok] = math.clamp(tonumber(oo[ok]), -Config.CELL, Config.CELL) end
					end
					if tonumber(oo.timer) then opt.timer = math.clamp(math.floor(tonumber(oo.timer)), 1, 30) end
					for _, gk in ipairs({ "gx0", "gx1", "gz0", "gz1" }) do
						if tonumber(oo[gk]) then opt[gk] = math.clamp(math.floor(tonumber(oo[gk])), 0, 28) end
					end
					if tonumber(oo.fx) and tonumber(oo.fy) and tonumber(oo.fz) and tonumber(oo.ff) then
						opt.fx = math.clamp(math.floor(tonumber(oo.fx)), -60, 60)
						opt.fy = math.clamp(math.floor(tonumber(oo.fy)), -60, 60)
						opt.fz = math.clamp(math.floor(tonumber(oo.fz)), -60, 60)
						opt.ff = math.clamp(math.floor(tonumber(oo.ff)), 1, 6)
					end
					if tonumber(oo.arc) then opt.arc = math.clamp(math.floor(tonumber(oo.arc)), 2, 200) end
					table.insert(out.ents, { e[1], x, y, z, f, math.floor(tonumber(e[6]) or 0) % 4, variant, id, span, next(opt) and opt or false })
				end
			end
		end
	end
	if type(data.links) == "table" then
		local seen = {}
		for i, l in ipairs(data.links) do
			if i > 150 then break end
			if type(l) == "table" and type(l[1]) == "string" and type(l[2]) == "string" and l[1] ~= l[2] then
				local a, b = ids[l[1]], ids[l[2]]
				local pair = l[1] .. ">" .. l[2]
				if a and b and Config.CanSource(a) and Config.CanTarget(b) and not seen[pair] then
					seen[pair] = true
					table.insert(out.links, { l[1], l[2] })
				end
			end
		end
	end
	if not (uniques.entry and uniques.exit) then return nil, "The chamber needs its Entry Door and Exit Door." end
	return out
end

-- the cube dropper model inside an item (TestElementsServer runs that one)
local function dropperIn(t)
	if CollectionService:HasTag(t, "CubeDropper") then return t end
	for _, d in ipairs(t:GetDescendants()) do
		if d:IsA("Model") and (CollectionService:HasTag(d, "CubeDropper") or d.Name:lower():find("dropper")) then return d end
	end
	return t
end

-- antlines (dotted lines over the panels) or signs for one link; recoloured blue / orange by the source's state
local function drawConnection(root, air, ea, eb, origin)
	local vis = (type(ea[10]) == "table" and ea[10].vis) or "Antline"
	local parts = {}
	local folder = root:FindFirstChild("Antlines") or Instance.new("Folder")
	folder.Name = "Antlines"
	folder.Parent = root
	if vis == "Antline" then
		local segs = Config.AntlinePath(air, { ea[2], ea[3], ea[4], ea[5] }, { eb[2], eb[3], eb[4], eb[5] }, origin, 0.06)
		if segs then
			for _, d in ipairs(Config.AntlineDots(segs)) do
				-- corners return the dot AND its hollow ring: only the dot gets recoloured
				local dot = Config.AntlineDot(d.cf, d.corner, Config.ANT_OFF, folder)
				table.insert(parts, dot)
			end
		end
	elseif vis == "Signage" then
		for _, e in ipairs({ ea, eb }) do
			local sign = Config.BuildSign(Config.ItemFrame(origin, e), folder)
			table.insert(parts, sign:FindFirstChild("Light"))
		end
	end
	return parts
end

local updateZones -- forward (ZONES below)
local function isOn(s)
	return s:GetAttribute("Pressed") == true or s:GetAttribute("PressesButton") == true
end

-- Wires up a built chamber. Sources report on their item model ("Pressed"). Logic gates work out their output from
-- their inputs and set their own "Pressed". Every other item turns on when ALL of its inputs are on: flips from its
-- start state (Config.LINK_DEFAULT_ON / "Start enabled"), flips a funnel's direction, or makes a dropper drop.
local runChips -- forward (CHIPS below)
local function wireLinks(root, links, data, origin, slot)
	if not root then return end
	links = type(links) == "table" and links or {}
	local air, entOf = {}, {}
	for _, c in ipairs(data and data.air or {}) do air[Config.Key(c[1], c[2], c[3])] = true end
	for _, e in ipairs(data and data.ents or {}) do if e[8] then entOf[e[8]] = e end end
	local byId = {}
	for _, d in ipairs(root:GetDescendants()) do
		local id = d:GetAttribute("EntId")
		if id and d:IsA("Model") and not byId[id] then byId[id] = d end
	end

	-- antlines / signs, painted by their source
	local linkParts = {}
	for _, l in ipairs(links) do
		local ea, eb, s = entOf[l[1]], entOf[l[2]], byId[l[1]]
		if ea and eb and s then
			local ok, parts = pcall(drawConnection, root, air, ea, eb, origin)
			if ok then
				linkParts[s] = linkParts[s] or {}
				for _, p in ipairs(parts) do table.insert(linkParts[s], p) end
			else
				warn("[PortalServer] antline:", parts)
			end
		end
	end
	for s, parts in pairs(linkParts) do
		local function paint()
			local on = isOn(s)
			for _, p in ipairs(parts) do
				if p and p.Parent and p.Name ~= "AntDotHole" then p.Color = on and Config.ANT_ON or Config.ANT_OFF end
			end
		end
		s:GetAttributeChangedSignal("Pressed"):Connect(paint)
		s:GetAttributeChangedSignal("PressesButton"):Connect(paint)
		paint()
	end

	-- who drives what
	local inputsOf, gates, targets = {}, {}, {}
	for _, d in pairs(byId) do
		if d:GetAttribute("Kind") == "gate" then
			inputsOf[d] = {}
			table.insert(gates, d)
		end
	end
	for _, l in ipairs(links) do
		local s, t = byId[l[1]], byId[l[2]]
		if s and t and s ~= t then
			if not inputsOf[t] then
				inputsOf[t] = {}
				table.insert(targets, t)
			end
			table.insert(inputsOf[t], s)
		end
	end

	-- gate panels: the light shows the output
	local function paintGate(g)
		local light = g:FindFirstChild("Light", true)
		if light and light:IsA("BasePart") and not g:GetAttribute("Hidden") then
			light.Color = isOn(g) and Config.ANT_ON or Config.ANT_OFF
		end
	end

	local state, pendingOff, delayToken = {}, {}, {}
	local function applyNow(t, on, first)
		local kind = t:GetAttribute("Kind")
		if kind == "cubedropper" then
			-- every time the inputs turn on: the old cube fizzles and a new one drops (TestElementsServer)
			if on and not first then dropperIn(t):SetAttribute("Drop", true) end
		elseif kind == "delay" then
			-- delay relay: its output follows its inputs, Delay seconds later
			local token = {}
			delayToken[t] = token
			if first then
				t:SetAttribute("Pressed", on)
			else
				task.delay(t:GetAttribute("Delay") or 1, function()
					if delayToken[t] == token and t.Parent then t:SetAttribute("Pressed", on) end
				end)
			end
		elseif kind == "tbeam" and t:GetAttribute("FunnelLink") ~= "Power" then
			Config.SetAll(t, "Reversed", (t:GetAttribute("BaseReversed") == true) ~= on)
		elseif kind == "tbeam" then
			-- powered by its button: off while the button is up (unless "Start enabled" flips that)
			local startOpt = t:GetAttribute("StartOpt")
			Config.SetAll(t, "Enabled", ((startOpt ~= nil) and startOpt or false) ~= on)
		else
			local startOpt = t:GetAttribute("StartOpt")
			local startOn = (startOpt ~= nil) and startOpt or (Config.LINK_DEFAULT_ON[kind] == true)
			Config.SetAll(t, "Enabled", startOn ~= on)
		end
	end
	local function apply(t, on)
		if state[t] == on then
			pendingOff[t] = nil -- back on before the linger ran out: stay on
			return
		end
		local first = state[t] == nil
		-- "Stay on after release": keep it on for Linger seconds after the inputs let go
		local linger = t:GetAttribute("Linger")
		if not first and not on and type(linger) == "number" and linger > 0 then
			if pendingOff[t] then return end
			local token = {}
			pendingOff[t] = token
			task.delay(linger, function()
				if pendingOff[t] ~= token or not t.Parent then return end
				pendingOff[t] = nil
				state[t] = false
				applyNow(t, false, false)
			end)
			return
		end
		pendingOff[t] = nil
		state[t] = on
		applyNow(t, on, first)
	end

	local busy, again = false, false
	local function evaluate()
		if busy then again = true return end
		busy = true
		repeat
			again = false
			-- gates feeding gates: go round until nothing changes (a loop of gates just stops after 20 passes)
			for _ = 1, 20 do
				local changed = false
				for _, g in ipairs(gates) do
					local ins = inputsOf[g]
					local on = 0
					for _, s in ipairs(ins) do if isOn(s) then on += 1 end end
					local out = Config.GateResult(g:GetAttribute("GateMode"), on, #ins)
					if isOn(g) ~= out then
						g:SetAttribute("Pressed", out)
						paintGate(g)
						changed = true
					end
				end
				if not changed then break end
			end
			for _, t in ipairs(targets) do
				if t:GetAttribute("Kind") ~= "gate" then
					local ins = inputsOf[t]
					local all = #ins > 0
					for _, s in ipairs(ins) do
						if not isOn(s) then all = false break end
					end
					apply(t, all)
				end
			end
		until not again
		busy = false
	end

	for _, t in ipairs(targets) do t:SetAttribute("Linked", true) end
	local watched = {}
	for _, ins in pairs(inputsOf) do
		for _, s in ipairs(ins) do
			if not watched[s] and s:GetAttribute("Kind") ~= "gate" then
				watched[s] = true
				s:GetAttributeChangedSignal("Pressed"):Connect(evaluate)
				s:GetAttributeChangedSignal("PressesButton"):Connect(evaluate)
			end
		end
	end
	for _, g in ipairs(gates) do paintGate(g) end
	evaluate()
	if type(data and data.chips) == "table" and #data.chips > 0 then runChips(root, data, byId, slot) end
end

-- ==========================================
-- CHIPS (programs from the editor's My Chips tab, see PortalConfig "CHIPS")
-- ==========================================
local lastLockedToast = {}
local function toast(player, text, kind)
	Push:FireClient(player, "Toast", { text = text, kind = kind })
end

runChips = function(root, data, byId, slot)
	-- label -> item model
	local byLabel = {}
	for _, e in ipairs(data.ents or {}) do
		local l = Config.LabelOf(e)
		if l and e[8] and byId[e[8]] then byLabel[l:lower()] = byId[e[8]] end
	end
	local function item(label) return label and byLabel[label:lower()] end
	local function alive() return root.Parent ~= nil end

	-- variables: shared by every chip in this chamber, start at 0
	local vars = {}
	local fxWindow, fxCount = 0, 0
	local started = os.clock()
	local callRules = {} -- [name] = { rule, ... }  ("when call <name>")
	local function value(word)
		if word == nil then return 0 end
		local n = tonumber(word)
		if n then return n end
		local lw = word:lower()
		if lw == "true" then return 1 elseif lw == "false" then return 0 end
		if lw == "time" then return math.floor((os.clock() - started) * 10) / 10 end
		if lw == "players" then return #slotPlayers(slot) end
		local t = item(word)
		if t then -- an item: 1 when it's pressed / on / open
			return (isOn(t) or t:GetAttribute("Enabled") == true or t:GetAttribute("Open") == true) and 1 or 0
		end
		local v = vars[lw]
		if type(v) == "boolean" then return v and 1 or 0 end
		return tonumber(v) or 0
	end
	local function compare(a, cmp, b)
		if cmp == "==" then return a == b elseif cmp == "!=" then return a ~= b
		elseif cmp == "<" then return a < b elseif cmp == ">" then return a > b
		elseif cmp == "<=" then return a <= b elseif cmp == ">=" then return a >= b end
		return false
	end

	-- faith plates: where the plate is and how it throws (the attributes BuildEntity put on it)
	local function plateOf(t)
		for _, d in ipairs(t:GetDescendants()) do
			if d:GetAttribute("StraightUp") ~= nil then return d end
		end
		return t
	end
	local function launchVelocity(el, p0)
		local g = workspace.Gravity
		if el:GetAttribute("StraightUp") ~= false then
			local h = tonumber(el:GetAttribute("UpHeight")) or 25
			return Vector3.new(0, math.sqrt(2 * g * math.max(h, 2)), 0)
		end
		local aim, apex = el:GetAttribute("AimPoint"), tonumber(el:GetAttribute("ApexY"))
		if typeof(aim) ~= "Vector3" or not apex then return Vector3.new(0, math.sqrt(2 * g * 25), 0) end
		local vy = math.sqrt(2 * g * math.max(apex - p0.Y, 2))
		local t = vy / g + math.sqrt(2 * math.max(apex - aim.Y, 0) / g)
		return Vector3.new((aim.X - p0.X) / t, vy, (aim.Z - p0.Z) / t)
	end
	local launchParams = OverlapParams.new()
	launchParams.FilterType = Enum.RaycastFilterType.Exclude
	local function launch(t)
		if t:GetAttribute("Enabled") == false then return end
		local el = plateOf(t)
		local cf, size
		if el:IsA("Model") then cf, size = el:GetBoundingBox() else cf, size = t:GetBoundingBox() end
		launchParams.FilterDescendantsInstances = { t }
		local box = Vector3.new(math.max(size.X, 6), 6, math.max(size.Z, 6))
		local seen = {}
		for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 + 3, 0)), box, launchParams)) do
			local root = part.AssemblyRootPart
			if root and not seen[root] and not root.Anchored then
				seen[root] = true
				local mdl = part:FindFirstAncestorOfClass("Model")
				local pl = mdl and Players:GetPlayerFromCharacter(mdl)
				local v = launchVelocity(el, root.Position)
				if pl then
					Push:FireClient(pl, "ChipFX", { op = "launch", v = v }) -- the player's own client moves their character
				elseif not root:GetAttribute("HeldBy") then
					if root:CanSetNetworkOwnership() then root:SetNetworkOwner(nil) end
					root.AssemblyLinearVelocity = v
				end
			end
		end
	end
	local function calc(a, o, b)
		if o == "+" then return a + b elseif o == "-" then return a - b elseif o == "*" then return a * b
		elseif o == "/" then return b ~= 0 and a / b or 0 elseif o == "%" then return b ~= 0 and a % b or 0
		elseif o == "min" then return math.min(a, b) elseif o == "max" then return math.max(a, b) end
		return 0
	end

	local act, runActs
	act = function(a, depth)
		if a.op == "set" then
			vars[a.var:lower()] = value(a.value)
			return
		elseif a.op == "add" then
			vars[a.var:lower()] = value(a.var) + (tonumber(a.value) or 0)
			return
		elseif a.op == "random" then
			vars[a.var:lower()] = math.random(a.lo or 1, math.max(a.hi or 6, a.lo or 1))
			return
		elseif a.op == "stop" then
			return "stop" -- run() ends the rule
		elseif a.op == "calc" then
			local r = calc(value(a.a), a.o, value(a.b))
			if r ~= r or r == math.huge or r == -math.huge then r = 0 end -- NaN / infinity
			vars[a.var:lower()] = r
			return
		elseif a.op == "until" then
			local deadline = os.clock() + 600
			while alive() and os.clock() < deadline and not compare(value(a.lhs), a.cmp, value(a.rhs)) do task.wait(0.1) end
			return
		elseif a.op == "call" then
			-- your own functions: runs each "when call <name>" rule here, then carries on
			if (depth or 0) >= 16 then warn("[PortalServer] chip: calls nested too deep (" .. a.name .. ")") return end
			for _, r in ipairs(callRules[a.name] or {}) do runActs(r.acts, (depth or 0) + 1) end
			return
		elseif a.op == "repeat" then
			for _ = 1, math.clamp(a.n or 1, 1, 50) do
				if not alive() or not a.act then return end
				local w = act(a.act, depth)
				if w == "stop" then return "stop" end
				if type(w) == "number" and w > 0 then task.wait(w) end
			end
			return
		elseif a.op == "if" then
			if compare(value(a.lhs), a.cmp, value(a.rhs)) then
				if a.act then return act(a.act, depth) end
			elseif a.elseAct then
				return act(a.elseAct, depth)
			end
			return
		elseif a.op == "wait" then
			return a.n or 0 -- the caller waits
		elseif Config.CHIP_FX[a.op] then
			-- effects: sent only to the players in this chamber (you, or you + your co-op partner); never gameplay
			local now = os.clock()
			if now - fxWindow > 1 then fxWindow, fxCount = now, 0 end
			fxCount += 1
			if fxCount > 20 then return end -- a chip spamming effects every frame gets cut off
			local text = a.text and a.text:gsub("{([%a_][%w_]*)}", function(n) return tostring(value(n)) end) or nil
			if (a.op == "music" or a.op == "sound") and text and text:lower() ~= "stop" then
				text = Config.AudioValue(text, data.audio) or text -- a name from File > Chamber audio = its id
			end
			for _, pl in ipairs(slotPlayers(slot)) do
				Push:FireClient(pl, "ChipFX", { op = a.op, text = text, n = a.n })
			end
			return
		end
		local t = item(a.target)
		local kind = t and t:GetAttribute("Kind")
		if a.op == "say" then
			local text = (a.text or ""):gsub("{([%a_][%w_]*)}", function(n) return tostring(value(n)) end)
			for _, pl in ipairs(slotPlayers(slot)) do toast(pl, text, "chip") end
		elseif not t then
			return
		elseif a.op == "drop" and kind == "cubedropper" then
			dropperIn(t):SetAttribute("Drop", true)
		elseif a.op == "reverse" and kind == "tbeam" then
			Config.SetAll(t, "Reversed", not (t:GetAttribute("Reversed") == true))
		elseif (a.op == "forward" or a.op == "backward") and kind == "tbeam" then
			Config.SetAll(t, "Reversed", a.op == "backward")
		elseif a.op == "speed" and kind == "tbeam" then
			Config.SetAll(t, "Speed", math.clamp(tonumber(a.n) or 13, 2, 40))
		elseif a.op == "launch" and kind == "faithplate" then
			launch(t)
		elseif a.op == "play" and Config.PLAYABLE[kind] then
			t:SetAttribute("Trigger", os.clock()) -- ChamberPiecesServer: note / music / crush / bounce
		elseif a.op == "color" and kind == "light" then
			local c = Config.LightColor(a.text)
			local glow = t:FindFirstChild("Glow", true)
			if c and glow then
				glow.Color = c
				local bulb = glow.Parent
				if bulb and bulb:IsA("BasePart") then bulb.Color = c end
			end
		elseif Config.ChipTargetOk(a.op, kind) then
			local now = t:GetAttribute("Enabled") == true
			local want = (a.op == "open" or a.op == "enable") or ((a.op == "toggle") and not now)
			Config.SetAll(t, "Enabled", want)
		end
	end

	-- runs a rule's lines in order (waits included); "stop" ends it
	runActs = function(acts, depth)
		for i, a in ipairs(acts) do
			if i > 200 or not alive() then return end
			local ok, w = pcall(act, a, depth)
			if not ok then warn("[PortalServer] chip:", w)
			elseif w == "stop" then return
			elseif type(w) == "number" and w > 0 then task.wait(w) end
		end
	end
	local function run(rule)
		task.spawn(runActs, rule.acts, 0)
	end

	-- functions first, so a "when start" in one chip can call one written in another
	local parsed = {}
	for _, chip in ipairs(data.chips) do
		local rules = Config.ParseChip(chip.src)
		table.insert(parsed, rules)
		for _, rule in ipairs(rules) do
			if rule.ev == "call" then
				callRules[rule.name] = callRules[rule.name] or {}
				table.insert(callRules[rule.name], rule)
			end
		end
	end
	for _, rules in ipairs(parsed) do
		for _, rule in ipairs(rules) do
			if rule.ev == "call" then
				-- (only runs when called)
			elseif rule.ev == "start" then
				run(rule)
			elseif rule.ev == "cond" then
				-- when <lhs> <compare> <rhs>: checked 10 times a second, runs each time it turns true
				task.spawn(function()
					local was = false
					while alive() do
						local now = compare(value(rule.lhs), rule.cmp, value(rule.rhs))
						if now and not was then run(rule) end
						was = now
						task.wait(0.1)
					end
				end)
			elseif rule.ev == "every" then
				task.spawn(function()
					while alive() do
						task.wait(math.max(rule.n or 1, 0.5))
						if alive() then run(rule) end
					end
				end)
			elseif rule.src then
				local s = item(rule.src)
				if s then
					local was = isOn(s)
					local function changed()
						local on = isOn(s)
						if on == was then return end
						was = on
						if (rule.ev == "pressed") == on then run(rule) end
					end
					s:GetAttributeChangedSignal("Pressed"):Connect(changed)
					s:GetAttributeChangedSignal("PressesButton"):Connect(changed)
				end
			end
		end
	end
end

-- ==========================================
-- TOOLBOX (Creator Store search for the editor's Textures / Meshes tabs)
-- ==========================================
-- Search uses InsertService:GetFreeDecals / GetFreeModels. Loading free models needs, in Studio:
-- select InsertService in the Explorer and tick AllowInsertFreeModels (Game Settings > Security too, if offered).
-- Loaded models are stripped of scripts and kept in ReplicatedStorage.PortalToolbox (Config.TOOLBOX_FOLDER).
local InsertService = game:GetService("InsertService")
local toolboxFolder = ReplicatedStorage:FindFirstChild(Config.TOOLBOX_FOLDER) or Instance.new("Folder")
toolboxFolder.Name = Config.TOOLBOX_FOLDER
toolboxFolder.Parent = ReplicatedStorage
local TOOLBOX_MAX_PARTS = 400
local toolboxSearchCache = {} -- [kind|query|page] = { t, list }
local toolboxLoading, toolboxFailed = {}, {}

local function loadToolboxAsset(id)
	id = math.floor(tonumber(id) or 0)
	if id <= 0 then return nil, "That isn't an asset id." end
	local have = toolboxFolder:FindFirstChild(tostring(id))
	if have then return have end
	if toolboxFailed[id] then return nil, toolboxFailed[id] end
	local t0 = os.clock()
	while toolboxLoading[id] and os.clock() - t0 < 20 do task.wait(0.1) end
	have = toolboxFolder:FindFirstChild(tostring(id))
	if have then return have end
	toolboxLoading[id] = true
	local ok, model = pcall(function() return InsertService:LoadAsset(id) end)
	toolboxLoading[id] = nil
	if not ok or not model then
		local err = "Couldn't load that asset. In Studio, select InsertService and turn on AllowInsertFreeModels."
		toolboxFailed[id] = err
		warn("[PortalServer] LoadAsset", id, model)
		return nil, err
	end
	local parts = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("Tool") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			parts += 1
			d.Anchored = true
		end
	end
	if parts > TOOLBOX_MAX_PARTS then
		model:Destroy()
		toolboxFailed[id] = "That model is too big (more than " .. TOOLBOX_MAX_PARTS .. " parts)."
		return nil, toolboxFailed[id]
	end
	model.Name = tostring(id)
	model.Parent = toolboxFolder
	return model
end

-- Meshes tab: a real MeshPart from a mesh asset id (AssetService:CreateMeshPartAsync works while the game runs),
-- optionally with a texture id. Kept in ReplicatedStorage.PortalToolbox as Config.MeshKey(id, tex).
local AssetService = game:GetService("AssetService")
local meshFailed = {}
local function loadMeshPart(id, tex)
	id = math.floor(tonumber(id) or 0)
	tex = tonumber(tex) and math.floor(tonumber(tex)) or nil
	if id <= 0 then return nil, "That isn't a mesh id." end
	local key = Config.MeshKey(id, tex)
	local have = toolboxFolder:FindFirstChild(key)
	if have then return have end
	if meshFailed[key] then return nil, meshFailed[key] end
	local t0 = os.clock()
	while toolboxLoading[key] and os.clock() - t0 < 20 do task.wait(0.1) end
	have = toolboxFolder:FindFirstChild(key)
	if have then return have end
	toolboxLoading[key] = true
	local ok, mp = pcall(function()
		return AssetService:CreateMeshPartAsync("rbxassetid://" .. id, {
			CollisionFidelity = Enum.CollisionFidelity.Hull, RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	toolboxLoading[key] = nil
	if not ok or not mp then
		warn("[PortalServer] CreateMeshPartAsync", id, mp)
		meshFailed[key] = "Couldn't make a MeshPart from that id. Use a Mesh asset id (not a model or decal id)."
		return nil, meshFailed[key]
	end
	if tex then pcall(function() mp.TextureID = "rbxassetid://" .. tex end) end
	mp.Anchored = true
	mp.Name = key
	mp.Parent = toolboxFolder
	return mp
end

-- Meshes tab, TOOLBOX: Roblox only lets a game search the Toolbox for models (InsertService:GetFreeModels), so a
-- picked item is loaded and cut down to ONLY its MeshParts (with their SurfaceAppearances / textures). Everything
-- else - scripts, sounds, plain parts, junk - is thrown away. One MeshPart is used as-is, several stay in a Model.
local function loadToolboxMeshes(id)
	id = math.floor(tonumber(id) or 0)
	local key = "tbmesh_" .. id
	local have = toolboxFolder:FindFirstChild(key)
	if have then return have end
	local m, err = loadToolboxAsset(id)
	if not m then return nil, err end
	local meshes = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("MeshPart") then table.insert(meshes, d) end
	end
	if #meshes == 0 then return nil, "That Toolbox item has no MeshParts in it. Pick another one." end
	local out
	if #meshes == 1 then
		out = meshes[1]:Clone()
	else
		out = Instance.new("Model")
		for _, mp in ipairs(meshes) do mp:Clone().Parent = out end
	end
	-- only the look of each MeshPart survives: SurfaceAppearance, textures, decals
	for _, part in ipairs(out:IsA("MeshPart") and { out } or out:GetChildren()) do
		for _, c in ipairs(part:GetChildren()) do
			if not (c:IsA("SurfaceAppearance") or c:IsA("Texture") or c:IsA("Decal")) then c:Destroy() end
		end
		part.Anchored = true
	end
	out.Name = key
	out.Parent = toolboxFolder
	return out
end

-- Meshes tab search: the Creator Store API with searchCategoryType = MeshPart, so ONLY meshes come back (not
-- models, not the whole Toolbox). Pages: the API pages with tokens, kept here per search.
local storeTokens = {} -- [query] = { [page] = pageToken }
local function creatorStoreKey()
	local ok, secret = pcall(function() return HttpService:GetSecret(Config.CREATOR_STORE_KEY_SECRET) end)
	return ok and secret or nil
end
local function searchStoreMeshes(q, page)
	local token = nil
	if page > 0 then
		token = storeTokens[q] and storeTokens[q][page]
		if not token then return true, {} end -- no more pages
	end
	local url = Config.CREATOR_STORE_SEARCH_URL .. "?searchCategoryType=MeshPart&maxPageSize=30&query=" .. HttpService:UrlEncode(q)
		.. (token and ("&pageToken=" .. HttpService:UrlEncode(token)) or "")
	local headers = {}
	local key = creatorStoreKey()
	if key then headers["x-api-key"] = key end
	local ok, res = pcall(function() return HttpService:RequestAsync({ Url = url, Method = "GET", Headers = headers }) end)
	if not ok then
		warn("[PortalServer] Creator Store search:", res)
		return false, "Couldn't reach the Creator Store. Turn on Game Settings > Security > Allow HTTP Requests."
	end
	if not res.Success then
		warn("[PortalServer] Creator Store search:", res.StatusCode, res.Body)
		if res.StatusCode == 401 or res.StatusCode == 403 then
			return false, "The Creator Store needs an API key: make an Open Cloud key with Creator Store read access and add it as the secret \""
				.. Config.CREATOR_STORE_KEY_SECRET .. "\" (see the README)."
		end
		return false, ("The Creator Store search failed (%d)."):format(res.StatusCode)
	end
	local okJ, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
	if not okJ or type(data) ~= "table" then return false, "The Creator Store sent something unreadable." end
	local list = {}
	for _, item in ipairs(type(data.creatorStoreAssets) == "table" and data.creatorStoreAssets or {}) do
		local a = type(item.asset) == "table" and item.asset or item
		local id = tonumber(a.id)
		if id then
			local creator = type(item.creator) == "table" and (item.creator.name or "") or ""
			table.insert(list, { id = id, name = tostring(a.name or a.displayName or id):sub(1, 60), creator = tostring(creator) })
		end
	end
	storeTokens[q] = storeTokens[q] or {}
	storeTokens[q][page + 1] = type(data.nextPageToken) == "string" and data.nextPageToken ~= "" and data.nextPageToken or nil
	return true, list
end

local function toolboxSearch(player, arg)
	arg = type(arg) == "table" and arg or {}
	local kind = arg.kind == "textures" and "textures" or "meshes"
	local q = tostring(arg.q or ""):sub(1, 50)
	local page = math.clamp(math.floor(tonumber(arg.page) or 0), 0, 20)
	local key = kind .. "|" .. q:lower() .. "|" .. page
	local c = toolboxSearchCache[key]
	if c and os.clock() - c.t < 300 then return true, c.list end
	if kind == "meshes" then
		local okS, list = searchStoreMeshes(q, page)
		if okS then toolboxSearchCache[key] = { t = os.clock(), list = list } end
		return okS, list
	end
	local ok, res = pcall(function()
		if kind == "textures" then return InsertService:GetFreeDecals(q, page) end
		return InsertService:GetFreeModels(q, page)
	end)
	if not ok then
		warn("[PortalServer] toolbox search", res)
		return false, "The Toolbox search isn't available right now."
	end
	local list = {}
	local set = type(res) == "table" and res[1]
	for _, r in ipairs(type(set) == "table" and set.Results or {}) do
		if #list >= 40 then break end
		if tonumber(r.AssetId) then
			table.insert(list, { id = tonumber(r.AssetId), name = tostring(r.Name or r.AssetId):sub(1, 60), creator = tostring(r.CreatorName or "") })
		end
	end
	toolboxSearchCache[key] = { t = os.clock(), list = list }
	return true, list
end

local function toolboxLoad(player, arg)
	if type(arg) ~= "table" then return false end
	if arg.kind == "storemesh" then
		-- a Creator Store MeshPart: a real MeshPart straight from its id, or (if that id won't make one) the
		-- asset loaded and cut down to its MeshParts
		local mp = loadMeshPart(arg.id, nil)
		if mp then return true, { value = "mesh:" .. math.floor(tonumber(arg.id)) } end
		local mm, merr = loadToolboxMeshes(arg.id)
		if mm then return true, { value = "tbmesh:" .. math.floor(tonumber(arg.id)) } end
		return false, merr or "Couldn't load that mesh."
	end
	if arg.kind == "toolboxmesh" then
		local mm, merr = loadToolboxMeshes(arg.id)
		if not mm then return false, merr end
		return true, { value = "tbmesh:" .. math.floor(tonumber(arg.id)) }
	end
	if arg.kind == "mesh" then
		local mp, merr = loadMeshPart(arg.id, arg.tex)
		if not mp then return false, merr end
		return true, { value = "mesh:" .. math.floor(tonumber(arg.id)) .. (tonumber(arg.tex) and (":" .. math.floor(tonumber(arg.tex))) or "") }
	end
	local m, err = loadToolboxAsset(arg.id)
	if not m then return false, err end
	if arg.kind == "textures" then
		-- a decal asset holds the image id we need for a Texture
		local t = m:FindFirstChildWhichIsA("Decal", true) or m:FindFirstChildWhichIsA("Texture", true)
		local img = t and t.Texture:match("%d+")
		if not img then return false, "That asset isn't an image." end
		return true, { value = "id:" .. img }
	end
	return true, { value = "asset:" .. math.floor(tonumber(arg.id)) }
end

-- Toolbox meshes a chamber uses have to be loaded before it's built
local function preloadToolbox(data)
	for _, e in ipairs(data and data.ents or {}) do
		local v = e[1] == "prop" and type(e[7]) == "string" and e[7] or ""
		local aid = v:match("^asset:(%d+)$")
		if aid then loadToolboxAsset(aid) end
		local tbid = v:match("^tbmesh:(%d+)$")
		if tbid then loadToolboxMeshes(tbid) end
		local mid, tid = v:match("^mesh:(%d+):?(%d*)$")
		if mid then loadMeshPart(mid, tid ~= "" and tid or nil) end
	end
end

local function buildChamberMap(data, name, player)
	preloadToolbox(data)
	for _, pl in ipairs(slotPlayers(acquireSlot(player))) do Push:FireClient(pl, "ChipFX", { op = "reset" }) end
	clearActive(player)
	local slot = acquireSlot(player)
	local origin = Config.ChamberOrigin(slot)
	local folder = activeFolder(player)
	local model = Config.BuildChamber(data, folder, origin, {})
	folder:SetAttribute("Map", name)
	wireLinks(model, data.links, data, origin, slot)
	return model
end

local function sortWorkshop(list, sort, player, friendIds)
	local out = {}
	local friends = {}
	for _, id in ipairs(friendIds or {}) do friends[tostring(id)] = true end
	local p = profiles[player]
	local follows = {}
	for _, id in ipairs(p and p.follows or {}) do follows[tostring(id)] = true end
	for _, m in ipairs(list) do
		local ok = true
		if sort == "FriendsFavorites" or sort == "FriendsTopRated" or sort == "FriendsCreations" then
			ok = friends[tostring(m.authorId)] == true
		elseif sort == "FollowedMostRecent" then
			ok = follows[tostring(m.authorId)] == true
		end
		if ok then table.insert(out, m) end
	end
	local function score(m)
		local up, down = m.up or 0, m.down or 0
		return (up + 1) / (up + down + 2)
	end
	if sort == "TopRated" or sort == "FriendsTopRated" or sort == "FriendsFavorites" then
		table.sort(out, function(a, b) return score(a) > score(b) end)
	elseif sort == "MostPopular" then
		table.sort(out, function(a, b) return (a.plays or 0) > (b.plays or 0) end)
	else
		table.sort(out, function(a, b) return (a.created or 0) > (b.created or 0) end)
	end
	local trimmed = {}
	for i = 1, math.min(#out, 40) do trimmed[i] = out[i] end
	return trimmed
end

local function metaById(id)
	for _, m in ipairs(workshopIndex()) do
		if m.id == id then return m end
	end
end

-- ==========================================
-- CO-OP
-- ==========================================
local pendingInvites = {}
local queued = {} -- [player] = { chamber = workshop id or nil }
local CoopRun = {} -- co-op runs: the vote, chamber lists, speedruns (filled in further down)
local QUEUE = nil
pcall(function() QUEUE = MemoryStoreService:GetSortedMap("PortalCoopQueue") end)

-- opts.chamber: a Workshop co-op chamber the pair goes straight into (invite / quick match from the Workshop);
-- without it they go to the co-op hub and vote on what to play
local function startCoop(a, b, opts)
	opts = type(opts) == "table" and opts or {}
	queued[a], queued[b] = nil, nil
	if QUEUE then
		pcall(function() QUEUE:RemoveAsync(tostring(a.UserId)) end)
		pcall(function() QUEUE:RemoveAsync(tostring(b.UserId)) end)
	end
	a:SetAttribute("CoopPartner", b.UserId)
	b:SetAttribute("CoopPartner", a.UserId)
	a:SetAttribute("CoopColor", "Blue")
	b:SetAttribute("CoopColor", "Orange")
	unlock(a, "COOP_FRIEND")
	unlock(b, "COOP_FRIEND")
	Push:FireClient(a, "CoopStart", { partner = b.Name, color = "Blue", chamber = opts.chamber })
	Push:FireClient(b, "CoopStart", { partner = a.Name, color = "Orange", chamber = opts.chamber })
	task.delay(1, function()
		-- the pair share one instance (a's), b's old one is cleaned up if nobody else is in it
		joinSlot(b, acquireSlot(a))
		local root = not opts.chamber and loadMap(Config.COOP_HUB_MAP, true, a) or nil
		local ready = 0
		for _, pl in ipairs({ a, b }) do
			task.spawn(function()
				pl:SetAttribute("Chapter", nil)
				local color = pl:GetAttribute("CoopColor")
				-- blue plays Atlas, orange plays P-body (RigChangerServer), then goes to their colour's spawn
				local oldChar = pl.Character
				if rigChange(pl, "Equip", { rig = Config.COOP_RIGS[color], source = "Coop", silent = true }) then
					waitForRig(pl, oldChar, 6)
				end
				local s = root and findSpawn(root, color)
				if s and pl.Parent then placeCharacter(pl, spawnCF(s)) end
				ready += 1
			end)
		end
		local t0 = os.clock()
		while ready < 2 and os.clock() - t0 < 8 do task.wait(0.1) end
		if not (a.Parent and b.Parent) then return end
		if opts.chamber then
			CoopRun.begin(a, b, { source = "custom", mode = "normal", single = true, ids = { opts.chamber } })
		else
			task.wait(1.5)
			CoopRun.openVote(a, b) -- Built-in or Custom chambers, Normal or Speedrun
		end
	end)
end

-- leaving: true when the player is leaving the game (no point changing their character back)
local function endCoop(player, leaving)
	if CoopRun.stop then CoopRun.stop(player) end
	local partnerId = player:GetAttribute("CoopPartner")
	if partnerId then leaveSlot(player) end -- the partner keeps the shared instance, this player gets a fresh one
	player:SetAttribute("CoopPartner", nil)
	player:SetAttribute("CoopColor", nil)
	if partnerId then
		-- no longer Atlas / P-body: back to Chell (or the normal character if co-op gave them the gun)
		if not leaving then
			local oldChar = player.Character
			if rigChange(player, "Restore", { source = "Coop" }) then waitForRig(player, oldChar, 5) end
		end
		local other = Players:GetPlayerByUserId(partnerId)
		if other then
			other:SetAttribute("CoopPartner", nil)
			other:SetAttribute("CoopColor", nil)
			rigChange(other, "Restore", { source = "Coop" })
			Push:FireClient(other, "CoopEnded", { partner = player.Name })
		end
	end
end

local MATCH_TOPIC = "PortalCoopMatch"
task.spawn(pcall, function() -- SubscribeAsync yields; don't hold up the rest of the script (PlayerAdded etc.)
	MessagingService:SubscribeAsync(MATCH_TOPIC, function(msg)
		local d = msg.Data
		if type(d) ~= "table" then return end
		for _, uid in ipairs({ d.a, d.b }) do
			local pl = Players:GetPlayerByUserId(uid)
			if pl and queued[pl] then
				queued[pl] = nil
				Push:FireClient(pl, "CoopFound", {})
				pcall(function()
					TeleportService:TeleportToPrivateServer(game.PlaceId, d.code, { pl }, nil, { coop = true, a = d.a, b = d.b, chamber = d.chamber })
				end)
			end
		end
	end)
end)

task.spawn(function()
	while true do
		task.wait(2.5)
		local here = {}
		for pl in pairs(queued) do
			if pl.Parent then table.insert(here, pl) else queued[pl] = nil end
		end
		-- pairs: same Workshop chamber, or one of them doesn't mind (plays the other's chamber)
		local function fits(x, y)
			local cx, cy = queued[x] and queued[x].chamber, queued[y] and queued[y].chamber
			return cx == nil or cy == nil or cx == cy
		end
		local paired = true
		while paired and #here >= 2 do
			paired = false
			for i = 1, #here do
				for j = i + 1, #here do
					local a, b = here[i], here[j]
					if fits(a, b) then
						local chamber = (queued[a] and queued[a].chamber) or (queued[b] and queued[b].chamber)
						table.remove(here, j)
						table.remove(here, i)
						startCoop(a, b, { chamber = chamber })
						paired = true
						break
					end
				end
				if paired then break end
			end
		end
		if QUEUE and #here >= 1 then
			local me = here[1]
			local myChamber = queued[me] and queued[me].chamber
			pcall(function() QUEUE:SetAsync(tostring(me.UserId), { job = game.JobId, t = os.time(), chamber = myChamber }, 120) end)
			local ok, entries = pcall(function() return QUEUE:GetRangeAsync(Enum.SortDirection.Ascending, 10) end)
			if ok and entries then
				for _, e in ipairs(entries) do
					local other = tonumber(e.key)
					local theirs = type(e.value) == "table" and e.value.chamber or nil
					if other and other ~= me.UserId and type(e.value) == "table" and e.value.job ~= game.JobId
						and (theirs == nil or myChamber == nil or theirs == myChamber) then
						local claimed = false
						pcall(function()
							QUEUE:UpdateAsync(e.key, function(v)
								if v == nil then return nil end
								claimed = true
								return nil
							end, 30)
							if claimed then QUEUE:RemoveAsync(e.key) end
						end)
						if claimed then
							local okR, code = pcall(function() return TeleportService:ReserveServer(game.PlaceId) end)
							if okR then
								pcall(function() MessagingService:PublishAsync(MATCH_TOPIC, { a = me.UserId, b = other, code = code,
									chamber = myChamber or theirs }) end)
							end
							break
						end
					end
				end
			end
		end
	end
end)

local arrivals = {}
local function checkArrival(player)
	local data = player:GetJoinData()
	local td = data and data.TeleportData
	if type(td) == "table" and td.coop then
		arrivals[player.UserId] = player
		local otherId = (td.a == player.UserId) and td.b or td.a
		local other = arrivals[otherId]
		if other and other.Parent then
			arrivals[player.UserId], arrivals[otherId] = nil, nil
			task.delay(2, startCoop, other, player, { chamber = type(td.chamber) == "string" and td.chamber or nil })
		end
	end
end

-- ==========================================
-- LEADERBOARDS
-- ==========================================
local function lbStore(chamber, kind)
	return getStore("PortalLB_" .. chamber .. "_" .. kind, true)
end

local function submitChallenge(player, chamber, portals, seconds)
	for kind, value in pairs({ portals = portals, time = math.floor(seconds * 100) }) do
		local store = lbStore(chamber, kind)
		if store then
			retry(function()
				store:UpdateAsync(tostring(player.UserId), function(old)
					if old and old <= value then return nil end
					return value
				end)
			end, 2)
		end
	end
end

-- ==========================================
-- STORE
-- ==========================================
local function owns(p, id)
	return table.find(p.inventory, id) ~= nil
end

local function grantItem(p, item)
	if item.grants then
		for _, g in ipairs(item.grants) do table.insert(p.inventory, g) end
	else
		table.insert(p.inventory, item.id)
	end
end

local productToItem = {}
for _, it in ipairs(Config.STORE) do
	if it.productId and it.productId ~= 0 then productToItem[it.productId] = it end
end

-- NOTE: only ONE script in the game may set ProcessReceipt. If you already have one, move this logic into it.
MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local item = productToItem[info.ProductId]
	if not player or not item then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local p = getProfile(player, 10)
	if not p then return Enum.ProductPurchaseDecision.NotProcessedYet end
	p.receipts = p.receipts or {}
	if not p.receipts[info.PurchaseId] then
		p.receipts[info.PurchaseId] = true
		grantItem(p, item)
		saveProfile(player)
	end
	Push:FireClient(player, "Inventory", { inventory = p.inventory })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function applyCosmetics(player)
	local p = profiles[player]
	if not p then return end
	local color = (player:GetAttribute("CoopColor") or "Blue"):lower()
	local eq = p.equipped[color] or {}
	for _, slot in ipairs({ "head", "flag", "gesture", "skin" }) do
		player:SetAttribute("Cosmetic_" .. slot, eq[slot])
	end
end

-- ==========================================
-- EDITOR HELPERS
-- ==========================================
local function parkPos(player) return Config.ChamberOrigin(acquireSlot(player)) + Vector3.new(0, -80, 0) end
local testSpawn = {} -- [player] = CFrame of the entry door spawn for the current playtest

local function findDraft(p, id)
	for i, d in ipairs(p.drafts) do
		if d.id == id then return d, i end
	end
end

local function park(player)
	local root = waitRoot(player, 5)
	if root then
		placeCharacter(player, CFrame.new(parkPos(player)))
		root = charRoot(player)
		if root then root.Anchored = true end
	end
end

local function draftSummary(d)
	local m = d.publishedId and metaById(d.publishedId)
	return {
		id = d.id, title = d.title, created = d.created, modified = d.modified,
		publishedId = d.publishedId, publishedAt = d.publishedAt, up = m and m.up or 0, down = m and m.down or 0,
	}
end

-- spawn in front of the entry door (its PlayerSpawn part, which PortalConfig puts just outside the door model)
local function entrySpawnCF(model)
	if not model then return nil end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("Kind") == "entry" then
			local s = d:FindFirstChild("PlayerSpawn", true)
			if s and s:IsA("BasePart") then return spawnCF(s) end
		end
	end
	local s = findSpawn(model)
	return s and spawnCF(s)
end

-- ==========================================
-- REQUEST ACTIONS
-- ==========================================
local Actions = {}

function Actions.GetProfile(player)
	local p = getProfile(player, 25)
	if not p then return false, "Couldn't load your profile." end
	return true, {
		settings = p.settings, saves = summarizeSaves(p), maxChapter = p.maxChapter,
		achievements = p.achievements, progress = p.progress, inventory = p.inventory,
		equipped = p.equipped, queue = p.queue, follows = p.follows,
		chambers = #p.drafts, published = p.published,
	}
end

function Actions.SetSettings(player, s)
	local p = getProfile(player, 5)
	if not p or type(s) ~= "table" then return false end
	local clean, n = {}, 0
	for k, v in pairs(s) do
		n += 1
		if n > 64 then break end
		-- (custom editor styles / colours are a little longer)
		local maxLen = (k == "edCustomTheme" or k == "edCustomColors") and 200 or 60
		if type(k) == "string" and #k < 40 and (type(v) == "string" and #v < maxLen or type(v) == "number" or type(v) == "boolean") then
			clean[k] = v
		end
	end
	p.settings = clean
	markDirty(player)
	return true
end

function Actions.ClientAchievement(player, id)
	local def = Config.Achievement(id)
	if def and def.client then return true, unlock(player, id) end
	return false
end

function Actions.NewGame(player, index)
	local p = getProfile(player, 5)
	index = tonumber(index) or 1
	if not p then return false, "Profile not loaded." end
	if index > p.maxChapter then return false, "That chapter is still locked." end
	endCoop(player)
	return startChapter(player, index)
end

function Actions.ContinueGame(player)
	local p = getProfile(player, 5)
	if not p then return false, "Profile not loaded." end
	local s = latestSave(p)
	if s then return loadSave(player, s) end
	return startChapter(player, 1)
end

function Actions.LoadGame(player, id)
	local p = getProfile(player, 5)
	if not p then return false, "Profile not loaded." end
	for _, s in ipairs(p.saves) do
		if s.id == id then return loadSave(player, s) end
	end
	return false, "Save not found."
end

function Actions.LoadLastSave(player)
	local p = getProfile(player, 5)
	local s = p and latestSave(p)
	if not s then return false, "There are no saved games." end
	return loadSave(player, s)
end

function Actions.SaveGame(player, id)
	local entry, err = makeSave(player, id, false)
	if not entry then return false, err end
	return true, summarizeSaves(profiles[player])
end

function Actions.DeleteSave(player, id)
	local p = getProfile(player, 5)
	if not p then return false end
	for i, s in ipairs(p.saves) do
		if s.id == id then table.remove(p.saves, i) break end
	end
	markDirty(player)
	return true, summarizeSaves(p)
end

function Actions.DeveloperCommentary(player)
	player:SetAttribute("Commentary", true)
	return Actions.NewGame(player, 1)
end

function Actions.ExitToMainMenu(player)
	Push:FireClient(player, "ChipFX", { op = "reset" })
	endCoop(player)
	local wasEditor = player:GetAttribute("InEditor")
	if wasEditor then
		-- the editor only lent the gun (RigChangerServer ignores this if you already owned it)
		player:SetAttribute("InEditor", nil) -- first, so the respawn isn't parked under the editor
		player:SetAttribute("EditorPlaytest", nil)
		testSpawn[player] = nil
		if rigChange(player, "Restore", { source = "Editor" }) then waitForRig(player, player.Character, 4) end
	end
	if player:GetAttribute("WorkshopMap") then
		-- the gun was only lent for the Workshop chamber
		player:SetAttribute("WorkshopMap", nil)
		testSpawn[player] = nil
		if rigChange(player, "Restore", { source = "Workshop" }) then waitForRig(player, player.Character, 4) end
	end
	local root = charRoot(player)
	if root then root.Anchored = false end
	leaveSlot(player) -- the instance goes away once nobody is left in it
	testSpawn[player] = nil
	player:SetAttribute("Chapter", nil)
	player:SetAttribute("Commentary", nil)
	player:SetAttribute("ChallengeChamber", nil)
	player:SetAttribute("WorkshopMap", nil)
	player:SetAttribute("InEditor", nil)
	player:SetAttribute("EditorPlaytest", nil)
	sendToLobby(player)
	return true
end

function Actions.ChallengeMode(player, chamberId)
	local ch, course = Config.Chamber(chamberId)
	if not ch then
		course = Config.COURSES[1]
		ch = course and course.chambers[1]
		if not ch then return false, "No challenge chambers set up." end
	end
	if course.coop and not player:GetAttribute("CoopPartner") then return false, "This course needs a co-op partner." end
	local root = loadMap(ch.id, true, player)
	player:SetAttribute("Chapter", nil)
	player:SetAttribute("ChallengeChamber", ch.id)
	player:SetAttribute("ChallengeStart", os.clock())
	player:SetAttribute("ChallengePortals", 0)
	local s = findSpawn(root, player:GetAttribute("CoopColor"))
	if s then placeCharacter(player, spawnCF(s)) end
	return true
end
Actions.CoopChallenge = Actions.ChallengeMode

function Actions.GetLeaderboard(player, arg)
	if type(arg) ~= "table" or not Config.Chamber(arg.chamber) then return false end
	local kind = arg.kind == "time" and "time" or "portals"
	local store = lbStore(arg.chamber, kind)
	local out = { top = {}, mine = nil }
	if not store then return true, out end
	local ok, pages = retry(function() return store:GetSortedAsync(true, 100) end, 2)
	if ok and pages then
		for rank, e in ipairs(pages:GetCurrentPage()) do
			table.insert(out.top, { userId = tonumber(e.key), value = e.value, rank = rank })
		end
	end
	local okMine, mine = retry(function() return store:GetAsync(tostring(player.UserId)) end, 1)
	if okMine then out.mine = mine end
	return true, out
end

-- arg: a userId, or { userId = n, chamber = Workshop co-op chamber id } (invite from a Workshop chamber)
function Actions.CoopInvite(player, arg)
	local targetUserId, chamber = arg, nil
	if type(arg) == "table" then targetUserId, chamber = arg.userId, type(arg.chamber) == "string" and arg.chamber or nil end
	local target = Players:GetPlayerByUserId(tonumber(targetUserId) or 0)
	if not target then return false, "notHere" end
	if target == player then return false, "You can't invite yourself." end
	local meta = chamber and metaById(chamber)
	if chamber and not meta then return false, "That chamber isn't in the Workshop any more." end
	pendingInvites[target.UserId] = { from = player.UserId, t = os.clock(), chamber = chamber }
	Push:FireClient(target, "CoopInvite", { from = player.UserId, name = player.DisplayName, chamberTitle = meta and meta.title })
	return true
end

function Actions.CoopRespond(player, arg)
	if type(arg) ~= "table" then return false end
	local inv = pendingInvites[player.UserId]
	pendingInvites[player.UserId] = nil
	if not inv or inv.from ~= arg.from or os.clock() - inv.t > 120 then return false, "That invite expired." end
	local from = Players:GetPlayerByUserId(inv.from)
	if not from then return false, "Your partner left." end
	if not arg.accept then
		Push:FireClient(from, "CoopDeclined", { name = player.DisplayName })
		return true
	end
	startCoop(from, player, { chamber = inv.chamber })
	return true
end

-- arg.chamber: only match with someone who wants that Workshop chamber (or anyone, who then plays it)
function Actions.CoopQuickMatch(player, arg)
	local chamber = type(arg) == "table" and type(arg.chamber) == "string" and arg.chamber or nil
	queued[player] = { chamber = chamber }
	return true
end

function Actions.CoopCancel(player)
	queued[player] = nil
	if QUEUE then pcall(function() QUEUE:RemoveAsync(tostring(player.UserId)) end) end
	return true
end

function Actions.WorkshopBrowse(player, arg)
	arg = type(arg) == "table" and arg or {}
	local list = workshopIndex()
	local filtered = {}
	for _, m in ipairs(list) do
		if (arg.coop == true) == (m.coop == true) then table.insert(filtered, m) end
	end
	if arg.sort == "Queue" then
		local p = getProfile(player, 5)
		local out = {}
		for _, id in ipairs(p and p.queue or {}) do
			local m = metaById(id)
			if m then table.insert(out, m) end
		end
		return true, out
	elseif arg.sort == "Mine" then
		local out = {}
		for _, m in ipairs(list) do
			if m.authorId == player.UserId then table.insert(out, m) end
		end
		return true, out
	end
	return true, sortWorkshop(filtered, arg.sort or "MostRecent", player, arg.friends)
end

function Actions.WorkshopGetMap(_player, id)
	if type(id) ~= "string" then return false end
	local data = getMapData(id)
	return data ~= nil, data
end

function Actions.CommunitySingle(player, id)
	if type(id) ~= "string" then return false, "No chamber picked." end
	local raw = getMapData(id)
	if not raw then return false, "Couldn't download that chamber." end
	-- stored chambers go through the same checks as the editor's (older saves get upgraded on the way)
	local data, err = cleanMap(raw)
	if not data then return false, "That chamber is broken: " .. tostring(err) end
	local okBuild, model = pcall(buildChamberMap, data, "workshop_" .. id, player)
	if not okBuild then
		warn("[PortalServer] building workshop chamber " .. id .. ":", model)
		return false, "Couldn't build that chamber: " .. tostring(model):gsub("^.-:%d+: ", ""):sub(1, 160)
	end
	local cf = entrySpawnCF(model)
	if not cf then return false, "That chamber has no entry door." end
	player:SetAttribute("Chapter", nil)
	player:SetAttribute("WorkshopMap", id)
	player:SetAttribute("ChallengeStart", os.clock())
	player:SetAttribute("ChamberDone", nil)
	testSpawn[player] = cf -- dying puts you back at the entry door, not the lobby

	-- Workshop chambers are played with the portal gun (it's only lent if you didn't have it)
	local root = charRoot(player)
	if root then root.Anchored = false end
	local oldChar = player.Character
	if not (oldChar and oldChar:GetAttribute("HasPortalGun")) and rigChange(player, "Equip", { source = "Workshop", silent = true }) then
		waitForRig(player, oldChar, 4)
	end
	placeCharacter(player, cf)
	updateIndex(function(list)
		for _, m in ipairs(list) do if m.id == id then m.plays = (m.plays or 0) + 1 end end
	end)
	return true
end

-- ==========================================
-- CO-OP RUNS
-- After two players pair up (invite / quick match) they vote: Built-in chambers (the co-op courses) or Custom ones
-- (the Workshop's co-op chambers), and Normal or Speedrun. Then they play the whole list together: a chamber is done
-- when BOTH reach the exit, then the next one loads. Speedrun times the whole list (personal bests are kept).
-- A Workshop co-op chamber picked with "invite a friend" / "quick match" is a run of just that chamber.
-- ==========================================
do
	local runs = {}  -- [player] = run (both players point at the same table)
	local votes = {} -- [player] = vote
	local function partnerOf(pl)
		local id = pl:GetAttribute("CoopPartner")
		return id and Players:GetPlayerByUserId(id) or nil
	end
	local function push(r, kind, d)
		for _, pl in ipairs({ r.a, r.b }) do
			if pl.Parent then Push:FireClient(pl, kind, d) end
		end
	end

	local function builtinList()
		local out = {}
		for _, course in ipairs(Config.COURSES) do
			if course.coop then
				for _, ch in ipairs(course.chambers) do table.insert(out, { kind = "builtin", id = ch.id, name = ch.name }) end
			end
		end
		return out
	end
	local function customList(pl)
		local out, coopMaps = {}, {}
		for _, m in ipairs(workshopIndex()) do if m.coop then table.insert(coopMaps, m) end end
		for i, m in ipairs(sortWorkshop(coopMaps, "TopRated", pl)) do
			if i > (Config.COOP_RUN_MAX or 12) then break end
			table.insert(out, { kind = "custom", id = m.id, name = m.title or "Untitled" })
		end
		return out
	end

	local function clearPlayer(pl)
		runs[pl] = nil
		testSpawn[pl] = nil
		if pl.Parent then
			pl:SetAttribute("CoopRun", nil)
			pl:SetAttribute("ChamberDone", nil)
		end
	end

	local function toHub(r)
		local root = loadMap(Config.COOP_HUB_MAP, true, r.a)
		for _, pl in ipairs({ r.a, r.b }) do
			local s = root and findSpawn(root, pl:GetAttribute("CoopColor"))
			if s and pl.Parent then task.spawn(placeCharacter, pl, spawnCF(s)) end
		end
	end

	local loadEntry
	local function finish(r)
		local total = os.clock() - r.startT
		for _, pl in ipairs({ r.a, r.b }) do clearPlayer(pl) end
		if r.single then
			-- one Workshop chamber: the usual "rate it" screen
			local e = r.list[1]
			push(r, "ChamberComplete", { mapId = e and e.id, time = total })
			return
		end
		for _, pl in ipairs({ r.a, r.b }) do
			if pl.Parent then
				local best, newBest
				local p = profiles[pl]
				if p and r.mode == "speedrun" then
					p.coopBest = type(p.coopBest) == "table" and p.coopBest or {}
					best = p.coopBest[r.source]
					if not best or total < best then
						p.coopBest[r.source] = total
						best, newBest = total, true
						markDirty(pl)
					end
				end
				Push:FireClient(pl, "CoopRunEnd", { mode = r.mode, source = r.source, total = total, splits = r.splits,
					names = r.names, best = best, newBest = newBest == true })
			end
		end
		task.delay(1.5, toHub, r)
	end

	loadEntry = function(r)
		if runs[r.a] ~= r then return end
		local e = r.list[r.index]
		if not e then finish(r) return end
		r.done = {}
		local spawns = {}
		local ok, err = pcall(function()
			if e.kind == "builtin" then
				local root = loadMap(e.id, true, r.a)
				for _, pl in ipairs({ r.a, r.b }) do
					local s = root and findSpawn(root, pl:GetAttribute("CoopColor"))
					spawns[pl] = s and spawnCF(s)
				end
			else
				local raw = getMapData(e.id)
				local data, why = raw and cleanMap(raw)
				if not data then error(why or "couldn't download it") end
				local model = buildChamberMap(data, "coop_" .. e.id, r.a)
				local cf = entrySpawnCF(model)
				if not cf then error("it has no entry door") end
				spawns[r.a], spawns[r.b] = cf * CFrame.new(-2, 0, 0), cf * CFrame.new(2, 0, 0) -- side by side
				updateIndex(function(list)
					for _, m in ipairs(list) do if m.id == e.id then m.plays = (m.plays or 0) + 1 end end
				end)
			end
		end)
		if not ok then
			-- a broken chamber doesn't end the run: skip it
			warn("[PortalServer] co-op run: skipping " .. tostring(e.id) .. ":", err)
			for _, pl in ipairs({ r.a, r.b }) do toast(pl, ("Skipped %s (it wouldn't load)."):format(e.name), "info") end
			r.index += 1
			return loadEntry(r)
		end
		for _, pl in ipairs({ r.a, r.b }) do
			pl:SetAttribute("ChamberDone", nil)
			testSpawn[pl] = spawns[pl] -- dying puts you back at the start of this chamber
			if spawns[pl] then task.spawn(placeCharacter, pl, spawns[pl]) end
		end
		r.chamberStart = os.clock()
		push(r, "CoopRunStep", { index = r.index, count = #r.list, name = e.name, mode = r.mode,
			total = r.mode == "speedrun" and (os.clock() - r.startT) or nil })
	end

	-- opts: { source = "builtin" | "custom", mode = "normal" | "speedrun", ids = { workshop ids } (optional), single }
	function CoopRun.begin(a, b, opts)
		local list
		if opts.ids then
			list = {}
			for _, id in ipairs(opts.ids) do
				local m = metaById(id)
				table.insert(list, { kind = "custom", id = id, name = m and m.title or "Workshop chamber" })
			end
		else
			list = opts.source == "builtin" and builtinList() or customList(a)
		end
		if #list == 0 then
			for _, pl in ipairs({ a, b }) do
				toast(pl, opts.source == "builtin" and "There are no built-in co-op chambers (Config.COURSES)." or "There are no co-op chambers in the Workshop yet.", "info")
			end
			return false
		end
		local names = {}
		for _, e in ipairs(list) do table.insert(names, e.name) end
		local r = { a = a, b = b, source = opts.source or "custom", mode = opts.mode == "speedrun" and "speedrun" or "normal",
			single = opts.single == true, list = list, names = names, index = 1, splits = {}, startT = os.clock(), done = {} }
		for _, pl in ipairs({ a, b }) do
			runs[pl], votes[pl] = r, nil
			pl:SetAttribute("CoopRun", true)
			pl:SetAttribute("WorkshopMap", nil)
			pl:SetAttribute("ChallengeChamber", nil)
		end
		push(r, "CoopRunStart", { source = r.source, mode = r.mode, count = #list, names = names, single = r.single })
		task.delay(2.5, function()
			r.startT = os.clock() -- the clock starts when the first chamber is there
			loadEntry(r)
		end)
		return true
	end

	-- the exit: returns true when the player is in a co-op run (the run handles it)
	function CoopRun.reached(pl)
		local r = runs[pl]
		if not r then return false end
		if r.done[pl] then return true end
		r.done[pl] = true
		pl:SetAttribute("ChamberDone", true)
		local other = pl == r.a and r.b or r.a
		if not r.done[other] then
			toast(pl, "Waiting for your partner at the exit...", "info")
			if other.Parent then toast(other, pl.DisplayName .. " made it to the exit.", "info") end
			return true
		end
		table.insert(r.splits, os.clock() - (r.chamberStart or r.startT))
		if r.index >= #r.list then
			finish(r)
		else
			r.index += 1
			push(r, "CoopRunSplit", { index = r.index - 1, split = r.splits[#r.splits], total = os.clock() - r.startT, mode = r.mode })
			task.delay(2, loadEntry, r)
		end
		return true
	end

	function CoopRun.stop(pl)
		local r = runs[pl]
		votes[pl] = nil
		if not r then return end
		for _, p in ipairs({ r.a, r.b }) do
			clearPlayer(p)
			if p.Parent then Push:FireClient(p, "CoopRunEnd", { cancelled = true }) end
		end
	end

	-- ----- the vote -----
	function CoopRun.openVote(a, b)
		if runs[a] or runs[b] then return false end
		if votes[a] and votes[a] == votes[b] then return true end -- already voting (both pressed PLAY AGAIN)
		local v = { a = a, b = b, picks = {} }
		votes[a], votes[b] = v, v
		local builtinN, customN = #builtinList(), #customList(a)
		for _, pl in ipairs({ a, b }) do
			local other = pl == a and b or a
			Push:FireClient(pl, "CoopVote", { partner = other.DisplayName, builtin = builtinN, custom = customN })
		end
		return true
	end

	function Actions.CoopVote(player, arg)
		local v = votes[player]
		if not v then return false, "There's nothing to vote on." end
		if type(arg) ~= "table" or (arg.source ~= "builtin" and arg.source ~= "custom") or (arg.mode ~= "normal" and arg.mode ~= "speedrun") then
			return false, "Pick the chambers and the mode."
		end
		v.picks[player] = { source = arg.source, mode = arg.mode }
		local other = player == v.a and v.b or v.a
		if other.Parent then Push:FireClient(other, "CoopVoteUpdate", { partner = player.DisplayName, source = arg.source, mode = arg.mode }) end
		local pa, pb = v.picks[v.a], v.picks[v.b]
		if pa and pb then
			votes[v.a], votes[v.b] = nil, nil
			-- the same pick wins; different picks: a coin flip (both see which way it went)
			local flips = {}
			local function decide(key)
				if pa[key] == pb[key] then return pa[key] end
				flips[key] = true
				return math.random(2) == 1 and pa[key] or pb[key]
			end
			local source, mode = decide("source"), decide("mode")
			for _, pl in ipairs({ v.a, v.b }) do
				Push:FireClient(pl, "CoopVoteResult", { source = source, mode = mode, flipSource = flips.source, flipMode = flips.mode })
			end
			task.delay(2, function()
				if v.a.Parent and v.b.Parent and partnerOf(v.a) == v.b then CoopRun.begin(v.a, v.b, { source = source, mode = mode }) end
			end)
		end
		return true
	end

	-- the pause menu / results screen: vote again
	function Actions.CoopVoteOpen(player)
		local other = partnerOf(player)
		if not other then return false, "You need a co-op partner first." end
		if runs[player] then return false, "Finish (or leave) this run first." end
		return CoopRun.openVote(player, other)
	end

	-- give up on the run (both go back to the hub)
	function Actions.CoopRunQuit(player)
		local r = runs[player]
		if not r then return false end
		CoopRun.stop(player)
		toHub(r)
		return true
	end
end

-- Workshop co-op chamber: with your partner if you have one (both go in), alone otherwise
function Actions.CommunityCoop(player, id)
	if type(id) ~= "string" then return false, "No chamber picked." end
	local other = player:GetAttribute("CoopPartner") and Players:GetPlayerByUserId(player:GetAttribute("CoopPartner"))
	if other then
		if not CoopRun.begin(player, other, { source = "custom", mode = "normal", single = true, ids = { id } }) then
			return false, "Couldn't start that chamber."
		end
		return true
	end
	return Actions.CommunitySingle(player, id)
end

function Actions.WorkshopRate(player, arg)
	if type(arg) ~= "table" or type(arg.id) ~= "string" then return false end
	local p = getProfile(player, 5)
	if not p then return false end
	p.rated = p.rated or {}
	local before = p.rated[arg.id]
	local now = arg.up and "up" or "down"
	if before == now then return true end
	p.rated[arg.id] = now
	markDirty(player)
	updateIndex(function(list)
		for _, m in ipairs(list) do
			if m.id == arg.id then
				if before then m[before] = math.max((m[before] or 1) - 1, 0) end
				m[now] = (m[now] or 0) + 1
			end
		end
	end)
	return true
end

function Actions.QueueAdd(player, id)
	local p = getProfile(player, 5)
	if not p or type(id) ~= "string" then return false end
	if not table.find(p.queue, id) then table.insert(p.queue, id) end
	markDirty(player)
	return true, p.queue
end

function Actions.QueueRemove(player, id)
	local p = getProfile(player, 5)
	if not p then return false end
	local i = table.find(p.queue, id)
	if i then table.remove(p.queue, i) end
	markDirty(player)
	return true, p.queue
end

function Actions.Follow(player, authorId)
	local p = getProfile(player, 5)
	if not p then return false end
	local key = tostring(authorId)
	if not table.find(p.follows, key) then table.insert(p.follows, key) end
	markDirty(player)
	return true
end

-- editor
function Actions.EditorList(player)
	local p = getProfile(player, 5)
	if not p then return false end
	local out = {}
	for _, d in ipairs(p.drafts) do table.insert(out, draftSummary(d)) end
	return true, out
end

function Actions.EditorGet(player, id)
	local p = getProfile(player, 5)
	local d = p and findDraft(p, id)
	return d ~= nil, d and d.data
end

function Actions.CommunityCreate(player, id)
	local p = getProfile(player, 5)
	if not p then return false, "Profile not loaded." end
	local d = id and findDraft(p, id)
	if not d then
		if #p.drafts >= 30 then return false, "You have 30 test chambers. Delete one first." end
		d = { id = HttpService:GenerateGUID(false), title = "Untitled Chamber", created = os.time(), modified = os.time(), data = Config.DefaultChamber() }
		table.insert(p.drafts, 1, d)
		markDirty(player)
	end
	endCoop(player)
	testSpawn[player] = nil
	player:SetAttribute("Chapter", nil)
	player:SetAttribute("InEditor", true)
	player:SetAttribute("EditorPlaytest", false)
	clearActive(player)
	park(player)
	unlock(player, "EDITOR")
	task.delay(0.2, function()
		Push:FireClient(player, "EditorStart", { id = d.id, title = d.title, data = d.data })
	end)
	return true
end

function Actions.EditorSave(player, arg)
	local p = getProfile(player, 5)
	if not p or type(arg) ~= "table" then return false end
	local d = findDraft(p, arg.id)
	if not d then return false, "Chamber not found." end
	local clean, err = cleanMap(arg.data)
	if not clean then return false, err end
	d.data = clean
	d.modified = os.time()
	if type(arg.title) == "string" and arg.title ~= "" then
		local filtered = filterText(arg.title:sub(1, 40), player)
		if filtered then d.title = filtered end
	end
	markDirty(player)
	return true, d.title
end

function Actions.EditorSaveAs(player, arg)
	local p = getProfile(player, 5)
	if not p or type(arg) ~= "table" then return false end
	local clean, err = cleanMap(arg.data)
	if not clean then return false, err end
	if #p.drafts >= 30 then return false, "You have 30 test chambers. Delete one first." end
	local title = type(arg.title) == "string" and arg.title:sub(1, 40) or "Untitled Chamber"
	local d = { id = HttpService:GenerateGUID(false), title = filterText(title, player) or "Untitled Chamber", created = os.time(), modified = os.time(), data = clean }
	table.insert(p.drafts, 1, d)
	markDirty(player)
	return true, d.id
end

-- build the chamber in the world and drop the player in at the entry door
function Actions.EditorTest(player, arg)
	if type(arg) ~= "table" then return false end
	if not player:GetAttribute("InEditor") then return false, "You're not in the editor." end
	local clean, err = cleanMap(arg.data)
	if not clean then return false, err end
	local okBuild, model = pcall(buildChamberMap, clean, "editor_test", player)
	if not okBuild then
		warn("[PortalServer] building chamber:", model)
		return false, "Couldn't build the chamber."
	end
	local cf = entrySpawnCF(model)
	if not cf then return false, "Place an Entry Door first." end

	-- set these first so a respawn from the rig swap lands at the entry door too
	testSpawn[player] = cf
	player:SetAttribute("EditorPlaytest", true)
	player:SetAttribute("ChallengeStart", os.clock())
	player:SetAttribute("ChamberDone", nil)

	local root = charRoot(player)
	if root then root.Anchored = false end
	local oldChar = player.Character
	if rigChange(player, "Equip", { source = "Editor", silent = true }) then
		waitForRig(player, oldChar, 4)
	end
	root = charRoot(player)
	if root then root.Anchored = false end
	placeCharacter(player, cf)
	-- NPCs (ChamberBotServer): "watch" = the demo plays, "with" = it plays while you record your part; every other
	-- playtest is recorded so you can keep it as the demo
	local bots = shared.ChamberBots
	if bots then
		local slot = slotOf[player]
		if (arg.demo == "watch" or arg.demo == "with") and clean.demo then
			bots.Play(clean.demo, Config.ChamberOrigin(slot), activeFolder(player))
		elseif arg.demo == "auto" and bots.AutoPlay then
			-- the NPC plays it on its own (two in co-op chambers / co-op demos), learning from every taught run
			local two = clean.coop or (clean.demo and #clean.demo.tracks >= 2)
			bots.AutoPlay(clean, Config.ChamberOrigin(slot), activeFolder(player), cf, two and 2 or 1)
		end
		if arg.demo ~= "watch" and arg.demo ~= "auto" then bots.StartRecording(player, slot, Config.ChamberOrigin(slot)) end
	end
	return true
end

-- File > NPC demo > Keep my last run: the recorded run(s) of your last playtest
function Actions.DemoTake(player)
	local bots = shared.ChamberBots
	if not bots then return false, "ChamberBotServer isn't in ServerScriptService." end
	local tracks = bots.Take(player)
	if not tracks then return false, "Play the chamber first (Build & Play) - your run is recorded while you play." end
	return true, tracks
end

function Actions.EditorEdit(player)
	Push:FireClient(player, "ChipFX", { op = "reset" }) -- chip music / tint / countdown stop when you go back to editing
	clearActive(player)
	testSpawn[player] = nil
	player:SetAttribute("EditorPlaytest", false)
	park(player)
	return true
end

function Actions.EditorExit(player)
	testSpawn[player] = nil
	player:SetAttribute("InEditor", nil)
	player:SetAttribute("EditorPlaytest", nil)
	if rigChange(player, "Restore", { source = "Editor" }) then waitForRig(player, player.Character, 4) end
	local root = charRoot(player)
	if root then root.Anchored = false end
	leaveSlot(player)
	sendToLobby(player)
	return true
end

function Actions.EditorDelete(player, id)
	local p = getProfile(player, 5)
	if not p then return false end
	local _, i = findDraft(p, id)
	if i then table.remove(p.drafts, i) markDirty(player) end
	return true
end

function Actions.EditorPublish(player, arg)
	if type(arg) ~= "table" then return false end
	local p = getProfile(player, 5)
	local d = p and findDraft(p, arg.id)
	if not d then return false, "Save the chamber first." end
	local clean, err = cleanMap(arg.data)
	if not clean then return false, err end
	if not Config.ExitCanOpen(clean) then
		return false, "Nothing opens the exit door. Connect a button to it, open it with a chip, or right-click it > Open without a button."
	end
	-- chip messages are shown to everyone who plays it: filter them
	for _, chip in ipairs(clean.chips) do
		local rules = Config.ParseChip(chip.src)
		local changed = false
		Config.ChipEachAction(rules, function(a) -- (says inside an "if" too)
			if (a.op == "say" or a.op == "title") and a.text ~= "" then
				a.text = filterText(a.text, player) or ""
				changed = true
			end
		end)
		if changed then chip.src = Config.ChipText(rules) end
		chip.name = filterText(chip.name, player) or "Chip"
	end
	local title = type(arg.title) == "string" and arg.title:sub(1, 40) or d.title
	title = filterText(title, player) or "Untitled Chamber"
	clean.title = title
	clean.coop = arg.coop == true
	local id = d.publishedId or HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 16)
	if workshopStore then
		local ok = retry(function() workshopStore:SetAsync("map_" .. id, clean) end)
		if not ok then return false, "Upload failed, try again." end
	else
		localWorkshop["map_" .. id] = clean
	end
	local isUpdate = d.publishedId ~= nil
	updateIndex(function(list)
		for _, m in ipairs(list) do
			if m.id == id then
				m.title, m.coop, m.updated = title, clean.coop, os.time()
				return
			end
		end
		table.insert(list, 1, {
			id = id, title = title, author = player.DisplayName, authorId = player.UserId,
			coop = clean.coop, created = os.time(), up = 0, down = 0, plays = 0,
		})
		while #list > 500 do table.remove(list) end
	end)
	d.publishedId, d.publishedAt, d.title, d.data, d.modified = id, os.time(), title, clean, os.time()
	if not isUpdate then table.insert(p.published, id) end
	markDirty(player)
	unlock(player, "PUBLISH")
	return true, id
end

Actions.ToolboxSearch = toolboxSearch
Actions.ToolboxLoad = toolboxLoad

-- My Chips library (chips you can drop into any of your chambers)
function Actions.ChipList(player)
	local p = getProfile(player, 5)
	if not p then return false end
	return true, p.chips
end

function Actions.ChipSave(player, arg)
	local p = getProfile(player, 5)
	if not p or type(arg) ~= "table" or type(arg.src) ~= "string" then return false end
	local name = type(arg.name) == "string" and arg.name:sub(1, 30) or "Chip"
	local src = arg.src:sub(1, Config.EDITOR_LIMITS.chipLen or 3000)
	for _, c in ipairs(p.chips) do
		if c.id == arg.id then
			c.name, c.src = name, src
			markDirty(player)
			return true, p.chips
		end
	end
	if #p.chips >= 50 then return false, "You have 50 chips saved. Delete one first." end
	table.insert(p.chips, 1, { id = HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 12), name = name, src = src })
	markDirty(player)
	return true, p.chips
end

function Actions.ChipDelete(player, id)
	local p = getProfile(player, 5)
	if not p then return false end
	for i, c in ipairs(p.chips) do
		if c.id == id then table.remove(p.chips, i) break end
	end
	markDirty(player)
	return true, p.chips
end

function Actions.CommunityWorkshop(player)
	return Actions.WorkshopBrowse(player, { sort = "Mine" })
end

-- store
function Actions.StoreClaim(player, id)
	local p = getProfile(player, 5)
	local item = Config.Item(id)
	if not p or not item then return false end
	if item.productId and item.productId ~= 0 then
		MarketplaceService:PromptProductPurchase(player, item.productId)
		return true, "prompted"
	end
	if #p.inventory >= Config.BACKPACK_SLOTS then return false, "Your backpack is full." end
	grantItem(p, item)
	markDirty(player)
	return true, p.inventory
end

function Actions.StoreEquip(player, arg)
	local p = getProfile(player, 5)
	if not p or type(arg) ~= "table" then return false end
	local bot = arg.bot == "orange" and "orange" or "blue"
	local slot = arg.slot
	if not table.find({ "head", "flag", "gesture", "skin" }, slot) then return false end
	if arg.id == nil then
		p.equipped[bot][slot] = nil
	else
		local item = Config.Item(arg.id)
		if not item or item.slot ~= slot or not owns(p, arg.id) then return false end
		if item.bots ~= "both" and item.bots ~= bot then return false, "That item doesn't fit this bot." end
		p.equipped[bot][slot] = arg.id
	end
	markDirty(player)
	applyCosmetics(player)
	return true, p.equipped
end

function Actions.StoreDelete(player, index)
	local p = getProfile(player, 5)
	index = tonumber(index)
	if not p or not index or not p.inventory[index] then return false end
	local id = table.remove(p.inventory, index)
	if not owns(p, id) then
		for _, bot in pairs(p.equipped) do
			for slot, v in pairs(bot) do if v == id then bot[slot] = nil end end
		end
	end
	markDirty(player)
	applyCosmetics(player)
	return true, { inventory = p.inventory, equipped = p.equipped }
end

-- ==========================================
-- REQUEST DISPATCH (with a small rate limit)
-- ==========================================
local lastCall = {}
Request.OnServerInvoke = function(player, action, arg)
	local fn = type(action) == "string" and Actions[action]
	if not fn then return false, "Unknown action " .. tostring(action) end
	local now = os.clock()
	local key = player.UserId .. action
	if lastCall[key] and now - lastCall[key] < 0.15 then return false, "Slow down." end
	lastCall[key] = now
	local ok, a, b = pcall(fn, player, arg)
	if not ok then
		warn("[PortalServer]", action, a)
		-- the real error goes into the popup too (without the script path), so it can be reported
		local msg = tostring(a):gsub("^.-:%d+: ", "")
		return false, ("Something went wrong (%s): %s"):format(tostring(action), msg:sub(1, 160))
	end
	return a, b
end

-- ==========================================
-- TRIGGERS (overlap detection instead of .Touched)
-- ==========================================
-- Every frame each player's character box is swept from where it was to where it is now and tested against all
-- trigger parts, so fast flings, portal exits and standing still inside a trigger all register.
local CHAR_BOX = Vector3.new(4, 6, 4)  -- generous character size
local MAX_SWEEP = 30                  -- moving further than this in one frame = teleport / portal, don't sweep the gap

local triggerOwners = {} -- [part] = { { tag = , inst = }, ... }
local triggerParts = {}
local triggerDirty = true
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.MaxParts = 50

local function addTriggerPart(part, tag, inst)
	triggerOwners[part] = triggerOwners[part] or {}
	for _, t in ipairs(triggerOwners[part]) do
		if t.tag == tag and t.inst == inst then return end
	end
	table.insert(triggerOwners[part], { tag = tag, inst = inst })
	part.CanQuery = true
	triggerDirty = true
end

local function registerTrigger(inst, tag)
	if inst:IsA("BasePart") then
		addTriggerPart(inst, tag, inst)
	elseif inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then addTriggerPart(d, tag, inst) end
		end
	end
end

local function rebuildTriggerList()
	table.clear(triggerParts)
	for part in pairs(triggerOwners) do
		if part.Parent and part:IsDescendantOf(workspace) then
			table.insert(triggerParts, part)
		elseif not part.Parent then
			triggerOwners[part] = nil
		end
	end
	overlap.FilterDescendantsInstances = triggerParts
	triggerDirty = false
end

local TRIGGERS = {} -- [tag] = { once = bool, fn = function(player, inst), again = seconds (fires again while you stay in it) }
local inside = {}   -- [player] = { [tag] = { [inst] = true } }
local fired = {}    -- [player] = { [tag] = { [inst] = true } } for once-only triggers

local lastFire = {}  -- [player] = { [inst] = os.clock() } for triggers that fire again while you stand in them
local function hookTrigger(tag, once, fn, again)
	TRIGGERS[tag] = { once = once, fn = fn, again = again }
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do registerTrigger(inst, tag) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst) registerTrigger(inst, tag) end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function() triggerDirty = true end)
end

local function checkPlayerTriggers(player)
	local root = charRoot(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or (hum and hum.Health <= 0) then lastPos[player] = nil return end
	local pos = root.Position
	local from = lastPos[player] or pos
	lastPos[player] = pos
	local dist = (pos - from).Magnitude
	local steps = (dist > MAX_SWEEP) and 1 or math.clamp(math.ceil(dist / 2), 1, 15)
	local hitParts = {}
	for i = 1, steps do
		local p = steps == 1 and pos or from:Lerp(pos, i / steps)
		for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(p), CHAR_BOX, overlap)) do
			hitParts[part] = true
		end
	end
	local now = {}
	for part in pairs(hitParts) do
		for _, t in ipairs(triggerOwners[part] or {}) do
			now[t.tag] = now[t.tag] or {}
			now[t.tag][t.inst] = true
		end
	end
	local was = inside[player] or {}
	fired[player] = fired[player] or {}
	for tag, insts in pairs(now) do
		local def = TRIGGERS[tag]
		for inst in pairs(insts) do
			local entered = not (was[tag] and was[tag][inst])
			local done = def and def.once and fired[player][tag] and fired[player][tag][inst]
			if def and def.again and not entered then
				lastFire[player] = lastFire[player] or {}
				local t = lastFire[player][inst]
				entered = t ~= nil and os.clock() - t > def.again
			end
			if def and def.again and entered then
				lastFire[player] = lastFire[player] or {}
				lastFire[player][inst] = os.clock()
			end
			if def and entered and not done then
				if def.once then
					fired[player][tag] = fired[player][tag] or {}
					fired[player][tag][inst] = true
				end
				task.spawn(def.fn, player, inst)
			end
		end
	end
	inside[player] = now
end

-- tagged instances, kept in sets instead of calling GetTagged every tick
local function taggedSet(tag)
	local set = {}
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do set[inst] = true end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst) set[inst] = true end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst) set[inst] = nil end)
	return set
end
local doorSet = taggedSet("PortalChamberDoor")
local floorButtonSet = taggedSet("PeTIFloorButton")

-- is this exit door unlocked? Editor-built exits (they have a Kind) need something to open them: a connection, a chip
-- or "Open without a button" all set Enabled. Hand-made doors in your maps keep the old rule.
local function doorUnlocked(door)
	if door:GetAttribute("Kind") == "exit" then return door:GetAttribute("Enabled") == true end
	return not door:GetAttribute("Linked") or door:GetAttribute("Enabled") == true
end

-- chamber doors: keep Open / PlayerNear / Unlocked up to date
local doorCenter = {}
local function updateDoors()
	local roots = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local r = charRoot(pl)
		if r then table.insert(roots, r.Position) end
	end
	local R = Config.DOOR_OPEN_RADIUS
	for door in pairs(doorSet) do
		if door.Parent and door:IsDescendantOf(workspace) then
			local center = doorCenter[door]
			if not center then
				center = door:IsA("Model") and door:GetPivot().Position or door.Position
				if door:IsA("Model") or door.Anchored then doorCenter[door] = center end
			end
			local near = false
			for _, p in ipairs(roots) do
				local d = p - center
				if math.abs(d.X) <= R and math.abs(d.Z) <= R and d.Magnitude <= R then near = true break end
			end
			local open = false
			local isExit = door:GetAttribute("DoorType") == "exit"
			local unlocked = isExit and doorUnlocked(door)
			if isExit then open = near and unlocked end
			if door:GetAttribute("PlayerNear") ~= near then door:SetAttribute("PlayerNear", near) end
			if isExit and door:GetAttribute("Unlocked") ~= unlocked then door:SetAttribute("Unlocked", unlocked) end
			if door:GetAttribute("Open") ~= open then door:SetAttribute("Open", open) end
		elseif not door.Parent then
			doorSet[door], doorCenter[door] = nil, nil
		end
	end
end

-- ==========================================
-- BUTTONS (chamber floor buttons, pedestals, laser catchers)
-- ==========================================
-- Floor button: pressed while a player or a cube is on it. The item's top model gets "Pressed" (true / false).
-- If the button asset has its own script that sets "Pressed" / "PressesButton" on something inside it, that counts too.
-- Pedestals (PedestalButtonServer) and laser catchers (TestElementsServer) set "Pressed" on the model inside the item;
-- that's copied up to the item, which is what the connections listen to.
local BUTTON_SOUNDS = { down = { "button_down", "buttondown", "button_press" }, up = { "button_up", "buttonup", "button_release" } }

local function findSounds(frags)
	local root = ReplicatedStorage:FindFirstChild("PortalAssets")
	root = root and root:FindFirstChild("Sounds")
	if not root then return nil end
	for _, f in ipairs(frags) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Sound") and d.Name:lower():find(f, 1, true) then return d end
		end
	end
	return nil
end
local buttonDownSound, buttonUpSound = findSounds(BUTTON_SOUNDS.down), findSounds(BUTTON_SOUNDS.up)

local function playAt(sound, model)
	local part = model and model:FindFirstChildWhichIsA("BasePart", true)
	if not sound or not part then return end
	local s = sound:Clone()
	s.Parent = part
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
end

local function isCube(part)
	local node = part
	for _ = 1, 5 do
		if not node or node == workspace then break end
		local ct = node:GetAttribute("CubeType")
		if ct or node:GetAttribute("Grabbable") or CollectionService:HasTag(node, "PortalCube")
			or node.Name:lower():find("cube") or node.Name:lower():find("sphere") or node.Name:lower():find("edgeless") then
			local n = (tostring(ct or "") .. node.Name):lower()
			return true, (n:find("edgeless") or n:find("sphere") or n:find("ball")) and "Sphere" or "Cube"
		end
		node = node.Parent
	end
	return false
end

local function innerPressed(m)
	for _, d in ipairs(m:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and (d:GetAttribute("Pressed") == true or d:GetAttribute("PressesButton") == true) then
			return true
		end
	end
	return false
end

local function setPressed(m, on)
	if (m:GetAttribute("Pressed") == true) == on then return end
	m:SetAttribute("Pressed", on)
	playAt(on and buttonDownSound or buttonUpSound, m)
end

local buttonBox = setmetatable({}, { __mode = "k" })
local buttonParams = OverlapParams.new()
buttonParams.FilterType = Enum.RaycastFilterType.Exclude
local function updateButtons()
	for m in pairs(floorButtonSet) do
		if not m.Parent then
			floorButtonSet[m] = nil
		elseif m:IsDescendantOf(workspace) then
			local box = buttonBox[m]
			if not box then
				box = { m:GetBoundingBox() } -- buttons are anchored: measure once
				buttonBox[m] = box
			end
			local cf, size = box[1], box[2]
			local top = cf.Position + Vector3.new(0, size.Y / 2 + 1.2, 0)
			buttonParams.FilterDescendantsInstances = { m }
			local on = false
			local btype = m:GetAttribute("ButtonType") or "Weighted"
			for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(top), Vector3.new(size.X * 0.8, 3, size.Z * 0.8), buttonParams)) do
				local mdl = part:FindFirstAncestorOfClass("Model")
				local hum = mdl and mdl:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					if btype == "Weighted" then on = true break end
				elseif not part.Anchored then
					local cube, shape = isCube(part)
					if cube and (btype == "Weighted" or btype == shape) then on = true break end
				end
			end
			setPressed(m, on or innerPressed(m))
		end
	end
end

-- pedestals / laser catchers: copy "Pressed" from the model inside up to the item (no prompt - the pedestal's own
-- click from PedestalButtonClient / PedestalButtonServer presses it, in whatever mode the editor set)
local function setupMirror(m)
	if not m:IsDescendantOf(workspace) or m:GetAttribute("MirrorHooked") then return end
	-- no asset (placeholder): the item IS the pedestal / catcher and sets "Pressed" on itself already
	if CollectionService:HasTag(m, "LaserCatcher") or CollectionService:HasTag(m, "PedestalButton") then return end
	m:SetAttribute("MirrorHooked", true)
	local old = m:FindFirstChild("PressPrompt", true)
	if old then old:Destroy() end
	local function sync()
		local on = innerPressed(m)
		if (m:GetAttribute("Pressed") == true) ~= on then m:SetAttribute("Pressed", on) end
	end
	local function hook(d)
		if d:IsA("Model") or d:IsA("BasePart") then
			d:GetAttributeChangedSignal("Pressed"):Connect(sync)
			d:GetAttributeChangedSignal("PressesButton"):Connect(sync)
		end
	end
	for _, d in ipairs(m:GetDescendants()) do hook(d) end
	m.DescendantAdded:Connect(hook)
	sync()
end
for _, tag in ipairs({ "PeTIMirror", "PeTIPedestal" }) do
	for _, m in ipairs(CollectionService:GetTagged(tag)) do task.spawn(setupMirror, m) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(m) task.defer(setupMirror, m) end)
end

-- invisible zones from the editor (Trigger Zone, Death Zone, Push Zone): one box per item, checked 10 times a second.
-- Players are pushed by TestElementsClient (it owns their character); cubes are pushed here.
local zoneSet = taggedSet("PeTIZone")
local zoneParams = OverlapParams.new()
zoneParams.FilterType = Enum.RaycastFilterType.Exclude
updateZones = function()
	for m in pairs(zoneSet) do
		if not m.Parent then
			zoneSet[m] = nil
		elseif m:IsDescendantOf(workspace) then
			local kind = m:GetAttribute("Kind")
			local zone = m:FindFirstChild("Zone")
			local active = m:GetAttribute("Enabled") ~= false
			if zone and (kind == "trigger" or active) and kind ~= "block" then
				zoneParams.FilterDescendantsInstances = { m }
				local mode = m:GetAttribute("TriggerMode") or "Players"
				local hit, seen = false, {}
				for _, part in ipairs(workspace:GetPartBoundsInBox(zone.CFrame, zone.Size, zoneParams)) do
					local mdl = part:FindFirstAncestorOfClass("Model")
					local hum = mdl and mdl:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 and Players:GetPlayerFromCharacter(mdl) then
						if kind == "killzone" then
							hum.Health = 0
						elseif kind == "trigger" and mode ~= "Cubes" then
							hit = true
						end
					elseif not part.Anchored and not (hum) then
						local root = part.AssemblyRootPart
						if kind == "trigger" and mode ~= "Players" and isCube(part) then
							hit = true
						elseif kind == "pushzone" and root and not seen[root] and not root.Anchored and not root:GetAttribute("HeldBy") then
							seen[root] = true
							local v = m:GetAttribute("PushVelocity")
							if typeof(v) == "Vector3" and v.Magnitude > 0 then
								if root:CanSetNetworkOwnership() then root:SetNetworkOwner(nil) end -- (like the funnels do)
								local cur = root.AssemblyLinearVelocity
								local dir = v.Unit
								if cur:Dot(dir) < v.Magnitude then
									root.AssemblyLinearVelocity = cur - dir * cur:Dot(dir) + v
								end
							end
						end
					end
					if hit and kind == "trigger" then break end
				end
				if kind == "trigger" and (m:GetAttribute("Pressed") == true) ~= hit then
					m:SetAttribute("Pressed", hit)
				end
			end
		end
	end
end

local doorClock, pruneClock = 0, 0
RunService.Heartbeat:Connect(function(dt)
	pruneClock += dt
	if triggerDirty or pruneClock > 2 then
		pruneClock = 0
		rebuildTriggerList()
	end
	if #triggerParts > 0 then
		for _, pl in ipairs(Players:GetPlayers()) do checkPlayerTriggers(pl) end
	end
	doorClock += dt
	if doorClock > 0.1 then
		doorClock = 0
		updateDoors()
		updateButtons()
		updateZones()
	end
end)

hookTrigger("PortalAutosave", true, function(pl)
	if pl:GetAttribute("Chapter") then makeSave(pl, nil, true) Push:FireClient(pl, "Autosaved", {}) end
end)

hookTrigger("PortalAchievement", true, function(pl, inst)
	local id = inst:GetAttribute("Achievement")
	if type(id) == "string" then unlock(pl, id) end
end)

hookTrigger("PortalChapterEnd", false, function(pl, inst)
	local ch = inst:GetAttribute("Chapter") or pl:GetAttribute("Chapter")
	if type(ch) ~= "number" then return end
	finishChapter(pl, ch)
	if ch < #Config.CHAPTERS then
		makeSave(pl, nil, true)
		if inst:GetAttribute("AutoAdvance") then
			Push:FireClient(pl, "LoadChapter", { chapter = ch + 1 })
		end
	else
		Push:FireClient(pl, "GameFinished", {})
	end
end)

-- the exit door model a finish trigger belongs to (nil = a trigger on its own in a hand-made map)
local function exitDoorOf(inst)
	local node = inst
	while node and node ~= workspace do
		if node:GetAttribute("DoorType") == "exit" then return node end
		node = node.Parent
	end
	return nil
end

hookTrigger("PortalChamberExit", false, function(pl, inst)
	if pl:GetAttribute("ChamberDone") then return end -- one finish per run
	local door = exitDoorOf(inst)
	if door and not doorUnlocked(door) then
		-- locked: no instant win. Keeps checking while you stand here (see the 0.5 below)
		if os.clock() - (lastLockedToast[pl] or 0) > 6 then
			lastLockedToast[pl] = os.clock()
			toast(pl, "The exit is locked. Find what opens it.", "locked")
		end
		return
	end
	if CoopRun.reached and CoopRun.reached(pl) then return end -- co-op runs: both players have to get out
	local started = pl:GetAttribute("ChallengeStart") or os.clock()
	local seconds = os.clock() - started
	local chamber = pl:GetAttribute("ChallengeChamber")
	local mapId = pl:GetAttribute("WorkshopMap")
	if chamber then
		pl:SetAttribute("ChamberDone", true)
		local portals = pl:GetAttribute("ChallengePortals") or 0
		submitChallenge(pl, chamber, portals, seconds)
		Push:FireClient(pl, "ChamberComplete", { chamber = chamber, portals = portals, time = seconds })
	elseif mapId then
		pl:SetAttribute("ChamberDone", true)
		unlock(pl, "WORKSHOP_PLAY")
		Push:FireClient(pl, "ChamberComplete", { mapId = mapId, time = seconds })
	elseif pl:GetAttribute("InEditor") and pl:GetAttribute("EditorPlaytest") then
		if shared.ChamberBots then shared.ChamberBots.Finish(pl) end -- the recorded run reached the exit
		pl:SetAttribute("ChamberDone", true)
		Push:FireClient(pl, "ChamberComplete", { editor = true, time = seconds })
	end
end, 0.5)

-- ==========================================
-- PLAYER LIFECYCLE
-- ==========================================
local function onCharacterAdded(player, char)
	lastPos[player] = nil
	inside[player] = nil
	task.spawn(function()
		local root = waitRoot(player, 5)
		if not root or player.Character ~= char then return end
		local playing = player:GetAttribute("EditorPlaytest") or player:GetAttribute("WorkshopMap") or player:GetAttribute("CoopRun")
		if playing and testSpawn[player] then
			-- died / respawned while testing or playing a Workshop chamber: back to the entry door, with the gun
			task.wait(0.1)
			placeCharacter(player, testSpawn[player])
			local source = player:GetAttribute("EditorPlaytest") and "Editor" or "Workshop"
			task.delay(1, function()
				-- (co-op runs: RigChangerServer gives Atlas / P-body back by itself)
				if player.Character == char and char.Parent and not char:GetAttribute("HasPortalGun") and not player:GetAttribute("CoopRun")
					and (player:GetAttribute("EditorPlaytest") or player:GetAttribute("WorkshopMap"))
					and os.clock() - (lastRig[player] or 0) > 6 then
					rigChange(player, "Equip", { source = source, silent = true })
				end
			end)
		elseif player:GetAttribute("InEditor") then
			park(player)
		end
	end)
end

local function onPlayerAdded(player)
	loadedEvent[player] = true
	player.CharacterAdded:Connect(function(char) onCharacterAdded(player, char) end)
	local data
	if profileStore then
		local ok, d = retry(function() return profileStore:GetAsync("u_" .. player.UserId) end)
		if ok then data = d end
	end
	if not player.Parent then return end
	profiles[player] = reconcile(type(data) == "table" and data or newProfile())
	applyCosmetics(player)
	checkArrival(player)
	local jd = player:GetJoinData()
	local td = jd and jd.TeleportData
	if type(td) == "table" and td.action then
		task.delay(1, function()
			if td.action == "NewGame" then startChapter(player, td.chapter or 1)
			elseif td.action == "LoadGame" then Actions.LoadGame(player, td.saveId) end
			Push:FireClient(player, "SkipMenu", {})
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, pl in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, pl) end

Players.PlayerRemoving:Connect(function(player)
	endCoop(player, true)
	queued[player] = nil
	if QUEUE then pcall(function() QUEUE:RemoveAsync(tostring(player.UserId)) end) end
	saveProfile(player)
	profiles[player] = nil
	loadedEvent[player] = nil
	dirty[player] = nil
	lastPos[player], inside[player], fired[player], lastFire[player] = nil, nil, nil, nil
	lastLockedToast[player] = nil
	leaveSlot(player)
	testSpawn[player], lastRig[player] = nil, nil
	for k in pairs(lastCall) do
		if k:sub(1, #tostring(player.UserId)) == tostring(player.UserId) then lastCall[k] = nil end
	end
end)

game:BindToClose(function()
	local threads = 0
	for _, pl in ipairs(Players:GetPlayers()) do
		threads += 1
		task.spawn(function()
			saveProfile(pl)
			threads -= 1
		end)
	end
	local t0 = os.clock()
	while threads > 0 and os.clock() - t0 < 25 do task.wait() end
end)

task.spawn(function()
	local sinceAuto = 0
	while true do
		task.wait(60)
		sinceAuto += 1
		for _, pl in ipairs(Players:GetPlayers()) do
			local p = profiles[pl]
			if p then p.stats.playtime = (p.stats.playtime or 0) + 60 end
			if Config.AUTOSAVE_MINUTES > 0 and sinceAuto >= Config.AUTOSAVE_MINUTES and pl:GetAttribute("Chapter") and not pl:GetAttribute("InMenu") then
				makeSave(pl, nil, true)
				Push:FireClient(pl, "Autosaved", {})
			end
			if dirty[pl] then task.spawn(saveProfile, pl) end
		end
		if sinceAuto >= Config.AUTOSAVE_MINUTES then sinceAuto = 0 end
	end
end)

-- ==========================================
-- API FOR YOUR OTHER SERVER SCRIPTS
-- ==========================================
shared.PortalData = {
	GetProfile = function(player) return profiles[player] end,
	Unlock = unlock,
	AddProgress = addProgress,
	FinishChapter = finishChapter,
	StartChapter = startChapter,
	Autosave = function(player) return makeSave(player, nil, true) end,
	LoadMap = loadMap, -- LoadMap(name, force, player): loads into that player's own instance
	InstanceSlot = function(player) return slotOf[player] end,
	InstanceFolder = function(player) return activeFolder(player) end,
	Toast = function(player, text) toast(player, text) end,
	PlaceCharacter = placeCharacter,
	RegisterSaveHook = function(name, saveFn, loadFn)
		saveHooks[name] = { save = saveFn, load = loadFn }
	end,
	CountPortal = function(player)
		local p = profiles[player]
		if p then p.stats.portals = (p.stats.portals or 0) + 1 end
		addProgress(player, "PORTALS_100", 1)
		addProgress(player, "PORTALS_1000", 1)
		if player:GetAttribute("ChallengeChamber") then
			player:SetAttribute("ChallengePortals", (player:GetAttribute("ChallengePortals") or 0) + 1)
		end
	end,
	Push = function(player, kind, data) Push:FireClient(player, kind, data) end,
}
