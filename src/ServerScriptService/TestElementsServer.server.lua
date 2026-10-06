-- TestElementsServer
-- ServerScriptService (Script)
-- Hard Light Bridges, lasers, fizzlers, funnels and cube droppers, built on YOUR
-- models, all working through portals.
--
-- RECOGNISED BY NAME (or CollectionService tag)
--   "Light_bridge_emitter" / "LightBridge" / anything with "bridge" -> Light Bridge
--   "laser field" / "laserfield" / "laser grid"  (tag "LaserField")  -> Laser Field
--   "laser catcher"                              (tag "LaserCatcher") -> Laser Catcher
--   anything else with "laser" / "lazer"         (tag "LaserEmitter") -> Laser Emitter
--   "Reflective" / "Reflective Cube" / "Weighted Aperture Science Reflective Cube" /
--   "Laser Redirector Cube" / "Discouragement Redirection Cube" (its real in-game name)
--   (or tag "LaserReflector" / "ReflectionCube")                    -> Reflective (redirection) cube
--   anything with "fizzler" / "grill"                                -> Fizzler
--   anything with "tractor" / "funnel" / "excursion" / "tbeam"       -> Excursion Funnel
--   anything with "dropper"  (or tag "CubeDropper")                  -> Cube Dropper
--
-- EXCURSION FUNNEL (TractorBeam.fbx)
--   Fires from the "Middle" bone toward "ShootOut", runs until it hits a wall,
--   goes through portals (out of the exit portal's centre). Carries players
--   (TestElementsClient) and loose objects along it, holding them in the middle.
--   Attributes: Reversed (bool) flips the flow (orange), Speed (studs/s),
--   Radius (studs), Enabled (bool).
--
-- LASER EMITTER (model with a "Laser" beam, "ShootOut", "ShootEnd" attachments, "Main")
--   Fires from ShootOut toward ShootEnd (any angle - up, down, sideways) and runs until it
--   hits a wall. Goes through portals like the real game (keeps its angle and offset; the
--   whole beam is copied for every piece, same as the light bridges), bounces off reflective
--   cubes and lights laser catchers.
--   Touching it hurts a little (LASER_DAMAGE every LASER_DAMAGE_INTERVAL seconds) and shoves
--   you back out of the beam (LASER_PUSH_SPEED). Tweak both in SETTINGS.
--
-- LASER CATCHER
--   While a laser hits it: attributes Activated, LaserActive and Pressed = true (false when it stops).
--   "Pressed" means a catcher works as a button for the test chamber editor's connections.
--
-- CUBE DROPPER (CubeDropper.fbx)
--   The cube waits in the glass tube, the 9-leaf iris opens, the cube falls. For the first
--   DROP_NOCOLLIDE_TIME after it is released it has no collision, so the iris
--   leaves and the tube can't catch it on the way out.
--   Attributes on the dropper model (all optional):
--     CubeType   "Normal" | "Companion" | "Edgeless" (also "Ball", "Sphere") | "Reflection"
--     DropTime   seconds from being triggered until the cube falls         (default 1.5)
--     RespawnOnDestroy  drop a new cube when this one is destroyed / fizzled (default true)
--     DropOnStart       drop a cube when the game starts                    (default true)
--     Enabled    false = never drops
--     Drop       set true from any script to drop a new cube (resets itself). The editor's connections use this,
--                so a dropper can have any number of buttons / gates driving it.
--   Button: an ObjectValue named "Button" inside the dropper pointing at a floor
--   button / pedestal: every time its Pressed / PressesButton turns ON, the old cube fizzles
--   and a new one drops (Portal 2).
--   Your cubes: models/parts named Normal, Companion, Edgeless, Reflection in
--   ReplicatedStorage.PortalAssets.Cubes (or ServerStorage.Cubes); missing ones
--   get a simple placeholder.
--   Dropped cubes go into the map the dropper belongs to (workspace.PortalInstances.Slot_<n>, or workspace.ActiveMap), so rebuilding / leaving a
--   chamber cleans them up.
--
-- FIXED BRIDGES: a bridge with an end piece (a child named "g2..." like
--   "g2End") is connected to another bridge segment, so it is left exactly as
--   built - nothing is moved. Only bridges WITHOUT an end piece (like
--   "LightBridgeFree") stretch and carry on through portals.
--
-- LIGHT BRIDGE / LASER (beam style, like Light_bridge_emitter)
--   Beams between attachment pairs: one end at the emitter, one at the far
--   end. The far ends are moved to where the bridge actually hits; "HitBox"
--   is stretched to match. Through a portal, the whole set (beams,
--   attachments, hitbox) is copied for each extra piece.
--   No beams? Falls back to attachment "1" (and "2" to aim) + drawn parts.
--
-- LASER FIELD
--   A wall of lasers. Walk into it and you die; cubes, gel and portal shots pass
--   through. With posts named "1", "2", ... (like a fizzler) the field runs between
--   them; without posts it covers the model's flat side (its two biggest
--   dimensions). Your own beams / the LaserField texture are the look.
--
-- FIZZLER
--   Posts named "1", "2", ... "10" (parts or attachments). The field runs
--   1 -> 2 -> 3 ... Height = your "Field" beam's width (or the post length).
--   Your own beams are the look.
--
-- ON / OFF: put a bool attribute named  Enabled  on the bridge / laser / fizzler / funnel model.
--   Enabled = false  -> the element switches OFF: every beam, particle, light, fire, smoke,
--                       trail, highlight and sound inside it turns off; a bridge's solid
--                       hitbox stops colliding; lasers stop killing; fizzlers stop fizzling
--                       and stop blocking portal shots; funnels stop carrying.
--   Enabled = true (or no attribute) -> switches back ON, and every effect goes back to
--                       exactly how you built it.
--   Works live: flip it in the Properties panel, or model:SetAttribute("Enabled", false).
--
-- CHANGES IN THIS VERSION
--   * Laser catchers no longer flicker: they used to be switched off and back on every frame, which fired their
--     attribute signals 120 times a second (a dropper wired to one would drop non-stop). Now they only change
--     when a laser actually starts / stops hitting them, and they also set "Pressed".
--   * Catchers are found a few levels up from the part the laser hits (catchers built from sub-models work).
--   * Dropped cubes are parented into their map, not straight into workspace.
--   * A "Drop" set before the dropper finished setting up is no longer lost.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local portalAssets = ReplicatedStorage:WaitForChild("PortalAssets")
local Gel = require(portalAssets:WaitForChild("GelShared")) -- portal links + transforms
local portalsFolder = workspace:WaitForChild("Portals")
local soundsFolder = portalAssets:FindFirstChild("CubeDropper")

-- ==========================================
-- SETTINGS
-- ==========================================
local MAX_BEAM = 800              -- studs a bridge/laser can travel in total
local MAX_PORTAL_HOPS = 8         -- stops infinite portal loops
local END_TOLERANCE = 1.5         -- a portal this far past a bridge's built end still catches it
local BRIDGE_PORTAL_LOW = 0.75    -- bridges leave a portal this far down from its centre
-- (x half the portal's height: 0 = centre, 1 = bottom edge)

local FUNNEL_SPEED = 13           -- studs/s along the funnel (attribute Speed overrides)
local FUNNEL_RADIUS = 54 / 14.7   -- ~3.7 studs (attribute Radius overrides)
local FUNNEL_PULL = 4             -- how hard things are pulled to the funnel's centre line
local FUNNEL_BLUE = Color3.fromRGB(40, 130, 255)
local FUNNEL_ORANGE = Color3.fromRGB(255, 130, 30)
local FUNNEL_SPECK_TEXTURE = "rbxassetid://103287895754358"   -- FunnelSpeck.png IMAGE id
local MIN_HITBOX_THICK = 1        -- free-bridge hitboxes thinner than this get thickened DOWNWARD

local LASER_COLOR = Color3.fromRGB(255, 45, 30)
local LASER_THICKNESS = 0.22      -- (fallback lasers without beams only)
local LASER_HIT_RADIUS = 1.1      -- studs from the beam's centre that burns you
local LASER_DAMAGE = 8            -- health taken per hit ("a bit")
local LASER_DAMAGE_INTERVAL = 0.25 -- seconds between hits while you stay in the beam
local LASER_PUSH_SPEED = 26       -- studs/s you are shoved away from the beam (0 = no push)
local LASER_PUSH_FORCE = 900      -- how hard the shove can fight your walking (x your mass)
local LASER_PUSH_LINGER = 0.12    -- seconds the shove keeps going after you leave the beam

local CATCHER_LENS_ON = Color3.fromRGB(255, 90, 70)   -- placeholder catchers (no asset) light their lens
local CATCHER_LENS_OFF = Color3.fromRGB(110, 30, 30)

local FIELD_DEPTH = 2             -- thickness of the fizzler's detection zone
local FIZZLE_TIME = 1.6           -- seconds an object floats, black, before it's gone
local FIZZLE_RISE = 2.5           -- studs it floats up
local FIZZLE_SOUND = "fizzle"     -- Sounds whose name or folder contains this
local PORTAL_FIZZLE_DEBOUNCE = 0.5

-- cube dropper
local DROP_TIME = 1.5             -- default seconds from trigger to the cube falling (attribute DropTime)
local DROP_NOCOLLIDE_TIME = 0.3   -- seconds the cube has NO collision right as it drops out
local IRIS_OPEN_ANGLE = 80        -- degrees the iris leaves swing (use -80 if they open the wrong way)
local IRIS_OPEN_TIME = 0.35
local IRIS_CLOSE_DELAY = 1.2      -- seconds the iris stays open after the cube falls
local RESPAWN_DELAY = 1.0         -- seconds after a cube is destroyed before the next drops
local CUBE_SIZE = 64 / 14.7       -- Portal cube, ~4.35 studs (placeholders only)
local TUBE_GLASS = true           -- make the dropper's "Tube" part glass (you see the cube inside)
local DROPPER_OPEN_SOUNDS = { "dropper_iris_open", "dropper_open" }   -- Sounds/Testelements/Dropper
local DROPPER_CLOSE_SOUNDS = { "dropper_iris_close", "dropper_close" }
local ISOLATE_DROPPER_SOUNDS = true  -- move those sounds out of PortalAssets.Sounds at start, so no other
-- script hunting for a "drop" sound (a player letting go of a cube) can ever pick them up
local BUTTON_ATTRIBUTES = { "Pressed", "pressed", "PressesButton" } -- what a linked button sets when it's on

-- ==========================================
-- SETUP
-- ==========================================
local cloneFolder = Instance.new("Folder")
cloneFolder.Name = "TestElementBeams"
cloneFolder.Parent = workspace

-- PortalServer listens to these
local fizzlePortals = portalAssets:FindFirstChild("FizzlePortals")
if not fizzlePortals then
	fizzlePortals = Instance.new("BindableEvent")
	fizzlePortals.Name = "FizzlePortals"
	fizzlePortals.Parent = portalAssets
end
local shotCheck = portalAssets:FindFirstChild("FizzlerBlocksShot")
if not shotCheck then
	shotCheck = Instance.new("BindableFunction")
	shotCheck.Name = "FizzlerBlocksShot"
	shotCheck.Parent = portalAssets
end

local elements = {} -- [model] = element

-- ==========================================
-- HELPERS
-- ==========================================
-- every name a reflective (laser redirection) cube may have. Case, spaces and symbols
-- don't matter: "Laser Redirector Cube" == "laser_redirector_cube".
local REFLECTOR_NAMES = {
	"reflectioncube", "reflectivecube", "laserreflector", "laserredirector",
	"redirectioncube", "redirectorcube", "laserredirection", "refractioncube",
	"discouragementredirection", -- "Discouragement Redirection Cube", the real in-game name
}
local function isReflectorName(name)
	local s = string.lower(name):gsub("[^%a]", "")
	if s == "reflective" then return true end -- plain "Reflective"
	for _, frag in ipairs(REFLECTOR_NAMES) do
		if s:find(frag, 1, true) then return true end
	end
	return false
end

local function kindOf(m)
	if CollectionService:HasTag(m, "LightBridge") then return "Bridge" end
	if CollectionService:HasTag(m, "LaserField") then return "LaserField" end
	if CollectionService:HasTag(m, "LaserCatcher") then return "LaserCatcher" end
	if CollectionService:HasTag(m, "LaserReflector") or CollectionService:HasTag(m, "ReflectionCube") then return "LaserReflector" end
	if CollectionService:HasTag(m, "LaserEmitter") then return "Laser" end
	if CollectionService:HasTag(m, "Fizzler") then return "Fizzler" end
	if CollectionService:HasTag(m, "Funnel") then return "Funnel" end
	local n = string.lower(m.Name)
	if n:find("bridge") then return "Bridge" end
	local squashed = n:gsub("[^%a]", "")
	if squashed:find("laserfield") or squashed:find("lasergrid") then return "LaserField" end
	if n:find("laser%s*catcher") or n:find("lasercatcher") then return "LaserCatcher" end
	if isReflectorName(m.Name) then return "LaserReflector" end
	if n:find("laser") or n:find("lazer") then return "Laser" end
	if n:find("fizzler") or n:find("grill") then return "Fizzler" end
	if n:find("tractor") or n:find("funnel") or n:find("excursion") or n:find("tbeam") then return "Funnel" end
	return nil
end

-- has a second segment piece (g2End etc.)? then it's a fixed bridge
local function hasEndPiece(m)
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("BasePart") and string.lower(c.Name):sub(1, 2) == "g2" then
			return true
		end
	end
	return false
end

local function isStatic(part)
	if part.Anchored then return true end
	local root = part.AssemblyRootPart
	return root ~= nil and root.Anchored
end

local function enabled(el)
	return el.model:GetAttribute("Enabled") ~= false
end

local function characterOf(inst)
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then return m end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function findAttachment(m, ...)
	local want = {}
	for _, n in ipairs({ ... }) do want[string.lower(n):gsub("[^%a]", "")] = true end
	for _, d in ipairs(m:GetDescendants()) do
		-- Bones are Attachments too; InitialPoses/AnimSaves only hold Poses
		if d:IsA("Attachment") and want[string.lower(d.Name):gsub("[^%a]", "")] then return d end
	end
	return nil
end

-- attachments may sit in a part OR directly in the model (then they're world-space)
local function inPartOrBone(att)
	return att:IsA("Bone") or (att.Parent and (att.Parent:IsA("BasePart") or att.Parent:IsA("Attachment")))
end
local function setAttPos(att, pos)
	if inPartOrBone(att) then
		att.WorldPosition = pos
	else
		att.Position = pos
	end
end

-- position + rotation: beams lay their ribbon by how the attachments are turned,
-- so turning the bridge means turning its attachments too
local function setAttCF(att, cf)
	if inPartOrBone(att) then
		att.WorldCFrame = cf
	else
		att.CFrame = cf
	end
end

-- anything inside an element that makes a visible / audible effect
local function isEffect(d)
	return d:IsA("Beam") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Fire")
		or d:IsA("Smoke") or d:IsA("Sparkles") or d:IsA("Light") or d:IsA("Highlight")
end

local function setVisible(el, on)
	-- remember how each effect was set up, so switching back ON restores it exactly
	-- (an effect you left disabled in Studio stays disabled)
	el.saved = el.saved or {}
	local saved = el.saved
	for _, d in ipairs(el.model:GetDescendants()) do
		if isEffect(d) then
			if on then
				local was = saved[d]
				if was ~= nil then d.Enabled = was end
			else
				if saved[d] == nil then saved[d] = d.Enabled end
				d.Enabled = false
			end
		elseif d:IsA("Sound") then
			if on then
				if saved[d] then d:Play() end
			else
				if saved[d] == nil then saved[d] = d.Playing end
				d:Stop()
			end
		end
	end
	if on then el.saved = {} end
	if el.kit and el.kit.hit then
		el.kit.hit.CanCollide = on and el.kit.hitCollide or false
	end
	for _, x in ipairs(el.extra or {}) do
		x.holder.Parent = (on and x.used) and cloneFolder or nil
	end
	for _, p in ipairs(el.pool or {}) do
		p.Parent = on and cloneFolder or nil
	end
end

-- ==========================================
-- BEAM TRACE (through linked portals)
-- ==========================================
-- Everything a beam must NOT stop on: portals, our own pieces, the emitter itself,
-- characters, and EVERY bridge hitbox (so crossing bridges don't cut each other short
-- or stick to invisible walls).
local function beamExclude(el)
	local list = { portalsFolder, cloneFolder, el.model }
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(list, plr.Character) end
	end
	local passage = workspace:FindFirstChild("PortalPassage")
	if passage then table.insert(list, passage) end
	for _, other in pairs(elements) do
		if other.kind == "Bridge" then
			if other.kit and other.kit.hit then table.insert(list, other.kit.hit) end
			for _, x in ipairs(other.extra or {}) do
				if x.hit then table.insert(list, x.hit) end
			end
		end
	end
	return list
end

-- segments { start, end, up }
-- reemit = true (light bridges): the exit portal re-emits the beam from its
-- centre, straight out and lined up with the portal (Portal 2). Otherwise
-- (lasers) the beam keeps its angle and offset through the portal.
local function trace(origin, dir, up, exclude, firstMax, reemit, low)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = exclude
	local links = Gel.getLinks(portalsFolder)
	local segs, remaining = {}, MAX_BEAM

	local skipped = {}
	local function cast(o, d)
		for _ = 1, 8 do
			local h = workspace:Raycast(o, d, params)
			-- bridges pass loose objects (cubes resting on them don't cut them short)
			if not (h and reemit and not isStatic(h.Instance)) then return h end
			table.insert(skipped, h.Instance)
			local f = table.clone(exclude)
			for _, x in ipairs(skipped) do table.insert(f, x) end
			params.FilterDescendantsInstances = f
		end
		return nil
	end

	for hop = 0, MAX_PORTAL_HOPS do
		-- the emitter's own piece only reaches as far as it was built (+ a little
		-- slack so a portal on the wall it ends at still catches it)
		local cap = (hop == 0 and firstMax) and math.min(remaining, firstMax + END_TOLERANCE) or remaining
		local hit = cast(origin, dir * cap)
		local endP = hit and hit.Position or (origin + dir * cap)
		local probeEnd = endP + dir * 0.3 -- portals sit a hair in front of their wall

		local bestT, inP, outP
		for _, link in ipairs(links) do
			local p = link[1]
			local cf = p.CFrame
			local a, b = cf:PointToObjectSpace(origin), cf:PointToObjectSpace(probeEnd)
			local da, db = -a.Z, -b.Z
			if da > 0 and db <= 0 then
				local t = da / (da - db)
				local h = a:Lerp(b, t)
				local ex, ey = h.X / (p.Size.X * 0.5), h.Y / (p.Size.Y * 0.5)
				if ex * ex + ey * ey <= 1 and (not bestT or t < bestT) then
					bestT, inP, outP = t, p, link[2]
				end
			end
		end

		if bestT then
			local cross = origin:Lerp(probeEnd, bestT)
			table.insert(segs, { origin, cross, up })
			remaining -= (cross - origin).Magnitude
			if remaining <= 0 then break end
			if reemit then
				-- out of the exit portal near its bottom, perpendicular, turned with the
				-- portal (so you can walk out of the portal onto it)
				local ocf = outP.CFrame
				origin = ocf.Position - ocf.UpVector * (outP.Size.Y * 0.5 * (low or 0))
					+ ocf.LookVector * 0.05
				dir = ocf.LookVector
				up = ocf.UpVector
			else
				origin = Gel.xformCF(CFrame.new(cross), inP, outP).Position + outP.CFrame.LookVector * 0.05
				dir = Gel.xformDir(dir, inP, outP).Unit
				up = Gel.xformDir(up, inP, outP).Unit
			end
		else
			if hop == 0 and firstMax then
				-- no portal: the bridge stays exactly the length it was built
				local d = math.min((endP - origin).Magnitude, firstMax)
				endP = origin + dir * d
			end
			table.insert(segs, { origin, endP, up })
			break
		end
	end
	return segs
end

-- ==========================================
-- BEAM-STYLE EMITTERS (your Light_bridge_emitter)
-- ==========================================
local function buildKit(el)
	local m = el.model
	local beams = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Beam") and d.Attachment0 and d.Attachment1 then table.insert(beams, d) end
	end
	if #beams == 0 then return false end

	local hit = m:FindFirstChild("HitBox")
	-- emitter body = the model's parts except the hitbox
	local sum, n = Vector3.zero, 0
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p ~= hit then sum += p.Position; n += 1 end
	end
	local body = n > 0 and sum / n or m:GetPivot().Position

	local list = {}
	for _, b in ipairs(beams) do
		local a0, a1 = b.Attachment0, b.Attachment1
		local near, far = a0, a1
		if (a1.WorldPosition - body).Magnitude < (a0.WorldPosition - body).Magnitude then
			near, far = a1, a0
		end
		table.insert(list, { beam = b, near = near, far = far, nearIs0 = (near == a0) })
	end
	local main = list[1]
	for _, p in ipairs(list) do
		if p.beam.Name == "Beam" or p.near.Name == "Middle" then main = p break end
	end

	-- Attachments sitting loose in the Model (not inside a part) can't be
	-- placed in the world properly - their far end ends up somewhere random.
	-- Give them an invisible holder part so moving them actually works.
	local holder
	-- LASER emitters never use that holder (it sits at the world origin, far from the laser).
	-- Their loose attachments are moved INTO the emitter's own body ("Main"), staying exactly
	-- where they were built, so they travel with the emitter and load in with it.
	local function bodyPartFor(att)
		local mainPart = m:FindFirstChild("Main", true)
		if mainPart and mainPart:IsA("BasePart") then return mainPart end
		local best, bestD
		for _, bp in ipairs(m:GetDescendants()) do
			if bp:IsA("BasePart") and bp ~= hit then
				local d = (bp.Position - att.WorldPosition).Magnitude
				if not bestD or d < bestD then best, bestD = bp, d end
			end
		end
		return best
	end
	for _, p in ipairs(list) do
		for _, att in ipairs({ p.near, p.far }) do
			if not inPartOrBone(att) then -- bones stay in their rig (moving them breaks the skinned mesh)
				local anchor = el.kind == "Laser" and bodyPartFor(att) or nil
				if anchor then
					local wcf = att.WorldCFrame
					att.Parent = anchor
					att.WorldCFrame = wcf
				elseif not holder then
					holder = Instance.new("Part")
					holder.Name = "BridgeEndHolder"
					holder.Anchored = true
					holder.CanCollide = false
					holder.CanQuery = false
					holder.CanTouch = false
					holder.CastShadow = false
					holder.Transparency = 1
					holder.Size = Vector3.one * 0.2
					holder.CFrame = CFrame.new()
					holder.Parent = m
					att.Parent = holder -- the beam keeps pointing at the same attachment
				else
					att.Parent = holder
				end
			end
		end
	end

	local origin = main.near.WorldPosition

	-- which way is "up" for the bridge surface: the hitbox's thinnest side
	local up = Vector3.yAxis
	if hit then
		local axes = { { hit.CFrame.RightVector, hit.Size.X }, { hit.CFrame.UpVector, hit.Size.Y }, { hit.CFrame.LookVector, hit.Size.Z } }
		table.sort(axes, function(x, y) return x[2] < y[2] end)
		up = axes[1][1]
		if up.Y < 0 then up = -up end
		-- too thin and you can fall straight through it when you land fast:
		-- thicken it downward so the walking surface stays exactly where it was
		local thin = axes[1][2]
		if thin < MIN_HITBOX_THICK then
			local extra = MIN_HITBOX_THICK - thin
			local s = hit.Size
			local cfr = hit.CFrame
			if axes[1][1] == cfr.RightVector or axes[1][1] == -cfr.RightVector then
				hit.Size = Vector3.new(MIN_HITBOX_THICK, s.Y, s.Z)
			elseif axes[1][1] == cfr.UpVector or axes[1][1] == -cfr.UpVector then
				hit.Size = Vector3.new(s.X, MIN_HITBOX_THICK, s.Z)
			else
				hit.Size = Vector3.new(s.X, s.Y, MIN_HITBOX_THICK)
			end
			hit.CFrame = cfr - up * (extra / 2)
		end
	end

	-- Direction: straight out of the Middle attachment. Of its six axis
	-- directions, use the one that lies flat along the bridge (not up/down)
	-- and points out of the emitter's front (away from the emitter body).
	-- The far attachments are ignored: loose in a model they mean nothing.
	local mid = main.near
	for _, p in ipairs(list) do
		if p.near.Name == "Middle" then mid = p.near break end
	end
	origin = mid.WorldPosition
	local wcf = mid.WorldCFrame
	local out = origin - body
	out = out - up * out:Dot(up)
	local dir, best = nil, -math.huge
	for _, v in ipairs({ wcf.RightVector, -wcf.RightVector, wcf.UpVector, -wcf.UpVector, wcf.LookVector, -wcf.LookVector }) do
		if math.abs(v:Dot(up)) < 0.7 then -- along the bridge surface, not into it
			local score = out.Magnitude > 1e-3 and v:Dot(out.Unit) or 0
			if score > best then dir, best = v, score end
		end
	end
	-- "Shoot out" attachment: if it's there, the bridge fires from Middle
	-- straight toward it (any spelling: "Shoot out", "ShootOut", "shoot_out")
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Attachment") and string.lower(d.Name):gsub("[^%a]", "") == "shootout" then
			local aim = d.WorldPosition - origin
			aim = aim - up * aim:Dot(up) -- keep the bridge flat
			if aim.Magnitude > 0.05 then
				dir = aim.Unit
			end
			break
		end
	end
	-- LASER: start at ShootOut (the muzzle), aim at ShootEnd. Whichever of the two is nearer
	-- the emitter body is the start. No flattening, so it works pointing up / down / angled.
	if el.kind == "Laser" then
		local a = findAttachment(m, "ShootOut", "Shoot out")
		local b = findAttachment(m, "ShootEnd", "Shoot end")
		if a and b and (a.WorldPosition - b.WorldPosition).Magnitude > 0.05 then
			local s, e = a.WorldPosition, b.WorldPosition
			if (e - body).Magnitude < (s - body).Magnitude then s, e = e, s end
			origin = s
			dir = (e - s).Unit
		end
	end
	if not dir then return false end
	up = up - dir * up:Dot(dir)
	if up.Magnitude > 1e-3 then
		up = up.Unit
	else
		up = math.abs(dir.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	end

	local frame0 = CFrame.lookAt(origin, origin + dir, up)
	local kit = { pairs = list, dir = dir, up = up, origin = origin }
	for _, p in ipairs(list) do
		p.nearRel = frame0:PointToObjectSpace(p.near.WorldPosition)
		p.nearRelCF = frame0:ToObjectSpace(p.near.WorldCFrame) -- incl. how it's turned
		p.farRot = frame0.Rotation:ToObjectSpace(p.far.WorldCFrame.Rotation)
	end
	if hit then
		kit.hit = hit
		kit.hitCollide = hit.CanCollide
		kit.hitRel = frame0:ToObjectSpace(hit.CFrame)
		kit.hitSize = hit.Size
		-- which side of the hitbox runs along the bridge
		local bestI, bestDot = 1, -1
		for i, v in ipairs({ hit.CFrame.RightVector, hit.CFrame.UpVector, hit.CFrame.LookVector }) do
			local d = math.abs(v:Dot(dir))
			if d > bestDot then bestI, bestDot = i, d end
		end
		kit.hitAxis = bestI
	end
	el.kit = kit
	el.extra = {}
	return true
end

local function sizedAlong(size, axis, len)
	if axis == 1 then return Vector3.new(len, size.Y, size.Z) end
	if axis == 2 then return Vector3.new(size.X, len, size.Z) end
	return Vector3.new(size.X, size.Y, len)
end

local function tintHitbox(hitbox)
end

-- one bridge piece: near attachments at the segment start, far ones len along it
local function placeSegment(kit, nearAtts, farAtts, hitbox, frame, len, keepNear)
	for i, p in ipairs(kit.pairs) do
		local n = p.nearRel
		local rot = p.nearRelCF.Rotation
		-- near end: where it was built, turned with the bridge piece
		-- (a laser's own start attachment is left exactly where it was built)
		if not keepNear then setAttCF(nearAtts[i], frame * p.nearRelCF) end
		-- far end: straight across from its near end, len along the bridge, same turn
		setAttCF(farAtts[i], frame * (CFrame.new(n.X, n.Y, n.Z - len) * rot))
	end
	if hitbox then
		-- the hitbox spans the whole piece, at the same height/side offset as built
		local r = kit.hitRel
		hitbox.Size = sizedAlong(kit.hitSize, kit.hitAxis, math.max(len, 0.05))
		hitbox.CFrame = frame * CFrame.new(r.X, r.Y, -len / 2) * r.Rotation
		tintHitbox(hitbox)
	end
end

-- a copy of the whole bridge (beams + attachments + hitbox) for pieces past a portal
local function makeExtra(el)
	local kit = el.kit
	local holder = Instance.new("Part")
	holder.Name = "BridgePiece"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new()
	local x = { holder = holder, near = {}, far = {} }
	for i, p in ipairs(kit.pairs) do
		local n, f = p.near:Clone(), p.far:Clone()
		n.Parent, f.Parent = holder, holder
		local b = p.beam:Clone()
		b.Attachment0 = p.nearIs0 and n or f
		b.Attachment1 = p.nearIs0 and f or n
		b.Parent = holder
		x.near[i], x.far[i] = n, f
	end
	if kit.hit then
		x.hit = kit.hit:Clone()
		for _, c in ipairs(x.hit:GetChildren()) do
			if c:IsA("Attachment") or c:IsA("Beam") then c:Destroy() end
		end
		x.hit.CanCollide = kit.hitCollide
		x.hit.Parent = holder
	end
	return x
end

local function sameSegs(a, b)
	if not a or #a ~= #b then return false end
	for i = 1, #a do
		if (a[i][1] - b[i][1]).Magnitude > 0.01 or (a[i][2] - b[i][2]).Magnitude > 0.01
			or a[i][3]:Dot(b[i][3]) < 0.9999 then -- the piece turned (re-placed portal, same spot)
			return false
		end
	end
	return true
end

-- ==========================================
-- LASER CATCHERS
-- ==========================================
local litNow, litLast = {}, {} -- catchers a laser hit this frame / last frame

-- the catcher model around the part a laser hit (checked a few levels up)
local function catcherModel(inst)
	local node = inst
	for _ = 1, 6 do
		if not node or node == workspace then break end
		if node:IsA("Model") then
			local n = string.lower(node.Name):gsub("%s+", "")
			if CollectionService:HasTag(node, "LaserCatcher") or n:find("lasercatcher", 1, true) then return node end
		end
		node = node.Parent
	end
	return nil
end

local function isLaserCatcher(inst)
	return catcherModel(inst) ~= nil
end

-- only called when the state really changes, so anything listening (doors, droppers, gates) sees one clean change
local function setCatcher(m, on)
	if not m.Parent then return end
	m:SetAttribute("Activated", on)
	m:SetAttribute("LaserActive", on)
	m:SetAttribute("Pressed", on)
	if m.Name == "PeTIItem" then -- the editor's placeholder catcher
		local lens = m:FindFirstChild("Lens", true)
		if lens and lens:IsA("BasePart") then lens.Color = on and CATCHER_LENS_ON or CATCHER_LENS_OFF end
	end
end

-- the thing that counts as the reflective cube: the part itself, or the Model around it
-- (checked a few levels up, so cubes built from several parts / sub-models work)
local function reflectorRoot(inst)
	if not inst then return nil end
	local node = inst
	for _ = 1, 5 do
		if not node or node == workspace then break end
		if (node:IsA("Model") or node:IsA("BasePart"))
			and (CollectionService:HasTag(node, "LaserReflector")
				or CollectionService:HasTag(node, "ReflectionCube")
				or isReflectorName(node.Name)) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function isLaserReflector(inst)
	return reflectorRoot(inst) ~= nil
end

local function reflectorDirection(inst)
	local root = reflectorRoot(inst)
	if not root then return nil end
	if root:IsA("Model") then return -root:GetPivot().LookVector end
	return -root.CFrame.LookVector
end

local function traceLaser(origin, dir, up, exclude)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = exclude

	local links = Gel.getLinks(portalsFolder)
	local segs = {}
	local remaining = MAX_BEAM
	local currentOrigin = origin
	local currentDir = dir.Unit
	local currentUp = up
	local reflectorHops = 0

	-- the cube we just bounced off is ignored for the NEXT cast only (FilterDescendantsInstances
	-- hands back a copy, so it has to be set as a whole list)
	local skipOnce = nil
	local function cast(o, d, distance)
		if skipOnce then
			local f = table.clone(exclude)
			table.insert(f, skipOnce)
			params.FilterDescendantsInstances = f
			skipOnce = nil
		else
			params.FilterDescendantsInstances = exclude
		end
		return workspace:Raycast(o, d * distance, params)
	end

	for hop = 0, MAX_PORTAL_HOPS do
		if remaining <= 0 then break end

		local hit = cast(currentOrigin, currentDir, remaining)
		local endP = hit and hit.Position or (currentOrigin + currentDir * remaining)
		local probeEnd = endP + currentDir * 0.3
		local hitT = hit and ((hit.Position - currentOrigin).Magnitude / math.max((probeEnd - currentOrigin).Magnitude, 1e-6)) or math.huge

		local bestT, inP, outP
		for _, link in ipairs(links) do
			local p, exitP = link[1], link[2]
			local cf = p.CFrame
			local a, b = cf:PointToObjectSpace(currentOrigin), cf:PointToObjectSpace(probeEnd)
			local da, db = -a.Z, -b.Z
			if da > 0 and db <= 0 then
				local t = da / (da - db)
				local h = a:Lerp(b, t)
				local ex = h.X / (p.Size.X * 0.5)
				local ey = h.Y / (p.Size.Y * 0.5)
				if ex * ex + ey * ey <= 1 and (not bestT or t < bestT) then
					bestT, inP, outP = t, p, exitP
				end
			end
		end

		if hit and isLaserCatcher(hit.Instance) and (not bestT or hitT <= bestT + 1e-5) then
			local hitPoint = hit.Position
			table.insert(segs, { currentOrigin, hitPoint, currentUp })
			remaining -= (hitPoint - currentOrigin).Magnitude
			local catcher = catcherModel(hit.Instance)
			if catcher then litNow[catcher] = true end
			break
		end

		if hit and isLaserReflector(hit.Instance) and (not bestT or hitT <= bestT + 1e-5) then
			local hitPoint = hit.Position
			table.insert(segs, { currentOrigin, hitPoint, currentUp })
			local reflector = reflectorRoot(hit.Instance)
			local newDir = reflectorDirection(hit.Instance)
			if not newDir or reflectorHops >= MAX_PORTAL_HOPS then break end
			reflectorHops += 1
			remaining -= (hitPoint - currentOrigin).Magnitude
			currentOrigin = hitPoint + newDir.Unit * 0.05
			currentDir = newDir.Unit
			currentUp = math.abs(currentDir.Y) < 0.95 and Vector3.yAxis or Vector3.xAxis
			skipOnce = reflector
			continue
		end

		if bestT then
			local cross = currentOrigin:Lerp(probeEnd, bestT)
			table.insert(segs, { currentOrigin, cross, currentUp })
			remaining -= (cross - currentOrigin).Magnitude
			if remaining <= 0 then break end
			currentOrigin = Gel.xformCF(CFrame.new(cross), inP, outP).Position + outP.CFrame.LookVector * 0.05
			currentDir = Gel.xformDir(currentDir, inP, outP).Unit
			currentUp = Gel.xformDir(currentUp, inP, outP).Unit
		else
			table.insert(segs, { currentOrigin, endP, currentUp })
			break
		end
	end

	return segs
end

local function updateKit(el)
	local kit = el.kit
	local segs = (el.kind == "Laser")
		and traceLaser(kit.origin, kit.dir, kit.up, beamExclude(el))
		or trace(kit.origin, kit.dir, kit.up, beamExclude(el), nil, el.kind == "Bridge", BRIDGE_PORTAL_LOW)
	if sameSegs(el.lastSegs, segs) then return segs end
	el.lastSegs = segs

	local nearAtts, farAtts = {}, {}
	for i, p in ipairs(kit.pairs) do nearAtts[i], farAtts[i] = p.near, p.far end

	for k, seg in ipairs(segs) do
		local a, b, up = seg[1], seg[2], seg[3]
		local len = (b - a).Magnitude
		local dir = len > 1e-3 and (b - a) / len or kit.dir
		local upP = up - dir * up:Dot(dir)
		upP = upP.Magnitude > 1e-3 and upP.Unit or kit.up
		local frame = CFrame.lookAt(a, a + dir, upP)
		if k == 1 then
			placeSegment(kit, nearAtts, farAtts, kit.hit, frame, len, el.kind == "Laser")
		else
			local x = el.extra[k - 1]
			if not x then
				x = makeExtra(el)
				el.extra[k - 1] = x
			end
			x.used = true
			x.holder.Parent = cloneFolder
			placeSegment(kit, x.near, x.far, x.hit, frame, len)
		end
	end
	-- pieces past portals that aren't needed any more
	for i = #segs, #el.extra do
		local x = el.extra[i]
		if x then
			x.used = false
			x.holder.Parent = nil
		end
	end
	return segs
end

-- ==========================================
-- FALLBACK EMITTERS (no beams): attachment "1" (+ "2" to aim), drawn parts
-- ==========================================
local function fallbackRay(el)
	local a1 = el.model:FindFirstChild("1", true)
	local a2 = el.model:FindFirstChild("2", true)
	if not (a1 and a1:IsA("Attachment")) then return nil end
	local origin = a1.WorldPosition
	local dir = (a2 and a2:IsA("Attachment")) and (a2.WorldPosition - origin) or a1.WorldAxis
	if dir.Magnitude < 1e-3 then dir = a1.WorldAxis end
	return origin, dir.Unit, a1.WorldSecondaryAxis
end

local function drawFallback(el, segs)
	el.pool = el.pool or {}
	for i, seg in ipairs(segs) do
		local a, b, up = seg[1], seg[2], seg[3]
		local len = (b - a).Magnitude
		local p = el.pool[i]
		if not p then
			p = Instance.new("Part")
			p.Anchored = true
			p.CastShadow = false
			p.CanTouch = false
			if el.kind == "Bridge" then
				p.Material = Enum.Material.ForceField
				p.Color = Color3.fromRGB(110, 195, 255)
				p.CanCollide = true
			else
				p.Shape = Enum.PartType.Cylinder
				p.Material = Enum.Material.Neon
				p.Color = LASER_COLOR
				p.CanCollide = false
				p.CanQuery = false
			end
			el.pool[i] = p
		end
		p.Parent = cloneFolder
		if len > 0.01 then
			local mid, dir = (a + b) / 2, (b - a).Unit
			if el.kind == "Bridge" then
				local upP = up - dir * up:Dot(dir)
				upP = upP.Magnitude > 1e-3 and upP.Unit or Vector3.yAxis
				p.Size = Vector3.new(64 / 14.7, 0.2, len)
				p.CFrame = CFrame.lookAt(mid - upP * 0.1, b - upP * 0.1, upP)
			else
				p.Size = Vector3.new(len, LASER_THICKNESS, LASER_THICKNESS)
				p.CFrame = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
			end
		end
	end
	for i = #segs + 1, #el.pool do el.pool[i].Parent = nil end
end

-- ==========================================
-- EXCURSION FUNNEL
-- ==========================================
local function funnelRay(el)
	local a, b = el.middle.WorldPosition, el.shootOut.WorldPosition
	local dir = b - a
	if dir.Magnitude < 1e-3 then return nil end
	dir = dir.Unit
	local up = dir:Cross(math.abs(dir.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis):Cross(dir).Unit
	return a, dir, up
end

local function drawFunnel(el, segs)
	local m = el.model
	local reversed = m:GetAttribute("Reversed") == true
	local speed = m:GetAttribute("Speed") or FUNNEL_SPEED
	local radius = m:GetAttribute("Radius") or FUNNEL_RADIUS
	local color = reversed and FUNNEL_ORANGE or FUNNEL_BLUE
	el.pool = el.pool or {}
	for i, seg in ipairs(segs) do
		local a, b = seg[1], seg[2]
		local len = math.max((b - a).Magnitude, 0.05)
		local p = el.pool[i]
		if not p then
			p = Instance.new("Part")
			p.Name = "FunnelSegment"
			p.Shape = Enum.PartType.Cylinder
			p.Material = Enum.Material.ForceField
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			local pe = Instance.new("ParticleEmitter") -- the glowing specks flowing along it
			pe.Name = "Flow"
			pe.Shape = Enum.ParticleEmitterShape.Box
			pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			pe.LightEmission = 1
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.32), NumberSequenceKeypoint.new(1, 0) })
			pe.Transparency = NumberSequence.new(0.1)
			pe.SpreadAngle = Vector2.new(6, 6)
			pe.Parent = p
			el.pool[i] = p
		end
		p.Transparency = 1 -- no tube: the look is the client's strands + these dots
		p.Size = Vector3.new(len, radius * 2, radius * 2)
		p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0) -- X = along the funnel
		p.Color = color
		p:SetAttribute("Speed", speed)
		p:SetAttribute("Reversed", reversed)
		p:SetAttribute("Last", i == #segs)
		p:SetAttribute("First", i == 1)
		local pe = p.Flow
		pe.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.15))
		pe.EmissionDirection = reversed and Enum.NormalId.Left or Enum.NormalId.Right
		pe.Speed = NumberRange.new(speed * 0.9, speed * 1.1)
		pe.Lifetime = NumberRange.new(math.min(len / speed, 6))
		pe.Rate = math.clamp(len * 8, 20, 300)
		if FUNNEL_SPECK_TEXTURE ~= "" then pe.Texture = FUNNEL_SPECK_TEXTURE end
		p.Parent = cloneFolder
	end
	for i = #segs + 1, #el.pool do el.pool[i].Parent = nil end
end

-- loose objects in the funnel ride along it (players: TestElementsClient)
local function funnelPush(el, segs)
	local m = el.model
	local reversed = m:GetAttribute("Reversed") == true
	local speed = m:GetAttribute("Speed") or FUNNEL_SPEED
	local radius = m:GetAttribute("Radius") or FUNNEL_RADIUS
	local flow = reversed and -1 or 1
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { cloneFolder, el.model, portalsFolder }
	local seen = {}
	for i, seg in ipairs(segs) do
		local a, b = seg[1], seg[2]
		local len = (b - a).Magnitude
		if len > 0.05 then
			local dir = (b - a) / len
			local cf = CFrame.lookAt((a + b) / 2, b)
			for _, part in ipairs(workspace:GetPartBoundsInBox(cf, Vector3.new(radius * 2, radius * 2, len), params)) do
				local root = part.AssemblyRootPart
				if root and not seen[root] and not root.Anchored and not root:GetAttribute("HeldBy")
					and not root:GetAttribute("Fizzling") and not characterOf(root) then
					seen[root] = true
					local lp = cf:PointToObjectSpace(root.Position)
					local radial = Vector3.new(lp.X, lp.Y, 0)
					if radial.Magnitude <= radius then
						local along = -lp.Z + len / 2 -- distance from this piece's start
						local v = speed * flow
						if flow > 0 and i == #segs and len - along < 2 then v = 0 end
						if flow < 0 and i == 1 and along < 2 then v = 0 end
						if root:CanSetNetworkOwnership() then root:SetNetworkOwner(nil) end
						local centerVelocity = cf:VectorToWorldSpace(-radial) * (FUNNEL_PULL * 2.2)
						root.AssemblyLinearVelocity = dir * v + centerVelocity
						root.AssemblyAngularVelocity *= 0.88
					end
				end
			end
		end
	end
end

-- ==========================================
-- LASER: hurts + pushes on touch
-- ==========================================
local function closestOnSegment(p, a, b)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return a + ab * t
end

local lastLaserDamage = {} -- [player] = time of their last burn
local pushed = {}          -- [HumanoidRootPart] = { att, lv, t }
Players.PlayerRemoving:Connect(function(plr) lastLaserDamage[plr] = nil end)

-- shoves the character along the ground, away from the beam. A LinearVelocity is used (not
-- setting velocity) because the player's own client simulates their character and honours it.
local function pushPlayer(root, dir, now)
	local st = pushed[root]
	if not st or not st.lv.Parent then
		local att = Instance.new("Attachment")
		att.Name = "LaserPushAttachment"
		att.Parent = root
		local lv = Instance.new("LinearVelocity")
		lv.Name = "LaserPush"
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane -- ground plane only: gravity/jumping untouched
		lv.PrimaryTangentAxis = Vector3.xAxis
		lv.SecondaryTangentAxis = Vector3.zAxis
		lv.ForceLimitMode = Enum.ForceLimitMode.Magnitude
		lv.MaxForce = math.max(root.AssemblyMass, 1) * LASER_PUSH_FORCE
		lv.Parent = root
		st = { att = att, lv = lv }
		pushed[root] = st
	end
	st.lv.PlaneVelocity = Vector2.new(dir.X, dir.Z) * LASER_PUSH_SPEED
	st.t = now
end

local function releasePushes(now)
	for root, st in pairs(pushed) do
		if not root.Parent or not st.lv.Parent then
			pushed[root] = nil
		elseif now - st.t > LASER_PUSH_LINGER then
			st.lv:Destroy()
			st.att:Destroy()
			pushed[root] = nil
		end
	end
end

-- touching the beam (any of its pieces, so also past portals): a little damage + a shove back
local function laserHurt(segs, now)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 then
			local bestD, bestPoint, bestSeg = math.huge, nil, nil
			for _, part in ipairs(char:GetChildren()) do
				if part:IsA("BasePart") then
					for _, seg in ipairs(segs) do
						local c = closestOnSegment(part.Position, seg[1], seg[2])
						local d = (part.Position - c).Magnitude
						if d < bestD then bestD, bestPoint, bestSeg = d, c, seg end
					end
				end
			end
			if bestSeg and bestD < LASER_HIT_RADIUS then
				if now - (lastLaserDamage[plr] or 0) >= LASER_DAMAGE_INTERVAL then
					lastLaserDamage[plr] = now
					hum:TakeDamage(LASER_DAMAGE)
				end
				if LASER_PUSH_SPEED > 0 then
					-- straight away from the beam, along the ground
					local away = root.Position - bestPoint
					away = Vector3.new(away.X, 0, away.Z)
					if away.Magnitude < 0.25 then
						-- standing right in the beam's line: out sideways, against where they walk
						local d = (bestSeg[2] - bestSeg[1])
						local side = d.Magnitude > 1e-3 and d.Unit:Cross(Vector3.yAxis) or Vector3.zero
						if side.Magnitude < 0.1 then side = -root.CFrame.LookVector end
						side = Vector3.new(side.X, 0, side.Z)
						side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
						if hum.MoveDirection:Dot(side) > 0 then side = -side end
						away = side
					end
					pushPlayer(root, away.Unit, now)
				end
			end
		end
	end
end

-- ==========================================
-- FIZZLER
-- ==========================================
local fizzling = {}
local lastPortalFizzle = {}

-- black, floating, fading - then gone
local function fizzleObject(root)
	if fizzling[root] or root:GetAttribute("Fizzling") then return end
	local parts = root.Anchored and { root } or root:GetConnectedParts(true)
	if not table.find(parts, root) then table.insert(parts, root) end
	for _, p in ipairs(parts) do
		fizzling[p] = true
		p:SetAttribute("Fizzling", true)
	end

	-- remove the whole model if it's only this object, otherwise just these parts
	local model = root:FindFirstAncestorOfClass("Model")
	local target
	if model and model.Parent then
		local all = true
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and not table.find(parts, d) then all = false break end
		end
		if all then target = model end
	end

	local start, center = {}, Vector3.zero
	for _, p in ipairs(parts) do
		p.Anchored = true -- also makes PortalServer let go if someone was holding it
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Color = Color3.fromRGB(12, 12, 14)
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0
		if p:IsA("MeshPart") then p.TextureID = "" end
		for _, d in ipairs(p:GetDescendants()) do
			if d:IsA("SurfaceAppearance") then
				d:Destroy()
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = 1
			end
		end
		start[p] = { cf = p.CFrame, t = p.Transparency }
		center += p.Position
	end
	center /= #parts

	local pe = Instance.new("ParticleEmitter") -- default texture = sparkles
	pe.Color = ColorSequence.new(Color3.fromRGB(150, 210, 255))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.4, 0.9)
	pe.Speed = NumberRange.new(0.5, 2.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 70
	pe.Parent = root

	local spinAxis = Vector3.new(math.random() - 0.5, 1, math.random() - 0.5).Unit
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / FIZZLE_TIME
			if a >= 1 then break end
			local eased = 1 - (1 - a) ^ 2
			local lift = CFrame.new(0, FIZZLE_RISE * eased, 0)
			local spin = CFrame.new(center) * CFrame.fromAxisAngle(spinAxis, 0.6 * eased) * CFrame.new(-center)
			local fade = math.clamp((a - 0.55) / 0.45, 0, 1)
			for _, p in ipairs(parts) do
				if p.Parent then
					p.CFrame = lift * spin * start[p].cf
					p.Transparency = start[p].t + (1 - start[p].t) * fade
				end
			end
			RunService.Heartbeat:Wait()
		end
		pe.Enabled = false
		if target then
			target:Destroy()
		else
			for _, p in ipairs(parts) do p:Destroy() end
		end
		for _, p in ipairs(parts) do fizzling[p] = nil end
	end)
end

-- a post's anchor point + its "up" + its length
local function postPoint(c)
	if c:IsA("Attachment") then return c.WorldPosition, c.WorldSecondaryAxis, nil end
	if not c:IsA("BasePart") then return nil end
	local a = c:FindFirstChild("Attachment")
	local pos = (a and a:IsA("Attachment")) and a.WorldPosition or c.Position
	local s, cf = c.Size, c.CFrame
	local up, len = cf.UpVector, s.Y
	if s.X > len then up, len = cf.RightVector, s.X end
	if s.Z > len then up, len = cf.LookVector, s.Z end
	if up.Y < 0 then up = -up end
	return pos, up, len
end

local function fieldPanels(el)
	local m = el.model
	local posts = {}
	for i = 1, 10 do
		local c = m:FindFirstChild(tostring(i))
		if not c then break end
		table.insert(posts, c)
	end
	local fieldBeam = m:FindFirstChild("Field")
	local beamHeight = fieldBeam and fieldBeam:IsA("Beam") and math.max(fieldBeam.Width0, fieldBeam.Width1) or nil

	local panels = {}
	for i = 1, #posts - 1 do
		local a, upA, lenA = postPoint(posts[i])
		local b = postPoint(posts[i + 1])
		if a and b and (b - a).Magnitude > 0.05 then
			local wd = (b - a).Unit
			local hd = upA - wd * upA:Dot(wd)
			hd = hd.Magnitude > 1e-3 and hd.Unit or Vector3.yAxis
			local height = beamHeight or lenA or (128 / 14.7)
			table.insert(panels, {
				cf = CFrame.fromMatrix((a + b) / 2, wd, hd),
				size = Vector3.new((b - a).Magnitude, height, FIELD_DEPTH),
			})
		end
	end
	return panels
end

local function fizzlerCheck(el, panels, now)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { cloneFolder, el.model, portalsFolder }
	for _, pn in ipairs(panels) do
		for _, part in ipairs(workspace:GetPartBoundsInBox(pn.cf, pn.size, params)) do
			local char = characterOf(part)
			local plr = char and Players:GetPlayerFromCharacter(char)
			if plr then
				if now - (lastPortalFizzle[plr] or 0) > PORTAL_FIZZLE_DEBOUNCE then
					lastPortalFizzle[plr] = now
					fizzlePortals:Fire(plr) -- PortalServer removes their portals
				end
			elseif not char and not fizzling[part] and not part:IsA("Terrain") then
				local root = part.AssemblyRootPart or part
				if not root.Anchored or part:GetAttribute("Grabbable") or root:GetAttribute("Grabbable") then
					fizzleObject(root)
				end
			end
		end
	end
end

-- ==========================================
-- LASER FIELD: kills anyone who walks into it (objects pass)
-- ==========================================
local function laserFieldPanels(el)
	local panels = fieldPanels(el) -- posts "1", "2", ... like a fizzler
	if #panels > 0 then return panels end
	-- no posts: the model's flat side (its thinnest dimension is "through" the field)
	local cf, size = el.model:GetBoundingBox()
	local axes = {
		{ v = cf.RightVector, s = size.X },
		{ v = cf.UpVector, s = size.Y },
		{ v = cf.LookVector, s = size.Z },
	}
	table.sort(axes, function(a, b) return a.s < b.s end)
	return { {
		cf = CFrame.fromMatrix(cf.Position, axes[3].v, axes[2].v),
		size = Vector3.new(axes[3].s, axes[2].s, math.max(axes[1].s, FIELD_DEPTH)),
	} }
end

local function laserFieldCheck(el)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { cloneFolder, el.model, portalsFolder }
	for _, pn in ipairs(el.panels) do
		for _, part in ipairs(workspace:GetPartBoundsInBox(pn.cf, pn.size, params)) do
			local char = characterOf(part)
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum.Health = 0
			end
		end
	end
end

-- ==========================================
-- CUBE DROPPER
-- ==========================================
local droppers = {} -- [model] = dropper state

-- every sound matching the first fragment that has any (so _01 / _02 variants play at random)
local function findSoundBy(fragments)
	if not soundsFolder then
		warn("[CubeDropper] CubeDropper folder not found under PortalAssets – iris sounds will be silent")
		return nil
	end
	for _, frag in ipairs(fragments) do
		local list = {}
		for _, s in ipairs(soundsFolder:GetDescendants()) do
			if s:IsA("Sound") and string.find(string.lower(s.Name), frag, 1, true) then
				table.insert(list, s)
			end
		end
		if #list > 0 then
			print(("[CubeDropper] found %d sound(s) matching '%s'"):format(#list, frag))
			return list
		end
	end
	warn("[CubeDropper] no sounds matched any of:", table.concat(fragments, ", "))
	return nil
end

local dropperOpenSound = findSoundBy(DROPPER_OPEN_SOUNDS)
local dropperCloseSound = findSoundBy(DROPPER_CLOSE_SOUNDS)

if ISOLATE_DROPPER_SOUNDS then
	local store = ServerStorage:FindFirstChild("DropperSounds")
	if not store then
		store = Instance.new("Folder")
		store.Name = "DropperSounds"
		store.Parent = ServerStorage
	end
	for _, list in ipairs({ dropperOpenSound or {}, dropperCloseSound or {} }) do
		for _, s in ipairs(list) do
			s.Parent = store
		end
	end
end

local function playSoundAt(src, parent)
	if not src or not parent then return end
	if type(src) == "table" then
		src = src[math.random(#src)]
	end
	local s = src:Clone()
	s.Looped = false
	s.Parent = parent
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(10, function() if s.Parent then s:Destroy() end end)
end

local function findBoneNamed(m, name)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Bone") and d.Name == name then return d end
	end
	return nil
end

local function cubeKind(t)
	t = string.lower(tostring(t or "normal")):gsub("[^%a]", "")
	if t:find("companion") then return "Companion" end
	if t:find("edgeless") or t:find("ball") or t:find("sphere") then return "Edgeless" end
	if t:find("reflect") or t:find("laser") or t:find("redirect") or t:find("refraction") then return "Reflection" end
	return "Normal"
end

local function cubeTemplate(kind)
	for _, folder in ipairs({ portalAssets:FindFirstChild("Cubes"), ServerStorage:FindFirstChild("Cubes") }) do
		if folder then
			for _, c in ipairs(folder:GetChildren()) do
				if cubeKind(c.Name) == kind and (c:IsA("Model") or c:IsA("BasePart")) then return c end
			end
		end
	end
	return nil
end

local function placeholderCube(kind)
	local model = Instance.new("Model")
	local p = Instance.new("Part")
	p.Name = "Cube"
	p.Size = Vector3.one * CUBE_SIZE
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(205, 208, 212)
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	if kind == "Companion" then
		p.Color = Color3.fromRGB(235, 180, 200)
		model.Name = "CompanionCube"
	elseif kind == "Edgeless" then
		p.Shape = Enum.PartType.Ball
		model.Name = "EdgelessSafetyCube"
	elseif kind == "Reflection" then
		model.Name = "ReflectionCube" -- the laser code above looks for this name
		local lens = Instance.new("Part")
		lens.Name = "Lens"
		lens.Shape = Enum.PartType.Cylinder
		lens.Material = Enum.Material.Neon
		lens.Color = Color3.fromRGB(255, 70, 60)
		lens.Size = Vector3.new(0.2, CUBE_SIZE * 0.55, CUBE_SIZE * 0.55)
		lens.CFrame = p.CFrame * CFrame.new(0, 0, -CUBE_SIZE / 2) * CFrame.Angles(0, math.rad(90), 0)
		lens.CanCollide = false
		lens.Massless = true
		lens.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = p, lens
		w.Parent = lens
	else
		model.Name = "WeightedStorageCube"
	end
	model.PrimaryPart = p
	return model
end

local function makeCube(kind)
	local t = cubeTemplate(kind)
	local cube = t and t:Clone() or placeholderCube(kind)
	if cube:IsA("BasePart") then
		local m = Instance.new("Model")
		m.Name = cube.Name
		cube.Parent = m
		m.PrimaryPart = cube
		cube = m
	end
	if not cube.PrimaryPart then cube.PrimaryPart = cube:FindFirstChildWhichIsA("BasePart", true) end
	if kind == "Reflection" and not isReflectorName(cube.Name) then
		cube.Name = "ReflectionCube"
	end
	for _, d in ipairs(cube:GetDescendants()) do
		if d:IsA("BasePart") then d:SetAttribute("Grabbable", true) end
	end
	cube:SetAttribute("CubeType", kind)
	return cube
end

-- where a dropper's cubes live: the map the dropper is part of, so clearing / rebuilding the map takes the cubes
-- with it. Maps live in workspace.PortalInstances.Slot_<n> (one per player / co-op pair), older setups in
-- workspace.ActiveMap. Droppers placed straight in workspace drop into workspace.
local function cubeHome(m)
	local function under(root)
		if not (root and m:IsDescendantOf(root)) then return nil end
		local node = m
		while node.Parent and node.Parent ~= root do node = node.Parent end
		return node
	end
	local slot = under(workspace:FindFirstChild("PortalInstances")) -- the Slot_<n> folder
	if slot then
		-- the map inside the slot (the slot folder itself is kept; its children are what gets cleared)
		local node = m
		while node.Parent and node.Parent ~= slot do node = node.Parent end
		return node ~= m and node or slot
	end
	return under(workspace:FindFirstChild("ActiveMap")) or workspace
end

local function setCubeCollide(cube, on)
	for _, d in ipairs(cube:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide = on and d.Name ~= "Lens" end
	end
end

-- frozen = waiting in the tube (anchored, no collision); unfrozen = real physics
local function setCubePhysics(cube, frozen)
	for _, d in ipairs(cube:GetDescendants()) do
		if d:IsA("BasePart") then
			if d == cube.PrimaryPart or not d:FindFirstChildWhichIsA("WeldConstraint") then
				d.Anchored = frozen
			end
			d.CanCollide = not frozen and d.Name ~= "Lens"
		end
	end
end

local function setIris(st, open)
	for _, leaf in ipairs(st.leaves) do
		local goal = open and (leaf.rest * CFrame.fromAxisAngle(leaf.axis, math.rad(IRIS_OPEN_ANGLE))) or leaf.rest
		TweenService:Create(leaf.bone, TweenInfo.new(IRIS_OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = goal }):Play()
	end

	-- MUST be a BasePart for proper 3D sound
	local soundParent = st.mesh
		or st.model.PrimaryPart
		or st.model:FindFirstChildWhichIsA("BasePart", true)

	if soundParent then
		playSoundAt(open and dropperOpenSound or dropperCloseSound, soundParent)
	end
end

local dropCube -- forward

local function respawnLater(m, st, delay)
	if m:GetAttribute("RespawnOnDestroy") == false then return end
	task.delay(delay, function()
		if m.Parent and not st.cube and not st.busy then dropCube(m) end
	end)
end

local function watchCube(m, st, cube)
	cube.AncestryChanged:Connect(function()
		if cube:IsDescendantOf(workspace) then return end
		if st.cube == cube then st.cube = nil end
		-- destroyed / fizzled / fell out of the world: a new one, if wanted
		if not st.replacing and m.Parent then respawnLater(m, st, RESPAWN_DELAY) end
	end)
	-- a fizzler grabbed it: count it as gone right away (it takes FIZZLE_TIME to vanish)
	local root = cube.PrimaryPart
	if root then
		root:GetAttributeChangedSignal("Fizzling"):Connect(function()
			if root:GetAttribute("Fizzling") and st.cube == cube and not st.replacing then
				st.cube = nil
				respawnLater(m, st, RESPAWN_DELAY + FIZZLE_TIME)
			end
		end)
	end
end

dropCube = function(m)
	local st = droppers[m]
	if not st or st.busy or m:GetAttribute("Enabled") == false or not m:IsDescendantOf(workspace) then return end
	st.busy = true

	-- the old cube fizzles (Portal 2: the dropper's button replaces it) - same fizzle as the fizzlers
	if st.cube and st.cube.Parent then
		st.replacing = true
		local root = st.cube.PrimaryPart or st.cube:FindFirstChildWhichIsA("BasePart", true)
		if root then fizzleObject(root) else st.cube:Destroy() end
		st.cube = nil
		task.delay(FIZZLE_TIME + 0.2, function() st.replacing = false end)
	end

	local kind = cubeKind(m:GetAttribute("CubeType"))
	local cube = makeCube(kind)
	cube:PivotTo(CFrame.new(st.spawn.WorldPosition) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	setCubePhysics(cube, true) -- waits inside the glass tube
	cube.Parent = cubeHome(m)
	st.cube = cube
	watchCube(m, st, cube)

	task.spawn(function()
		local dropTime = m:GetAttribute("DropTime") or DROP_TIME
		task.wait(math.max(dropTime - IRIS_OPEN_TIME, 0))
		if not cube.Parent then st.busy = false return end
		setIris(st, true)
		task.wait(IRIS_OPEN_TIME)
		if cube.Parent then
			setCubePhysics(cube, false)
			-- no collision for the first moment out of the dropper
			setCubeCollide(cube, false)
			task.delay(DROP_NOCOLLIDE_TIME, function()
				if cube.Parent then setCubeCollide(cube, true) end
			end)
			local root = cube.PrimaryPart
			if root then
				root.AssemblyLinearVelocity = -st.up * 4
				if root:CanSetNetworkOwnership() then root:SetNetworkOwner(nil) end
			end
		end
		task.wait(IRIS_CLOSE_DELAY)
		setIris(st, false)
		st.busy = false
	end)
end

local function setupDropper(m)
	if droppers[m] or not m:IsA("Model") then return end
	if not (CollectionService:HasTag(m, "CubeDropper") or string.lower(m.Name):find("dropper")) then return end
	local spawn = findBoneNamed(m, "Spawn")
	local leaves = {}
	for i = 1, 9 do
		local b = findBoneNamed(m, "Leaf" .. i)
		if b then table.insert(leaves, b) end
	end
	if not spawn or #leaves == 0 then
		-- bones can replicate a moment after the model
		task.delay(1, function() if not droppers[m] and m.Parent then setupDropper(m) end end)
		return
	end

	local mesh = spawn:FindFirstAncestorWhichIsA("MeshPart")
	local up = mesh and mesh.CFrame.UpVector or Vector3.yAxis
	local st = { model = m, spawn = spawn, mesh = mesh, up = up, leaves = {}, busy = false }
	for _, b in ipairs(leaves) do
		table.insert(st.leaves, { bone = b, rest = b.CFrame, axis = b.WorldCFrame:VectorToObjectSpace(up) })
	end
	droppers[m] = st

	-- glass tube: you see the cube waiting inside (Portal 2)
	if TUBE_GLASS then
		local tube = m:FindFirstChild("Tube", true)
		if tube and tube:IsA("BasePart") then
			tube.Material = Enum.Material.Glass
			tube.Transparency = 0.55
			tube.Color = Color3.fromRGB(190, 225, 240)
			tube.CanCollide = false
		end
	end

	-- triggers: the Drop attribute (the editor's connections use this), and a linked button
	m:GetAttributeChangedSignal("Drop"):Connect(function()
		if m:GetAttribute("Drop") then
			m:SetAttribute("Drop", false)
			dropCube(m)
		end
	end)
	-- floor buttons set "Pressed", pedestals set "PressesButton" (and "Pressed"):
	-- listen for whichever it has, on the object the ObjectValue points at AND on
	-- the model around it (a pedestal's model and its MeshPart share a name, so
	-- it's easy to pick the wrong one). Turning ON = drop.
	st.buttonConns = {}
	local function link()
		for _, c in ipairs(st.buttonConns) do c:Disconnect() end
		table.clear(st.buttonConns)
		local bv = m:FindFirstChild("Button")
		if not (bv and bv:IsA("ObjectValue")) then return end
		local target = bv.Value
		if not target then
			warn("[CubeDropper] " .. m:GetFullName() .. ": its Button ObjectValue is empty")
			return
		end
		local watch = { target }
		local model = target:FindFirstAncestorOfClass("Model")
		if model and model ~= workspace then table.insert(watch, model) end
		for _, obj in ipairs(watch) do
			for _, attr in ipairs(BUTTON_ATTRIBUTES) do
				table.insert(st.buttonConns, obj:GetAttributeChangedSignal(attr):Connect(function()
					if obj:GetAttribute(attr) == true then
						print(("[CubeDropper] %s: %s.%s = true -> dropping"):format(m.Name, obj.Name, attr))
						dropCube(m)
					end
				end))
			end
		end
		print(("[CubeDropper] %s linked to %s"):format(m:GetFullName(), target:GetFullName()))
	end
	link()
	-- Button ObjectValue added / changed later: re-link
	m.ChildAdded:Connect(function(c)
		if c.Name == "Button" and c:IsA("ObjectValue") then
			c.Changed:Connect(link)
			link()
		end
	end)
	local bv0 = m:FindFirstChild("Button")
	if bv0 and bv0:IsA("ObjectValue") then bv0.Changed:Connect(link) end

	print(("[CubeDropper] ready: %s  (%s cube, iris %d leaves)"):format(m:GetFullName(),
		cubeKind(m:GetAttribute("CubeType")), #st.leaves))
	if m:GetAttribute("Drop") then
		-- something asked for a drop before the bones had loaded
		m:SetAttribute("Drop", false)
		task.delay(0.5, dropCube, m)
	elseif m:GetAttribute("DropOnStart") ~= false then
		task.delay(0.5, dropCube, m)
	end
end

-- PortalServer asks: is there a fizzler between the player and where they shot?
-- Returns  true, hitPoint, normal  for the NEAREST enabled fizzler field the shot
-- would cross (so the bad-surface effect appears on the fizzler), or  false.
shotCheck.OnInvoke = function(from, to)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then return false end
	local bestT, bestPoint, bestNormal
	for _, el in pairs(elements) do
		if el.kind == "Fizzler" and enabled(el) then
			for _, pn in ipairs(fieldPanels(el)) do
				local a, b = pn.cf:PointToObjectSpace(from), pn.cf:PointToObjectSpace(to)
				if (a.Z > 0) ~= (b.Z > 0) then
					local t = a.Z / (a.Z - b.Z)
					local h = a:Lerp(b, t)
					if math.abs(h.X) <= pn.size.X / 2 and math.abs(h.Y) <= pn.size.Y / 2
						and (not bestT or t < bestT) then
						bestT = t
						bestPoint = pn.cf:PointToWorldSpace(Vector3.new(h.X, h.Y, 0))
						local n = pn.cf.LookVector
						if (from - bestPoint):Dot(n) < 0 then n = -n end -- face the shooter
						bestNormal = n
					end
				end
			end
		end
	end
	if bestT then return true, bestPoint, bestNormal end
	return false
end
portalAssets:SetAttribute("FizzlersReady", true)

-- ==========================================
-- REGISTRY + MAIN LOOP
-- ==========================================
local funnelRetries = {}
local function register(m)
	if elements[m] or not m:IsA("Model") or m:IsDescendantOf(cloneFolder) then return end
	local kind = kindOf(m)
	if not kind then return end
	local el = { model = m, kind = kind, on = true }
	if kind == "Bridge" and hasEndPiece(m) then
		-- fixed: never touch its attachments; just remember the hitbox for on/off
		el.fixed = true
		local hit = m:FindFirstChild("HitBox")
		if hit and hit:IsA("BasePart") then
			el.kit = { hit = hit, hitCollide = hit.CanCollide }
			tintHitbox(hit)
		end
	elseif kind == "Funnel" then
		el.middle = findAttachment(m, "Middle")
		el.shootOut = findAttachment(m, "ShootOut", "Shoot out")
		if not (el.middle and el.shootOut) then
			-- bones can replicate a moment after the model: try again shortly
			if (funnelRetries[m] or 0) < 10 then
				funnelRetries[m] = (funnelRetries[m] or 0) + 1
				task.delay(1, register, m)
			end
			return
		end
	elseif kind == "LaserCatcher" then
		el.fixed = true
		setCatcher(m, false)
	elseif kind == "LaserReflector" then
		el.fixed = true
	elseif kind == "LaserField" then
		el.panels = laserFieldPanels(el)
		if #el.panels == 0 then return end
		local sz = el.panels[1].size
		print(("[LaserField] ready: %s  (%d panel(s), %.1f x %.1f studs)%s"):format(m:GetFullName(), #el.panels,
			sz.X, sz.Y, m:GetAttribute("Enabled") == false and "  - Enabled is FALSE, so it starts OFF" or ""))
	elseif kind ~= "Fizzler" then
		if not buildKit(el) and not fallbackRay(el) then
			if kind == "Laser" and (funnelRetries[m] or 0) < 10 then
				funnelRetries[m] = (funnelRetries[m] or 0) + 1
				task.delay(1, register, m)
			end
			return
		end
	elseif #fieldPanels(el) == 0 then
		return
	end
	elements[m] = el
end

local function scan(d)
	if d:IsA("Model") then
		task.defer(register, d)
		task.defer(setupDropper, d)
	end
end
for _, d in ipairs(workspace:GetDescendants()) do scan(d) end
workspace.DescendantAdded:Connect(scan)
for _, tag in ipairs({ "LightBridge", "LaserEmitter", "LaserField", "LaserCatcher", "LaserReflector", "ReflectionCube", "Fizzler", "Funnel" }) do
	for _, m in ipairs(CollectionService:GetTagged(tag)) do register(m) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(register)
end
for _, m in ipairs(CollectionService:GetTagged("CubeDropper")) do setupDropper(m) end
CollectionService:GetInstanceAddedSignal("CubeDropper"):Connect(setupDropper)

-- one element's per-frame update (wrapped in pcall below so one error can't stop the rest)
local function updateElement(m, el, now)
	if not m:IsDescendantOf(workspace) then
		for _, x in ipairs(el.extra or {}) do x.holder:Destroy() end
		for _, p in ipairs(el.pool or {}) do p:Destroy() end
		elements[m] = nil
		return
	end
	local on = enabled(el)
	if on ~= el.on then
		el.on = on
		setVisible(el, on)
		if on then el.lastSegs = nil end -- switched back on (button / chip / "auto off"): redraw it from scratch
	end
	if not on then
		return
	end

	if el.fixed then
		-- fixed bridge / catcher / reflector: nothing to update
	elseif el.kind == "Funnel" then
		local origin, dir, up = funnelRay(el)
		if origin then
			local segs = trace(origin, dir, up, beamExclude(el), nil, true, 0)
			local rev = m:GetAttribute("Reversed") == true
			if not sameSegs(el.lastSegs, segs) or rev ~= el.lastRev
				or (m:GetAttribute("Speed") or FUNNEL_SPEED) ~= el.lastSpeed then
				el.lastSegs, el.lastRev, el.lastSpeed = segs, rev, (m:GetAttribute("Speed") or FUNNEL_SPEED)
				drawFunnel(el, segs)
			end
			funnelPush(el, segs)
		end
	elseif el.kind == "Fizzler" then
		fizzlerCheck(el, fieldPanels(el), now)
	elseif el.kind == "LaserField" then
		if el.model:GetPivot() ~= el.lastPivot then -- moved in Studio / by a script
			el.lastPivot = el.model:GetPivot()
			el.panels = laserFieldPanels(el)
		end
		laserFieldCheck(el)
	else
		local segs
		if el.kit then
			segs = updateKit(el)
		else
			local origin, dir, up = fallbackRay(el)
			segs = (el.kind == "Laser")
				and traceLaser(origin, dir, up, beamExclude(el))
				or trace(origin, dir, up, beamExclude(el), nil, el.kind == "Bridge", BRIDGE_PORTAL_LOW)
			drawFallback(el, segs)
		end
		if el.kind == "Laser" then laserHurt(segs, now) end
	end
end

local updateErrors = {}
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	table.clear(litNow)
	for m, el in pairs(elements) do
		local ok, err = pcall(updateElement, m, el, now)
		if not ok and updateErrors[m] ~= err then
			updateErrors[m] = err -- print each different error once, not every frame
			warn(("[TestElements] %s (%s): %s"):format(m:GetFullName(), tostring(el.kind), tostring(err)))
		end
	end
	-- laser catchers: only change when a laser starts / stops hitting them
	for m in pairs(litNow) do
		if not litLast[m] then setCatcher(m, true) end
	end
	for m in pairs(litLast) do
		if not litNow[m] then setCatcher(m, false) end
	end
	litLast = table.clone(litNow)
	releasePushes(now)
	-- droppers that were deleted
	for m in pairs(droppers) do
		if not m:IsDescendantOf(workspace) then droppers[m] = nil end
	end
end)
