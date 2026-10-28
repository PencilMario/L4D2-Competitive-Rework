from pathlib import Path
import re
import unittest

from test_l4d2_round_ratingpro_query import extract_function


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_SOURCE = ROOT / "addons" / "sourcemod" / "scripting" / "l4d2_round_ratingpro.sp"
INCLUDE_SOURCE = (
    ROOT / "addons" / "sourcemod" / "scripting" / "include" / "l4d2_round_ratingpro.inc"
)


class RatingProBackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plugin = SCRIPT_SOURCE.read_text(encoding="utf-8-sig")
        cls.api = INCLUDE_SOURCE.read_text(encoding="utf-8-sig")

    # ------------------------- 对外接口契约 -------------------------

    def test_every_declared_native_is_registered_and_implemented(self):
        declared = re.findall(r"^native\s+[\w\[\]]+\s+(RatingPro_\w+)\s*\(", self.api, re.M)
        self.assertTrue(declared, "l4d2_round_ratingpro.inc 必须声明 native")

        registered = dict(re.findall(r'CreateNative\("(\w+)",\s*(\w+)\)', self.plugin))

        missing = [name for name in declared if name not in registered]
        self.assertEqual(missing, [], "这些 native 声明了但没有 CreateNative 注册")

        for name in declared:
            handler = registered[name]
            self.assertIn(
                f"public any {handler}(Handle plugin, int numParams)",
                self.plugin,
                f"{name} 的处理函数 {handler} 缺失或签名不对",
            )

    def test_no_native_is_registered_without_a_declaration(self):
        declared = set(re.findall(r"^native\s+[\w\[\]]+\s+(RatingPro_\w+)\s*\(", self.api, re.M))
        registered = set(re.findall(r'CreateNative\("(\w+)"', self.plugin))
        self.assertEqual(registered - declared, set())

    def test_every_declared_forward_is_created(self):
        declared = re.findall(r"^forward\s+\w+\s+(RatingPro_\w+)\s*\(", self.api, re.M)
        self.assertTrue(declared)

        created = set(re.findall(r'CreateGlobalForward\("(\w+)"', self.plugin))
        for name in declared:
            self.assertIn(name, created, f"{name} 声明了但未 CreateGlobalForward")

    def test_plugin_executes_its_own_config_file(self):
        # sourcemod 只自动执行调用了 AutoExecConfig 的插件配置，缺这一句时
        # cfg/sourcemod/l4d2_round_ratingpro.cfg 不会被读取（API Key 也就读不到）。
        body = extract_function(self.plugin, "public void OnPluginStart()")
        self.assertIn('AutoExecConfig(true, "l4d2_round_ratingpro");', body)
        self.assertLess(
            body.index("CreateApiConVars();"),
            body.index("AutoExecConfig("),
            "配置文件必须在 ConVar 创建之后执行",
        )

    # ------------------------- 战役（章节序列）判定 -------------------------

    def test_campaign_break_only_resets_the_upload_counter(self):
        body = extract_function(self.plugin, "void UpdateCampaignProgress()")
        self.assertIn("IsCampaignBroken(hasScores, scoreA, scoreB)", body)
        self.assertIn("ResetCampaignProgress();", body)
        # 断章要换段序号，评分窗口里的槽位才能区分「同一段跨块」和「上一段残留」。
        self.assertIn("g_iCampaignSeqId++;", body)
        self.assertLess(body.index("ResetCampaignProgress();"), body.index("g_iCampaignSeqId++;"))

        # 断章只影响上传，不影响 !rating 的历史口径：评分窗口一律不因断章清空。
        self.assertNotIn("ResetCampaignWindow", self.plugin)
        self.assertNotIn("g_iRawHistoryCount", body)
        self.assertNotIn("g_iRawHistoryNextSlot", body)
        self.assertNotIn("g_hRawHistory", body)
        self.assertNotIn("g_hRawActionHistory", body)

        reset = extract_function(self.plugin, "void ResetCampaignProgress()")
        self.assertIn("g_iCampaignMaps = 0;", reset)
        for forbidden in (
            "g_iRawHistoryCount",
            "g_iRawHistoryNextSlot",
            "g_iRawHistorySeq",
            "g_hRawHistory",
            "g_hRawActionHistory",
            "g_sRawHistoryMap",
        ):
            self.assertNotIn(forbidden, reset, "断章不得清空评分窗口")

    def test_campaign_break_only_reads_the_scores(self):
        body = extract_function(
            self.plugin,
            "bool IsCampaignBroken(bool hasScores, int scoreA, int scoreB)",
        )

        # 仓库里有插件能把随机地图拼成章节序列：前缀会变、章节会跳，都不参与判定。
        self.assertNotIn("StrEqual", body)
        self.assertNotIn("g_sCampaignKey", body)
        self.assertNotIn("chapter", body)

        # 唯一判据：双方战役累计比分单调不减。
        self.assertIn("scoreA < g_iCampaignLastScoreA || scoreB < g_iCampaignLastScoreB", body)
        self.assertIn("g_bCampaignHasScoreBaseline", body)
        self.assertIn("g_hScoreGuard.BoolValue", body)

    def test_campaign_map_name_parsing_accepts_official_and_workshop_names(self):
        body = extract_function(
            self.plugin,
            "bool ParseCampaignProgress(const char[] map, char[] key, int keySize, int &chapter)",
        )
        self.assertIn("map[index] != 'm' && map[index] != 'M'", body)
        self.assertIn("nextCode < 48 || nextCode > 57", body)
        self.assertIn("prefixLength = index;", body)

    def test_settlement_runs_campaign_check_before_saving_the_slot(self):
        body = extract_function(self.plugin, "public Action Timer_PrintBestRating(Handle timer)")
        self.assertLess(
            body.index("UpdateCampaignProgress();"),
            body.index("SaveRoundRawHistory();"),
            "必须先判定对局连续性再写入原始分槽位",
        )

    def test_history_slot_carries_its_sequence_id(self):
        body = extract_function(self.plugin, "void SaveRoundRawHistory()")
        self.assertIn("g_iRawHistorySeq[slot] = g_iCampaignSeqId;", body)

    # ------------------------- 上传触发 -------------------------

    def test_upload_waits_for_a_full_campaign_of_maps(self):
        body = extract_function(self.plugin, "void MaybeUploadCampaign()")
        self.assertIn("if (!IsApiWritable())", body)
        self.assertIn("int requiredMaps = g_hUploadMaps.IntValue;", body)
        self.assertIn("g_iCampaignMaps < requiredMaps", body)

        # 跨段覆盖只提示不阻断：上传决策只看本段累计了多少张图。
        window = body[body.index("int foreignSlots = 0;"):body.index("BuildUploadPayload();")]
        self.assertIn("g_iRawHistorySeq[slot] != g_iCampaignSeqId", window)
        self.assertIn("g_iRawHistorySeq[slot] > 0", window)
        self.assertNotIn("StrEqual", window)
        self.assertNotIn("return;", window)

    def test_upload_resets_the_campaign_counter(self):
        body = extract_function(self.plugin, "void MaybeUploadCampaign()")
        self.assertIn("int settledMaps = g_iCampaignMaps;", body)

        # 交付后的归零必须发生在载荷构建之后、且先于「没有玩家」的早退：
        # 这样攒满只消费一次，成功 / 判重 / 彻底失败都不回补重传。
        handoff = body[body.index("BuildUploadPayload();"):]
        self.assertIn("g_iCampaignMaps = 0;", handoff)
        self.assertLess(
            handoff.index("g_iCampaignMaps = 0;"),
            handoff.index("if (g_iPendingUploadPlayerCount <= 0)"),
        )

        # 上一发还没结清时不许再攒一次，否则会覆盖仍在重试的载荷。
        self.assertIn("if (g_bUploadInFlight || g_bUploadPending)", body)
        self.assertLess(
            body.index("if (g_bUploadInFlight || g_bUploadPending)"),
            body.index("BuildUploadPayload();"),
        )

        # 「每战役只传一次」的标志已随归零机制一起移除，不再有第二份真相。
        self.assertNotIn("g_bCampaignUploaded", self.plugin)

    def test_upload_requires_minimum_player_count(self):
        self.assertIn('g_hMinPlayers = CreateConVar("sm_ratingpro_min_players", "8"', self.plugin)
        self.assertRegex(
            self.plugin,
            r'"sm_ratingpro_min_players", "8",[\s\S]*?true, 0\.0, true, float\(MAX_PARTICIPANTS\)\)',
        )

        body = extract_function(self.plugin, "void MaybeUploadCampaign()")
        gate_head = "if (minPlayers > 0 && g_iParticipantCount < minPlayers)"
        self.assertIn("int minPlayers = g_hMinPlayers.IntValue;", body)
        self.assertIn(gate_head, body)

        # 人数不足等于这一段没有效对局：直接丢弃、计数器归零，不留到下一局再传。
        gate = body[body.index(gate_head):]
        gate = gate[: gate.index("int settledMaps = g_iCampaignMaps;")]
        self.assertIn("g_iCampaignMaps = 0;", gate)
        self.assertIn("return;", gate)
        self.assertNotIn("BuildUploadPayload();", gate)

        # 上一发未结清时先别动计数器；人数门槛必须在攒数据 / 构建载荷之前判定。
        self.assertLess(
            body.index("if (g_bUploadInFlight || g_bUploadPending)"),
            body.index(gate_head),
        )
        self.assertLess(body.index(gate_head), body.index("int settledMaps = g_iCampaignMaps;"))
        self.assertLess(body.index(gate_head), body.index("BuildUploadPayload();"))

    def test_upload_is_triggered_once_per_settlement_path(self):
        body = extract_function(self.plugin, "public Action Timer_PrintBestRating(Handle timer)")
        self.assertEqual(body.count("MaybeUploadCampaign();"), 2)

    def test_upload_requires_an_api_key(self):
        body = extract_function(self.plugin, "bool IsApiWritable()")
        self.assertIn("g_hApiKey.GetString(apiKey, sizeof(apiKey));", body)
        self.assertIn("sm_ratingpro_api_key 未配置", body)

    # ------------------------- 载荷契约 -------------------------

    def test_payload_matches_backend_schema(self):
        body = extract_function(self.plugin, "void BuildUploadPayload()")
        for token in (
            '"{\\"schema_version\\":2,\\"stats_scope\\":\\"cumulative\\""',
            '\\"server\\":{\\"key\\"',
            '\\"snapshot\\":{\\"external_id\\"',
            '\\"snapshot_id\\":%d',
            '\\"maps\\":[',
            '\\"map_count\\":%d',
            '\\"settled_at\\"',
            '\\"mode\\":\\"versus\\"',
            '\\"players\\":[',
        ):
            self.assertIn(token, body, f"载荷缺少 {token}")

    def test_player_payload_matches_backend_schema(self):
        body = extract_function(
            self.plugin,
            "void AppendPlayerJson(int participant, RatingSnapshotEntry entry, int index)",
        )
        for key in (
            '\\"steam_id\\"',
            '\\"name\\"',
            '\\"team\\"',
            '\\"eligible\\"',
            '\\"recorded_slots\\"',
            '\\"tank_source\\"',
            '\\"rating\\"',
            '\\"raw\\"',
            '\\"normalized\\"',
            '\\"raw_scores\\"',
            '\\"survivor\\"',
            '\\"infected\\"',
            '\\"tank\\"',
        ):
            self.assertIn(key, body, f"players[] 缺少 {key}")

        for key in (
            "si_dmg",
            "ci_kill",
            "tank_dmg",
            "dmg_taken",
            "incaps",
            "deaths",
            "ff",
            "tankup_dmg",
            "tankup_kill",
            "skeet",
            "level",
            "pop",
            "tongue_cut",
            "crown",
            "booms",
            "death_charges",
            "became_tank",
            "dmg_upright",
            "punch",
            "rock",
            "hittable",
            "incap",
            "death",
        ):
            self.assertIn(key, body, f"行为计数缺少 {key}")

    def test_payload_never_exceeds_the_transport_buffer(self):
        body = extract_function(self.plugin, "void BuildUploadPayload()")
        self.assertIn("strlen(g_sUploadPayload) + 1024 >= sizeof(g_sUploadPayload)", body)

    def test_external_id_is_stable_across_retries(self):
        body = extract_function(self.plugin, "void BuildUploadPayload()")
        self.assertIn(
            'Format(g_sUploadExternalId, sizeof(g_sUploadExternalId), "%s|%s|%d|%s",',
            body,
        )

    # ------------------------- 网络层 -------------------------

    def test_requests_use_steamworks_and_the_documented_paths(self):
        self.assertIn("#include <SteamWorks>", self.plugin)
        self.assertNotIn("#include <ripext>", self.plugin)

        self.assertIn('#define API_UPLOAD_PATH "/api/v1/rounds"', self.plugin)
        self.assertIn('#define API_ELO_PATH "/api/v1/players/%s/elo/current"', self.plugin)
        self.assertIn(
            '#define API_RATING_AVERAGE_PATH "/api/v1/players/%s/rating/average?limit=%d"',
            self.plugin,
        )

        upload = extract_function(self.plugin, "void SendUploadRequest()")
        self.assertIn("SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, url)", upload)
        self.assertIn('SteamWorks_SetHTTPRequestHeaderValue(request, "Authorization", header);', upload)
        self.assertIn("SteamWorks_SetHTTPRequestRawPostBody", upload)

    def test_steamid_is_url_encoded_before_entering_the_path(self):
        body = extract_function(self.plugin, "void RequestClientApiData(int client)")
        self.assertIn("UrlEncode(auth, encoded, sizeof(encoded));", body)
        self.assertLess(
            body.index("UrlEncode("),
            body.index("RequestClientElo("),
            "必须先编码再拼 URL",
        )

    def test_stale_responses_are_dropped_after_slot_reuse(self):
        for handler in ("OnClientEloResponse", "OnClientRatingResponse"):
            body = extract_function(self.plugin, f"public void {handler}(")
            self.assertIn("token != g_iClientToken[client]", body, handler)

        for hook in ("public void OnClientDisconnect(int client)", "public void OnClientPutInServer(int client)"):
            body = extract_function(self.plugin, hook)
            self.assertIn("g_iClientToken[client]++;", body, hook)

    def test_client_cache_is_filled_after_steam_auth(self):
        body = extract_function(self.plugin, "public void OnClientPostAdminCheck(int client)")
        self.assertIn("RequestClientApiData(client);", body)
        self.assertIn("g_hAutoRefresh.BoolValue", body)

    def test_upload_retries_only_on_retryable_statuses(self):
        body = extract_function(
            self.plugin,
            "public void OnUploadCompleted(Handle request, bool failure, bool requestSuccessful, "
            "EHTTPStatusCode statusCode, any data1, any data2)",
        )
        self.assertIn("status == 429 || status >= 500", body)
        self.assertIn("ScheduleUploadRetry();", body)
        self.assertIn("bool success = transportOk && (status == 200 || status == 201);", body)

    def test_upload_forward_reports_status_and_player_count(self):
        body = extract_function(
            self.plugin, "void FireEloUploaded(int snapshotId, int httpStatus, bool success, int playerCount)"
        )
        self.assertIn("Call_StartForward(g_hFwdEloUploaded);", body)
        self.assertIn("Call_PushCell(playerCount);", body)

    # ------------------------- JSON 工具 -------------------------

    def test_json_scanner_handles_nested_containers(self):
        body = extract_function(self.plugin, "static int JsonSkipValue(const char[] json, int pos)")
        self.assertIn("depth++;", body)
        self.assertIn("depth--;", body)
        self.assertIn("if (depth == 0)", body)

    def test_json_path_lookup_walks_nested_objects(self):
        body = extract_function(
            self.plugin, "static bool JsonResolvePath(const char[] json, const char[] path, int &valuePos)"
        )
        self.assertIn("path[index] != '.'", body)
        self.assertIn("JsonFindMember(json, pos, segment, childPos)", body)

    def test_json_string_output_is_escaped(self):
        body = extract_function(self.plugin, "void JsonEscape(const char[] input, char[] output, int size)")
        self.assertIn("if (c == '\"' || c == '\\\\')", body)


if __name__ == "__main__":
    unittest.main()
