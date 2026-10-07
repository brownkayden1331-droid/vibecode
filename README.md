# Portal (Roblox) – menu, server, test chamber editor

| File | Goes in |
| --- | --- |
| `src/ReplicatedStorage/PortalConfig.lua` | ReplicatedStorage › ModuleScript named `PortalConfig` |
| `src/ServerScriptService/PortalServer.server.lua` | ServerScriptService › Script `PortalServer` |
| `src/StarterPlayerScripts/PortalMenu.client.lua` | StarterPlayerScripts › LocalScript `PortalMenu` |
| `src/StarterPlayerScripts/PortalMapEditor.client.lua` | StarterPlayerScripts › LocalScript `PortalMapEditor` |
| `src/StarterPlayerScripts/MusicDirector.client.lua` | StarterPlayerScripts › LocalScript `MusicDirector` |
| `src/ServerScriptService/RigChangerServer.server.lua` | ServerScriptService › Script `RigChangerServer` |
| `src/ServerScriptService/TestElementsServer.server.lua` | ServerScriptService › Script `TestElementsServer` |
| `src/StarterPlayerScripts/TestElementsClient.client.lua` | StarterPlayerScripts › LocalScript `TestElementsClient` |
| `src/StarterPlayerScripts/PingClient.client.lua` | StarterPlayerScripts › LocalScript `PingClient` |
| `src/ServerScriptService/PingServer.server.lua` | ServerScriptService › Script `PingServer` |
| `src/ServerScriptService/ChamberBotServer.server.lua` | ServerScriptService › Script `ChamberBotServer` |
| `src/ServerScriptService/FaithPlateServer.server.lua` | ServerScriptService › Script `FaithPlateServer` |
| `src/StarterPlayerScripts/FaithPlateClient.client.lua` | StarterPlayerScripts › LocalScript `FaithPlateClient` |
| `src/ServerScriptService/ChamberPiecesServer.server.lua` | ServerScriptService › Script `ChamberPiecesServer` |
| `src/StarterPlayerScripts/ChamberPiecesClient.client.lua` | StarterPlayerScripts › LocalScript `ChamberPiecesClient` |
| `src/ServerStorage/ChamberStudioTools.lua` | ServerStorage › ModuleScript `ChamberStudioTools` (Studio only) |

## Editor modes and tabs
Options › Editor › **Editor Mode** (also File › Editor mode inside the editor):

- **Simple** – Items palette (the original editor).
- **Intermediate** – adds **Textures** and **Meshes** tabs. Each searches the **Toolbox** (Creator Store) by default; **IN GAME** switches to your own assets.
  - Textures: Toolbox decals, `ReplicatedStorage.PortalAssets.Textures`, or a pasted id. Select surfaces, then click a texture.
  - Meshes: **MeshParts** only.
    - **TOOLBOX** (default) searches the Creator Store for **MeshParts only** (Roblox's Creator Store API, `toolbox-service/v2/assets:search` with `searchCategoryType=MeshPart`), so no models and no scripts. A pick becomes a real MeshPart. Setup:
      1. Game Settings › Security › **Allow HTTP Requests** on.
      2. If the tab says it needs an API key: Creator Hub › Open Cloud › API Keys › create a key with **Creator Store** read access, then add it to the experience's **Secrets** named `CreatorStoreApiKey` (Creator Hub › your experience › Secrets; for Studio testing, Game Settings › Security › Secrets).
    - **IN GAME** lists your own MeshParts in `ReplicatedStorage.PortalAssets.Meshes`.
    - Or paste any **Mesh** asset id (+ optional texture id): the server makes a real MeshPart with `AssetService:CreateMeshPartAsync`.
    - Loaded meshes are cached in `ReplicatedStorage.PortalToolbox`. Drag into the room; right-click › Size.
  - **Textures setup:** Toolbox decal search needs InsertService › **AllowInsertFreeModels** ticked in Studio to load the image.
- **Advanced** – adds **My Chips**, item labels, mesh nudge/turn, and a coordinates readout.

### Chips
Small programs that run in the built chamber. Edit them as **blocks** or as **lines** (same program):

```
when button1 pressed
    open exit
    say "Nice!"
when button1 released
    wait 2
    close exit
when every 5
    toggle field1
when start
    drop dropper1
```
Events: `when <item> pressed|released`, `when start`, `when every <seconds>`.
Actions: `open|close|enable|disable|toggle <item>`, `drop <dropper>`, `reverse <funnel>`, `wait <seconds>`, `say <text>`.
In the LINES view words are coloured (keywords, items, numbers, text, comments; unknown words in red), and typos are fixed when you press Enter or click away (e.g. `opne exitt` → `open exit`), with actions indented under their `when`.
Chips also have **variables** (`set score 0`, `add score 1`, `say "Score: {score}"`) and one-line **if** (`if score >= 3 then open exit`). In the LINES view suggestions pop up as you type (Tab takes the top one) and the bar under the text shows what the line expects.
**Effects** (look and sound only, for the players in that chamber: you, or you and your co-op partner): `music <song | id>` / `music stop` (the game's own music steps aside while it plays), `sound <name | id>`, `shake <seconds>`, `title "text"`, `tint <colour>`, `countdown <seconds>` / `countdown stop`. They stop when you leave, rebuild or go back to editing; a chip can send at most 20 a second. Songs come from `PortalAssets.OST`, sounds from `PortalAssets.Sounds`.
**Advanced code**: `when score >= 3` (runs each time it turns true), `random roll 1 6`, `repeat 3 then drop dropper1`, `stop` (ends the rule).
Items are named by label (right-click an item in Advanced mode). **To My Chips** stores a chip in your profile so you can use it in any chamber.

## Invisible blocks
At the end of the Items palette, Intermediate mode and up (Advanced adds the last two). See-through in the editor, invisible in game:
**Trigger Zone** (a source, on while players / cubes are in its cell), **Delay Relay** (passes a signal on 1–30 s later), **Invisible Wall** (solid, portal shots pass through, switchable), **Light** (coloured, switchable), **Death Zone**, **Push Zone** (shoves players and cubes out of its surface).

## Funnels and buttons
Right-click a funnel › **Button action**: *Reverse it* (Portal 2) or *Turn it on / off* — the funnel is off until the button is pressed ("auto off"). **Stay on after release** (Intermediate+, linked items) keeps it going 1–10 s after the button lets go.
Flying into a funnel stops you mid-air and carries you (TestElementsClient: swept check so you can't fly through it at speed, momentum killed on entry; `CATCH_SWEEP` / `CATCH_STOP` at the top).
TestElementsServer now drops cubes into the chamber's slot map (`workspace.PortalInstances.Slot_<n>`), so they're cleaned up with it.

## Chips and items
Chips can drive more items: `launch plate1` (aerial faith plates throw whoever stands on them, and cubes, along their arc), `forward` / `backward` / `speed <funnel> <n>`, `color <light> <name | #hex>`, and `enable` / `disable` on faith plates (a switched-off plate gets `Enabled = false` and its parts stop touching — if your FaithPlateServer uses something other than Touched, have it skip plates with `Enabled == false`).
More code: `if ... then ... else ...`, `wait until <a> <cmp> <b>`, `calc <var> <a> <+ - * / % min max> <b>`, functions (`when call <name>` / `call <name>`, across chips), built-in values `time` and `players`.

## Editor camera
Options › Editor: **Orbit In Place** (on by default) turns the camera where it stands instead of swinging it round a point in the middle of the chamber. **Fly Camera** (off by default) makes W / S fly where you look, up and down too, like Studio or Unity (A / D strafe, E / Q straight up / down).

## Editor styles + custom colours
Styles: Classic, Dark, Blueprint, High Contrast, **SCP: CB**, **Unity**, **Blender**, Roblox Studio, Terminal, Solarized, Synthwave, Aperture '70s, Aperture Clean, Midnight and **Custom** (File › Editor style › Make a custom style… — 12 colours, live preview, saved in `Setting_edCustomTheme`). New styles are 12 colours each in `THEMES` in PortalMapEditor, taken from the real programs. Item previews (3D viewports) and pictures keep their own colours in every style.
Intermediate / Advanced: **Tile color › Custom colour…** (and the Light's colour menu) opens a colour picker; tiles store `"#rrggbb"`, the last 8 are kept as recent colours.

## Duplicate, export, import, Studio
- **Ctrl+D** / right-click › **Duplicate**: copies the item (same options, new label) to the nearest free panel facing the same way.
- **File › Export**: the chamber as text. **File › Import**: paste that text back (replaces the open chamber; Ctrl+Z undoes).
- **Studio**: put the text in a StringValue `ServerStorage.ChamberImport`, then in the command bar:
  ```lua
  local T = require(game.ServerStorage.ChamberStudioTools)
  T.Import()   -- workspace.ChamberWorkbench: Cells (one block per open cell) + Items (one block per item, attributes) + Chips
  T.Preview()  -- the real chamber, built from your PortalAssets, next to it (T.ClearPreview() removes it)
  T.Export()   -- text into ServerStorage.ChamberExport -> copy its Value -> File › Import in the editor
  T.New()      -- a fresh workbench
  ```
  Set Studio's move snap to 10 (one cell). Panel settings live on the cells as `Face_<side>`, `Color_<side>`, `Texture_<side>`; items have `Kind`, `Side`, `Rot`, `Options` (JSON), `LinksTo` (Ids, comma separated). Nothing from the game's assets is copied out.

## Old chambers
Chambers saved or published before exits needed a button carry no `fmt`. When one is loaded (editor, Workshop, Studio import) and nothing is wired to its exit, the exit gets **Open without a button**, so it plays like it used to. New chambers are saved with `fmt = 3`. Drafts are no longer dropped from your profile just because they're old.

## Co-op: invites, quick match, runs
- **Workshop co-op chambers** (Co-op › Workshop co-op chambers, or Community): picking one asks how to play it: **with your partner** (if you have one), **Invite a friend** (they're invited straight into that chamber), **Quick match** (pairs you with someone who wants the same chamber, or anyone), or **Play alone**.
- **Normal co-op mode**: after you pair up (invite or quick match) you both **vote**: *Built-in chambers* (the co-op courses in `Config.COURSES`) or *Custom chambers* (the top `Config.COOP_RUN_MAX` rated Workshop co-op chambers), and *Normal* or *Speedrun*. Same pick wins, different picks are a coin flip. Then you play the whole list: a chamber is done when **both** of you reach the exit. Speedrun runs one clock over the whole list (HUD at the top, splits per chamber, personal best per list kept in your profile). Co-op › *Pick what to play (vote)* or *Play again* on the results starts another run.

## Portal 2 maps -> Roblox (tools/p2_to_roblox.py)
A Python 3 script for your PC (standard library only) that turns a Portal 2 map into a `.rbxmx` model, e.g. the co-op hub:
```
python tools/p2_to_roblox.py mp_coop_lobby_3.vmf -o CoopHub.rbxmx --name CoopHub
```
- **Input**: `.vmf` (best; get it from a `.bsp` with BSPSource) or a `.bsp` directly (experimental).
- **Geometry**: boxes (also rotated) become Parts, right-angle ramps WedgeParts, every other shape thin wedge-pair triangles. Sides with a different texture than the rest of the box get a thin plate. Tool textures: nodraw sides aren't drawn, clips / invisible become invisible walls, triggers / skybox / hints are left out.
- **Materials**: `tools/p2_materials.json` maps Portal 2 texture paths (regular expressions) to your MaterialService variants (White 4.5, Metal 9, DevG, bts1concrete...) and says which are portalable. The script prints every texture it had no rule for - add rules and run it again.
- **Entities**: `info_player_start` -> PlayerSpawn, `info_coop_spawn` -> PlayerSpawnBlue (Atlas) / PlayerSpawnOrange (P-body), test elements (buttons, cubes with their type, doors, turrets, lasers, catchers, funnels, bridges, fizzlers, faith plates) -> placeholders, lights -> PointLights. Props (`prop_static` / `prop_dynamic` models) aren't converted; the script lists them.
- **Connections (Portal 2 I/O)**: every entity with a name or outputs goes into the model's `P2IO` module, and `P2MapSetup` runs them like Portal 2: floor buttons (OnPressed / OnUnPressed - pressed by PortalServer like editor buttons), pedestals (OnPressed / OnButtonReset), laser catchers (OnPowered / OnUnpowered), trigger_once / trigger_multiple (OnStartTouch, OnTrigger, OnEndTouch...), logic_auto, logic_relay, logic_branch, logic_coop_manager (both players), math_counter, logic_timer, env_entity_maker + point_template (cube droppers: ForceSpawn makes a cube of the template's type), and inputs Open / Close on chamber doors (the door's `Open` attribute), Enable / Disable / Toggle on fizzlers, lasers, bridges, funnels, faith plates, turrets, SetLinearForce on funnels (speed + direction), Kill / Dissolve, FireUser1-4. Triggers whose outputs lead to a level change / transition become `PortalChamberExit` (the chamber ends there). Not run: VScript (`RunScriptCode`), sounds, animations, moving brushes (func_door etc. stay put).
- **In Studio**: Insert from File, then put it in ServerStorage.PortalMaps (named CoopHub for the hub). Its `P2MapSetup` script, when the map is loaded, gives every part its MaterialVariant's BaseMaterial, adds `NoPortal` to non-portal surfaces and swaps the placeholders for your PortalAssets models. Portal surfaces need a variant whose BaseMaterial isn't one the gun blocks (use SmoothPlastic or Concrete for the White ones) - it warns you if not.
- Options: `--scale` (default 1/14.7 studs per unit, the gun's U), `--no-center`, `--no-face-plates`, `--no-lights`, `--thickness`, `--materials`.

## Editor: connections, multi-select, doors
- **L** (or File / Edit › *Show connections*) draws every connection as a line from the source to what it drives (arrow at the driven end, labels at both ends), through walls. Selecting an item doesn't draw them by default; turn on Options › Editor › *Show Connections Of Selected* to see the selected item(s)' connections in yellow.
- **Several items at once**: Ctrl / Shift + click items to add or remove them; *Select all like this* (Edit menu or right-click) selects every item of that kind (all funnels...). Delete, R, item options (e.g. funnel speed) and **C** work on all of them: C then click an item connects every selected one to it. **Shift + click** while connecting keeps going, so one button can be connected to several things in a row.
- **Swap entrance and exit**: File / Edit menu, or right-click a door.

## Phones / tablets in the editor
- **Move stick** (bottom left) flies the camera around (up on the stick = where you look), **▲ / ▼** go up and down. **Look stick** (bottom right) turns the camera, its speed follows Options › Editor › *Touch Orbit Speed*. One finger on the room still orbits too, two fingers pan and pinch zooms. *Touch Move Stick* turns both sticks off.
- **Double-tap** a surface or an item = right-click: opens its menu (options, connect, delete, Move…).
- A tap that wobbles a few pixels no longer drags the item or the selection to the next tile (14 px dead zone).
- Right-click / long-press an item › **Move** › Up / Down / Left / Right moves it one tile – no dragging needed.

## Doors at any height
`Config.DOORS_ANY_HEIGHT = true`: entry / exit doors can go on any row of a wall (their alcove has its own floor). Drag them, or Move › Up / Down. A raised exit is a puzzle goal; a raised entry drops you into the room. Set it to false for floor-only doors like Portal 2.

## How doors open
Right-click a door › **Opens**: *Its own animation* (the door model's own script, default), *Slides left / right / up / down*, *Splits to the sides / up and down*. For the slide styles the model's scripts are switched off and ChamberPiecesServer slides the door's leaves while `Open` is true. Leaves = parts with the attribute `DoorLeaf = true`, else parts named like door / leaf / panel / slide (not frame), else the biggest part. Tag your door model's moving parts with `DoorLeaf` for exact control (two leaves split, one leaf slides).

## Faith plates + funnels
`FaithPlateServer` / `FaithPlateClient` are in the repo. A faith plate launch used to hold your sideways speed for the whole flight, so funnels couldn't catch you; now the flight ends the moment a funnel grabs you (`InFunnel`), so funnels stop you mid-air like in Portal 2.

## Moving pieces, crushers, sound blocks (ChamberPiecesServer + ChamberPiecesClient)
- **Moving Panel**, **Arm Panel** (`PortalAssets…Panel_Interior`) and **Arm Panel 2** (`Panel_Interior2`): the tile becomes a socket; the panel (`PanelTile`, portalable unless you untick it) comes out when it's on. Right-click › *When it's on*: **Extend** (straight out 1–3 tiles), **Door** (swings open on its bottom edge), **Bounce** (flips up and flings players / cubes; unconnected bounce panels go every 3 s). The arm models are bent procedurally: the deepest bone (`arm_192_tip` / `5`) follows the panel, the bones above take a growing share of the move. If an arm sits the wrong way in the socket, set `PanelNormal` (Vector3, model space: the way the panel faces) and/or `PanelOffset` (studs) on the model in PortalAssets.
- **Crusher** (`PortalAssets…Crusher`, or a built-in plate): *Sensor* crushes whoever walks in front of it, *Button* crushes when its inputs turn on (*Stay down while powered* holds it). Reach 1–4 tiles. Anyone caught dies, cubes get squashed. States `CRUSH` → `Holdcrush` → `Crushback` (attribute `CrushState`); Animation objects named **Holdcrush**, **CRUSH**, **Crushback** inside the Crusher model (or `PortalAssets.Animations.Crusher`) are played on clients, otherwise the model follows the plate.
- **Note Block** (Intermediate): plays its sound at the block (heard up to 50 studs) each time it's switched on or `play`ed, pitch ±24 semitones. **Music Block**: the chamber's music while it's on.
- **Custom audio**: File › *Chamber audio…* keeps audio ids with names (saved with the chamber, max 24). Use them in Note / Music Blocks (Sound › pick or *Type an audio id…*) and in chips (`music BossTheme`, `sound 1234567`). Chips can `play` note / music blocks, crushers and panels.

## NPCs that play your chamber (ChamberBotServer)
`src/ServerScriptService/ChamberBotServer.server.lua`. Every editor playtest is recorded (where you walk, the portals you shoot, when you carry a cube). **File › NPC demo**:
- **Keep my last run as the demo** – saved with the chamber (`data.demo`).
- **Watch the NPC play it** – Chell (or Atlas + P-body) replays it: walks, jumps, shoots the same portals, carries cubes onto buttons. Buttons see NPCs like players.
- **Play alongside the NPC (record your part)** then **Add my last run as the partner** – make a co-op demo on your own: the Atlas NPC plays its half while you play P-body's; then two NPCs play it together.
- **Watch the NPC play on its own** – autonomous: the NPC works out what opens the exit from the connections (through logic gates back to buttons / pedestals / trigger zones), carries cubes onto floor buttons, presses pedestals, waits for the door and walks out, with PathfindingService. It **learns from every run you taught it** (the demo runs plus up to 6 from *Teach the NPC with my last run*): the order you did the buttons in and which cubes went where, how fast you move, and – wherever it can't walk (portals, funnels, faith plates, gaps) – it finds a stretch of one of your runs from about where it is to about where it has to go and does that, with that run's portals. Co-op chambers / two-run demos get two NPCs (one can hold a button down for the other). Places none of your runs reached, it says so.
Replays repeat a recorded run exactly; on its own the NPC plans and walks itself, but its portal tricks come only from your runs. Rigs come from `PortalAssets.Rigs` (Chell / Atlas / PBody); without rigs a plain R15 dummy is used. Their portals go into `workspace.Portals` with the same attributes the portal gun uses (`OwnerUserId` negative, `PortalName`, `Opened`).

## Funnels: speed + cubes
Right-click a funnel › **Speed** (6–35 studs/s, saved as `speed`). Funnels now pick up loose cubes that just touch their beam – a cube resting under a funnel, dropped into it, or already there when it switches on.

## Pings (PingClient)
`src/StarterPlayerScripts/PingClient.client.lua`: pings only work while you're playing / testing a chamber together with your co-op partner (same `InstanceSlot`, not in a menu, not building in the editor). Pings from players outside your chamber are ignored, and leaving the chamber clears them. PingServer only sends a ping (and the death icon) to the other player in your chamber. `PING_ONLY_EDITOR_TESTS = true` at the top limits them to co-op editor playtests.

## Exit door
The exit is **locked** until something opens it: connect a button/pedestal/laser catcher/gate to it, open it with a chip, or right-click it › **Open without a button**. Standing at a locked exit does nothing. Publishing a chamber nobody can finish is refused.

> Chambers published before this change that have no connection to the exit are now locked too. Re-open them, connect a button, and publish again.

## Start / End markers
Add a Folder named `Start` and one named `End` with a part in each:
- **inside the door model** (`ChamberLockDoor`) – used exactly where they are (Start = spawn point, End = finish trigger), or
- in `ReplicatedStorage.PortalAssets` (or `.EditorAssets`), `ReplicatedStorage`, `ServerStorage` or `workspace` – cloned and put in front of the entry/exit door.

If there are none, the old invisible square spawn pad / finish box is used.

## Door placement
Doors now keep their model upright and turn so their thin side faces the room. `PortalConfig.DOOR_INSET` sets how far back the door sits (0 = flush with the wall). If a door faces the wall, give the door model a `MountRotation` attribute of `(0, 180, 0)`.

## Instances (chambers far apart)
Each player (a co-op pair shares one) gets their own slot, `workspace.PortalInstances.Slot_<n>`, 6000 studs from the next (`INSTANCE_SPACING`). Chapters, challenge maps, Workshop chambers and editor playtests all load there, so players never clear or walk into each other's maps. Set `OFFSET_CHAPTER_MAPS = false` if a chapter map has scripts that need it to stay at its Studio position.

## Toast notifications
Small pop-ups for achievements, autosaves, unlocked chapters, finished chambers, chip messages and so on. Turn them off in Options › Editor or Video › Advanced Video › **Toast Notifications**.
Other scripts: `PlayerGui.PortalMenu.MenuRequest:Fire("Toast", { title = "...", text = "...", kind = "good" })`, or from the server `shared.PortalData.Toast(player, text)`.

## Game view
Tab (or the eye button) shows the chamber exactly as it will look in game (real tiles, textures, item models, antlines) without building it or leaving the editor. Tab again to keep editing.

## Tutorials
The editor runs its own tutorial that outlines the real GUI as it explains it (palette, the tabs your mode has, play, game view, File) and lights up the exit door in the room. Help › Tutorial shows it again.
Elsewhere a tutorial card appears when a level starts: every chapter, challenges, Workshop chambers, co-op, the editor and editor playtests. Enter = next, Backspace = skip. Turn them off in Options › Gameplay › **Tutorials** (or Options › Editor). A chapter can have its own steps: `tutorial = { { "Title", "Text" }, ... }` in `PortalConfig.CHAPTERS`. Editor: Help › Tutorial shows it again.

## Version check
`PortalConfig.VERSION` must match what the other scripts expect (3). If you update the scripts but not PortalConfig, the Output window says so.

## Co-op: Atlas and P-body
In co-op the blue player becomes **Atlas** and the orange player **P-body** (RigChangerServer, rigs `Atlas` and `PBody` in `ReplicatedStorage.PortalAssets.Rigs`; names are matched loosely, so `P-Body` works). If a rig is missing it warns once and uses Chell. Leaving co-op puts you back the way you were. Change the names in `PortalConfig.COOP_RIGS` / `COOP_RIGS` in RigChangerServer.

## Menu music
MusicDirector plays `ReplicatedStorage.PortalAssets.OST["Main Menu"]` (a Sound, or a folder of Sounds) on the main menu. It used to read that folder once, before it had replicated, and stayed silent; it now picks the tracks up whenever they arrive.

## Wiki
Help › **Wiki** (or F1) in the editor explains everything: shaping rooms, items, connections, textures, meshes, chips (with a full language reference and examples), modes, styles and controls. The **?** in the chip editor opens the chip reference on top of your chip.

## Editor styles
Options › Editor › **Editor Style** (or File › Editor style): Classic, Dark, Blueprint, High Contrast. Add your own in the `STYLES` table in PortalMapEditor.

## Music troubleshooting
MusicDirector prints one line in Output a few seconds after starting (what it found), warns when a song can't load (usually audio permissions), and **Ctrl+Shift+M** shows a live music HUD in game.
