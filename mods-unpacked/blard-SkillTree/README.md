# Skill Tree (blard-SkillTree)

Path of Exile style passive tree for Brotato 1.2.0.2 (+ Abyssal Terrors / Primal Dread).

- Level-ups give skill points instead of the 4-upgrade choice screen. Crates are unchanged.
- After a wave where you levelled up, the tree opens before the shop (one player at a time in co-op).
- In the shop: "Skill Tree" button next to Reroll, or P (keyboard) / Back-Select (controller).
- 105 nodes in 8 sectors: Vitality, Melee, Precision, Ranged, Elemental, Engineering, Fortune, Agility.
  Small passives, 16 notables, 8 keystones with big trade-offs, and cross-links between sectors.
- Endless frontier: taking a keystone or frontier node places a cluster: one of 13 patterns
  (patterns.gd, generated + validated by build/patterns2.py), 6-25 nodes, 2-7 notables, loops,
  and >= 2 exits at right angles. Rotated/mirrored to fit: >= 130px between nodes, no
  crossing lines. Orbit exits (cyan) grow the next cluster around the tree (tangent to the
  centre), so you can circle to other sections; ports/exits link to nearby far-along nodes.
- Stat desire: new nodes' stats are weighted by the frontier node (strong), its neighbours
  (medium, allocated x2), your tree investment (weaker), plus noise. One exit per cluster is a
  "New direction" node drawing from your least-wanted stats.
- Minor spur nodes (35% of clusters): +1 Evolution, -1 Evolution or +1 Curse.
- Mechanized/Mutated/Cursed clusters: level = Evolution (+) / Evolution (-) / Curse (dual
  evolution: both use |Evolution|). 0% at level 0, +2.5% per level, max 35%.
- Red crits (extensions/entities/units/enemies/enemy.gd): crit chance over 100% rolls crit
  tiers; each tier past 1 multiplies crit damage by 1.5 (+ "red_crit" mods). Red/purple
  numbers via extensions/visual_effects/floating_text/floating_text_manager.gd.
- Oddity capstones (teal halo): hand-made bundles of secondary stats - pickup range,
  consumable healing, blocked hits, materials per crate, bounces, piercing damage, damage vs
  bosses, cheaper rerolls/weapons, knockback, XP gain, explosion size, extra trees.
- Relics (sparkling gold halo): very rare, one of each per run. Bottomless Bank (interest
  keeps paying past wave 20), Evergreen (harvesting keeps growing past wave 20), Extra
  Arsenal (+1 weapon slot, can't be refunded), Font of Insight (+1 skill point every wave),
  Treasure Map (+1 loot alien every wave), Lumberjack, Shopkeeper's Favor, Aegis.
  Oddity and relic amounts are exact and ignore the power option.
- Click a far node to take the whole highlighted path if you have the points.
- Refund (right-click / Y) any node whose removal keeps the rest connected. Can be turned off.
- Characters that turn level-ups into weapon slots still get their slots.

Controls
- Mouse: hover = inspect, click = allocate, right-click = refund, drag = pan, wheel = zoom, Esc = close.
- Keyboard: arrows/WASD move, Enter/Space allocate, Backspace/R refund, +/- zoom, Home = start, Esc/P close.
- Controller: stick/D-pad move, A allocate, Y/X refund, right stick pan, LB/RB zoom, B/Back close.

Mod Options (optional): open on level-up, allow refunds, points per level (1-3), node power (50-200%).
Power is locked into a run the first time it uses the tree.

Tree data is generated (tree_data.gd); stats are applied with RunData.add_stat, saved with the run.
