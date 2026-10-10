--!strict
-- Fixed lat/lon grid used for streaming and caching. Tile (ix, iy) covers
--   lon in [ix * size - 180, (ix + 1) * size - 180)   lat in [iy * size - 90, (iy + 1) * size - 90)

export type Bounds = { south: number, west: number, north: number, east: number }
export type TileId = { ix: number, iy: number }

type Entry = { ix: number, iy: number, d: number }

local TileMath = {}

function TileMath.tilesPerLon(size: number): number
	return math.floor(360 / size + 0.5)
end

function TileMath.tilesPerLat(size: number): number
	return math.floor(180 / size + 0.5)
end

function TileMath.tileIndex(lat: number, lon: number, size: number): (number, number)
	local lonCount = TileMath.tilesPerLon(size)
	local latCount = TileMath.tilesPerLat(size)
	local ix = math.floor((lon + 180) / size) % lonCount
	local iy = math.clamp(math.floor((lat + 90) / size), 0, latCount - 1)
	return ix, iy
end

function TileMath.bounds(ix: number, iy: number, size: number): Bounds
	return {
		south = iy * size - 90,
		west = ix * size - 180,
		north = (iy + 1) * size - 90,
		east = (ix + 1) * size - 180,
	}
end

function TileMath.isValid(ix: any, iy: any, size: number): boolean
	if typeof(ix) ~= "number" or typeof(iy) ~= "number" then
		return false
	end
	if ix ~= ix or iy ~= iy or ix % 1 ~= 0 or iy % 1 ~= 0 then
		return false
	end
	return ix >= 0 and ix < TileMath.tilesPerLon(size) and iy >= 0 and iy < TileMath.tilesPerLat(size)
end

function TileMath.key(ix: number, iy: number): string
	return ix .. ":" .. iy
end

-- Tile indices within `radius` of (ix, iy), nearest first (so the tile under the player loads first).
-- Longitude wraps around the antimeridian; latitude does not.
function TileMath.around(ix: number, iy: number, radius: number, size: number): { TileId }
	local lonCount = TileMath.tilesPerLon(size)
	local latCount = TileMath.tilesPerLat(size)
	local list: { Entry } = {}
	for dy = -radius, radius do
		local ty = iy + dy
		if ty >= 0 and ty < latCount then
			for dx = -radius, radius do
				table.insert(list, { ix = (ix + dx) % lonCount, iy = ty, d = dx * dx + dy * dy })
			end
		end
	end
	table.sort(list, function(a: Entry, b: Entry): boolean
		return a.d < b.d
	end)
	local out: { TileId } = {}
	for _, entry in list do
		table.insert(out, { ix = entry.ix, iy = entry.iy })
	end
	return out
end

-- Chebyshev distance in tiles, taking longitude wrap into account.
function TileMath.distance(ax: number, ay: number, bx: number, by: number, size: number): number
	local lonCount = TileMath.tilesPerLon(size)
	local dx = math.abs(ax - bx)
	dx = math.min(dx, lonCount - dx)
	return math.max(dx, math.abs(ay - by))
end

return TileMath
