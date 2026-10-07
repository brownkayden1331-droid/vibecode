-- FaithPlateServer
-- ServerScriptService (Script)
-- Aerial Faith Plates. Plates you place by hand work like before (LaunchSpeed / LaunchAngle / Target / StraightUp /
-- ArcHeight attributes). Plates built by the test chamber editor get AimPoint + ApexY (aimed at a panel) or
-- StraightUp + UpHeight from PortalConfig, and land you exactly on the target.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ==========================================
-- SETTINGS
-- ==========================================
local PLATE_NAME = "FaithPlate"
local FLIP_ANGLE = 60
local UP_TIME = 0.08
local HOLD_TIME = 0.15
local DOWN_TIME = 0.55
local COOLDOWN = 0.9
local DEFAULT_ARC = 40         -- arc height for plates with a Target ObjectValue and no ArcHeight
local TRIGGER_SIZE = Vector3.new(2.8, 3, 6.2)
local MAX_OBJECT_MASS = 1000
local DEFAULT_SPEED = 250      -- hand-placed plates without a target
local DEFAULT_ANGLE = 45

local ASSETS = {
	UsedTexture = "rbxassetid://89868839811055",
	InAnim = "rbxassetid://138281113638033",
	HoldAnim = "rbxassetid://111345125429772",
	OutAnim = "rbxassetid://131979976936032",
}
local LAUNCH_DELAY = 0

-- ==========================================
-- SETUP
-- ==========================================
local remote = ReplicatedStorage:FindFirstChild("FaithPlateLaunch")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "FaithPlateLaunch"
	remote.Parent = ReplicatedStorage
end

local plates = {}

local function setup(model)
	if plates[model] or not model:IsA("Model") then return end
	local bone
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Bone") and d.Name == "Paddle" then
			bone = d
			break
		end
	end
	if not bone then return end
	local mesh = bone:FindFirstAncestorWhichIsA("MeshPart")
	if not mesh then return end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	local st = { bone = bone, mesh = mesh, rest = bone.CFrame, last = 0, busy = false, normalTexture = mesh.TextureID }

	local controller = model:FindFirstChildOfClass("AnimationController") or model:FindFirstChildWhichIsA("AnimationController", true)
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Parent = model
	end
	local animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = controller
	st.tracks = {}
	for _, name in ipairs({ "InAnim", "HoldAnim", "OutAnim" }) do
		local id = model:GetAttribute(name) or ASSETS[name]
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = (name == "HoldAnim")
			st.tracks[name] = track
		end
	end
	plates[model] = st
end

local function parentWorld(st)
	local p = st.bone.Parent
	return p:IsA("Bone") and p.WorldCFrame or st.mesh.CFrame
end

local function geometry(model, st)
	local restWorld = parentWorld(st) * st.rest
	local hinge = restWorld.Position
	local bbCF = model:GetBoundingBox()
	local up = bbCF.UpVector
	if math.abs(up.Y) < 0.5 then up = Vector3.yAxis end
	if up.Y < 0 then up = -up end
	local center = bbCF.Position
	local along = center - hinge
	along = (along - up * along:Dot(up)).Unit
	local axis = along:Cross(up)
	return restWorld, hinge, up, along, axis
end

local function setAngle(model, st, deg)
	local restWorld, hinge, _, _, axis = geometry(model, st)
	local world = CFrame.new(hinge) * CFrame.fromAxisAngle(axis, math.rad(deg)) * CFrame.new(-hinge) * restWorld
	st.bone.CFrame = parentWorld(st):Inverse() * world
end

local function ballistic(p0, p1, arc, g)
	local apex = math.max(p0.Y, p1.Y) + arc
	local vy = math.sqrt(2 * g * math.max(apex - p0.Y, 0.1))
	local t = vy / g + math.sqrt(2 * math.max(apex - p1.Y, 0.1) / g)
	return Vector3.new((p1.X - p0.X) / t, vy, (p1.Z - p0.Z) / t)
end

-- peaks at apexY (world height) and comes down through p1
local function ballisticApex(p0, p1, apexY, g)
	apexY = math.max(apexY, p0.Y + 0.5, p1.Y + 0.5)
	local vy = math.sqrt(2 * g * (apexY - p0.Y))
	local t = vy / g + math.sqrt(2 * (apexY - p1.Y) / g)
	return Vector3.new((p1.X - p0.X) / t, vy, (p1.Z - p0.Z) / t)
end

local function launchVelocity(model, from)
	local arc = model:GetAttribute("ArcHeight") or DEFAULT_ARC
	local g = workspace.Gravity

	-- editor plates: aimed at a panel with an arc height (set by PortalConfig)
	local aim = model:GetAttribute("AimPoint")
	if typeof(aim) == "Vector3" then
		return ballisticApex(from, aim, model:GetAttribute("ApexY") or (math.max(from.Y, aim.Y) + arc), g)
	end

	local tv = model:FindFirstChild("Target")
	local target = tv and tv:IsA("ObjectValue") and tv.Value
	if target and target:IsA("BasePart") then
		return ballistic(from, target.Position + Vector3.new(0, target.Size.Y * 0.5 + 3, 0), arc, g)
	end

	local st = plates[model]
	local _, _, up, along = geometry(model, st)

	along = -along -- Invert launch direction default
	if model:GetAttribute("LaunchFlip") then along = -along end

	local speed = model:GetAttribute("LaunchSpeed") or DEFAULT_SPEED

	if model:GetAttribute("StraightUp") then
		local h = model:GetAttribute("UpHeight")
		if type(h) == "number" then return up * math.sqrt(2 * g * math.max(h, 1)) end -- exactly that high
		return up * speed
	end

	local angle = math.rad(model:GetAttribute("LaunchAngle") or DEFAULT_ANGLE)
	return (up * math.cos(angle) + along * math.sin(angle)) * speed
end

local function trackLength(track)
	local t0 = os.clock()
	while track.Length == 0 and os.clock() - t0 < 2 do task.wait() end
	return track.Length
end

local function setUsed(st, on)
	local used = st.mesh.Parent and (st.mesh.Parent:GetAttribute("UsedTexture") or ASSETS.UsedTexture)
	st.mesh.TextureID = on and used or st.normalTexture
end

local function fire(model, st)
	st.busy = true
	st.last = os.clock()
	local tr = st.tracks or {}
	if tr.InAnim and tr.OutAnim then
		task.spawn(function()
			setUsed(st, true)
			tr.InAnim:Play(0)
			task.wait(trackLength(tr.InAnim))
			if tr.HoldAnim then
				tr.HoldAnim:Play(0)
				tr.InAnim:Stop(0)
				task.wait(HOLD_TIME)
			end
			tr.OutAnim:Play(0)
			if tr.HoldAnim then tr.HoldAnim:Stop(0) else tr.InAnim:Stop(0) end
			task.wait(trackLength(tr.OutAnim))
			tr.OutAnim:Stop(0.1)
			setUsed(st, false)
			st.busy = false
		end)
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local t = os.clock() - t0
			local deg
			if t < UP_TIME then
				local a = t / UP_TIME
				deg = FLIP_ANGLE * (1 - (1 - a) ^ 3)
			elseif t < UP_TIME + HOLD_TIME then
				deg = FLIP_ANGLE
			elseif t < UP_TIME + HOLD_TIME + DOWN_TIME then
				local a = (t - UP_TIME - HOLD_TIME) / DOWN_TIME
				deg = FLIP_ANGLE * (1 - a * a * (3 - 2 * a))
			else
				break
			end
			if not model.Parent then return end
			setAngle(model, st, deg)
			RunService.Heartbeat:Wait()
		end
		setAngle(model, st, 0)
		st.busy = false
	end)
end

-- ==========================================
-- TRIGGER
-- ==========================================
local function launchPlayer(model, plr)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local v = launchVelocity(model, hrp.Position)
		local aim = model:GetAttribute("AimPoint")
		-- the client re-aims from where it really is (the server's copy of your position is a bit behind)
		remote:FireClient(plr, v, typeof(aim) == "Vector3" and aim or nil, model:GetAttribute("ApexY"))
	end
end

local function launchNPC(model, char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then
		hrp.CFrame += Vector3.new(0, 1.5, 0)
		local v = launchVelocity(model, hrp.Position)
		hum:ChangeState(Enum.HumanoidStateType.Physics)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp:ApplyImpulse(v * hrp.AssemblyMass)

		task.delay(0.1, function()
			if hum and hum.Health > 0 then
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		end)
	end
end

local function launchObject(model, root)
	if not root.Parent or root.Anchored then return end
	if root:CanSetNetworkOwnership() then root:SetNetworkOwner(nil) end

	root.CFrame += Vector3.new(0, 0.5, 0)
	local v = launchVelocity(model, root.Position) -- aimed from where it actually starts
	root.AssemblyLinearVelocity = Vector3.zero
	root:ApplyImpulse(v * root.AssemblyMass)

	task.delay(2, function()
		if root.Parent and root:CanSetNetworkOwnership() then
			root:SetNetworkOwner(nil)
		end
	end)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for model, st in pairs(plates) do
		if not model.Parent then
			plates[model] = nil
		elseif not st.busy and now - st.last > COOLDOWN and model:GetAttribute("Enabled") ~= false then
			local bbCF, bbSize = model:GetBoundingBox()
			local up = bbCF.UpVector
			if math.abs(up.Y) < 0.5 then up = Vector3.yAxis end
			if up.Y < 0 then up = -up end
			local topY = math.abs(bbCF.UpVector.Y) >= 0.5 and bbSize.Y * 0.5 or 0
			local boxCF = CFrame.new(bbCF.Position + up * (topY + TRIGGER_SIZE.Y * 0.5)) * bbCF.Rotation
			local zone = Vector3.new(bbSize.X, TRIGGER_SIZE.Y, bbSize.Z)
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { model }

			local players, npcs, objects, seen = {}, {}, {}, {}
			for _, part in ipairs(workspace:GetPartBoundsInBox(boxCF, zone, params)) do
				local char = part:FindFirstAncestorOfClass("Model")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local plr = char and Players:GetPlayerFromCharacter(char)

				if plr then
					if not seen[plr] then
						seen[plr] = true
						table.insert(players, plr)
					end
				elseif hum then
					if not seen[char] then
						seen[char] = true
						table.insert(npcs, char)
					end
				else
					local root = part.AssemblyRootPart
					if root and not root.Anchored and not seen[root] and root.AssemblyMass <= MAX_OBJECT_MASS
						and not root:GetAttribute("HeldBy") then
						seen[root] = true
						table.insert(objects, root)
					end
				end
			end

			if #players > 0 or #npcs > 0 or #objects > 0 then
				fire(model, st)

				task.delay(model:GetAttribute("LaunchDelay") or LAUNCH_DELAY, function()
					for _, plr in ipairs(players) do launchPlayer(model, plr) end
					for _, char in ipairs(npcs) do launchNPC(model, char) end
					for _, root in ipairs(objects) do launchObject(model, root) end
				end)
			end
		end
	end
end)

for _, d in ipairs(workspace:GetDescendants()) do
	if d.Name == PLATE_NAME then setup(d) end
end
workspace.DescendantAdded:Connect(function(d)
	if d.Name == PLATE_NAME then task.defer(setup, d) end
end)
for _, m in ipairs(CollectionService:GetTagged(PLATE_NAME)) do setup(m) end
CollectionService:GetInstanceAddedSignal(PLATE_NAME):Connect(setup)
