--!strict
-- A small heads-up display built entirely in code: a search box ("Eiffel Tower", "Kyoto", "48.85, 2.35"),
-- one-tap preset places, the current coordinates and the tile loading status.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.shared.configs["world-config"])
local WorldController = require(ReplicatedStorage.client.controllers["world-controller"])

local UiController = {}

local player = Players.LocalPlayer

local PANEL_COLOR = Color3.fromRGB(24, 28, 36)
local ACCENT_COLOR = Color3.fromRGB(64, 128, 255)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local MUTED_COLOR = Color3.fromRGB(150, 158, 172)

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function label(parent: Instance, text: string, size: number, color: Color3, height: number): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Size = UDim2.new(1, 0, 0, height)
	item.Font = Enum.Font.GothamMedium
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Text = text
	item.Parent = parent
	return item
end

-- Built in init() so the listeners below exist before WorldController.start() emits anything.
function UiController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 12)
	panel.Size = UDim2.fromOffset(440, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.12
	panel.Parent = gui
	round(panel, 12)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local placeLabel = label(panel, "", 16, TEXT_COLOR, 20)
	placeLabel.LayoutOrder = 1
	local coordsLabel = label(panel, "", 12, MUTED_COLOR, 14)
	coordsLabel.LayoutOrder = 2

	local searchRow = Instance.new("Frame")
	searchRow.BackgroundTransparency = 1
	searchRow.Size = UDim2.new(1, 0, 0, 32)
	searchRow.LayoutOrder = 3
	searchRow.Parent = panel

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -72, 1, 0)
	box.BackgroundColor3 = Color3.fromRGB(40, 46, 58)
	box.TextColor3 = TEXT_COLOR
	box.PlaceholderColor3 = MUTED_COLOR
	box.PlaceholderText = "Go to a place or lat, lon"
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.TextSize = 14
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = searchRow
	round(box, 8)
	local boxPadding = Instance.new("UIPadding")
	boxPadding.PaddingLeft = UDim.new(0, 10)
	boxPadding.Parent = box

	local go = Instance.new("TextButton")
	go.AnchorPoint = Vector2.new(1, 0)
	go.Position = UDim2.fromScale(1, 0)
	go.Size = UDim2.new(0, 64, 1, 0)
	go.BackgroundColor3 = ACCENT_COLOR
	go.Text = "Go"
	go.TextColor3 = Color3.new(1, 1, 1)
	go.Font = Enum.Font.GothamBold
	go.TextSize = 14
	go.Parent = searchRow
	round(go, 8)

	local presets = Instance.new("ScrollingFrame")
	presets.BackgroundTransparency = 1
	presets.Size = UDim2.new(1, 0, 0, 30)
	presets.CanvasSize = UDim2.new()
	presets.AutomaticCanvasSize = Enum.AutomaticSize.X
	presets.ScrollBarThickness = 0
	presets.ScrollingDirection = Enum.ScrollingDirection.X
	presets.LayoutOrder = 4
	presets.Parent = panel
	local presetLayout = Instance.new("UIListLayout")
	presetLayout.FillDirection = Enum.FillDirection.Horizontal
	presetLayout.Padding = UDim.new(0, 6)
	presetLayout.Parent = presets

	local statusLabel = label(panel, "", 12, ACCENT_COLOR, 14)
	statusLabel.LayoutOrder = 5
	statusLabel.Visible = false

	-- OpenStreetMap's licence (ODbL) requires crediting the data wherever it is shown.
	local attribution = Instance.new("TextLabel")
	attribution.Name = "Attribution"
	attribution.AnchorPoint = Vector2.new(1, 1)
	attribution.Position = UDim2.new(1, -8, 1, -4)
	attribution.Size = UDim2.fromOffset(260, 16)
	attribution.BackgroundTransparency = 1
	attribution.Font = Enum.Font.Gotham
	attribution.TextSize = 11
	attribution.TextColor3 = Color3.new(1, 1, 1)
	attribution.TextStrokeTransparency = 0.5
	attribution.TextXAlignment = Enum.TextXAlignment.Right
	attribution.Text = "Map data (c) OpenStreetMap contributors"
	attribution.Parent = gui

	local busy = false
	local function go_to(query: string)
		if busy or query == "" then
			return
		end
		busy = true
		local ok, message = WorldController.teleportTo(query)
		if not ok then
			statusLabel.Text = message
			statusLabel.Visible = true
			task.delay(5, function()
				if statusLabel.Text == message then
					statusLabel.Visible = false
				end
			end)
		end
		busy = false
	end

	go.Activated:Connect(function()
		go_to(box.Text)
	end)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			go_to(box.Text)
		end
	end)

	for _, preset in WorldConfig.presets do
		local button = Instance.new("TextButton")
		button.AutomaticSize = Enum.AutomaticSize.X
		button.Size = UDim2.new(0, 0, 1, 0)
		button.BackgroundColor3 = Color3.fromRGB(40, 46, 58)
		button.TextColor3 = TEXT_COLOR
		button.Font = Enum.Font.Gotham
		button.TextSize = 12
		button.Text = preset.name
		button.Parent = presets
		round(button, 8)
		local buttonPadding = Instance.new("UIPadding")
		buttonPadding.PaddingLeft, buttonPadding.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
		buttonPadding.Parent = button
		button.Activated:Connect(function()
			if not busy then
				WorldController.setLocation(preset.lat, preset.lon, preset.name)
			end
		end)
	end

	WorldController.onLocation(function(name, lat, lon)
		placeLabel.Text = name
		coordsLabel.Text = string.format("%.5f, %.5f", lat, lon)
	end)
	WorldController.onStatus(function(text)
		statusLabel.Text = text
		statusLabel.Visible = text ~= ""
	end)
end

return UiController
