--!strict
-- Loads every module in ReplicatedStorage.client.controllers, then calls init() on all of them before
-- start() on all of them, so controllers can rely on each other being initialised.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local controllers = ReplicatedStorage:WaitForChild("client"):WaitForChild("controllers")

type Controller = {
	init: (() -> ())?,
	start: (() -> ())?,
}

local loaded: { { name: string, controller: Controller } } = {}

for _, module in controllers:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and typeof(result) == "table" then
			table.insert(loaded, { name = module.Name, controller = result :: Controller })
		else
			warn(`[bootstrap] failed to load controller {module.Name}: {result}`)
		end
	end
end

for _, entry in loaded do
	local init = entry.controller.init
	if init then
		local ok, err = pcall(init)
		if not ok then
			warn(`[bootstrap] {entry.name}.init failed: {err}`)
		end
	end
end

for _, entry in loaded do
	local start = entry.controller.start
	if start then
		task.spawn(function()
			local ok, err = pcall(start)
			if not ok then
				warn(`[bootstrap] {entry.name}.start failed: {err}`)
			end
		end)
	end
end
