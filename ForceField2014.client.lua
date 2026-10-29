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

local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
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

	-- The sparkles from today's ForceField: a glittery swirl spinning around the
	-- waist and little stars floating up. The swirl image is built into this
	-- script, so nothing has to be uploaded. To use an uploaded copy of
	-- textures/ForceFieldSwirl.png instead, paste its image ID here, like
	-- "rbxassetid://1234567890".
	ShowSparkles = true,
	SwirlTexture = "",
	SwirlColor = Color3.new(1, 1, 1), -- tints the swirl
	SwirlFramerate = 30, -- flipbook frames per second; 16 frames make one full turn
	SparkleSize = 1, -- scales the swirl and the stars

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
local SPARKLE_TEXTURE = Content.fromUri("rbxasset://textures/particles/sparkles_main.dds")

-- The swirl is a 4x4 flipbook of a glittery ring seen from a slight angle, and
-- each frame turns it a bit further. A couple of copies overlap at a time,
-- fading in and out, so it shimmers.
local SWIRL_HEIGHT = -0.25 -- studs below the center of the character's root part
local SWIRL_SIZE = 1 -- particle width as a fraction of the bubble's diameter
-- The swirl image built into the script holds 8 frames, each the 116 rows of
-- a 256x256 frame that aren't empty (starting at row 70), with 64 levels of
-- transparency. The flipbook has 16 frames, but frames 9-16 are almost exactly
-- frames 1-8 again, so they're reused.
local SWIRL_CELL = 256
local SWIRL_TOP = 70
local SWIRL_ROWS = 116
local SWIRL_DATA: string -- set near the bottom of the script

local SWIRL_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.25, 0.3),
	NumberSequenceKeypoint.new(0.75, 0.3),
	NumberSequenceKeypoint.new(1, 1),
})

-- The stars float up out of this box.
local STAR_BOX = Vector3.new(4.4, 3.2, 4.4)
local STAR_COLORS = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 235, 255))

-- Star size over its lifetime: { time, size, random variation }.
local STAR_SIZE = { { 0, 0 }, { 0.3, 0.22, 0.06 }, { 1, 0 } }

local localPlayer = Players.LocalPlayer

local swirlTexture: Content? -- built the first time a bubble needs it
local swirlTextureTried = false

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

local function sizeSequence(keys, scale: number): NumberSequence
	local keypoints = {}
	for _, key in keys do
		table.insert(keypoints, NumberSequenceKeypoint.new(key[1], key[2] * scale, (key[3] or 0) * scale))
	end
	return NumberSequence.new(keypoints)
end

-- An invisible part that only carries effects: no collisions, no weight.
local function newCarrier(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Locked = true
	return part
end

local function newEmitter(parent: Instance, texture: Content, colors: ColorSequence): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.TextureContent = texture
	emitter.Color = colors
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.LockedToPart = true -- particles move with the player instead of trailing behind
	emitter.Enabled = false
	emitter.Parent = parent
	return emitter
end

local function layoutSparkles(effect)
	local scale = effect.diameter / BASE_DIAMETER
	effect.anchor.Size = STAR_BOX * scale

	if effect.swirl then
		effect.swirl.Parent.Position = Vector3.new(0, SWIRL_HEIGHT * scale, 0)
		effect.swirl.Size = NumberSequence.new(effect.diameter * SWIRL_SIZE * CONFIG.SparkleSize)
	end

	local particleScale = scale * CONFIG.SparkleSize
	effect.stars.Size = sizeSequence(STAR_SIZE, particleScale)
	effect.stars.Speed = NumberRange.new(1.2 * scale, 2.4 * scale)
	effect.stars.Acceleration = Vector3.new(0, 0.6 * scale, 0)
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

-- Unpacks SWIRL_DATA into a 1024x1024 flipbook image (4x4 frames). Its color
-- is the original's warm white, a little whiter where it's brighter.
local function buildSwirlImage(): Content
	local packed = buffer.fromstring((string.gsub(SWIRL_DATA, "%s", "")))
	local levels =
		EncodingService:DecompressBuffer(EncodingService:Base64Decode(packed), Enum.CompressionAlgorithm.Zstd)

	-- The RGBA pixel for each transparency level, packed for buffer.writeu32.
	local colors = {}
	for level = 0, 63 do
		local opacity = level / 63
		local green = math.round(240 + 4 * opacity)
		local blue = math.round(215 + 15 * opacity)
		colors[level] = 255 + green * 0x100 + blue * 0x10000 + math.round(opacity * 255) * 0x1000000
	end

	local size = SWIRL_CELL * 4
	local rowBytes = size * 4
	local pixels = buffer.create(size * rowBytes)
	local emptyRow = buffer.create(rowBytes)
	for x = 0, size - 1 do
		buffer.writeu32(emptyRow, x * 4, colors[0])
	end

	-- Frames 1-8 fill the top two rows of frames, and the bottom two repeat them.
	local half = size // 2
	for y = 0, half - 1 do
		local row = y % SWIRL_CELL - SWIRL_TOP
		if row < 0 or row >= SWIRL_ROWS then
			buffer.copy(pixels, y * rowBytes, emptyRow)
		else
			local frameRow = y // SWIRL_CELL
			for x = 0, size - 1 do
				local frame = frameRow * 4 + x // SWIRL_CELL
				local level = buffer.readu8(levels, (frame * SWIRL_ROWS + row) * SWIRL_CELL + x % SWIRL_CELL)
				buffer.writeu32(pixels, y * rowBytes + x * 4, colors[level])
			end
		end
	end
	buffer.copy(pixels, half * rowBytes, pixels, 0, half * rowBytes)

	local image = AssetService:CreateEditableImage({ Size = Vector2.new(size, size) })
	assert(image, "not enough memory for it")
	image:WritePixelsBuffer(Vector2.zero, image.Size, pixels)
	return Content.fromObject(image)
end

-- The uploaded swirl image if CONFIG.SwirlTexture is set, otherwise the one
-- built into the script. nil if it can't be built.
local function getSwirlTexture(): Content?
	if CONFIG.SwirlTexture ~= "" then
		return Content.fromUri(CONFIG.SwirlTexture)
	end
	if not swirlTextureTried then
		swirlTextureTried = true
		local ok, result = pcall(buildSwirlImage)
		if ok then
			swirlTexture = result
		else
			warn(
				"ForceField2014: couldn't build the swirl image ("
					.. tostring(result)
					.. "). In a published game, turn on Allow Mesh / Image APIs in Game Settings > Security,"
					.. " or upload textures/ForceFieldSwirl.png and set CONFIG.SwirlTexture."
			)
		end
	end
	return swirlTexture
end

local function createEffect(forceField: ForceField, model: Model)
	-- Invisible part that carries everything. It gets welded to the character,
	-- so the bubble can't fall behind, even while it fades out.
	local anchor = newCarrier(model.Name)
	anchor.Anchored = true

	local weld = Instance.new("Weld")
	weld.Part1 = anchor
	weld.Parent = anchor

	-- The glittery swirl around the waist. It's camera-facing, since the ring is
	-- already drawn at an angle in the image, and it turns by stepping through
	-- the flipbook. It sits on an attachment so every copy starts at the center.
	local swirl
	local swirlImage = if CONFIG.ShowSparkles then getSwirlTexture() else nil
	if swirlImage then
		local center = Instance.new("Attachment")
		center.Name = "Swirl"
		center.Parent = anchor

		swirl = newEmitter(center, swirlImage, ColorSequence.new(CONFIG.SwirlColor))
		swirl.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		swirl.FlipbookMode = Enum.ParticleFlipbookMode.Loop
		swirl.FlipbookFramerate = NumberRange.new(CONFIG.SwirlFramerate)
		swirl.FlipbookStartRandom = true
		swirl.Rate = 1.5
		swirl.Lifetime = NumberRange.new(1.4)
		swirl.Speed = NumberRange.new(0)
		swirl.Transparency = SWIRL_FADE
	end

	-- Little four-pointed stars floating up and out of the bubble.
	local stars = newEmitter(anchor, SPARKLE_TEXTURE, STAR_COLORS)
	stars.Rate = 3
	stars.Lifetime = NumberRange.new(1.2, 2)
	stars.SpreadAngle = Vector2.new(15, 15)
	stars.Transparency = NumberSequence.new(0.05, 0.3)

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
		swirl = swirl,
		stars = stars,
		emitters = if swirl then { swirl, stars } else { stars },
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

	-- The particles are locked to the anchor, so they move with the character,
	-- and fade out along with the bubble.
	local sparkling = CONFIG.ShowSparkles and effect.visible and not effect.dying
	local sparkleFade = if CONFIG.ShowSparkles then 1 - alpha else 1
	for _, emitter in effect.emitters do
		emitter.Enabled = sparkling
		emitter.LocalTransparencyModifier = sparkleFade
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

-- The swirl image (see buildSwirlImage): Base64 of Zstd-compressed transparency
-- levels for 8 frames, made from textures/ForceFieldSwirl.png.
SWIRL_DATA = [[
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
]]

workspace.DescendantAdded:Connect(watch)
for _, descendant in workspace:GetDescendants() do
	watch(descendant)
end

RunService:BindToRenderStep("ForceField2014", Enum.RenderPriority.Camera.Value + 1, onRenderStep)
