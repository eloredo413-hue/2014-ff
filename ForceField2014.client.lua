--[[
	ForceField2014 (LocalScript)

	Brings back the ROBLOX ForceField look from the October 2014 update (the
	same update that changed Smoke, Sparkles and Fire): a glowing cyan bubble
	with a bright rim, a softly pulsing inner ring and a swirly shell, around
	the same sparkle effect today's ForceField uses. When the camera goes
	inside a bubble the screen turns cyan, like it did back then.

	It replaces the look of every ForceField in the game: SpawnLocation spawn
	protection, admin :ff commands, Instance.new("ForceField"), and so on.
	Nothing has to be uploaded; everything is built from a part and UI objects.

	Setup: put this LocalScript in StarterPlayer > StarterPlayerScripts.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CONFIG = {
	DiameterScale = 1.45, -- bubble diameter = character height * this
	FallbackDiameter = 7, -- used when the character can't be measured

	RimColor = Color3.fromRGB(95, 215, 255),
	GlowColor = Color3.fromRGB(60, 190, 255),
	HazeColor = Color3.fromRGB(0, 150, 255),
	HighlightColor = Color3.fromRGB(225, 252, 255),

	ShowShell = true, -- swirly 3D shell inside the rim
	ShellColor = Color3.fromRGB(0, 170, 255),
	ShellTransparency = 0.6,

	-- The 2014 bubble had the same sparkles as today's ForceField, so Roblox's own
	-- ForceField effect stays on inside it. Set to false for just the bubble.
	ShowModernSparkles = true,

	ShowInsideTint = true, -- tint the screen while the camera is inside a bubble
	InsideTintTransparency = 0.6,

	HighlightFollowsSun = true, -- brightest side of the rim faces the sun
	PulseSpeed = 2.6, -- how fast the inner ring breathes in and out

	FadeInTime = 0.2,
	FadeOutTime = 0.35,
}

-- How far the billboard reaches, in bubble radii. Leaves room for the outer glow.
local CANVAS = 1.25

-- Every ring is a UIStroke drawn just outside a circle. Radii are in bubble
-- radii (1 = the rim). They are listed back to front.
local BANDS = {
	-- inner glow, fading toward the middle
	{ inner = 0.78, outer = 0.86, color = CONFIG.GlowColor, opacity = 0.06 },
	{ inner = 0.86, outer = 0.91, color = CONFIG.GlowColor, opacity = 0.12 },
	{ inner = 0.91, outer = 0.94, color = CONFIG.GlowColor, opacity = 0.22 },
	{ inner = 0.94, outer = 0.96, color = CONFIG.GlowColor, opacity = 0.35 },
	-- thin inner ring that drifts in and out
	{ inner = 0.9, outer = 0.912, color = Color3.fromRGB(140, 225, 255), opacity = 0.55, pulse = true },
	-- outer haze
	{ inner = 1, outer = 1.09, color = CONFIG.HazeColor, opacity = 0.07 },
	{ inner = 1, outer = 1.045, color = CONFIG.HazeColor, opacity = 0.18 },
	{ inner = 1, outer = 1.018, color = CONFIG.RimColor, opacity = 0.4 },
	-- the rim and its hot white core
	{ inner = 0.96, outer = 1, color = Color3.new(1, 1, 1), opacity = 0.92, highlight = true },
	{ inner = 0.974, outer = 0.988, color = CONFIG.HighlightColor, opacity = 0.7 },
}

local PULSE_SWING = 0.045 -- how far the pulsing ring moves, in bubble radii
local FILL_RADIUS = 0.96
local FILL_OPACITY = 0.16
local DEATH_GROWTH = 0.15 -- the bubble swells this much while fading out

local localPlayer = Players.LocalPlayer

local folder = Instance.new("Folder")
folder.Name = "ForceField2014"
folder.Parent = workspace

local effects = {} -- [ForceField] = effect
local fading = {} -- effects whose ForceField is gone, fading out
local hiddenByUs = setmetatable({}, { __mode = "k" }) -- ForceFields we made invisible
local watched = setmetatable({}, { __mode = "k" })

local function findRoot(model: Model): BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RootPart then
		return humanoid.RootPart
	end
	for _, name in { "HumanoidRootPart", "Torso", "UpperTorso" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

-- The bubble is sized from the body's height. Only direct child parts count,
-- so hats and gear don't make it bigger.
local function measureDiameter(model: Model, root: BasePart): number
	local up = root.CFrame.UpVector
	local top, bottom = -math.huge, math.huge
	local count = 0
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local cf = child.CFrame
			local half = child.Size / 2
			local reach = math.abs(cf.RightVector:Dot(up)) * half.X
				+ math.abs(cf.UpVector:Dot(up)) * half.Y
				+ math.abs(cf.LookVector:Dot(up)) * half.Z
			local height = (child.Position - root.Position):Dot(up)
			top = math.max(top, height + reach)
			bottom = math.min(bottom, height - reach)
			count += 1
		end
	end
	if count < 2 then
		return CONFIG.FallbackDiameter
	end
	return math.clamp((top - bottom) * CONFIG.DiameterScale, 2, 2048)
end

local function newCircle(parent: Instance, radius: number, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(radius / CANVAS, radius / CANVAS)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	frame.Parent = parent
	return frame
end

local function createEffect(forceField: ForceField, model: Model)
	local shell = Instance.new("Part")
	shell.Name = model.Name
	shell.Shape = Enum.PartType.Ball
	shell.Material = Enum.Material.ForceField
	shell.Color = CONFIG.ShellColor
	shell.Transparency = 1
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanTouch = false
	shell.CanQuery = false
	shell.CastShadow = false
	shell.Locked = true

	-- The rim is drawn on a camera-facing billboard, so it is always a perfect
	-- circle, just like the 2014 bubble.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Rim"
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = math.huge
	billboard.ClipsDescendants = false
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.Size = UDim2.fromScale(1, 1)
	billboard.Parent = shell

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.Visible = false
	canvas.Parent = billboard

	local fill = newCircle(canvas, FILL_RADIUS, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 210, 255)
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Rotation = 90 -- clear at the top, misty at the bottom
	fillGradient.Transparency = NumberSequence.new(0.88, 0)
	fillGradient.Parent = fill

	local bands = {}
	local highlight
	for index, spec in BANDS do
		local frame = newCircle(canvas, spec.inner, index + 1)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = spec.color
		stroke.Transparency = 1
		stroke.Parent = frame

		if spec.highlight then
			highlight = Instance.new("UIGradient")
			highlight.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, CONFIG.GlowColor),
				ColorSequenceKeypoint.new(0.55, CONFIG.RimColor),
				ColorSequenceKeypoint.new(1, CONFIG.HighlightColor),
			})
			highlight.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(0.55, 0.1),
				NumberSequenceKeypoint.new(1, 0),
			})
			highlight.Parent = stroke
		end

		table.insert(bands, { spec = spec, frame = frame, stroke = stroke })
	end

	local effect = {
		forceField = forceField,
		model = model,
		root = nil :: BasePart?,
		cframe = CFrame.identity,
		diameter = CONFIG.FallbackDiameter,
		size = 0,
		alpha = 0,
		visible = false,
		dying = false,
		phase = math.random() * math.pi * 2,
		shell = shell,
		billboard = billboard,
		canvas = canvas,
		fill = fill,
		bands = bands,
		highlight = highlight,
		connection = nil :: RBXScriptConnection?,
	}

	-- Re-measure when body parts show up after the ForceField does.
	effect.connection = model.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") and effect.root then
			effect.diameter = measureDiameter(model, effect.root)
		end
	end)

	shell.Parent = folder
	return effect
end

local function isWanted(forceField: ForceField): boolean
	local model = forceField.Parent
	return model ~= nil
		and model:IsA("Model")
		and model:IsDescendantOf(workspace)
		and (forceField.Visible or hiddenByUs[forceField] == true)
end

local function stop(forceField: ForceField)
	local effect = effects[forceField]
	if not effect then
		return
	end
	effects[forceField] = nil
	effect.dying = true
	if effect.connection then
		effect.connection:Disconnect()
	end
	table.insert(fading, effect)
end

local function refresh(forceField: ForceField)
	local effect = effects[forceField]
	if effect and effect.model ~= forceField.Parent then
		stop(forceField)
	end
	if not isWanted(forceField) then
		stop(forceField)
		return
	end

	-- A ForceField that is already invisible when we first see it is meant to
	-- stay invisible, so only ones we hid ourselves get the 2014 look.
	if forceField.Visible and not CONFIG.ShowModernSparkles then
		hiddenByUs[forceField] = true
		forceField.Visible = false
	end
	if not effects[forceField] then
		effects[forceField] = createEffect(forceField, forceField.Parent :: Model)
	end
end

local function watch(instance: Instance)
	if not instance:IsA("ForceField") or watched[instance] then
		return
	end
	local forceField = instance :: ForceField
	watched[forceField] = true
	forceField.AncestryChanged:Connect(function()
		refresh(forceField)
	end)
	forceField:GetPropertyChangedSignal("Visible"):Connect(function()
		refresh(forceField)
	end)
	refresh(forceField)
end

local tintFrame: Frame?
local tintGradient: UIGradient?
local tintAmount = 0

if CONFIG.ShowInsideTint then
	local gui = Instance.new("ScreenGui")
	gui.Name = "ForceField2014Tint"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -100 -- stay behind the game's own UI

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Visible = false
	frame.Parent = gui

	-- Streaky cyan and white, like looking at the inside of the bubble.
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(205, 242, 255)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(80, 185, 250)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(215, 247, 255)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(95, 195, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 240, 255)),
	})
	gradient.Parent = frame

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	tintFrame, tintGradient = frame, gradient
end

-- Points the bright end of the rim gradient at the sun, as seen on screen.
local function getHighlightRotation(camera: Camera, now: number): number
	local rotation = -45 -- top right
	if CONFIG.HighlightFollowsSun then
		local sun = Lighting:GetSunDirection()
		local x = sun:Dot(camera.CFrame.RightVector)
		local y = sun:Dot(camera.CFrame.UpVector)
		if x * x + y * y > 0.01 then
			rotation = math.deg(math.atan2(-y, x))
		end
	end
	return rotation + math.sin(now * 0.7) * 10
end

local function projectedPixels(camera: Camera, position: Vector3, studs: number): number
	local depth = (position - camera.CFrame.Position):Dot(camera.CFrame.LookVector)
	if depth <= 0 then
		return 0
	end
	return studs / (2 * depth * math.tan(math.rad(camera.FieldOfView) / 2)) * camera.ViewportSize.Y
end

-- Updates one bubble and returns how strongly it covers the camera (0 when
-- the camera is outside it).
local function updateEffect(effect, dt: number, now: number, camera: Camera, highlightRotation: number): number
	local root = effect.root
	if not effect.dying then
		if not (root and root:IsDescendantOf(effect.model)) then
			root = findRoot(effect.model)
			effect.root = root
			if root then
				effect.diameter = measureDiameter(effect.model, root)
			end
		end
		effect.visible = root ~= nil
	end
	-- Keep following the character while fading out too, so a jump doesn't
	-- leave the bubble behind. If the character is gone it stays where it was.
	if root and root:IsDescendantOf(effect.model) then
		effect.cframe = root.CFrame
	end

	if effect.dying then
		effect.alpha = math.max(effect.alpha - dt / CONFIG.FadeOutTime, 0)
	elseif effect.visible then
		effect.alpha = math.min(effect.alpha + dt / CONFIG.FadeInTime, 1)
	end

	local alpha = if effect.visible then effect.alpha else 0
	local growth = if effect.dying then 1 + (1 - effect.alpha) * DEATH_GROWTH else 1
	local radius = effect.diameter / 2 * growth
	local position = effect.cframe.Position

	if effect.size ~= radius then
		effect.size = radius
		effect.shell.Size = Vector3.one * (radius * 2)
	end
	effect.shell.CFrame = effect.cframe
	effect.shell.Transparency = if CONFIG.ShowShell then 1 - (1 - CONFIG.ShellTransparency) * alpha else 1

	local distance = (camera.CFrame.Position - position).Magnitude
	if distance <= radius or alpha <= 0 then
		effect.canvas.Visible = false
		return if distance <= radius then alpha else 0
	end

	-- Up close a sphere looks bigger than a flat disc through its middle, so
	-- grow the billboard to match the sphere's real outline.
	local perspective = math.min(distance / math.sqrt(distance * distance - radius * radius), 3)
	local studs = radius * 2 * CANVAS * perspective
	effect.billboard.Size = UDim2.fromScale(studs, studs)
	effect.canvas.Visible = true

	-- UIStroke thickness is in pixels, so keep it in step with the on-screen size.
	local pixels = effect.canvas.AbsoluteSize.X
	if pixels <= 0 then
		pixels = projectedPixels(camera, position, studs)
	end
	local pixelsPerRadius = pixels / (2 * CANVAS)
	local pulse = math.sin(now * CONFIG.PulseSpeed + effect.phase)
	local shimmer = 0.95 + 0.05 * math.sin(now * 6 + effect.phase)

	effect.fill.BackgroundTransparency = 1 - FILL_OPACITY * alpha
	for _, band in effect.bands do
		local spec = band.spec
		if spec.pulse then
			local ringRadius = spec.inner + PULSE_SWING * pulse
			band.frame.Size = UDim2.fromScale(ringRadius / CANVAS, ringRadius / CANVAS)
		end
		band.stroke.Thickness = (spec.outer - spec.inner) * pixelsPerRadius
		band.stroke.Transparency = 1 - spec.opacity * alpha * shimmer
	end
	effect.highlight.Rotation = highlightRotation

	return 0
end

local function onRenderStep(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local highlightRotation = getHighlightRotation(camera, now)
	local inside = 0

	for forceField, effect in effects do
		if not isWanted(forceField) or forceField.Parent ~= effect.model then
			stop(forceField)
		else
			inside = math.max(inside, updateEffect(effect, dt, now, camera, highlightRotation))
		end
	end

	for index = #fading, 1, -1 do
		local effect = fading[index]
		inside = math.max(inside, updateEffect(effect, dt, now, camera, highlightRotation))
		if effect.alpha <= 0 then
			effect.shell:Destroy()
			table.remove(fading, index)
		end
	end

	if tintFrame and tintGradient then
		tintAmount += (inside - tintAmount) * math.min(dt * 12, 1)
		tintFrame.Visible = tintAmount > 0.01
		tintFrame.BackgroundTransparency = 1 - (1 - CONFIG.InsideTintTransparency) * tintAmount
		tintGradient.Rotation = (now * 6) % 360
		tintGradient.Offset = Vector2.new(math.sin(now * 0.5) * 0.15, 0)
	end
end

workspace.DescendantAdded:Connect(watch)
for _, descendant in workspace:GetDescendants() do
	watch(descendant)
end

RunService:BindToRenderStep("ForceField2014", Enum.RenderPriority.Camera.Value + 1, onRenderStep)
