--!strict
-- Collects geometry per material and starts a fresh mesh whenever the current one would exceed the
-- vertex cap, so every finished mesh stays safely under Roblox's EditableMesh limit.

local MeshData = require(script.Parent["mesh-data"])

export type MeshData = MeshData.MeshData

export type FinishedMesh = { material: string, mesh: MeshData }

export type MeshSet = {
	maxVertices: number,
	current: { [string]: MeshData },
	finished: { FinishedMesh },
}

local MeshSet = {}

function MeshSet.new(maxVertices: number): MeshSet
	return { maxVertices = maxVertices, current = {}, finished = {} }
end

-- Returns the mesh for `material` that has room for `vertexBudget` more vertices.
function MeshSet.get(set: MeshSet, material: string, vertexBudget: number): MeshData
	local mesh = set.current[material]
	if mesh ~= nil and (mesh.vertexCount == 0 or mesh.vertexCount + vertexBudget <= set.maxVertices) then
		return mesh
	end
	if mesh ~= nil then
		table.insert(set.finished, { material = material, mesh = mesh })
	end
	local fresh = MeshData.new()
	set.current[material] = fresh
	return fresh
end

-- Flushes everything and returns all non-empty meshes.
function MeshSet.finish(set: MeshSet): { FinishedMesh }
	for material, mesh in set.current do
		if mesh.triangleCount > 0 then
			table.insert(set.finished, { material = material, mesh = mesh })
		end
	end
	set.current = {}
	local result: { FinishedMesh } = {}
	for _, entry in set.finished do
		if entry.mesh.triangleCount > 0 then
			table.insert(result, entry)
		end
	end
	set.finished = {}
	return result
end

return MeshSet
