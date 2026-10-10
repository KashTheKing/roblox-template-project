--!strict
-- Flat, upward-facing surfaces: roads/paths/rivers (polylines with a width) and filled areas such as
-- parks and lakes. Coordinates are flat { x1, z1, x2, z2, ... } arrays in local studs.

local MeshData = require(script.Parent["mesh-data"])
local MeshSet = require(script.Parent["mesh-set"])
local Polygon = require(script.Parent.polygon)

local FlatGeometry = {}

local DISC_SIDES = 8
-- Skip the joint disc when the path hardly turns (dot product of the two directions above this).
local STRAIGHT_DOT = 0.985

local function addDisc(mesh: MeshData.MeshData, cx: number, y: number, cz: number, radius: number)
	local center = MeshData.addVertex(mesh, cx, y, cz, 0, 1, 0, 0.5, 0.5)
	local first = 0
	local prev = 0
	for s = 0, DISC_SIDES - 1 do
		local angle = (s / DISC_SIDES) * math.pi * 2
		local v =
			MeshData.addVertex(mesh, cx + math.cos(angle) * radius, y, cz + math.sin(angle) * radius, 0, 1, 0, 0.5, 0.5)
		if s == 0 then
			first = v
		else
			MeshData.addTriangle(mesh, center, prev, v, 0, 1, 0)
		end
		prev = v
	end
	MeshData.addTriangle(mesh, center, prev, first, 0, 1, 0)
end

-- Adds a ribbon of `width` studs along the polyline. When `segmentsOut` is given, each segment is appended
-- as x1, z1, x2, z2, width, kindCode (used by the part-based fallback renderer).
function FlatGeometry.addRibbon(
	set: MeshSet.MeshSet,
	material: string,
	pts: { number },
	width: number,
	y: number,
	segmentsOut: { number }?,
	kindCode: number?
)
	local n = #pts // 2
	if n < 2 then
		return
	end
	local half = width / 2
	-- Worst case: 4 vertices per segment plus a joint disc per vertex.
	local mesh = MeshSet.get(set, material, n * 4 + n * (DISC_SIDES + 1))

	local prevDx, prevDz = 0, 0
	for i = 1, n - 1 do
		local x1, z1 = pts[i * 2 - 1], pts[i * 2]
		local x2, z2 = pts[i * 2 + 1], pts[i * 2 + 2]
		local dx, dz = x2 - x1, z2 - z1
		local length = math.sqrt(dx * dx + dz * dz)
		if length > 0.01 then
			dx, dz = dx / length, dz / length
			local px, pz = -dz * half, dx * half -- left-hand perpendicular scaled to half width
			local v1 = MeshData.addVertex(mesh, x1 + px, y, z1 + pz, 0, 1, 0, 0.5, 0.5)
			local v2 = MeshData.addVertex(mesh, x2 + px, y, z2 + pz, 0, 1, 0, 0.5, 0.5)
			local v3 = MeshData.addVertex(mesh, x2 - px, y, z2 - pz, 0, 1, 0, 0.5, 0.5)
			local v4 = MeshData.addVertex(mesh, x1 - px, y, z1 - pz, 0, 1, 0, 0.5, 0.5)
			MeshData.addQuad(mesh, v1, v2, v3, v4, 0, 1, 0)

			if segmentsOut ~= nil then
				table.insert(segmentsOut, x1)
				table.insert(segmentsOut, z1)
				table.insert(segmentsOut, x2)
				table.insert(segmentsOut, z2)
				table.insert(segmentsOut, width)
				table.insert(segmentsOut, kindCode or 1)
			end

			-- Fill the wedge on the outside of a bend (and round off the start of the road).
			if i == 1 or dx * prevDx + dz * prevDz < STRAIGHT_DOT then
				addDisc(mesh, x1, y, z1, half)
			end
			prevDx, prevDz = dx, dz
		end
	end
	addDisc(mesh, pts[n * 2 - 1], y, pts[n * 2], half)
end

function FlatGeometry.addArea(set: MeshSet.MeshSet, material: string, pts: { number }, y: number)
	local ring = Polygon.cleanRing(pts, 0.05)
	local n = #ring // 2
	if n < 3 then
		return
	end
	local mesh = MeshSet.get(set, material, n)
	local base = mesh.vertexCount
	for i = 1, n do
		MeshData.addVertex(mesh, ring[i * 2 - 1], y, ring[i * 2], 0, 1, 0, 0.5, 0.5)
	end
	local tris = Polygon.triangulate(ring)
	for t = 1, #tris, 3 do
		MeshData.addTriangle(mesh, base + tris[t], base + tris[t + 1], base + tris[t + 2], 0, 1, 0)
	end
end

return FlatGeometry
