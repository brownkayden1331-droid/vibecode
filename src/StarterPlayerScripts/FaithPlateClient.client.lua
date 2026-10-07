-- FaithPlateClient
-- StarterPlayerScripts (LocalScript)
-- Launches you off a faith plate. Editor plates send the exact point to land on + the arc height, so this
-- re-aims from where your character really is and then holds the sideways speed for the whole flight
-- (the Humanoid's air control would otherwise brake it and you'd fall short).
-- While you're flying the player attribute "FaithPlateFlight" is true: have your movement script (air strafing /
-- bhop) leave the velocity alone while it is, or it'll fight this.
-- Flying into an Excursion Funnel ends the flight at once (TestElementsClient sets "InFunnel"): the funnel catches you
-- mid-air like in Portal 2 instead of this holding your speed through it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("FaithPlateLaunch")

local DEBUG = true
local POP = 1.5          -- studs you get lifted off the plate first (so floor friction doesn't eat the launch)
local AIR_STEER = 0.15   -- how much WASD can bend the arc (0 = none, Portal 2 lets you nudge it a little)

local function ballistic(p0, p1, apexY, g)
	apexY = math.max(apexY, p0.Y + 0.5, p1.Y + 0.5)
	local vy = math.sqrt(2 * g * (apexY - p0.Y))
	local t = vy / g + math.sqrt(2 * (apexY - p1.Y) / g)
	return Vector3.new((p1.X - p0.X) / t, vy, (p1.Z - p0.Z) / t), t
end

local flight
local function endFlight()
	if flight then flight:Disconnect() flight = nil end
	player:SetAttribute("FaithPlateFlight", nil)
end

-- (also ends it the moment a funnel grabs you, even between frames)
player:GetAttributeChangedSignal("InFunnel"):Connect(function()
	if player:GetAttribute("InFunnel") then endFlight() end
end)

remote.OnClientEvent:Connect(function(velocity, aim, apexY)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 or typeof(velocity) ~= "Vector3" then return end
	endFlight()
	player:SetAttribute("FaithPlateLaunchTime", os.clock())

	hrp.CFrame += Vector3.new(0, POP, 0)
	local g = workspace.Gravity
	local flightTime
	if typeof(aim) == "Vector3" then
		velocity, flightTime = ballistic(hrp.Position, aim, tonumber(apexY) or math.max(hrp.Position.Y, aim.Y) + 20, g)
	end
	if DEBUG then print(("[FaithPlateClient] launch %.0f studs/s%s"):format(velocity.Magnitude, aim and " (aimed)" or "")) end

	hum:ChangeState(Enum.HumanoidStateType.Physics)
	hrp.AssemblyLinearVelocity = velocity
	task.delay(0.1, function()
		if hum.Parent and hum.Health > 0 then hum:ChangeState(Enum.HumanoidStateType.Freefall) end
	end)

	-- straight up: nothing sideways to hold
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude < 1 then return end

	player:SetAttribute("FaithPlateFlight", true)
	local t0 = os.clock()
	local maxTime = (flightTime or 4) + 0.4
	flight = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if player:GetAttribute("InFunnel") then -- caught by a funnel: it takes over
			endFlight()
			return
		end
		if not hrp.Parent or hum.Health <= 0 or t > maxTime or (t > 0.25 and hum.FloorMaterial ~= Enum.Material.Air) then
			endFlight()
			return
		end
		local steer = hum.MoveDirection * flat.Magnitude * AIR_STEER
		local cur = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(flat.X + steer.X, cur.Y, flat.Z + steer.Z)
	end)
end)
