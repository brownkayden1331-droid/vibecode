-- PingClient (LocalScript, StarterPlayerScripts)
-- Portal 2 co-op ping tool.
-- Teammate death = Atlas / P-body death icon where they died (sent by PingServer)
-- Tap F  = smart ping (icon picked from what you're aiming at)
-- Hold F = radial menu. Point at a slot = arrow snaps to it, between slots = arrow follows the mouse.
--          Release F to send. Scroll = emote page, right click = cancel
-- Each player can have several pings up at once (PingModule.MaxPingsPerPlayer)
-- Pings only work while you're playing a co-op chamber with your partner (see canPing below): not in the menus,
-- the lobby, single player or while building in the editor. Pings from anyone outside your chamber are ignored.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local PingModule = require(ReplicatedStorage:WaitForChild("PingModule"))
local PingEvent = ReplicatedStorage:WaitForChild("PingEvent")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Layout = PingModule.Layout
local WorldCfg = PingModule.World
local HintCfg = PingModule.Hint

local SLOT_NAMES = {"Center", "Up", "Down", "Left", "Right"}
local DIRS = {
	Up = Vector2.new(0, -1),
	Down = Vector2.new(0, 1),
	Left = Vector2.new(-1, 0),
	Right = Vector2.new(1, 0),
}
local OBJECT_KINDS = {"Turret", "TallButton", "Button", "Cube"} -- detection priority

local GESTURE_ACTION = "PingGesture"
local GESTURE_PRIORITY = Enum.ContextActionPriority.High.Value + 100

local TWEEN_SELECT = TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local TWEEN_POP = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_OPEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local currentScale = 1 -- screen-height scale (720p = 1), updated every frame

---------------------------------------------------------------------
-- When pings work: only while testing / playing a chamber in co-op
---------------------------------------------------------------------
local PING_ONLY_EDITOR_TESTS = false -- true = only in co-op editor playtests (not Workshop / campaign co-op chambers)

-- someone else in my chamber (PortalServer puts a co-op pair in the same InstanceSlot)
local function sameChamber(other)
	if other == LocalPlayer then return true end
	local mine = LocalPlayer:GetAttribute("InstanceSlot")
	return mine ~= nil and other:GetAttribute("InstanceSlot") == mine
end

local function hasPartner()
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= LocalPlayer and sameChamber(pl) then return true end
	end
	return false
end

local function canPing()
	if LocalPlayer:GetAttribute("InMenu") then return false end
	local inEditor = LocalPlayer:GetAttribute("InEditor")
	if inEditor and not LocalPlayer:GetAttribute("EditorPlaytest") then return false end -- building, not testing
	if PING_ONLY_EDITOR_TESTS and not inEditor then return false end
	return hasPartner()
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
-- arrow box from length (along the point) and thickness, whichever way the image is drawn
local function arrowSize(length, thickness)
	local sideways = ((PingModule.ArrowImageAngle or 0) % 180) == 90
	if sideways then return UDim2.fromOffset(length, thickness) end
	return UDim2.fromOffset(thickness, length)
end

-- rotation that makes the arrow image point along a screen direction
local function arrowRotation(dir)
	return math.deg(math.atan2(dir.Y, dir.X)) + 90 - (PingModule.ArrowImageAngle or 0)
end

local function getCamera()
	return workspace.CurrentCamera
end

local function tween(obj, info, props)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

local function playSound(id, speed)
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.8
	s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 4)
end

local function getColorFor(player)
	local override = player:GetAttribute("PingColor")
	if typeof(override) == "Color3" then return override end

	local list = Players:GetPlayers()
	table.sort(list, function(a, b) return a.UserId < b.UserId end)
	local index = table.find(list, player) or 1
	if index == 1 then return PingModule.Colors.Blue end
	if index == 2 then return PingModule.Colors.Orange end
	return Color3.fromHSV((player.UserId % 360) / 360, 0.7, 1)
end

-- Atlas (blue) or P-body (orange) death icon for this player
local function deathKeyFor(player)
	return getColorFor(player) == PingModule.Colors.Orange and "DeathOrange" or "DeathBlue"
end

---------------------------------------------------------------------
-- GUIs
---------------------------------------------------------------------
local menuGui = Instance.new("ScreenGui")
menuGui.Name = "PingRadialMenu"
menuGui.IgnoreGuiInset = true
menuGui.ResetOnSpawn = false
menuGui.DisplayOrder = 50
menuGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
menuGui.Enabled = false
menuGui.Parent = PlayerGui

local menuRoot = Instance.new("Frame")
menuRoot.Name = "Root"
menuRoot.AnchorPoint = Vector2.new(0.5, 0.5)
menuRoot.Position = UDim2.fromScale(0.5, 0.5)
menuRoot.Size = UDim2.fromOffset(0, 0)
menuRoot.BackgroundTransparency = 1
menuRoot.Parent = menuGui

local menuScale = Instance.new("UIScale")
menuScale.Parent = menuRoot

local openScale = Instance.new("UIScale") -- separate scale for the open pop
openScale.Parent = menuGui

-- Cross lines: a fixed segment from the center outward, like Portal 2.
local lines = {}
do
	local inner = Layout.SmallSize * 0.5
	local outer = Layout.LineReach
	local len = outer - inner
	local mid = (inner + outer) * 0.5
	for dir, vec in pairs(DIRS) do
		local line = Instance.new("Frame")
		line.Name = dir .. "Line"
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BackgroundTransparency = Layout.LineTransparency
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromOffset(vec.X * mid, vec.Y * mid)
		line.Size = vec.X ~= 0 and UDim2.fromOffset(len, Layout.LineThickness) or UDim2.fromOffset(Layout.LineThickness, len)
		line.ZIndex = 1
		line.Parent = menuRoot
		lines[dir] = line
	end
end

local slotIcons = {}
for _, name in ipairs(SLOT_NAMES) do
	local vec = DIRS[name] or Vector2.zero
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromOffset(vec.X * Layout.SlotDistance, vec.Y * Layout.SlotDistance)
	img.Size = UDim2.fromOffset(Layout.SmallSize, Layout.SmallSize)
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 2
	img.Parent = menuRoot
	slotIcons[name] = img
end

local MENU_ARROW_SIZE = arrowSize(PingModule.MenuArrow.Length, PingModule.MenuArrow.Thickness)
local menuArrow = Instance.new("ImageLabel")
menuArrow.Name = "SelectArrow"
menuArrow.BackgroundTransparency = 1
menuArrow.AnchorPoint = Vector2.new(0.5, 0.5)
menuArrow.Image = PingModule.Assets.ArrowDecal
menuArrow.Size = MENU_ARROW_SIZE
menuArrow.ZIndex = 5
menuArrow.Visible = false
menuArrow.Parent = menuRoot

local trackerGui = Instance.new("ScreenGui")
trackerGui.Name = "PingTracker"
trackerGui.IgnoreGuiInset = true
trackerGui.ResetOnSpawn = false
trackerGui.DisplayOrder = 40
trackerGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
trackerGui.Parent = PlayerGui

-- local-only folder for the surface reticles
local ringFolder = Instance.new("Folder")
ringFolder.Name = "PingReticles_" .. LocalPlayer.Name
ringFolder.Parent = workspace

---------------------------------------------------------------------
-- Surface reticle (SurfaceGui on a thin invisible part = drawn in perspective on the surface)
---------------------------------------------------------------------
local function surfaceUp(normal)
	if math.abs(normal.Y) > 0.99 then
		-- floor / ceiling: line it up with where you're looking
		local look = getCamera().CFrame.LookVector
		local flat = look - normal * look:Dot(normal)
		return flat.Magnitude > 0.05 and flat.Unit or Vector3.zAxis
	end
	return Vector3.yAxis
end

local function makeRing(position, normal, color, transparency)
	transparency = transparency or 0
	local origin = position + normal * WorldCfg.SurfaceOffset
	local base = CFrame.lookAt(origin, origin + normal, surfaceUp(normal))
	local diameter = WorldCfg.RingRadius * 2

	local part = Instance.new("Part")
	part.Name = "PingReticle"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(diameter, diameter, 0.02)
	part.CFrame = base
	part.Parent = ringFolder

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- Front faces the surface normal
	gui.LightInfluence = 0
	gui.Brightness = WorldCfg.RingBrightness
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(256, 256)
	gui.Adornee = part
	gui.Parent = part

	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = PingModule.Assets.Reticle
	img.ImageColor3 = color
	img.ImageTransparency = transparency
	img.Parent = gui

	return {
		Part = part,
		Image = img,
		Base = base,
		Diameter = diameter,
		Transparency = transparency,
		Start = os.clock(),
	}
end

-- spin + shrink into place, then fade
local function animateRing(ring, fade)
	local intro = math.clamp((os.clock() - ring.Start) / 0.3, 0, 1)
	local e = (1 - intro) ^ 2
	local d = ring.Diameter * (1 + 1.5 * e)
	ring.Part.Size = Vector3.new(d, d, 0.02)
	ring.Part.CFrame = ring.Base * CFrame.Angles(0, 0, math.rad(WorldCfg.RingSpin) * e)
	ring.Image.ImageTransparency = ring.Transparency + (1 - ring.Transparency) * (fade or 0)
end

local function destroyRing(ring)
	if ring then ring.Part:Destroy() end
end

---------------------------------------------------------------------
-- Smart Select
---------------------------------------------------------------------
local function findTagged(inst, tag)
	local cur, depth = inst, 0
	while cur and cur ~= workspace and depth < 6 do
		if CollectionService:HasTag(cur, tag) then return cur end
		cur, depth = cur.Parent, depth + 1
	end
end

local function findNamed(inst, keywords)
	local cur, depth = inst, 0
	while cur and cur ~= workspace and depth < 3 do
		local n = string.lower(cur.Name)
		for _, kw in ipairs(keywords) do
			if string.find(n, kw, 1, true) then return cur end
		end
		cur, depth = cur.Parent, depth + 1
	end
end

-- Conversion gel lets portals go on blocked surfaces (same check PortalServer uses)
local Gel
do
	local assets = ReplicatedStorage:FindFirstChild("PortalAssets")
	local mod = assets and assets:FindFirstChild("GelShared")
	if mod then
		local ok, result = pcall(require, mod)
		if ok then Gel = result end
	end
end

-- Same orientation PortalServer gives a portal at this spot
local function portalFrame(normal, facing)
	local up = Vector3.yAxis
	if math.abs(normal.Y) > 0.9 then
		local flat = facing - normal * facing:Dot(normal)
		up = flat.Magnitude > 0.1 and flat.Unit or Vector3.zAxis
	end
	return CFrame.lookAt(Vector3.zero, normal, up)
end

local function isStaticPart(part)
	if part.Anchored then return true end
	local root = part.AssemblyRootPart
	return root ~= nil and root.Anchored
end

-- Things portal shots fly straight through (light bridge HitBoxes, invisible parts...)
local function isPassThrough(part)
	return not part.CanCollide
		or part.Name == "HitBox" or part.Name == "BridgeEndHolder"
		or part.Transparency >= 0.95
		or part:GetAttribute("PortalPassThrough") == true
end

-- Mirror of PortalServer's isPortalable + surfaceBigEnough
local function isPortalable(part, point, normal, facing)
	local rules = PingModule.PortalRules
	if not part:IsA("BasePart") or part:IsA("Terrain") then return false end
	if isPassThrough(part) or not isStaticPart(part) then return false end
	if rules.BlockSurfacesOnly and not (part:IsA("Part") and part.Shape == Enum.PartType.Block) then
		return false
	end
	if part:GetAttribute("NoPortal") or rules.BlockedMaterials[part.Material] then
		if not Gel then return false end
		local ok, gel = pcall(Gel.gelAt, part, point, normal)
		if not (ok and gel == "Conversion") then return false end
	end

	local rot = portalFrame(normal, facing)
	local h, cf = part.Size * 0.5, part.CFrame
	local function ext(axis)
		return h.X * math.abs(cf.RightVector:Dot(axis))
			+ h.Y * math.abs(cf.UpVector:Dot(axis))
			+ h.Z * math.abs(cf.LookVector:Dot(axis))
	end
	return ext(rot.RightVector) * 2 >= rules.PortalSize.X - 0.01
		and ext(rot.UpVector) * 2 >= rules.PortalSize.Y - 0.01
end

-- Portal parts have CanQuery off, so test the aim ray against each portal's oval directly.
local function portalOnRay(origin, dir, maxDist)
	local folder = workspace:FindFirstChild(PingModule.PortalFolderName)
	if not folder then return nil end

	local pad = PingModule.PortalAimPadding
	local best, bestT, bestPoint = nil, maxDist, nil
	for _, portal in ipairs(folder:GetChildren()) do
		if portal:IsA("BasePart") then
			local cf = portal.CFrame
			local n = cf.LookVector
			local denom = dir:Dot(n)
			if denom < -1e-3 then
				local t = (cf.Position - origin):Dot(n) / denom
				if t > 0 and t < bestT then
					local p = origin + dir * t
					local lp = cf:PointToObjectSpace(p)
					local ex = lp.X / (portal.Size.X * 0.5 + pad)
					local ey = lp.Y / (portal.Size.Y * 0.5 + pad)
					if ex * ex + ey * ey <= 1 then
						best, bestT, bestPoint = portal, t, p
					end
				end
			end
		end
	end
	return best, bestT, bestPoint
end

local function highlightTargetFor(found)
	if found:IsA("Model") and found ~= workspace then return found end
	local model = found:FindFirstAncestorWhichIsA("Model")
	if model and model ~= workspace then return model end
	return found
end

local function getContext()
	local cam = getCamera()
	local vp = cam.ViewportSize
	local unitRay = cam:ViewportPointToRay(vp.X * 0.5, vp.Y * 0.5)
	local origin, dir = unitRay.Origin, unitRay.Direction

	local filter = {LocalPlayer.Character, cam, ringFolder}
	local folder = workspace:FindFirstChild(PingModule.PortalFolderName)
	if folder then table.insert(filter, folder) end
	local beams = workspace:FindFirstChild("TestElementBeams")
	if beams then table.insert(filter, beams) end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter

	local hit
	for _ = 1, 6 do
		hit = workspace:Raycast(origin, dir * PingModule.MaxDistance, params)
		if not hit or not isPassThrough(hit.Instance) then break end
		params:AddToFilter(hit.Instance)
		hit = nil
	end

	local hitDist = hit and (hit.Position - origin).Magnitude or PingModule.MaxDistance
	local portal, _, portalPoint = portalOnRay(origin, dir, hitDist + 0.5)
	if portal then
		local n = portal.CFrame.LookVector
		return {
			Position = portalPoint,
			Normal = n,
			IsHorizontal = math.abs(n.Y) > PingModule.FloorThreshold,
			IsGround = n.Y > PingModule.FloorThreshold,
			Kind = "Portal",
		}
	end

	if not hit then return nil end

	local part = hit.Instance
	local ctx = {
		Position = hit.Position,
		Normal = hit.Normal,
		IsHorizontal = math.abs(hit.Normal.Y) > PingModule.FloorThreshold,
		IsGround = hit.Normal.Y > PingModule.FloorThreshold,
		Kind = "Surface",
	}

	for _, kind in ipairs(OBJECT_KINDS) do
		local found = findTagged(part, PingModule.Tags[kind]) or findNamed(part, PingModule.Keywords[kind])
		if found then
			ctx.Kind = kind
			ctx.Target = highlightTargetFor(found)
			return ctx
		end
	end

	if isPortalable(part, hit.Position, hit.Normal, cam.CFrame.LookVector) then
		ctx.Kind = "Portalable"
	end
	return ctx
end

local function resolveKey(key, ctx)
	local variant = key .. (ctx.IsHorizontal and "Floor" or "Wall")
	if PingModule.Decals[variant] then return variant end
	return key
end

local function buildSlots(ctx, page)
	local def = page == "Emotes" and PingModule.EmotePage
		or PingModule.Contexts[ctx.Kind]
		or PingModule.Contexts.Surface

	local slots = {}
	for _, name in ipairs(SLOT_NAMES) do
		local key = def[name]
		if not key and ctx.IsGround and def.Ground then key = def.Ground[name] end
		if key then slots[name] = resolveKey(key, ctx) end
	end
	return slots
end

---------------------------------------------------------------------
-- Hint: "F  Use your Ping Tool" (first time the server has 2+ players)
---------------------------------------------------------------------
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "PingHint"
hintGui.IgnoreGuiInset = true
hintGui.ResetOnSpawn = false
hintGui.DisplayOrder = 30
hintGui.Enabled = false
hintGui.Parent = PlayerGui

local hintImg = Instance.new("ImageLabel")
hintImg.Name = "Hint"
hintImg.BackgroundTransparency = 1
hintImg.AnchorPoint = Vector2.new(0.5, 0.5)
hintImg.Image = PingModule.Assets.Hint or ""
hintImg.ScaleType = Enum.ScaleType.Fit
hintImg.ImageTransparency = 1
hintImg.Parent = hintGui
local GuiService = game:GetService("GuiService")
local hintShown = false  -- only ever shows once per session
local hintActive = false
local hintToken = 0
-- where the hint lands: dead center, or the crosshair's center if it respects the top bar inset
local function hintTarget()
	local y = 0
	if HintCfg.MatchCrosshairInset then
		local inset = GuiService:GetGuiInset()
		y = inset.Y * 0.5
	end
	local o = HintCfg.Offset or Vector2.zero
	return UDim2.new(0.5, o.X, 0.5, y + o.Y)
end
local function hideHint()
	if not hintActive then return end
	hintActive = false
	hintToken += 1
	local info = TweenInfo.new(HintCfg.OutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local t = tween(hintImg, info, {
		ImageTransparency = 1,
		Position = hintTarget() + UDim2.fromOffset(0, 14),
	})
	t.Completed:Once(function()
		if not hintActive then hintGui.Enabled = false end
	end)
end

local function showHint()
	if hintShown or not (HintCfg and HintCfg.Enabled) then return end
	hintShown = true
	hintActive = true
	hintToken += 1
	local token = hintToken

	-- start at the bottom-right corner, invisible, then glide into place
	hintImg.Position = UDim2.fromScale(1, 1)
	hintImg.ImageTransparency = 1
	hintGui.Enabled = true
	tween(hintImg, TweenInfo.new(HintCfg.InTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{Position = hintTarget()})
	tween(hintImg, TweenInfo.new(HintCfg.InTime * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ImageTransparency = 0})

	task.delay(HintCfg.MaxTime, function()
		if token == hintToken then hideHint() end
	end)
end

local function checkMultiplayer()
	if hintShown or not canPing() then return end
	task.delay(HintCfg.ShowDelay, function()
		if canPing() then showHint() end
	end)
end

---------------------------------------------------------------------
-- Placed pings (several per player)
---------------------------------------------------------------------
local activePings = {} -- [pingId] = ping
local pingCounter = 0
local lastPingTime = 0

local function removePing(id)
	local p = activePings[id]
	if not p then return end
	activePings[id] = nil
	p.Holder:Destroy()
	p.Arrow:Destroy()
	p.Tether:Destroy()
	destroyRing(p.Ring)
	if p.Highlight then p.Highlight:Destroy() end
end

local function removeAllFrom(userId)
	for id, p in pairs(activePings) do
		if p.OwnerId == userId then removePing(id) end
	end
end

-- make room for a new ping: drop this player's oldest ones past the limit
local function trimOwner(userId)
	local mine = {}
	for id, p in pairs(activePings) do
		if p.OwnerId == userId then table.insert(mine, {Id = id, At = p.CreatedAt}) end
	end
	table.sort(mine, function(a, b) return a.At < b.At end)
	local max = math.max(1, PingModule.MaxPingsPerPlayer or 1)
	while #mine >= max do
		removePing(table.remove(mine, 1).Id)
	end
end

local function spawnPing(owner, data)
	if typeof(data) ~= "table" or typeof(data.Position) ~= "Vector3" or typeof(data.Normal) ~= "Vector3" then return end
	if typeof(data.Type) ~= "string" then return end

	trimOwner(owner.UserId)
	pingCounter += 1
	local id = pingCounter

	local color = typeof(data.Color) == "Color3" and data.Color or getColorFor(owner)
	local isDeath = data.Type == "Death"
	local imageKey = isDeath and deathKeyFor(owner) or data.Type

	local holder = Instance.new("Frame")
	holder.Name = "Ping_" .. owner.Name .. "_" .. id
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 2
	holder.Parent = trackerGui

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(1.6, 1.6)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = PingModule.GetImage(imageKey)
	icon.ImageColor3 = PingModule.NoTint[imageKey] and Color3.new(1, 1, 1) or color
	icon.ZIndex = 2
	icon.Parent = holder
	tween(icon, TWEEN_POP, {Size = UDim2.fromScale(1, 1)})

	local A = PingModule.OffscreenArrow
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "OffscreenArrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Image = PingModule.Assets.ArrowDecal
	arrow.ImageColor3 = color
	arrow.Size = arrowSize(A.Length, A.Thickness)
	arrow.ZIndex = 2
	arrow.Visible = false
	arrow.Parent = trackerGui

	-- see-through wedge from the reticle center to the icon
	local tether = Instance.new("ImageLabel")
	tether.Name = "Tether"
	tether.AnchorPoint = Vector2.new(0.5, 0.5)
	tether.BackgroundTransparency = 1
	tether.Image = PingModule.Assets.Tether
	tether.ImageColor3 = color
	tether.ImageTransparency = WorldCfg.TetherTransparency
	tether.ScaleType = Enum.ScaleType.Stretch
	tether.ZIndex = 1
	tether.Visible = false
	tether.Parent = trackerGui

	local highlight
	if PingModule.HighlightTargets and typeof(data.Target) == "Instance" and data.Target:IsDescendantOf(workspace) then
		highlight = Instance.new("Highlight")
		highlight.Adornee = data.Target
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.FillTransparency = 0.8
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = data.Target
	end

	local sequence = nil
	local fadeDelay = PingModule.TypeDurations[data.Type] or PingModule.FadeDelay
	if data.Type == "Countdown" then
		sequence = PingModule.CountdownSequence
		fadeDelay = #sequence * PingModule.CountdownInterval + PingModule.CountdownHold
	end

	activePings[id] = {
		OwnerId = owner.UserId,
		Position = data.Position,
		Holder = holder,
		Icon = icon,
		Arrow = arrow,
		Tether = tether,
		Ring = makeRing(data.Position, data.Normal.Unit, color),
		Highlight = highlight,
		Sequence = sequence,
		FadeDelay = fadeDelay,
		IconScale = PingModule.TypeIconScale[imageKey] or 1,
		CreatedAt = os.clock(),
	}

	playSound(isDeath and PingModule.Assets.DeathSound or PingModule.Assets.PingSound)
end

local function sendPing(key, ctx)
	if not key or not ctx then return end
	lastPingTime = os.clock()
	hideHint()
	local data = {
		Position = ctx.Position,
		Normal = ctx.Normal,
		Type = key,
		Color = getColorFor(LocalPlayer),
		Target = ctx.Target,
	}
	spawnPing(LocalPlayer, data)
	if hasPartner() then
		PingEvent:FireServer(data)
	end
end

---------------------------------------------------------------------
-- Radial menu
---------------------------------------------------------------------
local isKeyDown = false
local pressToken = 0
local menuOpen = false
local menuCtx = nil
local menuPage = "Main"
local currentSlots = {}
local selected = "Center"
local gesture = Vector2.zero
local previewRing = nil
local savedMouseBehavior, savedIconEnabled
local pressedKey = nil
local arrowState = nil -- nil = hidden, "Free" = following the mouse, slot name = snapped

local function hideArrow()
	arrowState = nil
	menuArrow.Visible = false
end

local function showArrow(u, state)
	local d = Layout.SlotDistance * Layout.ArrowOffset
	menuArrow.Position = UDim2.fromOffset(u.X * d, u.Y * d)
	menuArrow.Rotation = arrowRotation(u)

	local wasHidden = not menuArrow.Visible
	local snappedNew = state ~= "Free" and state ~= arrowState
	arrowState = state
	menuArrow.Visible = true

	if wasHidden or snappedNew then
		local sz = MENU_ARROW_SIZE
		menuArrow.Size = UDim2.fromOffset(sz.X.Offset * 0.6, sz.Y.Offset * 0.6)
		tween(menuArrow, TWEEN_POP, {Size = MENU_ARROW_SIZE})
	end
end

local function applySlots(slots)
	currentSlots = slots
	for _, name in ipairs(SLOT_NAMES) do
		local key = slots[name]
		slotIcons[name].Visible = key ~= nil
		if key then slotIcons[name].Image = PingModule.GetImage(key) end
	end
end

local function setSelected(name, instant)
	local changed = name ~= selected
	if not changed and not instant then return end
	selected = name

	for _, slotName in ipairs(SLOT_NAMES) do
		local icon = slotIcons[slotName]
		local isSel = slotName == name
		local size = isSel and Layout.BigSize or Layout.SmallSize
		local props = {
			Size = UDim2.fromOffset(size, size),
			ImageTransparency = isSel and 0 or Layout.UnselectedTransparency,
		}
		icon.ZIndex = isSel and 4 or 2
		if instant then
			icon.Size, icon.ImageTransparency = props.Size, props.ImageTransparency
		else
			tween(icon, TWEEN_SELECT, props)
		end
	end

	for dir, line in pairs(lines) do
		line.Visible = currentSlots[dir] ~= nil and dir ~= name
	end

	if changed and not instant then
		playSound(PingModule.Assets.HoverSound)
	end
end

local function pickSlot(v, deadzone, maxAngle)
	if v.Magnitude < deadzone then return "Center" end
	local unit = v.Unit
	local best, bestDot = nil, math.cos(math.rad(maxAngle))
	for dir, vec in pairs(DIRS) do
		if currentSlots[dir] then
			local d = unit:Dot(vec)
			if d >= bestDot then best, bestDot = dir, d end
		end
	end
	return best
end

local function updateAim(v, deadzone, maxAngle)
	local pick = pickSlot(v, deadzone, maxAngle)
	if pick == "Center" then
		setSelected("Center")
		hideArrow()
	elseif pick then
		setSelected(pick)
		showArrow(DIRS[pick], pick)
	else
		setSelected("Center")
		showArrow(v.Unit, "Free")
	end
end

local closeMenu -- forward

local function onGesture(_, state, input)
	if not menuOpen then return Enum.ContextActionResult.Pass end

	if input.UserInputType == Enum.UserInputType.MouseMovement then
		gesture += Vector2.new(input.Delta.X, input.Delta.Y) * Layout.Sensitivity
		if gesture.Magnitude > Layout.MaxTravel then
			gesture = gesture.Unit * Layout.MaxTravel
		end
		updateAim(gesture, Layout.Deadzone, Layout.SnapAngle)

	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		menuPage = menuPage == "Main" and "Emotes" or "Main"
		gesture = Vector2.zero
		applySlots(buildSlots(menuCtx, menuPage))
		setSelected("Center", true)
		hideArrow()
		playSound(PingModule.Assets.HoverSound, 0.9)

	elseif input.UserInputType == Enum.UserInputType.MouseButton2 and state == Enum.UserInputState.Begin then
		isKeyDown = false
		closeMenu()

	elseif input.KeyCode == PingModule.GamepadStick then
		local v = Vector2.new(input.Position.X, -input.Position.Y) * Layout.MaxTravel
		updateAim(v, Layout.MaxTravel * 0.5, Layout.GamepadAngle)
	end

	return Enum.ContextActionResult.Sink
end

local function openMenu()
	local ctx = getContext()
	if not ctx then return end

	menuOpen = true
	menuCtx = ctx
	menuPage = "Main"
	gesture = Vector2.zero
	selected = "Center"
	hideArrow()

	applySlots(buildSlots(ctx, menuPage))
	setSelected("Center", true)
	previewRing = makeRing(ctx.Position, ctx.Normal, getColorFor(LocalPlayer), 0.45)

	savedMouseBehavior = UserInputService.MouseBehavior
	savedIconEnabled = UserInputService.MouseIconEnabled
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	LocalPlayer:SetAttribute("PingMenuOpen", true)

	ContextActionService:BindActionAtPriority(GESTURE_ACTION, onGesture, false, GESTURE_PRIORITY,
		Enum.UserInputType.MouseMovement,
		Enum.UserInputType.MouseWheel,
		Enum.UserInputType.MouseButton2,
		PingModule.GamepadStick)

	openScale.Scale = 0.85
	menuGui.Enabled = true
	tween(openScale, TWEEN_OPEN, {Scale = 1})
end

closeMenu = function()
	if not menuOpen then return end
	menuOpen = false
	menuGui.Enabled = false
	hideArrow()
	ContextActionService:UnbindAction(GESTURE_ACTION)

	destroyRing(previewRing)
	previewRing = nil

	if savedMouseBehavior then UserInputService.MouseBehavior = savedMouseBehavior end
	if savedIconEnabled ~= nil then UserInputService.MouseIconEnabled = savedIconEnabled end
	LocalPlayer:SetAttribute("PingMenuOpen", false)
end

---------------------------------------------------------------------
-- Input
---------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode ~= PingModule.Key and input.KeyCode ~= PingModule.GamepadKey then return end
	if isKeyDown then return end
	if os.clock() - lastPingTime < PingModule.Cooldown then return end
	if not canPing() then return end

	isKeyDown = true
	pressedKey = input.KeyCode
	pressToken += 1
	local token = pressToken
	task.delay(PingModule.HoldDelay, function()
		if isKeyDown and token == pressToken and not menuOpen then
			openMenu()
		end
	end)
end)

UserInputService.InputEnded:Connect(function(input)
	if not isKeyDown or input.KeyCode ~= pressedKey then return end
	isKeyDown = false

	if menuOpen then
		local key, ctx = currentSlots[selected], menuCtx
		closeMenu()
		sendPing(key, ctx)
	else
		local ctx = getContext()
		if ctx then sendPing(buildSlots(ctx, "Main").Center, ctx) end
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	isKeyDown = false
	closeMenu()
end)

PingEvent.OnClientEvent:Connect(function(sender, data)
	if typeof(sender) == "Instance" and sender:IsA("Player") then
		-- only your co-op partner's pings (and death icons), and only while you're playing together
		if sender ~= LocalPlayer and not (sameChamber(sender) and canPing()) then return end
		spawnPing(sender, data)
	end
end)

Players.PlayerAdded:Connect(checkMultiplayer)
-- pinging turns on / off as you start / leave a co-op chamber: show the hint then, close the menu and clear pings when it ends
local function pingStateChanged()
	if canPing() then
		checkMultiplayer()
	else
		isKeyDown = false
		closeMenu()
		for id in pairs(activePings) do removePing(id) end
	end
end
for _, attr in ipairs({ "InMenu", "InEditor", "EditorPlaytest", "InstanceSlot" }) do
	LocalPlayer:GetAttributeChangedSignal(attr):Connect(pingStateChanged)
end
Players.PlayerRemoving:Connect(function(player)
	removeAllFrom(player.UserId)
end)
task.defer(checkMultiplayer) -- already 2+ players when you join

---------------------------------------------------------------------
-- Per-frame: scaling, projection, tether, off-screen arrow, fade
---------------------------------------------------------------------
local function edgeClamp(dir, vp, margin)
	local half = vp * 0.5 - Vector2.new(margin, margin)
	local sx = dir.X ~= 0 and half.X / math.abs(dir.X) or math.huge
	local sy = dir.Y ~= 0 and half.Y / math.abs(dir.Y) or math.huge
	return vp * 0.5 + dir * math.min(sx, sy)
end

RunService.RenderStepped:Connect(function()
	local cam = getCamera()
	local vp = cam.ViewportSize
	local center = vp * 0.5
	local now = os.clock()
	local s = math.clamp(vp.Y / Layout.ReferenceHeight, Layout.MinScale, Layout.MaxScale)
	currentScale = s
	menuScale.Scale = s

	if previewRing then animateRing(previewRing, 0) end

	if hintGui.Enabled then
		local h = HintCfg.Height * s
		hintImg.Size = UDim2.fromOffset(h * HintCfg.Aspect, h)
	end

	for id, p in pairs(activePings) do
		local age = now - p.CreatedAt
		if age > p.FadeDelay + PingModule.FadeDuration then
			removePing(id)
			continue
		end
		local fade = age > p.FadeDelay and (age - p.FadeDelay) / PingModule.FadeDuration or 0

		-- countdown 3, 2, 1, GO
		if p.Sequence then
			local step = math.clamp(math.floor(age / PingModule.CountdownInterval) + 1, 1, #p.Sequence)
			if step ~= p.Step then
				p.Step = step
				p.Icon.Image = PingModule.GetImage(p.Sequence[step])
				p.Icon.Size = UDim2.fromScale(1.35, 1.35)
				tween(p.Icon, TWEEN_POP, {Size = UDim2.fromScale(1, 1)})
				local isGo = step == #p.Sequence
				playSound(isGo and PingModule.Assets.CountdownGoSound or PingModule.Assets.CountdownTickSound, isGo and 1 or 1.2)
			end
		end

		animateRing(p.Ring, fade)
		if p.Highlight then
			p.Highlight.OutlineTransparency = fade
			p.Highlight.FillTransparency = 0.8 + 0.2 * fade
		end

		local iconSize = WorldCfg.IconSize * s * p.IconScale
		p.Holder.Size = UDim2.fromOffset(iconSize, iconSize)
		p.Icon.ImageTransparency = fade

		local sp, onScreen = cam:WorldToViewportPoint(p.Position)
		local hit2 = Vector2.new(sp.X, sp.Y)

		if onScreen then
			local iconPos = hit2 + WorldCfg.IconOffset * s * p.IconScale
			p.Holder.Position = UDim2.fromOffset(iconPos.X, iconPos.Y)
			p.Arrow.Visible = false

			-- wedge: point at the reticle center, wide end under the icon
			local delta = iconPos - hit2
			local len = delta.Magnitude
			p.Tether.Visible = len > 2
			p.Tether.Position = UDim2.fromOffset((hit2.X + iconPos.X) * 0.5, (hit2.Y + iconPos.Y) * 0.5)
			p.Tether.Size = UDim2.fromOffset(len, iconSize * WorldCfg.TetherWidth)
			p.Tether.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			local T = WorldCfg.TetherTransparency
			p.Tether.ImageTransparency = T + (1 - T) * fade
		else
			local dir = hit2 - center
			if sp.Z < 0 then dir = -dir end
			if dir.Magnitude < 1e-3 then dir = Vector2.new(0, 1) end
			dir = dir.Unit

			local pos = edgeClamp(dir, vp, iconSize * 1.4)
			p.Holder.Position = UDim2.fromOffset(pos.X, pos.Y)
			p.Tether.Visible = false

			local A = PingModule.OffscreenArrow
			local ap = pos + dir * (iconSize * 0.5 + A.Gap + A.Length * 0.5)
			p.Arrow.Visible = true
			p.Arrow.Position = UDim2.fromOffset(ap.X, ap.Y)
			p.Arrow.Rotation = arrowRotation(dir)
			p.Arrow.ImageTransparency = fade
		end
	end
end)
