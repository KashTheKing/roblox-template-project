--!strict
-- Plain-table triangle mesh that the geometry generators write into and the client turns into an
-- EditableMesh. Keeping it free of Roblox types makes the generators testable outside Roblox.

export type MeshData = {
	positions: { number }, -- x, y, z per vertex
	normals: { number }, -- x, y, z per vertex
	uvs: { number }, -- u, v per vertex
	indices: { number }, -- three 1-based vertex indices per triangle
	vertexCount: number,
	triangleCount: number,
}

local MeshData = {}

function MeshData.new(): MeshData
	return { positions = {}, normals = {}, uvs = {}, indices = {}, vertexCount = 0, triangleCount = 0 }
end

-- Returns the 1-based index of the new vertex.
function MeshData.addVertex(
	mesh: MeshData,
	x: number,
	y: number,
	z: number,
	nx: number,
	ny: number,
	nz: number,
	u: number,
	v: number
): number
	local count = mesh.vertexCount + 1
	mesh.vertexCount = count
	local p = count * 3
	mesh.positions[p - 2], mesh.positions[p - 1], mesh.positions[p] = x, y, z
	mesh.normals[p - 2], mesh.normals[p - 1], mesh.normals[p] = nx, ny, nz
	mesh.uvs[count * 2 - 1], mesh.uvs[count * 2] = u, v
	return count
end

-- Adds a triangle wound counter-clockwise when seen from the side the normal (nx, ny, nz) points to.
-- Degenerate triangles are skipped.
function MeshData.addTriangle(mesh: MeshData, a: number, b: number, c: number, nx: number, ny: number, nz: number)
	local pos = mesh.positions
	local ax, ay, az = pos[a * 3 - 2], pos[a * 3 - 1], pos[a * 3]
	local e1x, e1y, e1z = pos[b * 3 - 2] - ax, pos[b * 3 - 1] - ay, pos[b * 3] - az
	local e2x, e2y, e2z = pos[c * 3 - 2] - ax, pos[c * 3 - 1] - ay, pos[c * 3] - az
	local cx = e1y * e2z - e1z * e2y
	local cy = e1z * e2x - e1x * e2z
	local cz = e1x * e2y - e1y * e2x
	if cx * cx + cy * cy + cz * cz < 1e-12 then
		return
	end
	if cx * nx + cy * ny + cz * nz < 0 then
		b, c = c, b
	end
	local idx = mesh.indices
	local n = mesh.triangleCount * 3
	idx[n + 1], idx[n + 2], idx[n + 3] = a, b, c
	mesh.triangleCount += 1
end

function MeshData.addQuad(
	mesh: MeshData,
	a: number,
	b: number,
	c: number,
	d: number,
	nx: number,
	ny: number,
	nz: number
)
	MeshData.addTriangle(mesh, a, b, c, nx, ny, nz)
	MeshData.addTriangle(mesh, a, c, d, nx, ny, nz)
end

-- Moves the mesh so the centre of its bounding box is the origin and returns the offset that was removed.
-- Roblox positions a MeshPart relative to that centre, so this keeps placement unambiguous.
function MeshData.recenter(mesh: MeshData): (number, number, number)
	local count = mesh.vertexCount
	if count == 0 then
		return 0, 0, 0
	end
	local pos = mesh.positions
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for i = 1, count do
		local x, y, z = pos[i * 3 - 2], pos[i * 3 - 1], pos[i * 3]
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minY, maxY = math.min(minY, y), math.max(maxY, y)
		minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
	end
	local cx, cy, cz = (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2
	for i = 1, count do
		pos[i * 3 - 2] -= cx
		pos[i * 3 - 1] -= cy
		pos[i * 3] -= cz
	end
	return cx, cy, cz
end

return MeshData
