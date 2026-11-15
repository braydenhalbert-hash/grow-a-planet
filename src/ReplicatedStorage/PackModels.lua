--[[
	PackModels  (ModuleScript)
	Put in: ReplicatedStorage     (name it exactly:  PackModels)

	Hands out copies of your 3D seed pack models. It looks for the models in a Folder named
	PackModels inside ReplicatedStorage (you make that folder, see the steps), and finds each
	pack by its name: Singularity, Event Horizon, Quasar, Void Heart
	(a model named EventHorizon or VoidHeart, with no space, works too).

	Every copy comes ready to use: it can't be bumped into, the part called "Glow" is Neon,
	and the model's pivot is its center.

	PackModels.Get("Quasar")  ->  a new Model (or nil if that pack's model isn't there yet)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PackModels = {}

-- the FOLDER named PackModels (there is also a ModuleScript with the same name, so check the type)
local function findFolder()
	for _ = 1, 100 do
		for _, child in ipairs(ReplicatedStorage:GetChildren()) do
			if child.Name == "PackModels" and child:IsA("Folder") then
				return child
			end
		end
		task.wait(0.1)
	end
	return nil
end
local folder = findFolder()
local warned = {}

-- "Singularity Pack", "singularity_pack", "Singularity" and "SingularityPack" all count as the same name
local function squash(text)
	local simple = string.lower((string.gsub(text, "[%s_%-]", "")))
	return (string.gsub(simple, "pack$", ""))
end

local function findTemplate(name)
	if not folder then
		return nil
	end
	local direct = folder:FindFirstChild(name)
	if direct then
		return direct
	end
	local wanted = squash(name)
	for _, child in ipairs(folder:GetChildren()) do
		if squash(child.Name) == wanted then
			return child
		end
	end
	return nil
end

function PackModels.Get(name)
	local template = findTemplate(name)
	if not template then
		if not warned[name] then
			warned[name] = true
			if not folder then
				warn("[PackModels] there is no Folder named PackModels inside ReplicatedStorage")
			else
				local have = {}
				for _, child in ipairs(folder:GetChildren()) do
					table.insert(have, child.Name)
				end
				warn("[PackModels] no model for '" .. tostring(name) .. "'. The PackModels folder has: "
					.. (#have > 0 and table.concat(have, ", ") or "nothing in it"))
			end
		end
		return nil
	end

	local model = template:Clone()
	if not model:IsA("Model") then
		local wrapper = Instance.new("Model")
		model.Parent = wrapper
		model = wrapper
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Massless = true
			if string.find(string.lower(descendant.Name), "glow") then
				descendant.Material = Enum.Material.Neon
			else
				descendant.Material = Enum.Material.SmoothPlastic
			end
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	-- the pivot becomes the middle of the model, so it spins and sits where you put it
	local boxCFrame = model:GetBoundingBox()
	model.WorldPivot = boxCFrame

	return model
end

return PackModels
