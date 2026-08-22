# BaselineReadSetHint

## Read files and why

- \`addons/sourcemod/scripting/l4d_tankfight.sp\` — target plugin and all player-visible message call sites.
- \`addons/sourcemod/scripting/include/multicolors.inc\` — confirms \`CPrintToChat\` uses the client target while \`CPrintToChatAll\` uses \`LANG_SERVER\`.
- \`addons/sourcemod/translations/l4d_boss_vote.phrases.txt\` — repository root Phrase format.
- \`addons/sourcemod/translations/chi/l4d_boss_vote.phrases.txt\` — repository Simplified Chinese overlay convention.
- \`addons/sourcemod/scripting/l4d2_horde_equaliser.sp\` — existing \`LoadTranslation\`/\`%t\` usage pattern.
- \`docs/aegis/README.md\` and \`docs/aegis/INDEX.md\` — project process-record baseline.
- Recent history for \`l4d_tankfight.sp\` — confirms the plugin is actively maintained and the change should remain narrowly scoped.

## Facts, assumptions, unknowns

- Fact: the plugin currently has hardcoded Chinese player-facing messages and no own translation file.
- Fact: repository language directory is \`chi\`, not \`zho\`, for Simplified Chinese plugin overlays.
- Assumption: server-language broadcasts are acceptable because this matches the existing \`CPrintToChatAll\` implementation.
- Unknown: no automated SourcePawn runtime test harness exists; static checks plus compiler verification are the available local evidence.
