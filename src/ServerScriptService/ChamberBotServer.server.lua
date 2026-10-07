-- ChamberBotServer
-- ServerScriptService (Script)
-- NPCs that play a test chamber: the editor records your playtests, then Chell (or Atlas and P-body in co-op) play
-- them back - walking, jumping, shooting the same portals and carrying cubes onto buttons.
--
-- It records, it doesn't think: an NPC repeats a run somebody played. In the editor:
--   File > NPC demo > Keep my last run as the demo      (after you played it, best after reaching the exit)
--   File > NPC demo > Watch the NPC play it             the NPC(s) play the chamber, you watch
--   File > NPC demo > Play alongside the NPC partner    co-op on your own: record Atlas's part first, then play
--                                                        P-body's part while the Atlas NPC does its half
--   File > NPC demo > Add my last run as the partner    keeps that second run, so two NPCs play it together
-- The demo is saved with the chamber (data.demo).
--
-- API for PortalServer (shared.ChamberBots):
--   StartRecording(player, slot, origin)    a playtest began (EditorTest)
--   Finish(player)                          the player reached the exit
--   Take(player) -> tracks                  the last recorded run of the player's chamber (and their partner's)
--   Play(demo, origin, folder)              NPCs play demo inside folder (the chamber's slot folder: they're
--                                           removed with the chamber)
--
-- demo = { tracks = { { color = "Blue" | "Orange" | nil, t0 = seconds, dt = 0.1, done = bool,
--                       frames = { { x, y, z, yaw, flags }, ... },        (relative to the chamber origin)
--                       portals = { { t, "Blue" | "Orange", x, y, z, lx, ly, lz, ux, uy, uz, sx, sy } | { t, name } } } } }
--   flags: 1 = carrying something

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("PortalConfig"))

-- ==========================================
-- SETTINGS
-- ==========================================
local SAMPLE = 0.1          -- seconds between recorded frames
local MAX_FRAMES = 2400     -- 4 minutes
local MAX_PORTAL_EVENTS = 300
local SNAP_DISTANCE = 8     -- a jump bigger than this between two frames = went through a portal: no sliding
local CARRY_OFFSET = CFrame.new(0, 0.5, -4.5)
local RIG_FOR = Config.COOP_RIGS or { Blue = "Atlas", Orange = "PBody" } -- co-op colour -> rig in PortalAssets.Rigs
local PORTAL_COLORS = { Blue = Color3.fromRGB(0, 150, 255), Orange = Color3.fromRGB(255, 120, 0) }

local portalsFolder = workspace:FindFirstChild("Portals")
if not portalsFolder then
	portalsFolder = Instance.new("Folder")
	portalsFolder.Name = "Portals"
	portalsFolder.Parent = workspace
end

local function round(v) return math.floor(v * 100 + 0.5) / 100 end

-- ==========================================
-- RECORDING
-- ==========================================
local sessions = {}   -- [slot] = { t0, origin, order = { player }, tracks = { [player] = track } }
local recording = {}  -- [player] = { session, track, slot }
local lastSession = {} -- [player] = session (the last one they were recorded in)

local function stopRecording(player)
	local r = recording[player]
	if not r then return end
	recording[player] = nil
	r.track.recording = false
	lastSession[player] = r.session
end

local function relCF(cf, origin)
	return cf - origin
end

local function startRecording(player, slot, origin)
	stopRecording(player)
	local now = os.clock()
	local s = sessions[slot]
	-- a fresh run: a new session, unless your partner's run started a moment ago (co-op playtest together)
	if not s or s.tracks[player] or now - s.t0 > 20 then
		s = { t0 = now, origin = origin, order = {}, tracks = {} }
		sessions[slot] = s
	end
	local track = { t0 = round(now - s.t0), dt = SAMPLE, frames = {}, portals = {}, start = now, recording = true,
		color = player:GetAttribute("CoopColor") }
	s.tracks[player] = track
	table.insert(s.order, player)
	recording[player] = { session = s, track = track, slot = slot, next = now }
	lastSession[player] = s
end

local function heldBy(player, root)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	for _, p in ipairs(workspace:GetPartBoundsInRadius(root.Position, 10, params)) do
		local r = p.AssemblyRootPart
		if r and r:GetAttribute("HeldBy") == player.UserId then return true end
	end
	return false
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for player, r in pairs(recording) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not player.Parent or not player:GetAttribute("EditorPlaytest") or #r.track.frames >= MAX_FRAMES then
			stopRecording(player)
		elseif root and now >= r.next then
			r.next = now + SAMPLE
			local cf = relCF(root.CFrame, r.session.origin)
			local look = cf.LookVector
			table.insert(r.track.frames, { round(cf.X), round(cf.Y), round(cf.Z), round(math.atan2(-look.X, -look.Z)),
				heldBy(player, root) and 1 or 0 })
		end
	end
end)

-- portals the recorded players shoot
portalsFolder.ChildAdded:Connect(function(p)
	task.defer(function()
		if not p:IsA("BasePart") then return end
		local owner = Players:GetPlayerByUserId(tonumber(p:GetAttribute("OwnerUserId")) or 0)
		local r = owner and recording[owner]
		if not r or #r.track.portals >= MAX_PORTAL_EVENTS then return end
		local cf = relCF(p.CFrame, r.session.origin)
		local look, up = cf.LookVector, cf.UpVector
		table.insert(r.track.portals, { round(os.clock() - r.track.start), p:GetAttribute("PortalName") or "Blue",
			round(cf.X), round(cf.Y), round(cf.Z), round(look.X), round(look.Y), round(look.Z), round(up.X), round(up.Y), round(up.Z),
			round(p.Size.X), round(p.Size.Y) })
		p.AncestryChanged:Connect(function()
			if p.Parent == nil and recording[owner] == r and #r.track.portals < MAX_PORTAL_EVENTS then
				table.insert(r.track.portals, { round(os.clock() - r.track.start), p:GetAttribute("PortalName") or "Blue" })
			end
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(p)
	stopRecording(p)
	lastSession[p] = nil
end)

local function take(player)
	local s = lastSession[player]
	if not s then return nil end
	local out = {}
	for _, pl in ipairs(s.order) do
		local t = s.tracks[pl]
		if t and #t.frames > 5 then
			table.insert(out, { color = t.color, t0 = t.t0, dt = t.dt, done = t.done == true, frames = t.frames, portals = t.portals,
				name = pl.Name })
		end
	end
	return #out > 0 and out or nil
end

-- ==========================================
-- PLAYBACK
-- ==========================================
local function squash(s) return (string.lower(s):gsub("[^%w]", "")) end
local function findRig(name)
	local assets = ReplicatedStorage:FindFirstChild("PortalAssets")
	local rigs = assets and assets:FindFirstChild("Rigs")
	if not rigs then return nil end
	local want = squash(name)
	for _, m in ipairs(rigs:GetChildren()) do
		if m:IsA("Model") and squash(m.Name) == want then return m end
	end
	for _, m in ipairs(rigs:GetChildren()) do
		if m:IsA("Model") and string.find(squash(m.Name), want, 1, true) then return m end
	end
	return nil
end

local function makeNpc(color, folder)
	local template = findRig(RIG_FOR[color] or "Chell") or findRig("Chell")
	local npc
	if template then
		npc = template:Clone()
	else
		-- no rigs in PortalAssets.Rigs: a plain R15 dummy
		local ok, m = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if not ok then return nil end
		npc = m
	end
	npc.Name = (RIG_FOR[color] or "Chell") .. " (NPC)"
	npc:SetAttribute("ChamberBot", true)

	-- its walk / idle animations, read from the rig's Animate script before every script is taken out
	local anims = {}
	local animate = npc:FindFirstChild("Animate")
	if animate then
		for _, key in ipairs({ "idle", "walk", "run", "jump", "fall" }) do
			local holder = animate:FindFirstChild(key)
			local a = holder and holder:FindFirstChildWhichIsA("Animation")
			if a then anims[key] = a:Clone() end
		end
	end
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then d:Destroy() end
	end
	local hum = npc:FindFirstChildOfClass("Humanoid") or Instance.new("Humanoid", npc)
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.MaxHealth, hum.Health = math.huge, math.huge
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
	if not root then npc:Destroy() return nil end
	npc.PrimaryPart = root
	-- the NPC goes where the recording says: anchored, and players walk through it. Buttons still see it (they look
	-- for a Humanoid in their box).
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Anchored = d == root
		end
	end
	npc.Parent = folder

	local tracks = {}
	for key, a in pairs(anims) do
		local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
		if ok then tracks[key] = tr end
	end
	return npc, root, tracks
end

local function makePortal(ev, origin, botId)
	local p = Instance.new("Part")
	p.Name = ev[2] .. "Portal"
	p.Size = Vector3.new(ev[12] or 4.35, ev[13] or 7.6, 0.02)
	p.Color = PORTAL_COLORS[ev[2]] or PORTAL_COLORS.Blue
	p.Transparency = 1
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	local pos = origin + Vector3.new(ev[3], ev[4], ev[5])
	local look, up = Vector3.new(ev[6], ev[7], ev[8]), Vector3.new(ev[9], ev[10], ev[11])
	p.CFrame = CFrame.lookAt(pos, pos + look, up)
	p:SetAttribute("OwnerUserId", botId)
	p:SetAttribute("PortalName", ev[2])
	p:SetAttribute("Opened", true)
	p:SetAttribute("SpawnTime", workspace:GetServerTimeNow())
	p:SetAttribute("ChamberBot", true)
	p.Parent = portalsFolder
	return p
end

local function isLoose(r)
	return r and not r.Anchored and r:GetAttribute("HeldBy") == nil
end

local function nearestCube(pos, folder)
	local best, bestD
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and (CollectionService:HasTag(d, "PortalCube") or d:GetAttribute("CubeType") or d:GetAttribute("Grabbable")) then
			local r = d.AssemblyRootPart
			if isLoose(r) then
				local dist = (r.Position - pos).Magnitude
				if dist < 14 and (not bestD or dist < bestD) then best, bestD = r, dist end
			end
		end
	end
	for _, m in ipairs(CollectionService:GetTagged("PortalCube")) do
		local r = m:IsA("BasePart") and m.AssemblyRootPart or (m:IsA("Model") and m.PrimaryPart and m.PrimaryPart.AssemblyRootPart)
		if isLoose(r) and r:IsDescendantOf(folder) then
			local dist = (r.Position - pos).Magnitude
			if dist < 14 and (not bestD or dist < bestD) then best, bestD = r, dist end
		end
	end
	return best
end

local botCounter = 0
local function playTrack(track, origin, folder)
	botCounter += 1
	local botId = -1000 - botCounter -- (not a real user: portals still pair up by owner)
	local npc, root, anims = makeNpc(track.color, folder)
	if not npc then warn("[ChamberBots] couldn't make an NPC (no rig in PortalAssets.Rigs?)") return end
	local frames, dt = track.frames, track.dt or SAMPLE
	local myPortals = {}
	local carried, playing = nil, nil
	local function setAnim(key)
		if playing == key then return end
		if playing and anims[playing] then anims[playing]:Stop(0.15) end
		playing = key
		if anims[key] then anims[key]:Play(0.15) end
	end
	local function frameCF(i)
		local f = frames[i]
		return CFrame.new(origin + Vector3.new(f[1], f[2], f[3])) * CFrame.Angles(0, f[4], 0)
	end
	root.CFrame = frameCF(1)
	local function cleanup()
		for _, p in pairs(myPortals) do if p.Parent then p:Destroy() end end
		if carried and carried.Parent then
			carried.Anchored = false
			carried:SetAttribute("HeldBy", nil)
		end
		if npc.Parent then npc:Destroy() end
	end

	task.spawn(function()
		task.wait(track.t0 or 0)
		local start = os.clock()
		local nextPortal = 1
		local lastPos = root.Position
		local frameDt = 1 / 60
		while npc.Parent and folder.Parent do
			local t = os.clock() - start
			local fi = t / dt + 1
			local i = math.floor(fi)
			if i >= #frames then break end
			local a = frames[i]
			local cfA, cfB = frameCF(i), frameCF(i + 1)
			local cf
			if (cfB.Position - cfA.Position).Magnitude > SNAP_DISTANCE then
				cf = (fi - i) < 0.5 and cfA or cfB -- went through a portal: no sliding through walls
			else
				cf = cfA:Lerp(cfB, fi - i)
			end
			root.CFrame = cf

			-- animation from how it moves
			local step = cf.Position - lastPos
			lastPos = cf.Position
			local flat = Vector3.new(step.X, 0, step.Z).Magnitude / math.max(frameDt, 1e-3)
			if math.abs(step.Y) / math.max(frameDt, 1e-3) > 8 then setAnim(anims.fall and "fall" or "idle")
			elseif flat > 1 then setAnim(anims.run and "run" or "walk")
			else setAnim("idle") end

			-- portals
			while nextPortal <= #track.portals and track.portals[nextPortal][1] <= t do
				local ev = track.portals[nextPortal]
				nextPortal += 1
				local name = ev[2]
				if myPortals[name] then myPortals[name]:Destroy() myPortals[name] = nil end
				if ev[3] then myPortals[name] = makePortal(ev, origin, botId) end
			end

			-- carrying: picks up the nearest cube when the recording starts carrying, puts it down when it stops
			local holding = (a[5] or 0) % 2 == 1
			if holding and not carried then
				carried = nearestCube(cf.Position, folder)
				if carried then
					carried:SetAttribute("HeldBy", botId)
					carried.Anchored = true
				end
			elseif not holding and carried then
				carried.Anchored = false
				carried.AssemblyLinearVelocity = Vector3.zero
				carried:SetAttribute("HeldBy", nil)
				carried = nil
			end
			if carried then
				if carried.Parent then carried.CFrame = cf * CARRY_OFFSET else carried = nil end
			end
			frameDt = RunService.Heartbeat:Wait()
		end
		-- the run is over: drop what it holds, wave goodbye after a moment
		if carried and carried.Parent then
			carried.Anchored = false
			carried:SetAttribute("HeldBy", nil)
			carried = nil
		end
		setAnim("idle")
		task.wait(3)
		cleanup()
	end)
	npc.AncestryChanged:Connect(function()
		if not npc.Parent then cleanup() end
	end)
end

local function play(demo, origin, folder)
	if type(demo) ~= "table" or type(demo.tracks) ~= "table" then return 0 end
	local n = 0
	for _, track in ipairs(demo.tracks) do
		if type(track.frames) == "table" and #track.frames > 1 then
			playTrack(track, origin, folder)
			n += 1
		end
	end
	return n
end

shared.ChamberBots = {
	StartRecording = startRecording,
	StopRecording = stopRecording,
	Finish = function(player)
		local r = recording[player]
		if r then r.track.done = true end
		stopRecording(player)
	end,
	Take = take,
	Play = play,
}
