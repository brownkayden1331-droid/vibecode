-- ChamberPiecesClient
-- StarterPlayerScripts (LocalScript)
-- The looks of the moving chamber pieces (ChamberPiecesServer moves the parts that matter):
--   Arm Panel / Arm Panel 2 (Panel_Interior / Panel_Interior2): the arm's bone chain bends to follow the PanelTile.
--     The deepest bone (arm_192_tip / 5) goes wherever the panel goes, the bones above it take a share of the move
--     (more the closer they are to the panel), so the arm unfolds out of the socket.
--   Crusher (a "Crusher" model from PortalAssets): plays its own animations if it has them - Animation objects named
--     Holdcrush, CRUSH and Crushback anywhere inside the model (or in PortalAssets.Animations.Crusher). Without them
--     the model just follows the CrushPlate.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("PortalConfig"))

local arms = {}     -- [model] = { tile, restTile, chain = { { bone, rest } } }
local crushers = {} -- [model] = { plate, restPlate, visual, restVisual, tracks }

local function squash(s) return (string.lower(s):gsub("[^%w]", "")) end

local function visualOf(m)
	-- the model from PortalAssets inside the item (not the item's own parts)
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("Model") then return c end
	end
	return nil
end

local function setupArm(m)
	local tile = m:WaitForChild("PanelTile", 5)
	local visual = visualOf(m)
	if not tile or not visual then return end
	local chain = Config.BoneChain(visual)
	if not chain then return end
	local entry = { tile = tile, restTile = tile.CFrame, chain = {} }
	for i, b in ipairs(chain) do
		-- share of the panel's move: 0 at the top bone, 1 at the panel end
		local share = (#chain > 1) and ((i - 1) / (#chain - 1)) or 1
		table.insert(entry.chain, { bone = b, rest = b.WorldCFrame, share = share * share * (3 - 2 * share) })
	end
	arms[m] = entry
end

local function findAnims(m)
	local found = {}
	local function scan(root)
		if not root then return end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Animation") then
				local k = squash(d.Name)
				if k == "holdcrush" or k == "crush" or k == "crushback" then found[k] = found[k] or d end
			end
		end
	end
	scan(m)
	local assets = ReplicatedStorage:FindFirstChild("PortalAssets")
	local anims = assets and assets:FindFirstChild("Animations")
	scan(anims and anims:FindFirstChild("Crusher"))
	return found
end

local function setupCrusher(m)
	local plate = m:WaitForChild("CrushPlate", 5)
	local visual = visualOf(m)
	if not plate or not visual then return end -- (no model: the plate itself is what you see, the server moves it)
	local entry = { plate = plate, restPlate = plate.CFrame, visual = visual, restVisual = visual:GetPivot(), tracks = {} }
	local anims = findAnims(visual)
	if next(anims) then
		local controller = visual:FindFirstChildWhichIsA("AnimationController", true) or visual:FindFirstChildWhichIsA("Humanoid", true)
		if not controller then
			controller = Instance.new("AnimationController")
			controller.Parent = visual
		end
		local animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator", controller)
		for k, a in pairs(anims) do
			local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
			if ok then entry.tracks[k] = tr end
		end
	end
	entry.animated = next(entry.tracks) ~= nil
	crushers[m] = entry
	local function onState()
		if not entry.animated then return end
		local s = squash(m:GetAttribute("CrushState") or "idle")
		for k, tr in pairs(entry.tracks) do
			if k ~= s and tr.IsPlaying then tr:Stop(0.1) end
		end
		local tr = entry.tracks[s]
		if tr then
			tr.Looped = s == "holdcrush"
			tr:Play(0.05)
		end
	end
	m:GetAttributeChangedSignal("CrushState"):Connect(onState)
	onState()
end

local function setup(m)
	if not m:IsDescendantOf(workspace) then return end
	local kind = m:GetAttribute("Kind")
	if kind == "panelarm" or kind == "panelarm2" then
		task.spawn(setupArm, m)
	elseif kind == "crusher" then
		task.spawn(setupCrusher, m)
	end
end
for _, m in ipairs(CollectionService:GetTagged("PeTIPiece")) do setup(m) end
CollectionService:GetInstanceAddedSignal("PeTIPiece"):Connect(function(m) task.defer(setup, m) end)
CollectionService:GetInstanceRemovedSignal("PeTIPiece"):Connect(function(m) arms[m], crushers[m] = nil, nil end)

RunService.RenderStepped:Connect(function()
	for m, a in pairs(arms) do
		if not m.Parent or not a.tile.Parent then
			arms[m] = nil
		else
			-- how far the panel moved from where it rests (world space), handed down the chain
			local delta = a.tile.CFrame * a.restTile:Inverse()
			if a.lastDelta ~= delta then
				a.lastDelta = delta
				for _, c in ipairs(a.chain) do
					if c.bone.Parent then
						local part = CFrame.identity:Lerp(delta, c.share)
						c.bone.WorldCFrame = part * c.rest
					end
				end
			end
		end
	end
	for m, c in pairs(crushers) do
		if not m.Parent or not c.plate.Parent then
			crushers[m] = nil
		elseif not c.animated then
			local delta = c.plate.CFrame * c.restPlate:Inverse()
			c.visual:PivotTo(delta * c.restVisual)
		end
	end
end)
