--[[
	ItemIcons  (ModuleScript)  -- ReplicatedStorage

	Makes the little 3D picture of an item (a ViewportFrame) for the hotbar and the backpack.
	  ItemIcons.Make(parent, tool)   -> the ViewportFrame, or nil if the item has no 3D model
	Works for seeds and harvested planets (PlanetId), sprinklers (GearId) and seed packs (PackId).
	Pictures are built from the same models the shops use.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PlanetBuilder = require(ReplicatedStorage:WaitForChild("PlanetBuilder"))
local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog"))
local PackCatalog = require(ReplicatedStorage:WaitForChild("PackCatalog"))
local SprinklerModel = require(ReplicatedStorage:WaitForChild("SprinklerModel"))

-- the PackModels ModuleScript (a Folder with the same name also exists, so look for the module)
local PackModels = nil
task.spawn(function()
	for _ = 1, 100 do
		for _, child in ipairs(ReplicatedStorage:GetChildren()) do
			if child.Name == "PackModels" and child:IsA("ModuleScript") then
				local ok, result = pcall(require, child)
				if ok then
					PackModels = result
				end
				return
			end
		end
		task.wait(0.1)
	end
end)

local ItemIcons = {}

local function viewport(parent, ambient)
	local v = Instance.new("ViewportFrame")
	v.Name = "Icon"
	v.BackgroundTransparency = 1
	v.Size = UDim2.fromScale(1, 1)
	v.Ambient = ambient
	v.LightColor = Color3.fromRGB(255, 250, 240)
	v.LightDirection = Vector3.new(-0.6, -0.5, -0.7)
	v.Parent = parent
	return v
end

local function camera(v, cframe)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = cframe
	cam.Parent = v
	v.CurrentCamera = cam
end

local function radiusUnits(look)
	local r = 0.5
	for _, ring in ipairs(look.Rings or {}) do
		r = math.max(r, math.min(ring.Scale / 2, 1.05))
	end
	if look.Glow then
		r = math.max(r, look.Glow.Size / 2)
	end
	for _, moon in ipairs(look.Moons or {}) do
		r = math.max(r, math.min(moon.Distance + moon.Size / 2, 0.85))
	end
	return r
end

local function planetIcon(parent, planet)
	local v = viewport(parent, Color3.fromRGB(170, 160, 190))
	local ok = pcall(PlanetBuilder.Build, planet, v, nil, nil, "icon")
	if not ok then
		v:Destroy()
		return nil
	end
	local radius = planet.Look.Size * radiusUnits(planet.Look)
	local distance = radius / math.tan(math.rad(15)) * 1.1
	camera(v, CFrame.lookAt(Vector3.new(0, radius * 0.3, distance), Vector3.zero))
	return v
end

local function gearIcon(parent, gear)
	local v = viewport(parent, Color3.fromRGB(150, 150, 175))
	local ok, model = pcall(SprinklerModel.Build, gear, CFrame.new(), false, true)
	if not ok or not model then
		v:Destroy()
		return nil
	end
	model.Parent = v
	local box, size = model:GetBoundingBox()
	if model.PrimaryPart then
		model.PrimaryPart.PivotOffset = model.PrimaryPart.CFrame:ToObjectSpace(CFrame.new(box.Position))
	end
	model:PivotTo(CFrame.new())
	local fit = math.max(size.Y, size.X * 0.9) / 2
	camera(v, CFrame.lookAt(Vector3.new(0, fit * 0.35, fit / math.tan(math.rad(15)) * 1.08), Vector3.zero))
	return v
end

local function packIcon(parent, pack)
	if not PackModels then
		return nil
	end
	local ok, model = pcall(PackModels.Get, pack.Name)
	if not ok or not model then
		return nil
	end
	local v = viewport(parent, Color3.fromRGB(190, 180, 215))
	model.Parent = v
	model:PivotTo(CFrame.new())
	local _, size = model:GetBoundingBox()
	local distance = (size.Y / 2) / math.tan(math.rad(15)) * 1.25
	camera(v, CFrame.lookAt(Vector3.new(distance * 0.3, distance * 0.16, distance), Vector3.zero))
	return v
end

function ItemIcons.Make(parent, tool)
	local planetId = tool:GetAttribute("PlanetId")
	if planetId then
		local planet = PlanetCatalog.Get(planetId)
		return planet and planetIcon(parent, planet)
	end
	local gearId = tool:GetAttribute("GearId")
	if gearId then
		local gear = GearCatalog.Get(gearId)
		return gear and gearIcon(parent, gear)
	end
	local packId = tool:GetAttribute("PackId")
	if packId then
		local pack = PackCatalog.Get(packId)
		return pack and packIcon(parent, pack)
	end
	return nil
end

-- the main colour of an item (used when there's no 3D picture)
function ItemIcons.Color(tool)
	local planetId = tool:GetAttribute("PlanetId")
	local planet = planetId and PlanetCatalog.Get(planetId)
	if planet and planet.Look and planet.Look.Color then
		return planet.Look.Color
	end
	return Color3.fromRGB(150, 140, 200)
end

return ItemIcons
