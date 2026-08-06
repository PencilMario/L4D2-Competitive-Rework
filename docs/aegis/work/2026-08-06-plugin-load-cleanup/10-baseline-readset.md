# Plugin Load Cleanup Baseline

## Facts

- `addons/sourcemod/plugins/*.smx` is the automatic-load area used by this repository.
- Existing cfg conventions explicitly load optional plugins with `sm plugins load optional/<name>.smx`.
- `cfg/server.cfg` sets `confogl_match_execcfg_plugins` to `generalfixes.cfg;confogl_plugins.cfg;sharedplugins.cfg`.
- Mode-specific plugin cfg files load `l4d2_hittable_control.smx` and `readyup.smx` before the root `cfg/sharedplugins.cfg` runs.

## Target Classification

Delete because no explicit load was found:

- `addons/sourcemod/plugins/l4d_MusicMapStart.smx`
- `addons/sourcemod/plugins/fun/l4d_MusicMapStart.smx`
- `addons/sourcemod/plugins/l4d_swimming.smx`
- `addons/sourcemod/plugins/fun/l4d2_airstrike.core.smx`
- `addons/sourcemod/plugins/clientprefs.smx`
- `addons/sourcemod/plugins/l4d2_CreateSurvivorBot_Test.smx`

Move to `plugins/optional/` and update cfg paths:

- `l4d2_tank_reset_iron.smx`: `cfg/sharedplugins.cfg`
- `fun/fortnite_l4d1_2.smx`: `cfg/sharedplugins.cfg`
- `fun/l4d_laser_sp.smx`: `cfg/sharedplugins.cfg`
- `fun/l4d_climb.smx`: `cfg/sharedplugins.cfg`
- `fun/l4d_jump_beamring.smx`: `cfg/sharedplugins.cfg`
- `afkspec_kick.smx`: `cfg/cfgogl/hyzmtf/shared_plugins.cfg` and `cfg/cfgogl/hyzonemod/shared_plugins.cfg`

## Unknowns

- A dedicated SourceMod runtime is not available in this workspace, so final startup-log behavior cannot be exercised here.
