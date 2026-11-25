# Changelog

## 1.0.0 - 2026-11-25

First public release: an Auto Shot rhythm bar for hunters on WoW Forever, plus ammo
vendors on the map.

### The bar

- Shows one Auto Shot swing at a glance: **MOVE** (green) with a countdown to the red
  window, **STAND STILL** (red) for the last part of the swing, and **STOP** when you are
  moving exactly where you must stand.
- The red window at the end of the bar is exactly the time you have to stand still.
- A slim second bar under the main one fills over that window, stays full when the shot
  leaves and turns grey when you run between shots.
- Late shots keep talking: **STAND STILL**, **STOP**, **TOO CLOSE** or **OUT OF RANGE**
  while a shot waits for you.
- **MELEE** (gold) and **TOO CLOSE** so the bar never disappears in close combat.
- The stand-still time is learned from your own shots (median of the last nine), so the
  red window follows your latency; until three shots are learned it uses 0.5 s plus your
  ping.

### Extras

- Range check with a distance estimate (`20-25 yd` or `~23 yd`).
- Shots-to-kill estimate from the target's health and your average shot.
- Ammo left as a percentage or a count, coloured by how much is left.
- 139 ammo vendors pinned on the world map and the minimap, coloured by faction, with a
  tooltip showing what they sell and a click to set a waypoint.

### Options and commands

- Options window with layouts, fonts, colours, the stand-still window and every toggle;
  also reachable from Options -> AddOns -> Hunter Swing Forever -> Open settings.
- Lock, unlock, drag or reset the bar position.
- Commands: `/hsf`, `/hunterswing`, and `/hsf reset`, `lock`, `unlock`, `move`, `range`,
  `moving`, `timing`, `probe`.
- Settings are stored in the `HunterSwingForeverDB` saved variable.

### Notes

- No dependency: the bundled fonts are under the SIL OFL (see `NOTICE.md`), and the vendor
  data comes from pfQuest and Wowhead facts (see `NOTICE.md`).
- The bar is hunter-only; the options window and the commands work on any class.

### Français

Première version publique : une barre de rythme Auto Shot pour les chasseurs sur WoW
Forever, avec les vendeurs de munitions sur la carte du monde.

#### La barre

- Montre un tir automatique d'un coup d'œil : **MOVE** (vert) avec un compte à rebours vers
  la fenêtre rouge, **STAND STILL** (rouge) pour la dernière partie du tir, et **STOP**
  quand vous bougez exactement là où il faut s'arrêter. Les textes de la barre sont en
  anglais, comme dans le reste de l'addon.
- La fenêtre rouge à la fin de la barre est exactement le temps pendant lequel il faut
  rester immobile.
- Une fine seconde barre sous la barre principale se remplit pendant cette fenêtre, reste
  pleine quand le tir part et devient grise quand vous courez entre deux tirs.
- Les tirs en retard continuent de parler : **STAND STILL**, **STOP**, **TOO CLOSE** ou
  **OUT OF RANGE** pendant qu'un tir attend.
- **MELEE** (doré) et **TOO CLOSE** pour que la barre ne disparaisse jamais au contact.
- Le temps d'immobilité est appris de vos propres tirs (médiane des neuf derniers), donc la
  fenêtre rouge suit votre latence ; avant trois tirs appris, elle vaut 0,5 s plus votre
  ping.

#### En plus

- Vérification de portée avec une estimation de distance (`20-25 yd` ou `~23 yd`).
- Estimation du nombre de tirs pour tuer, à partir de la vie de la cible et de votre tir
  moyen.
- Munitions restantes en pourcentage ou en nombre, colorées selon ce qu'il reste.
- 139 vendeurs de munitions sur la carte du monde et sur la minicarte, colorés par faction,
  avec une infobulle sur ce qu'ils vendent et un clic pour poser un point de passage.

#### Options et commandes

- Fenêtre d'options avec dispositions, polices, couleurs, fenêtre d'immobilité et tous les
  réglages ; aussi accessible par Options -> AddOns -> Hunter Swing Forever -> Open
  settings.
- Verrouiller, déverrouiller, déplacer ou réinitialiser la position de la barre.
- Commandes : `/hsf`, `/hunterswing`, et `/hsf reset`, `lock`, `unlock`, `move`, `range`,
  `moving`, `timing`, `probe`.
- Les réglages sont stockés dans la variable sauvegardée `HunterSwingForeverDB`.

#### Remarques

- Aucune dépendance : les polices fournies sont sous SIL OFL (voir `NOTICE.md`) et les
  données des vendeurs viennent de pfQuest et de Wowhead (voir `NOTICE.md`).
- La barre est réservée aux chasseurs ; la fenêtre d'options et les commandes marchent avec
  toutes les classes.
