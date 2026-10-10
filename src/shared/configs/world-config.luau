--!strict
-- Central tuning knobs for the OpenStreetMap world. Everything here is plain data so it can be
-- required from the server, the client and the offline tests.

export type Location = { name: string, lat: number, lon: number }

local WorldConfig = {
	-- Scale: a Roblox character is ~5.6 studs tall, a person is ~1.8 m, so 1 stud ~= 0.28 m.
	studsPerMeter = 1 / 0.28,

	-- Streaming ---------------------------------------------------------------------------------
	-- The world is cut into a fixed lat/lon grid (independent of where a player starts), so tiles can be
	-- cached on the server and shared between players. 0.0025 degrees is ~277 m north-south.
	tileSizeDegrees = 0.0025,
	viewRadiusTiles = 2, -- tiles kept loaded around the player (2 => 5x5 tiles)
	unloadRadiusTiles = 3, -- tiles farther than this are destroyed (hysteresis avoids thrashing)
	maxConcurrentTileRequests = 2, -- per client
	tileRetryDelaySeconds = 15,
	tileMaxRetries = 3,
	streamingIntervalSeconds = 0.5,

	-- Where new players start, plus quick-jump buttons in the UI.
	defaultLocation = { name = "Times Square, New York", lat = 40.7580, lon = -73.9855 } :: Location,
	presets = {
		{ name = "Times Square, New York", lat = 40.7580, lon = -73.9855 },
		{ name = "Eiffel Tower, Paris", lat = 48.8584, lon = 2.2945 },
		{ name = "Shibuya Crossing, Tokyo", lat = 35.6595, lon = 139.7005 },
		{ name = "Big Ben, London", lat = 51.5007, lon = -0.1246 },
		{ name = "Sydney Opera House", lat = -33.8568, lon = 151.2153 },
	} :: { Location },

	-- Buildings ---------------------------------------------------------------------------------
	floorHeightMeters = 3.2,
	bayWidthMeters = 4, -- one window per bay
	defaultBuildingHeightMeters = 9,
	minBuildingHeightMeters = 2.5,
	maxBuildingHeightMeters = 500,

	-- Meshes ------------------------------------------------------------------------------------
	-- Roblox caps an EditableMesh at 60,000 vertices; stay well under it and roll over to a new mesh.
	maxVerticesPerMesh = 40000,
	-- "wrap": one quad per wall whose UVs repeat the one-window facade tile (cheap: a dense city tile is
	-- ~25k vertices). Relies on the texture sampler repeating UVs above 1, which is normal for MeshParts.
	-- "quads": one quad per window bay per floor with UVs kept in 0..1. Works whatever the sampler does but
	-- is ~15x heavier, so use it only if facades look stretched or streaky in "wrap" mode.
	facadeUvMode = "wrap",
	-- Flip if buildings look inside-out (triangle winding convention check).
	flipTriangleWinding = false,
	doubleSidedMeshes = true,
	-- Keep each EditableMesh alive (parented to its MeshPart). Set to false to free memory once a
	-- MeshPart exists, if you have confirmed in Studio that the part keeps rendering without it.
	keepEditableMeshes = true,
	-- "walls": invisible wall parts for each building edge. "none": no building collision.
	collisionMode = "walls",
	wallCollisionThicknessStuds = 2,

	-- Vertical layering of flat surfaces above the ground plane (avoids z-fighting).
	layerHeights = {
		grass = 0.06,
		forest = 0.12,
		water = 0.18,
		plaza = 0.24,
		road = 0.3,
		path = 0.36,
	},

	-- Roads (meters wide) by OSM highway tag.
	roadWidthsMeters = {
		motorway = 14,
		trunk = 12,
		primary = 11,
		secondary = 9,
		tertiary = 8,
		residential = 7,
		unclassified = 6.5,
		living_street = 6,
		service = 4.5,
		pedestrian = 5,
		footway = 2.5,
		path = 2.5,
		cycleway = 2.5,
		steps = 2.5,
		track = 3,
	} :: { [string]: number },
	defaultRoadWidthMeters = 5,
	waterwayWidthsMeters = { river = 20, canal = 12, stream = 3 } :: { [string]: number },

	-- Overpass (server) --------------------------------------------------------------------------
	overpassEndpoints = {
		"https://overpass-api.de/api/interpreter",
		"https://overpass.kumi.systems/api/interpreter",
		"https://overpass.private.coffee/api/interpreter",
	},
	overpassTimeoutSeconds = 25,
	overpassMinSecondsBetweenRequests = 1,
	overpassMaxConcurrent = 2,
	overpassAttemptsPerTile = 4,
	tileCacheMaxEntries = 400,
	failedTileCooldownSeconds = 20,

	-- Geocoding (server) -------------------------------------------------------------------------
	photonEndpoint = "https://photon.komoot.io/api/",
	nominatimEndpoint = "https://nominatim.openstreetmap.org/search",
}

return WorldConfig
