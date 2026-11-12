#!/usr/bin/env bash
# SoloShot folder reorganization. Run from the project root (the folder with project.godot),
# with Godot CLOSED, after committing or backing up. Safe to re-run: files already moved are skipped.
set -u
[ -f project.godot ] || { echo "Run this from the folder that contains project.godot"; exit 1; }
command -v perl >/dev/null || { echo "perl is required (it ships with macOS, Linux and Git for Windows)"; exit 1; }

# old_path new_path   (relative to the project root)
MOVES="
modes/game_mode.gd            rules/game_mode.gd
modes/shot_result.gd          rules/shot_result.gd
modes/cue_placement.gd        rules/cue_placement.gd
modes/layout_def.gd           rules/layout_def.gd
input/cue_placer.gd           rules/cue_placer.gd
game/shot_report.gd           rules/shot_report.gd
game/rack_builder.gd          rules/rack_builder.gd
game/rack_jitter.gd           rules/rack_jitter.gd
game/pocketed_log.gd          rules/pocketed_log.gd
modes/free_practice_mode.gd   rules/modes/free_practice_mode.gd
modes/9_ball.gd               rules/modes/nine_ball_mode.gd
modes/time_trial_mode.gd      rules/modes/time_trial_mode.gd
game/mode_catalog.gd          rules/modes/mode_catalog.gd
input/cue_placment_controller.gd  input/cue_placement_controller.gd
game/shot_predictor.gd        input/shot_predictor.gd
game/prediction_result.gd     input/prediction_result.gd
game/coordinate_mapper.gd     screen/coordinate_mapper.gd
game/screen_layout.gd         screen/screen_layout.gd
ui/safe_area.gd               screen/safe_area.gd
game/pocketed_tray.gd         view/pocketed_tray.gd
game/placement_overlay.gd     view/placement_overlay.gd
scenes/testing.tscn           tests/testing.tscn
scenes/testing_prediction.tscn tests/testing_prediction.tscn
"

moved=0
while read -r old new; do
  [ -z "${old:-}" ] && continue
  if [ ! -f "$old" ]; then
    [ -f "$new" ] || echo "skip (not found): $old"
    continue
  fi
  mkdir -p "$(dirname "$new")"
  mv "$old" "$new"
  [ -f "$old.uid" ] && mv "$old.uid" "$new.uid"
  # Fix every text reference to the old path.
  export OLD="res://$old" NEW="res://$new"
  find . -path ./.godot -prune -o -type f \
    \( -name '*.tscn' -o -name '*.tres' -o -name '*.gd' -o -name '*.godot' -o -name '*.cfg' \) \
    -print0 | xargs -0 perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g'
  echo "moved: $old -> $new"
  moved=$((moved+1))
done <<< "$MOVES"

# Drop now-empty old folders (modes/ is replaced by rules/modes/).
rmdir modes 2>/dev/null
echo "Done: $moved file(s) moved. Open the project in Godot; it will re-scan on first load."
