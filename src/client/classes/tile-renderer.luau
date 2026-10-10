--!strict
-- Owns the Instances for one map tile: a ground slab (created instantly, so players never fall into the
-- void while data loads) plus, once the tile's data arrives, textured meshes and invisible wall colliders.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GeoProjection = require(ReplicatedStorage.shared.geo["geo-projection"])
local MeshWriter = require(ReplicatedStorage.client.classes["mesh-writer"])
local OsmParser = require(ReplicatedStorage.shared.osm["osm-parser"])
local TextureLibrary = require(ReplicatedStorage.client.classes["texture-library"])
local TileGeometry = require(ReplicatedStorage.shared.geometry["tile-geometry"])
local TileMath = require(ReplicatedStorage.shared.geo["tile-math"])
local WorldConfig = require(ReplicatedStorage.shared.configs["world-config"])

export type Handle = {
	key: string,
	ix: number,
	iy: number,
	folder: Folder,
	anchorX: number,
	anchorZ: number,
	destroyed: boolean,
	populated: boolean,
}

local TileRenderer = {}

local GROUND_COLOR = Color3.fromRGB(118, 122, 118)
local GROUND_THICKNESS = 4
local INSTANCES_PER_FRAME = 150

-- Instant: creates the tile folder and its ground slab.
function TileRenderer.create(parent: Instance, ix: number, iy: number, origin: GeoProjection.Origin): Handle
	local bounds = TileMath.bounds(ix, iy, WorldConfig.tileSizeDegrees)
	local westX, northZ = GeoProjection.toLocal(origin, bounds.north, bounds.west)
	local eastX, southZ = GeoProjection.toLocal(origin, bounds.south, bounds.east)
	local anchorX, anchorZ = (westX + eastX) / 2, (northZ + southZ) / 2

	local folder = Instance.new("Folder")
	folder.Name = TileMath.key(ix, iy)

	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.CanTouch = false
	ground.Material = Enum.Material.Concrete
	ground.Color = GROUND_COLOR
	-- Slightly oversized so neighbouring slabs overlap instead of leaving hairline gaps.
	ground.Size = Vector3.new(eastX - westX + 1, GROUND_THICKNESS, southZ - northZ + 1)
	ground.CFrame = CFrame.new(anchorX, -GROUND_THICKNESS / 2, anchorZ)
	ground.Parent = folder
	folder.Parent = parent

	return {
		key = folder.Name,
		ix = ix,
		iy = iy,
		folder = folder,
		anchorX = anchorX,
		anchorZ = anchorZ,
		destroyed = false,
		populated = false,
	}
end

local function addWalls(handle: Handle, walls: { number }, visible: boolean)
	local thickness = WorldConfig.wallCollisionThicknessStuds
	local created = 0
	for i = 1, #walls, 6 do
		if handle.destroyed then
			return
		end
		local x1, z1, x2, z2, height, variant =
			walls[i], walls[i + 1], walls[i + 2], walls[i + 3], walls[i + 4], walls[i + 5]
		local dx, dz = x2 - x1, z2 - z1
		local length = math.sqrt(dx * dx + dz * dz)
		if length > 0.05 then
			local wall = Instance.new("Part")
			wall.Name = "Wall"
			wall.Anchored = true
			wall.CanTouch = false
			wall.Size = Vector3.new(length, height, thickness)
			wall.CFrame = CFrame.fromMatrix(
				Vector3.new(handle.anchorX + (x1 + x2) / 2, height / 2, handle.anchorZ + (z1 + z2) / 2),
				Vector3.new(dx / length, 0, dz / length),
				Vector3.yAxis
			)
			if visible then
				wall.Material = Enum.Material.SmoothPlastic
				wall.Color = TextureLibrary.fallbackColor("wall" .. variant)
			else
				wall.Transparency = 1
				wall.CastShadow = false
				wall.CanQuery = false
			end
			wall.Parent = handle.folder

			created += 1
			if created % INSTANCES_PER_FRAME == 0 then
				task.wait()
			end
		end
	end
end

-- Part-based stand-in for roads and rivers when EditableMesh is unavailable.
local function addSegments(handle: Handle, segments: { number })
	local layers = WorldConfig.layerHeights
	local created = 0
	for i = 1, #segments, 6 do
		if handle.destroyed then
			return
		end
		local x1, z1, x2, z2, width, kind =
			segments[i], segments[i + 1], segments[i + 2], segments[i + 3], segments[i + 4], segments[i + 5]
		local dx, dz = x2 - x1, z2 - z1
		local length = math.sqrt(dx * dx + dz * dz)
		if length > 0.05 then
			local material, y
			if kind == TileGeometry.SEGMENT_WATER then
				material, y = "water", layers.water
			elseif kind == TileGeometry.SEGMENT_PATH then
				material, y = "path", layers.path
			else
				material, y = "road", layers.road
			end
			local strip = Instance.new("Part")
			strip.Name = material
			strip.Anchored = true
			strip.CanCollide = false
			strip.CanTouch = false
			strip.CanQuery = false
			strip.CastShadow = false
			strip.Material = Enum.Material.SmoothPlastic
			strip.Color = TextureLibrary.fallbackColor(material)
			strip.Size = Vector3.new(length + width * 0.5, 0.1, width)
			strip.CFrame = CFrame.fromMatrix(
				Vector3.new(handle.anchorX + (x1 + x2) / 2, y, handle.anchorZ + (z1 + z2) / 2),
				Vector3.new(dx / length, 0, dz / length),
				Vector3.yAxis
			)
			strip.Parent = handle.folder

			created += 1
			if created % INSTANCES_PER_FRAME == 0 then
				task.wait()
			end
		end
	end
end

-- Yields. Builds the detail for a tile from its parsed OSM data. Safe to abandon mid-way: if the tile
-- is destroyed while this runs, it stops and leaves nothing behind.
function TileRenderer.populate(handle: Handle, data: OsmParser.TileData, origin: GeoProjection.Origin)
	local geometry = TileGeometry.build(data, origin, handle.anchorX, handle.anchorZ, WorldConfig)
	if handle.destroyed then
		return
	end

	local meshesFailed = not MeshWriter.isSupported()
	if not meshesFailed then
		for _, entry in geometry.meshes do
			if meshesFailed then
				break -- the rest of this tile is drawn with the part-based fallback
			end
			local part, cx, cy, cz = MeshWriter.createMeshPart(entry.mesh, entry.material, WorldConfig)
			if handle.destroyed then
				if part ~= nil then
					part:Destroy()
				end
				return
			end
			if part ~= nil then
				part.CFrame = CFrame.new(handle.anchorX + cx, cy, handle.anchorZ + cz)
				part.Parent = handle.folder
			else
				meshesFailed = true
			end
			task.wait() -- one mesh per frame keeps dense tiles from hitching
		end
	end

	addWalls(handle, geometry.walls, meshesFailed)
	if meshesFailed then
		addSegments(handle, geometry.segments)
	end
	handle.populated = true
end

function TileRenderer.destroy(handle: Handle)
	if not handle.destroyed then
		handle.destroyed = true
		handle.folder:Destroy()
	end
end

return TileRenderer
