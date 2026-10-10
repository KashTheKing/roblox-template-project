local OsmParser = require(shared.osm["osm-parser"])
local WorldConfig = require(shared.configs["world-config"])

-- A 0.01 x 0.01 degree box around (10, 20).
local BOUNDS = { south = 10, west = 20, north = 10.01, east = 20.01 }

local function way(id, tags, coords)
	local geometry = {}
	for i = 1, #coords, 2 do
		table.insert(geometry, { lon = coords[i], lat = coords[i + 1] })
	end
	return { type = "way", id = id, tags = tags, geometry = geometry }
end

local function square(lon, lat, size)
	return { lon, lat, lon + size, lat, lon + size, lat + size, lon, lat + size, lon, lat }
end

test("parses a tagged building with its height", function()
	local data = OsmParser.parse({
		elements = { way(1, { building = "yes", height = "12.5 m" }, square(20.002, 10.002, 0.0002)) },
	}, BOUNDS, WorldConfig)
	check(#data.buildings == 1)
	approx(data.buildings[1].heightMeters, 12.5)
	check(#data.buildings[1].pts == 8, "closing point removed")
end)

test("building height falls back to levels, feet, then a kind default", function()
	local cfg = WorldConfig
	approx(OsmParser.buildingHeightMeters({ ["building:levels"] = "5" }, 1, cfg), 5 * 3.2 + 1)
	approx(OsmParser.buildingHeightMeters({ height = "40 ft" }, 1, cfg), 12.192, 1e-6)
	local house = OsmParser.buildingHeightMeters({ building = "house" }, 0, cfg)
	check(house >= 5 and house <= 8.5, "house default height was " .. house)
	local plain = OsmParser.buildingHeightMeters({ building = "yes" }, 0, cfg)
	check(plain >= 7 and plain <= 11, "generic default height was " .. plain)
	approx(OsmParser.buildingHeightMeters({ height = "9000" }, 1, cfg), cfg.maxBuildingHeightMeters)
end)

test("parseLength understands units and garbage", function()
	approx(OsmParser.parseLength("12"), 12)
	approx(OsmParser.parseLength("12.5 m"), 12.5)
	approx(OsmParser.parseLength("40'"), 12.192, 1e-6)
	check(OsmParser.parseLength("tall") == nil)
	check(OsmParser.parseLength(nil) == nil)
end)

test("skips building=no and unclosed building ways", function()
	local open = way(2, { building = "yes" }, { 20.002, 10.002, 20.003, 10.002, 20.003, 10.003 })
	local data = OsmParser.parse({
		elements = { way(1, { building = "no" }, square(20.002, 10.002, 0.0002)), open },
	}, BOUNDS, WorldConfig)
	check(#data.buildings == 0)
end)

test("a building belongs only to the tile holding its centroid", function()
	local straddling = way(3, { building = "yes" }, square(20.0095, 10.002, 0.0008)) -- centroid at lon 20.0099
	local neighbour = { south = 10, west = 20.01, north = 10.01, east = 20.02 }
	local elements = { straddling }
	check(#OsmParser.parse({ elements = elements }, BOUNDS, WorldConfig).buildings == 1)
	check(#OsmParser.parse({ elements = elements }, neighbour, WorldConfig).buildings == 0)
end)

test("roads are clipped to the tile and get a width from their class", function()
	local data = OsmParser.parse({
		elements = {
			way(4, { highway = "residential" }, { 19.99, 10.005, 20.02, 10.005 }),
			way(5, { highway = "footway" }, { 20.001, 10.001, 20.002, 10.002 }),
		},
	}, BOUNDS, WorldConfig)
	check(#data.lines == 2)
	local road = data.lines[1]
	approx(road.widthMeters, 7)
	approx(road.pts[1], 20)
	approx(road.pts[#road.pts - 1], 20.01)
	check(road.layer == "road")
	approx(data.lines[2].widthMeters, 2.5)
end)

test("tunnels and proposed roads are ignored", function()
	local data = OsmParser.parse({
		elements = {
			way(6, { highway = "primary", tunnel = "yes" }, { 20.001, 10.001, 20.002, 10.002 }),
			way(7, { highway = "proposed" }, { 20.001, 10.001, 20.002, 10.002 }),
		},
	}, BOUNDS, WorldConfig)
	check(#data.lines == 0)
end)

test("water, parks and woods become areas; rivers become water lines", function()
	local data = OsmParser.parse({
		elements = {
			way(8, { natural = "water" }, square(20.001, 10.001, 0.002)),
			way(9, { leisure = "park" }, square(20.004, 10.004, 0.002)),
			way(10, { landuse = "forest" }, square(20.006, 10.006, 0.002)),
			way(11, { waterway = "river" }, { 20.001, 10.009, 20.009, 10.009 }),
			way(12, { highway = "pedestrian", area = "yes" }, square(20.007, 10.001, 0.001)),
		},
	}, BOUNDS, WorldConfig)
	local kinds = {}
	for _, area in data.areas do
		kinds[area.kind] = true
	end
	check(kinds.water and kinds.grass and kinds.forest and kinds.plaza, "area kinds missing")
	check(#data.lines == 1 and data.lines[1].layer == "water")
	approx(data.lines[1].widthMeters, 20)
end)

test("a lake spanning two tiles is clipped to each", function()
	local lake = way(13, { natural = "water" }, square(20.005, 10.002, 0.01))
	local left = OsmParser.parse({ elements = { lake } }, BOUNDS, WorldConfig)
	local right = OsmParser.parse(
		{ elements = { lake } },
		{ south = 10, west = 20.01, north = 10.01, east = 20.02 },
		WorldConfig
	)
	check(#left.areas == 1 and #right.areas == 1)
	for i = 1, #left.areas[1].pts, 2 do
		check(left.areas[1].pts[i] <= 20.01 + 1e-12, "left tile leaks east")
	end
	for i = 1, #right.areas[1].pts, 2 do
		check(right.areas[1].pts[i] >= 20.01 - 1e-12, "right tile leaks west")
	end
end)

test("malformed responses yield an empty tile", function()
	for _, junk in { {}, { elements = 5 }, { elements = { 1, "x", { type = "way" } } } } do
		local data = OsmParser.parse(junk, BOUNDS, WorldConfig)
		check(#data.buildings == 0 and #data.lines == 0 and #data.areas == 0)
	end
	check(#OsmParser.parse(nil, BOUNDS, WorldConfig).buildings == 0)
end)

test("the Overpass query covers the tile box and is well formed", function()
	local query = OsmParser.buildQuery(BOUNDS, 25)
	check(string.find(query, "[out:json][timeout:25]", 1, true))
	check(string.find(query, "10.000000,20.000000,10.010000,20.010000", 1, true))
	check(string.find(query, "out geom;", 1, true))
	local opens = select(2, string.gsub(query, "%(", ""))
	local closes = select(2, string.gsub(query, "%)", ""))
	check(opens == closes, "unbalanced parentheses")
end)
