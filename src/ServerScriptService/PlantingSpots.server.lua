-- PlantingSpots: turns every part named "GROWING BEDS" in Workspace into a plantable GardenPad
local CollectionService = game:GetService("CollectionService")

local TAG = "GardenPad"
local PAD_NAME = "GROWING BEDS"

local function tagPart(inst)
	if inst:IsA("BasePart") and inst.Name == PAD_NAME and not CollectionService:HasTag(inst, TAG) then
		inst.Anchored = true
		CollectionService:AddTag(inst, TAG)
		print("[PlantingSpots] Tagged pad: " .. inst:GetFullName())
	end
end

for _, desc in workspace:GetDescendants() do
	tagPart(desc)
end
workspace.DescendantAdded:Connect(tagPart)

print("[PlantingSpots] Watching for '" .. PAD_NAME .. "' parts in Workspace")
