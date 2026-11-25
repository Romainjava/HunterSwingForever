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
- A late shot is predicted the way the game retries it: Auto Shot is tried again 0.5 s
  after a refusal, so the bar waits for that retry instead of promising a shot you cannot
  make. A melee swing restarts the Auto Shot swing, and the stand-still time follows ranged
  haste (Rapid Fire, Quick Shots). After Feign Death, your first move or jump restarts the
  Auto Shot swing at the weapon's base speed + 0.15 s. Each of the four can be turned off in
  the options.
- The stand-still time is learned from shots without a temporary haste buff, so Rapid Fire
  and Quick Shots do not pull it down; under the buff the window shrinks by the haste.
- No STOP in the last 0.1 s before the shot: a move that late no longer stops it.

### Extras

- Range check with a distance estimate (`20-25 yd` or `~23 yd`). The range no longer shows
  OUT OF RANGE when the game hides the range in combat: an unreadable range now stays
  unknown instead of guessing.
- Shots-to-kill estimate from the target's health and your average shot.
- Ammo left as a percentage or a count, coloured by how much is left.
- 139 ammo vendors pinned on the world map and the minimap, coloured by faction, with a
  tooltip showing what they sell and a click to set a waypoint.
- `/hsf timing` now also reports the Auto Shot tries the game refused (how many, and how
  long before the shot) and the haste seen (your swing speed against the weapon's).

### Options and commands

- Options window with layouts, fonts, colours, the stand-still window and every toggle;
  also reachable from Options -> AddOns -> Hunter Swing Forever -> Open settings.
- Lock, unlock, drag or reset the bar position.
- Commands: `/hsf`, `/hunterswing`, and `/hsf reset`, `lock`, `unlock`, `move`, `range`,
  `moving`, `timing`, `probe`.
- `/hsf record on` / `off` / `clear` (off by default): records every shot, melee swing,
  refused try, move, jump, spell, haste and range change, with the bar's prediction, into
  the saved variables, to measure the timing over a long session.
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
- Un tir en retard est prédit comme le jeu le retente : Auto Shot est retenté 0,5 s après un
  refus, donc la barre attend ce nouvel essai au lieu de promettre un tir impossible. Un
  coup au corps à corps relance le tir automatique, et le temps d'immobilité suit la hâte à
  distance (Rapid Fire, Quick Shots). Après Feindre la mort, le premier déplacement ou saut
  relance le tir automatique à la vitesse de base de l'arme + 0,15 s. Chacun des quatre se
  désactive dans les options.
- Le temps d'immobilité est appris sur les tirs sans buff de hâte temporaire, pour que Rapid
  Fire et Quick Shots ne le faussent pas ; sous le buff, la fenêtre rétrécit avec la hâte.
- Plus de STOP dans les 0,1 dernière seconde avant le tir : un mouvement aussi tardif ne
  l'empêche plus.

#### En plus

- Vérification de portée avec une estimation de distance (`20-25 yd` ou `~23 yd`). La
  portée n'affiche plus OUT OF RANGE quand le jeu cache la portée en combat : une portée
  illisible reste inconnue au lieu d'être devinée.
- Estimation du nombre de tirs pour tuer, à partir de la vie de la cible et de votre tir
  moyen.
- Munitions restantes en pourcentage ou en nombre, colorées selon ce qu'il reste.
- 139 vendeurs de munitions sur la carte du monde et sur la minicarte, colorés par faction,
  avec une infobulle sur ce qu'ils vendent et un clic pour poser un point de passage.
- `/hsf timing` indique aussi les tirs automatiques que le jeu a refusés (combien, et
  combien de temps avant le tir) et la hâte vue (votre vitesse de tir face à celle de
  l'arme).

#### Options et commandes

- Fenêtre d'options avec dispositions, polices, couleurs, fenêtre d'immobilité et tous les
  réglages ; aussi accessible par Options -> AddOns -> Hunter Swing Forever -> Open
  settings.
- Verrouiller, déverrouiller, déplacer ou réinitialiser la position de la barre.
- Commandes : `/hsf`, `/hunterswing`, et `/hsf reset`, `lock`, `unlock`, `move`, `range`,
  `moving`, `timing`, `probe`.
- `/hsf record on` / `off` / `clear` (désactivé par défaut) : enregistre chaque tir, coup au
  corps à corps, essai refusé, mouvement, saut, sort, changement de hâte et de portée, avec
  la prédiction de la barre, dans la variable sauvegardée, pour mesurer le timing sur une
  longue session.
- Les réglages sont stockés dans la variable sauvegardée `HunterSwingForeverDB`.

#### Remarques

- Aucune dépendance : les polices fournies sont sous SIL OFL (voir `NOTICE.md`) et les
  données des vendeurs viennent de pfQuest et de Wowhead (voir `NOTICE.md`).
- La barre est réservée aux chasseurs ; la fenêtre d'options et les commandes marchent avec
  toutes les classes.
