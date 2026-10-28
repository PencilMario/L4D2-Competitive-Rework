from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "addons" / "sourcemod" / "scripting" / "l4d2_ratingpro_elo.sp"
CONFIG = ROOT / "cfg" / "sourcemod" / "l4d2_ratingpro_elo.cfg"


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


def strip_comments(source: str) -> str:
    """Drop // line comments and /* */ blocks so checks only see real code."""
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


class RatingProEloNotifyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")
        cls.code = strip_comments(cls.source)
        cls.config = CONFIG.read_text(encoding="utf-8-sig")

    def test_command_registered(self):
        self.assertRegex(
            self.source,
            r'RegConsoleCmd\(\s*"sm_elo"\s*,\s*Command_Elo\b',
            "sm_elo must be registered and bound to Command_Elo",
        )

    def test_forwards_match_include_signature(self):
        self.assertIn(
            "public void RatingPro_OnClientDataLoaded(int client, RatingProCacheStatus status)",
            self.source,
            "join notice must hook the RatingPro_OnClientDataLoaded forward",
        )
        self.assertIn(
            "public void RatingPro_OnClientEloUpdated(int client, float eloBefore, float eloAfter, float eloDelta)",
            self.source,
            "settlement notice must hook the RatingPro_OnClientEloUpdated forward",
        )

    def test_ratingpro_natives_are_marked_optional(self):
        """Missing l4d2_round_ratingpro must not fail plugin load."""
        called = set(re.findall(r"\b(RatingPro_[A-Za-z]+)\s*\(", self.code))
        natives = {name for name in called if not name.startswith("RatingPro_On")}
        self.assertTrue(natives, "expected the plugin to call RatingPro_* natives")

        optional = set(re.findall(r'MarkNativeAsOptional\(\s*"([^"]+)"\s*\)', self.code))
        missing = sorted(natives - optional)
        self.assertEqual(missing, [], f"natives called but not marked optional: {missing}")

    def test_no_conflicting_team_colors(self):
        """colors.inc throws when one message carries two team colors ({blue}/{red}/{lightgreen})."""
        self.assertIn('"{blue}[{green}RatingPro{blue}]{default}', self.code)
        self.assertNotIn("{red}", self.code, "never mix {red} with the {blue} prefix")
        self.assertNotIn("{lightgreen}", self.code, "never mix {lightgreen} with the {blue} prefix")

    def test_join_notice_is_gated(self):
        body = extract_function(self.source, "void PrintJoinNotice(int client)")
        self.assertTrue(body, "PrintJoinNotice must exist")
        self.assertIn("g_hNotify.BoolValue", body, "join notice must honour sm_ratingpro_elo_notify")
        self.assertIn("g_bNotified[client]", body, "join notice must not repeat itself")

    def test_join_notice_waits_for_cached_data(self):
        body = extract_function(self.source, "public void OnClientPostAdminCheck(int client)")
        self.assertIn("RatingPro_GetClientCacheStatus", body)
        self.assertIn("RatingPro_RefreshClientData", body, "must request data when auto cache is disabled")
        self.assertIn("ScheduleJoinNotice", body)

    def test_report_contains_elo_delta_and_recent_rating(self):
        body = extract_function(self.source, "bool BuildEloReport(int client, bool full, char lines")
        self.assertTrue(body, "BuildEloReport must exist")
        for call in (
            "RatingPro_GetClientElo(",
            "RatingPro_GetClientLastEloDelta(",
            "RatingPro_GetClientRecentRating(",
            "RatingPro_GetClientRecentRatingAt(",
        ):
            self.assertIn(call, body, f"ELO report must read {call}")

    def test_recent_per_match_list_only_in_full_report(self):
        body = extract_function(self.source, "bool BuildEloReport(int client, bool full, char lines")
        match = re.search(r"if \(full\)\s*\{[^}]*RatingPro_GetClientRecentRatingAt", body, re.S)
        self.assertIsNotNone(match, "per-match recent ratings must only be built for the !elo report")

    def test_command_is_not_rate_limited(self):
        """!elo reads the local cache, so it must answer every call."""
        body = extract_function(self.code, "public Action Command_Elo(int client, int args)")
        self.assertTrue(body, "Command_Elo must exist")
        for forbidden in ("COOLDOWN", "g_fLastQuery", "频繁"):
            self.assertNotIn(forbidden, body, f"!elo must not be rate limited ({forbidden})")

    def test_config_file_matches_registered_convars(self):
        created = set(re.findall(r'CreateConVar\(\s*"(sm_ratingpro_elo_[a-z_]+)"', self.source))
        self.assertTrue(created, "expected sm_ratingpro_elo_* convars")

        configured = set(re.findall(r'^(sm_ratingpro_elo_[a-z_]+)\s+"', self.config, re.M))
        self.assertEqual(sorted(created - configured), [], "convars missing from the shipped cfg")
        self.assertEqual(sorted(configured - created), [], "cfg entries without a convar")

    def test_config_is_autoloaded_from_expected_name(self):
        self.assertIn('AutoExecConfig(true, "l4d2_ratingpro_elo")', self.source)
        self.assertEqual(CONFIG.name, "l4d2_ratingpro_elo.cfg")


if __name__ == "__main__":
    unittest.main()
