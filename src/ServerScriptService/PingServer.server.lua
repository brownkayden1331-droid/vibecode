-- PingServer (Script, ServerScriptService)
-- Relays pings to your co-op partner (the other player in your chamber), and drops a death ping
-- for them when you die. Pings only work while playing / testing a chamber together.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PingModule = require(ReplicatedStorage:WaitForChild("PingModule"))
local PingEvent = ReplicatedStorage:WaitForChild("PingEvent")

local lastPing = {}
local lastGround = {} -- [player] = last position they were standing on something

-- only your co-op partner gets your pings / death icon: the players in the same chamber instance
-- (PortalServer puts a co-op pair in the same InstanceSlot). Nobody else on the server sees them.
local function partners(sender)
	local slot = sender:GetAttribute("InstanceSlot")
	local list = {}
	if slot == nil then return list end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= sender and other:GetAttribute("InstanceSlot") == slot then table.insert(list, other) end
	end
	return list
end

local function sendToOthers(sender, data)
	for _, other in ipairs(partners(sender)) do
		PingEvent:FireClient(other, sender, data)
	end
end

---------------------------------------------------------------------
-- Normal pings
---------------------------------------------------------------------
PingEvent.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" then return end
	-- pings only while playing / testing a chamber together (not while building in the editor; PingClient also
	-- stops them in the menus)
	if player:GetAttribute("InEditor") and not player:GetAttribute("EditorPlaytest") then return end
	if #partners(player) == 0 then return end
	if typeof(data.Position) ~= "Vector3" or typeof(data.Normal) ~= "Vector3" then return end
	if typeof(data.Type) ~= "string" or not PingModule.Decals[data.Type] then return end
	if data.Type == "Death" then return end -- only the server sends death pings
	if data.Normal.Magnitude < 0.5 then return end

	local now = os.clock()
	if lastPing[player] and now - lastPing[player] < PingModule.Cooldown * 0.8 then return end
	lastPing[player] = now

	local target = data.Target
	if typeof(target) ~= "Instance" or not target:IsDescendantOf(workspace) then
		target = nil
	end

	sendToOthers(player, {
		Position = data.Position,
		Normal = data.Normal.Unit,
		Type = data.Type,
		Color = typeof(data.Color) == "Color3" and data.Color or nil,
		Target = target,
	})
end)

---------------------------------------------------------------------
-- Death pings
---------------------------------------------------------------------
local function snapToGround(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(filter, p.Character) end
	end
	local portals = workspace:FindFirstChild("Portals")
	if portals then table.insert(filter, portals) end
	params.FilterDescendantsInstances = filter

	local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -30, 0), params)
	if hit then
		return hit.Position, hit.Normal
	end
	return pos, Vector3.yAxis
end

local function onCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end

	hum.Died:Once(function()
		if not PingModule.DeathPing then return end

		-- Fell into a pit / the void: the body is gone or way down there,
		-- so mark the last place they were standing instead.
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local pos = hrp and hrp.Position
		if not pos or pos.Y < workspace.FallenPartsDestroyHeight + 25 then
			pos = lastGround[player]
		end
		if not pos then return end

		local point, normal = snapToGround(pos)
		sendToOthers(player, {
			Position = point,
			Normal = normal,
			Type = "Death",
			-- no Color: clients use the dead player's blue/orange
		})
	end)
end

local function hookPlayer(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(hookPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end

-- remember where everyone last stood on solid ground
local groundTimer = 0
RunService.Heartbeat:Connect(function(dt)
	groundTimer += dt
	if groundTimer < 0.2 then return end
	groundTimer = 0

	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hum and hrp and hum.Health > 0 and hum.FloorMaterial ~= Enum.Material.Air then
			lastGround[p] = hrp.Position
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastPing[player] = nil
	lastGround[player] = nil
end)
