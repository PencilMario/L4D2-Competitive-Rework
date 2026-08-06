# Plugin Load Cleanup Atomic Tasks

- [x] Read the startup errors and enumerate every target path.
- [x] Search cfg files for exact explicit load commands.
- [x] Confirm optional directory conventions and dependency load order.
- [x] Delete the six targets without explicit cfg ownership.
- [x] Move the six cfg-owned targets into `plugins/optional/`.
- [x] Update seven explicit load commands to `optional/` paths.
- [x] Run path, reference, and diff-scope verification.
- [x] Record final evidence and residual runtime risk.
