--!strict
-- Turns what a player types into a coordinate: either "lat, lon" (no network needed) or a place name
-- looked up through Photon (OpenStreetMap-based), falling back to Nominatim.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.shared.configs["world-config"])

export type Result = { lat: number, lon: number, name: string }

local GeocodeService = {}

local MAX_QUERY_LENGTH = 100
local MAX_LAT = 85
local CACHE_LIMIT = 200

local cache: { [string]: Result } = {}
local cacheCount = 0
-- Public geocoders ask for at most one request per second, server-wide.
local MIN_SECONDS_BETWEEN_LOOKUPS = 1
local nextLookupSlot = 0

local function remember(key: string, result: Result)
	if cacheCount >= CACHE_LIMIT then
		cache = {}
		cacheCount = 0
	end
	cache[key] = result
	cacheCount += 1
end

local function get(url: string): any?
	local startAt = math.max(os.clock(), nextLookupSlot)
	nextLookupSlot = startAt + MIN_SECONDS_BETWEEN_LOOKUPS
	if startAt > os.clock() then
		task.wait(startAt - os.clock())
	end
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = { ["User-Agent"] = "RobloxOSMWorld/1.0" },
		})
	end)
	if not ok or not response.Success then
		return nil
	end
	local decodedOk, decoded = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	return if decodedOk then decoded else nil
end

-- "40.758, -73.9855", "40.758 -73.9855" or "40.758;-73.9855"
function GeocodeService.parseCoordinates(text: string): Result?
	local a, b = string.match(text, "^%s*([%-%+]?%d+%.?%d*)%s*[,;%s]%s*([%-%+]?%d+%.?%d*)%s*$")
	local lat, lon = tonumber(a), tonumber(b)
	if lat == nil or lon == nil or math.abs(lat) > MAX_LAT or math.abs(lon) > 180 then
		return nil
	end
	return { lat = lat, lon = lon, name = string.format("%.5f, %.5f", lat, lon) }
end

local function viaPhoton(query: string): Result?
	local decoded = get(`{WorldConfig.photonEndpoint}?limit=1&q={HttpService:UrlEncode(query)}`)
	local feature = decoded and decoded.features and decoded.features[1]
	local coordinates = feature and feature.geometry and feature.geometry.coordinates
	if typeof(coordinates) ~= "table" or typeof(coordinates[1]) ~= "number" or typeof(coordinates[2]) ~= "number" then
		return nil
	end
	local properties = feature.properties or {}
	local parts: { string } = {}
	for _, field in { "name", "city", "country" } do
		local value = properties[field]
		if typeof(value) == "string" and (#parts == 0 or parts[#parts] ~= value) then
			table.insert(parts, value)
		end
	end
	return {
		lat = coordinates[2],
		lon = coordinates[1],
		name = if #parts > 0 then table.concat(parts, ", ") else query,
	}
end

local function viaNominatim(query: string): Result?
	local decoded = get(`{WorldConfig.nominatimEndpoint}?format=jsonv2&limit=1&q={HttpService:UrlEncode(query)}`)
	local hit = decoded and decoded[1]
	if typeof(hit) ~= "table" then
		return nil
	end
	local lat, lon = tonumber(hit.lat), tonumber(hit.lon)
	if lat == nil or lon == nil then
		return nil
	end
	return { lat = lat, lon = lon, name = if typeof(hit.display_name) == "string" then hit.display_name else query }
end

-- Yields while it talks to the geocoder. Returns the place, or nil and a reason shown to the player.
function GeocodeService.resolve(rawQuery: any): (Result?, string?)
	if typeof(rawQuery) ~= "string" then
		return nil, "Type a place name or coordinates."
	end
	local query = string.match(rawQuery, "^%s*(.-)%s*$") or ""
	if query == "" or #query > MAX_QUERY_LENGTH then
		return nil, "Type a place name or coordinates."
	end

	local coordinates = GeocodeService.parseCoordinates(query)
	if coordinates ~= nil then
		return coordinates, nil
	end
	if string.match(query, "^[%-%+]?%d+%.?%d*%s*[,;%s]%s*[%-%+]?%d+%.?%d*$") then
		return nil, "Latitude must be between -85 and 85, longitude between -180 and 180."
	end

	local key = string.lower(query)
	if cache[key] ~= nil then
		return cache[key], nil
	end

	local result = viaPhoton(query) or viaNominatim(query)
	if result == nil then
		return nil, "Could not find that place."
	end
	result.lat = math.clamp(result.lat, -MAX_LAT, MAX_LAT)
	remember(key, result)
	return result, nil
end

return GeocodeService
