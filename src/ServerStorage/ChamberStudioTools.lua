-- ChamberStudioTools
-- ServerStorage (ModuleScript)
-- Make test chambers in Studio without copying any game assets out: bring a chamber in from the editor as plain
-- blocks you can move around, change it, and send it back as text.
--
-- IN STUDIO (View > Command Bar):
--   local T = require(game.ServerStorage.ChamberStudioTools)
--   T.Import()            -- reads ServerStorage.ChamberImport (a StringValue: paste the editor's File > Export text into
--                            its Value) and builds workspace.ChamberWorkbench
--   T.Import(text)        -- same, from a string
--   T.Preview()           -- builds the real chamber (your PortalAssets, like the game does) from the workbench into
--                            workspace.ChamberPreview, to see how it looks. T.ClearPreview() removes it.
--   T.Export()            -- reads workspace.ChamberWorkbench and writes the text into ServerStorage.ChamberExport
--                            (a StringValue). Copy its Value, then in the game's editor: File > Import, paste.
--   T.New()               -- a fresh workbench from the default chamber
--
-- THE WORKBENCH (workspace.ChamberWorkbench). Everything snaps to a 10-stud grid (Config.CELL): set Studio's
-- Move snap to 10 and keep it there.
--   Cells   one see-through block per open cell of the room. Duplicate (Ctrl+D) and move them to grow the room,
--           delete them to fill it in. A side of a cell with no cell next to it is a wall / floor / ceiling panel.
--           Panel settings ride on the cell, per side (1 = +X, 2 = -X, 3 = up/ceiling, 4 = down/floor, 5 = +Z, 6 = -Z):
--             Face_<side>    nothing = portalable, 0 = not portalable, 2 = portalable + wall tiles, 3 = not + wall tiles
--             Color_<side>   tile colour number (Config.TILE_COLORS) or "#rrggbb", Texture_<side>  texture name or "id:<number>"
--   Items   one small block per item, sitting in its cell against the side it's mounted on. Move it into another
--           cell to move the item. Attributes:
--             Kind (button, exit, tbeam, ...), Side (1 - 6, as above), Rot (0 - 3), Variant, Id, Span,
--             Options (the item's options as JSON, e.g. {"label":"button1","startOn":false}),
--             LinksTo (Ids it drives, separated by commas)
--   Chips   one ModuleScript (or StringValue) per chip, its Source / Value is the program.
--   Workbench attributes: Title, Coop.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("PortalConfig"))
local CELL = Config.CELL
local FORMAT = "PortalChamber"
local WORKBENCH = "ChamberWorkbench"
local PREVIEW = "ChamberPreview"
-- where the workbench sits (far from your lobby so it doesn't get in the way)
local ORIGIN = Vector3.new(0, 500, -3000)

local T = {}

local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function cellOf(pos)
	local l = (pos - ORIGIN) / CELL
	return math.floor(l.X + 0.5), math.floor(l.Y + 0.5), math.floor(l.Z + 0.5)
end

local function block(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	return p
end

-- the text from the editor (or a bare chamber table) -> chamber data
local function decode(text)
	assert(type(text) == "string" and text ~= "", "No chamber text. Paste File > Export from the editor into ServerStorage.ChamberImport.")
	local ok, t = pcall(HttpService.JSONDecode, HttpService, text)
	assert(ok and type(t) == "table", "That isn't chamber text.")
	local data = (t.format == FORMAT and type(t.data) == "table") and t.data or t
	assert(type(data.air) == "table" and #data.air > 0, "There's no room in that text.")
	return data, t.title, (t.coop == true or data.coop == true)
end

-- ==========================================
-- IMPORT: chamber data -> workspace.ChamberWorkbench
-- ==========================================
function T.Build(data, title, coop)
	local old = workspace:FindFirstChild(WORKBENCH)
	if old then old:Destroy() end
	local wb = Instance.new("Model")
	wb.Name = WORKBENCH
	wb:SetAttribute("Title", title or "Studio Chamber")
	wb:SetAttribute("Coop", coop == true)
	local cells = Instance.new("Folder")
	cells.Name = "Cells"
	cells.Parent = wb
	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = wb
	local chips = Instance.new("Folder")
	chips.Name = "Chips"
	chips.Parent = wb

	local byKey = {}
	for _, c in ipairs(data.air) do
		local x, y, z = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
		if x and y and z then
			local p = block({ Name = "Cell", Size = Vector3.one * (CELL - 0.2), CFrame = CFrame.new(ORIGIN + Vector3.new(x, y, z) * CELL),
				Transparency = 0.85, Color = Color3.fromRGB(150, 200, 255), CanCollide = false, CastShadow = false })
			p.Parent = cells
			byKey[key(x, y, z)] = p
		end
	end
	-- panel settings onto the cell they belong to
	local function each(map, attr)
		for fk, v in pairs(type(map) == "table" and map or {}) do
			local x, y, z, f = string.match(fk, "^(%-?%d+),(%-?%d+),(%-?%d+),(%d+)$")
			local p = x and byKey[key(x, y, z)]
			if p then p:SetAttribute(attr .. "_" .. f, v) end
		end
	end
	each(data.faces, "Face")
	each(data.colors, "Color")
	each(data.textures, "Texture")

	local linksFrom = {}
	for _, l in ipairs(type(data.links) == "table" and data.links or {}) do
		if type(l) == "table" and l[1] and l[2] then
			linksFrom[l[1]] = linksFrom[l[1]] or {}
			table.insert(linksFrom[l[1]], l[2])
		end
	end
	for _, e in ipairs(type(data.ents) == "table" and data.ents or {}) do
		local def = type(e) == "table" and Config.ENTITY_TYPES[e[1]]
		if def then
			local f = tonumber(e[5]) or 4
			local center = ORIGIN + Vector3.new(e[2], e[3], e[4]) * CELL
			local opt = type(e[10]) == "table" and e[10] or nil
			local label = opt and opt.label
			local p = block({ Name = label or e[1], Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(center + Config.DIRS[f] * (CELL / 2 - 1.6)),
				Color = def.mandatory and Color3.fromRGB(240, 150, 60) or (Config.HIDDEN_COLORS and Config.HIDDEN_COLORS[e[1]]) or Color3.fromRGB(80, 90, 100),
				CanCollide = false })
			p:SetAttribute("Kind", e[1])
			p:SetAttribute("Side", f)
			p:SetAttribute("Rot", tonumber(e[6]) or 0)
			if type(e[7]) == "string" then p:SetAttribute("Variant", e[7]) end
			if type(e[8]) == "string" then p:SetAttribute("Id", e[8]) end
			if tonumber(e[9]) then p:SetAttribute("Span", tonumber(e[9])) end
			if opt then p:SetAttribute("Options", HttpService:JSONEncode(opt)) end
			if type(e[8]) == "string" and linksFrom[e[8]] then p:SetAttribute("LinksTo", table.concat(linksFrom[e[8]], ",")) end
			local tag = Instance.new("BillboardGui")
			tag.Size = UDim2.fromOffset(160, 24)
			tag.StudsOffset = Vector3.new(0, 2.5, 0)
			tag.AlwaysOnTop = true
			local tl = Instance.new("TextLabel")
			tl.Size = UDim2.fromScale(1, 1)
			tl.BackgroundTransparency = 1
			tl.TextColor3 = Color3.new(1, 1, 1)
			tl.TextStrokeTransparency = 0.3
			tl.TextScaled = true
			tl.Text = (label or e[1]) .. "  (" .. def.name .. ")"
			tl.Parent = tag
			tag.Parent = p
			p.Parent = items
		end
	end
	for i, c in ipairs(type(data.chips) == "table" and data.chips or {}) do
		if type(c) == "table" and type(c.src) == "string" then
			local name = type(c.name) == "string" and c.name or ("Chip " .. i)
			local ok = pcall(function()
				local m = Instance.new("ModuleScript")
				m.Name = name
				m.Source = c.src -- needs the command bar / a plugin
				m.Parent = chips
			end)
			if not ok then
				local v = Instance.new("StringValue")
				v.Name = name
				v.Value = c.src
				v.Parent = chips
			end
		end
	end
	wb.Parent = workspace
	return wb
end

function T.Import(text)
	if text == nil then
		local v = ServerStorage:FindFirstChild("ChamberImport")
		assert(v and v:IsA("StringValue"), "Make a StringValue called ChamberImport in ServerStorage and paste the editor's File > Export text into it.")
		text = v.Value
	end
	local data, title, coop = decode(text)
	local wb = T.Build(data, title, coop)
	print(("[ChamberStudioTools] Imported '%s': %d cells, %d items. It's in workspace.%s"):format(
		tostring(title), #wb.Cells:GetChildren(), #wb.Items:GetChildren(), WORKBENCH))
	return wb
end

function T.New()
	return T.Build(Config.DefaultChamber(), "Studio Chamber", false)
end

-- ==========================================
-- EXPORT: workspace.ChamberWorkbench -> chamber data / text
-- ==========================================
function T.Read(wb)
	wb = wb or workspace:FindFirstChild(WORKBENCH)
	assert(wb, "No workspace." .. WORKBENCH .. " - run T.Import() or T.New() first.")
	local data = { v = 2, fmt = Config.CHAMBER_FORMAT, air = {}, faces = {}, colors = {}, textures = {}, ents = {}, links = {}, chips = {},
		coop = wb:GetAttribute("Coop") == true }
	local air = {}
	for _, p in ipairs(wb.Cells:GetChildren()) do
		if p:IsA("BasePart") then
			local x, y, z = cellOf(p.Position)
			local k = key(x, y, z)
			if not air[k] then
				air[k] = p
				table.insert(data.air, { x, y, z })
			end
		end
	end
	-- panel settings: only sides that really are panels (no open cell next to them)
	for k, p in pairs(air) do
		local x, y, z = string.match(k, "^(%-?%d+),(%-?%d+),(%-?%d+)$")
		x, y, z = tonumber(x), tonumber(y), tonumber(z)
		for f, o in ipairs(Config.OFFS) do
			if not air[key(x + o[1], y + o[2], z + o[3])] then
				local fk = Config.FaceKey(x, y, z, f)
				local fv, cv, tv = p:GetAttribute("Face_" .. f), p:GetAttribute("Color_" .. f), p:GetAttribute("Texture_" .. f)
				if fv == 0 or fv == 2 or fv == 3 then data.faces[fk] = fv end
				if Config.ValidTileColor(cv) then data.colors[fk] = tonumber(cv) or string.lower(cv) end
				if type(tv) == "string" and tv ~= "" then data.textures[fk] = tv end
			end
		end
	end
	local used = {}
	for _, p in ipairs(wb.Items:GetChildren()) do
		local kind = p:IsA("BasePart") and p:GetAttribute("Kind")
		if Config.ENTITY_TYPES[kind] then
			local x, y, z = cellOf(p.Position)
			local side = math.clamp(math.floor(tonumber(p:GetAttribute("Side")) or 4), 1, 6)
			local o = Config.OFFS[side]
			if not air[key(x, y, z)] then
				warn(("[ChamberStudioTools] '%s' isn't inside a cell - left out"):format(p.Name))
			elseif air[key(x + o[1], y + o[2], z + o[3])] then
				warn(("[ChamberStudioTools] '%s': Side %d faces another open cell, not a wall - the editor will drop it"):format(p.Name, side))
			else
				local id = p:GetAttribute("Id")
				if type(id) ~= "string" or used[id] then id = HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 8) p:SetAttribute("Id", id) end
				used[id] = true
				local opt = false
				local js = p:GetAttribute("Options")
				if type(js) == "string" and js ~= "" then
					local ok, t = pcall(HttpService.JSONDecode, HttpService, js)
					if ok and type(t) == "table" then opt = t else warn(("[ChamberStudioTools] '%s': Options isn't valid JSON - ignored"):format(p.Name)) end
				end
				table.insert(data.ents, { kind, x, y, z, side,
					math.floor(tonumber(p:GetAttribute("Rot")) or 0) % 4, p:GetAttribute("Variant") or false, id,
					tonumber(p:GetAttribute("Span")) or false, opt })
				local to = p:GetAttribute("LinksTo")
				if type(to) == "string" then
					for target in string.gmatch(to, "[^,%s]+") do table.insert(data.links, { id, target }) end
				end
			end
		end
	end
	for _, c in ipairs(wb.Chips:GetChildren()) do
		local src = (c:IsA("LuaSourceContainer") and c.Source) or (c:IsA("StringValue") and c.Value) or nil
		if type(src) == "string" and src ~= "" then table.insert(data.chips, { name = c.Name, src = src }) end
	end
	return data
end

function T.Export(wb)
	wb = wb or workspace:FindFirstChild(WORKBENCH)
	local data = T.Read(wb)
	local text = HttpService:JSONEncode({ format = FORMAT, version = Config.VERSION, title = wb:GetAttribute("Title") or "Studio Chamber",
		coop = data.coop, data = data })
	local v = ServerStorage:FindFirstChild("ChamberExport")
	if not v then
		v = Instance.new("StringValue")
		v.Name = "ChamberExport"
		v.Parent = ServerStorage
	end
	v.Value = text
	local doors = {}
	for _, e in ipairs(data.ents) do doors[e[1]] = true end
	if not (doors.entry and doors.exit) then warn("[ChamberStudioTools] The chamber needs an entry and an exit door before the editor will take it.") end
	if not Config.ExitCanOpen(data) then warn("[ChamberStudioTools] Nothing opens the exit (connect a button: LinksTo, or Options {\"free\":true}).") end
	print(("[ChamberStudioTools] Exported %d cells, %d items, %d chips (%d characters) to ServerStorage.ChamberExport."):format(
		#data.air, #data.ents, #data.chips, #text))
	return text
end

-- ==========================================
-- PREVIEW: the real chamber, built like the game builds it
-- ==========================================
function T.ClearPreview()
	local old = workspace:FindFirstChild(PREVIEW)
	if old then old:Destroy() end
end

function T.Preview(wb)
	T.ClearPreview()
	local data = T.Read(wb)
	local folder = Instance.new("Folder")
	folder.Name = PREVIEW
	folder.Parent = workspace
	-- next to the workbench, so you can compare them
	local ok, err = pcall(Config.BuildChamber, data, folder, ORIGIN + Vector3.new(0, 0, 70 * CELL), {})
	if not ok then warn("[ChamberStudioTools] Preview failed: " .. tostring(err)) end
	return folder
end

return T
