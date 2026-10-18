from pathlib import Path
import unittest

from test_l4d2_round_ratingpro_query import extract_function


SOURCE = Path(__file__).resolve().parents[1] / "addons/sourcemod/scripting/l4d2_round_ratingpro.sp"


class RatingProBileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")

    def test_engine_events_replace_aggregate_skill_forward(self):
        self.assertIn('HookEvent("player_now_it", Event_PlayerBiled, EventHookMode_Post)', self.source)
        self.assertIn('HookEvent("player_no_longer_it", Event_PlayerUnbiled, EventHookMode_Post)', self.source)
        self.assertNotIn("public void OnBoomerVomitLanded(", self.source)

    def test_all_sources_share_target_scoped_deduplication(self):
        body = extract_function(self.source, "public void Event_PlayerBiled(")
        self.assertIn('event.GetInt("userid")', body)
        self.assertIn('event.GetInt("attacker")', body)
        self.assertIn("GetClientTeam(victim) != TEAM_SURVIVOR", body)
        self.assertIn("g_bBiled[victim]", body)
        self.assertLess(body.index("g_bBiled[victim]"), body.index("g_bBiled[victim] = true"))
        self.assertLess(body.index("g_bBiled[victim] = true"), body.index("!g_hEnabled.BoolValue"))
        self.assertIn("!IsHumanClient(attacker)", body)
        self.assertIn("GetClientTeam(attacker) != TEAM_INFECTED", body)
        self.assertIn("RememberClient(attacker)", body)
        self.assertIn("g_iInfBooms[attacker]++;", body)
        self.assertNotIn('GetBool("exploded")', body)
        self.assertNotIn('GetBool("by_boomer")', body)
        self.assertNotIn("g_bBiled[attacker]", body)

    def test_expiry_and_lifecycle_reset_target_state(self):
        expiry = extract_function(self.source, "public void Event_PlayerUnbiled(")
        self.assertIn("g_bBiled[victim] = false", expiry)
        self.assertNotIn("g_hEnabled", expiry)
        for signature, index in (
            ("public void OnClientDisconnect(", "client"),
            ("public void Event_PlayerSpawn(", "client"),
            ("public void Event_PlayerDeath(", "victim"),
            ("void ResetRoundStats()", "client"),
            ("public void Event_RoundStart(", "client"),
        ):
            self.assertIn(f"g_bBiled[{index}] = false", extract_function(self.source, signature), signature)

    def test_takeover_preserves_active_bile(self):
        self.assertIn('HookEvent("player_bot_replace", Event_PlayerBotReplace, EventHookMode_Post)', self.source)
        for signature, assignment in (
            ("public void Event_BotPlayerReplace(", "g_bBiled[player] = g_bBiled[bot]"),
            ("public void Event_PlayerBotReplace(", "g_bBiled[bot] = g_bBiled[player]"),
        ):
            body = extract_function(self.source, signature)
            self.assertIn(assignment, body)

    def test_bile_has_single_counter_owner(self):
        self.assertEqual(self.source.count("g_iInfBooms[attacker]++;"), 1)
        self.assertNotIn("g_iInfBooms[boomer] += amount", self.source)
