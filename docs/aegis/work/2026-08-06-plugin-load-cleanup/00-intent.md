# Plugin Load Cleanup Intent

## Scope

Process the SourceMod plugins named in the startup log from 2026-08-05. Delete a target plugin when no cfg file explicitly loads its path. Move an explicitly loaded target plugin into `addons/sourcemod/plugins/optional/` and update the explicit command to the new path.

## Acceptance Criteria

- The six non-explicit target paths are absent.
- The six explicit target plugins exist only under `plugins/optional/`.
- Every explicit load command points to the new `optional/` path.
- No unrelated plugin or cfg entry changes.

## Non-Goals

- Do not repair or recompile the reported plugins.
- Do not change dependency plugins such as `readyup.smx` or `l4d2_hittable_control.smx`.
- Do not change match-mode load ordering.
