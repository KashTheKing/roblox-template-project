--!strict
-- The only door between players and the outside world. Clients ask for map tiles and place searches
-- through two RemoteFunctions; this service validates and rate limits every call before the HTTP work
-- (done by OsmService / GeocodeService) happens on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GeocodeService = require(ServerScriptService.services["geocode-service"])
local OsmService = require(ServerScriptService.services["osm-service"])
local TileMath = require(ReplicatedStorage.shared.geo["tile-math"])
local WorldConfig = require(ReplicatedStorage.shared.configs["world-config"])

type Bucket = { tokens: number, updated: number }

local WorldService = {}

local tileBuckets: { [Player]: Bucket } = {}
local searchBuckets: { [Player]: Bucket } = {}

-- Token bucket: `capacity` calls in a burst, refilled at `perSecond`.
local function take(buckets: { [Player]: Bucket }, player: Player, capacity: number, perSecond: number): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if bucket == nil then
		bucket = { tokens = capacity, updated = now }
		buckets[player] = bucket
	end
	local b = bucket :: Bucket
	b.tokens = math.min(capacity, b.tokens + (now - b.updated) * perSecond)
	b.updated = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function WorldService.init()
	local remotes = ReplicatedStorage:WaitForChild("remotes")
	local getTile = remotes:WaitForChild("get-tile") :: RemoteFunction
	local resolveLocation = remotes:WaitForChild("resolve-location") :: RemoteFunction

	getTile.OnServerInvoke = function(player: Player, ix: any, iy: any): any
		if not TileMath.isValid(ix, iy, WorldConfig.tileSizeDegrees) then
			return { ok = false, error = "invalid tile" }
		end
		if not take(tileBuckets, player, 8, 3) then
			return { ok = false, error = "slow down" }
		end
		local data, err = OsmService.getTile(ix, iy)
		if data == nil then
			return { ok = false, error = err or "unavailable" }
		end
		return { ok = true, data = data }
	end

	resolveLocation.OnServerInvoke = function(player: Player, query: any): any
		if not take(searchBuckets, player, 3, 0.5) then
			return { ok = false, error = "Searching too fast, wait a moment." }
		end
		local result, err = GeocodeService.resolve(query)
		if result == nil then
			return { ok = false, error = err or "Could not find that place." }
		end
		return { ok = true, lat = result.lat, lon = result.lon, name = result.name }
	end

	Players.PlayerRemoving:Connect(function(player)
		tileBuckets[player] = nil
		searchBuckets[player] = nil
	end)
end

return WorldService
