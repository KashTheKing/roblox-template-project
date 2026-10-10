--!strict
-- Builds one small EditableImage per material from the procedural pixel generators and hands out
-- Content references to them. Nothing is uploaded: the whole city is textured from code.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TexturePixels = require(ReplicatedStorage.shared.geometry["texture-pixels"])

local TextureLibrary = {}

local contents: { [string]: any } = {}
local failed: { [string]: boolean } = {}

-- Returns Content for the material's texture, or nil when EditableImage is unavailable (callers then
-- fall back to a flat colour).
function TextureLibrary.get(material: string): any?
	local existing = contents[material]
	if existing ~= nil then
		return existing
	end
	if failed[material] then
		return nil
	end

	local ok, result = pcall(function()
		local pixels = TexturePixels.generate(material)
		local size = Vector2.new(pixels.width, pixels.height)
		local image = AssetService:CreateEditableImage({ Size = size })
		image:WritePixelsBuffer(Vector2.zero, size, pixels.data)
		return Content.fromObject(image)
	end)

	if ok then
		contents[material] = result
		return result
	end
	failed[material] = true
	warn(`[textures] could not create the {material} texture, using flat colour instead: {result}`)
	return nil
end

-- Colour used when a texture cannot be applied.
function TextureLibrary.fallbackColor(material: string): Color3
	local rgb = TexturePixels.baseColor(material)
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

return TextureLibrary
