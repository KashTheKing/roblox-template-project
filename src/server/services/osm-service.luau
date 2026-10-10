--!strict
-- Fetches OpenStreetMap data from Overpass one tile at a time, parses it into compact tile data and
-- caches the result. Requests are queued, spaced out, retried across mirrors, and shared between
-- players asking for the same tile, so a busy server stays inside Overpass' fair-use limits.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OsmParser = require(ReplicatedStorage.shared.osm["osm-parser"])
local TileMath = require(ReplicatedStorage.shared.geo["tile-math"])
local WorldConfig = require(ReplicatedStorage.shared.configs["world-config"])

type TileData = OsmParser.TileData

type Job = {
	key: string,
	ix: number,
	iy: number,
	waiters: { thread },
}

local OsmService = {}

local cache: { [string]: { data: TileData, lastUsed: number } } = {}
local cacheCount = 0
local failedUntil: { [string]: number } = {}
local inflight: { [string]: Job } = {}
local queue: { Job } = {}
local active = 0
local nextSlot = 0

local pump: () -> ()

local function storeInCache(key: string, data: TileData)
	if cache[key] == nil then
		cacheCount += 1
	end
	cache[key] = { data = data, lastUsed = os.clock() }
	if cacheCount > WorldConfig.tileCacheMaxEntries then
		local oldestKey: string? = nil
		local oldest = math.huge
		for k, entry in cache do
			if entry.lastUsed < oldest then
				oldest = entry.lastUsed
				oldestKey = k
			end
		end
		if oldestKey ~= nil then
			cache[oldestKey] = nil
			cacheCount -= 1
		end
	end
end

local function request(endpoint: string, query: string): (any?, string?)
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = endpoint,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
			Body = "data=" .. HttpService:UrlEncode(query),
		})
	end)
	if not ok then
		return nil, tostring(response)
	end
	if not response.Success then
		return nil, `HTTP {response.StatusCode}`
	end
	local decodedOk, decoded = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not decodedOk or typeof(decoded) ~= "table" then
		return nil, "unreadable response"
	end
	-- Overpass answers 200 with a "remark" when it ran out of time or memory; the elements are partial.
	if typeof(decoded.remark) == "string" and string.find(decoded.remark, "error", 1, true) then
		return nil, decoded.remark
	end
	return decoded, nil
end

local function fetch(job: Job): (TileData?, string?)
	local bounds = TileMath.bounds(job.ix, job.iy, WorldConfig.tileSizeDegrees)
	local query = OsmParser.buildQuery(bounds, WorldConfig.overpassTimeoutSeconds)
	local endpoints = WorldConfig.overpassEndpoints
	local lastError = "no endpoints configured"

	for attempt = 1, WorldConfig.overpassAttemptsPerTile do
		local endpoint = endpoints[(attempt - 1) % #endpoints + 1]
		local decoded, err = request(endpoint, query)
		if decoded ~= nil then
			return OsmParser.parse(decoded, bounds, WorldConfig), nil
		end
		lastError = err or "unknown error"
		task.wait(math.min(2 ^ attempt, 8))
	end
	return nil, lastError
end

local function runJob(job: Job)
	-- Reserve a start slot so concurrent jobs do not fire in the same instant.
	local startAt = math.max(os.clock(), nextSlot)
	nextSlot = startAt + WorldConfig.overpassMinSecondsBetweenRequests
	if startAt > os.clock() then
		task.wait(startAt - os.clock())
	end

	local data, err = fetch(job)

	active -= 1
	inflight[job.key] = nil
	if data ~= nil then
		storeInCache(job.key, data)
	else
		failedUntil[job.key] = os.clock() + WorldConfig.failedTileCooldownSeconds
		warn(`[osm] tile {job.key} failed: {err}`)
	end
	for _, thread in job.waiters do
		task.spawn(thread, data, err)
	end
	pump()
end

pump = function()
	while active < WorldConfig.overpassMaxConcurrent and #queue > 0 do
		local job = table.remove(queue, 1) :: Job
		active += 1
		task.spawn(runJob, job)
	end
end

-- Yields until the tile is available. Returns the tile data, or nil and a reason.
function OsmService.getTile(ix: number, iy: number): (TileData?, string?)
	local key = TileMath.key(ix, iy)

	local cached = cache[key]
	if cached ~= nil then
		cached.lastUsed = os.clock()
		return cached.data, nil
	end

	local cooldown = failedUntil[key]
	if cooldown ~= nil then
		if os.clock() < cooldown then
			return nil, "tile temporarily unavailable"
		end
		failedUntil[key] = nil
	end

	local job = inflight[key]
	if job == nil then
		job = { key = key, ix = ix, iy = iy, waiters = {} }
		inflight[key] = job
		table.insert(queue, job :: Job)
		pump()
	end
	table.insert((job :: Job).waiters, coroutine.running())
	return coroutine.yield()
end

function OsmService.init()
	if not HttpService.HttpEnabled then
		warn("[osm] HTTP requests are disabled. Enable them in Game Settings > Security > Allow HTTP Requests.")
	end
end

return OsmService
