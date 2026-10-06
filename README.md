# Portal (Roblox) – menu, server, test chamber editor

| File | Goes in |
| --- | --- |
| `src/ReplicatedStorage/PortalConfig.lua` | ReplicatedStorage › ModuleScript named `PortalConfig` |
| `src/ServerScriptService/PortalServer.server.lua` | ServerScriptService › Script `PortalServer` |
| `src/StarterPlayerScripts/PortalMenu.client.lua` | StarterPlayerScripts › LocalScript `PortalMenu` |
| `src/StarterPlayerScripts/PortalMapEditor.client.lua` | StarterPlayerScripts › LocalScript `PortalMapEditor` |

## Editor modes and tabs
Options › Editor › **Editor Mode** (also File › Editor mode inside the editor):

- **Simple** – Items palette (the original editor).
- **Intermediate** – adds **Textures** and **Meshes** tabs, each with a search box.
  - Textures: `ReplicatedStorage.PortalAssets.Textures` (Textures, Decals, or parts carrying one; sub-folders OK), or paste any texture asset id. Select surfaces, then click a texture.
  - Meshes: `ReplicatedStorage.PortalAssets.Meshes` (Models / MeshParts), or paste a mesh id (+ optional texture id). Drag into the room; right-click › Size.
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
