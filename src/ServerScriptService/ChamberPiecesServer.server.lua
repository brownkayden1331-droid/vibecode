-- ChamberPiecesServer
-- ServerScriptService (Script)
-- Runs the editor's moving chamber pieces, crushers and sound blocks in built chambers (tag "PeTIPiece", the item's
-- "Kind" attribute says which). They switch on / off with "Enabled" (buttons, connections, chips, "Start enabled") and
-- go once when a chip "play"s them ("Trigger" attribute).
--
--   Moving Panel / Arm Panel / Arm Panel 2   (PanelTile moves; ChamberPiecesClient bends the arm's bones to follow)
--     Extend  on = comes straight out of the wall Dist tiles, off = back into its socket
--     Door    on = swings open on its bottom edge, off = closes
--     Bounce  on = flips up and flings whatever is on it (players, cubes). Unconnected + Start enabled = every 3 s
--   Crusher  (CrushPlate slams across Reach tiles; CrushState = "CRUSH" -> "Holdcrush" -> "Crushback" -> "Idle")
--     Sensor  crushes when a player is in front of it (while Enabled)
--     Button  crushes when its inputs turn on (Hold = stays down while they're on). Anyone crushed dies.
--   Note Block   on (or play) = plays AudioId at the block, heard up to 50 studs away, pitched by Pitch semitones
--   Music Block  on = plays AudioId as the chamber's music for its players, off = stops it

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("PortalConfig"))
local CELL = Config.CELL

-- ==========================================
-- SETTINGS
-- ==========================================
local EXTEND_TIME = 0.7
local DOOR_TIME = 0.8
local DOOR_ANGLE = 100
local BOUNCE_ANGLE = 55
local BOUNCE_UP_TIME = 0.12
local BOUNCE_DOWN_TIME = 0.6
local BOUNCE_SPEED = 60       -- studs/s things get flung
local BOUNCE_REPEAT = 3       -- seconds between bounces for an unconnected bounce panel
local CRUSH_TIME = 0.28
local HOLD_TIME = 1.2
local CRUSHBACK_TIME = 1.3
local CRUSH_COOLDOWN = 0.6
local NOTE_ROLLOFF = 50       -- note blocks: heard up to this far

local function push(player, kind, data)
	local pd = shared.PortalData
	if pd and pd.Push then pd.Push(player, kind, data) end
end

-- the players in the chamber an item is in (workspace.PortalInstances.Slot_<n>)
local function playersOf(m)
	local node = m
	while node and node.Parent and node.Parent ~= workspace do
		local n = node.Name:match("^Slot_(%d+)$")
		if n and node.Parent.Name == "PortalInstances" then
			local list = {}
			for _, pl in ipairs(Players:GetPlayers()) do
				if pl:GetAttribute("InstanceSlot") == tonumber(n) then table.insert(list, pl) end
			end
			return list
		end
		node = node.Parent
	end
	return Players:GetPlayers() -- placed by hand outside the instances: everyone
end

local function characterOf(part)
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then return m end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function ease(kind, t)
	t = math.clamp(t, 0, 1)
	if kind == "in" then return t * t end
	if kind == "out" then return 1 - (1 - t) * (1 - t) end
	return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2 -- in-out
end

-- one moving part: animates a 0..1 value and applies pose(value) to the part every frame
local movers = {}
local function newMover(part, pose)
	local mv = { part = part, pose = pose, value = 0, from = 0, to = 0, t0 = 0, dur = 0, easing = "inout" }
	movers[mv] = true
	return mv
end
local function moveTo(mv, to, dur, easing)
	mv.from, mv.to, mv.t0, mv.dur, mv.easing = mv.value, to, os.clock(), math.max(dur, 0.01), easing or "inout"
end
local function waitMove(mv)
	while mv.part.Parent and os.clock() - mv.t0 < mv.dur do task.wait() end
end
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for mv in pairs(movers) do
		if not mv.part.Parent then
			movers[mv] = nil
		elseif mv.value ~= mv.to or now - mv.t0 < mv.dur then
			local a = ease(mv.easing, (now - mv.t0) / mv.dur)
			mv.value = mv.from + (mv.to - mv.from) * a
			if now - mv.t0 >= mv.dur then mv.value = mv.to end
			mv.part.CFrame = mv.pose(mv.value)
		end
	end
end)

-- ==========================================
-- MOVING PANELS
-- ==========================================
local function fling(m, tile, dir)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { m }
	local cf = tile.CFrame * CFrame.new(0, 0, -3) -- the space in front of the panel
	local seen = {}
	for _, part in ipairs(workspace:GetPartBoundsInBox(cf, Vector3.new(CELL, CELL, 6), params)) do
		local root = part.AssemblyRootPart
		if root and not seen[root] and not root.Anchored then
			seen[root] = true
			local char = characterOf(part)
			local pl = char and Players:GetPlayerFromCharacter(char)
			local v = dir * BOUNCE_SPEED
			if pl then
				push(pl, "ChipFX", { op = "launch", v = v }) -- (the player's client moves their character)
			elseif not char and not root:GetAttribute("HeldBy") then
				if root:CanSetNetworkOwnership() then root:SetNetworkOwner(nil) end
				root.AssemblyLinearVelocity = v
			end
		end
	end
end

local function setupPanel(m)
	local tile = m:FindFirstChild("PanelTile")
	if not tile then return end
	local base = tile.CFrame
	local mode = m:GetAttribute("PieceMode") or "Extend"
	local dist = (m:GetAttribute("Dist") or 1) * CELL
	-- hinge: the panel's bottom front edge (cf space: -Z out of the wall, the tile's centre is 0.5 behind the surface)
	local hinge = CFrame.new(0, -CELL / 2, -0.5)
	local mv = newMover(tile, function(a)
		if mode == "Extend" then return base * CFrame.new(0, 0, -dist * a) end
		local ang = (mode == "Door" and DOOR_ANGLE or BOUNCE_ANGLE) * a
		return base * hinge * CFrame.Angles(-math.rad(ang), 0, 0) * hinge:Inverse()
	end)

	local busy = false
	local function bounce()
		if busy or not tile.Parent then return end
		busy = true
		-- flung straight out, tipped the way the panel swings
		local out, up = base.LookVector, base.UpVector
		fling(m, tile, (out * 1 + up * 0.35).Unit)
		moveTo(mv, 1, BOUNCE_UP_TIME, "out")
		waitMove(mv)
		moveTo(mv, 0, BOUNCE_DOWN_TIME, "inout")
		waitMove(mv)
		busy = false
	end

	local linked = m:GetAttribute("Linked") == true
	local function apply()
		local on = m:GetAttribute("Enabled") ~= false
		if mode == "Bounce" then
			if on then task.spawn(bounce) end
		else
			moveTo(mv, on and 1 or 0, mode == "Door" and DOOR_TIME or EXTEND_TIME, "inout")
		end
	end
	m:GetAttributeChangedSignal("Enabled"):Connect(apply)
	m:GetAttributeChangedSignal("Trigger"):Connect(function()
		if mode == "Bounce" then
			task.spawn(bounce)
		else
			-- out and back once
			task.spawn(function()
				moveTo(mv, 1, EXTEND_TIME, "inout")
				waitMove(mv)
				task.wait(1)
				moveTo(mv, m:GetAttribute("Enabled") ~= false and 1 or 0, EXTEND_TIME, "inout")
			end)
		end
	end)
	-- the start: extended / open panels start out (no animation), bounce panels nobody connected bounce on their own
	task.defer(function()
		linked = m:GetAttribute("Linked") == true
		local on = m:GetAttribute("Enabled") ~= false
		if mode ~= "Bounce" and on then
			mv.value, mv.to = 1, 1
			tile.CFrame = mv.pose(1)
		end
		if mode == "Bounce" and not linked then
			while m.Parent do
				task.wait(BOUNCE_REPEAT)
				if m:GetAttribute("Enabled") ~= false then bounce() end
			end
		end
	end)
end

-- ==========================================
-- CRUSHERS
-- ==========================================
local function killIn(m, cf, size)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { m }
	for _, part in ipairs(workspace:GetPartBoundsInBox(cf, size, params)) do
		local char = characterOf(part)
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and Players:GetPlayerFromCharacter(char) then hum.Health = 0 end
		else
			-- cubes get squashed (droppers make a new one)
			local root = part.AssemblyRootPart
			if root and not root.Anchored and (root:GetAttribute("CubeType") or CollectionService:HasTag(root, "PortalCube")
				or root:GetAttribute("Grabbable")) then
				local model = root:FindFirstAncestorOfClass("Model")
				if model and model ~= workspace and (model:GetAttribute("CubeType") or CollectionService:HasTag(model, "PortalCube")) then
					model:Destroy()
				else
					root:Destroy()
				end
			end
		end
	end
end

local function setupCrusher(m)
	local plate = m:FindFirstChild("CrushPlate")
	if not plate then return end
	local base = plate.CFrame
	local travel = math.max((m:GetAttribute("Reach") or 1) * CELL - plate.Size.Z - 0.2, 1)
	local mv = newMover(plate, function(a) return base * CFrame.new(0, 0, -travel * a) end)
	local state = "Idle"
	local function setState(s)
		state = s
		m:SetAttribute("CrushState", s)
		m:SetAttribute("CrushStateTime", workspace:GetServerTimeNow())
	end
	setState("Idle")

	local holding = false
	local function crush(hold)
		if state ~= "Idle" or not plate.Parent then return end
		setState("CRUSH")
		moveTo(mv, 1, CRUSH_TIME, "in")
		waitMove(mv)
		setState("Holdcrush")
		local t0 = os.clock()
		while plate.Parent and (os.clock() - t0 < HOLD_TIME or (hold and holding)) do task.wait(0.05) end
		setState("Crushback")
		moveTo(mv, 0, CRUSHBACK_TIME, "inout")
		waitMove(mv)
		task.wait(CRUSH_COOLDOWN)
		if plate.Parent then setState("Idle") end
	end

	-- anyone between the plate and the far wall while it comes down / stays down dies
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not plate.Parent then conn:Disconnect() return end
		if (state == "CRUSH" and mv.value > 0.35) or state == "Holdcrush" then
			killIn(m, plate.CFrame, plate.Size + Vector3.new(0.6, 0.6, 1))
		end
	end)

	local mode = m:GetAttribute("CrusherMode") or "Sensor"
	local hold = m:GetAttribute("Hold") == true
	local wasOn = m:GetAttribute("Enabled") ~= false
	m:GetAttributeChangedSignal("Enabled"):Connect(function()
		local on = m:GetAttribute("Enabled") ~= false
		holding = on
		if mode == "Button" and on and not wasOn then task.spawn(crush, hold) end
		wasOn = on
	end)
	m:GetAttributeChangedSignal("Trigger"):Connect(function() task.spawn(crush, false) end)

	-- sensor: a player in the column in front of it
	if mode == "Sensor" then
		task.spawn(function()
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { m }
			local reach = (m:GetAttribute("Reach") or 1) * CELL
			local zone = base * CFrame.new(0, 0, -reach / 2)
			local size = Vector3.new(CELL - 1, CELL - 1, reach)
			while m.Parent do
				task.wait(0.1)
				if state == "Idle" and m:GetAttribute("Enabled") ~= false then
					for _, part in ipairs(workspace:GetPartBoundsInBox(zone, size, params)) do
						local char = characterOf(part)
						if char and Players:GetPlayerFromCharacter(char) then
							task.spawn(crush, false)
							break
						end
					end
				end
			end
		end)
	end
end

-- ==========================================
-- NOTE BLOCKS / MUSIC BLOCKS
-- ==========================================
local function soundFor(value, kind)
	if type(value) ~= "string" or value == "" then return nil end
	if value:match("^rbxasset://") then
		local s = Instance.new("Sound")
		s.SoundId = value
		return s
	end
	local id = Config.AudioValue(value)
	if id and id:match("^%d+$") then
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. id
		return s
	end
	local found = Config.ChipFindSound(kind, value)
	return found and found:Clone() or nil
end

local function setupNote(m)
	local body = m:FindFirstChild("Body") or m:FindFirstChildWhichIsA("BasePart", true)
	if not body then return end
	local last = 0
	local function play()
		if os.clock() - last < 0.08 then return end
		last = os.clock()
		local s = soundFor(m:GetAttribute("AudioId"), "sound")
		if not s then return end
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 6
		s.RollOffMaxDistance = NOTE_ROLLOFF
		s.Looped = false
		s.Volume = m:GetAttribute("Volume") or 1
		s.PlaybackSpeed = 2 ^ ((m:GetAttribute("Pitch") or 0) / 12) -- semitones
		s.Parent = body
		s:Play()
		Debris:AddItem(s, 12)
	end
	local wasOn = m:GetAttribute("Enabled") ~= false
	m:GetAttributeChangedSignal("Enabled"):Connect(function()
		local on = m:GetAttribute("Enabled") ~= false
		if on and not wasOn then play() end
		wasOn = on
	end)
	m:GetAttributeChangedSignal("Trigger"):Connect(play)
end

local function setupMusic(m)
	local function send(on)
		local audio = m:GetAttribute("AudioId")
		if type(audio) ~= "string" or audio == "" then return end
		local value = Config.AudioValue(audio) or audio
		for _, pl in ipairs(playersOf(m)) do
			push(pl, "ChipFX", { op = "music", text = on and value or "stop" })
		end
	end
	m:GetAttributeChangedSignal("Enabled"):Connect(function() send(m:GetAttribute("Enabled") ~= false) end)
	m:GetAttributeChangedSignal("Trigger"):Connect(function() send(true) end)
	-- starts enabled: plays once the players are in (they arrive a moment after the chamber is built)
	task.delay(2, function()
		if m.Parent and m:GetAttribute("Enabled") ~= false then send(true) end
	end)
	m.AncestryChanged:Connect(function()
		if not m:IsDescendantOf(workspace) then
			for _, pl in ipairs(Players:GetPlayers()) do
				if m:GetAttribute("Enabled") ~= false then push(pl, "ChipFX", { op = "music", text = "stop" }) end
			end
		end
	end)
end

-- ==========================================
local done = setmetatable({}, { __mode = "k" })
local function setup(m)
	if done[m] or not m:IsDescendantOf(workspace) then return end
	done[m] = true
	local kind = m:GetAttribute("Kind")
	local def = Config.ENTITY_TYPES[kind]
	if not def then return end
	local ok, err = pcall(function()
		if def.piece then setupPanel(m)
		elseif kind == "crusher" then setupCrusher(m)
		elseif kind == "noteblock" then setupNote(m)
		elseif kind == "musicblock" then setupMusic(m) end
	end)
	if not ok then warn("[ChamberPieces] " .. tostring(kind) .. ": " .. tostring(err)) end
end
for _, m in ipairs(CollectionService:GetTagged("PeTIPiece")) do task.spawn(setup, m) end
CollectionService:GetInstanceAddedSignal("PeTIPiece"):Connect(function(m) task.defer(setup, m) end)
