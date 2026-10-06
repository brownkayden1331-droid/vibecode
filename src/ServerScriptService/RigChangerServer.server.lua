-- RigChangerServer
-- ServerScriptService (Script)
-- Turns a player into a portal gun rig (from PortalAssets.Rigs) and back: Chell, or in co-op Atlas (blue) / P-body (orange).
-- The pedestal, the map editor playtest, co-op, or any of your scripts just fire the event.
--
-- FROM ANY SERVER SCRIPT (BindableEvent, ReplicatedStorage.PortalAssets.RigChangerEvent):
--   RigChangerEvent:Fire(player, "Equip",   { rig = "Chell", silent = false, source = "Pedestal" })
--   RigChangerEvent:Fire(player, "Restore", { source = "Editor" })
--   rig    : rig name in Rigs (matched loosely: "PBody" finds "P-Body" / "P body"). nil = the player's co-op rig
--            (player attribute CoopColor: Blue -> Atlas, Orange -> P-body), else the first model with "chell" in its name
--   silent : true = no power-up animation (the editor and co-op use this)
--   source : "Editor" = the gun is only lent for playtesting; Restore with source "Editor"
--            gives the normal character back ONLY if the gun came from the editor
--            "Workshop" = lent for a Workshop chamber; Restore with source "Workshop" takes it back only if it was lent
--            "Coop"   = co-op made you Atlas / P-body; Restore with source "Coop" puts you back the way you were
--                       (normal character if co-op gave you the gun, Chell if you already had it)
--
-- The script bumps the player attribute  RigChangeDone  (a number) every time it finishes a
-- request, so a caller can wait for it:
--   local before = player:GetAttribute("RigChangeDone") or 0
--   event:Fire(player, "Equip", {})
--   repeat task.wait() until (player:GetAttribute("RigChangeDone") or 0) ~= before
--
-- The character gets the attribute RigName (the rig it was made from), and HasPortalGun.
--
-- REMOTE (ReplicatedStorage.PortalAssets.RigChangerRemote):
--   server -> client  OnClientEvent("RigChanged", { gun = bool, rig = string })
--   client -> server  FireServer("Equip" | "Restore")   only accepted while the player is in the
--                     map editor (player attribute InEditor), always with source "Editor"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local portalAssets = ReplicatedStorage:WaitForChild("PortalAssets")
local rigsFolder = portalAssets:WaitForChild("Rigs")

-- ==========================================
-- SETTINGS
-- ==========================================
local DEFAULT_RIG_NAME = nil     -- exact rig name; nil = first model with "chell" in its name
local KEEP_ON_RESPAWN = true     -- respawn as the gun rig after dying (while HasPortalGun is true)
-- co-op: which rig each colour plays as (names in PortalAssets.Rigs, matched loosely)
local COOP_RIGS = { Blue = "Atlas", Orange = "PBody" }

-- ==========================================
-- EVENTS
-- ==========================================
local function ensure(class, name)
	local o = portalAssets:FindFirstChild(name)
	if not o then
		o = Instance.new(class)
		o.Name = name
		o.Parent = portalAssets
	end
	return o
end

local changerEvent = ensure("BindableEvent", "RigChangerEvent")
local changerRemote = ensure("RemoteEvent", "RigChangerRemote")

-- ==========================================
-- RIGS
-- ==========================================
local function squash(s) return (string.lower(s):gsub("[^%w]", "")) end

local function defaultTemplate()
	if DEFAULT_RIG_NAME then return rigsFolder:FindFirstChild(DEFAULT_RIG_NAME) end
	for _, m in ipairs(rigsFolder:GetChildren()) do
		if m:IsA("Model") and string.find(string.lower(m.Name), "chell", 1, true) then
			return m
		end
	end
	return rigsFolder:FindFirstChildWhichIsA("Model")
end

-- exact name first, then loosely ("PBody" = "P-Body" = "p body"), then any rig whose name contains it
local function findRig(name)
	local exact = rigsFolder:FindFirstChild(name)
	if exact and exact:IsA("Model") then return exact end
	local want = squash(name)
	for _, m in ipairs(rigsFolder:GetChildren()) do
		if m:IsA("Model") and squash(m.Name) == want then return m end
	end
	for _, m in ipairs(rigsFolder:GetChildren()) do
		if m:IsA("Model") and string.find(squash(m.Name), want, 1, true) then return m end
	end
	return nil
end

local warned = {}
-- the rig a player should get: what was asked for, else their co-op rig, else Chell
local function getTemplate(player, rigName)
	local wanted = rigName or COOP_RIGS[player:GetAttribute("CoopColor") or ""]
	if wanted then
		local t = findRig(wanted)
		if t then return t end
		if not warned[wanted] then
			warned[wanted] = true
			warn("[RigChanger] No rig named '" .. wanted .. "' in PortalAssets.Rigs - using Chell instead")
		end
	end
	return defaultTemplate()
end

local function isCoopRig(char)
	local n = char and char:GetAttribute("RigName")
	if not n then return false end
	for _, r in pairs(COOP_RIGS) do
		if squash(n) == squash(r) or string.find(squash(n), squash(r), 1, true) then return true end
	end
	return false
end

local function equip(player, options)
	local old = player.Character
	local hadGun = player:GetAttribute("HasPortalGun") == true

	local template = getTemplate(player, options.rig)
	if not template then
		warn("[RigChanger] No rig found in PortalAssets.Rigs")
		return
	end
	-- already this rig with the gun: nothing to do (a different rig = swap, e.g. Chell -> Atlas)
	if old and old:GetAttribute("HasPortalGun") and old:GetAttribute("RigName") == template.Name then return end
	if not template:FindFirstChild("HumanoidRootPart") then
		warn("[RigChanger] Rig '" .. template.Name .. "' has no HumanoidRootPart")
		return
	end

	player:SetAttribute("PortalGunEquipping", true)

	-- where to put them: exactly where the old character's root is
	local oldRoot = old and old:FindFirstChild("HumanoidRootPart")
	local spawnCF = oldRoot and oldRoot.CFrame or CFrame.new(0, 10, 0)
	local oldHumanoid = old and old:FindFirstChildOfClass("Humanoid")

	local rig = template:Clone()
	rig.Name = player.Name
	rig:SetAttribute("HasPortalGun", true)
	rig:SetAttribute("RigName", template.Name)

	-- a playable character needs a Humanoid with an Animator (and only one animator)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = rig
	end
	for _, ac in ipairs(rig:GetDescendants()) do
		if ac:IsA("AnimationController") then ac:Destroy() end
	end
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end
	if oldHumanoid then
		humanoid.WalkSpeed = oldHumanoid.WalkSpeed
		humanoid.JumpPower = oldHumanoid.JumpPower
		humanoid.JumpHeight = oldHumanoid.JumpHeight
		humanoid.UseJumpPower = oldHumanoid.UseJumpPower
	end

	rig.PrimaryPart = rig:FindFirstChild("HumanoidRootPart")
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = false end
	end

	-- Setting player.Character by hand does NOT copy StarterCharacterScripts
	for _, s in ipairs(StarterPlayer.StarterCharacterScripts:GetChildren()) do
		local existing = rig:FindFirstChild(s.Name)
		if existing then existing:Destroy() end
		s:Clone().Parent = rig
	end

	rig:PivotTo(spawnCF)
	player.Character = rig
	rig.Parent = workspace
	if old and old ~= rig then old:Destroy() end

	-- the gun is only lent by the editor / co-op if they didn't already own it
	if options.source == "Editor" and not hadGun then
		player:SetAttribute("GunFromEditor", true)
	end
	if options.source == "Coop" and not hadGun then
		player:SetAttribute("GunFromCoop", true)
	end
	if options.source == "Workshop" and not hadGun then
		player:SetAttribute("GunFromWorkshop", true)
	end
	if not hadGun and not options.silent then -- first pickup only: power-up anim on the client
		player:SetAttribute("PortalGunPickupTime", workspace:GetServerTimeNow())
	end
	player:SetAttribute("HasPortalGun", true)
	player:SetAttribute("PortalGunEquipping", nil)
end

-- back to the normal character (no gun)
local function loadNormal(player)
	local old = player.Character
	local oldRoot = old and old:FindFirstChild("HumanoidRootPart")
	local cf = oldRoot and oldRoot.CFrame

	-- HasPortalGun first, so the respawn watcher below leaves the new character alone
	player:SetAttribute("HasPortalGun", false)
	player:SetAttribute("GunFromEditor", nil)
	player:SetAttribute("GunFromCoop", nil)
	player:SetAttribute("GunFromWorkshop", nil)
	player:LoadCharacter()

	local char = player.Character
	local root = char and char:WaitForChild("HumanoidRootPart", 5)
	if root and cf then char:PivotTo(cf) end
end

local function restore(player, options)
	local old = player.Character
	if options.source == "Coop" then
		if player:GetAttribute("GunFromCoop") then
			loadNormal(player) -- co-op gave them the gun: take it back
		elseif isCoopRig(old) then
			player:SetAttribute("CoopColor", nil)
			equip(player, { silent = true }) -- they had the gun before co-op: back to Chell
		end
		return
	end
	if options.source == "Editor" and player:GetAttribute("GunFromEditor") ~= true then return end
	if options.source == "Workshop" and player:GetAttribute("GunFromWorkshop") ~= true then return end
	if player:GetAttribute("HasPortalGun") ~= true and not (old and old:GetAttribute("HasPortalGun")) then return end
	loadNormal(player)
end

-- ==========================================
-- REQUESTS (one at a time per player)
-- ==========================================
local busy = {}

local function handle(player, action, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then return end
	options = type(options) == "table" and options or {}
	while busy[player] do task.wait() end
	if not player.Parent then return end
	busy[player] = true

	local ok, err = pcall(function()
		if action == "Equip" then
			equip(player, options)
		elseif action == "Restore" then
			restore(player, options)
		else
			warn("[RigChanger] unknown action " .. tostring(action))
		end
	end)
	if not ok then warn("[RigChanger] " .. tostring(err)) end

	busy[player] = nil
	player:SetAttribute("RigChangeDone", (player:GetAttribute("RigChangeDone") or 0) + 1)
	if player.Parent then
		changerRemote:FireClient(player, "RigChanged", {
			gun = player:GetAttribute("HasPortalGun") == true,
			rig = player.Character and (player.Character:GetAttribute("RigName") or player.Character.Name) or "",
		})
	end
end

changerEvent.Event:Connect(function(player, action, options)
	task.spawn(handle, player, action, options)
end)

-- clients may only ask while they are in the map editor
changerRemote.OnServerEvent:Connect(function(player, action)
	if not player:GetAttribute("InEditor") then return end
	if action ~= "Equip" and action ~= "Restore" then return end
	task.spawn(handle, player, action, { source = "Editor", silent = true })
end)

-- ==========================================
-- RESPAWN: come back as the gun rig (Atlas / P-body in co-op)
-- ==========================================
local function watchPlayer(player)
	player.CharacterAdded:Connect(function(char)
		if not KEEP_ON_RESPAWN then return end
		if not player:GetAttribute("HasPortalGun") then return end
		if char:GetAttribute("HasPortalGun") then return end -- this IS the gun rig
		char:WaitForChild("HumanoidRootPart", 5)
		task.wait() -- let the spawn location settle first
		if player.Character == char then
			task.spawn(handle, player, "Equip", { silent = true })
		end
	end)
end

for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)
