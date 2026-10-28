--[[
	ForceField2014 (LocalScript)

	Brings back the ROBLOX ForceField look from the October 2014 update (the
	same update that changed Smoke, Sparkles and Fire): a glowing cyan bubble
	with a bright rim and a softly pulsing inner ring, filled with the swirling
	sparkles that today's ForceField still uses. When the camera goes inside a
	bubble the screen turns cyan, like it did back then.

	It replaces the look of every ForceField in the game: SpawnLocation spawn
	protection, admin :ff commands, Instance.new("ForceField"), and so on.
	Nothing has to be uploaded; everything is built from parts, beams,
	particles and UI objects.

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

	-- The sparkles from today's ForceField: glitter rings spinning around the
	-- waist and little stars drifting up.
	ShowSparkles = true,
	SparkleColor = Color3.fromRGB(230, 242, 255),
	SpinSpeed = 2.2, -- radians per second

	ShowInsideTint = true, -- tint the screen while the camera is inside a bubble
	InsideTintTransparency = 0.6,

	HighlightFollowsSun = true, -- brightest side of the rim faces the sun
	PulseSpeed = 2.6, -- how fast the inner ring breathes in and out

	FadeInTime = 0.25,
	FadeOutTime = 1,
}

-- How far the billboard reaches, in bubble radii. Leaves room for the outer glow.
local CANVAS = 1.25

-- The rim is made of soft glows, listed back to front. Each glow is a stack of
-- faint nested rings whose opacities add up to a smooth falloff, so it keeps
-- the blurry look of the original even in HD. Distances are in bubble radii
-- (1 = the rim); a glow fades out about two spreads from its center.
local GLOWS = {
	-- soft light inside the rim, fading toward the middle
	{ center = 0.975, spreadIn = 0.11, spreadOut = 0, peak = 0.42, color = CONFIG.GlowColor, rings = 22 },
	-- haze outside the rim
	{ center = 0.98, spreadIn = 0, spreadOut = 0.07, peak = 0.4, color = CONFIG.HazeColor, rings = 18 },
	-- the inner ring that drifts in and out
	{
		center = 0.9,
		spreadIn = 0.018,
		spreadOut = 0.018,
		peak = 0.5,
		color = Color3.fromRGB(140, 225, 255),
		rings = 8,
		pulse = true,
	},
	-- the rim
	{ center = 0.98, spreadIn = 0.03, spreadOut = 0.022, peak = 0.88, color = CONFIG.RimColor, rings = 14 },
	-- its white-hot core, brightest on the side facing the sun
	{
		center = 0.98,
		spreadIn = 0.011,
		spreadOut = 0.009,
		peak = 0.7,
		color = Color3.new(1, 1, 1),
		rings = 8,
		highlight = true,
	},
}

local PULSE_SWING = 0.045 -- how far the pulsing ring moves, in bubble radii
local FILL_RADIUS = 0.96
local FILL_OPACITY = 0.16

-- The sparkles are laid out in studs for a 5 stud tall R6 character and
-- scaled to fit the real bubble.
local BASE_DIAMETER = 5 * CONFIG.DiameterScale
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPARKLE_BOX = Vector3.new(4, 1.6, 4) -- glitter and stars come out of this box

-- Swirl streaks: arcs of flat circles around the character (angles in degrees).
local ARCS = {
	{ radius = 2.1, height = -0.4, start = 0, length = 110 },
	{ radius = 2.1, height = -0.4, start = 180, length = 110 },
	{ radius = 2.5, height = -0.9, start = 60, length = 90 },
	{ radius = 2.5, height = -0.9, start = 240, length = 90 },
	{ radius = 1.8, height = 0.2, start = 120, length = 80 },
	{ radius = 1.8, height = 0.2, start = 300, length = 80 },
}
local ARC_WIDTH = 0.06
local ARC_FADE = NumberSequence.new({ -- faint tail, bright leading end
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.55, 0.65),
	NumberSequenceKeypoint.new(0.9, 0.3),
	NumberSequenceKeypoint.new(1, 0.8),
})
-- A wide, faint copy of each streak around it softens its edges.
local ARC_HALO_WIDTH = 0.24
local ARC_HALO_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.55, 0.9),
	NumberSequenceKeypoint.new(0.9, 0.78),
	NumberSequenceKeypoint.new(1, 0.95),
})

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

-- Splits a glow into nested rings of equal opacity, sized so that where they
-- overlap the opacity follows a bell curve. Returns each ring's reach inside
-- and outside the glow's center, and the opacity of a single ring.
local function glowRings(glow)
	local opacity = 1 - (1 - glow.peak) ^ (1 / glow.rings)
	local rings = {}
	for index = 1, glow.rings do
		local stacked = 1 - (1 - opacity) ^ (index - 0.5)
		local reach = math.sqrt(2 * math.log(glow.peak / stacked))
		table.insert(rings, { inner = glow.spreadIn * reach, outer = glow.spreadOut * reach })
	end
	return rings, opacity
end

local function newEmitter(parent: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Color = ColorSequence.new(CONFIG.SparkleColor, CONFIG.RimColor)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.LockedToPart = true -- particles move with the player instead of trailing behind
	emitter.Enabled = false
	emitter.Parent = parent
	return emitter
end

-- A point on a flat circle around the character, with its X axis pointing
-- along the circle so a Beam between two of them curves the right way.
local function arcPoint(radius: number, height: number, angle: number): CFrame
	local position = Vector3.new(radius * math.cos(angle), height, radius * math.sin(angle))
	local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	return CFrame.fromMatrix(position, tangent, Vector3.yAxis)
end

local function layoutSparkles(effect)
	local scale = effect.diameter / BASE_DIAMETER
	effect.anchor.Size = SPARKLE_BOX * scale

	for _, arc in effect.arcs do
		local spec = arc.spec
		local radius = spec.radius * scale
		local start = math.rad(spec.start)
		local sweep = math.rad(spec.length)
		arc.from.CFrame = arcPoint(radius, spec.height * scale, start)
		arc.to.CFrame = arcPoint(radius, spec.height * scale, start + sweep)
		-- Handle length that makes a Bezier curve follow a circle.
		local handle = 4 / 3 * math.tan(sweep / 4) * radius
		for beam, width in { [arc.beam] = ARC_WIDTH, [arc.halo] = ARC_HALO_WIDTH } do
			beam.CurveSize0 = handle
			beam.CurveSize1 = handle
			beam.Width0 = width * scale
			beam.Width1 = width * scale
		end
	end

	effect.glitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, 0.14 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	effect.stars.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.35 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	effect.stars.Speed = NumberRange.new(1 * scale, 2 * scale)
	effect.stars.Acceleration = Vector3.new(0, 0.5 * scale, 0)
end

local function setDiameter(effect, diameter: number)
	if effect.diameter ~= diameter then
		effect.diameter = diameter
		layoutSparkles(effect)
	end
end

-- Welds the bubble to a character part, or freezes it in place when there is
-- nothing to hold on to. It is never anchored while welded, since that would
-- anchor the character too.
local function attach(effect, root: BasePart?)
	effect.root = root
	if root then
		effect.anchor.CFrame = root.CFrame
		effect.anchor.Anchored = false
		effect.weld.Part0 = root
	else
		effect.weld.Part0 = nil
		effect.anchor.Anchored = true
	end
end

local function createEffect(forceField: ForceField, model: Model)
	-- Invisible part that carries everything. It gets welded to the character,
	-- so the bubble can't fall behind, even while it fades out.
	local anchor = Instance.new("Part")
	anchor.Name = model.Name
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Massless = true
	anchor.Locked = true

	local weld = Instance.new("Weld")
	weld.Part1 = anchor
	weld.Parent = anchor

	local glitter = newEmitter(anchor)
	glitter.Rate = 40
	glitter.Lifetime = NumberRange.new(0.6, 1.2)
	glitter.Speed = NumberRange.new(0)
	glitter.Rotation = NumberRange.new(0, 360)
	glitter.Transparency = NumberSequence.new(0.15)

	local stars = newEmitter(anchor)
	stars.Rate = 5
	stars.Lifetime = NumberRange.new(1, 1.6)
	stars.Transparency = NumberSequence.new(0.1, 0.5)

	local arcs = {}
	for _, spec in ARCS do
		local from = Instance.new("Attachment")
		from.Parent = anchor
		local to = Instance.new("Attachment")
		to.Parent = anchor

		local beam = Instance.new("Beam")
		beam.Attachment0 = from
		beam.Attachment1 = to
		beam.FaceCamera = true
		beam.Segments = 16
		beam.Color = ColorSequence.new(CONFIG.SparkleColor)
		beam.Transparency = ARC_FADE
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.LocalTransparencyModifier = 1
		beam.Parent = anchor

		local halo = beam:Clone()
		halo.Transparency = ARC_HALO_FADE
		halo.Parent = anchor

		table.insert(arcs, { spec = spec, from = from, to = to, beam = beam, halo = halo })
	end

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
	billboard.Parent = anchor

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

	local rings = {}
	local highlights = {}
	for index, glow in GLOWS do
		local reaches, opacity = glowRings(glow)
		for _, reach in reaches do
			local frame = newCircle(canvas, glow.center - reach.inner, index + 1)
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Color = glow.color
			stroke.Transparency = 1
			stroke.Parent = frame

			if glow.highlight then
				local gradient = Instance.new("UIGradient")
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, CONFIG.GlowColor),
					ColorSequenceKeypoint.new(0.55, CONFIG.RimColor),
					ColorSequenceKeypoint.new(1, CONFIG.HighlightColor),
				})
				gradient.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.3),
					NumberSequenceKeypoint.new(0.55, 0.1),
					NumberSequenceKeypoint.new(1, 0),
				})
				gradient.Parent = stroke
				table.insert(highlights, gradient)
			end

			table.insert(rings, {
				glow = glow,
				inner = reach.inner,
				outer = reach.outer,
				opacity = opacity,
				frame = frame,
				stroke = stroke,
			})
		end
	end

	local effect = {
		forceField = forceField,
		model = model,
		root = nil :: BasePart?,
		diameter = CONFIG.FallbackDiameter,
		alpha = 0,
		visible = false,
		dying = false,
		phase = math.random() * math.pi * 2,
		anchor = anchor,
		weld = weld,
		glitter = glitter,
		stars = stars,
		arcs = arcs,
		billboard = billboard,
		canvas = canvas,
		fill = fill,
		rings = rings,
		highlights = highlights,
		pixelsPerRadius = 0, -- on-screen size the ring widths were last set for
		drawnAlpha = -1, -- fade level the ring transparencies were last set for
		connection = nil :: RBXScriptConnection?,
	}
	layoutSparkles(effect)

	-- Re-measure when body parts show up after the ForceField does.
	effect.connection = model.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") and effect.root then
			setDiameter(effect, measureDiameter(model, effect.root))
		end
	end)

	anchor.Parent = folder
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

	-- Hide Roblox's own ForceField look; the sparkles are rebuilt above. One
	-- that is already invisible when we first see it is meant to stay invisible,
	-- so only ones we hid ourselves get the 2014 look.
	if forceField.Visible then
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
	if root and not root:IsDescendantOf(effect.model) then
		-- The part we were welded to is gone (respawn, streaming). Stay where we
		-- are until there's a new one.
		attach(effect, nil)
		root = nil
	end
	if not root and not effect.dying then
		root = findRoot(effect.model)
		if root then
			attach(effect, root)
			setDiameter(effect, measureDiameter(effect.model, root))
		end
	end
	if not effect.dying then
		effect.visible = root ~= nil
	end

	if effect.dying then
		effect.alpha = math.max(effect.alpha - dt / CONFIG.FadeOutTime, 0)
	elseif effect.visible then
		effect.alpha = math.min(effect.alpha + dt / CONFIG.FadeInTime, 1)
	end
	local alpha = if effect.visible then effect.alpha else 0

	-- Spin the sparkles. Particles are locked to the spinning part, so they
	-- swirl around the character and fade with it.
	effect.weld.C0 = CFrame.Angles(0, effect.phase - now * CONFIG.SpinSpeed, 0)
	local sparkling = CONFIG.ShowSparkles and effect.visible and not effect.dying
	effect.glitter.Enabled = sparkling
	effect.stars.Enabled = sparkling
	local sparkleFade = if CONFIG.ShowSparkles then 1 - alpha else 1
	effect.glitter.LocalTransparencyModifier = sparkleFade
	effect.stars.LocalTransparencyModifier = sparkleFade
	for _, arc in effect.arcs do
		arc.beam.LocalTransparencyModifier = sparkleFade
		arc.halo.LocalTransparencyModifier = sparkleFade
	end

	local radius = effect.diameter / 2
	local position = if root then root.Position else effect.anchor.Position
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
	-- There are a lot of rings, so widths are only redone when the on-screen
	-- size changes by more than 1%, and transparencies only while fading.
	local pixelsPerRadius = pixels / (2 * CANVAS)
	local resize = math.abs(pixelsPerRadius - effect.pixelsPerRadius) > effect.pixelsPerRadius * 0.01
	if resize then
		effect.pixelsPerRadius = pixelsPerRadius
	end
	local refade = alpha ~= effect.drawnAlpha
	effect.drawnAlpha = alpha
	local pulse = math.sin(now * CONFIG.PulseSpeed + effect.phase)
	local shimmer = 0.95 + 0.05 * math.sin(now * 6 + effect.phase)

	effect.fill.BackgroundTransparency = 1 - FILL_OPACITY * alpha
	for _, ring in effect.rings do
		local glow = ring.glow
		if glow.pulse then
			local radius = glow.center + PULSE_SWING * pulse - ring.inner
			ring.frame.Size = UDim2.fromScale(radius / CANVAS, radius / CANVAS)
		end
		if resize then
			ring.stroke.Thickness = (ring.inner + ring.outer) * pixelsPerRadius
		end
		if refade or glow.highlight then
			local strength = if glow.highlight then alpha * shimmer else alpha
			ring.stroke.Transparency = 1 - ring.opacity * strength
		end
	end
	for _, gradient in effect.highlights do
		gradient.Rotation = highlightRotation
	end

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
			effect.anchor:Destroy()
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
