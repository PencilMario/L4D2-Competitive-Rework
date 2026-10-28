"""mt_elo / mt_rating 分队插件的契约测试。

SourcePawn 没有可用的单测运行时，这里沿用本仓库其他插件测试的做法：
直接对源码做结构化断言，锁住「哪些行为必须存在」，而不是断言实现细节。
重点覆盖三件容易回归错的事：

1. 分队算法只在一处（include/mt_balance.inc），两个插件不许各自复制一份；
2. 缺数据 / 落位失败必须走 Call_AbortMix + Plugin_Handled（mix_team 的约定）；
3. 源码里用到的每个翻译键都必须在中英文翻译文件里存在。
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTING = ROOT / "addons" / "sourcemod" / "scripting"
TRANSLATIONS = ROOT / "addons" / "sourcemod" / "translations"

BALANCE_INCLUDE = SCRIPTING / "include" / "mt_balance.inc"

PLUGINS = {
    "mt_elo.sp": {
        "mix_type": "elo",
        "metric": "RatingPro_GetClientEloValue",
        "decimals": "0",
        "phrases": "mt_elo.phrases.txt",
    },
    "mt_rating.sp": {
        "mix_type": "rating",
        "metric": "RatingPro_GetClientRecentRating",
        "decimals": "2",
        "phrases": "mt_rating.phrases.txt",
    },
}


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


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


def used_phrase_keys(source: str) -> set:
    """Collect every translation key the plugin hands to %t / %T, plus the
    phrase names passed to MtBalancePrintTeam()."""
    keys = set(re.findall(r'"%[tT]"\s*,\s*"([A-Z0-9_]+)"', source))

    for first, more in re.findall(
        r'MtBalancePrintTeam\(\s*"([A-Z0-9_]+)"\s*,\s*"([A-Z0-9_]+)"', source
    ):
        keys.add(first)
        keys.add(more)

    return keys


def defined_phrase_keys(path: Path) -> set:
    return set(re.findall(r'^\t"([A-Za-z0-9_]+)"\s*$', read(path), re.MULTILINE))


class BalanceIncludeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = read(BALANCE_INCLUDE)

    def test_team_size_is_half_but_never_over_limit(self):
        body = extract_function(self.source, "stock int MtBalanceResolveTeamSize(")
        self.assertTrue(body, "MtBalanceResolveTeamSize must be defined")
        self.assertIn("count / 2", body, "每个队伍应当先按人数对半分配")
        self.assertIn("maxPerTeam", body, "每队人数不能超过 survivor_limit")

    def test_only_players_in_mix_and_humans_are_collected(self):
        body = extract_function(self.source, "stock int MtBalanceCollectMembers(")
        self.assertIn("IsClientInGame", body)
        self.assertIn("IsFakeClient", body)
        self.assertIn("IsMixMember", body)

    def test_normal_sizes_use_exact_partition(self):
        self.assertRegex(
            self.source,
            r"#define\s+MT_BALANCE_EXACT_MAX_TEAM_SIZE\s+(\d+)",
            "枚举上限必须显式定义",
        )
        limit = int(
            re.search(
                r"#define\s+MT_BALANCE_EXACT_MAX_TEAM_SIZE\s+(\d+)", self.source
            ).group(1)
        )
        self.assertGreaterEqual(limit, 5, "5v5 这种常见规模必须走精确枚举")

        body = extract_function(self.source, "stock void MtBalanceSplit(")
        self.assertIn("MtBalanceSplitExact", body, "常规规模必须走精确枚举")
        self.assertIn("MT_BALANCE_EXACT_MAX_TEAM_SIZE", body)
        self.assertIn(
            "MtBalanceImproveBySwap",
            body,
            "超出枚举范围时必须有贪心兜底，不能直接放弃平衡",
        )

    def test_exact_partition_enumerates_combinations(self):
        body = extract_function(
            self.source,
            "stock float MtBalanceSplitExact(const int[] sorted, int teamSize",
        )
        self.assertTrue(body, "MtBalanceSplitExact must be defined")
        self.assertIn("MtBalanceNextCombination", body)

        comb = extract_function(
            self.source, "stock bool MtBalanceNextCombination(int[] index"
        )
        self.assertIn(
            "count - size + i",
            comb,
            "组合枚举必须按字典序推进到最后一个组合后返回 false",
        )

    def test_both_teams_have_equal_size(self):
        body = extract_function(
            self.source,
            "stock float MtBalanceSplitExact(const int[] sorted, int teamSize",
        )
        self.assertIn("teamSize * 2", body, "只从 2 * teamSize 人里挑，保证两队人数相等")
        self.assertIn("iTeamA", body)
        self.assertIn("iTeamB", body)

    def test_survivors_are_placed_last(self):
        body = extract_function(
            self.source,
            "stock bool MtBalanceApply(const int[] teamA, int sizeA",
        )
        self.assertTrue(body, "MtBalanceApply must be defined")
        self.assertIn(
            "teamAId == TEAM_SURVIVOR",
            body,
            "生还者要靠接管 bot 落位，必须放在最后处理",
        )

    def test_roster_announcement_is_chunked(self):
        body = extract_function(
            self.source, "stock void MtBalancePrintTeam(const char[] firstPhrase"
        )
        self.assertIn("MT_BALANCE_ROSTER_CHUNK", body, "名册太长必须拆成多条消息")
        self.assertIn("MtBalancePrintRoster", body)

        printer = extract_function(
            self.source, "stock void MtBalancePrintRoster(const char[] sPhrase"
        )
        self.assertIn(
            "CPrintToChatAll",
            printer,
            "名册播报必须走 %t 翻译，不能把中文写死在代码里",
        )

    def test_no_dynamic_array_allocation(self):
        # SourcePawn 里 new int[变量] 是堆分配且不会自动释放，逐次调用会泄漏
        self.assertNotRegex(
            self.source,
            r"new\s+int\s*\[\s*[A-Za-z_][A-Za-z0-9_]*\s*\]",
            "不要用变长 new int[...]，改用定长数组避免泄漏",
        )


class SplitPluginContractTests(unittest.TestCase):
    def test_each_plugin_registers_its_own_mix_type(self):
        for filename, info in PLUGINS.items():
            with self.subTest(plugin=filename):
                source = read(SCRIPTING / filename)
                self.assertIn(
                    f'#define MIX_TYPE                "{info["mix_type"]}"',
                    source,
                    f"{filename} 必须注册自己的 mix 类型名",
                )
                self.assertIn("AddMix(MIX_TYPE", source)

    def test_mix_type_names_are_unique(self):
        names = [info["mix_type"] for info in PLUGINS.values()]
        self.assertEqual(len(names), len(set(names)), "两个插件的 mix 类型不能重名")

    def test_plugins_reuse_the_shared_balance_include(self):
        for filename in PLUGINS:
            with self.subTest(plugin=filename):
                source = read(SCRIPTING / filename)
                self.assertIn(
                    '#include "include/mt_balance.inc"',
                    source,
                    "分队算法必须复用 include/mt_balance.inc，不能在插件里再写一份",
                )
                # 插件本身不应该再出现分队算法的主体（精确枚举 / 交换优化）
                self.assertNotIn("MtBalanceNextCombination", source)
                self.assertNotIn("MtBalanceExact", source)

    def test_plugins_read_ratingpro_data_and_gate_on_it(self):
        for filename, info in PLUGINS.items():
            with self.subTest(plugin=filename):
                source = read(SCRIPTING / filename)
                self.assertIn("RatingPro_IsClientDataReady", source)
                self.assertIn(info["metric"], source)
                self.assertIn('LibraryExists(LIB_RATINGPRO)', source)
                self.assertIn(
                    f'MarkNativeAsOptional("{info["metric"]}")',
                    source,
                    "依赖后端插件时 native 必须标记为可选，否则缺库时整个插件加载失败",
                )

    def test_missing_data_aborts_the_mix(self):
        for filename in PLUGINS:
            with self.subTest(plugin=filename):
                source = read(SCRIPTING / filename)
                body = extract_function(source, "public Action OnMixInProgress()")
                self.assertTrue(body, f"{filename} 必须实现 OnMixInProgress")

                # 缺数据分支：先 Call_AbortMix()，再 return Plugin_Handled
                abort_at = body.find('Call_AbortMix();')
                self.assertNotEqual(abort_at, -1, "缺数据时必须取消 mix")

                after_abort = body[abort_at:]
                self.assertRegex(
                    after_abort[:200],
                    r"return\s+Plugin_Handled\s*;",
                    "取消 mix 后必须返回 Plugin_Handled，否则 mix_team 会立刻 FinishMix",
                )
                self.assertIn(
                    "require_data", source, "缺数据是否中止必须可配"
                )

    def test_success_path_returns_plugin_continue(self):
        for filename in PLUGINS:
            with self.subTest(plugin=filename):
                source = read(SCRIPTING / filename)
                body = extract_function(source, "public Action OnMixInProgress()")
                self.assertRegex(
                    body, r"return\s+Plugin_Continue\s*;\s*\}\s*$",
                    "分队完成后要返回 Plugin_Continue 交回 mix_team",
                )

    def test_plugins_declare_a_decimal_precision(self):
        for filename, info in PLUGINS.items():
            with self.subTest(plugin=filename):
                source = read(SCRIPTING / filename)
                self.assertRegex(
                    source,
                    r"MtBalancePrintTeam\([^;]*,\s*" + info["decimals"] + r"\)\s*;",
                    "播报小数位数要和分数口径一致（ELO 取整 / RatingPro 两位）",
                )

    def test_plugins_execute_their_own_config_files(self):
        # sourcemod 只自动执行调用了 AutoExecConfig 的插件配置；缺这一句时
        # cfg/sourcemod/<plugin>.cfg 完全不生效（改文件也不会有任何反应）。
        for filename in PLUGINS:
            with self.subTest(plugin=filename):
                stem = filename.removesuffix(".sp")
                source = read(SCRIPTING / filename)
                body = extract_function(source, "public void OnPluginStart()")
                self.assertIn(f'AutoExecConfig(true, "{stem}");', body)
                self.assertLess(
                    body.index("CreateConVar("),
                    body.index("AutoExecConfig("),
                    "配置文件必须在 ConVar 创建之后执行",
                )
                self.assertTrue((ROOT / "cfg" / "sourcemod" / f"{stem}.cfg").exists())

    def test_vote_hooks_are_exposed_for_mix_team(self):
        for filename in PLUGINS:
            with self.subTest(plugin=filename):
                source = read(SCRIPTING / filename)
                self.assertIn(
                    "public void GetVoteDisplayMessage(int iClient, char[] sTitle)",
                    source,
                )
                self.assertIn(
                    "public void GetVoteEndMessage(int iClient, char[] sMsg)", source
                )
                self.assertIn("public Action OnMixInProgress()", source)


class PhraseCoverageTests(unittest.TestCase):
    def test_every_used_phrase_is_translated(self):
        for filename, info in PLUGINS.items():
            with self.subTest(plugin=filename):
                keys = used_phrase_keys(read(SCRIPTING / filename))
                self.assertTrue(keys, "必须能从源码里解析出翻译键")

                for path in (
                    TRANSLATIONS / info["phrases"],
                    TRANSLATIONS / "chi" / info["phrases"],
                ):
                    with self.subTest(locale=path.parent.name):
                        self.assertTrue(path.is_file(), f"缺少翻译文件 {path}")
                        missing = keys - defined_phrase_keys(path)
                        self.assertFalse(
                            missing, f"{path.name} 缺少翻译键: {sorted(missing)}"
                        )

    def test_translation_locales_cover_the_same_keys(self):
        for info in PLUGINS.values():
            english = defined_phrase_keys(TRANSLATIONS / info["phrases"])
            chinese = defined_phrase_keys(TRANSLATIONS / "chi" / info["phrases"])
            self.assertEqual(
                english, chinese, "en 与 chi 的翻译键必须一一对应"
            )


class DeploymentTests(unittest.TestCase):
    def test_plugins_are_loaded_in_sharedplugins(self):
        cfg = read(ROOT / "cfg" / "sharedplugins.cfg")
        for filename in PLUGINS:
            smx = filename.replace(".sp", ".smx")
            with self.subTest(plugin=smx):
                self.assertIn(f"sm plugins load {smx}", cfg)

    def test_backend_plugin_is_loaded_before_the_split_plugins(self):
        cfg = read(ROOT / "cfg" / "sharedplugins.cfg")
        backend = cfg.find("sm plugins load optional/l4d2_round_ratingpro.smx")
        self.assertNotEqual(backend, -1, "分队插件依赖后端插件，后端必须被加载")
        for filename in PLUGINS:
            self.assertGreater(
                cfg.find("sm plugins load " + filename.replace(".sp", ".smx")),
                backend,
                "分队插件必须排在后端插件之后加载",
            )


if __name__ == "__main__":
    unittest.main()
