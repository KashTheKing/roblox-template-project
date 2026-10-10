local Clip = require(shared.geometry.clip)
local Polygon = require(shared.geometry.polygon)

local function trianglesArea(poly, tris)
	local total = 0
	for t = 1, #tris, 3 do
		local a, b, c = tris[t], tris[t + 1], tris[t + 2]
		local ax, ay = poly[a * 2 - 1], poly[a * 2]
		local bx, by = poly[b * 2 - 1], poly[b * 2]
		local cx, cy = poly[c * 2 - 1], poly[c * 2]
		local area2 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
		check(area2 > 0, "every triangle must be counter-clockwise")
		total += area2 / 2
	end
	return total
end

test("signed area is positive for counter-clockwise polygons", function()
	approx(Polygon.signedArea({ 0, 0, 4, 0, 4, 3, 0, 3 }), 12)
	approx(Polygon.signedArea({ 0, 0, 0, 3, 4, 3, 4, 0 }), -12)
end)

test("cleanRing drops the closing point and duplicates", function()
	local ring = Polygon.cleanRing({ 0, 0, 4, 0, 4, 0, 4, 3, 0, 3, 0, 0 }, 1e-9)
	check(#ring == 8, "expected 4 points, got " .. #ring // 2)
end)

test("triangulating a square gives two triangles covering it", function()
	local poly = { 0, 0, 4, 0, 4, 4, 0, 4 }
	local tris = Polygon.triangulate(poly)
	check(#tris == 6)
	approx(trianglesArea(poly, tris), 16)
end)

test("clockwise input still yields counter-clockwise triangles", function()
	local poly = { 0, 0, 0, 4, 4, 4, 4, 0 }
	local tris = Polygon.triangulate(poly)
	approx(trianglesArea(poly, tris), 16)
end)

test("concave L shape is covered exactly", function()
	local poly = { 0, 0, 6, 0, 6, 2, 2, 2, 2, 6, 0, 6 }
	local tris = Polygon.triangulate(poly)
	check(#tris == 12, "L shape has 6 vertices => 4 triangles")
	approx(trianglesArea(poly, tris), Polygon.signedArea(poly))
end)

test("a comb polygon with many concavities is covered exactly", function()
	local poly = { 0, 0, 10, 0, 10, 5, 8, 5, 8, 2, 6, 2, 6, 5, 4, 5, 4, 2, 2, 2, 2, 5, 0, 5 }
	local tris = Polygon.triangulate(poly)
	approx(trianglesArea(poly, tris), Polygon.signedArea(poly), 1e-9)
end)

test("collinear vertices do not break triangulation", function()
	local poly = { 0, 0, 2, 0, 4, 0, 4, 4, 0, 4 }
	local tris = Polygon.triangulate(poly)
	approx(trianglesArea(poly, tris), 16)
end)

test("self-intersecting input terminates", function()
	local bowtie = { 0, 0, 4, 4, 4, 0, 0, 4 }
	local tris = Polygon.triangulate(bowtie)
	check(#tris % 3 == 0)
end)

test("degenerate input returns nothing", function()
	check(#Polygon.triangulate({ 0, 0, 1, 1 }) == 0)
	check(#Polygon.triangulate({}) == 0)
end)

test("circle-like polygon with 64 points triangulates", function()
	local poly = {}
	for i = 0, 63 do
		local a = i / 64 * math.pi * 2
		table.insert(poly, math.cos(a) * 10)
		table.insert(poly, math.sin(a) * 10)
	end
	local tris = Polygon.triangulate(poly)
	check(#tris == 62 * 3)
	approx(trianglesArea(poly, tris), Polygon.signedArea(poly), 1e-6)
end)

test("polygon clipping keeps the overlap", function()
	local clipped = Clip.polygonToRect({ -2, -2, 2, -2, 2, 2, -2, 2 }, 0, 0, 10, 10)
	approx(math.abs(Polygon.signedArea(clipped)), 4)
end)

test("polygon fully outside clips to nothing and fully inside is unchanged", function()
	check(#Clip.polygonToRect({ 20, 20, 30, 20, 30, 30 }, 0, 0, 10, 10) == 0)
	local inside = Clip.polygonToRect({ 1, 1, 3, 1, 3, 3, 1, 3 }, 0, 0, 10, 10)
	approx(math.abs(Polygon.signedArea(inside)), 4)
end)

test("polyline clipping splits a line that leaves and re-enters", function()
	local pieces = Clip.polylineToRect({ -5, 5, 5, 5, 5, 15, 8, 15, 8, 5, 20, 5 }, 0, 0, 10, 10)
	-- enters at x=0, runs to (5,5), exits the top at (5,10); re-enters at (8,10), ends at the right edge
	check(#pieces == 2, "expected 2 pieces, got " .. #pieces)
	approx(pieces[1][1], 0)
	approx(pieces[1][#pieces[1] - 1], 5)
	approx(pieces[1][#pieces[1]], 10)
	approx(pieces[2][1], 8)
	approx(pieces[2][#pieces[2] - 1], 10)
end)

test("polyline entirely outside is dropped", function()
	check(#Clip.polylineToRect({ -5, -5, -1, -1 }, 0, 0, 10, 10) == 0)
end)
