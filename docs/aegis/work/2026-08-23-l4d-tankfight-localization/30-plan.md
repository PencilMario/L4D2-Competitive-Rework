# TankFight Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use aegis:subagent-driven-development (recommended) or aegis:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Localize every player-visible TankFight message with English and Simplified Chinese SourceMod Phrase files.

**Architecture:** Keep TankFight logic unchanged. Load one plugin-owned Phrase catalog, route chat output through \`%t\`, and translate the ReadyUp footer label with the server language before appending the existing percentage list.

**Tech Stack:** SourcePawn, SourceMod translations, Colors, Python standard-library static contract test, repository \`spcomp\`.

**Baseline / Authority Refs:** \`docs/aegis/specs/2026-08-23-l4d-tankfight-localization-design.md\`; \`addons/sourcemod/scripting/l4d_tankfight.sp\`; \`addons/sourcemod/scripting/include/multicolors.inc\`; existing \`l4d_boss_vote\` English/Chinese Phrase files.

**Compatibility Boundary:** Preserve all TankFight gameplay behavior and function signatures. Keep console logs, comments, and ConVar descriptions unchanged. Broadcasts remain server-language output; per-client command replies remain player-language output.

**Verification:** \`python -m unittest tests/test_l4d_tankfight_localization.py -v\`; \`addons/sourcemod/scripting/sourcemod/spcomp.exe -i.\addons/sourcemod/scripting/include -i.\addons/sourcemod/scripting/sourcemod/include addons/sourcemod/scripting/l4d_tankfight.sp\`; static diff checks for untranslated player-visible calls; manual server-language checks remain residual risk.

---

### Task 1: Define the localization contract with a failing static test

**Files:**
- Create: \`tests/test_l4d_tankfight_localization.py\`
- Read: \`addons/sourcemod/scripting/l4d_tankfight.sp\`

**Why this task exists:** The user-visible feature needs a repeatable check that every Phrase key exists in both language catalogs and every player-facing call uses a loaded translation key.

**Impact / Compatibility:** This test is static and does not execute SourceMod. It must not require external packages or modify repository files.

**Verification:** Run \`python -m unittest tests/test_l4d_tankfight_localization.py -v\` before adding production Phrase files; it must fail because the catalogs and translation load/calls do not yet exist.

- [x] **Step 1: Write the failing test**

  Define the expected key set for all player-visible messages, parse top-level Phrase blocks and language entries, assert root \`en\` and \`chi\` catalogs have identical keys, assert the plugin loads \`l4d_tankfight.phrases\`, and assert every expected key is referenced by a \`%t\` call in the plugin.

- [x] **Step 2: Run test to verify it fails**

  Run:

  ~~~powershell
  python -m unittest tests/test_l4d_tankfight_localization.py -v
  ~~~

  Expected result: failure naming the missing \`addons/sourcemod/translations/l4d_tankfight.phrases.txt\` catalog or missing translation load, not a Python syntax/import error.

### Task 2: Add bilingual Phrase catalogs and wire all player-visible output

**Files:**
- Modify: \`addons/sourcemod/scripting/l4d_tankfight.sp:150-1523\` for \`LoadTranslations\` and all player-visible message call sites.
- Create: \`addons/sourcemod/translations/l4d_tankfight.phrases.txt\` with English entries.
- Create: \`addons/sourcemod/translations/chi/l4d_tankfight.phrases.txt\` with Simplified Chinese entries.

**Why this task exists:** This is the requested user-visible behavior: English clients/servers receive English text and Chinese clients/servers receive Chinese text through the existing SourceMod language mechanism.

**Impact / Compatibility:** Only message formatting and translation data change. All numeric arguments, color tokens, command behavior, timers, score logic, and ReadyUp footer list construction remain unchanged. The footer keeps its 65-character bound.

**Phrase key contract:** \`IntroTitle\`, \`IntroRule\`, \`IntroTeleport\`, \`IntroRounds\`, \`SavedPositions\`, \`PositionsReady\`, \`RoundEnded\`, \`NextRound\`, \`TankPosition\`, \`AllRoundsEnded\`, \`ScoreSeparator\`, \`SurvivorBonus\`, \`SpecialSpawnDelay\`, \`UnsupportedMap\`, \`NoDistanceScore\`, \`TankSpawned\`, \`AmmoRestored\`, \`ScorePerTank\`, \`PositionsNotReady\`, \`PositionsHeader\`, \`RoundCount\`, \`RoundFlow\`, \`RoundMissing\`, and \`TankFooter\`.

- [x] **Step 1: Add the English catalog**

  Create the root Phrase file with \`"en"\` entries and \`#format\` declarations matching every \`%d\`, \`%i\`, and \`%f\` argument.

- [x] **Step 2: Add the Simplified Chinese catalog**

  Create the \`chi\` overlay with exactly the same 24 keys and equivalent format placeholders, preserving Colors markers where the English catalog uses them.

- [x] **Step 3: Load the catalog during plugin startup**

  Add:

  ~~~sourcepawn
  LoadTranslations("l4d_tankfight.phrases");
  ~~~

  near the other \`OnPluginStart()\` initialization calls before any event can emit a localized message.

- [x] **Step 4: Convert broadcast and command messages**

  Replace literal chat strings with calls such as:

  ~~~sourcepawn
  CPrintToChatAll("%t", "IntroTitle");
  CPrintToChat(client, "%t", "ScorePerTank", scorePerTank);
  ~~~

  Preserve each existing argument and use \`CPrintToChatAll\` for the existing all-player path.

- [x] **Step 5: Convert the ReadyUp footer label**

  Before \`strcopy\` in \`GetTankPositionString\`, set the global translation target to \`LANG_SERVER\` and format the translated \`TankFooter\` phrase into \`msg\`; keep the existing percentage append and length checks unchanged.

### Task 3: Verify contract, compile, and inspect the final diff

**Files:**
- Read: \`tests/test_l4d_tankfight_localization.py\`
- Read: all three implementation files from Tasks 1–2.
- Create or update: \`docs/aegis/work/2026-08-23-l4d-tankfight-localization/50-evidence.md\`.

**Why this task exists:** SourceMod translation syntax errors can prevent plugin loading, while static tests alone cannot prove SourcePawn compilation.

**Impact / Compatibility:** Verification must confirm no unrelated source logic changed and no temporary files remain in the repository.

- [x] **Step 1: Run the static contract test after implementation**

  Run \`python -m unittest tests/test_l4d_tankfight_localization.py -v\`; expected result is zero failures.

- [x] **Step 2: Compile the plugin**

  Run:

  ~~~powershell
  & '.\addons\sourcemod\scripting\sourcemod\spcomp.exe' '-i.\addons/sourcemod/scripting/include' '-i.\addons/sourcemod/scripting/sourcemod/include' '.\addons\sourcemod\scripting\l4d_tankfight.sp'
  ~~~

  Expected result: exit code 0 and a generated \`l4d_tankfight.smx\` with no compiler errors. Remove only this generated artifact after verification if it is untracked and not an existing user file.

- [x] **Step 3: Inspect source and catalog invariants**

  Confirm the diff contains only the intended plugin, two Phrase catalogs, static test, and task evidence; confirm no \`CPrintToChat\`/\`PrintToChatAll\` player-visible call retains hardcoded Chinese or a literal message instead of \`%t\`.

- [x] **Step 4: Record bounded evidence and residual risk**

  Record exact commands, exit codes, and results in \`50-evidence.md\`. State that a live L4D2 server/client language switch was not available locally and remains the manual follow-up check.
