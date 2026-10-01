-- validate.luau: ModelTools.Validate. Install once, then call with a 1-line execute_luau (datamodel_type = "Edit"):
--   return require(game.ServerStorage.ModelTools.Validate)({ mode = "validate", path = "Workspace.Lamp", target = 14 })
-- Returns one JSON line; read that instead of inspecting the tree.
--
-- mode = "validate": sanitize + scale + credit the freshly inserted model at `path`.
-- mode = "replace":  validate `path`, then swap it into `old`'s spot and archive `old`.
-- mode = "rollback": archive the live model at `path` and restore the newest archived model that lived there.
-- Paths use dots from the DataModel root (e.g. "Workspace.Props.Lamp"); names containing dots are not supported.

local DEFAULTS = {
	mode = "validate",
	path = "Workspace.NewModel",
	old = nil, -- replace only: path of the model being replaced
	target = nil, -- studs along `axis`; nil keeps the current size (replace + nil = match the old model)
	axis = "Y", -- "X" | "Y" | "Z" | "max"
	tolerance = 0.10,
	needsLight = false, -- true for lamps, signs, screens
	collision = "Box", -- Enum.CollisionFidelity name: "Box" | "Hull" | "Default" | "PreciseConvexDecomposition"
	assetId = "", -- Open Cloud asset id, kept for history
	credit = { Title = "", Author = "", Source = "", License = "", Changes = "" },
}
local CONFIG = DEFAULTS

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local function resolve(path: string?): Instance?
	if not path then
		return nil
	end
	local inst: Instance? = game
	for name in string.gmatch(path, "[^%.]+") do
		if inst == game and name == "game" then
			continue
		end
		inst = if inst then inst:FindFirstChild(name) else nil
	end
	return if inst ~= game then inst else nil
end

local function round(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

local function archiveFolder(): Instance
	local folder = ServerStorage:FindFirstChild("ModelArchive")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ModelArchive"
		folder.Parent = ServerStorage
	end
	return folder
end

local function measure(model: Model): number
	local s = model:GetExtentsSize()
	if CONFIG.axis == "max" then
		return math.max(s.X, s.Y, s.Z)
	end
	return (s :: any)[CONFIG.axis]
end

local function archive(model: Instance)
	model:SetAttribute("ArchivedAt", DateTime.now():ToIsoDate())
	model:SetAttribute("ArchivedFrom", model:GetFullName())
	model:SetAttribute("ArchivedParent", if model.Parent then model.Parent:GetFullName() else "Workspace")
	model:SetAttribute("ArchivedName", model.Name)
	model.Parent = archiveFolder()
end

local function sanitize(model: Model, r)
	-- 1. Remove anything executable plus the package link (Open Cloud model uploads arrive as packages;
	--    deleting PackageLink turns the copy into a plain model so local edits stick).
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("PackageLink") then
			r.removed[d.ClassName] = (r.removed[d.ClassName] or 0) + 1
			pcall(d.Destroy, d)
		end
	end

	-- 2. Anchor, collision, and count what matters.
	local fidelity = (Enum.CollisionFidelity :: any)[CONFIG.collision]
	local fidelityFailed = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			r.parts += 1
			d.Anchored = true
			if d:IsA("MeshPart") then
				r.meshParts += 1
				if not pcall(function()
					d.CollisionFidelity = fidelity
				end) then
					fidelityFailed = true
				end
				if d:FindFirstChildOfClass("SurfaceAppearance") then
					r.surfaceAppearances += 1
				end
			end
		elseif d:IsA("Light") then
			r.lights += 1
		end
	end
	if fidelityFailed then
		table.insert(r.warnings, "CollisionFidelity not writable from execute_luau; set it in the importer or leave Default")
	end
	if r.parts == 0 then
		r.ok = false
		table.insert(r.warnings, "model has no parts")
	end
	if r.meshParts > 0 and r.surfaceAppearances == 0 then
		table.insert(r.warnings, "no SurfaceAppearance: fine for flat-color kits, otherwise run the PBR fix-up")
	end
	if r.meshParts > 8 then
		table.insert(r.warnings, ("%d MeshParts: re-prep with palette/join to cut draw calls"):format(r.meshParts))
	end
	if CONFIG.needsLight and r.lights == 0 then
		table.insert(r.warnings, "needsLight but 0 lights: add a PointLight/SurfaceLight at the emissive part")
	end
end

local function scale(model: Model, target: number?, r)
	local before = measure(model)
	r.size = { before = round(before) }
	if not target or before <= 0 then
		return
	end
	local ratio = target / before
	if math.abs(ratio - 1) > CONFIG.tolerance then
		model:ScaleTo(model:GetScale() * ratio)
	end
	local after = measure(model)
	r.size.after = round(after)
	r.size.target = target
	if math.abs(after / target - 1) > CONFIG.tolerance then
		r.ok = false
		table.insert(r.warnings, "size still outside tolerance after ScaleTo")
	end
end

local function credit(model: Model)
	for key, value in CONFIG.credit do
		if value ~= "" then
			model:SetAttribute("Credit_" .. key, value)
		end
	end
	if CONFIG.assetId ~= "" then
		model:SetAttribute("SourceAssetId", CONFIG.assetId)
	end
	model:SetAttribute("ImportedAt", DateTime.now():ToIsoDate())
end

-- Bottom-align `new` on `old`'s footprint and copy its facing. Assumes both are upright props.
local function place(new: Model, old: Model)
	new:PivotTo(CFrame.new(new:GetPivot().Position) * old:GetPivot().Rotation)
	local oc, os = old:GetBoundingBox()
	local nc, ns = new:GetBoundingBox()
	local offset = Vector3.new(
		oc.Position.X - nc.Position.X,
		(oc.Position.Y - os.Y / 2) - (nc.Position.Y - ns.Y / 2),
		oc.Position.Z - nc.Position.Z
	)
	new:PivotTo(new:GetPivot() + offset)
end

local function asModel(inst: Instance): Model
	if inst:IsA("Model") then
		return inst
	end
	local wrapper = Instance.new("Model")
	wrapper.Name = inst.Name
	wrapper.Parent = inst.Parent
	inst.Parent = wrapper
	return wrapper
end

local function run()
	local r = {
		ok = true,
		mode = CONFIG.mode,
		removed = {},
		warnings = {},
		parts = 0,
		meshParts = 0,
		surfaceAppearances = 0,
		lights = 0,
	}
	local target = resolve(CONFIG.path)
	if not target then
		return { ok = false, error = "not found: " .. tostring(CONFIG.path) }
	end

	if CONFIG.mode == "rollback" then
		local livePath = target:GetFullName()
		local best: Instance? = nil
		for _, a in archiveFolder():GetChildren() do
			if a:GetAttribute("ArchivedFrom") == livePath then
				if not best or a:GetAttribute("ArchivedAt") > best:GetAttribute("ArchivedAt") then
					best = a
				end
			end
		end
		if not best then
			return { ok = false, error = "nothing archived from " .. livePath }
		end
		local parent = resolve(best:GetAttribute("ArchivedParent")) or workspace
		local name = best:GetAttribute("ArchivedName")
		archive(target)
		for _, key in { "ArchivedAt", "ArchivedFrom", "ArchivedParent", "ArchivedName" } do
			best:SetAttribute(key, nil)
		end
		best.Name = name
		best.Parent = parent
		return { ok = true, mode = "rollback", restored = best:GetFullName() }
	end

	local model = asModel(target)
	sanitize(model, r)

	if CONFIG.mode == "replace" then
		local old = resolve(CONFIG.old)
		if not old or not old:IsA("Model") then
			return { ok = false, error = "old model not found: " .. tostring(CONFIG.old) }
		end
		scale(model, CONFIG.target or measure(old), r)
		place(model, old)
		local name, parent = old.Name, old.Parent
		archive(old)
		model.Name = name
		model.Parent = parent
		r.archived = "ServerStorage.ModelArchive." .. name
	else
		scale(model, CONFIG.target, r)
	end

	credit(model)
	r.path = model:GetFullName()
	return r
end

return function(opts: { [string]: any }?): string
	CONFIG = table.clone(DEFAULTS)
	for key, value in opts or {} do
		CONFIG[key] = value
	end
	local ok, result = pcall(run)
	return HttpService:JSONEncode(if ok then result else { ok = false, error = tostring(result) })
end
