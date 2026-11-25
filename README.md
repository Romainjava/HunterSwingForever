# Hunter Swing Forever by Illusion

An Auto Shot rhythm bar for hunters on WoW Forever (interface 16001).

The bar covers one swing and tells you, at a glance:

- **MOVE** (green) while you may run, with a countdown to the red window;
- **STAND STILL** (red) for the last part of the swing, and the same words while a
  late shot is waiting for you to stop;
- **STOP** when you are moving exactly where you must stand;
- **TOO CLOSE** / **OUT OF RANGE** when a late shot is held up by range instead;
- **MELEE** (gold) and **TOO CLOSE** so the bar never disappears in close combat.

The red window at the end of the bar is exactly the time you must stand still. A slim
second bar under the main one fills over that time, stays full when the shot leaves and
turns grey when you run between shots.

Optional extras:

- range check with a distance estimate (`20-25 yd` or `~23 yd`);
- shots-to-kill estimate from the target's health and your average shot;
- ammo left as a percentage or a count, coloured by how much is left;
- ammo vendor pins on the world map and the minimap: 139 vendors, coloured by faction,
  hover for what they sell, click for a waypoint;
- an options window with layouts, fonts, colours, the stand-still window and every toggle.

## Commands

| Command | Effect |
|---|---|
| `/hsf` | open or close the options window |
| `/hunterswing` | alias of `/hsf` |
| `/hsf reset` | forget the bar position |
| `/hsf lock` / `/hsf unlock` / `/hsf move` | lock, unlock or toggle dragging |
| `/hsf range` | print what the range check sees |
| `/hsf moving` | print the movement source that is used |
| `/hsf timing` | print the last shot gaps and the measured stand-still time |
| `/hsf probe` | print what the shots-to-kill estimate sees |

The settings and measurements are stored in the `HunterSwingForeverDB` saved variable.
The bar is hunter-only; the options window and the commands work on any class.

Settings can also be reached from Options -> AddOns -> Hunter Swing Forever -> Open settings.

## Notes

- The stand-still time is learned from your own shots (median of the last nine), so the red
  window follows your latency. Until three shots are learned, it uses 0.5 s plus your ping.
- No dependency: the bundled fonts are under the SIL OFL (see `NOTICE.md`), the vendor data
  comes from pfQuest and Wowhead facts (see `NOTICE.md`).
