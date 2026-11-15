--[[
	NpcOutfits  (Script)  -- ServerScriptService

	Dresses the shop NPCs in real Roblox avatar items when the server starts
	(so they aren't plain noobs). Change any number below to swap an item:
	  Hat / Hair / Face / Shirt / Pants  = catalog item IDs (the number in the item's web address)
	  Skin                               = body colour
	Use 0 (or "") to leave a slot empty. The NPCs are found by name inside Workspace.SHOPS.
]]

local NPC_OUTFITS = {
	-- Seed Seller (blue stand): straw hat, denim overalls, no shirt, big toothy grin
	SeedSeller = {
		Hat = "15509791137",          -- Farmer's Straw Hat
		Shirt = 0,
		Pants = 130438744409735,      -- Farmer Overalls
		Face = 20722130,              -- Shiny Teeth
		Skin = Color3.fromRGB(165, 105, 72),
	},
	-- Planet Buyer (red stand): straw hat, maroon shirt, black jeans, smile
	PlanetBuyer = {
		Hat = "15509791137",          -- Farmer's Straw Hat
		Shirt = 96714350302033,       -- Maroon Shirt
		Pants = 105229674413918,      -- Black Jeans
		Face = 0,                     -- classic smile
		Skin = Color3.fromRGB(165, 105, 72),
	},
	-- Black hole pack seller (purple stand): beanie, purple hoodie, black jeans
	R6 = {
		Hat = "83960657335506",       -- Worn Black Beanie
		Shirt = 4580627432,           -- Purple Hoodie
		Pants = 105229674413918,      -- Black Jeans
		Face = 26424808,              -- Know-It-All Grin
		Skin = Color3.fromRGB(120, 80, 58),
	},
}

local shops = workspace:WaitForChild("SHOPS", 30)
if not shops then
	warn("[NpcOutfits] no Workspace.SHOPS folder")
	return
end

local function dress(name, outfit)
	local npc = shops:WaitForChild(name, 20)
	local humanoid = npc and npc:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[NpcOutfits] couldn't find NPC " .. name)
		return
	end
	local description = Instance.new("HumanoidDescription")
	description.HatAccessory = outfit.Hat or ""
	description.HairAccessory = outfit.Hair or ""
	description.Shirt = outfit.Shirt or 0
	description.Pants = outfit.Pants or 0
	description.Face = outfit.Face or 0
	for _, part in ipairs({ "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }) do
		description[part] = outfit.Skin
	end
	-- the catalog can be slow: try a few times
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			humanoid:ApplyDescription(description)
		end)
		if ok then
			return
		end
		warn("[NpcOutfits] " .. name .. " attempt " .. attempt .. ": " .. tostring(err))
		task.wait(2)
	end
end

for name, outfit in pairs(NPC_OUTFITS) do
	task.spawn(dress, name, outfit)
end
print("[NpcOutfits] dressing the shop NPCs")
