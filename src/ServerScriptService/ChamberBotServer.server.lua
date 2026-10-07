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

-- physical = the NPC walks with physics (autonomous play) instead of being placed where a recording says
local function makeNpc(color, folder, physical)
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
			if physical then
				d.Anchored = false
			else
				d.CanCollide = false
				d.Anchored = d == root
			end
		end
	end
	npc.Parent = folder
	if physical then pcall(function() root:SetNetworkOwner(nil) end) end

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

-- ==========================================
-- AUTONOMOUS PLAY ("Watch the NPC play on its own")
-- The NPC works the chamber out itself, using every run it was taught (data.demo.tracks + data.demo.learn):
--   * the plan: what opens the exit (connections, through logic gates, back to buttons / pedestals); which cube
--     goes on which button and in what order comes from the runs (where you picked cubes up / put them down)
--   * walking: PathfindingService (jumps included)
--   * anything it can't walk to (portals, funnels, faith plates): it finds a stretch of a taught run from about
--     where it is to about where it has to be, and does that stretch (with that run's portals)
-- ==========================================
local PathfindingService = game:GetService("PathfindingService")
local NEAR = 6          -- "about here" for matching taught runs (studs)
local GOAL_REACH = 3.5  -- close enough to a walk target

-- every taught run, as world positions, with its pickup / drop moments
local function learnRuns(demo, origin)
	local runs = {}
	if type(demo) ~= "table" then return runs end
	local all = {}
	for _, t in ipairs(demo.tracks or {}) do table.insert(all, t) end
	for _, t in ipairs(demo.learn or {}) do table.insert(all, t) end
	for _, t in ipairs(all) do
		local frames = t.frames or {}
		if #frames > 2 then
			local run = { dt = t.dt or SAMPLE, pos = {}, carry = {}, portals = t.portals or {}, picks = {}, drops = {}, speed = 0 }
			local moving, dist = 0, 0
			for i, f in ipairs(frames) do
				run.pos[i] = origin + Vector3.new(f[1], f[2], f[3])
				run.carry[i] = (f[5] or 0) % 2 == 1
				if i > 1 then
					local d = (run.pos[i] - run.pos[i - 1]) * Vector3.new(1, 0, 1)
					if d.Magnitude / run.dt > 3 and d.Magnitude < SNAP_DISTANCE then moving += 1 dist += d.Magnitude end
					if run.carry[i] and not run.carry[i - 1] then table.insert(run.picks, { i = i, pos = run.pos[i] }) end
					if not run.carry[i] and run.carry[i - 1] then table.insert(run.drops, { i = i, pos = run.pos[i] }) end
				end
			end
			run.speed = moving > 0 and dist / (moving * run.dt) or 0
			table.insert(runs, run)
		end
	end
	return runs
end

-- a stretch of a taught run from near `from` to near `to` (the shortest one found): run, i, j
local function findStretch(runs, from, to)
	local best, bi, bj, blen
	for _, run in ipairs(runs) do
		for i = 1, #run.pos do
			if (run.pos[i] - from).Magnitude < NEAR then
				for j = i + 1, math.min(#run.pos, i + 1200) do
					if (run.pos[j] - to).Magnitude < NEAR then
						if not blen or j - i < blen then best, bi, bj, blen = run, i, j, j - i end
						break
					end
				end
			end
		end
	end
	return best, bi, bj
end

local function autoPlay(data, origin, folder, startCF, count)
	local runs = learnRuns(data.demo, origin)
	local items = {}   -- id -> { e = entity, model = built model }
	for _, d in ipairs(folder:GetDescendants()) do
		local id = d:IsA("Model") and d:GetAttribute("EntId")
		if id then items[id] = items[id] or { model = d } end
	end
	for _, e in ipairs(data.ents or {}) do
		if e[8] and items[e[8]] then items[e[8]].e = e end
	end
	local function itemPos(it) return it.model and it.model.Parent and it.model:GetPivot().Position or Config.EntityCFrame(origin, it.e).Position end
	local exit
	for _, it in pairs(items) do if it.e and it.e[1] == "exit" then exit = it end end
	if not exit then warn("[ChamberBots] no exit door") return 0 end

	-- ----- the plan: what has to be on for the exit to open -----
	local inputs = {}
	for _, l in ipairs(data.links or {}) do
		inputs[l[2]] = inputs[l[2]] or {}
		table.insert(inputs[l[2]], l[1])
	end
	local needs, seen = {}, {}
	local function need(id)
		if seen[id] then return end
		seen[id] = true
		local it = items[id]
		local kind = it and it.e and it.e[1]
		if not kind then return end
		if kind == "gate" then
			local mode = Config.GateMode(it.e)
			local ins = inputs[id] or {}
			if mode == "NOT" or mode == "NOR" or mode == "NAND" then return end -- (true while its inputs are off)
			if mode == "OR" or mode == "XOR" then
				-- one is enough: a floor button first (the NPC can do those for sure)
				table.sort(ins, function(a, b)
					local ka = items[a] and items[a].e and items[a].e[1]
					return ka == "button" and (items[b] and items[b].e and items[b].e[1]) ~= "button"
				end)
				if ins[1] then need(ins[1]) end
				return
			end
			for _, s in ipairs(ins) do need(s) end
		elseif kind == "button" or kind == "pedestal" or kind == "trigger" then
			table.insert(needs, it)
		elseif kind == "delay" then
			for _, s in ipairs(inputs[id] or {}) do need(s) end
		end
	end
	if not Config.ExitFree(exit.e) then
		for _, s in ipairs(inputs[exit.e[8]] or {}) do need(s) end
		if #needs == 0 then
			-- (chips / lasers open it: press every button there is and hope)
			for _, it in pairs(items) do
				if it.e and (it.e[1] == "button" or it.e[1] == "pedestal") then table.insert(needs, it) end
			end
		end
	end
	-- the order you did them in (where your taught runs put cubes down / stood)
	local learnedOrder = {}
	for _, run in ipairs(runs) do
		for k, dr in ipairs(run.drops) do
			for _, it in ipairs(needs) do
				if (itemPos(it) - dr.pos).Magnitude < 8 then
					learnedOrder[it] = math.min(learnedOrder[it] or math.huge, k)
				end
			end
		end
	end
	table.sort(needs, function(a, b) return (learnedOrder[a] or 99) < (learnedOrder[b] or 99) end)

	local walkSpeed = 16
	do
		local sum, n = 0, 0
		for _, run in ipairs(runs) do if run.speed > 4 then sum += run.speed n += 1 end end
		if n > 0 then walkSpeed = math.clamp(sum / n, 10, 22) end -- moves as fast as you did
	end

	-- ----- the NPCs -----
	local botsDone = 0
	local claimedCubes, claimedNeeds = {}, {}
	local started = os.clock()
	local function cubes()
		local list = {}
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("BasePart") and (d:GetAttribute("CubeType") or CollectionService:HasTag(d, "PortalCube") or d:GetAttribute("Grabbable")) then
				local r = d.AssemblyRootPart
				if r and not r.Anchored and not r:GetAttribute("HeldBy") and not claimedCubes[r] and not table.find(list, r) then table.insert(list, r) end
			end
		end
		return list
	end
	local function onButton(it)
		return it.model and (it.model:GetAttribute("Pressed") == true or it.model:GetAttribute("PressesButton") == true)
	end

	local function runBot(index, color)
		botCounter += 1
		local botId = -1000 - botCounter
		local npc, root, anims = makeNpc(color, folder, true)
		if not npc then return end
		local hum = npc:FindFirstChildOfClass("Humanoid")
		hum.WalkSpeed = walkSpeed
		hum.UseJumpPower = false
		hum.JumpHeight = 7.2
		npc:PivotTo(startCF * CFrame.new((index - 1) * 3, 0, 0))
		local playing
		local function setAnim(key)
			if playing == key then return end
			if playing and anims[playing] then anims[playing]:Stop(0.15) end
			playing = key
			if anims[key] then anims[key]:Play(0.15) end
		end
		hum.Running:Connect(function(sp) if sp > 1 then setAnim(anims.run and "run" or "walk") else setAnim("idle") end end)
		hum.StateChanged:Connect(function(_, st)
			if st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping then setAnim(anims.fall and "fall" or "idle") end
		end)
		local myPortals, carried = {}, nil
		local function alive() return npc.Parent ~= nil and folder.Parent ~= nil end
		local function say(text) for _, pl in ipairs(Players:GetPlayers()) do if pl:GetAttribute("EditorPlaytest") then
			local pd = shared.PortalData
			if pd and pd.Toast then pd.Toast(pl, npc.Name .. ": " .. text) end
		end end end

		local function carryStep()
			if carried and carried.Parent then carried.CFrame = root.CFrame * CARRY_OFFSET end
		end
		local carryConn = RunService.Heartbeat:Connect(carryStep)

		-- do a stretch of a taught run (portals included): what it learned for places it can't walk to
		local function doStretch(run, i, j)
			root.Anchored = true
			local t0 = (i - 1) * run.dt
			-- the portals that were up at that moment
			local latest = {}
			for _, ev in ipairs(run.portals) do if ev[1] <= t0 then latest[ev[2]] = ev end end
			for name, ev in pairs(latest) do
				if myPortals[name] then myPortals[name]:Destroy() myPortals[name] = nil end
				if ev[3] then myPortals[name] = makePortal(ev, origin, botId) end
			end
			local nextEv = 1
			while nextEv <= #run.portals and run.portals[nextEv][1] <= t0 do nextEv += 1 end
			for k = i, j - 1 do
				if not alive() then return end
				local a, b = run.pos[k], run.pos[k + 1]
				local dir = (b - a) * Vector3.new(1, 0, 1)
				local look = dir.Magnitude > 0.05 and dir.Unit or root.CFrame.LookVector
				local steps = (b - a).Magnitude > SNAP_DISTANCE and 1 or 6
				for s2 = 1, steps do
					local p = a:Lerp(b, s2 / steps)
					root.CFrame = CFrame.lookAt(p, p + look)
					setAnim(dir.Magnitude / run.dt > 2 and (anims.run and "run" or "walk") or "idle")
					task.wait(run.dt / steps)
				end
				local t = k * run.dt
				while nextEv <= #run.portals and run.portals[nextEv][1] <= t do
					local ev = run.portals[nextEv]
					nextEv += 1
					if myPortals[ev[2]] then myPortals[ev[2]]:Destroy() myPortals[ev[2]] = nil end
					if ev[3] then myPortals[ev[2]] = makePortal(ev, origin, botId) end
				end
			end
			root.Anchored = false
		end

		-- walk to a point: pathfinding, else a taught stretch. true when it got there
		local function goTo(target)
			for attempt = 1, 3 do
				if not alive() then return false end
				if (root.Position - target).Magnitude < GOAL_REACH then return true end
				local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5.5, AgentCanJump = true, WaypointSpacing = 4 })
				local ok = pcall(function() path:ComputeAsync(root.Position, target) end)
				if ok and path.Status == Enum.PathStatus.Success then
					local stuck = false
					for _, wp in ipairs(path:GetWaypoints()) do
						if not alive() then return false end
						if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
						hum:MoveTo(wp.Position)
						local t0 = os.clock()
						while alive() and (root.Position - wp.Position) * Vector3.new(1, 0, 1) ~= Vector3.zero
							and ((root.Position - wp.Position) * Vector3.new(1, 0, 1)).Magnitude > 2 do
							if os.clock() - t0 > 2.5 then stuck = true break end
							task.wait(0.05)
						end
						if stuck then break end
					end
					if not stuck and (root.Position - target).Magnitude < GOAL_REACH + 2 then return true end
				end
				-- can't walk there: what did the taught runs do from about here?
				local run, i, j = findStretch(runs, root.Position, target)
				if run then
					doStretch(run, i, j)
					if (root.Position - target).Magnitude < NEAR + 1 then return true end
				elseif attempt == 3 then
					say("I don't know how to get there yet. Teach me with a run that does (File > NPC demo).")
					return false
				end
				hum.Jump = true
				task.wait(0.3)
			end
			return false
		end

		local function pressPedestal(it)
			local el = it.model
			for _, d in ipairs(it.model:GetDescendants()) do
				if d:IsA("Model") and CollectionService:HasTag(d, "PedestalButton") then el = d break end
			end
			el:SetAttribute("Pressed", true)
			task.delay(tonumber(el:GetAttribute("TimerLength")) or 3, function() if el.Parent then el:SetAttribute("Pressed", false) end end)
		end

		task.spawn(function()
			task.wait(1 + index * 0.4)
			for _, it in ipairs(needs) do
				if not alive() then break end
				if not claimedNeeds[it] and not onButton(it) then
					claimedNeeds[it] = index
					local kind = it.e[1]
					local spot = itemPos(it)
					if kind == "pedestal" then
						if goTo(spot + (Config.EntityCFrame(origin, it.e).UpVector * 0)) then pressPedestal(it) end
					elseif kind == "trigger" then
						goTo(spot)
					else
						-- a floor button: a cube on it (the one your runs used if they did), else stand on it (co-op: the
						-- other NPC carries on)
						local list = cubes()
						table.sort(list, function(a, b) return (a.Position - spot).Magnitude < (b.Position - spot).Magnitude end)
						local cube = list[1]
						if not cube then
							-- no loose cube: ask the droppers for one and give it a moment
							for _, d in ipairs(folder:GetDescendants()) do
								if CollectionService:HasTag(d, "CubeDropper") then d:SetAttribute("Drop", true) end
							end
							task.wait(3)
							cube = cubes()[1]
						end
						if cube and goTo(cube.Position) then
							claimedCubes[cube] = true
							carried = cube
							cube:SetAttribute("HeldBy", botId)
							cube.Anchored = true
							for _, pp in ipairs(cube:GetConnectedParts(true)) do pp.CanCollide = false end
							if goTo(spot) then
								carried = nil
								cube.CFrame = CFrame.new(spot + Vector3.new(0, 3, 0))
								cube.Anchored = false
								for _, pp in ipairs(cube:GetConnectedParts(true)) do pp.CanCollide = pp.Name ~= "Lens" end
								cube:SetAttribute("HeldBy", nil)
								root.CFrame = root.CFrame * CFrame.new(0, 0, 3) -- step back off the button
							end
						elseif count > 1 and index == count then
							goTo(spot) -- the last NPC holds the button down for the other one
							return
						else
							goTo(spot)
						end
					end
					task.wait(0.5)
				end
			end
			-- the exit: wait for it to open, then out
			local exitPos = itemPos(exit) + Config.EntityCFrame(origin, exit.e).LookVector * 4
			local t0 = os.clock()
			while alive() and exit.model and exit.model:GetAttribute("Enabled") ~= true and os.clock() - t0 < 20 do task.wait(0.2) end
			if goTo(exitPos) then
				botsDone += 1
				say(("Solved it in %.1f s."):format(os.clock() - started))
			end
			setAnim("idle")
			task.wait(4)
			carryConn:Disconnect()
			for _, pt in pairs(myPortals) do if pt.Parent then pt:Destroy() end end
			if npc.Parent then npc:Destroy() end
		end)
		npc.AncestryChanged:Connect(function()
			if not npc.Parent then
				carryConn:Disconnect()
				for _, pt in pairs(myPortals) do if pt.Parent then pt:Destroy() end end
			end
		end)
	end

	local colors = count > 1 and { "Blue", "Orange" } or { nil }
	for i = 1, count do runBot(i, colors[i]) end
	return count
end

shared.ChamberBots = {
	AutoPlay = autoPlay,
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
