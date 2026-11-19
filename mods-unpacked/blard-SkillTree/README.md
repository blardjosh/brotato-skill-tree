# Skill Tree (blard-SkillTree)

Path of Exile style passive tree for Brotato 1.2.0.2 (+ Abyssal Terrors / Primal Dread).

- Level-ups give skill points instead of the 4-upgrade choice screen. Crates are unchanged.
- After a wave where you levelled up, the tree opens before the shop (one player at a time in co-op).
- In the shop: "Skill Tree" button next to Reroll, or P (keyboard) / Back-Select (controller).
- 105 nodes in 8 sectors: Vitality, Melee, Precision, Ranged, Elemental, Engineering, Fortune, Agility.
  Small passives, 16 notables, 8 keystones with big trade-offs, and cross-links between sectors.
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
