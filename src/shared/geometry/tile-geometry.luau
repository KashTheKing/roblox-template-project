--!strict
-- Turns one parsed OSM tile into render-ready geometry. Everything is expressed in local studs relative
-- to the tile's anchor point, so the numbers stay small and the meshes can be moved as a unit.

local BuildingGeometry = require(script.Parent["building-geometry"])
local FlatGeometry = require(script.Parent["flat-geometry"])
local GeoProjection = require(script.Parent.Parent.geo["geo-projection"])
local MeshSet = require(script.Parent["mesh-set"])
local OsmParser = require(script.Parent.Parent.osm["osm-parser"])

export type Result = {
	meshes: { MeshSet.FinishedMesh },
	-- Collision walls: x1, z1, x2, z2, height, variant (6 numbers each).
	walls: { number },
	-- Road/path/river segments for the part-based fallback: x1, z1, x2, z2, width, kind (kind: 1 road, 2 path, 3 water).
	segments: { number },
	stats: { buildings: number, lines: number, areas: number, triangles: number },
}

local TileGeometry = {}

TileGeometry.SEGMENT_ROAD = 1
TileGeometry.SEGMENT_PATH = 2
TileGeometry.SEGMENT_WATER = 3

local AREA_MATERIAL: { [string]: string } = { water = "water", grass = "grass", forest = "forest", plaza = "path" }
local SEGMENT_ROAD, SEGMENT_PATH, SEGMENT_WATER = 1, 2, 3
local PATH_KINDS = { footway = true, path = true, cycleway = true, steps = true, track = true, pedestrian = true }

local function project(origin: GeoProjection.Origin, pts: { number }, anchorX: number, anchorZ: number): { number }
	local out: { number } = table.create(#pts, 0)
	for i = 1, #pts // 2 do
		local x, z = GeoProjection.toLocal(origin, pts[i * 2], pts[i * 2 - 1])
		out[i * 2 - 1] = x - anchorX
		out[i * 2] = z - anchorZ
	end
	return out
end

function TileGeometry.build(
	data: OsmParser.TileData,
	origin: GeoProjection.Origin,
	anchorX: number,
	anchorZ: number,
	cfg: any
): Result
	local set = MeshSet.new(cfg.maxVerticesPerMesh)
	local walls: { number } = {}
	local segments: { number } = {}
	local layers = cfg.layerHeights
	local spm: number = cfg.studsPerMeter

	for _, area in data.areas do
		local material = AREA_MATERIAL[area.kind]
		if material ~= nil then
			FlatGeometry.addArea(
				set,
				material,
				project(origin, area.pts, anchorX, anchorZ),
				layers[area.kind] or layers.grass
			)
		end
	end

	for _, line in data.lines do
		local pts = project(origin, line.pts, anchorX, anchorZ)
		local width = line.widthMeters * spm
		if line.layer == "water" then
			FlatGeometry.addRibbon(set, "water", pts, width, layers.water, segments, SEGMENT_WATER)
		elseif PATH_KINDS[line.kind] then
			FlatGeometry.addRibbon(set, "path", pts, width, layers.path, segments, SEGMENT_PATH)
		else
			FlatGeometry.addRibbon(set, "road", pts, width, layers.road, segments, SEGMENT_ROAD)
		end
	end

	local collision = if cfg.collisionMode == "walls" then walls else nil
	local buildingCount = 0
	for _, building in data.buildings do
		local footprint = project(origin, building.pts, anchorX, anchorZ)
		if BuildingGeometry.add(set, building.id, footprint, building.heightMeters, cfg, collision) ~= nil then
			buildingCount += 1
		end
	end

	local meshes = MeshSet.finish(set)
	local triangles = 0
	for _, entry in meshes do
		triangles += entry.mesh.triangleCount
	end

	return {
		meshes = meshes,
		walls = walls,
		segments = segments,
		stats = { buildings = buildingCount, lines = #data.lines, areas = #data.areas, triangles = triangles },
	}
end

return TileGeometry
