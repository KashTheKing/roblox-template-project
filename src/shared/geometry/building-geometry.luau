--!strict
-- Extrudes a building footprint into window-textured walls plus a flat roof.
-- Footprints are flat { x1, z1, x2, z2, ... } arrays in local studs.

local MeshData = require(script.Parent["mesh-data"])
local MeshSet = require(script.Parent["mesh-set"])
local Polygon = require(script.Parent.polygon)

local BuildingGeometry = {}

-- Facade textures are inset by half a texel so bilinear filtering never samples the neighbouring tile.
local UV_INSET = 0.5 / 64
local ROOF_MATERIAL = "roof"
local WALL_VARIANTS = 6

BuildingGeometry.WALL_VARIANTS = WALL_VARIANTS

function BuildingGeometry.wallMaterial(variant: number): string
	return "wall" .. variant
end

-- Which of the facade textures a building uses (stable per OSM id).
function BuildingGeometry.variantFor(id: number): number
	return (id % WALL_VARIANTS) + 1
end

export type Result = {
	height: number, -- studs
	variant: number,
	ring: { number }, -- cleaned, counter-clockwise footprint
}

-- Adds one building to `set`. When `collision` is given, one record per wall edge is appended to it:
-- x1, z1, x2, z2, height, variant. Returns nil if the footprint is unusable.
function BuildingGeometry.add(
	set: MeshSet.MeshSet,
	id: number,
	footprint: { number },
	heightMeters: number,
	cfg: any,
	collision: { number }?
): Result?
	local ring = Polygon.cleanRing(footprint, 0.05)
	local n = #ring // 2
	if n < 3 then
		return nil
	end
	if Polygon.signedArea(ring) < 0 then
		ring = Polygon.reversed(ring)
	end

	local spm: number = cfg.studsPerMeter
	local floorStuds: number = cfg.floorHeightMeters * spm
	local bayStuds: number = cfg.bayWidthMeters * spm
	local levels = math.max(1, math.floor(heightMeters / cfg.floorHeightMeters + 0.5))
	local height = levels * floorStuds
	local variant = BuildingGeometry.variantFor(id)
	local wallMaterial = BuildingGeometry.wallMaterial(variant)

	-- Work out how many vertices this building needs so it always lands in a single mesh.
	local perEdgeBays: { number } = table.create(n, 1)
	local quadMode = cfg.facadeUvMode == "quads"
	local wallVertices = 0
	for i = 1, n do
		local j = if i == n then 1 else i + 1
		local dx, dz = ring[j * 2 - 1] - ring[i * 2 - 1], ring[j * 2] - ring[i * 2]
		local length = math.sqrt(dx * dx + dz * dz)
		local bays = math.clamp(math.floor(length / bayStuds + 0.5), 1, 80)
		perEdgeBays[i] = bays
		wallVertices += bays * levels * 4
	end
	if quadMode and wallVertices > set.maxVertices * 0.4 then
		-- Huge building: one stretched quad per wall instead of one per window.
		quadMode = false
		wallVertices = n * 4
	elseif not quadMode then
		wallVertices = n * 4
	end

	local walls = MeshSet.get(set, wallMaterial, wallVertices)
	local roofs = MeshSet.get(set, ROOF_MATERIAL, n)

	for i = 1, n do
		local j = if i == n then 1 else i + 1
		local x1, z1 = ring[i * 2 - 1], ring[i * 2]
		local x2, z2 = ring[j * 2 - 1], ring[j * 2]
		local dx, dz = x2 - x1, z2 - z1
		local length = math.sqrt(dx * dx + dz * dz)
		if length > 0.05 then
			-- Outward normal for a counter-clockwise ring (x, z plane): rotate the edge direction clockwise.
			local nx, nz = dz / length, -dx / length
			local bays = perEdgeBays[i]

			if quadMode then
				for b = 0, bays - 1 do
					local t0, t1 = b / bays, (b + 1) / bays
					local ax, az = x1 + dx * t0, z1 + dz * t0
					local bx, bz = x1 + dx * t1, z1 + dz * t1
					for f = 0, levels - 1 do
						local y0, y1 = f * floorStuds, (f + 1) * floorStuds
						local v1 = MeshData.addVertex(walls, ax, y0, az, nx, 0, nz, UV_INSET, UV_INSET)
						local v2 = MeshData.addVertex(walls, bx, y0, bz, nx, 0, nz, 1 - UV_INSET, UV_INSET)
						local v3 = MeshData.addVertex(walls, bx, y1, bz, nx, 0, nz, 1 - UV_INSET, 1 - UV_INSET)
						local v4 = MeshData.addVertex(walls, ax, y1, az, nx, 0, nz, UV_INSET, 1 - UV_INSET)
						MeshData.addQuad(walls, v1, v2, v3, v4, nx, 0, nz)
					end
				end
			else
				local uMax = if cfg.facadeUvMode == "wrap" then bays else 1
				local vMax = if cfg.facadeUvMode == "wrap" then levels else 1
				local v1 = MeshData.addVertex(walls, x1, 0, z1, nx, 0, nz, 0, 0)
				local v2 = MeshData.addVertex(walls, x2, 0, z2, nx, 0, nz, uMax, 0)
				local v3 = MeshData.addVertex(walls, x2, height, z2, nx, 0, nz, uMax, vMax)
				local v4 = MeshData.addVertex(walls, x1, height, z1, nx, 0, nz, 0, vMax)
				MeshData.addQuad(walls, v1, v2, v3, v4, nx, 0, nz)
			end

			if collision ~= nil then
				table.insert(collision, x1)
				table.insert(collision, z1)
				table.insert(collision, x2)
				table.insert(collision, z2)
				table.insert(collision, height)
				table.insert(collision, variant)
			end
		end
	end

	-- Roof: triangulated footprint, flat colour (every roof vertex samples the centre of the roof texture).
	local base = roofs.vertexCount
	for i = 1, n do
		MeshData.addVertex(roofs, ring[i * 2 - 1], height, ring[i * 2], 0, 1, 0, 0.5, 0.5)
	end
	local tris = Polygon.triangulate(ring)
	for t = 1, #tris, 3 do
		MeshData.addTriangle(roofs, base + tris[t], base + tris[t + 1], base + tris[t + 2], 0, 1, 0)
	end

	return { height = height, variant = variant, ring = ring }
end

return BuildingGeometry
