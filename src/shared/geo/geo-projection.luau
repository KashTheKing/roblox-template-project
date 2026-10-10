--!strict
-- Local flat projection around an origin (equirectangular, accurate to well under 1% within a few km).
-- Local space: +X = east, -Z = north (Roblox "forward" is -Z), units are studs.

export type Origin = {
	lat: number,
	lon: number,
	studsPerMeter: number,
	metersPerDegLat: number,
	metersPerDegLon: number,
}

local GeoProjection = {}

local MAX_LAT = 85

function GeoProjection.clampLat(lat: number): number
	return math.clamp(lat, -MAX_LAT, MAX_LAT)
end

function GeoProjection.wrapLon(lon: number): number
	return ((lon + 180) % 360) - 180
end

-- WGS84 series expansions for the length of one degree at a latitude.
function GeoProjection.metersPerDegree(lat: number): (number, number)
	local phi = math.rad(lat)
	local perLat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
	local perLon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi) + 0.118 * math.cos(5 * phi)
	return perLat, perLon
end

function GeoProjection.newOrigin(lat: number, lon: number, studsPerMeter: number): Origin
	lat = GeoProjection.clampLat(lat)
	lon = GeoProjection.wrapLon(lon)
	local perLat, perLon = GeoProjection.metersPerDegree(lat)
	return {
		lat = lat,
		lon = lon,
		studsPerMeter = studsPerMeter,
		metersPerDegLat = perLat,
		metersPerDegLon = perLon,
	}
end

-- lat/lon (degrees) -> local x, z (studs)
function GeoProjection.toLocal(origin: Origin, lat: number, lon: number): (number, number)
	local dLon = GeoProjection.wrapLon(lon - origin.lon)
	local x = dLon * origin.metersPerDegLon * origin.studsPerMeter
	local z = -(lat - origin.lat) * origin.metersPerDegLat * origin.studsPerMeter
	return x, z
end

-- local x, z (studs) -> lat/lon (degrees)
function GeoProjection.toGeo(origin: Origin, x: number, z: number): (number, number)
	local lon = origin.lon + x / (origin.metersPerDegLon * origin.studsPerMeter)
	local lat = origin.lat - z / (origin.metersPerDegLat * origin.studsPerMeter)
	return GeoProjection.clampLat(lat), GeoProjection.wrapLon(lon)
end

return GeoProjection
