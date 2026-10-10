--!strict
-- Loads every module in ServerScriptService.services, then calls init() on all of them before start()
-- on all of them, so services can rely on each other being initialised.
local ServerScriptService = game:GetService("ServerScriptService")

local services = ServerScriptService:WaitForChild("services")

type Service = {
	init: (() -> ())?,
	start: (() -> ())?,
}

local loaded: { { name: string, service: Service } } = {}

for _, module in services:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and typeof(result) == "table" then
			table.insert(loaded, { name = module.Name, service = result :: Service })
		else
			warn(`[bootstrap] failed to load service {module.Name}: {result}`)
		end
	end
end

for _, entry in loaded do
	local init = entry.service.init
	if init then
		local ok, err = pcall(init)
		if not ok then
			warn(`[bootstrap] {entry.name}.init failed: {err}`)
		end
	end
end

for _, entry in loaded do
	local start = entry.service.start
	if start then
		task.spawn(function()
			local ok, err = pcall(start)
			if not ok then
				warn(`[bootstrap] {entry.name}.start failed: {err}`)
			end
		end)
	end
end
