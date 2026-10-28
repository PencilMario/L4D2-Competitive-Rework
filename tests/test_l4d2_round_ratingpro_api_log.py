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


class RatingProApiLogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")

    # ------------------------------ 日志载体 ------------------------------

    def test_dedicated_logger_and_file(self):
        """API 日志必须有自己的 logger，不能复用会被结算改名的那一个。"""
        self.assertIn(
            'new Logger(API_LOG_NAME, LoggerType_NewLogFile)', self.source
        )
        self.assertIn('#define API_LOG_NAME "l4d2_ratingpro_api"', self.source)

        start = extract_function(self.source, "public void OnPluginStart()")
        self.assertIn("g_ApiLogger = new Logger(API_LOG_NAME", start)
        self.assertIn(
            'g_RatingLogger = new Logger("ratingpro", LoggerType_NewLogFile)', start
        )

    def test_logger_is_not_repurposed_by_settlement(self):
        """结算只会改 g_RatingLogger 的文件名，g_ApiLogger 必须保持固定。"""
        settlement = extract_function(
            self.source, "void RecordRatingSettlement()"
        )
        self.assertIn("g_RatingLogger.SetLogName", settlement)
        self.assertNotIn("g_ApiLogger", settlement)

    def test_log_level_cvar(self):
        self.assertRegex(
            self.source,
            r'CreateConVar\(\s*"sm_ratingpro_api_log"\s*,\s*"2"',
            msg="默认 2（全量）：排查期先把证据记全",
        )
        body = extract_function(self.source, "void CreateApiConVars()")
        cvar = body.split('"sm_ratingpro_api_log"')[1]
        self.assertIn("true, 0.0, true, 2.0", cvar)

    # ------------------------------ 写日志的实现 ------------------------------

    def test_api_log_gates_on_cvar_and_chunks_bodies(self):
        body = extract_function(self.source, "void ApiLog(LogType level")
        self.assertIn("g_hApiLog.IntValue <= 0", body)
        self.assertIn("level == LogType_Debug && g_hApiLog.IntValue < 2", body)
        self.assertIn("VFormat(buffer, sizeof(buffer), fmt, 3)", body)
        # 直写文件，避免每条失败都刷服务器控制台
        self.assertIn("g_ApiLogger.WritetoLogFile(level, buffer)", body)
        self.assertNotIn("PrintToServer", body)
        self.assertNotIn(".error(", body)

        chunked = extract_function(self.source, "void ApiLogBody(")
        self.assertIn("API_LOG_BODY_CHUNK", chunked)
        self.assertIn("body[offset]", chunked)
        self.assertIn("offset < length", chunked)

    # ------------------------------ 失败分支必须落日志 ------------------------------

    def test_elo_callback_logs_every_failure_branch(self):
        body = extract_function(
            self.source,
            "public void OnClientEloResponse(Handle request, bool failure",
        )
        for expected in (
            "传输失败",
            "requestSuccessful",
            "返回 HTTP %d",
            "响应解析失败",
            "SetClientApiError",
            "ApiLogBody",
        ):
            self.assertIn(expected, body, f"ELO 回调缺少诊断信息: {expected}")
        # 传输失败必须给出可能原因，否则日志只是一句“失败了”
        self.assertIn("DNS", body)

    def test_rating_callback_logs_failures_and_parse_errors(self):
        body = extract_function(
            self.source,
            "public void OnClientRatingResponse(Handle request, bool failure",
        )
        for expected in (
            "传输失败",
            "返回 HTTP %d",
            "响应解析失败",
            "ApiLogBody",
        ):
            self.assertIn(expected, body)

    def test_send_failures_are_logged(self):
        for signature in (
            "void RequestClientElo(",
            "void RequestClientRecentRating(",
            "void SendUploadRequest()",
        ):
            body = extract_function(self.source, signature)
            self.assertIn("SteamWorks_SendHTTPRequest", body)
            self.assertIn("ApiLog(LogType_Error", body, f"{signature} 未记录发送失败")

    def test_upload_result_is_logged(self):
        body = extract_function(
            self.source,
            "public void OnUploadCompleted(Handle request, bool failure",
        )
        self.assertIn("可重试", body)
        self.assertIn("不可重试", body)
        self.assertIn("ApiLogBody", body)

    def test_body_read_failure_reports_native_results_and_headers(self):
        """HTTP 200 却读不到 body 时，必须分开记录 size 原生与响应头。"""
        details = extract_function(self.source, "void LogResponseBodyReadFailure(")
        for expected in (
            "GetHTTPResponseBodySize 返回=%d",
            "Content-Length",
            "Content-Encoding",
            "Transfer-Encoding",
            "Server",
            "Content-Type",
        ):
            self.assertIn(expected, details, f"body 读取失败缺证据: {expected}")

        reader = extract_function(self.source, "bool ReadResponseBody(")
        self.assertIn("bool sizeOk = SteamWorks_GetHTTPResponseBodySize", reader)
        self.assertIn("LogResponseBodyReadFailure(request, sizeOk, length)", reader)
        self.assertIn("两种 bufferLen 都失败", reader)

    def test_body_read_passes_exact_body_size(self):
        """Valve 要求 unBufferLen 与 body 大小一致，多传 1 字节会让读取直接失败。"""
        reader = extract_function(self.source, "bool ReadResponseBody(")
        self.assertIn("SteamWorks_GetHTTPResponseBodyData(request, buffer, length)", reader)
        # 先精确大小，失败后才退回 +1
        self.assertLess(
            reader.index("GetHTTPResponseBodyData(request, buffer, length)"),
            reader.index("GetHTTPResponseBodyData(request, buffer, length + 1)"),
        )
        # 精确读取后仍要自己补 null 结尾
        self.assertIn("buffer[length] = '\\0'", reader)

    def test_api_key_never_reaches_the_log(self):
        """Authorization 头里有 api_key，日志只能出现 url 与载荷。"""
        for line in self.source.splitlines():
            if "ApiLog" not in line:
                continue
            self.assertNotIn("apiKey", line)
            self.assertNotIn("header", line)

    # ------------------------------ 运维可见性 ------------------------------

    def test_apidebug_surfaces_log_path_and_last_error(self):
        body = extract_function(
            self.source, "public Action Command_ApiDebug(int client, int args)"
        )
        self.assertIn("API_LOG_NAME", body)
        self.assertIn("最近错误=", body)
        self.assertIn("g_sClientApiError", body)

    def test_session_banner_runs_after_cfg_is_executed(self):
        """OnPluginStart 里 cfg 还没执行，会话头必须放在 OnConfigsExecuted。"""
        banner = extract_function(self.source, "public void OnConfigsExecuted()")
        self.assertIn("会话开始", banner)
        self.assertIn("g_hApiBase.GetString", banner)

    def test_client_error_cache_is_reset(self):
        body = extract_function(self.source, "void ResetClientApiCache(int client)")
        self.assertIn("ClearClientApiError(client)", body)


if __name__ == "__main__":
    unittest.main()
