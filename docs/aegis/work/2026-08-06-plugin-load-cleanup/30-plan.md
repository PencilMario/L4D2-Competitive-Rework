# Plugin Load Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use aegis:subagent-driven-development (recommended) or aegis:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove startup-autoload failures for the listed SourceMod plugins by deleting unowned plugin files and moving cfg-owned plugins into the optional directory.

**Architecture:** SourceMod auto-discovers `.smx` files in the main plugin directory. Config-owned plugins are kept outside that discovery path and loaded explicitly through `optional/<name>.smx`. The existing match-mode dependency order is preserved.

**Tech Stack:** SourceMod plugin layout, SourceMod cfg commands, Git file moves/deletions, PowerShell verification.

**Baseline / Authority Refs:** User-provided startup log; `README.md`; `cfg/server.cfg`; `cfg/sharedplugins.cfg`; mode-specific `shared_plugins.cfg` files; `docs/aegis/work/2026-08-06-plugin-load-cleanup/10-baseline-readset.md`.

**Compatibility Boundary:** Explicitly loaded plugins must remain loadable at the same logical points, with only their path changed to `optional/<name>.smx`. No other plugin, dependency, or match-mode ordering may change.

**Verification:** Check target paths, search all cfg files for stale paths, verify every `optional/<name>.smx` exists, and inspect the final Git diff/status. Runtime startup verification remains external.

---

### Task 1: Remove Unowned Startup Targets

**Files:**
- Delete: `addons/sourcemod/plugins/l4d_MusicMapStart.smx`
- Delete: `addons/sourcemod/plugins/fun/l4d_MusicMapStart.smx`
- Delete: `addons/sourcemod/plugins/l4d_swimming.smx`
- Delete: `addons/sourcemod/plugins/fun/l4d2_airstrike.core.smx`
- Delete: `addons/sourcemod/plugins/clientprefs.smx`
- Delete: `addons/sourcemod/plugins/l4d2_CreateSurvivorBot_Test.smx`

**Why this task exists:** These six paths are in auto-load locations and have no explicit cfg load owner.

**Verification:** Confirm all six paths are absent and no cfg file references their exact plugin names.

**Repair Track:** Remove the automatic-load sources of the reported errors; the canonical owner is the cfg layer, and no owner is retained for these six unconfigured plugins.

**Retirement Track:** The duplicate music plugin paths and other unowned binaries retire permanently from the repository; restore only if a future cfg explicitly claims the plugin.

- [ ] Delete only the six listed paths.
- [ ] Verify deletion and stale-reference absence.

### Task 2: Move Cfg-Owned Plugins to Optional

**Files:**
- Move: `addons/sourcemod/plugins/l4d2_tank_reset_iron.smx` to `addons/sourcemod/plugins/optional/l4d2_tank_reset_iron.smx`
- Move: `addons/sourcemod/plugins/fun/fortnite_l4d1_2.smx` to `addons/sourcemod/plugins/optional/fortnite_l4d1_2.smx`
- Move: `addons/sourcemod/plugins/fun/l4d_laser_sp.smx` to `addons/sourcemod/plugins/optional/l4d_laser_sp.smx`
- Move: `addons/sourcemod/plugins/fun/l4d_climb.smx` to `addons/sourcemod/plugins/optional/l4d_climb.smx`
- Move: `addons/sourcemod/plugins/fun/l4d_jump_beamring.smx` to `addons/sourcemod/plugins/optional/l4d_jump_beamring.smx`
- Move: `addons/sourcemod/plugins/afkspec_kick.smx` to `addons/sourcemod/plugins/optional/afkspec_kick.smx`

**Why this task exists:** These plugins already have explicit cfg owners, so their files should not also be discovered and loaded automatically.

**Impact / Compatibility:** The binary contents remain unchanged. Only the filesystem path changes; explicit load commands are updated in Task 3.

**Verification:** Each source path is absent, each destination exists, and Git recognizes six renames.

**Repair Track:** Move the canonical cfg-owned binaries out of auto-discovery while retaining their explicit load lifecycle.

**Retirement Track:** The old root and `fun/` copies retire; no duplicate copy remains in an auto-load directory.

- [ ] Move exactly the six listed binaries.
- [ ] Verify source/destination exclusivity.

### Task 3: Synchronize Explicit Load Paths

**Files:**
- Modify: `cfg/sharedplugins.cfg`
- Modify: `cfg/cfgogl/hyzmtf/shared_plugins.cfg`
- Modify: `cfg/cfgogl/hyzonemod/shared_plugins.cfg`

**Why this task exists:** SourceMod load commands use the plugin-relative path, so moved binaries require `optional/` prefixes.

**Verification:** Search all cfg files for stale old paths and assert every six new paths has a corresponding explicit command.

**Repair Track:** Update the existing cfg command owners only; preserve command order and surrounding settings.

**Retirement Track:** Old unprefixed/path-prefixed commands retire when replaced by their `optional/` equivalents. No automatic fallback is added.

- [ ] Replace five `cfg/sharedplugins.cfg` paths and two `afkspec_kick` paths.
- [ ] Verify no stale target path remains.

### Task 4: Final Regression Checks

**Files:**
- Verify all files above and the task evidence record.

**Why this task exists:** File moves and deletions can leave stale config references or accidental extra changes.

**Verification:** Run the exact PowerShell assertions from `50-evidence.md`, then inspect `git diff --stat`, `git diff --name-status`, and `git status --short`.

- [ ] Run path and cfg consistency checks.
- [ ] Review the final diff for scope and record residual runtime risk.
