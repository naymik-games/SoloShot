# SoloShot — Project Overview

A one-player pool game for mobile (landscape), built in **Godot 4.7** with **GDScript**. It has its own deterministic 2D pool physics (with cue-ball spin), a drag-to-aim interface with a live shot prediction, and three solo game modes.

> This document describes the project as it stands after the `pool_game.gd` split and the folder reorganization. File paths are relative to the project root (`res://`).

---

## 1. At a glance

| | |
|---|---|
| Engine | Godot 4.7, **Mobile** renderer, GDScript |
| Main scene | `scenes/home.tscn` (the menu) → `scenes/pool_game.tscn` |
| Display | `canvas_items` stretch, aspect `expand`; layout is built for **landscape** |
| Physics | Custom 2D simulator in `sim/` (not Godot physics). Godot's 3D "Jolt" setting in `project.godot` is irrelevant to the game |
| Table | 2.54 m × 1.27 m (9 ft); all game logic uses **meters** |
| Size | About 4,400 lines of GDScript in roughly 55 scripts |
| Game modes | Free Practice, 9-Ball (solo), Time Trial |

---

## 2. Controls

**Touch / mouse**

| Action | How |
|---|---|
| Aim (coarse) | Drag anywhere on the table. Relative to where you touched down, so the line never jumps. Ignored within 55 px of the cue ball |
| Aim (fine) | Drag up/down on the thin strip right of the table (0.001 rad per pixel) |
| Power + fire | Pull the handle of the power bar (left of the table) **down**, then **release** to fire. Drag it back into the top dead zone and release to cancel |
| Spin | Tap or drag on the cue-ball face (bottom-right). Double-tap recenters. Resets after every shot |
| Place the cue ball | Drag it (relative drag, so your finger never covers it), then press **Place cue ball** |
| Back to menu | Home button (top-left of the HUD) |

**Keyboard (desktop testing)**

| Key | Action |
|---|---|
| ← / → | Nudge aim 0.25° (hold **Shift** for ×0.1) |
| W / S or mouse wheel | Power up / down (0.05 per key, 0.02 per wheel notch) |
| Space | Fire |
| Enter / Space | Confirm cue-ball placement |

---

## 3. The game modes

The menu (`scenes/home.gd`) lists the modes from `ModeCatalog.Type`. The chosen mode is handed to the game through `GameSession.selected_mode`.

### Common rules of the table

- Ball **0** is the cue ball; **1–15** are object balls.
- **Head string** is at 25% of the table length, **foot spot** at 75%. Racks have their apex on the foot spot.
- Every rack gets tiny random offsets (`rack_jitter`), so every break comes out differently.
- The **first shot after a fresh rack is the break**: higher speed cap (10 m/s) and a small random aim error that grows with power.
- Fouls the rules layer can detect (`ShotReport.Foul`): **Scratch** (cue ball pocketed), **No contact**, **Wrong ball first**, **No rail** (after contact, no ball reached a cushion and no object ball was pocketed). Each mode decides which matter.
- Before the break the cue ball is placed **anywhere behind the head string** (in Free Practice, unless a custom layout is used).

### Free Practice (`rules/modes/free_practice_mode.gd`)

- Standard 15-ball triangle, cue ball + no clock, never ends.
- Any ball is a legal first contact. Fouls are **shown as a message but never penalized**.
- After a scratch you place the cue ball **anywhere**.
- Clearing the table reports "Table cleared in N shots", keeps the best count, and racks again.
- It can also run a custom drill: assign a `LayoutDef` to `PoolGame.layout`. A custom layout starts with the cue ball where the layout puts it, and is never reracked.

### 9-Ball (`rules/modes/nine_ball_mode.gd`)

Solo: pocket the balls in order in as few shots as possible. The score is the shot counter (lower is better).

- Diamond rack: 1 at the apex, 9 in the center, balls 2–8 shuffled.
- The cue ball must hit the **lowest-numbered ball on the table** first.
- Any ball may be pocketed on a legal shot. **Pocketing the 9 on a legal shot ends the game** ("9-ball! Cleared in N shots").
- Fouls add penalty shots and **stack**:

| Foul | Penalty |
|---|---|
| Wrong ball first | +1 |
| No contact | +1 |
| Scratch | +2 |
| No rail | +2 (not charged on top of a scratch) |
| 9 pocketed on a foul (respotted at its rack spot) | +2 |

- After a scratch the cue ball returns to the head spot automatically (nearest free spot if occupied). A no-rail foul leaves the cue ball where it stopped, unless `no_rail_repositions_cue` is turned on.
- HUD shows `Shots: N (M penalty)` and `Next ball: X`.

### Time Trial (`rules/modes/time_trial_mode.gd`)

Pocket as many balls as possible before the clock runs out.

- 15-ball rack, **120 s** on the clock. The clock **starts on the first shot** (placing the break is free).
- **Points:** 100 per ball × the current multiplier.
- **Multiplier:** starts at 1.0, +0.5 after every shot that pockets a ball (max 4.0), −0.5 after a plain miss (min 1.0). A scratch resets it to 1.0.
- **Bonus time:** each pocketed ball adds 10 s on rack 1, 9 s on rack 2, 8 s on rack 3, … down to 0.
- **Scratch:** −30 s, multiplier reset, cue ball returns to the head spot. Balls pocketed on the same shot still count.
- Clearing a rack brings a fresh one. If the clock runs out during a shot, that shot still scores but earns no bonus time.
- At zero the game ends: "Time's up! Score … | N balls | N racks cleared".
- HUD shows time, score, multiplier, rack number and balls pocketed.

---

## 4. How the code works

### 4.1 The big idea

The project keeps **simulation, rules, input, drawing and UI strictly separate**:

- The **simulator** only moves balls and reports what happened as **events** (ball–ball, ball–cushion, pocketed, at rest). It knows nothing about rules or screens.
- The **rules layer** (`GameMode`) never touches physics. It reads a **`ShotReport`** (a summary built from the events) after each shot and returns a **`ShotResult`** (score, fouls, cue-ball placement, rerack, game over, message).
- **Views** only read state and draw. **Input** only produces a `Shot` or a cue-ball position.
- **`PoolGame`** is the conductor that wires these together and runs the phase machine.

### 4.2 Coordinates and units

- Everything simulated is in **meters**, origin at the **top-left of the playfield**, **+Y down**.
- `CoordinateMapper` (`screen/`) is the only place that converts meters ↔ pixels. Nodes that draw with it sit at (0,0) with no camera.
- The table is fitted into a region of the screen (see `ScreenLayout`), leaving room for the controls around it.

### 4.3 Folder map

```
sim/       Physics and plain data. Depends on nothing else in the project.
             pool_simulator, physics_params, table_def, table_builder, ball_state,
             sim_state, sim_event, shot, pocket, cushion_segment
rules/     What the game means. Depends on sim/.
             game_mode (base), shot_report, shot_result, cue_placement, cue_placer,
             rack_builder, rack_jitter, pocketed_log, layout_def
  modes/     free_practice_mode, nine_ball_mode, time_trial_mode, mode_catalog
input/     Turning touches/keys into aim and shots.
             aim_controller, aim_state, aim_config, cue_placement_controller,
             shot_predictor, prediction_result
screen/    Screen geometry.
             coordinate_mapper, screen_layout, safe_area
view/      Drawing only (reads state, never changes it).
             table_view, balls_layer, ball_view, aim_overlay, cue_stick,
             placement_overlay, pocketed_tray, debug_overlay
ui/        On-screen controls.
             hud, power_control, fine_aim_control, spin_control
game/      The conductor and its helpers.
             pool_game, game_session, shot_runner, placement_flow
scenes/    home.tscn (+ home.gd), pool_game.tscn
tests/     Headless test scenes: sim_tests, prediction_tests
data/      .tres configuration (physics, tables, aim, layouts)
shaders/   ball_sphere.gdshader
art/       Textures (table, balls, cue, menu backgrounds)
```

Dependencies point one way: `sim` has none, `rules` and `screen` build on `sim`, `input`/`view`/`ui` build on those, and `game` sits on top wiring everything. There are no folder-level cycles.

### 4.4 `PoolGame`: the conductor (`game/pool_game.gd`)

Owns the live `SimState`, the simulator, the current mode and the phase machine. Build order in `_ready()`:

1. `_build_core`: table geometry, simulator, shot predictor, state, `ShotRunner`, coordinate mapper.
2. `_build_views`: aim overlay and debug overlay setup.
3. `_wire_aim_input`: connects `AimController`, power bar and fine-aim strip (one shared `AimConfig`).
4. `_build_cue_stick`, `_build_pocketed_tray`, `_build_placement`, `_build_spin_control`.
5. `_start_game`: creates the mode via `ModeCatalog.create()`, racks the balls, then starts aiming (or asks the player to place the cue ball for the break).

Three helpers keep it small:

| Helper | Job |
|---|---|
| `ScreenLayout` (`screen/`) | All layout math: table area, tray strip, side controls, spin control, home-button safe area |
| `ShotRunner` (`game/`) | Fixed-timestep loop for one shot; fills the `ShotReport`. No rules or UI knowledge |
| `PlacementFlow` (`game/`) | Ball-in-hand UI: drag controller, overlay, "Place cue ball" button |

### 4.5 Phases

| Phase | What's happening |
|---|---|
| `SETUP` | Initial, before the game starts |
| `AIMING` | Aim/power/spin enabled; prediction line drawn; cue stick visible |
| `PLACING` | Player drags the cue ball and confirms; aim controls hidden |
| `SIMULATING` | A shot is in flight; input disabled |
| `RESOLVING` | Balls stopped; the mode rules on the shot (runs instantly, then moves on) |
| `GAME_OVER` | Input disabled; the message stays on screen. Use the home button to leave |

The mode's clock (`tick`) runs during aiming, placing and simulating. If time runs out outside a shot, the game ends immediately; during a shot it is handled when the shot resolves.

### 4.6 Life of a shot

1. The player releases the power handle (or presses Space). `AimController.fire()` locks input and emits `shot_requested(Shot)`, where a `Shot` is just a direction and a power.
2. `PoolGame._on_shot_requested`: tells the mode (`on_shot_taken`), applies the shot to the simulator (break speed and error on the break; spin offset = spin × `max_cue_offset`), resets the `ShotRunner`, enters `SIMULATING`.
3. Every physics frame `ShotRunner.advance()` steps the simulator in `substep` slices (1/480 s) and returns that frame's events. They are added to the `ShotReport`, logged by `PocketedLog` (for the tray), and passed to `mode.on_events`. The balls layer redraws.
4. When no ball is moving → `RESOLVING`: `mode.on_shot_ended(state, report)` returns a `ShotResult`.
5. `PoolGame` applies it: score and message, rerack if requested, then picks what comes next: **fixed respot** (automatic), **placing** (player drags the ball), or straight back to **aiming**. Safety nets: a pocketed cue ball always comes back (head spot), and a new rack that lands on the cue ball moves it to the head spot.
6. If `game_over` is set, the phase becomes `GAME_OVER`.

### 4.7 Cue-ball placement

A mode returns a `CuePlacement` from `initial_cue_placement()` or in a `ShotResult`:

| Mode | Meaning |
|---|---|
| `NONE` | Leave the cue ball where it is (if pocketed, falls back to the head spot) |
| `FIXED` | Put it at `spot` automatically (nearest free spot if occupied) |
| `LIMITED` | Player drags it, but only inside `region` (e.g. behind the head string for a break) |
| `ANYWHERE` | Player drags it anywhere on the playfield |

`CuePlacer` holds the geometry rules (valid positions, nearest free spot); `CuePlacementController` handles the drag; `PlacementOverlay` draws the region and a ring that is green on a legal spot and red otherwise.

### 4.8 Aim prediction

`ShotPredictor` clones the state and fires a **full-power** shot at the current angle through its **own** simulator instance, stopping at the first cue-ball contact (or a scratch, a rail, rest, or the time cap). It returns a `PredictionResult` (path, ghost-ball position, object-ball direction, outcome) that `AimOverlay` draws. It deliberately **ignores spin and the break's random error**, so the line stays clean. It never touches the live game.

### 4.9 The physics model (`sim/pool_simulator.gd`)

- **Deterministic** and independent of frame rate: friction is applied per substep, and every contact is solved at its **exact time** inside the substep (so the substep size doesn't affect accuracy).
- **Friction and spin:** each ball has a *slip* velocity (`vel + roll_spin`). While slipping, sliding friction acts until the ball reaches pure rolling; then a small rolling friction applies. With no spin this gives the classic loss of 2/7 of the speed before rolling. Spin survives ball–ball hits, which is what makes follow and draw work.
- **Side spin (english)** only matters at cushions: the cushion grips it and changes the rebound angle (`cushion_friction`); it also decays on the cloth.
- **Cushions** are 6 segments with rounded jaw tips at their ends; **pockets** are capture circles, with a backstop for balls whose center leaves the playfield. Pocket indices: 0 top-left, 1 top-middle, 2 top-right, 3 bottom-left, 4 bottom-middle, 5 bottom-right.
- The simulator emits `SimEvent`s (`BALL_BALL`, `BALL_CUSHION`, `BALL_POCKETED`, `BALLS_AT_REST`) with exact contact positions and post-impact velocities. Everything above the simulator (rules, prediction, tray) works from these events.

### 4.10 Drawing

- `TableView` draws the table art (`TableDef.art_texture`) or a procedural table if none is set.
- `BallView` draws each ball as a lit, rolling sphere using `shaders/ball_sphere.gdshader`. Rolling is purely visual (derived from on-screen movement). Textures are `res://art/balls/ball_<id>.png` (0 = cue ball); a flat colored fallback is used if a texture is missing.
- `CueStick` is a visual-only sprite that follows the aim angle and pulls back with power.
- `PocketedTray` shows pocketed balls in order in the band above the table.
- `HUD` shows the mode's status text (bottom-left) and a fading message panel.

---

## 5. Key configuration

Most tuning lives in `.tres` resources in `data/`. Select the resource in the FileSystem dock and edit it in the inspector. A setting that isn't listed in a `.tres` uses the default from its script.

### 5.1 Resource files in use

| File | Type | What it sets |
|---|---|---|
| `data/physics/default_physics.tres` | `PhysicsParams` | All defaults (no overrides) |
| `data/tables/london_table.tres` | `TableDef` | **Ball radius 0.039 m** (default 0.02858) and the London table art. Assigned in `pool_game.tscn` |
| `data/aim.tres` | `AimConfig` | `nudge_step_degrees = 0.05`, `power_curve_exponent = 1.9`; everything else default |
| `data/tables/standard_9ft.tres` | `TableDef` | Defaults, no art (the procedural table). **Not currently used** |
| `data/layouts/default15.tres` | `LayoutDef` | Empty. **Not currently used** |

The London table has a ball radius about 36% larger than regulation. That is a readability choice for small screens; the table's real size stays 2.54 × 1.27 m.

### 5.2 `PhysicsParams` (`sim/physics_params.gd`)

| Setting | Default | Meaning |
|---|---|---|
| `ball_restitution` | 0.95 | Bounciness of ball–ball hits |
| `cushion_restitution` | 0.75 | Speed kept after a cushion bounce |
| `cushion_tangent_loss` | 0.0 | Optional loss of speed along the cushion (0–~0.05) |
| `sliding_friction` | 0.2 | Friction while the ball slips on the cloth |
| `rolling_friction` | 0.01 | Friction while rolling (how far balls roll out) |
| `gravity` | 9.81 | Used with the friction coefficients |
| `stop_speed` | 0.005 | Below this speed (m/s) a rolling ball snaps to rest |
| `max_shot_speed` | 6.0 | Cue-ball speed (m/s) at power 1.0 |
| `substep` | 1/480 s | Simulation step. Collisions are exact, so this doesn't affect contact accuracy |

Groups:

| Group | Setting | Default | Meaning |
|---|---|---|---|
| Break | `break_max_shot_speed` | 10.0 | Speed at power 1.0 on a break |
| Break | `break_aim_error_deg` | 0.3 | Std. deviation of the break aim error at full power (scales with power) |
| Break | `rack_jitter` | 0.0002 | Max random offset (m, per axis) per object ball when racking |
| Break | `rack_min_gap` | 0.00002 | Minimum gap beyond touching after jitter |
| Spin | `max_cue_offset` | 0.7 | Cue-tip offset at the edge of the spin control, as a fraction of the ball radius |
| Spin | `side_spin_decay` | 1.5 | How fast english dies out on the cloth |
| Spin | `cushion_friction` | 0.2 | How hard a cushion grips side spin (0 = ignores english) |
| Spin | `cushion_roll_retention` | 0.0 | Fraction of top/back spin kept through a cushion bounce |

### 5.3 `TableDef` (`sim/table_def.gd`)

| Setting | Default | Meaning |
|---|---|---|
| `size` | 2.54 × 1.27 m | Playfield |
| `ball_radius` | 0.02858 | (London table overrides to 0.039) |
| `corner_pocket_capture_radius` / `side_pocket_capture_radius` | 0.07 / 0.06 | How close a ball center must get to be pocketed |
| `corner_mouth` / `side_mouth_half` | 0.098 / 0.079 | Pocket mouth openings (where cushions stop) |
| `corner_pocket_overhang` / `side_pocket_overhang` | 0.038 / 0.069 | How far pocket centers sit outside the playfield |
| `rail_width`, `cushion_thickness` | 0.09, 0.04 | Procedural look only |
| `art_texture` | none | Full table image including rails |
| `art_playfield_rect` | (50.5, 50.5, 865, 433) | The playfield inside the art, in **texture pixels** (measured from the 970 × 538 London art) |

If you change the art or the pocket geometry, turn on `TableView.show_collision_geometry` to check that the art and the physics line up.

### 5.4 `AimConfig` (`input/aim_config.gd`)

| Setting | Default | Meaning |
|---|---|---|
| `coarse_dead_zone_px` | 55 | Ignore table drags this close to the cue ball |
| `fine_strip_sensitivity` | 0.001 | Radians per pixel on the fine-aim strip |
| `nudge_step_degrees` | 0.1 (0.05 in `aim.tres`) | Only used by the old nudge buttons (see section 8) |
| `power_curve_exponent` | 1.6 (1.9 in `aim.tres`) | Power = input ^ exponent; higher = finer control on soft shots |
| `min_fire_power` | 0.02 | Releasing below this cancels instead of firing |
| `reset_power_each_shot` | false | Exported but not currently read (the controller always resets power) |
| `prediction_time_cap` | 4.0 s | Stop predicting after this long |
| `max_bounces` | 0 | Rail bounces the aim line follows (0 = ends at the first rail) |
| `show_aim_line`, `show_ghost_ball`, `show_object_line` | true | Overlay parts |
| `object_line_length` | 0.25 m | Length of the object-ball line |
| `key_nudge_degrees`, `key_fine_multiplier`, `key_power_step`, `wheel_power_step` | 0.25, 0.1, 0.05, 0.02 | Desktop controls |

### 5.5 `ScreenLayout` (`screen/screen_layout.gd`)

Assign one in `PoolGame.screen_layout`, or leave it empty for these defaults.

| Setting | Default | Meaning |
|---|---|---|
| `table_inset_left` / `right` | 0.065 / 0.065 | Screen fraction kept clear beside the table (power bar left, fine-aim strip right) |
| `table_inset_top` | 0.085 | Band above the table (pocketed-ball tray) |
| `table_inset_bottom` | 0.10 | Band below (HUD text, Place button) |
| `tray_gap_px` | 6 | Gap between tray and table area |
| `side_control_gap_px` | 12 | Gap between the table and the side controls |
| `side_control_height_fraction` | 0.8 | Side control height as a fraction of the table height |
| `spin_control_size_px` | 80 | Spin control diameter |
| `spin_control_margin_px` | 10 | Margin from the safe-area corner |

### 5.6 Mode constants

These are `const`s at the top of each mode script; change them in code.

| Mode | Constant | Value |
|---|---|---|
| 9-Ball | `PENALTY_WRONG_BALL`, `PENALTY_NO_CONTACT` | 1, 1 |
| 9-Ball | `PENALTY_SCRATCH`, `PENALTY_NO_RAIL`, `PENALTY_NINE_RESPOT` | 2, 2, 2 |
| 9-Ball | `shuffle_rack`, `no_rail_repositions_cue` (variables) | true, false |
| Time Trial | `start_time` (variable) | 120 s |
| Time Trial | `BALL_POINTS` | 100 |
| Time Trial | `MULT_MIN`, `MULT_MAX`, `MULT_STEP` | 1.0, 4.0, 0.5 |
| Time Trial | `BONUS_FIRST_RACK`, `BONUS_DROP_PER_RACK`, `BONUS_MIN` | 10 s, 1 s, 0 s |
| Time Trial | `SCRATCH_TIME` | 30 s |
| Free Practice | `show_detected_fouls`, `rerack_when_cleared` (variables) | true, true |

### 5.7 Other inspector settings worth knowing

| Where | Setting | Notes |
|---|---|---|
| `PoolGame` (in `pool_game.tscn`) | `mode_type` | Saved as **2 = Time Trial**. Only matters when you run `pool_game.tscn` directly; the menu overrides it |
| `PoolGame` | `debug_print_shot_report` | Currently **on**: prints a one-line summary of every shot to the Output panel |
| `PoolGame` | `layout` | Optional `LayoutDef` for a Free Practice drill |
| `TableView` | `show_collision_geometry` | Draws real cushions and pocket circles over the art |
| `DebugOverlay` | `enabled` | Cushion segments, pocket circles, velocity vectors |
| `CueStick` | `cue_length_m`, `tip_px`, `min_gap_radii`, `max_gap_radii` | Size of the cue and how far it pulls back |
| `PowerControl` | `dead_zone` (0.04), `grab_margin` (14 px) | Cancel zone and grab forgiveness |
| `Hud` | `message_seconds` (2.5), `bottom_band_px` (64), `status_left_px` (24), `status_width_px` (400), `message_y_fraction` (0.78) | HUD placement and message time |
| `project.godot` | stretch `canvas_items`, aspect `expand`; Mobile renderer | |

---

## 6. Scenes

**`scenes/home.tscn`**: the menu. `home.gd` builds the buttons in code from the `MODES` list, stores the choice in `GameSession.selected_mode`, then loads `pool_game.tscn`.

**`scenes/pool_game.tscn`** (root `pool_game`, script `PoolGame`):

```
pool_game (Node2D)            PoolGame: conductor
├─ TableView                  draws the table
├─ BallsLayer                 one BallView per ball
├─ AimOverlay                 aim line, ghost ball, object line
├─ DebugOverlay               optional debug drawing
├─ AimController              turns input into aim/shots
└─ UI (CanvasLayer)
   └─ HUD (Control)           stats text + messages
      ├─ FinAimControl        fine-aim strip (unique name %FinAimControl)
      ├─ PowerControl         power bar     (unique name %PowerControl)
      └─ home_button          back to menu  (unique name %home_button)
```

Created in code at startup: `CueStick`, `PocketedTray`, the placement controller/overlay/button (`PlacementFlow`) and `SpinControl`. The scene may still contain an unused `PlacementOverlay` node and an empty `VBoxContainer`; both are safe to delete (see section 8).

`PoolGame` finds its controls by **unique name** (`%PowerControl` etc.), so keep "Access as Unique Name" enabled on those nodes if you rebuild the scene.

---

## 7. Tests

Two headless test scenes in `tests/`. Open one and press **F6**; results print to the Output panel (failures also appear in the Errors tab).

| Scene | Script | Covers |
|---|---|---|
| `tests/testing.tscn` | `sim_tests.gd` | Head-on and cut shots, contact accuracy independent of speed, bank shot, coming to rest, pockets, rack break, random shots (energy and bounds), determinism |
| `tests/testing_prediction.tscn` | `prediction_tests.gd` | Prediction matches a real full-power shot, straight-shot geometry, prediction has no side effects on the live state |

The tests only use `sim/` and the predictor, which is possible because the simulator has no dependency on the scene tree.

---

## 8. How to…

**Add a game mode**
1. Create `rules/modes/my_mode.gd` with `class_name MyMode` and `extends GameMode`. Override what you need: `setup`, `initial_cue_placement`, `status_text`, `on_shot_taken`, `on_events`, `on_shot_ended`, `tick`, `is_time_up`, `time_up_message`.
2. In `ModeCatalog` (`rules/modes/mode_catalog.gd`), add a value **at the end** of `enum Type` (so the integer saved in `pool_game.tscn` stays valid) and a case in `create()`.
3. Add an entry to `MODES` in `scenes/home.gd` (label, subtitle, mode).

In `on_shot_ended` you receive a `ShotReport` (first contact, pocketed balls, cue pocketed, cushion after contact, plus `detect_fouls()`) and return a `ShotResult`. Build reracks with `RackBuilder` and cue-ball placements with `CuePlacement`.

**Add a table**: create a `TableDef` resource, set the size, pocket geometry and optional art (`art_texture` + `art_playfield_rect`), then assign it to `PoolGame.table_def` in `pool_game.tscn`.

**Change the feel**: ball speed and roll-out in `PhysicsParams`; aiming sensitivity and power curve in `data/aim.tres`; layout and control sizes in a `ScreenLayout` resource.

**Debug a shot**: keep `debug_print_shot_report` on, enable `TableView.show_collision_geometry` or `DebugOverlay.enabled`, and run the test scenes after any physics change.

---

## 9. Assets and external dependencies

Referenced from code or scenes (kept outside the code folders):

| Path | Used for |
|---|---|
| `art/singletableLondon-hd.png` | Table art (970 × 538) |
| `art/balls/ball_<id>.png` | Ball textures, 2:1 wrapped, number spots at u = 0.25 and 0.75; missing ones fall back to colors |
| `art/cue.png` | Cue stick, horizontal, tip on the left |
| `art/BG_Android_new.png`, `art/menuList.png` | Menu background and HUD button art |
| `shaders/ball_sphere.gdshader` | Lit, rolling ball look |
| Custom font (set in project settings) | Global UI theme |

---

## 10. Known quirks and loose ends

These are things noticed while writing this document; none stops the game from working.

1. **Time Trial comments don't match the code.** The header says the multiplier rises *before* scoring (1.5× on the first ball). The code scores at the *current* multiplier and raises it afterwards, so the first pocketing shot scores at 1.0×. The HUD message shows the *raised* value ("+100 (x1.5)"). The header also says bonus time is multiplied; that part is commented out in the code (`#* multiplier`), so bonus time is **not** multiplied.
2. **`ShotResult.foul` and `respot_balls` are informational.** `PoolGame` doesn't act on them (there's a TODO in `_apply_result`). 9-Ball respots the 9 by changing the state itself.
3. **`Hud.set_score()` is a stub.** Scores appear through the mode's `status_text()`.
4. **Unused settings.** `AimConfig.nudge_step_degrees` was only used by the removed nudge buttons, and `reset_power_each_shot` is exported but never read.
5. **Unused data files:** `data/layouts/default15.tres` and `data/tables/standard_9ft.tres`.
6. **Scene defaults:** `pool_game.tscn` saves `mode_type = Time Trial` and `debug_print_shot_report = true`.
7. **Stale comment in `sim_tests.gd`:** it mentions `tests/sim_test_runner.tscn`; the scene is `tests/testing.tscn`.
8. **No restart from game over.** The only way out is the home button.
9. **Prediction ignores spin** by design, so the aim line shows the no-spin path.
10. **`project.godot` sets Jolt 3D physics**, which the game doesn't use.
