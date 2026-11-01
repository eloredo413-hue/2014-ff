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

	-- The sparkles from today's ForceField: a glittery swirl spinning around the
	-- waist and little stars floating up. The swirl is rebuilt from the
	-- ForceField's own swirl image (textures/ForceFieldSwirl.png) out of shapes
	-- Roblox can always draw, so nothing has to be uploaded. To show the image
	-- itself instead, upload it and paste its image ID here, like
	-- "rbxassetid://1234567890".
	ShowSparkles = true,
	SwirlTexture = "",
	SwirlColor = Color3.new(1, 1, 1), -- tints the swirl
	SwirlFramerate = 30, -- swirl speed in image frames per second; 16 frames make one full turn
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
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- The swirl. The original is a 4x4 flipbook (textures/ForceFieldSwirl.png) of a
-- glittery disc seen from a slight angle: squashed to 48% of its width, tilted
-- 4.5 degrees, and turned 22.5 degrees further in each frame. Unless an uploaded
-- copy is set, the same disc is rebuilt on a part that always leans toward the
-- camera that way and spins: rings and spiral arcs are drawn with UIStrokes, and
-- the glints' brightness follows the original frame by frame. The shapes come
-- from tracing the original image (SWIRL_ARCS and friends, near the bottom).
local SWIRL_HEIGHT = -0.25 -- studs below the center of the character's root part
local SWIRL_SIZE = 1 -- uploaded flipbook: particle width as a fraction of the bubble's diameter
local SWIRL_RADIUS = 0.449 -- rebuilt disc: radius as a fraction of the bubble's diameter
local SWIRL_SQUASH = 0.48
local SWIRL_ROLL = math.rad(4.5)
local SWIRL_STEP = math.rad(22.5)
local SWIRL_CANVAS = 512 -- SurfaceGui pixels across the disc part
local SWIRL_EXTENT = 1.15 -- the disc part reaches this far out, in disc radii
local SWIRL_TWINKLE_RATE = 15 -- glint brightness updates per second
-- Each glint is nested soft discs { radius, opacity }, matching the original's
-- falloff. Radii are in the original image's pixels; its disc is 115 of them.
local GLINT_DISCS = { { 1, 0.8 }, { 2, 0.33 }, { 3, 0.2 }, { 4, 0.17 }, { 5.5, 0.1 } }
local GLINT_PIXEL = 1 / 115
local SWIRL_ARCS, SWIRL_GLOWS, SWIRL_GLINTS, SWIRL_TWINKLE, SWIRL_RING_COLOR -- set near the bottom of the script

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

local swirlTemplate: SurfaceGui? -- built the first time a bubble needs it

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

local function newEmitter(parent: Instance, texture: string, colors: ColorSequence): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
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
	effect.scale = scale
	effect.anchor.Size = STAR_BOX * scale

	if effect.swirlDisc then
		local width = 2 * SWIRL_EXTENT * SWIRL_RADIUS * effect.diameter * CONFIG.SparkleSize
		effect.swirlDisc.part.Size = Vector3.new(width, width, 0.05)
	end

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

-- A soft band: 3 nested strokes of equal opacity whose overlap follows a bell
-- curve, like the rim's glows. Width is the band's full width at half brightness.
local function bandLayers(peak: number, width: number)
	local sigma = width / 2.355
	local reaches, opacity = glowRings({ peak = math.min(peak, 0.95), rings = 3, spreadIn = sigma, spreadOut = sigma })
	local layers = {}
	for _, reach in reaches do
		table.insert(layers, { thickness = reach.inner + reach.outer, opacity = opacity })
	end
	return layers
end

-- The part of a ring a UIGradient mask lets through: fully visible within 60% of
-- the arc's half length from its middle, gone by 115%. Along the ring the
-- gradient position is 0.5 + 0.5 * k * cos(angle from the middle).
local function arcMask(half: number, k: number): NumberSequence
	local function at(angle: number): number
		return 0.5 + 0.5 * k * math.cos(math.min(angle, math.pi))
	end
	local gone = math.max(at(half * 1.15), 0.001)
	local full = math.clamp(at(half * 0.6), gone + 0.001, 0.999)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(gone, 1),
		NumberSequenceKeypoint.new(full, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
end

-- Builds the rebuilt swirl once, as a SurfaceGui that gets cloned onto each
-- bubble's disc. Positions are in disc radii, with y pointing down like in the
-- original image.
local function buildSwirlTemplate(): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Swirl"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(SWIRL_CANVAS, SWIRL_CANVAS)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = 250
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Disc"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = gui

	local unit = SWIRL_CANVAS / 2 / SWIRL_EXTENT -- canvas pixels per disc radius
	local function place(frame: GuiObject, x: number, y: number)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(SWIRL_CANVAS / 2 + x * unit, SWIRL_CANVAS / 2 + y * unit)
	end

	-- Rings and arcs. The stroke sits just outside its circle, so the circle is
	-- shrunk by half the stroke to center the band on the radius.
	local function band(
		x: number,
		y: number,
		radius: number,
		width: number,
		peak: number,
		middle: number?,
		half: number?
	)
		for _, layer in bandLayers(peak, width) do
			local frame = Instance.new("Frame")
			place(frame, x, y)
			local size = math.max(2 * radius - layer.thickness, 0) * unit
			frame.Size = UDim2.fromOffset(size, size)
			frame.BackgroundTransparency = 1
			frame.ZIndex = 1

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = frame

			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Color = SWIRL_RING_COLOR
			stroke.Thickness = layer.thickness * unit
			stroke.Transparency = 1
			stroke:SetAttribute("Opacity", layer.opacity)
			stroke.Parent = frame

			if middle and half then
				local mask = Instance.new("UIGradient")
				mask.Rotation = middle
				mask.Transparency = arcMask(math.rad(half), radius / (radius + layer.thickness / 2))
				mask.Parent = stroke
			end
			frame.Parent = root
		end
	end
	for _, glow in SWIRL_GLOWS do
		band(0, 0, glow[1], glow[2], glow[3])
	end
	for _, arc in SWIRL_ARCS do
		band(arc[1], arc[2], arc[3], arc[7], arc[6], arc[4], arc[5])
	end

	-- Glints. Each one is stretched along the canvas so it looks round once the
	-- disc leans away; the stretch is kept pointing down the screen as it spins.
	local biggest = GLINT_DISCS[#GLINT_DISCS][1]
	for index, glint in SWIRL_GLINTS do
		local reach = biggest * glint[3] * GLINT_PIXEL * unit
		local holder = Instance.new("Frame")
		holder.Name = "Glint"
		place(holder, glint[1], glint[2])
		holder.Size = UDim2.fromOffset(2 * reach, 2 * reach / SWIRL_SQUASH)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 2
		holder:SetAttribute("Glint", index)
		for _, disc in GLINT_DISCS do
			local layer = Instance.new("Frame")
			layer.AnchorPoint = Vector2.new(0.5, 0.5)
			layer.Position = UDim2.fromScale(0.5, 0.5)
			layer.Size = UDim2.fromScale(disc[1] / biggest, disc[1] / biggest)
			layer.BackgroundColor3 = Color3.fromRGB(glint[4], glint[5], glint[6])
			layer.BackgroundTransparency = 1
			layer.BorderSizePixel = 0
			layer.ZIndex = 2
			layer:SetAttribute("Opacity", disc[2])
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = layer
			layer.Parent = holder
		end
		holder.Parent = root
	end
	return gui
end

-- Gives a bubble its own copy of the rebuilt swirl, on a disc part welded to
-- the anchor.
local function newSwirlDisc(anchor: BasePart)
	if not swirlTemplate then
		swirlTemplate = buildSwirlTemplate()
	end
	local part = newCarrier("Swirl")
	local weld = Instance.new("Weld")
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = part

	local gui = (swirlTemplate :: SurfaceGui):Clone()
	gui.Adornee = part
	gui.Parent = part
	part.Parent = anchor

	local strokes, glints = {}, {}
	for _, item in gui:GetDescendants() do
		if item:IsA("UIStroke") then
			table.insert(strokes, item)
		elseif item:GetAttribute("Glint") then
			local layers = {}
			for _, layer in item:GetChildren() do
				table.insert(layers, layer)
			end
			glints[item:GetAttribute("Glint")] = { holder = item, layers = layers }
		end
	end
	return {
		part = part,
		weld = weld,
		root = gui:FindFirstChild("Disc") :: Frame,
		strokes = strokes,
		glints = glints,
		angle = math.random() * math.pi * 2,
		twinkleClock = math.huge,
		drawnAlpha = -1,
	}
end

local function createEffect(forceField: ForceField, model: Model)
	-- Invisible part that carries everything. It gets welded to the character,
	-- so the bubble can't fall behind, even while it fades out.
	local anchor = newCarrier(model.Name)
	anchor.Anchored = true

	local weld = Instance.new("Weld")
	weld.Part1 = anchor
	weld.Parent = anchor

	-- The glittery swirl around the waist: the uploaded flipbook if there is one,
	-- otherwise the rebuilt disc. The flipbook particles face the camera, since the
	-- disc is already drawn at an angle in the image, and sit on an attachment so
	-- every copy starts at the center.
	local swirl, swirlDisc
	if CONFIG.ShowSparkles and CONFIG.SwirlTexture ~= "" then
		local center = Instance.new("Attachment")
		center.Name = "Swirl"
		center.Parent = anchor

		swirl = newEmitter(center, CONFIG.SwirlTexture, ColorSequence.new(CONFIG.SwirlColor))
		swirl.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		swirl.FlipbookMode = Enum.ParticleFlipbookMode.Loop
		swirl.FlipbookFramerate = NumberRange.new(CONFIG.SwirlFramerate)
		swirl.FlipbookStartRandom = true
		swirl.Rate = 1.5
		swirl.Lifetime = NumberRange.new(1.4)
		swirl.Speed = NumberRange.new(0)
		swirl.Transparency = SWIRL_FADE
	elseif CONFIG.ShowSparkles then
		swirlDisc = newSwirlDisc(anchor)
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
		scale = 1,
		swirl = swirl,
		swirlDisc = swirlDisc,
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

-- Leans the rebuilt swirl toward the camera the way the original image shows it
-- (seen 28.7 degrees from edge-on, rolled 4.5 degrees), spins it, keeps the
-- glints round, and plays their twinkle from the original frames.
local function updateSwirl(effect, dt: number, camera: Camera, alpha: number, show: boolean)
	local swirl = effect.swirlDisc
	swirl.root.Visible = show
	if not show then
		return
	end
	swirl.angle = (swirl.angle + dt * SWIRL_STEP * CONFIG.SwirlFramerate) % (math.pi * 2)

	local position = (effect.anchor.CFrame * CFrame.new(0, SWIRL_HEIGHT * effect.scale, 0)).Position
	local toCamera = (camera.CFrame.Position - position).Unit
	local cameraRight, cameraUp = camera.CFrame.RightVector, camera.CFrame.UpVector
	local right = cameraRight * math.cos(SWIRL_ROLL) - cameraUp * math.sin(SWIRL_ROLL)
	local up = cameraRight * math.sin(SWIRL_ROLL) + cameraUp * math.cos(SWIRL_ROLL)
	local upOnScreen = (up - toCamera * up:Dot(toCamera)).Unit
	local normal = toCamera * SWIRL_SQUASH + upOnScreen * math.sqrt(1 - SWIRL_SQUASH * SWIRL_SQUASH)
	local across = (right - normal * right:Dot(normal)).Unit -- screen right, on the disc
	local down = across:Cross(normal) -- screen down, on the disc
	local cos, sin = math.cos(swirl.angle), math.sin(swirl.angle)
	local canvasRight = across * cos + down * sin
	local canvasDown = down * cos - across * sin
	-- A Front-face SurfaceGui runs right along -RightVector and down along -UpVector.
	local disc = CFrame.fromMatrix(position, -canvasRight, -canvasDown)
	swirl.weld.C0 = effect.anchor.CFrame:ToObjectSpace(disc)

	-- Keep each glint's stretch pointing down the screen.
	local rotation = -math.deg(swirl.angle)
	for _, glint in swirl.glints do
		glint.holder.Rotation = rotation
	end

	-- Twinkle (a few times a second) and fades.
	swirl.twinkleClock += dt
	if swirl.twinkleClock < 1 / SWIRL_TWINKLE_RATE and alpha == swirl.drawnAlpha then
		return
	end
	swirl.twinkleClock = 0
	local frame = swirl.angle / SWIRL_STEP
	local first = math.floor(frame) % 16
	local blend = frame - math.floor(frame)
	for index, glint in swirl.glints do
		local levels = SWIRL_TWINKLE[index]
		local brightness = (levels[first + 1] * (1 - blend) + levels[(first + 1) % 16 + 1] * blend) * alpha
		for _, layer in glint.layers do
			layer.BackgroundTransparency = 1 - math.min(layer:GetAttribute("Opacity") * brightness, 0.95)
		end
	end
	if alpha ~= swirl.drawnAlpha then
		swirl.drawnAlpha = alpha
		for _, stroke in swirl.strokes do
			stroke.Transparency = 1 - stroke:GetAttribute("Opacity") * alpha
		end
	end
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
	if effect.swirlDisc then
		updateSwirl(effect, dt, camera, alpha, CONFIG.ShowSparkles and alpha > 0 and distance > radius)
	end
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

-- The rebuilt swirl, traced from textures/ForceFieldSwirl.png (see the README).
-- Positions are in disc radii with y pointing down, angles in degrees, and each
-- arc comes in a pair half a turn apart, like in the original.
SWIRL_ARCS = {
	-- { center x, center y, radius, middle angle, half length (degrees), peak opacity, width }
	{ 0.0474, 0.1391, 0.4302, 2.1, 26.4, 0.661, 0.1118 },
	{ -0.0474, -0.1391, 0.4302, 182.1, 26.4, 0.661, 0.1118 },
	{ -0.0243, 0.1034, 0.5102, 51.8, 24.7, 0.637, 0.0923 },
	{ 0.0243, -0.1034, 0.5102, 231.8, 24.7, 0.637, 0.0923 },
	{ -0.0363, 0.0656, 0.5497, 96.3, 23.8, 0.432, 0.1200 },
	{ 0.0363, -0.0656, 0.5497, 276.3, 23.8, 0.432, 0.1200 },
	{ -0.0528, -0.0138, 0.4052, 109.4, 22.1, 0.184, 0.1200 },
	{ 0.0528, 0.0138, 0.4052, 289.4, 22.1, 0.184, 0.1200 },
	{ -0.0291, -0.0418, 0.4419, 149.5, 21.9, 0.376, 0.0961 },
	{ 0.0291, 0.0418, 0.4419, 329.5, 21.9, 0.376, 0.0961 },
	{ -0.0221, -0.0471, 0.8875, 85.7, 17.1, 0.150, 0.0747 },
	{ 0.0221, 0.0471, 0.8875, 265.7, 17.1, 0.150, 0.0747 },
	{ -0.0173, -0.0656, 0.9066, 119.8, 17.3, 0.210, 0.0655 },
	{ 0.0173, 0.0656, 0.9066, 299.8, 17.3, 0.210, 0.0655 },
	{ 0.0096, -0.0897, 0.9428, 154.1, 17.5, 0.199, 0.0619 },
	{ -0.0096, 0.0897, 0.9428, 334.1, 17.5, 0.199, 0.0619 },
	{ 0.0306, -0.0520, 0.7881, 122.8, 19.4, 0.392, 0.1084 },
	{ -0.0306, 0.0520, 0.7881, 302.8, 19.4, 0.392, 0.1084 },
	{ -0.0504, 0.0407, 0.6768, 66.9, 25.2, 0.238, 0.1200 },
	{ 0.0504, -0.0407, 0.6768, 246.9, 25.2, 0.238, 0.1200 },
	{ 0.0065, -0.0718, 0.8044, 157.3, 14.6, 0.243, 0.0835 },
	{ -0.0065, 0.0718, 0.8044, 337.3, 14.6, 0.243, 0.0835 },
	{ -0.0189, 0.0313, 0.4184, 31.0, 6.1, 0.397, 0.1200 },
	{ 0.0189, -0.0313, 0.4184, 211.0, 6.1, 0.397, 0.1200 },
	{ 0.0163, -0.0018, 0.3613, 83.6, 9.1, 0.208, 0.0671 },
	{ -0.0163, 0.0018, 0.3613, 263.6, 9.1, 0.208, 0.0671 },
	{ 0.0632, -0.0073, 0.4820, 82.5, 6.1, 0.355, 0.0807 },
	{ -0.0632, 0.0073, 0.4820, 262.5, 6.1, 0.355, 0.0807 },
	{ 0.0235, 0.0966, 0.5887, 165.6, 6.1, 0.281, 0.1200 },
	{ -0.0235, -0.0966, 0.5887, 345.6, 6.1, 0.281, 0.1200 },
	{ 0.0048, 0.0045, 0.2986, 133.3, 9.0, 0.134, 0.1200 },
	{ -0.0048, -0.0045, 0.2986, 313.3, 9.0, 0.134, 0.1200 },
	{ -0.0049, 0.0457, 0.9208, 6.1, 9.1, 0.103, 0.0630 },
	{ 0.0049, -0.0457, 0.9208, 186.1, 9.1, 0.103, 0.0630 },
	{ -0.0000, -0.0000, 0.7408, 18.0, 6.0, 0.164, 0.1200 },
	{ 0.0000, 0.0000, 0.7408, 198.0, 6.0, 0.164, 0.1200 },
	{ -0.0000, -0.0000, 0.7863, 6.0, 6.0, 0.104, 0.1200 },
	{ 0.0000, 0.0000, 0.7863, 186.0, 6.0, 0.104, 0.1200 },
}
SWIRL_GLOWS = { -- full rings: { radius, width, peak opacity }
	{ 0.580, 0.350, 0.180 },
	{ 0.850, 0.250, 0.080 },
}
SWIRL_GLINTS = { -- { x, y, size, red, green, blue }
	{ 0.0625, -0.8125, 0.80, 255, 233, 205 },
	{ -0.2542, -0.8042, 0.80, 255, 234, 209 },
	{ 0.3792, -0.8042, 0.80, 254, 231, 203 },
	{ 0.1208, -0.6458, 1.25, 254, 247, 238 },
	{ -0.4208, -0.6292, 0.80, 255, 235, 210 },
	{ -0.0542, -0.6208, 1.25, 254, 249, 243 },
	{ 0.6458, -0.5708, 0.80, 255, 231, 201 },
	{ 0.4125, -0.5542, 1.25, 253, 246, 236 },
	{ -0.2875, -0.5125, 1.25, 254, 248, 239 },
	{ 0.2292, -0.4958, 0.80, 254, 244, 230 },
	{ -0.6208, -0.4875, 1.00, 255, 237, 217 },
	{ -0.1292, -0.4708, 0.80, 254, 245, 235 },
	{ 0.5625, -0.4375, 1.00, 254, 243, 228 },
	{ -0.3792, -0.4042, 1.25, 254, 250, 245 },
	{ -0.0708, -0.3458, 0.85, 255, 248, 242 },
	{ 0.8792, -0.2792, 0.80, 254, 230, 199 },
	{ -0.3458, -0.2458, 0.80, 254, 247, 238 },
	{ 0.2042, -0.2208, 0.80, 254, 245, 234 },
	{ 0.5625, -0.2208, 0.80, 254, 242, 226 },
	{ -0.7042, -0.2042, 0.85, 255, 238, 219 },
	{ -0.4708, -0.1958, 1.25, 254, 248, 241 },
	{ -0.2792, -0.1542, 0.80, 255, 246, 238 },
	{ -0.4625, -0.0708, 1.25, 253, 249, 243 },
	{ 0.4625, 0.0708, 1.25, 253, 249, 243 },
	{ 0.2792, 0.1542, 0.80, 255, 246, 238 },
	{ 0.4708, 0.1958, 1.25, 254, 248, 241 },
	{ 0.7042, 0.2042, 0.85, 255, 238, 219 },
	{ -0.5625, 0.2208, 0.80, 254, 242, 226 },
	{ -0.2042, 0.2208, 0.80, 254, 245, 234 },
	{ 0.3458, 0.2458, 0.80, 254, 247, 238 },
	{ -0.8792, 0.2792, 0.80, 254, 230, 199 },
	{ 0.0708, 0.3458, 0.85, 255, 248, 242 },
	{ 0.3792, 0.4042, 1.25, 254, 250, 245 },
	{ -0.5625, 0.4375, 1.00, 254, 243, 228 },
	{ 0.1292, 0.4708, 0.80, 254, 245, 235 },
	{ 0.6208, 0.4875, 1.00, 255, 237, 217 },
	{ -0.2292, 0.4958, 0.80, 254, 244, 230 },
	{ 0.2875, 0.5125, 1.25, 254, 248, 239 },
	{ -0.4125, 0.5542, 1.25, 253, 246, 236 },
	{ -0.6458, 0.5708, 0.80, 255, 231, 201 },
	{ 0.0542, 0.6208, 1.25, 254, 249, 243 },
	{ 0.4208, 0.6292, 0.80, 255, 235, 210 },
	{ -0.1208, 0.6458, 1.25, 254, 247, 238 },
	{ -0.3792, 0.8042, 0.80, 254, 231, 203 },
	{ 0.2542, 0.8042, 0.80, 255, 234, 209 },
	{ -0.0625, 0.8125, 0.80, 255, 233, 205 },
}
SWIRL_TWINKLE = { -- each glint's brightness in the original's 16 frames
	{ 1.19, 1.28, 1.47, 1.68, 1.68, 1.55, 1.20, 0.94, 0.81, 0.80, 0.81, 0.93, 1.04, 1.08, 1.10, 1.16 },
	{ 1.11, 1.18, 1.34, 1.62, 1.69, 1.69, 1.69, 1.69, 1.69, 1.69, 1.69, 1.69, 1.45, 1.32, 1.21, 1.16 },
	{ 1.69, 1.69, 1.59, 1.36, 1.27, 1.24, 1.10, 1.07, 1.11, 1.28, 1.41, 1.50, 1.69, 1.69, 1.69, 1.69 },
	{ 1.65, 1.57, 1.41, 1.21, 1.05, 1.17, 1.37, 1.56, 1.35, 1.15, 0.90, 0.73, 0.73, 1.06, 1.46, 1.69 },
	{ 0.73, 0.50, 0.60, 0.64, 0.90, 0.97, 1.15, 1.35, 1.36, 1.13, 1.21, 1.25, 1.44, 1.28, 1.11, 1.01 },
	{ 1.47, 1.63, 1.60, 1.46, 1.27, 1.31, 1.30, 1.56, 1.64, 1.69, 1.65, 1.48, 1.12, 1.00, 0.98, 1.28 },
	{ 1.04, 1.07, 1.06, 0.90, 0.87, 0.81, 0.90, 0.97, 1.20, 1.49, 1.57, 1.53, 1.42, 1.22, 1.18, 1.06 },
	{ 1.69, 1.52, 1.22, 1.00, 1.01, 1.13, 1.29, 1.38, 1.44, 1.42, 1.35, 1.27, 1.59, 1.69, 1.69, 1.69 },
	{ 1.28, 1.40, 1.30, 1.18, 1.17, 1.09, 1.23, 1.31, 1.54, 1.69, 1.60, 1.43, 1.26, 1.28, 1.21, 1.16 },
	{ 1.51, 1.39, 1.27, 1.23, 1.16, 1.05, 0.95, 0.94, 0.88, 0.82, 0.90, 1.08, 1.22, 1.37, 1.53, 1.52 },
	{ 1.69, 1.69, 1.59, 1.47, 1.27, 1.23, 1.20, 1.25, 1.33, 1.46, 1.60, 1.63, 1.69, 1.69, 1.69, 1.69 },
	{ 0.41, 0.62, 0.57, 0.86, 1.03, 1.25, 1.27, 1.18, 1.14, 1.20, 1.03, 1.11, 0.99, 0.98, 0.80, 0.56 },
	{ 1.09, 0.97, 0.69, 0.90, 1.16, 1.37, 1.40, 1.47, 1.56, 1.49, 1.36, 1.41, 1.57, 1.54, 1.33, 1.20 },
	{ 1.26, 1.50, 1.63, 1.64, 1.47, 1.23, 1.32, 1.14, 1.29, 1.58, 1.69, 1.69, 1.58, 1.36, 1.43, 1.16 },
	{ 1.56, 1.31, 1.16, 1.20, 1.17, 1.28, 1.40, 1.59, 1.45, 1.54, 1.69, 1.69, 1.69, 1.69, 1.69, 1.69 },
	{ 1.07, 1.18, 1.39, 1.44, 1.45, 1.46, 1.50, 1.49, 1.35, 1.24, 1.22, 1.05, 0.90, 0.85, 0.92, 1.00 },
	{ 0.96, 1.03, 0.99, 0.80, 0.77, 0.76, 0.45, 0.51, 0.38, 0.54, 0.76, 0.96, 1.21, 1.29, 1.32, 1.27 },
	{ 1.07, 1.28, 1.50, 1.66, 1.69, 1.69, 1.69, 1.69, 1.69, 1.61, 1.49, 1.27, 1.03, 0.88, 0.85, 0.92 },
	{ 0.80, 1.05, 1.15, 1.36, 1.45, 1.48, 1.53, 1.53, 1.59, 1.69, 1.60, 1.54, 1.28, 1.01, 0.85, 0.71 },
	{ 1.69, 1.69, 1.69, 1.69, 1.69, 1.69, 1.48, 1.31, 1.21, 1.15, 1.17, 1.12, 1.23, 1.45, 1.59, 1.67 },
	{ 1.29, 1.41, 1.61, 1.68, 1.55, 1.54, 1.27, 0.95, 1.00, 1.08, 1.40, 1.50, 1.39, 1.48, 1.06, 1.12 },
	{ 1.64, 1.54, 1.44, 1.24, 1.08, 1.05, 1.02, 1.11, 0.93, 0.86, 0.89, 0.82, 1.07, 1.40, 1.61, 1.69 },
	{ 1.40, 1.32, 1.58, 1.69, 1.69, 1.69, 1.62, 1.43, 1.44, 1.24, 1.42, 1.59, 1.57, 1.59, 1.37, 1.26 },
	{ 1.40, 1.32, 1.58, 1.69, 1.69, 1.69, 1.62, 1.43, 1.44, 1.24, 1.42, 1.59, 1.57, 1.59, 1.37, 1.26 },
	{ 1.64, 1.54, 1.44, 1.24, 1.08, 1.05, 1.02, 1.11, 0.93, 0.86, 0.89, 0.82, 1.07, 1.40, 1.61, 1.69 },
	{ 1.29, 1.41, 1.61, 1.68, 1.55, 1.54, 1.27, 0.95, 1.00, 1.08, 1.40, 1.50, 1.39, 1.48, 1.06, 1.12 },
	{ 1.69, 1.69, 1.69, 1.69, 1.69, 1.69, 1.48, 1.31, 1.21, 1.15, 1.17, 1.12, 1.23, 1.45, 1.59, 1.67 },
	{ 0.80, 1.05, 1.15, 1.36, 1.45, 1.48, 1.53, 1.53, 1.59, 1.69, 1.60, 1.54, 1.28, 1.01, 0.85, 0.71 },
	{ 1.07, 1.28, 1.50, 1.66, 1.69, 1.69, 1.69, 1.69, 1.69, 1.61, 1.49, 1.27, 1.03, 0.88, 0.85, 0.92 },
	{ 0.96, 1.03, 0.99, 0.80, 0.77, 0.76, 0.45, 0.51, 0.38, 0.54, 0.76, 0.96, 1.21, 1.29, 1.32, 1.27 },
	{ 1.07, 1.18, 1.39, 1.44, 1.45, 1.46, 1.50, 1.49, 1.35, 1.24, 1.22, 1.05, 0.90, 0.85, 0.92, 1.00 },
	{ 1.56, 1.31, 1.16, 1.20, 1.17, 1.28, 1.40, 1.59, 1.45, 1.54, 1.69, 1.69, 1.69, 1.69, 1.69, 1.69 },
	{ 1.26, 1.50, 1.63, 1.64, 1.47, 1.23, 1.32, 1.14, 1.29, 1.58, 1.69, 1.69, 1.58, 1.36, 1.43, 1.16 },
	{ 1.09, 0.97, 0.69, 0.90, 1.16, 1.37, 1.40, 1.47, 1.56, 1.49, 1.36, 1.41, 1.57, 1.54, 1.33, 1.20 },
	{ 0.41, 0.62, 0.57, 0.86, 1.03, 1.25, 1.27, 1.18, 1.14, 1.20, 1.03, 1.11, 0.99, 0.98, 0.80, 0.56 },
	{ 1.69, 1.69, 1.59, 1.47, 1.27, 1.23, 1.20, 1.25, 1.33, 1.46, 1.60, 1.63, 1.69, 1.69, 1.69, 1.69 },
	{ 1.51, 1.39, 1.27, 1.23, 1.16, 1.05, 0.95, 0.94, 0.88, 0.82, 0.90, 1.08, 1.22, 1.37, 1.53, 1.52 },
	{ 1.28, 1.40, 1.30, 1.18, 1.17, 1.09, 1.23, 1.31, 1.54, 1.69, 1.60, 1.43, 1.26, 1.28, 1.21, 1.16 },
	{ 1.69, 1.52, 1.22, 1.00, 1.01, 1.13, 1.29, 1.38, 1.44, 1.42, 1.35, 1.27, 1.59, 1.69, 1.69, 1.69 },
	{ 1.04, 1.07, 1.06, 0.90, 0.87, 0.81, 0.90, 0.97, 1.20, 1.49, 1.57, 1.53, 1.42, 1.22, 1.18, 1.06 },
	{ 1.47, 1.63, 1.60, 1.46, 1.27, 1.31, 1.30, 1.56, 1.64, 1.69, 1.65, 1.48, 1.12, 1.00, 0.98, 1.28 },
	{ 0.73, 0.50, 0.60, 0.64, 0.90, 0.97, 1.15, 1.35, 1.36, 1.13, 1.21, 1.25, 1.44, 1.28, 1.11, 1.01 },
	{ 1.65, 1.57, 1.41, 1.21, 1.05, 1.17, 1.37, 1.56, 1.35, 1.15, 0.90, 0.73, 0.73, 1.06, 1.46, 1.69 },
	{ 1.69, 1.69, 1.59, 1.36, 1.27, 1.24, 1.10, 1.07, 1.11, 1.28, 1.41, 1.50, 1.69, 1.69, 1.69, 1.69 },
	{ 1.11, 1.18, 1.34, 1.62, 1.69, 1.69, 1.69, 1.69, 1.69, 1.69, 1.69, 1.69, 1.45, 1.32, 1.21, 1.16 },
	{ 1.19, 1.28, 1.47, 1.68, 1.68, 1.55, 1.20, 0.94, 0.81, 0.80, 0.81, 0.93, 1.04, 1.08, 1.10, 1.16 },
}
SWIRL_RING_COLOR = Color3.fromRGB(254, 246, 231)

workspace.DescendantAdded:Connect(watch)
for _, descendant in workspace:GetDescendants() do
	watch(descendant)
end

RunService:BindToRenderStep("ForceField2014", Enum.RenderPriority.Camera.Value + 1, onRenderStep)
print("ForceField2014 is running (" .. (if CONFIG.SwirlTexture ~= "" then "uploaded" else "rebuilt") .. " swirl)")
