# Plugin Load Cleanup Evidence

## Verification Plan

The final check will assert:

- six deleted source paths do not exist;
- six moved source paths do not exist;
- six optional destination paths exist;
- all seven updated cfg commands use `optional/` paths;
- no old explicit path remains in cfg files;
- only the scoped binaries, cfg files, and task records changed.

## Runtime Boundary

No dedicated SourceMod runtime is available in this workspace. Startup-log behavior must be confirmed by restarting the target server after deployment. The repository checks can prove filesystem and cfg consistency, but cannot prove extension availability or plugin dependency resolution at runtime.

## Fresh Verification Results

Command: PowerShell path and cfg consistency assertions.

- Deleted paths absent: 6.
- Moved destinations present and sources absent: 6.
- Updated explicit load commands present: 7.
- Stale explicit load commands: 0.

Command: `git diff --check` and `git diff --check --cached`.

- Both exited with status 0 and produced no whitespace errors.

Command: `git diff --cached --summary`.

- Six plugin moves were detected as `R100`, proving the binary contents were unchanged.
- Six other target plugin paths were deleted.

## Residual Risk

- The actual dedicated-server startup log was not available for a post-change run.
- SourceMod extension availability and dependency resolution remain runtime checks.
- The task records under this directory are untracked until intentionally included in the next commit.
