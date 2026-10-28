# 2014 ForceField

A recreation of the ROBLOX ForceField look from the **October 2014** update, the same update that
changed Smoke, Sparkles and Fire. It is a glowing cyan bubble around the character with:

- a bright rim that is always a perfect circle, with a white-hot core and a soft outer haze,
  all drawn as smooth, blurry glows like the original, so it stays soft even in HD
- a brighter side on the rim that faces the sun
- a thin inner ring that drifts in and out
- a misty fill that's thicker at the bottom
- only the sparkles from today's ForceField (the 2014 one had them too), without today's blue
  sphere: a faint, smoky swirl of rings spinning around the waist like a whirlpool, soft
  glowing dots on it in white, peach, pink and pale blue, and little white stars drifting up
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

That's it. You don't need to upload any decals or meshes. Every ForceField in the game gets the
2014 look: SpawnLocation spawn protection, admin `:ff` commands, and anything a script makes
with `Instance.new("ForceField")`.

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
| `ShowSparkles` | The swirl, dots and stars inside the bubble |
| `SwirlColor`, `SpinSpeed` | Color of the swirl rings and how fast everything spins |
| `SparkleSize` | Makes the dots and stars bigger or smaller (`1` = normal) |
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
- The sparkles are rebuilt from particles and beams on that part. The swirl is 8 rings of
  curved streaks (beams), each with a wide, faint copy around it so it looks smoky. The dots
  use Roblox's built-in smoke texture shrunk down, which makes soft round dots. The stars use
  the built-in sparkle texture. The part spins, and the particles are locked to it, so they
  swirl around the player and fade out with the bubble.
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
- This is a recreation built from video footage, not the original 2014 textures. The colors
  and sizes can all be changed in `CONFIG`.
