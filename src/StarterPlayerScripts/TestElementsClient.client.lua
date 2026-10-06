-- TestElementsClient
-- StarterPlayerScripts (LocalScript)
-- Excursion funnels, your side:
--   * spins the funnel's "Rotator" bone (arms + inner mechanism)
--   * draws the Portal 2 funnel look (helix ribbons, haze, dots, emitter ring/tips/wisps)
--   * carries YOU along any funnel you're inside (through portals too)
--   * enter whoosh when you get pulled in + the funnel loop while you ride
--
-- Your Source movement script should skip its update while
-- player:GetAttribute("InFunnel") is true (same as GelStuck).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local portalAssets = ReplicatedStorage:WaitForChild("PortalAssets")
local Gel = require(portalAssets:WaitForChild("GelShared"))
local portalsFolder = workspace:WaitForChild("Portals")

-- ==========================================
-- SETTINGS: carrying + arms
-- ==========================================
local SPIN_SPEED = 1.4        -- radians/s the arms turn
local SPIN_EASE = 2.5
local CENTER_PULL = 7.5       -- how firmly you're drawn back to the centre line once you stop moving
local CENTER_PULL_MAX = 18     -- never faster than this (studs/s)
local PULL_EASE = 3.5         -- how slowly the pull fades in when you let go (and out when you move)
local STEER_SPEED = 16        -- studs/s you can move sideways: fast enough to glide out of the side
local END_HOVER = 2
local ENTER_SMOOTH = 18
local START_REACH = 10       -- studs behind the emitter mouth where the funnel already catches you
local MAX_FUNNEL = 800       -- studs a funnel can reach in total (through portals too)
local MAX_PORTAL_HOPS = 8
-- Portal 2: a funnel catches you mid-air, even when you're flung through it fast
local CATCH_SWEEP = true      -- also check the path you flew along since last frame (no tunnelling through at speed)
local CATCH_STOP = true       -- entering kills your momentum at once (you hang in the funnel) instead of easing in

-- ==========================================
-- SETTINGS: funnel look
-- ==========================================
-- PASTE THE NEW IMAGE IDS HERE (upload funnel_textures/*.png, then Asset Manager > Copy ID).
-- Empty = the script falls back to plain beams / built-in sparkles.
local WISP_TEXTURE = "rbxassetid://115109186806028"   -- FunnelWisp.png  (streaked ribbon)
local HAZE_TEXTURE = "rbxassetid://75096577001613"   -- FunnelHaze.png  (soft cloud puff)
local SPECK_TEXTURE = "rbxassetid://103287895754358"   -- FunnelSpeck.png (round glowing dot)
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" -- built in: soft puffs for the haze
local DEFAULT_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- a bare number or "rbxasset://123" is turned into "rbxassetid://123"
local function fixId(id)
	if id:match("^%d+$") then return "rbxassetid://" .. id end
	return (id:gsub("^rbxasset://(%d+)$", "rbxassetid://%1"))
end
WISP_TEXTURE, HAZE_TEXTURE, SPECK_TEXTURE = fixId(WISP_TEXTURE), fixId(HAZE_TEXTURE), fixId(SPECK_TEXTURE)

local FUNNEL_BLUE = Color3.fromRGB(40, 130, 255)   -- keep in sync with the server
local FUNNEL_ORANGE = Color3.fromRGB(255, 130, 30)

--               phase(deg)  radius(x funnel radius)  kind
local STRANDS = {
	{ 0,   1.0,  "line" },   -- the three bright spiral lines (+ ribbon streaks behind each)
	{ 120, 1.0,  "line" },
	{ 240, 1.0,  "line" },
	{ -16, 1.0,  "wisp" },   -- streaked ribbon sheets trailing each line (need the WISP texture)
	{ 104, 1.0,  "wisp" },
	{ 224, 1.0,  "wisp" },
}
local STRAND_TURN = 18         -- studs per full twist
local STRAND_STEP = 120         -- degrees between points (beams curve smoothly between)
local LINE_WIDTH = 0.16
local LINE_GLOW_WIDTH = 0.8
local LINE_BRIGHTNESS = 2
local LINE_EMISSION = 0.25     -- low = stays BLUE instead of turning white
local RIBBON_HAIRS = 4         -- fine streaks trailing each bright line (the ribbon sheet)
local RIBBON_SPREAD = 40       -- degrees the sheet fans out behind each line
local HAIR_WIDTH = 0.06
local WISP_WIDTH = 2.0
local WISP_TRANSPARENCY = 0.4
local STRAND_SPIN = 0.9        -- radians/s the whole spiral turns
local STRAND_FLOW = 1.2        -- how fast glow slides along the strands
local STRAND_CURVE_FLIP = false -- strands look kinked/looped? set true
local HAIR_RANGE = 70    -- studs around you where the fine streaks are drawn
local WISP_RANGE = 140   -- studs around you where the ribbon sheets are drawn
local FX_WINDOW = 360          -- studs of funnel drawn around you
local FX_RANGE = 300

local HAZE_ON = true           -- the blue/orange fog that tints the walls (image 6)
local HAZE_SIZE = { 5, 9 }
local HAZE_TRANSPARENCY = 0.82

-- Emitter look
local TIP_GLOW_SIZE = 0.5
local TIP_LIGHT_RANGE = 12
local TIP_LIGHT_BRIGHTNESS = 2
local RING_WIDTH = 0.16        -- bright core of the ring joining the tips
local RING_GLOW_WIDTH = 0.8
local RING_CURVE_FLIP = false  -- ring arcs loop/bend inward? set true
local STREAM_HEIGHT = 9        -- studs the wisps take to curl out from the tips into the funnel
local STREAM_POINTS = 14
local MOUTH_GLOW = true        -- soft glow in the emitter opening


-- ==========================================
-- TEXTURE CHECK (bad id = squares / invisible beams)
-- ==========================================
local wispOk, speckOk = WISP_TEXTURE ~= "", SPECK_TEXTURE ~= ""

local function stripTexture(id, replacement)
	for _, d in ipairs(workspace:GetDescendants()) do
		if (d:IsA("Beam") or d:IsA("ParticleEmitter")) and d.Texture == id then
			d.Texture = replacement
		end
	end
end

local function checkTexture(id, label, onFail)
	if id == "" then return end
	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ id }, function(_, status)
				if status ~= Enum.AssetFetchStatus.Success then
					onFail()
				end
			end)
		end)
		if not ok then onFail() end
	end)
end

checkTexture(WISP_TEXTURE, "WISP", function()
	local bad = WISP_TEXTURE
	wispOk = false
	WISP_TEXTURE = ""
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Beam") and d.Texture == bad then
			if d.Width0 > 1.5 then d:Destroy() else d.Texture = "" end
		end
	end
end)
checkTexture(HAZE_TEXTURE, "HAZE", function()
	local bad = HAZE_TEXTURE
	HAZE_TEXTURE = ""
	stripTexture(bad, SMOKE_TEXTURE)
end)
checkTexture(SPECK_TEXTURE, "SPECK", function()
	local bad = SPECK_TEXTURE
	speckOk = false
	SPECK_TEXTURE = ""
	stripTexture(bad, DEFAULT_SPARKLE)
end)

local function isFunnel(m)
	local n = string.lower(m.Name)
	return n:find("tractor") or n:find("funnel") or n:find("excursion") or n:find("tbeam")
end

-- ==========================================
-- TEST ELEMENT SOUNDS (CLIENT-SIDE, 3D)
-- ==========================================
local soundsRoot = portalAssets:WaitForChild("Sounds")
local soundsFolder = soundsRoot:WaitForChild("Testelements")
local elementSounds = {}

-- funnel: whoosh when YOU get pulled in + the funnel loop while you ride (2D, on you)
-- Sounds/Testelements/Tractor/Enter can be a folder of sounds (a random one plays) or one sound.
local tractorSounds = soundsFolder:FindFirstChild("Tractor")
local enterSounds = tractorSounds and tractorSounds:FindFirstChild("Enter")
local lastEnterSound = 0
local rideLoop, rideLoopName = nil, nil

local function playFunnelEnter()
	if not enterSounds or os.clock() - lastEnterSound < 0.5 then return end
	local list = {}
	if enterSounds:IsA("Sound") then table.insert(list, enterSounds) end
	for _, s in ipairs(enterSounds:GetDescendants()) do
		if s:IsA("Sound") then table.insert(list, s) end
	end
	if #list == 0 then return end
	lastEnterSound = os.clock()
	local s = list[math.random(#list)]:Clone()
	s.Looped = false
	s.Parent = SoundService -- 2D: it's your whoosh
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(10, function() if s.Parent then s:Destroy() end end)
end

local function setRideLoop(name) -- nil = stop
	if rideLoopName == name then return end
	if rideLoop then
		rideLoop:Destroy()
		rideLoop = nil
	end
	rideLoopName = name
	if not name then return end
	local src = soundsFolder:FindFirstChild(name, true)
	if src and src:IsA("Sound") then
		rideLoop = src:Clone()
		rideLoop.Looped = true
		rideLoop.Parent = SoundService
		rideLoop:Play()
	end
end

local function soundTemplate(name)
	local s = soundsFolder:FindFirstChild(name, true)
	return s and s:IsA("Sound") and s or nil
end

local function soundPart(m)
	local preferred = {"HitBox", "Middle", "Root", "Base", "Emitter", "Part"}
	for _, name in ipairs(preferred) do
		local p = m:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then return p end
	end
	if m:IsA("Model") and m.PrimaryPart then return m.PrimaryPart end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local function elementKind(m)
	local n = string.lower(m.Name)
	if n:find("fizzler") or n:find("grill") then return "Fizzler" end
	if n:find("tractor") or n:find("funnel") or n:find("excursion") or n:find("tbeam") then return "Funnel" end
	if n:find("laser") and not n:find("catcher") and not n:find("reflect") then return "Laser" end
	if n:find("bridge") then return "Bridge" end
	return nil
end

local function ensureSound(m, key, templateName, looped)
	local state = elementSounds[m]
	if not state then state = {}; elementSounds[m] = state end
	if state[key] and state[key].Parent then return state[key] end
	local part = soundPart(m)
	local template = soundTemplate(templateName)
	if not part or not template then return nil end
	local sound = template:Clone()
	sound.Name = "TestElementSound_" .. key
	sound.Looped = looped == true
	sound.Parent = part
	state[key] = sound
	return sound
end

local function playOneShot(m, key, templateName)
	local part = soundPart(m)
	local template = soundTemplate(templateName)
	if not part or not template then return end
	local sound = template:Clone()
	sound.Name = "TestElementSound_" .. key
	sound.Looped = false
	sound.Parent = part
	sound:Play()
	sound.Ended:Once(function()
		if sound then sound:Destroy() end
	end)
	task.delay(15, function()
		if sound and sound.Parent then sound:Destroy() end
	end)
end

local function stopSound(m, key)
	local state = elementSounds[m]
	if not state then return end
	local sound = state[key]
	if sound then
		sound:Stop()
		sound:Destroy()
		state[key] = nil
	end
end

local function stopAllElementSounds(m)
	local state = elementSounds[m]
	if not state then return end
	for key, sound in pairs(state) do
		if typeof(sound) == "Instance" then
			sound:Stop()
			sound:Destroy()
		end
		state[key] = nil
	end
	elementSounds[m] = nil
end

local function updateElementSounds(m)
	local kind = elementKind(m)
	if not kind or not m:IsDescendantOf(workspace) then
		stopAllElementSounds(m)
		return
	end

	local on = m:GetAttribute("Enabled") ~= false
	local state = elementSounds[m] or {}
	local wasOn = state._enabled
	state._enabled = on
	elementSounds[m] = state

	if kind == "Bridge" then
		if on then
			local s = ensureSound(m, "bridge", "bridge_glow_lp_01", true)
			if s and not s.IsPlaying then s:Play() end
		else
			stopSound(m, "bridge")
		end
	elseif kind == "Laser" then
		if on then
			local template = soundTemplate("laser_beam_lp_01") or soundTemplate("laser_beam_lp_02")
			if template then
				local s = ensureSound(m, "laser", template.Name, true)
				if s and not s.IsPlaying then s:Play() end
			end
		else
			stopSound(m, "laser")
		end
	elseif kind == "Funnel" then
		if on then
			local reversed = m:GetAttribute("Reversed") == true
			local desired = reversed and "tbeam_neg_lp_01" or "tbeam_pos_lp_01"
			local current = state.funnelTemplate
			if current ~= desired then
				stopSound(m, "funnel")
				local s = ensureSound(m, "funnel", desired, true)
				if s then s:Play() end
				state.funnelTemplate = desired
			elseif state.funnel and not state.funnel.IsPlaying then
				state.funnel:Play()
			end
		else
			if wasOn == true then playOneShot(m, "shutdown", "fizzler_shutdown_01") end
			stopSound(m, "funnel")
			state.funnelTemplate = nil
		end
	elseif kind == "Fizzler" then
		if on then
			if wasOn == false or wasOn == nil then
				playOneShot(m, "start", "fizzler_start_01")
			end
			local s = ensureSound(m, "ambient", "fizzler_lp_01", true)
			if s and not s.IsPlaying then s:Play() end
			local vortex = ensureSound(m, "vortex", "fizzler_vortex_lp_01", true)
			if vortex and not vortex.IsPlaying then vortex:Play() end
		else
			if wasOn == true then playOneShot(m, "shutdown", "fizzler_shutdown_01") end
			stopSound(m, "ambient")
			stopSound(m, "vortex")
		end
	end
end

local soundElements = {}

local function registerSoundElement(m)
	if not m:IsA("Model") then return end
	if elementKind(m) then soundElements[m] = true end
end

for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") then registerSoundElement(d) end
end

workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(registerSoundElement, d)
	end
end)

workspace.DescendantRemoving:Connect(function(d)
	if d:IsA("Model") then
		soundElements[d] = nil
		stopAllElementSounds(d)
	end
end)

RunService.Heartbeat:Connect(function()
	for m in pairs(soundElements) do
		if m:IsDescendantOf(workspace) then
			updateElementSounds(m)
		else
			soundElements[m] = nil
			stopAllElementSounds(m)
		end
	end
end)

-- ==========================================
-- SPINNING ARMS
-- ==========================================
local spinners = {}

local function findBone(m, name)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Bone") and d.Name == name then return d end
	end
	return nil
end

local function addSpinner(m)
	if spinners[m] or not m:IsA("Model") or not isFunnel(m) then return end
	local rot = findBone(m, "Rotator")
	if not rot then return end
	local mid, out = findBone(m, "Middle"), findBone(m, "ShootOut")
	local axisWorld = (mid and out) and (out.WorldPosition - mid.WorldPosition) or rot.WorldCFrame.UpVector
	if axisWorld.Magnitude < 1e-3 then axisWorld = rot.WorldCFrame.UpVector end
	local axis = rot.WorldCFrame:VectorToObjectSpace(axisWorld.Unit)
	spinners[m] = { bone = rot, axis = axis, angle = 0, speed = 0, rest = rot.CFrame }
end

for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") then addSpinner(d) end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then task.defer(addSpinner, d) end
end)

RunService.RenderStepped:Connect(function(dt)
	for m, sp in pairs(spinners) do
		if not m:IsDescendantOf(workspace) or not sp.bone.Parent then
			spinners[m] = nil
		else
			local target = 0
			if m:GetAttribute("Enabled") ~= false then
				target = (m:GetAttribute("Reversed") == true) and -SPIN_SPEED or SPIN_SPEED
			end
			sp.speed += (target - sp.speed) * (1 - math.exp(-SPIN_EASE * dt))
			sp.angle = (sp.angle + sp.speed * dt) % (2 * math.pi)
			sp.bone.CFrame = sp.rest * CFrame.fromAxisAngle(sp.axis, sp.angle)
		end
	end
end)

-- ==========================================
-- FUNNEL PIECES (made by the server)
-- ==========================================
local emitters = {} -- [model] = emitter info (filled further down)

-- CLIENT-SIDE FUNNEL
-- If the server made no "FunnelSegment" pieces, the client builds its own from the
-- Middle -> ShootOut bones, and follows it through linked portals: each exit portal
-- sends it on from its centre, straight out (Portal 2).
local localFolder
local localSegs = {} -- [model] = { part, part, ... } one per piece (portal hops)

local function localFunnelSegments()
	local cam = workspace.CurrentCamera
	if not localFolder or localFolder.Parent ~= cam then
		localFolder = Instance.new("Folder")
		localFolder.Name = "LocalFunnel"
		localFolder.Parent = cam
		table.clear(localSegs)
	end
	local base = { localFolder, cam }
	for _, n in ipairs({ "TestElementBeams", "Portals", "PortalPassage" }) do
		local f = workspace:FindFirstChild(n)
		if f then table.insert(base, f) end
	end
	if player.Character then table.insert(base, player.Character) end
	local links = Gel.getLinks(portalsFolder)

	local alive = {}
	for m, e in pairs(emitters) do
		if e and m:IsDescendantOf(workspace) and m:GetAttribute("Enabled") ~= false then
			local origin = e.mid.WorldPosition
			local dir = e.out.WorldPosition - origin
			if dir.Magnitude > 1e-3 then
				dir = dir.Unit
				local filter = table.clone(base)
				table.insert(filter, m)
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.RespectCanCollide = true
				params.FilterDescendantsInstances = filter

				local pieces, remaining = {}, MAX_FUNNEL
				for _ = 0, MAX_PORTAL_HOPS do
					-- straight on until a real wall (bridge hitboxes / loose objects don't stop it)
					local endP = origin + dir * remaining
					for _ = 1, 12 do
						local h = workspace:Raycast(origin, dir * remaining, params)
						if not h then break end
						local inst = h.Instance
						local root = inst.AssemblyRootPart
						if inst.Name == "HitBox" or inst.Name == "FunnelSegment"
							or not (inst.Anchored or (root and root.Anchored)) then
							table.insert(filter, inst)
							params.FilterDescendantsInstances = filter
						else
							endP = h.Position
							break
						end
					end

					-- did it run into a linked portal on the way? (portals sit a hair in front of their wall)
					local probeEnd = endP + dir * 0.3
					local bestT, outP
					for _, link in ipairs(links) do
						local p = link[1]
						local a = p.CFrame:PointToObjectSpace(origin)
						local b = p.CFrame:PointToObjectSpace(probeEnd)
						if a.Z < 0 and b.Z >= 0 then -- front of the portal -> through it
							local t = a.Z / (a.Z - b.Z)
							local hp = a:Lerp(b, t)
							local ex, ey = hp.X / (p.Size.X * 0.5), hp.Y / (p.Size.Y * 0.5)
							if ex * ex + ey * ey <= 1 and (not bestT or t < bestT) then
								bestT, outP = t, link[2]
							end
						end
					end

					if bestT then
						local cross = origin:Lerp(probeEnd, bestT)
						table.insert(pieces, { origin, cross })
						remaining -= (cross - origin).Magnitude
						if remaining <= 0 then break end
						local ocf = outP.CFrame
						origin = ocf.Position + ocf.LookVector * 0.05
						dir = ocf.LookVector
					else
						table.insert(pieces, { origin, endP })
						break
					end
				end

				local radius = m:GetAttribute("Radius") or (54 / 14.7)
				local reversed = m:GetAttribute("Reversed") == true
				local speed = m:GetAttribute("Speed") or 13
				local list = localSegs[m] or {}
				localSegs[m] = list
				for i, pc in ipairs(pieces) do
					local a, b = pc[1], pc[2]
					local len = math.max((b - a).Magnitude, 0.05)
					local part = list[i]
					if not part or not part.Parent then
						part = Instance.new("Part")
						part.Name = "FunnelSegment"
						part.Shape = Enum.PartType.Cylinder
						part.Anchored = true
						part.CanCollide = false
						part.CanQuery = false
						part.CanTouch = false
						part.CastShadow = false
						part.Transparency = 1
						part.Parent = localFolder
						list[i] = part
					end
					local size = Vector3.new(len, radius * 2, radius * 2)
					if (part.Size - size).Magnitude > 0.01 then part.Size = size end
					local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
					if part.CFrame ~= cf then part.CFrame = cf end
					part.Color = reversed and FUNNEL_ORANGE or FUNNEL_BLUE
					part:SetAttribute("Speed", speed)
					part:SetAttribute("Reversed", reversed)
					part:SetAttribute("First", i == 1)
					part:SetAttribute("Last", i == #pieces)
				end
				for i = #list, #pieces + 1, -1 do
					list[i]:Destroy()
					list[i] = nil
				end
				alive[m] = true
			end
		end
	end
	for m, list in pairs(localSegs) do
		if not alive[m] then
			for _, part in ipairs(list) do part:Destroy() end
			localSegs[m] = nil
		end
	end
end

local segments = {}
local lastScan = -1
local function scanSegments(now)
	if now - lastScan < 0.03 then return end
	lastScan = now
	table.clear(segments)
	local folder = workspace:FindFirstChild("TestElementBeams")
	if folder then
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "FunnelSegment" and d.Parent then
				table.insert(segments, d)
				local flow = d:FindFirstChild("Flow")
				if flow and not speckOk and flow.Texture ~= DEFAULT_SPARKLE then flow.Texture = DEFAULT_SPARKLE end
			end
		end
	end
	if #segments == 0 then
		localFunnelSegments()
		if localFolder then
			for _, d in ipairs(localFolder:GetChildren()) do table.insert(segments, d) end
		end
	elseif localFolder then
		localFolder:ClearAllChildren()
		table.clear(localSegs)
	end
end

-- ==========================================
-- FUNNEL LOOK: helix lines + ribbon streaks + wisps + haze
-- ==========================================
local fx = {} -- [segment] = { holder, haze, strands, ... }

local function clearFx(seg)
	local f = fx[seg]
	if f then
		f.holder:Destroy()
		if f.haze then f.haze:Destroy() end
		fx[seg] = nil
	end
end

local function makeBeam(a0, a1, width, color, transparency, brightness, emission, texture, texLen)
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Width0, b.Width1 = width, width
	b.FaceCamera = true
	b.Segments = 6
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new(transparency)
	b.Brightness = brightness
	b.LightEmission = emission
	b.LightInfluence = 0
	if texture then
		b.Texture = texture
		b.TextureMode = Enum.TextureMode.Static
		b.TextureLength = texLen
	end
	return b
end

local function makeHaze(color, drawLen, r, speed, flow)
	local p = Instance.new("Part")
	p.Name = "FunnelHaze"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(drawLen, r * 1.6, r * 1.6)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Haze"
	pe.Texture = HAZE_TEXTURE ~= "" and HAZE_TEXTURE or SMOKE_TEXTURE
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 0.7
	pe.LightInfluence = 0
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, HAZE_TRANSPARENCY),
		NumberSequenceKeypoint.new(0.75, HAZE_TRANSPARENCY + 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Size = NumberSequence.new(HAZE_SIZE[1], HAZE_SIZE[2])
	pe.Lifetime = NumberRange.new(3, 5)
	pe.Rate = math.clamp(drawLen / 5, 6, 24)
	pe.Speed = NumberRange.new(speed * 0.6, speed)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-15, 15)
	pe.SpreadAngle = Vector2.new(4, 4)
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.EmissionDirection = flow > 0 and Enum.NormalId.Right or Enum.NormalId.Left
	pe.Parent = p

	-- floating round dots, mixed sizes (Size envelope = random size per dot)
	local dots = Instance.new("ParticleEmitter")
	dots.Name = "Dots"
	dots.Texture = SPECK_TEXTURE ~= "" and SPECK_TEXTURE or DEFAULT_SPARKLE
	dots.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35))
	dots.LightEmission = 1
	dots.LightInfluence = 0
	dots.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12, 0.1),
		NumberSequenceKeypoint.new(0.2, 0.32, 0.25),
		NumberSequenceKeypoint.new(1, 0.1, 0.08),
	})
	dots.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	dots.Lifetime = NumberRange.new(1.5, 3)
	dots.Rate = math.clamp(drawLen * 0.5, 15, 60)
	dots.Speed = NumberRange.new(speed * 0.8, speed * 1.2)
	dots.SpreadAngle = Vector2.new(3, 3)
	dots.Shape = Enum.ParticleEmitterShape.Box
	dots.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dots.EmissionDirection = flow > 0 and Enum.NormalId.Right or Enum.NormalId.Left
	dots.Parent = p

	-- the funnel tints the room around it
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 28
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = p

	p.Parent = workspace.CurrentCamera
	return p
end

local function buildFx(seg)
	clearFx(seg)
	local len, r = seg.Size.X, seg.Size.Y * 0.5
	local color = seg.Color
	local core = color:Lerp(Color3.new(1, 1, 1), 0.25)
	local drawLen = math.min(len, FX_WINDOW)
	local dx = STRAND_TURN * STRAND_STEP / 360
	local count = math.max(math.ceil(drawLen / dx), 1) + 1
	local flow = seg:GetAttribute("Reversed") and -1 or 1
	local speed = seg:GetAttribute("Speed") or 13

	local holder = Instance.new("Part")
	holder.Name = "FunnelFX"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = seg.CFrame
	holder.Parent = workspace.CurrentCamera -- yours only, never replicated

	local hasTex = WISP_TEXTURE ~= ""
	local strands = {}
	for _, def in ipairs(STRANDS) do
		local defs = {}
		if def[3] == "wisp" then
			if hasTex then defs[1] = { def[1], def[2], "wisp", 0 } end
		else
			defs[1] = { def[1], def[2], "line", 0 }
			for h = 1, RIBBON_HAIRS do
				defs[#defs + 1] = { def[1] - RIBBON_SPREAD * h / RIBBON_HAIRS, def[2] * (1 - 0.045 * h), "hair", h }
			end
		end
		for _, d in ipairs(defs) do
			local st = { phase = math.rad(d[1]), twist = 1, rad = r * d[2], kind = d[3], atts = {}, beams = {} }
			for j = 1, count do
				local a = Instance.new("Attachment")
				a.Parent = holder
				st.atts[j] = a
				if j > 1 then
					local a0 = st.atts[j - 1]
					if st.kind == "line" then
						table.insert(st.beams, makeBeam(a0, a, LINE_WIDTH, core, 0, LINE_BRIGHTNESS, LINE_EMISSION))
						table.insert(st.beams, makeBeam(a0, a, LINE_GLOW_WIDTH, color, 0.6, 2, 0.6,
							hasTex and WISP_TEXTURE or nil, LINE_GLOW_WIDTH * 2))
					elseif st.kind == "hair" then
						local b = makeBeam(a0, a, HAIR_WIDTH, color, 0.25 + 0.65 * d[4] / RIBBON_HAIRS, 2, 0.5)
						b.Segments = 4
						table.insert(st.beams, b)
					else
						table.insert(st.beams, makeBeam(a0, a, WISP_WIDTH, color, WISP_TRANSPARENCY, 1.5, 1,
							WISP_TEXTURE, WISP_WIDTH * 2))
					end
				end
			end
			for _, b in ipairs(st.beams) do b.Parent = holder end
			table.insert(strands, st)
		end
	end

	fx[seg] = {
		holder = holder, strands = strands, angle = 0, start = nil,
		haze = HAZE_ON and makeHaze(color, drawLen, r, speed, flow) or nil,
		hazeOffset = CFrame.new(),
		drawLen = drawLen, count = count, len = len, r = r,
		key = ("%.2f|%.2f|%s|%s"):format(len, r, tostring(seg:GetAttribute("Reversed") == true), tostring(color)),
	}
end

-- Angles come from the ABSOLUTE position along the funnel, so sliding the
-- drawn stretch as you move never makes the spiral jump.
local function layoutFx(f, start, camAlong)
	f.start = start
	f.lastCam = camAlong
	local step = f.drawLen / (f.count - 1)
	local k = 2 * math.pi / STRAND_TURN
	for _, st in ipairs(f.strands) do
		local R = st.rad
		local dTheta = k * step
		local arcLen = math.sqrt(step * step + (R * dTheta) ^ 2)
		local handle = dTheta > 1e-4 and arcLen * (4 / 3) * math.tan(dTheta / 4) / dTheta or step / 3
		for j, a in ipairs(st.atts) do
			local x = start + (j - 1) * step
			local th = st.phase + k * x
			local c, sn = math.cos(th), math.sin(th)
			local pos = Vector3.new(x - f.len / 2, R * c, R * sn)
			local tangent = Vector3.new(1, -R * sn * k, R * c * k).Unit
			a.CFrame = CFrame.fromMatrix(pos, tangent, Vector3.new(0, c, sn))
		end
		if st.kind ~= "line" then -- one beam per step: only draw it near the camera
			local range = st.kind == "hair" and HAIR_RANGE or WISP_RANGE
			for jb, b in ipairs(st.beams) do
				b.Enabled = math.abs(start + (jb - 0.5) * step - camAlong) <= range
			end
		end
		for _, b in ipairs(st.beams) do
			if b.Texture ~= "" then b.TextureLength = arcLen end -- exactly one tile per beam: no seams
			b.CurveSize0 = handle
			b.CurveSize1 = STRAND_CURVE_FLIP and -handle or handle
		end
	end
	f.hazeOffset = CFrame.new(start + f.drawLen / 2 - f.len / 2, 0, 0)
end

RunService.RenderStepped:Connect(function(dt)
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	scanSegments(os.clock())
	local alive = {}
	for _, seg in ipairs(segments) do
		if seg.Parent then
			alive[seg] = true
			local len = seg.Size.X
			local lp = seg.CFrame:PointToObjectSpace(camPos)
			local far = math.max(math.abs(lp.X) - len * 0.5, 0) + math.sqrt(lp.Y * lp.Y + lp.Z * lp.Z) > FX_RANGE
			if far then
				clearFx(seg)
			else
				local key = ("%.2f|%.2f|%s|%s"):format(len, seg.Size.Y * 0.5,
					tostring(seg:GetAttribute("Reversed") == true), tostring(seg.Color))
				if not fx[seg] or fx[seg].key ~= key then buildFx(seg) end
				local f = fx[seg]

				local camAlong = math.clamp(lp.X + len * 0.5, 0, len)
				local start = math.clamp(camAlong - f.drawLen * 0.5, 0, len - f.drawLen)
				if not f.start or math.abs(start - f.start) > STRAND_TURN * STRAND_STEP / 360 * 0.5
					or math.abs(camAlong - (f.lastCam or -1e9)) > 6 then
					layoutFx(f, start, camAlong)
				end

				local flow = seg:GetAttribute("Reversed") and -1 or 1
				-- the spiral turns so it looks like it slides along the funnel with the flow
				f.angle = (f.angle - STRAND_SPIN * flow * dt) % (2 * math.pi)
				f.holder.CFrame = seg.CFrame * CFrame.Angles(f.angle, 0, 0)
				if f.haze then f.haze.CFrame = seg.CFrame * f.hazeOffset end
				if f.flow ~= flow then
					f.flow = flow
					for _, st in ipairs(f.strands) do
						for _, b in ipairs(st.beams) do b.TextureSpeed = STRAND_FLOW * flow end
					end
					if f.haze then
						local dir = flow > 0 and Enum.NormalId.Right or Enum.NormalId.Left
						f.haze.Haze.EmissionDirection = dir
						f.haze.Dots.EmissionDirection = dir
					end
				end
			end
		end
	end
	for seg in pairs(fx) do
		if not alive[seg] then clearFx(seg) end
	end
end)

-- ==========================================
-- EMITTER LOOK: tips, ring, mouth glow, wisps curling out into the funnel
-- ==========================================
-- (emitters table is declared above, with the client-side funnel)

local function boneWorld(b)
	local ok, cf = pcall(function() return b.TransformedWorldCFrame end)
	return ok and cf or b.WorldCFrame
end

local function newFxPart(name, shape, size, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Parent = parent
	return p
end

local function simpleBeam(a0, a1, w0, w1, t0, t1, emission, segs)
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Width0, b.Width1 = w0, w1
	b.Transparency = NumberSequence.new(t0, t1)
	b.FaceCamera = true
	b.LightEmission = emission
	b.LightInfluence = 0
	b.Segments = segs
	return b
end

local function buildEmitter(m)
	local tips = {}
	for i = 1, 3 do
		local t = findBone(m, "Tip" .. i)
		if t then table.insert(tips, t) end
	end
	local mid, out = findBone(m, "Middle"), findBone(m, "ShootOut")
	if #tips < 2 or not (mid and out) then return nil end

	local holder = newFxPart("EmitterFX", Enum.PartType.Block, Vector3.one * 0.2, workspace.CurrentCamera)
	holder.Transparency = 1
	holder.CFrame = CFrame.new()
	local e = { model = m, tips = tips, mid = mid, out = out, holder = holder, atts = {}, balls = {}, ring = {}, streams = {} }

	for i = 1, #tips do
		local a = Instance.new("Attachment")
		a.Parent = holder
		e.atts[i] = a

		local ball = newFxPart("TipGlow", Enum.PartType.Ball, Vector3.one * TIP_GLOW_SIZE, holder)
		ball.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Range = TIP_LIGHT_RANGE
		light.Brightness = TIP_LIGHT_BRIGHTNESS
		light.Shadows = false
		light.Parent = ball
		local pe = Instance.new("ParticleEmitter")
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Speed = NumberRange.new(1.5, 4)
		pe.Lifetime = NumberRange.new(0.5, 1.3)
		pe.Rate = 22
		pe.SpreadAngle = Vector2.new(30, 30)
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		pe.Texture = SPECK_TEXTURE ~= "" and SPECK_TEXTURE or DEFAULT_SPARKLE
		pe.Parent = ball
		e.balls[i] = { part = ball, light = light, pe = pe }

		-- wisp curling out of this tip: thin bright line + soft glow
		local pts, cores, glows = {}, {}, {}
		for j = 1, STREAM_POINTS do
			local pa = Instance.new("Attachment")
			pa.Parent = holder
			pts[j] = pa
			if j > 1 then
				local s0, s1 = (j - 2) / (STREAM_POINTS - 1), (j - 1) / (STREAM_POINTS - 1)
				local c = simpleBeam(pts[j - 1], pa, 0.12, 0.12, 0.1 + 0.9 * s0 ^ 1.5, 0.1 + 0.9 * s1 ^ 1.5, 0.5, 1)
				local g = simpleBeam(pts[j - 1], pa, 0.25 + 0.45 * s0, 0.25 + 0.45 * s1,
					0.65 + 0.35 * s0 ^ 1.5, 0.65 + 0.35 * s1 ^ 1.5, 0.6, 1)
				c.Parent, g.Parent = holder, holder
				cores[#cores + 1], glows[#glows + 1] = c, g
			end
		end
		e.streams[i] = { pts = pts, cores = cores, glows = glows }
	end

	-- the ring joining the tips: bright core + soft glow, one arc per neighbour pair
	for i = 1, #tips do
		local a0, a1 = e.atts[i], e.atts[i % #tips + 1]
		local core = simpleBeam(a0, a1, RING_WIDTH, RING_WIDTH, 0.05, 0.05, 0.6, 16)
		local glow = simpleBeam(a0, a1, RING_GLOW_WIDTH, RING_GLOW_WIDTH, 0.6, 0.6, 1, 16)
		core.Parent, glow.Parent = holder, holder
		e.ring[i] = { core = core, glow = glow }
	end

	if MOUTH_GLOW then
		local mouth = newFxPart("Mouth", Enum.PartType.Ball, Vector3.one * 0.2, holder)
		mouth.Transparency = 1
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = HAZE_TEXTURE ~= "" and HAZE_TEXTURE or SMOKE_TEXTURE
		pe.LightEmission = 1
		pe.LightInfluence = 0
		pe.Speed = NumberRange.new(0)
		pe.Lifetime = NumberRange.new(0.7)
		pe.Rate = 8
		pe.Rotation = NumberRange.new(0, 360)
		pe.Size = NumberSequence.new(3.2)
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.85),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.Parent = mouth
		e.mouth = { part = mouth, pe = pe }
	end

	-- keep the tips in order around the axis so the ring joins neighbours
	local axis = (out.WorldPosition - mid.WorldPosition).Unit
	local c = Vector3.zero
	for _, t in ipairs(tips) do c += boneWorld(t).Position end
	c /= #tips
	local ref = (boneWorld(tips[1]).Position - c)
	ref = (ref - axis * ref:Dot(axis)).Unit
	local side = axis:Cross(ref)
	local order = {}
	for i, t in ipairs(tips) do
		local d = boneWorld(t).Position - c
		order[i] = { i = i, a = math.atan2(d:Dot(side), d:Dot(ref)) }
	end
	table.sort(order, function(x, y) return x.a < y.a end)
	e.order = {}
	for k, o in ipairs(order) do e.order[k] = o.i end
	return e
end

local function addEmitter(m)
	if emitters[m] or not m:IsA("Model") or not isFunnel(m) then return end
	emitters[m] = buildEmitter(m)
end

task.spawn(function()
	while true do
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("Model") and isFunnel(d) then
				if not spinners[d] then addSpinner(d) end
				if not emitters[d] then addEmitter(d) end
			end
		end
		task.wait(2)
	end
end)

for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") then task.defer(addEmitter, d) end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then task.defer(addEmitter, d) end
end)

local function paintEmitter(e, color)
	if e.color == color then return end
	e.color = color
	local bright = color:Lerp(Color3.new(1, 1, 1), 0.35)
	for _, b in ipairs(e.balls) do
		b.part.Color = bright
		b.light.Color = color
		b.pe.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.5))
	end
	for _, r in ipairs(e.ring) do
		r.core.Color = ColorSequence.new(bright)
		r.glow.Color = ColorSequence.new(color)
	end
	for _, st in ipairs(e.streams) do
		for _, b in ipairs(st.cores) do b.Color = ColorSequence.new(bright) end
		for _, b in ipairs(st.glows) do b.Color = ColorSequence.new(color) end
	end
	if e.mouth then e.mouth.pe.Color = ColorSequence.new(color) end
end

RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for m, e in pairs(emitters) do
		if e then
			if not m:IsDescendantOf(workspace) then
				e.holder:Destroy()
				emitters[m] = nil
			else
				local on = m:GetAttribute("Enabled") ~= false
				local axisVec = e.out.WorldPosition - e.mid.WorldPosition
				local far = (e.mid.WorldPosition - camPos).Magnitude > FX_RANGE
				if not on or far or axisVec.Magnitude < 1e-3 then
					e.holder.Parent = nil
				else
					e.holder.Parent = cam
					local reversed = m:GetAttribute("Reversed") == true
					paintEmitter(e, reversed and FUNNEL_ORANGE or FUNNEL_BLUE)
					local axis = axisVec.Unit
					local funnelR = m:GetAttribute("Radius") or (54 / 14.7)
					local kTurn = 2 * math.pi / STRAND_TURN

					local pos, c = {}, Vector3.zero
					for i, t in ipairs(e.tips) do
						pos[i] = boneWorld(t).Position
						c += pos[i]
					end
					c /= #e.tips
					if e.mouth then e.mouth.part.CFrame = CFrame.new(c + axis * 0.4) end

					local flow = reversed and -1 or 1
					for _, i in ipairs(e.order) do
						local radial = pos[i] - c
						local h = radial:Dot(axis)
						radial -= axis * h
						local r = radial.Magnitude
						if r > 1e-3 then
							local r1 = radial / r
							local tangent = axis:Cross(r1)
							local cf = CFrame.fromMatrix(pos[i], tangent, axis)
							e.atts[i].CFrame = cf
							e.balls[i].part.CFrame = cf

							-- wisp: leaves the tip, twists the same way as the funnel's spiral,
							-- and opens out to the funnel's radius
							local st = e.streams[i]
							for j, pa in ipairs(st.pts) do
								local sj = (j - 1) / (STREAM_POINTS - 1)
								local ang = kTurn * STREAM_HEIGHT * sj
								local rad = r + (funnelR - r) * sj * sj
								pa.WorldPosition = c + axis * (h + STREAM_HEIGHT * sj)
									+ (r1 * math.cos(ang) + tangent * math.sin(ang)) * rad
							end
							for _, b in ipairs(st.glows) do b.TextureSpeed = 0.8 * flow end
						end
					end
					local n = #e.order
					for k = 1, n do
						local i = e.order[k]
						local j = e.order[k % n + 1]
						local r = ((pos[i] - c) - axis * (pos[i] - c):Dot(axis)).Magnitude
						local da = 2 * math.pi / n
						local handle = 4 / 3 * math.tan(da / 4) * r
						local rg = e.ring[i]
						for _, b in ipairs({ rg.core, rg.glow }) do
							b.Attachment1 = e.atts[j]
							b.CurveSize0 = handle
							b.CurveSize1 = RING_CURVE_FLIP and -handle or handle
						end
					end
				end
			end
		end
	end
end)

-- ==========================================
-- CARRYING YOU
-- ==========================================
local inFunnel = false
local pullAmt = 0
local lastRootPos = nil -- where your root was last frame (for the swept catch)

-- is world point `pos` inside funnel piece p? (same test as the probes below)
local function insidePiece(p, pos)
	local r = p.Size.Y * 0.5
	local reach = p:GetAttribute("First") and START_REACH or 2
	local l = p.CFrame:PointToObjectSpace(pos)
	return l.X >= -p.Size.X * 0.5 - reach and l.X <= p.Size.X * 0.5 + 2
		and (l.Y * l.Y + l.Z * l.Z) <= (r + 1.5) * (r + 1.5)
end

-- flew THROUGH a funnel between two frames? walk the path in small steps, return the first point inside
local function sweepCatch(from, to)
	local d = to - from
	local dist = d.Magnitude
	if dist < 1 then return nil end
	local steps = math.min(math.ceil(dist / 1), 64)
	for i = 1, steps do
		local pt = from + d * (i / steps)
		for _, p in ipairs(segments) do
			if p.Parent and insidePiece(p, pt) then return p, pt end
		end
	end
	return nil
end

local function setInFunnel(on, hum)
	if inFunnel == on then return end
	inFunnel = on
	player:SetAttribute("InFunnel", on)
	if on then
		playFunnelEnter() -- the whoosh as it grabs you
	else
		setRideLoop(nil)
	end
	if hum and hum.Parent then
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function getFunnelInput(hum, camera, funnelDir)
	local move = hum.MoveDirection
	local look = camera.CFrame.LookVector
	local lateral = move - funnelDir * move:Dot(funnelDir)

	if lateral.Magnitude > 1 then
		lateral = lateral.Unit
	end

	local lookLateral = look - funnelDir * look:Dot(funnelDir)
	if lookLateral.Magnitude > 1e-3 then
		lookLateral = lookLateral.Unit
	else
		lookLateral = Vector3.zero
	end

	return lateral, lookLateral, move.Magnitude
end

RunService.PreSimulation:Connect(function(dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not hrp or not hum or hum.Health <= 0 or not camera then
		pullAmt = 0
		lastRootPos = nil
		setInFunnel(false)
		return
	end
	local prevPos = lastRootPos
	lastRootPos = hrp.Position

	scanSegments(os.clock())

	local seg, lp
	local probeParts = { hrp }
	for _, name in ipairs({ "UpperTorso", "Torso", "LowerTorso", "Head" }) do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(probeParts, part)
		end
	end

	for _, p in ipairs(segments) do
		if p.Parent then
			for _, probe in ipairs(probeParts) do
				if insidePiece(p, probe.Position) then
					seg = p
					lp = p.CFrame:PointToObjectSpace(hrp.Position)
					break
				end
			end
			if seg then break end
		end
	end

	-- flung straight through it this frame? catch you where you crossed it
	local caught = false
	if not seg and not inFunnel and CATCH_SWEEP and prevPos
		-- only a real flight path: a portal hop / respawn moves you further than your speed could
		and (hrp.Position - prevPos).Magnitude <= hrp.AssemblyLinearVelocity.Magnitude * math.max(dt, 1 / 60) * 2.5 + 4 then
		local p, pt = sweepCatch(prevPos, hrp.Position)
		if p then
			seg = p
			hrp.CFrame = hrp.CFrame - hrp.Position + pt
			lastRootPos = pt
			lp = p.CFrame:PointToObjectSpace(pt)
			caught = true
		end
	end

	if not seg then
		pullAmt = 0
		setInFunnel(false, hum)
		return
	end

	local entering = not inFunnel
	setInFunnel(true, hum)

	local cf = seg.CFrame
	local funnelDir = cf.RightVector
	local len = seg.Size.X
	local flow = seg:GetAttribute("Reversed") and -1 or 1
	local funnelSpeed = seg:GetAttribute("Speed") or 13
	local along = lp.X + len * 0.5

	-- the funnel's hum follows you while you ride (pos / neg loop for the direction)
	setRideLoop(flow > 0 and "tbeam_pos_lp_01" or "tbeam_neg_lp_01")

	if flow > 0 and seg:GetAttribute("Last") and len - along < END_HOVER then
		funnelSpeed = 0
	elseif flow < 0 and seg:GetAttribute("First") and along < END_HOVER then
		funnelSpeed = 0
	end

	local lateralInput, lookLateral, moveAmount = getFunnelInput(hum, camera, funnelDir)
	local steering = lateralInput.Magnitude > 0.08
	pullAmt += ((steering and 0 or 1) - pullAmt) * (1 - math.exp(-PULL_EASE * dt))

	local toCenter = cf:VectorToWorldSpace(Vector3.new(0, -lp.Y, -lp.Z))
	if toCenter.Magnitude > CENTER_PULL_MAX then
		toCenter = toCenter.Unit * CENTER_PULL_MAX
	end
	toCenter *= CENTER_PULL * pullAmt

	local steerVelocity = lateralInput * STEER_SPEED
	if moveAmount < 0.08 then
		steerVelocity += lookLateral * 5
	end

	local lookUpDown = Vector3.new(0, camera.CFrame.LookVector.Y, 0)
	if lookUpDown.Magnitude > 0.05 then
		steerVelocity += lookUpDown.Unit * (10 * math.abs(camera.CFrame.LookVector.Y))
	end

	local forwardVelocity = funnelDir * (funnelSpeed * flow)
	local desiredPerpendicular = steerVelocity + toCenter

	local gravityPerpendicular = Vector3.new(0, workspace.Gravity, 0)
	- funnelDir * Vector3.new(0, workspace.Gravity, 0):Dot(funnelDir)

	local target = forwardVelocity + desiredPerpendicular + gravityPerpendicular * dt
	local current = hrp.AssemblyLinearVelocity
	local a = 1 - math.exp(-ENTER_SMOOTH * dt)
	if (entering or caught) and CATCH_STOP then
		a = 1 -- caught mid-air: your fall / fling stops dead, the funnel takes over
	end

	hrp.AssemblyLinearVelocity = current + (target - current) * a

	local newVelocity = hrp.AssemblyLinearVelocity
	local forwardComponent = funnelDir * newVelocity:Dot(funnelDir)
	if flow > 0 and forwardComponent:Dot(funnelDir) < funnelSpeed then
		hrp.AssemblyLinearVelocity += funnelDir * (funnelSpeed - forwardComponent:Dot(funnelDir))
	elseif flow < 0 and forwardComponent:Dot(funnelDir) > -funnelSpeed then
		hrp.AssemblyLinearVelocity += funnelDir * (-funnelSpeed - forwardComponent:Dot(funnelDir))
	end
end)

player.CharacterAdded:Connect(function()
	inFunnel = false
	setRideLoop(nil)
	player:SetAttribute("InFunnel", false)
end)

-- ==========================================
-- PUSH ZONES (editor's Advanced "Push Zone": an invisible cell that shoves you out of its surface)
-- ==========================================
-- The server pushes cubes; your character is yours to move, so this does it. Zones: tag PeTIZone, Kind = "pushzone",
-- a child part "Zone" (the box) and the attribute PushVelocity (studs/s). Enabled = false switches it off.
do
	local CollectionService = game:GetService("CollectionService")
	local zones = {}
	local function add(m)
		if m:GetAttribute("Kind") == "pushzone" then zones[m] = true end
	end
	for _, m in ipairs(CollectionService:GetTagged("PeTIZone")) do add(m) end
	CollectionService:GetInstanceAddedSignal("PeTIZone"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("PeTIZone"):Connect(function(m) zones[m] = nil end)

	RunService.PreSimulation:Connect(function()
		if not next(zones) then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		for m in pairs(zones) do
			local zone = m.Parent and m:FindFirstChild("Zone")
			local v = m:GetAttribute("PushVelocity")
			if zone and typeof(v) == "Vector3" and v.Magnitude > 0 and m:GetAttribute("Enabled") ~= false then
				local l = zone.CFrame:PointToObjectSpace(hrp.Position)
				local h = zone.Size / 2
				if math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z then
					local cur = hrp.AssemblyLinearVelocity
					local dir = v.Unit
					if cur:Dot(dir) < v.Magnitude then
						hrp.AssemblyLinearVelocity = cur - dir * cur:Dot(dir) + v
						local hum = char:FindFirstChildOfClass("Humanoid")
						if hum and dir.Y > 0.5 then hum:ChangeState(Enum.HumanoidStateType.Freefall) end -- off the ground
					end
				end
			end
		end
	end)
end
