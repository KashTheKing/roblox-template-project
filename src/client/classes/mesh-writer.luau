--!strict
-- Converts a MeshData into an EditableMesh and then into a textured, non-colliding MeshPart.
-- EditableMeshes do not replicate, so this runs on the client that will look at the result.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshData = require(ReplicatedStorage.shared.geometry["mesh-data"])
local TextureLibrary = require(ReplicatedStorage.client.classes["texture-library"])

local MeshWriter = {}

local supported: boolean? = nil
local consecutiveFailures = 0
local MAX_CONSECUTIVE_FAILURES = 3

-- True if this experience is allowed to create EditableMeshes.
function MeshWriter.isSupported(): boolean
	if supported == nil then
		local ok, err = pcall(function()
			local probe = AssetService:CreateEditableMesh()
			probe:Destroy()
		end)
		supported = ok
		if not ok then
			warn(`[mesh] EditableMesh is not available here ({err}). Using the part-based fallback.`)
		end
	end
	return supported == true
end

local function buildEditableMesh(data: MeshData.MeshData, flipWinding: boolean): any
	local mesh = AssetService:CreateEditableMesh()
	local count = data.vertexCount
	local positions, normals, uvs = data.positions, data.normals, data.uvs

	local vertexIds = table.create(count, 0)
	local normalIds = table.create(count, 0)
	local uvIds = table.create(count, 0)
	for i = 1, count do
		local p, uv = i * 3, i * 2
		vertexIds[i] = mesh:AddVertex(Vector3.new(positions[p - 2], positions[p - 1], positions[p]))
		normalIds[i] = mesh:AddNormal(Vector3.new(normals[p - 2], normals[p - 1], normals[p]))
		uvIds[i] = mesh:AddUV(Vector2.new(uvs[uv - 1], uvs[uv]))
	end

	local indices = data.indices
	for t = 1, #indices, 3 do
		local a, b, c = indices[t], indices[t + 1], indices[t + 2]
		if flipWinding then
			b, c = c, b
		end
		local face = mesh:AddTriangle(vertexIds[a], vertexIds[b], vertexIds[c])
		mesh:SetFaceNormals(face, { normalIds[a], normalIds[b], normalIds[c] })
		mesh:SetFaceUVs(face, { uvIds[a], uvIds[b], uvIds[c] })
	end
	return mesh
end

local function createMeshPart(mesh: any, doubleSided: boolean): MeshPart
	local content = Content.fromObject(mesh)
	if doubleSided then
		-- Not every engine version accepts DoubleSided; fall through to the plain call if it throws.
		local ok, part = pcall(function()
			return AssetService:CreateMeshPartAsync(content, { DoubleSided = true })
		end)
		if ok then
			return part
		end
	end
	return AssetService:CreateMeshPartAsync(content)
end

-- Yields. The mesh is recentred first, so the returned (x, y, z) offset is where the MeshPart's centre
-- must be placed (relative to the tile anchor) to put every vertex where it was authored.
-- Returns nil for the part when creation fails.
function MeshWriter.createMeshPart(
	data: MeshData.MeshData,
	material: string,
	cfg: any
): (MeshPart?, number, number, number)
	local cx, cy, cz = MeshData.recenter(data)

	local ok, result = pcall(function()
		local mesh = buildEditableMesh(data, cfg.flipTriangleWinding)
		local part = createMeshPart(mesh, cfg.doubleSidedMeshes)
		if cfg.keepEditableMeshes then
			mesh.Parent = part
		else
			mesh:Destroy()
		end
		return part
	end)

	if not ok then
		consecutiveFailures += 1
		warn(`[mesh] failed to build the {material} mesh: {result}`)
		if consecutiveFailures >= MAX_CONSECUTIVE_FAILURES then
			supported = false
		end
		return nil, cx, cy, cz
	end
	consecutiveFailures = 0

	local part: MeshPart = result
	part.Name = material
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = string.sub(material, 1, 4) == "wall" or material == "roof"
	part.Material = Enum.Material.SmoothPlastic

	local texture = TextureLibrary.get(material)
	local textured = false
	if texture ~= nil then
		textured = pcall(function()
			(part :: any).TextureContent = texture
		end)
	end
	if not textured then
		part.Color = TextureLibrary.fallbackColor(material)
	end

	return part, cx, cy, cz
end

return MeshWriter
