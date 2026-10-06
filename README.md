# Portal (Roblox) – menu, server, test chamber editor

| File | Goes in |
| --- | --- |
| `src/ReplicatedStorage/PortalConfig.lua` | ReplicatedStorage › ModuleScript named `PortalConfig` |
| `src/ServerScriptService/PortalServer.server.lua` | ServerScriptService › Script `PortalServer` |
| `src/StarterPlayerScripts/PortalMenu.client.lua` | StarterPlayerScripts › LocalScript `PortalMenu` |
| `src/StarterPlayerScripts/PortalMapEditor.client.lua` | StarterPlayerScripts › LocalScript `PortalMapEditor` |
| `src/StarterPlayerScripts/MusicDirector.client.lua` | StarterPlayerScripts › LocalScript `MusicDirector` |
| `src/ServerScriptService/RigChangerServer.server.lua` | ServerScriptService › Script `RigChangerServer` |

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
Items are named by label (right-click an item in Advanced mode). **To My Chips** stores a chip in your profile so you can use it in any chamber.

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
