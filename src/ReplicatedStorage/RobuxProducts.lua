--[[
	RobuxProducts  (ModuleScript)  -- ReplicatedStorage

	Every Robux Developer Product in the game, keyed by item id.
	  Price      what the shop button shows (must match the product's price on Creator Hub)
	  ProductId  the Developer Product id from Creator Hub > Monetization > Developer Products

	Prices follow the coin price: R$ = 9 * (coins / 100) ^ 0.288, rounded to a normal Robux price.
	To change a price: change it on Creator Hub first, then change Price here to match.
	An item that isn't listed here has no Robux / Gift button.
]]

local RobuxProducts = {}

RobuxProducts.Restock = { Price = 29, ProductId = 3731802712 }

RobuxProducts.Items = {
	-- planet seeds (Planet shop + Sun shop)
	moon = { Price = 9, ProductId = 3731803941 },
	mercury = { Price = 15, ProductId = 3731804150 },
	venus = { Price = 15, ProductId = 3731804174 },
	earth = { Price = 19, ProductId = 3731804197 },
	mars = { Price = 25, ProductId = 3731804214 },
	red_dwarf = { Price = 29, ProductId = 3731804223 },
	jupiter = { Price = 39, ProductId = 3731804235 },
	saturn = { Price = 49, ProductId = 3731804248 },
	white_dwarf = { Price = 69, ProductId = 3731804259 },
	uranus = { Price = 99, ProductId = 3731804272 },
	neptune = { Price = 119, ProductId = 3731804287 },
	blue_giant = { Price = 149, ProductId = 3731804487 },
	sun = { Price = 199, ProductId = 3731804507 },
	betelgeuse = { Price = 299, ProductId = 3731804527 },
	pulsar = { Price = 399, ProductId = 3731804544 },

	-- black hole packs
	pack_singularity = { Price = 79, ProductId = 3729889622 },
	pack_horizon = { Price = 149, ProductId = 3729889738 },
	pack_quasar = { Price = 299, ProductId = 3729889792 },
	pack_voidheart = { Price = 599, ProductId = 3729889844 },

	-- sprinklers (Gear shop)
	sprinkler_basic = { Price = 15, ProductId = 3731804570 },
	sprinkler_stardust = { Price = 25, ProductId = 3731804591 },
	sprinkler_nebula = { Price = 49, ProductId = 3731805372 },
	sprinkler_cosmic = { Price = 149, ProductId = 3731804625 },
	sprinkler_nebulacloud = { Price = 399, ProductId = 3731804636 },
	sprinkler_celestialtree = { Price = 399, ProductId = 3731804652 },
	sprinkler_quasar = { Price = 449, ProductId = 3731804803 },
	sprinkler_darkmatter = { Price = 449, ProductId = 3731804811 },
	sprinkler_galaxystardust = { Price = 499, ProductId = 3731804826 },
	sprinkler_voidspiral = { Price = 599, ProductId = 3731804834 },
	sprinkler_blackhole = { Price = 599, ProductId = 3731804847 },
	sprinkler_timedilation = { Price = 699, ProductId = 3731804854 },
	sprinkler_planetaryring = { Price = 699, ProductId = 3731804872 },
	sprinkler_orbitalstation = { Price = 699, ProductId = 3731804883 },
	sprinkler_solarstardust = { Price = 799, ProductId = 3731804894 },
	sprinkler_supernova = { Price = 899, ProductId = 3731804903 },
	sprinkler_galaxycore = { Price = 999, ProductId = 3731805058 },
	sprinkler_cosmicsupreme = { Price = 999, ProductId = 3731805077 },
	sprinkler_blackholestardust = { Price = 1199, ProductId = 3731805093 },
	sprinkler_divine = { Price = 1499, ProductId = 3731805108 },
	sprinkler_nebulastardust = { Price = 1499, ProductId = 3731805120 },
	sprinkler_celestial = { Price = 1799, ProductId = 3731805141 },
	sprinkler_supernovastardust = { Price = 1799, ProductId = 3731805164 },
	sprinkler_celestialstardust = { Price = 1999, ProductId = 3731805182 },
	sprinkler_quantumstardust = { Price = 1999, ProductId = 3731805203 },
	sprinkler_voidstardust = { Price = 2499, ProductId = 3731805225 },
}

local byProductId = {}
for id, info in pairs(RobuxProducts.Items) do
	byProductId[info.ProductId] = id
end

function RobuxProducts.Get(itemId)
	return RobuxProducts.Items[itemId]
end

-- product id -> item id (nil for the restock product or unknown ids)
function RobuxProducts.ItemForProduct(productId)
	return byProductId[productId]
end

return RobuxProducts
