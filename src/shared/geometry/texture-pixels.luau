--!strict
-- Procedural pixel data for every material. The client copies these buffers into EditableImages, so
-- the whole city is textured without a single uploaded image asset. Pixels are RGBA, 4 bytes each.

export type Image = { width: number, height: number, data: buffer }

local TexturePixels = {}

local FACADE_SIZE = 64
local FLAT_SIZE = 16

-- Wall facade palettes: base wall colour, window glass colour, frame colour, glass share of the tile.
type Facade = { wall: Color, glass: Color, frame: Color, curtain: boolean }
type Color = { number }

local FACADES: { Facade } = {
	{ wall = { 156, 92, 74 }, glass = { 62, 78, 96 }, frame = { 226, 222, 214 }, curtain = false }, -- brick
	{ wall = { 212, 196, 165 }, glass = { 70, 88, 108 }, frame = { 245, 240, 230 }, curtain = false }, -- sandstone
	{ wall = { 150, 152, 155 }, glass = { 58, 72, 90 }, frame = { 210, 212, 214 }, curtain = false }, -- concrete
	{ wall = { 232, 230, 224 }, glass = { 74, 96, 120 }, frame = { 120, 120, 124 }, curtain = false }, -- plaster
	{ wall = { 82, 110, 134 }, glass = { 128, 168, 196 }, frame = { 58, 76, 92 }, curtain = true }, -- glass tower
	{ wall = { 190, 140, 100 }, glass = { 66, 84, 102 }, frame = { 240, 232, 220 }, curtain = false }, -- terracotta
}

TexturePixels.WALL_VARIANTS = #FACADES

local FLAT_COLORS: { [string]: Color } = {
	roof = { 112, 114, 118 },
	road = { 58, 60, 64 },
	path = { 176, 168, 152 },
	water = { 64, 128, 178 },
	grass = { 98, 150, 74 },
	forest = { 56, 108, 58 },
}

-- Cheap deterministic hash noise in [-1, 1].
local function noise(x: number, y: number, seed: number): number
	local h = bit32.bxor(x * 73856093, y * 19349663, seed * 83492791)
	h = bit32.band(bit32.bxor(h, bit32.rshift(h, 13)) * 1274126177, 0xFFFF)
	return h / 32767.5 - 1
end

local function put(data: buffer, width: number, x: number, y: number, r: number, g: number, b: number)
	local o = (y * width + x) * 4
	buffer.writeu8(data, o, math.clamp(math.floor(r + 0.5), 0, 255))
	buffer.writeu8(data, o + 1, math.clamp(math.floor(g + 0.5), 0, 255))
	buffer.writeu8(data, o + 2, math.clamp(math.floor(b + 0.5), 0, 255))
	buffer.writeu8(data, o + 3, 255)
end

local function facade(variant: number): Image
	local spec = FACADES[variant]
	local size = FACADE_SIZE
	local data = buffer.create(size * size * 4)
	-- The window sits in the middle of the tile, symmetric top to bottom, so it does not matter which
	-- way up the texture's V axis points.
	local margin = if spec.curtain then 3 else 14
	local frameWidth = 2
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local inWindow = x >= margin and x < size - margin and y >= margin and y < size - margin
			local color = spec.wall
			local grain = noise(x, y, variant) * 5
			if inWindow then
				local edge = math.min(x - margin, size - margin - 1 - x, y - margin, size - margin - 1 - y)
				if edge < frameWidth then
					color = spec.frame
					grain = 0
				else
					color = spec.glass
					-- soft vertical sheen, mirrored so the tile stays symmetric
					local t = 1 - math.abs((y / (size - 1)) * 2 - 1)
					grain = t * 14 + noise(x, y, variant + 11) * 3
				end
				if spec.curtain and (x % 16 == 0 or y % 16 == 0) then
					color = spec.frame
					grain = 0
				end
			end
			put(data, size, x, y, color[1] + grain, color[2] + grain, color[3] + grain)
		end
	end
	return { width = size, height = size, data = data }
end

local function flat(material: string): Image
	local color = FLAT_COLORS[material]
	local size = FLAT_SIZE
	local data = buffer.create(size * size * 4)
	local seed = #material
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local grain = noise(x, y, seed) * 4
			put(data, size, x, y, color[1] + grain, color[2] + grain, color[3] + grain)
		end
	end
	return { width = size, height = size, data = data }
end

-- Names of every material the geometry generators can reference.
function TexturePixels.materials(): { string }
	local list: { string } = {}
	for i = 1, #FACADES do
		table.insert(list, "wall" .. i)
	end
	for name in FLAT_COLORS do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

-- Average colour of a material, used when a texture cannot be applied (part-based fallback).
function TexturePixels.baseColor(material: string): { number }
	local variant = tonumber(string.match(material, "^wall(%d+)$"))
	if variant ~= nil and FACADES[variant] ~= nil then
		return FACADES[variant].wall
	end
	return FLAT_COLORS[material] or FLAT_COLORS.road
end

function TexturePixels.generate(material: string): Image
	local variant = tonumber(string.match(material, "^wall(%d+)$"))
	if variant ~= nil and FACADES[variant] ~= nil then
		return facade(variant)
	end
	assert(FLAT_COLORS[material] ~= nil, "unknown material: " .. material)
	return flat(material)
end

return TexturePixels
