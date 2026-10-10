--!strict
-- Clipping of polygons and polylines to an axis-aligned rectangle. Coordinates are flat arrays
-- { x1, y1, x2, y2, ... } (the OSM parser stores lon as x and lat as y).

local Clip = {}

local function clipHalfPlane(poly: { number }, axis: number, bound: number, keepGreater: boolean): { number }
	local n = #poly // 2
	local out: { number } = {}
	if n == 0 then
		return out
	end

	local function inside(v: number): boolean
		if keepGreater then
			return v >= bound
		end
		return v <= bound
	end

	local prevX, prevY = poly[n * 2 - 1], poly[n * 2]
	local prevV = if axis == 1 then prevX else prevY
	for i = 1, n do
		local curX, curY = poly[i * 2 - 1], poly[i * 2]
		local curV = if axis == 1 then curX else curY
		local curIn, prevIn = inside(curV), inside(prevV)
		if curIn ~= prevIn then
			local t = (bound - prevV) / (curV - prevV)
			local ix = prevX + t * (curX - prevX)
			local iy = prevY + t * (curY - prevY)
			if axis == 1 then
				ix = bound
			else
				iy = bound
			end
			table.insert(out, ix)
			table.insert(out, iy)
		end
		if curIn then
			table.insert(out, curX)
			table.insert(out, curY)
		end
		prevX, prevY, prevV = curX, curY, curV
	end
	return out
end

-- Sutherland-Hodgman. Exact for convex polygons; concave polygons may gain zero-width bridges along the
-- rectangle border, which is harmless for filled areas.
function Clip.polygonToRect(poly: { number }, minX: number, minY: number, maxX: number, maxY: number): { number }
	local result = clipHalfPlane(poly, 1, minX, true)
	result = clipHalfPlane(result, 1, maxX, false)
	result = clipHalfPlane(result, 2, minY, true)
	result = clipHalfPlane(result, 2, maxY, false)
	if #result < 6 then
		return {}
	end
	return result
end

-- Liang-Barsky. Returns whether any part is inside plus the clipped segment.
local function clipSegment(
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	minX: number,
	minY: number,
	maxX: number,
	maxY: number
): (boolean, number, number, number, number)
	local dx, dy = x2 - x1, y2 - y1
	local p = { -dx, dx, -dy, dy }
	local q = { x1 - minX, maxX - x1, y1 - minY, maxY - y1 }
	local t0, t1 = 0, 1
	for i = 1, 4 do
		if p[i] == 0 then
			if q[i] < 0 then
				return false, 0, 0, 0, 0
			end
		else
			local r = q[i] / p[i]
			if p[i] < 0 then
				if r > t1 then
					return false, 0, 0, 0, 0
				elseif r > t0 then
					t0 = r
				end
			else
				if r < t0 then
					return false, 0, 0, 0, 0
				elseif r < t1 then
					t1 = r
				end
			end
		end
	end
	return true, x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end

-- Splits a polyline into the pieces that lie inside the rectangle.
function Clip.polylineToRect(pts: { number }, minX: number, minY: number, maxX: number, maxY: number): { { number } }
	local pieces: { { number } } = {}
	local current: { number }? = nil
	local n = #pts // 2
	for i = 1, n - 1 do
		local ok, ax, ay, bx, by =
			clipSegment(pts[i * 2 - 1], pts[i * 2], pts[i * 2 + 1], pts[i * 2 + 2], minX, minY, maxX, maxY)
		if ok then
			local cur = current
			if cur ~= nil and math.abs(cur[#cur - 1] - ax) < 1e-12 and math.abs(cur[#cur] - ay) < 1e-12 then
				table.insert(cur, bx)
				table.insert(cur, by)
			else
				cur = { ax, ay, bx, by }
				table.insert(pieces, cur)
				current = cur
			end
		else
			current = nil
		end
	end
	return pieces
end

return Clip
