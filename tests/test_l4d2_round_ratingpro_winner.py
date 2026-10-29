"""胜负/比分上传链路的回归测试。

这三个东西以前一起缺失，且都是「静默失效」型故障：插件不报错、后端不报错，
只是永远拿不到 winner_team，于是所有人默认走表现 ELO。所以这里钉住的是
**契约形状**与**两个已知的时序陷阱**，而不是 ELO 的数值（数值在后端自测里）。

1. 逻辑队 A/B 的分数必须换算成 players[].team 的 2/3 口径才能上报。
2. 第一半场生还方的记录不能被后续一次读不到分清的调用抹掉。
3. 结算重试不能重复累加「本段已结算张数」，否则同一张图会被算成两张。
"""
from pathlib import Path
import unittest

from test_l4d2_round_ratingpro_query import extract_function


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "addons"
    / "sourcemod"
    / "scripting"
    / "l4d2_round_ratingpro.sp"
)


class RatingProWinnerUploadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")

    # ------------------------- 重试常量 -------------------------

    def test_retry_budget_is_bounded(self):
        self.assertRegex(self.source, r"#define\s+MAP_RESULT_RETRY_DELAY\s+[\d.]+")
        self.assertRegex(self.source, r"#define\s+MAP_RESULT_MAX_ATTEMPTS\s+\d+")

    # ------------------------- 第一半场映射 -------------------------

    def test_remember_first_half_never_clears_a_known_answer(self):
        """补读时机比 round_end 更晚，必须只补不清 —— 清掉就再也没机会了。"""
        body = extract_function(self.source, "void RememberFirstHalfSurvivorTeam()")
        self.assertTrue(body, "RememberFirstHalfSurvivorTeam 缺失")
        self.assertNotIn("g_iFirstHalfLogicalTeam = 0;", body)
        self.assertIn("scoreA >= 0 && scoreB < 0", body)
        self.assertIn("scoreB >= 0 && scoreA < 0", body)
        self.assertIn("g_iFirstHalfLogicalTeam = logicalTeam;", body)

    def test_late_remember_timer_only_fills_gaps(self):
        body = extract_function(self.source, "public Action Timer_RememberFirstHalfTeam(Handle timer)")
        self.assertTrue(body, "Timer_RememberFirstHalfTeam 缺失")
        self.assertIn("if (g_iFirstHalfLogicalTeam == 0)", body)

    # ------------------------- 逻辑队 → 2/3 换算 -------------------------

    def test_team_scores_are_converted_to_second_half_side_numbering(self):
        body = extract_function(self.source, "bool TryGetTeamScores(int &team2Score, int &team3Score)")
        self.assertTrue(body, "TryGetTeamScores 缺失")
        # 缺分数或缺映射都必须拒绝上报，不能拿 -1 或错位的值凑数
        self.assertIn("if (g_iMapScoreA < 0 || g_iMapScoreB < 0)", body)
        self.assertIn("if (g_iFirstHalfLogicalTeam != 1 && g_iFirstHalfLogicalTeam != 2)", body)
        # 第二半场生还方 = 第一半场的对面，比分按它换位
        self.assertIn("int secondHalfLogical = (g_iFirstHalfLogicalTeam == 1) ? 2 : 1;", body)

    # ------------------------- 胜负判定 -------------------------

    def test_resolve_map_winner_reports_whether_a_retry_helps(self):
        body = extract_function(self.source, "bool ResolveMapWinner()")
        self.assertTrue(body, "ResolveMapWinner 缺失或不再返回 bool")
        self.assertRegex(body, r"return false;")
        self.assertRegex(body, r"return true;")
        # 打平、映射未知、没有 native 都是终局答案：重试没有意义
        self.assertIn("scoreA == scoreB", body)

    def test_resolve_runs_before_campaign_progress(self):
        """重试会重新进 Timer_PrintBestRating，顺序错了同一张图会被计两次。"""
        body = extract_function(self.source, "public Action Timer_PrintBestRating(Handle timer)")
        self.assertTrue(body, "Timer_PrintBestRating 缺失")
        resolve_at = body.find("ResolveMapWinner()")
        progress_at = body.find("UpdateCampaignProgress()")
        self.assertNotEqual(resolve_at, -1)
        self.assertNotEqual(progress_at, -1)
        self.assertLess(resolve_at, progress_at, "ResolveMapWinner 必须在 UpdateCampaignProgress 之前")
        self.assertIn("CreateTimer(MAP_RESULT_RETRY_DELAY, Timer_PrintBestRating", body)

    def test_round_state_is_reset_per_map(self):
        body = extract_function(self.source, "void ResetRoundStats()")
        self.assertTrue(body, "ResetRoundStats 缺失")
        for assignment in (
            "g_iFirstHalfLogicalTeam = 0;",
            "g_iFirstHalfScoreA = -1;",
            "g_iFirstHalfScoreB = -1;",
            "g_iMapScoreA = -1;",
            "g_iMapScoreB = -1;",
            "g_iMapWinnerTeam = 0;",
            "g_iMapResultAttempts = 0;",
        ):
            self.assertIn(assignment, body, f"ResetRoundStats 漏了 {assignment}")

    # ------------------------- 上传载荷与日志 -------------------------

    def test_payload_carries_both_winner_and_scores(self):
        body = extract_function(self.source, "void BuildUploadPayload()")
        self.assertTrue(body, "BuildUploadPayload 缺失")
        self.assertIn('\\"winner_team\\":%d', body)
        self.assertIn('\\"team_scores\\":{\\"2\\":%d,\\"3\\":%d}', body)

    def test_settlement_log_line_is_machine_readable(self):
        body = extract_function(self.source, "void FormatScoreNote(char[] buffer, int size)")
        self.assertTrue(body, "FormatScoreNote 缺失")
        self.assertIn("team2=%d team3=%d", body)

    def test_agent_parse_pattern_matches_log_line(self):
        """日志与代理是一条链：插件的格式和代理的正则必须对得上。"""
        body = extract_function(self.source, "void PrintMapWinnerLine(int requester, bool logToFile)")
        self.assertIn("本图胜负:", body)
        # 代理的正则是 /本图胜负:.*?winner_team=(\d+)/，两种胜方都要留出这个 token
        self.assertIn("winner_team=2", body)
        self.assertIn("winner_team=3", body)
        # 未判定时不能出现 winner_team=，否则代理会把「没判定」读成某队赢
        undetermined = next((line for line in body.splitlines() if "未判定" in line), "")
        self.assertIn("本图胜负:", undetermined)
        self.assertNotIn("winner_team=", undetermined)


if __name__ == "__main__":
    unittest.main()
