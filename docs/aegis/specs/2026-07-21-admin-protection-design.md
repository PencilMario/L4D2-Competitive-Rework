# Administrator Kick and Ban Protection

## Intent

Add a SourceMod plugin that prevents authenticated human administrators from
being kicked or banned through the server's common command and SourceMod ban
paths. A protected administrator is a connected, non-bot client whose
`AdminId` is valid after SourceMod authentication.

## Design

The plugin uses two interception layers:

1. Implement `OnBanClient` and `OnBanIdentity` as pre-forwards. When the target
   resolves to a protected administrator, return `Plugin_Handled`; otherwise
   return `Plugin_Continue`.
2. Register command listeners for common kick and ban commands, including
   `kick`, `banid`, `addip`, `sm_kick`, and `sm_ban`. Parse only enough of each
   command to resolve its target. Return `Plugin_Handled` when any resolved
   target is protected and log the blocked attempt.

Protection applies regardless of whether the command originated from a player,
RCON, or the server console. A configuration ConVar, writable only through the
normal SourceMod permission system, allows server operators to disable the
protection temporarily for emergency maintenance. Protection is enabled by
default.

## Target Resolution

- Client-oriented commands use SourceMod target processing where appropriate.
- Engine commands resolve user IDs, Steam identities, IP addresses, or exact
  connected-client identities according to the command's argument format.
- An identity ban is blocked only when it matches a currently connected,
  protected administrator. The plugin does not maintain a separate offline
  administrator database.
- Bots and clients whose administrator check has not completed are not
  protected.

## Feedback and Logging

Blocked player-issued commands receive a concise command reply. Every blocked
attempt is written to the SourceMod log with the command source and protected
target. The target is not notified to avoid unnecessary chat noise.

## Compatibility Boundary

The plugin must compile against the SourceMod includes bundled in this
repository and must not require an additional extension.

SourceMod exposes cancellable forwards for bans, but it does not expose a
general cancellable forward for direct calls to `KickClient()`. Consequently,
the plugin blocks the registered command paths but cannot intercept another
plugin that calls `KickClient()` directly. Engine disconnects, timeouts, server
shutdowns, and network failures remain unaffected.

## Acceptance Criteria

- A protected administrator cannot be targeted by the registered kick or ban
  commands, including commands issued by the server console.
- `OnBanClient` returns `Plugin_Handled` for a protected administrator.
- `OnBanIdentity` returns `Plugin_Handled` when the identity belongs to a
  connected protected administrator.
- Non-admin human players and bots keep the server's existing behavior.
- Disabling the protection ConVar makes every callback return or behave as an
  unblocked path.
- The plugin compiles without errors or warnings using the bundled compiler.

## Non-Goals

- Protecting offline administrator identities.
- Preventing direct `KickClient()` calls made by arbitrary third-party plugins.
- Preventing legitimate disconnects or changing administrator immunity levels.
- Modifying the existing basecommands, basebans, or vote plugins.

## Design Inputs

**Task intent:** Add administrator kick and ban protection with cancellable
pre-callbacks returning `Plugin_Handled`.

**Baseline read set:** Existing `basecommands`, `basebans`, bundled SourceMod
`banning.inc`, and `nativevotes_kickvote_immunity.sp` define the relevant
commands, forwards, compiler API, and current vote-only protection.

**Impact statement:** Adds one standalone scripting plugin. It affects command
dispatch and ban forwards but does not change shared includes, persistence, or
existing plugin ownership.
