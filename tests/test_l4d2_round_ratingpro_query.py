from pathlib import Path
import re
import unittest


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "addons"
    / "sourcemod"
    / "scripting"
    / "l4d2_round_ratingpro.sp"
)


def extract_function(source: str, signature: str) -> str:
    """Extract a function body by counting braces starting from signature."""
    idx = source.find(signature)
    if idx == -1:
        return ""
    brace_open = source.find("{", idx)
    if brace_open == -1:
        return ""
    depth = 0
    i = brace_open
    while i < len(source):
        char = source[i]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[idx : i + 1]
        i += 1
    return source[idx:]


class RatingProQueryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")

    def test_commands_registered(self):
        source = self.source
        self.assertRegex(
            source,
            r'RegConsoleCmd\(\s*"sm_ratingpro"\s*,\s*Command_RatingPro\b',
            "sm_ratingpro must be registered as a console command bound to Command_RatingPro",
        )
        self.assertRegex(
            source,
            r'RegConsoleCmd\(\s*"sm_rating"\s*,\s*Command_RatingPro\b',
            "sm_rating must be registered as an alias bound to Command_RatingPro",
        )
        self.assertRegex(
            source,
            r'RegConsoleCmd\(\s*"sm_rt"\s*,\s*Command_RatingPro\b',
            "sm_rt must be registered as an alias bound to Command_RatingPro",
        )

    def test_command_ratingpro_implementation_contract(self):
        cmd_body = extract_function(self.source, "public Action Command_RatingPro(int client, int args)")
        self.assertTrue(cmd_body, "Command_RatingPro function must be defined")

        # Must not modify history, tank cache, reset stats, or recompute raw ranges
        self.assertNotIn("SaveLatestTankRaw", cmd_body)
        self.assertNotIn("SaveRoundRawHistory", cmd_body)
        self.assertNotIn("ResetRoundStats", cmd_body)
        self.assertNotIn("BuildRawRanges", cmd_body)

        # Must support empty args / @all for all online human players
        self.assertTrue(
            "@all" in cmd_body or 'StrEqual(arg, "@all"' in cmd_body,
            "Must handle @all to query all online humans",
        )

        # Target filtering and single-target resolution
        self.assertIn("ProcessTargetString", cmd_body)
        self.assertIn("COMMAND_FILTER_NO_BOTS", cmd_body)
        self.assertIn("COMMAND_FILTER_NO_MULTI", cmd_body)
        self.assertIn("COMMAND_FILTER_NO_IMMUNITY", cmd_body)
        self.assertIn("ReplyToTargetError", cmd_body)

        # Client 0 handling & feedback
        self.assertIn("client == 0", cmd_body)
        self.assertNotIn("CPrintToChatAll", cmd_body, "Command_RatingPro must not broadcast to chat")

        # Cooldown handling (exempting client 0)
        self.assertRegex(cmd_body, r"g_fLastQueryTime|g_fQueryCooldown", "Must include cooldown tracking")

    def test_print_rating_snapshot_to_console(self):
        func_body = extract_function(
            self.source,
            "void PrintRatingSnapshotToConsole(int requester, int targetClient",
        )
        if not func_body:
            # Also allow slightly varied signature as long as requester and target are present
            func_body = extract_function(self.source, "PrintRatingSnapshotToConsole(")
        self.assertTrue(func_body, "PrintRatingSnapshotToConsole function must be defined")

        # Must print to requester's console using PrintToConsole
        self.assertIn("PrintToConsole", func_body)
        self.assertNotIn("PrintToServer", func_body, "Should use PrintToConsole for the requester")
        self.assertNotIn("CPrintToChatAll", func_body)

        # Meta fields
        self.assertIn("userid", func_body.lower())
        self.assertIn("rating", func_body.lower())
        self.assertIn("raw", func_body.lower())

        # Survivor count fields
        survivor_fields = [
            "siDmg", "ciKill", "tankDmg", "dmgTaken", "incaps", "deaths",
            "ff", "tankupDmg", "tankupKill", "skeet", "level", "pop", "tongueCut", "crown"
        ]
        for field in survivor_fields:
            self.assertIn(field.lower(), func_body.lower(), f"Missing survivor field {field}")

        # Infected count fields
        infected_fields = [
            "dmg", "booms", "deathCharges", "tankDmgUpright", "punch",
            "rock", "hittable", "incap", "death"
        ]
        for field in infected_fields:
            self.assertIn(field.lower(), func_body.lower(), f"Missing infected field {field}")

        # Covers Tank source indication (current / history / no data)
        self.assertRegex(func_body, r"tankSource|Tank Source|Tank来源|tank.*source", re.IGNORECASE)

        # Covers unverified / no snapshot / not eligible status indication
        self.assertIn("N/A", func_body)

        # Covers score contributions (weighted raw contribution and raw components)
        self.assertIn("贡献", func_body)
        self.assertIn("0.30", func_body)
        self.assertIn("0.25", func_body)

    def test_snapshot_capture_lifecycle(self):
        source = self.source
        timer_body = extract_function(source, "public Action Timer_PrintBestRating(Handle timer)")
        self.assertTrue(timer_body, "Timer_PrintBestRating function must be defined")

        # Snapshot saving happens after SaveLatestTankRaw and SaveRoundRawHistory
        tank_pos = timer_body.find("SaveLatestTankRaw()")
        history_pos = timer_body.find("SaveRoundRawHistory()")
        self.assertNotEqual(tank_pos, -1)
        self.assertNotEqual(history_pos, -1)
        self.assertLess(tank_pos, history_pos)

        # Snapshot function or logic invoked after history
        self.assertIn("g_hLastRatingSnapshot", source)
        self.assertIn("AuthId_Steam2", source)

        # ResetRoundStats must NOT clear g_hLastRatingSnapshot
        reset_body = extract_function(source, "void ResetRoundStats()")
        self.assertNotIn("g_hLastRatingSnapshot.Clear()", reset_body)

        # Prompt online humans to use !rating to view details
        self.assertIn("!rating", timer_body)


if __name__ == "__main__":
    unittest.main()
