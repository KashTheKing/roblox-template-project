local GeoProjection = require(shared.geo["geo-projection"])
local TileMath = require(shared.geo["tile-math"])

local SPM = 1 / 0.28

test("origin projects to the local origin", function()
	local origin = GeoProjection.newOrigin(40.758, -73.9855, SPM)
	local x, z = GeoProjection.toLocal(origin, 40.758, -73.9855)
	approx(x, 0, 1e-9)
	approx(z, 0, 1e-9)
end)

test("north is -Z and east is +X", function()
	local origin = GeoProjection.newOrigin(40, -73, SPM)
	local _, zNorth = GeoProjection.toLocal(origin, 40.001, -73)
	local xEast = GeoProjection.toLocal(origin, 40, -72.999)
	check(zNorth < 0, "north should have negative z")
	check(xEast > 0, "east should have positive x")
end)

test("0.001 degrees of latitude is about 111 m", function()
	local origin = GeoProjection.newOrigin(0, 0, 1)
	local _, z = GeoProjection.toLocal(origin, 0.001, 0)
	approx(math.abs(z), 110.57, 0.2)
	local polar = GeoProjection.newOrigin(60, 0, 1)
	local _, z60 = GeoProjection.toLocal(polar, 60.001, 0)
	approx(math.abs(z60), 111.4, 0.3)
end)

test("longitude shrinks with the cosine of latitude", function()
	local origin = GeoProjection.newOrigin(60, 10, 1)
	local x = GeoProjection.toLocal(origin, 60, 10.001)
	approx(x, 55.8, 0.3)
end)

test("toGeo inverts toLocal", function()
	local origin = GeoProjection.newOrigin(-33.8568, 151.2153, SPM)
	local x, z = GeoProjection.toLocal(origin, -33.8601, 151.2201)
	local lat, lon = GeoProjection.toGeo(origin, x, z)
	approx(lat, -33.8601, 1e-9)
	approx(lon, 151.2201, 1e-9)
end)

test("projection handles the antimeridian", function()
	local origin = GeoProjection.newOrigin(0, 179.999, 1)
	local x = GeoProjection.toLocal(origin, 0, -179.999)
	check(x > 0 and x < 500, "crossing +180 should be a short hop east, got " .. x)
end)

test("a tile always contains the point it was computed from", function()
	local size = 0.0025
	for _, p in { { 40.758, -73.9855 }, { -33.8568, 151.2153 }, { 0, 0 }, { 89.9, 179.99 }, { -89.9, -179.99 } } do
		local ix, iy = TileMath.tileIndex(p[1], p[2], size)
		local b = TileMath.bounds(ix, iy, size)
		check(p[1] >= b.south - 1e-9 and p[1] < b.north + 1e-9, "lat outside tile for " .. p[1])
		check(p[2] >= b.west - 1e-9 and p[2] < b.east + 1e-9, "lon outside tile for " .. p[2])
		check(TileMath.isValid(ix, iy, size), "tile should be valid")
	end
end)

test("tile size is about 277 m north-south", function()
	local b = TileMath.bounds(10, 36000, 0.0025) -- iy 36000 is lat 0
	local origin = GeoProjection.newOrigin(b.south, b.west, 1)
	local _, z = GeoProjection.toLocal(origin, b.north, b.west)
	approx(math.abs(z), 276.4, 1)
end)

test("tile validation rejects junk", function()
	local size = 0.0025
	check(not TileMath.isValid(1.5, 2, size))
	check(not TileMath.isValid(-1, 2, size))
	check(not TileMath.isValid("1", 2, size))
	check(not TileMath.isValid(0 / 0, 2, size))
	check(not TileMath.isValid(1e9, 2, size))
	check(not TileMath.isValid(1, 1e9, size))
end)

test("tiles around a point are nearest first and complete", function()
	local list = TileMath.around(100, 100, 2, 0.0025)
	check(#list == 25, "expected 25 tiles, got " .. #list)
	check(list[1].ix == 100 and list[1].iy == 100, "own tile should come first")
	local seen = {}
	for _, t in list do
		seen[TileMath.key(t.ix, t.iy)] = true
	end
	check(seen["98:98"] and seen["102:102"] and seen["100:98"], "corners and edges present")
end)

test("tiles wrap around the antimeridian but not the poles", function()
	local size = 0.0025
	local lonCount = TileMath.tilesPerLon(size)
	local list = TileMath.around(0, 5, 1, size)
	local sawWrapped = false
	for _, t in list do
		if t.ix == lonCount - 1 then
			sawWrapped = true
		end
	end
	check(sawWrapped, "tile -1 should wrap to the last column")
	check(#TileMath.around(5, 0, 1, size) == 6, "bottom edge has no row below")
	check(TileMath.distance(0, 5, lonCount - 1, 5, size) == 1, "wrapped distance is 1")
end)
