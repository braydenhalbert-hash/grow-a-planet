--[[
	MutationCatalog  (ModuleScript)
	Put in: ReplicatedStorage   (name it exactly: MutationCatalog, next to PlanetCatalog)

	Mutations are lucky bonuses a planet can get while it grows in your garden.
	A mutated planet shows a glowing title above it, has its own special effects,
	makes MORE coins from the stuff around it (CoinMult) and SELLS for more (SellMult).

	Chance = chance (0.15 = 15%) that a freshly planted seed gets that mutation.
	Every mutation rolls on its own, so ONE planet can get several and they STACK (see Stacking below).
	Change the numbers here to make mutations more or less common or valuable.
]]

local MutationCatalog = {}

-- How mutations stack on one planet:
--   "add"       (default) 1 + (each boost - 1).  Meteor Shower (3x) + Frozen (2x) = 4x
--   "multiply"  each boost multiplies the last.  Meteor Shower (3x) + Frozen (2x) = 6x   (gets big fast!)
MutationCatalog.Stacking = "add"

MutationCatalog.Order = { "meteor", "frozen", "nebula", "solarflare", "supernova", "stardust" }

MutationCatalog.Mutations = {
	meteor = {
		Id = "meteor", Name = "Meteor Shower",
		Chance = 0.15, CoinMult = 3, SellMult = 3,
		Color = Color3.fromRGB(255, 150, 60), Color2 = Color3.fromRGB(255, 70, 40),
	},
	frozen = {
		Id = "frozen", Name = "Frozen",
		Chance = 0.10, CoinMult = 2, SellMult = 2,
		Color = Color3.fromRGB(170, 235, 255), Color2 = Color3.fromRGB(90, 160, 255),
	},
	nebula = {
		Id = "nebula", Name = "Nebula",
		Chance = 0.06, CoinMult = 4, SellMult = 4,
		Color = Color3.fromRGB(255, 120, 230), Color2 = Color3.fromRGB(130, 90, 255),
	},
	solarflare = {
		Id = "solarflare", Name = "Solar Flare",
		Chance = 0.03, CoinMult = 6, SellMult = 6,
		Color = Color3.fromRGB(255, 225, 80), Color2 = Color3.fromRGB(255, 110, 20),
	},
	supernova = {
		Id = "supernova", Name = "Supernova",
		Chance = 0.01, CoinMult = 12, SellMult = 12,
		Color = Color3.fromRGB(255, 255, 255), Color2 = Color3.fromRGB(255, 200, 90),
	},
	-- never happens by itself (Chance = 0): only a BLACK HOLE that swallows stardust from a
	-- Stardust Sprinkler (gear shop) can get it. How likely that is is set per sprinkler in GearCatalog.
	stardust = {
		Id = "stardust", Name = "Stardust",
		Chance = 0, CoinMult = 5, SellMult = 5,
		Color = Color3.fromRGB(215, 190, 255), Color2 = Color3.fromRGB(120, 230, 255),
	},
}

function MutationCatalog.Get(id)
	return type(id) == "string" and MutationCatalog.Mutations[id] or nil
end

-- "meteor,frozen" (or a list of ids) -> a clean list of valid ids, no repeats
function MutationCatalog.Parse(value)
	local ids, seen = {}, {}
	local function add(id)
		if MutationCatalog.Mutations[id] and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	if type(value) == "string" then
		for id in string.gmatch(value, "[^,]+") do
			add(id)
		end
	elseif type(value) == "table" then
		for _, id in ipairs(value) do
			add(id)
		end
	end
	return ids
end

function MutationCatalog.Join(value)
	return table.concat(MutationCatalog.Parse(value), ",")
end

-- "Meteor Shower Frozen"
function MutationCatalog.Names(value)
	local names = {}
	for _, id in ipairs(MutationCatalog.Parse(value)) do
		table.insert(names, MutationCatalog.Mutations[id].Name)
	end
	return table.concat(names, " ")
end

local function total(value, key)
	local sum, product = 1, 1
	for _, id in ipairs(MutationCatalog.Parse(value)) do
		local m = MutationCatalog.Mutations[id][key]
		sum += m - 1
		product *= m
	end
	return MutationCatalog.Stacking == "multiply" and product or sum
end

-- the boost from ALL of a planet's mutations together (value = "meteor,frozen", a list, or one id)
function MutationCatalog.CoinMult(value)
	return total(value, "CoinMult")
end

function MutationCatalog.SellMult(value)
	return total(value, "SellMult")
end

-- roll once when a seed is planted: every mutation rolls on its own, so a planet can get several
function MutationCatalog.RollAll(rng)
	rng = rng or Random.new()
	local ids = {}
	for _, id in ipairs(MutationCatalog.Order) do
		if rng:NextNumber() < MutationCatalog.Mutations[id].Chance then
			table.insert(ids, id)
		end
	end
	return ids
end

-- (old single roll, still here in case something uses it)
function MutationCatalog.Roll(rng)
	local ids = MutationCatalog.RollAll(rng)
	return ids[1]
end

return MutationCatalog
