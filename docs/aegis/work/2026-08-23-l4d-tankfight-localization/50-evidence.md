# Verification Evidence

## RED

Command:

    python -m unittest tests/test_l4d_tankfight_localization.py -v

Result: expected failure before implementation. All 3 tests failed for feature-related reasons: the English Phrase file was missing, the first hardcoded chat call was still present, and `LoadTranslations("l4d_tankfight.phrases")` was absent.

## GREEN and regression checks

Command:

    python -m unittest tests/test_l4d_tankfight_localization.py -v

Result: exit code 0; 3 tests passed.

Command:

    $source=Get-Content -LiteralPath 'addons\sourcemod\scripting\l4d_tankfight.sp' -Raw
    $bad=$source -split '\r?\n' | Where-Object { $_ -notmatch '^\s*//' -and $_ -match '\b(?:CPrintToChat|PrintToChat)(?:All)?\s*\(' -and $_ -notmatch '"%t"' }
    if($bad){ throw 'Found a player-visible chat call without %t' }

Result: no player-visible chat call without `%t`.

Command:

    git diff --check

Result: exit code 0; no whitespace errors.

## Compile

Command:

    & '.\addons\sourcemod\scripting\sourcemod\spcomp.exe' '-i.\addons\sourcemod\scripting\include' '-i.\addons\sourcemod\scripting\sourcemod\include' '.\addons\sourcemod\scripting\l4d_tankfight.sp'

Result: exit code 0. SourcePawn compiler produced no errors. It emitted one warning at the repository's `halflife.inc(655)` for deprecated `CreateDialog`; this warning is outside the changed plugin and translation files. The generated root-level `l4d_tankfight.smx` was removed after the check.

## Scope and residual risk

- Changed behavior is limited to Phrase loading and localized player-visible text.
- Console debug logs, comments, ConVar descriptions, timers, game logic, score calculations, and footer percentage assembly remain unchanged.
- The test runner's generated `tests/__pycache__` was removed; no generated test cache remains.
- A live L4D2 server/client was not available, so actual English/Chinese chat rendering and the ReadyUp footer language are not runtime-verified locally.
- Confidence: B — direct static contract evidence plus successful SourcePawn compilation, with bounded runtime-language residual risk.

## Evidence boundary

- Summary used: repository source, existing Phrase examples, static test output, compiler output, and final diff checks.
- Raw payload not loaded: no full server log or live client transcript was available.
- Authority note: this is verified evidence for the local change; live server deployment remains the runtime owner of final language rendering.
