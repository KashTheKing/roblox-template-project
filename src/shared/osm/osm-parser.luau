--!strict
-- Turns an Overpass `out geom` response into a compact, tile-local data set. Runs on the server (so
-- clients only receive the small result) and in the offline tests. All coordinates are flat arrays of
-- { lon1, lat1, lon2, lat2, ... } (x = lon, y = lat).

local Clip = require(script.Parent.Parent.geometry.clip)
local Polygon = require(script.Parent.Parent.geometry.polygon)

export type Bounds = { south: number, west: number, north: number, east: number }

export type Building = {
	id: number,
	kind: string,
	heightMeters: number,
	pts: { number },
}

-- layer is "road" (roads and paths) or "water" (rivers, canals, streams).
export type Line = {
	id: number,
	kind: string,
	layer: string,
	widthMeters: number,
	pts: { number },
}

-- kind is "water", "grass", "forest" or "plaza".
export type Area = {
	id: number,
	kind: string,
	pts: { number },
}

export type TileData = {
	buildings: { Building },
	lines: { Line },
	areas: { Area },
}

export type ParseConfig = {
	floorHeightMeters: number,
	defaultBuildingHeightMeters: number,
	minBuildingHeightMeters: number,
	maxBuildingHeightMeters: number,
	roadWidthsMeters: { [string]: number },
	defaultRoadWidthMeters: number,
	waterwayWidthsMeters: { [string]: number },
}

local OsmParser = {}

-- Typical heights (meters) for buildings that carry no height or level tags.
local DEFAULT_HEIGHTS: { [string]: number } = {
	house = 6.5,
	detached = 6.5,
	semidetached_house = 7,
	terrace = 8,
	bungalow = 4.5,
	cabin = 4,
	hut = 3,
	residential = 12,
	apartments = 16,
	dormitory = 14,
	commercial = 16,
	retail = 8,
	office = 20,
	industrial = 9,
	warehouse = 8,
	garage = 3,
	garages = 3,
	carport = 3,
	shed = 3,
	church = 16,
	cathedral = 30,
	hospital = 16,
	school = 10,
	university = 14,
	hotel = 22,
	civic = 12,
	public = 12,
	train_station = 12,
	stadium = 20,
}

local WATER_NATURAL = { water = true, bay = true, strait = true }
local GRASS_LANDUSE = { grass = true, meadow = true, recreation_ground = true, village_green = true, cemetery = true }
local GRASS_LEISURE = { park = true, garden = true, playground = true, pitch = true, golf_course = true }

-- Parses OSM length values such as "12", "12.5 m", "40 ft" or `40'`. Returns meters.
function OsmParser.parseLength(value: any): number?
	if typeof(value) ~= "string" then
		return nil
	end
	local numberText, unit = string.match(value, "^%s*(%d+%.?%d*)%s*(%S*)")
	local n = tonumber(numberText)
	if n == nil then
		return nil
	end
	unit = string.lower(unit or "")
	if unit == "ft" or unit == "'" or unit == "feet" then
		return n * 0.3048
	end
	return n
end

local function parseNumber(value: any): number?
	if typeof(value) ~= "string" then
		return nil
	end
	return tonumber(string.match(value, "^%s*(%d+%.?%d*)"))
end

function OsmParser.buildingHeightMeters(tags: { [string]: any }, id: number, cfg: ParseConfig): number
	local height = OsmParser.parseLength(tags.height)
	if height == nil then
		local levels = parseNumber(tags["building:levels"])
		if levels ~= nil then
			height = levels * cfg.floorHeightMeters + 1 -- +1 m for the roof
		end
	end
	local resolved: number
	if height ~= nil then
		resolved = height
	else
		local base = DEFAULT_HEIGHTS[tags.building or ""] or cfg.defaultBuildingHeightMeters
		-- Deterministic variety so untagged blocks do not all share a single height.
		resolved = base * (0.85 + (id % 11) / 36)
	end
	return math.clamp(resolved, cfg.minBuildingHeightMeters, cfg.maxBuildingHeightMeters)
end

function OsmParser.roadWidthMeters(highway: string, cfg: ParseConfig): number
	return cfg.roadWidthsMeters[highway] or cfg.defaultRoadWidthMeters
end

local function isClosed(pts: { number }): boolean
	local n = #pts // 2
	return n >= 4 and pts[1] == pts[n * 2 - 1] and pts[2] == pts[n * 2]
end

local function geometryToPoints(geometry: any): { number }
	local pts: { number } = {}
	if typeof(geometry) ~= "table" then
		return pts
	end
	for _, node in geometry do
		if typeof(node) == "table" and typeof(node.lon) == "number" and typeof(node.lat) == "number" then
			table.insert(pts, node.lon)
			table.insert(pts, node.lat)
		end
	end
	return pts
end

local function areaKind(tags: { [string]: any }): string?
	if WATER_NATURAL[tags.natural or ""] or tags.waterway == "riverbank" or tags.landuse == "reservoir" then
		return "water"
	end
	if tags.natural == "wood" or tags.landuse == "forest" then
		return "forest"
	end
	if tags.natural == "grassland" or GRASS_LANDUSE[tags.landuse or ""] or GRASS_LEISURE[tags.leisure or ""] then
		return "grass"
	end
	if tags.highway ~= nil and tags.area == "yes" then
		return "plaza"
	end
	return nil
end

function OsmParser.buildQuery(bounds: Bounds, timeoutSeconds: number): string
	local box = string.format("%.6f,%.6f,%.6f,%.6f", bounds.south, bounds.west, bounds.north, bounds.east)
	return table.concat({
		string.format("[out:json][timeout:%d];(", timeoutSeconds),
		string.format('way["building"](%s);', box),
		string.format('way["highway"](%s);', box),
		string.format('way["waterway"~"^(river|canal|stream|riverbank)$"](%s);', box),
		string.format('way["natural"~"^(water|bay|strait|wood|grassland)$"](%s);', box),
		string.format(
			'way["landuse"~"^(forest|grass|meadow|recreation_ground|village_green|cemetery|reservoir)$"](%s);',
			box
		),
		string.format('way["leisure"~"^(park|garden|playground|pitch|golf_course)$"](%s);', box),
		");out geom;",
	}, "")
end

-- `decoded` is the JSON-decoded Overpass response. Each way is reduced to what falls inside `bounds`:
-- buildings belong to the tile that holds their centroid; roads and areas are clipped to the tile, so
-- neighbouring tiles never draw the same thing twice.
function OsmParser.parse(decoded: any, bounds: Bounds, cfg: ParseConfig): TileData
	local result: TileData = { buildings = {}, lines = {}, areas = {} }
	if typeof(decoded) ~= "table" or typeof(decoded.elements) ~= "table" then
		return result
	end

	for _, element in decoded.elements do
		if typeof(element) == "table" and element.type == "way" and typeof(element.id) == "number" then
			local tags: { [string]: any } = if typeof(element.tags) == "table" then element.tags else {}
			local pts = geometryToPoints(element.geometry)
			if #pts >= 4 then
				local id: number = element.id
				local closed = isClosed(pts)

				if tags.building ~= nil and tags.building ~= "no" then
					if closed then
						local ring = Polygon.cleanRing(pts, 1e-9)
						local cx, cy = Polygon.vertexCentroid(ring)
						if cx >= bounds.west and cx < bounds.east and cy >= bounds.south and cy < bounds.north then
							table.insert(result.buildings, {
								id = id,
								kind = tags.building,
								heightMeters = OsmParser.buildingHeightMeters(tags, id, cfg),
								pts = ring,
							})
						end
					end
				else
					local kind = if closed then areaKind(tags) else nil
					if kind ~= nil then
						local clipped = Clip.polygonToRect(
							Polygon.cleanRing(pts, 1e-9),
							bounds.west,
							bounds.south,
							bounds.east,
							bounds.north
						)
						if #clipped >= 6 then
							table.insert(result.areas, { id = id, kind = kind, pts = clipped })
						end
					elseif tags.highway ~= nil and tags.tunnel ~= "yes" and tags.area ~= "yes" then
						local highway: string = tags.highway
						if highway ~= "proposed" and highway ~= "construction" then
							local width = OsmParser.parseLength(tags.width) or OsmParser.roadWidthMeters(highway, cfg)
							for _, piece in
								Clip.polylineToRect(pts, bounds.west, bounds.south, bounds.east, bounds.north)
							do
								table.insert(result.lines, {
									id = id,
									kind = highway,
									layer = "road",
									widthMeters = width,
									pts = piece,
								})
							end
						end
					elseif tags.waterway ~= nil and cfg.waterwayWidthsMeters[tags.waterway] ~= nil then
						local width = cfg.waterwayWidthsMeters[tags.waterway]
						for _, piece in Clip.polylineToRect(pts, bounds.west, bounds.south, bounds.east, bounds.north) do
							table.insert(result.lines, {
								id = id,
								kind = tags.waterway,
								layer = "water",
								widthMeters = width,
								pts = piece,
							})
						end
					end
				end
			end
		end
	end

	return result
end

return OsmParser
