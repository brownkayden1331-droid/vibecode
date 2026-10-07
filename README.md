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

## NPCs that play your chamber (ChamberBotServer)
`src/ServerScriptService/ChamberBotServer.server.lua`. Every editor playtest is recorded (where you walk, the portals you shoot, when you carry a cube). **File › NPC demo**:
- **Keep my last run as the demo** – saved with the chamber (`data.demo`).
- **Watch the NPC play it** – Chell (or Atlas + P-body) replays it: walks, jumps, shoots the same portals, carries cubes onto buttons. Buttons see NPCs like players.
- **Play alongside the NPC (record your part)** then **Add my last run as the partner** – make a co-op demo on your own: the Atlas NPC plays its half while you play P-body's; then two NPCs play it together.
NPCs repeat a recorded run – they don't solve puzzles on their own. Rigs come from `PortalAssets.Rigs` (Chell / Atlas / PBody); without rigs a plain R15 dummy is used. Their portals go into `workspace.Portals` with the same attributes the portal gun uses (`OwnerUserId` negative, `PortalName`, `Opened`).

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
