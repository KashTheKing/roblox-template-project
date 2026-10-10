local BuildingGeometry = require(shared.geometry["building-geometry"])
local FlatGeometry = require(shared.geometry["flat-geometry"])
local GeoProjection = require(shared.geo["geo-projection"])
local MeshData = require(shared.geometry["mesh-data"])
local MeshSet = require(shared.geometry["mesh-set"])
local TexturePixels = require(shared.geometry["texture-pixels"])
local TileGeometry = require(shared.geometry["tile-geometry"])
local WorldConfig = require(shared.configs["world-config"])

local SPM = WorldConfig.studsPerMeter

-- The default mode is "wrap"; several tests exercise the exact per-window "quads" mode explicitly.
local QUADS = table.clone(WorldConfig)
QUADS.facadeUvMode = "quads"

-- Every triangle's winding must agree with the normals stored on its vertices.
local function checkWinding(mesh)
	for t = 1, #mesh.indices, 3 do
		local a, b, c = mesh.indices[t], mesh.indices[t + 1], mesh.indices[t + 2]
		check(
			a >= 1 and a <= mesh.vertexCount and b >= 1 and b <= mesh.vertexCount and c >= 1 and c <= mesh.vertexCount,
			"index out of range"
		)
		local p = mesh.positions
		local e1x, e1y, e1z = p[b * 3 - 2] - p[a * 3 - 2], p[b * 3 - 1] - p[a * 3 - 1], p[b * 3] - p[a * 3]
		local e2x, e2y, e2z = p[c * 3 - 2] - p[a * 3 - 2], p[c * 3 - 1] - p[a * 3 - 1], p[c * 3] - p[a * 3]
		local cx, cy, cz = e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
		local n = mesh.normals
		local dot = cx * n[a * 3 - 2] + cy * n[a * 3 - 1] + cz * n[a * 3]
		check(dot > 0, "triangle " .. (t + 2) // 3 .. " faces against its normal")
	end
end

local function square(size)
	return { 0, 0, size, 0, size, size, 0, size }
end

test("a building extrudes into outward-facing walls and an upward roof", function()
	local set = MeshSet.new(60000)
	local collision = {}
	local result = BuildingGeometry.add(set, 1, square(10 * SPM), 9.6, WorldConfig, collision)
	check(result ~= nil)
	approx(result.height, 3 * WorldConfig.floorHeightMeters * SPM, 1e-6, "3 floors")
	local meshes = MeshSet.finish(set)
	local walls, roof
	for _, m in meshes do
		if m.material == "roof" then
			roof = m.mesh
		else
			walls = m.mesh
		end
	end
	check(walls and roof)
	checkWinding(walls)
	checkWinding(roof)
	check(roof.triangleCount == 2, "square roof is 2 triangles")
	for i = 1, roof.vertexCount do
		check(roof.normals[i * 3 - 1] == 1, "roof normals point up")
	end
	check(#collision == 4 * 6, "one collision record per wall")
end)

test("wall normals point away from the building centre regardless of footprint winding", function()
	for _, ring in { square(40), { 0, 0, 0, 40, 40, 40, 40, 0 } } do
		local set = MeshSet.new(60000)
		BuildingGeometry.add(set, 2, ring, 6, WorldConfig, nil)
		for _, m in MeshSet.finish(set) do
			if m.material ~= "roof" then
				for i = 1, m.mesh.vertexCount do
					local x, z = m.mesh.positions[i * 3 - 2] - 20, m.mesh.positions[i * 3] - 20
					local nx, nz = m.mesh.normals[i * 3 - 2], m.mesh.normals[i * 3]
					check(x * nx + z * nz > 0, "normal points inward")
				end
			end
		end
	end
end)

test("wall quads cover the whole facade exactly once", function()
	local set = MeshSet.new(60000)
	BuildingGeometry.add(set, 3, square(10 * SPM), 9.6, QUADS, nil)
	local walls
	for _, m in MeshSet.finish(set) do
		if m.material ~= "roof" then
			walls = m.mesh
		end
	end
	local area = 0
	for t = 1, #walls.indices, 3 do
		local a, b, c = walls.indices[t], walls.indices[t + 1], walls.indices[t + 2]
		local p = walls.positions
		local e1x, e1y, e1z = p[b * 3 - 2] - p[a * 3 - 2], p[b * 3 - 1] - p[a * 3 - 1], p[b * 3] - p[a * 3]
		local e2x, e2y, e2z = p[c * 3 - 2] - p[a * 3 - 2], p[c * 3 - 1] - p[a * 3 - 1], p[c * 3] - p[a * 3]
		local cx, cy, cz = e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
		area += math.sqrt(cx * cx + cy * cy + cz * cz) / 2
	end
	local expected = 4 * (10 * SPM) * (3 * WorldConfig.floorHeightMeters * SPM)
	approx(area, expected, expected * 1e-6)
end)

test("quad-mode UVs stay inside 0..1 so no texture wrapping is needed", function()
	local set = MeshSet.new(60000)
	BuildingGeometry.add(set, 4, square(30 * SPM), 20, QUADS, nil)
	for _, m in MeshSet.finish(set) do
		for i = 1, #m.mesh.uvs do
			local v = m.mesh.uvs[i]
			check(v >= 0 and v <= 1, "uv out of range: " .. v)
		end
	end
end)

test("wrap mode (the default) emits one quad per wall with repeating UVs", function()
	check(WorldConfig.facadeUvMode == "wrap")
	local set = MeshSet.new(60000)
	BuildingGeometry.add(set, 5, square(20 * SPM), 12.8, WorldConfig, nil)
	for _, m in MeshSet.finish(set) do
		if m.material ~= "roof" then
			check(m.mesh.vertexCount == 16, "4 walls x 4 vertices, got " .. m.mesh.vertexCount)
			local maxU = 0
			for i = 1, m.mesh.vertexCount do
				maxU = math.max(maxU, m.mesh.uvs[i * 2 - 1])
			end
			check(maxU > 1, "UVs should repeat")
		end
	end
end)

test("a huge building falls back to stretched walls instead of overflowing a mesh", function()
	local ring = {}
	for i = 0, 99 do
		local a = i / 100 * math.pi * 2
		table.insert(ring, math.cos(a) * 400 * SPM)
		table.insert(ring, math.sin(a) * 400 * SPM)
	end
	local set = MeshSet.new(WorldConfig.maxVerticesPerMesh)
	BuildingGeometry.add(set, 6, ring, 80, QUADS, nil)
	for _, m in MeshSet.finish(set) do
		check(m.mesh.vertexCount <= WorldConfig.maxVerticesPerMesh)
	end
end)

test("degenerate footprints are rejected", function()
	local set = MeshSet.new(1000)
	check(BuildingGeometry.add(set, 7, { 0, 0, 1, 1 }, 10, WorldConfig, nil) == nil)
	check(BuildingGeometry.add(set, 7, { 0, 0, 0, 0, 0, 0 }, 10, WorldConfig, nil) == nil)
end)

test("mesh sets roll over before exceeding the vertex cap", function()
	local set = MeshSet.new(2000)
	for _ = 1, 60 do
		BuildingGeometry.add(set, 6, square(30 * SPM), 12.8, QUADS, nil) -- same id => same material
	end
	local meshes = MeshSet.finish(set)
	local wallMeshes = 0
	for _, m in meshes do
		check(m.mesh.vertexCount <= 2000, "mesh exceeded cap: " .. m.mesh.vertexCount)
		if m.material == "wall" .. BuildingGeometry.variantFor(6) then
			wallMeshes += 1
		end
	end
	check(wallMeshes > 1, "expected the wall mesh to roll over")
end)

test("a straight road ribbon covers length x width", function()
	local set = MeshSet.new(60000)
	local segments = {}
	FlatGeometry.addRibbon(set, "road", { 0, 0, 100, 0 }, 10, 0.3, segments, 1)
	local mesh = MeshSet.finish(set)[1].mesh
	checkWinding(mesh)
	check(#segments == 6 and segments[5] == 10 and segments[6] == 1)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, mesh.vertexCount do
		minX, maxX = math.min(minX, mesh.positions[i * 3 - 2]), math.max(maxX, mesh.positions[i * 3 - 2])
		minZ, maxZ = math.min(minZ, mesh.positions[i * 3]), math.max(maxZ, mesh.positions[i * 3])
		approx(mesh.positions[i * 3 - 1], 0.3)
	end
	approx(maxZ - minZ, 10, 1e-9)
	check(minX >= -5 - 1e-9 and maxX <= 105 + 1e-9, "round caps stay within half a width")
end)

test("a bent road gets a joint so the outside corner has no gap", function()
	local straight = MeshSet.new(60000)
	FlatGeometry.addRibbon(straight, "road", { 0, 0, 50, 0, 100, 0 }, 10, 0, nil, 1)
	local bent = MeshSet.new(60000)
	FlatGeometry.addRibbon(bent, "road", { 0, 0, 50, 0, 50, 50 }, 10, 0, nil, 1)
	local s = MeshSet.finish(straight)[1].mesh
	local b = MeshSet.finish(bent)[1].mesh
	check(b.triangleCount > s.triangleCount, "the bend should add a joint disc")
	checkWinding(b)
end)

test("filled areas triangulate to the right area", function()
	local set = MeshSet.new(60000)
	FlatGeometry.addArea(set, "grass", { 0, 0, 20, 0, 20, 10, 10, 10, 10, 20, 0, 20 }, 0.06)
	local mesh = MeshSet.finish(set)[1].mesh
	checkWinding(mesh)
	check(mesh.triangleCount == 4)
end)

test("recentering moves the bounding box centre to the origin", function()
	local mesh = MeshData.new()
	MeshData.addVertex(mesh, 10, 0, 100, 0, 1, 0, 0, 0)
	MeshData.addVertex(mesh, 30, 4, 140, 0, 1, 0, 0, 0)
	local cx, cy, cz = MeshData.recenter(mesh)
	approx(cx, 20)
	approx(cy, 2)
	approx(cz, 120)
	approx(mesh.positions[1], -10)
	approx(mesh.positions[6], 20)
end)

test("degenerate triangles are skipped", function()
	local mesh = MeshData.new()
	local a = MeshData.addVertex(mesh, 0, 0, 0, 0, 1, 0, 0, 0)
	local b = MeshData.addVertex(mesh, 1, 0, 0, 0, 1, 0, 0, 0)
	local c = MeshData.addVertex(mesh, 2, 0, 0, 0, 1, 0, 0, 0)
	MeshData.addTriangle(mesh, a, b, c, 0, 1, 0)
	check(mesh.triangleCount == 0)
end)

test("every material has a texture with the right size and opaque pixels", function()
	local materials = TexturePixels.materials()
	check(#materials == TexturePixels.WALL_VARIANTS + 6, "got " .. #materials .. " materials")
	for _, name in materials do
		local image = TexturePixels.generate(name)
		check(buffer.len(image.data) == image.width * image.height * 4, name .. " buffer size")
		for p = 0, image.width * image.height - 1 do
			check(buffer.readu8(image.data, p * 4 + 3) == 255, name .. " must be opaque")
		end
		check(#TexturePixels.baseColor(name) == 3)
	end
	check(BuildingGeometry.WALL_VARIANTS == TexturePixels.WALL_VARIANTS, "variant counts must match")
end)

test("facade textures are vertically symmetric", function()
	local image = TexturePixels.generate("wall1")
	local function px(x, y, channel)
		return buffer.readu8(image.data, (y * image.width + x) * 4 + channel)
	end
	-- window frame rows mirror each other (noise aside, the frame pixels are flat colours)
	check(px(32, 14, 0) == px(32, 49, 0), "window frame should mirror top/bottom")
end)

test("tile geometry end to end", function()
	local origin = GeoProjection.newOrigin(40.758, -73.9855, SPM)
	local cx, cz = GeoProjection.toLocal(origin, 40.7585, -73.985)
	local lon, lat = -73.985, 40.7585
	local data = {
		buildings = {
			{
				id = 10,
				kind = "yes",
				heightMeters = 30,
				pts = { lon, lat, lon + 0.0002, lat, lon + 0.0002, lat + 0.0001, lon, lat + 0.0001 },
			},
			{
				id = 11,
				kind = "house",
				heightMeters = 7,
				pts = { lon + 0.001, lat, lon + 0.0011, lat, lon + 0.0011, lat + 0.0001, lon + 0.001, lat + 0.0001 },
			},
		},
		lines = {
			{
				id = 20,
				kind = "residential",
				layer = "road",
				widthMeters = 7,
				pts = { lon - 0.001, lat - 0.0003, lon + 0.002, lat - 0.0003 },
			},
			{
				id = 21,
				kind = "footway",
				layer = "road",
				widthMeters = 2.5,
				pts = { lon - 0.001, lat - 0.0004, lon + 0.002, lat - 0.0004 },
			},
			{
				id = 22,
				kind = "river",
				layer = "water",
				widthMeters = 20,
				pts = { lon - 0.001, lat - 0.001, lon + 0.002, lat - 0.001 },
			},
		},
		areas = {
			{
				id = 30,
				kind = "grass",
				pts = { lon, lat + 0.0005, lon + 0.0005, lat + 0.0005, lon + 0.0005, lat + 0.001, lon, lat + 0.001 },
			},
			{
				id = 31,
				kind = "water",
				pts = { lon, lat + 0.0012, lon + 0.0005, lat + 0.0012, lon + 0.0005, lat + 0.0016, lon, lat + 0.0016 },
			},
		},
	}
	local result = TileGeometry.build(data, origin, cx, cz, WorldConfig)
	check(result.stats.buildings == 2)
	check(result.stats.triangles > 0)
	check(#result.walls == 8 * 6, "two buildings, four walls each")
	check(#result.segments % 6 == 0 and #result.segments > 0)
	local materials = {}
	for _, m in result.meshes do
		materials[m.material] = true
		check(m.mesh.vertexCount <= WorldConfig.maxVerticesPerMesh)
		checkWinding(m.mesh)
	end
	check(
		materials.roof and materials.road and materials.path and materials.water and materials.grass,
		"expected materials"
	)
	-- everything is expressed relative to the anchor, so numbers stay small
	for _, m in result.meshes do
		for i = 1, #m.mesh.positions, 3 do
			check(
				math.abs(m.mesh.positions[i]) < 5000 and math.abs(m.mesh.positions[i + 2]) < 5000,
				"coordinates should be tile-local"
			)
		end
	end
end)

test("collision can be switched off", function()
	local cfg = table.clone(WorldConfig)
	cfg.collisionMode = "none"
	local origin = GeoProjection.newOrigin(0, 0, SPM)
	local data = {
		buildings = { { id = 1, kind = "yes", heightMeters = 9, pts = { 0, 0, 0.0001, 0, 0.0001, 0.0001, 0, 0.0001 } } },
		lines = {},
		areas = {},
	}
	check(#TileGeometry.build(data, origin, 0, 0, cfg).walls == 0)
end)
