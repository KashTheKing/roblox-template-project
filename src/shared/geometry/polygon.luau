--!strict
-- Polygon helpers. A polygon is a flat array of coordinates: { x1, y1, x2, y2, ... } with no repeated
-- closing point. "Counter-clockwise" always means in the (x, y) math sense, i.e. positive signed area.

local Polygon = {}

local function cross(ax: number, ay: number, bx: number, by: number, cx: number, cy: number): number
	return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end

function Polygon.signedArea(poly: { number }): number
	local n = #poly // 2
	local area = 0
	for i = 1, n do
		local j = if i == n then 1 else i + 1
		area += poly[i * 2 - 1] * poly[j * 2] - poly[j * 2 - 1] * poly[i * 2]
	end
	return area / 2
end

-- Drops consecutive duplicate points and a repeated closing point.
function Polygon.cleanRing(poly: { number }, epsilon: number): { number }
	local out: { number } = {}
	local eps2 = epsilon * epsilon
	local n = #poly // 2
	for i = 1, n do
		local x, y = poly[i * 2 - 1], poly[i * 2]
		local m = #out
		local keep = true
		if m >= 2 then
			local dx, dy = x - out[m - 1], y - out[m]
			keep = dx * dx + dy * dy > eps2
		end
		if keep then
			out[m + 1] = x
			out[m + 2] = y
		end
	end
	local m = #out
	if m >= 4 then
		local dx, dy = out[1] - out[m - 1], out[2] - out[m]
		if dx * dx + dy * dy <= eps2 then
			out[m] = nil :: any
			out[m - 1] = nil :: any
		end
	end
	return out
end

function Polygon.reversed(poly: { number }): { number }
	local n = #poly // 2
	local out: { number } = {}
	for i = n, 1, -1 do
		table.insert(out, poly[i * 2 - 1])
		table.insert(out, poly[i * 2])
	end
	return out
end

-- Average of the vertices (good enough for assigning a building to a tile).
function Polygon.vertexCentroid(poly: { number }): (number, number)
	local n = #poly // 2
	if n == 0 then
		return 0, 0
	end
	local sx, sy = 0, 0
	for i = 1, n do
		sx += poly[i * 2 - 1]
		sy += poly[i * 2]
	end
	return sx / n, sy / n
end

local function pointInTriangle(
	px: number,
	py: number,
	ax: number,
	ay: number,
	bx: number,
	by: number,
	cx: number,
	cy: number
): boolean
	local eps = 1e-9
	return cross(ax, ay, bx, by, px, py) > eps
		and cross(bx, by, cx, cy, px, py) > eps
		and cross(cx, cy, ax, ay, px, py) > eps
end

-- Ear clipping. Returns 1-based vertex indices, three per triangle, each triangle counter-clockwise.
-- Self-intersecting input never loops forever: whatever cannot be clipped is fanned out at the end.
function Polygon.triangulate(poly: { number }): { number }
	local n = #poly // 2
	local tris: { number } = {}
	if n < 3 then
		return tris
	end

	local idx: { number } = table.create(n, 0)
	if Polygon.signedArea(poly) >= 0 then
		for i = 1, n do
			idx[i] = i
		end
	else
		for i = 1, n do
			idx[i] = n - i + 1
		end
	end

	local count = n
	local i = 1
	local iterations = 0
	local maxIterations = n * n + 10
	while count > 3 and iterations < maxIterations do
		iterations += 1
		local a = idx[if i == 1 then count else i - 1]
		local b = idx[i]
		local c = idx[if i == count then 1 else i + 1]
		local ax, ay = poly[a * 2 - 1], poly[a * 2]
		local bx, by = poly[b * 2 - 1], poly[b * 2]
		local cx, cy = poly[c * 2 - 1], poly[c * 2]
		local area2 = cross(ax, ay, bx, by, cx, cy)

		local isEar = false
		local drop = false
		if math.abs(area2) < 1e-9 then
			drop = true -- collinear vertex: remove it without emitting a sliver
		elseif area2 > 0 then
			isEar = true
			for k = 1, count do
				local v = idx[k]
				if v ~= a and v ~= b and v ~= c then
					if pointInTriangle(poly[v * 2 - 1], poly[v * 2], ax, ay, bx, by, cx, cy) then
						isEar = false
						break
					end
				end
			end
		end

		if isEar or drop then
			if isEar then
				table.insert(tris, a)
				table.insert(tris, b)
				table.insert(tris, c)
			end
			table.remove(idx, i)
			count -= 1
			if i > count then
				i = 1
			end
		else
			i = if i == count then 1 else i + 1
		end
	end

	if count == 3 then
		local a, b, c = idx[1], idx[2], idx[3]
		if
			math.abs(cross(poly[a * 2 - 1], poly[a * 2], poly[b * 2 - 1], poly[b * 2], poly[c * 2 - 1], poly[c * 2]))
			> 1e-9
		then
			table.insert(tris, a)
			table.insert(tris, b)
			table.insert(tris, c)
		end
	elseif count > 3 then
		for k = 2, count - 1 do
			table.insert(tris, idx[1])
			table.insert(tris, idx[k])
			table.insert(tris, idx[k + 1])
		end
	end

	return tris
end

return Polygon
