# 2014 ForceField

A recreation of the ROBLOX ForceField look from the **October 2014** update, the same update that
changed Smoke, Sparkles and Fire. It is a glowing cyan bubble around the character with:

- a bright rim that is always a perfect circle, with a white-hot core and a soft outer haze,
  all drawn as smooth, blurry glows like the original, so it stays soft even in HD
- a brighter side on the rim that faces the sun
- a thin inner ring that drifts in and out
- a misty fill that's thicker at the bottom
- only the sparkles from today's ForceField (the 2014 one had them too), without today's blue
  sphere: the glittery swirl spinning around the waist, using the ForceField's own swirl
  flipbook, and a few small white stars floating up out of the bubble
- a one-second fade-out when the ForceField ends, and the whole thing stays attached to the
  player while it fades
- a cyan screen tint while your camera is inside a bubble (in the 2014 version the screen
  turned blue-white when the camera was inside one)

It was rebuilt from these videos:

- [ROBLOX's new Forcefield, Smoke, Sparkles, and Fire appearance!](https://youtu.be/g_80GI-w3pY)
- [ROBLOX Updates! Episode 1: New Force Field](https://youtu.be/lFF-52B4sfA)
- [ROBLOX New Forcefield 2014!!](https://youtu.be/BrMq3rC-rOM)

## Setup

1. In Roblox Studio, open **StarterPlayer > StarterPlayerScripts**.
2. Insert a **LocalScript** and name it `ForceField2014`.
3. Paste in everything from [`ForceField2014.client.lua`](ForceField2014.client.lua).
That's it: the swirl image is built into the script, so nothing has to be uploaded. Every ForceField in the game gets the 2014 look: SpawnLocation spawn protection, admin `:ff`
commands, and anything a script makes with `Instance.new("ForceField")`.

### Published games

The script builds the swirl image with Roblox's `EditableImage`, which works in Studio right away.
In a **published** game Roblox blocks it unless you turn on **Allow Mesh / Image APIs** in
**Game Settings > Security**, and that needs your account to be 13+ and ID-verified. If you can't
do that, upload the image instead:

1. In Studio, open the **Asset Manager** (View tab), import
   [`textures/ForceFieldSwirl.png`](textures/ForceFieldSwirl.png), then right-click it and choose
   **Copy ID to Clipboard**.
2. In the script's `CONFIG`, set `SwirlTexture` to that ID, like
   `SwirlTexture = "rbxassetid://1234567890",`.

Use the image's ID from the Asset Manager, not a decal ID from the website: a decal ID won't load
from a script. A new upload can take a few minutes to pass moderation before it shows up. If the
swirl can't be shown either way, the bubble still works without it and the script explains why in
the Output window.

## Trying it out

- Press **Play**. SpawnLocations give a ForceField for 10 seconds by default.
- To test a ForceField that never runs out, run this in the command bar while playing (Server view):

  ```lua
  for _, p in game.Players:GetPlayers() do Instance.new("ForceField", p.Character) end
  ```

## Settings

The `CONFIG` table at the top of the script controls the look:

| Setting | What it does |
| --- | --- |
| `DiameterScale` | Bubble size relative to the character's height (`1.45` matches the videos) |
| `RimColor`, `GlowColor`, `HazeColor`, `HighlightColor` | Colors of the rim and its glow |
| `ShowSparkles` | The swirl and stars inside the bubble |
| `SwirlTexture` | Leave empty to use the built-in swirl, or set an uploaded image's ID (see Published games) |
| `SwirlColor` | Tints the swirl (white = the image's own colors) |
| `SwirlFramerate` | How fast the swirl spins, in flipbook frames per second (16 frames = one full turn) |
| `SparkleSize` | Makes the swirl and stars bigger or smaller (`1` = normal) |
| `ShowInsideTint`, `InsideTintTransparency` | Screen tint while the camera is inside a bubble |
| `HighlightFollowsSun` | Brightest side of the rim faces the sun (off = always top right) |
| `PulseSpeed` | How fast the inner ring moves |
| `FadeInTime`, `FadeOutTime` | Fade when a ForceField is added or removed |

## How it works

- Roblox's own ForceField look is hidden by setting `ForceField.Visible = false` on each
  player's client. The ForceField still protects the character as normal.
- Everything hangs off one invisible, non-colliding, massless part that is **welded** to the
  character's root part. The engine moves it with the character, so nothing gets left behind
  when you jump or run, even during the fade-out.
- The swirl is a `ParticleEmitter` using a 4x4 flipbook: 16 frames of a glittery ring seen at
  a slight angle, each turned 22.5° further than the last, so looping through them spins it.
  The image is stored in the script as compressed data (8 frames, since frames 9-16 nearly
  repeat 1-8) and turned back into a 1024x1024 image with `EncodingService` and
  `EditableImage` the first time a ForceField appears.
  The particles face the camera, sit just below the root part, and fade in and out with a
  couple overlapping at a time so the swirl shimmers. The stars float up from a box around
  the body. Both are locked to the welded part, so they stay with the player and fade out with
  the bubble.
- The rim is a camera-facing `BillboardGui`. Each glow in it (inner light, outer haze, inner
  ring, rim, core) is a stack of faint, nested round `UIStroke` rings whose opacities add up
  to a smooth falloff, which gives the blurry gradient look without any images. The script
  resizes the billboard to line up with the sphere's outline, and re-scales the ring widths
  when the bubble's size on screen changes.
- Only the client draws the effect, so the server does no extra work.

## Notes

- A ForceField that a game made invisible (`Visible = false`) before it showed up stays
  invisible. But if the server hides a ForceField *after* the bubble has appeared, the
  bubble won't notice.
- The rim is a recreation built from video footage, not the original 2014 textures. The colors
  and sizes can all be changed in `CONFIG`.
