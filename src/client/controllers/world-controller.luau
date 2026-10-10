--!strict
-- Keeps the right tiles of the real world around the player. The world's origin is local to this
-- player: teleporting to a new place re-centres everything on (0, 0, 0) so coordinates stay small no
-- matter where on Earth you are.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GeoProjection = require(ReplicatedStorage.shared.geo["geo-projection"])
local TileMath = require(ReplicatedStorage.shared.geo["tile-math"])
local TileRenderer = require(ReplicatedStorage.client.classes["tile-renderer"])
local WorldConfig = require(ReplicatedStorage.shared.configs["world-config"])

type TileState = {
	ix: number,
	iy: number,
	handle: TileRenderer.Handle,
	status: string, -- "idle" | "loading" | "loaded" | "failed"
	failures: number,
	retryAt: number,
}

local WorldController = {}

local SPAWN_HEIGHT = 8
local GROUND_WAIT_TIMEOUT = 25

local player = Players.LocalPlayer
local origin: GeoProjection.Origin? = nil
local locationName = ""
local generation = 0
local activeRequests = 0
local tiles: { [string]: TileState } = {}
local container: Folder? = nil
local holdUntilLoaded = false
local holdStartedAt = 0
local lastLocationEmit = 0
local lastStatus: string? = nil

local getTile: RemoteFunction
local resolveLocation: RemoteFunction

local statusListeners: { (string) -> () } = {}
local locationListeners: { (string, number, number) -> () } = {}

local function emitStatus(text: string)
	if text == lastStatus then
		return
	end
	lastStatus = text
	for _, listener in statusListeners do
		task.spawn(listener, text)
	end
end

local function emitLocation(lat: number, lon: number)
	for _, listener in locationListeners do
		task.spawn(listener, locationName, lat, lon)
	end
end

local function getRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function WorldController.onStatus(listener: (string) -> ())
	table.insert(statusListeners, listener)
end

function WorldController.onLocation(listener: (string, number, number) -> ())
	table.insert(locationListeners, listener)
end

-- Holds the character in place until the ground (and colliders) under it exist.
local function holdCharacter()
	local root = getRoot()
	if root ~= nil then
		root.Anchored = true
		holdUntilLoaded = true
		holdStartedAt = os.clock()
	end
end

local function releaseCharacter()
	holdUntilLoaded = false
	local root = getRoot()
	if root ~= nil then
		root.Anchored = false
	end
end

local function clearTiles()
	for key, state in tiles do
		TileRenderer.destroy(state.handle)
		tiles[key] = nil
	end
end

-- Re-centres the world on a new place and puts the player at its centre.
function WorldController.setLocation(lat: number, lon: number, name: string)
	generation += 1
	activeRequests = 0
	clearTiles()

	origin = GeoProjection.newOrigin(lat, lon, WorldConfig.studsPerMeter)
	locationName = name

	local character = player.Character
	if character ~= nil then
		holdCharacter()
		character:PivotTo(CFrame.new(0, SPAWN_HEIGHT, 0))
	end
	emitLocation(origin.lat, origin.lon)
	emitStatus("Loading map...")
end

-- Yields while the server looks the place up.
function WorldController.teleportTo(query: string): (boolean, string)
	emitStatus("Searching...")
	local ok, reply = pcall(function()
		return resolveLocation:InvokeServer(query)
	end)
	if not ok or typeof(reply) ~= "table" then
		emitStatus("")
		return false, "Could not reach the server."
	end
	if reply.ok ~= true then
		emitStatus("")
		return false, if typeof(reply.error) == "string" then reply.error else "Could not find that place."
	end
	WorldController.setLocation(reply.lat, reply.lon, reply.name)
	return true, reply.name
end

local function loadTile(state: TileState, currentOrigin: GeoProjection.Origin)
	local myGeneration = generation
	state.status = "loading"
	activeRequests += 1

	task.spawn(function()
		local ok, reply = pcall(function()
			return getTile:InvokeServer(state.ix, state.iy)
		end)
		if myGeneration ~= generation then
			return -- the player teleported while this was in flight
		end
		activeRequests = math.max(0, activeRequests - 1)
		if state.handle.destroyed then
			return
		end

		if ok and typeof(reply) == "table" and reply.ok == true then
			local populated, err = pcall(TileRenderer.populate, state.handle, reply.data, currentOrigin)
			if myGeneration ~= generation or state.handle.destroyed then
				return
			end
			if populated then
				state.status = "loaded"
				return
			end
			warn(`[world] failed to build tile {state.handle.key}: {err}`)
		end

		state.failures += 1
		if state.failures >= WorldConfig.tileMaxRetries then
			state.status = "failed" -- keep the plain ground slab; the player can still walk here
		else
			state.status = "idle"
			state.retryAt = os.clock() + WorldConfig.tileRetryDelaySeconds
		end
	end)
end

local function step()
	local currentOrigin = origin
	local root = getRoot()
	local currentContainer = container
	if currentOrigin == nil or root == nil or currentContainer == nil then
		return
	end

	local position = root.Position
	local lat, lon = GeoProjection.toGeo(currentOrigin, position.X, position.Z)
	local size = WorldConfig.tileSizeDegrees
	local ix, iy = TileMath.tileIndex(lat, lon, size)

	if os.clock() - lastLocationEmit > 0.5 then
		lastLocationEmit = os.clock()
		emitLocation(lat, lon)
	end

	-- Drop tiles that are far away.
	for key, state in tiles do
		if TileMath.distance(state.ix, state.iy, ix, iy, size) > WorldConfig.unloadRadiusTiles then
			TileRenderer.destroy(state.handle)
			tiles[key] = nil
		end
	end

	-- Create ground for, and request, every tile in view (nearest first).
	local wanted = TileMath.around(ix, iy, WorldConfig.viewRadiusTiles, size)
	local loadedCount = 0
	for _, tile in wanted do
		local key = TileMath.key(tile.ix, tile.iy)
		local state = tiles[key]
		if state == nil then
			state = {
				ix = tile.ix,
				iy = tile.iy,
				handle = TileRenderer.create(currentContainer, tile.ix, tile.iy, currentOrigin),
				status = "idle",
				failures = 0,
				retryAt = 0,
			}
			tiles[key] = state
		end
		local s = state :: TileState
		if s.status == "loaded" or s.status == "failed" then
			loadedCount += 1
		elseif
			s.status == "idle"
			and activeRequests < WorldConfig.maxConcurrentTileRequests
			and os.clock() >= s.retryAt
		then
			loadTile(s, currentOrigin)
		end
	end

	if loadedCount < #wanted then
		emitStatus(`Loading map: {loadedCount}/{#wanted} tiles`)
	else
		emitStatus("")
	end

	if holdUntilLoaded then
		local here = tiles[TileMath.key(ix, iy)]
		local ready = here ~= nil and (here.status == "loaded" or here.status == "failed")
		if ready or os.clock() - holdStartedAt > GROUND_WAIT_TIMEOUT then
			releaseCharacter()
		end
	end
end

function WorldController.init()
	local remotes = ReplicatedStorage:WaitForChild("remotes")
	getTile = remotes:WaitForChild("get-tile") :: RemoteFunction
	resolveLocation = remotes:WaitForChild("resolve-location") :: RemoteFunction

	local folder = Instance.new("Folder")
	folder.Name = "WorldTiles"
	folder.Parent = workspace
	container = folder
end

function WorldController.start()
	-- A respawned character appears near the world's centre; hold it until there is ground under it.
	player.CharacterAdded:Connect(function(character)
		if origin ~= nil then
			character:WaitForChild("HumanoidRootPart")
			holdCharacter()
		end
	end)

	if player.Character == nil then
		player.CharacterAdded:Wait()
	end
	player.Character:WaitForChild("HumanoidRootPart")

	local start = WorldConfig.defaultLocation
	WorldController.setLocation(start.lat, start.lon, start.name)

	while true do
		local ok, err = pcall(step)
		if not ok then
			warn(`[world] streaming step failed: {err}`)
		end
		task.wait(WorldConfig.streamingIntervalSeconds)
	end
end

return WorldController
