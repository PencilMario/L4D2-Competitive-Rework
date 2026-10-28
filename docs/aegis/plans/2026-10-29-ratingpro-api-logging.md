# RatingPro 后端排查日志（ELO 请求失败定位）

**现象：** `sm_ratingpro_apidebug` 里在线玩家显示 `状态=请求失败 ELO=0.00 排名=0/0 对局数=0`，
`!elo` 因此没有任何数据；服务器 error 日志里没有对应记录，看不出失败发生在哪一层。

**问题：** 三个失败分支（传输失败 / HTTP 非 200 / 响应体解析失败）此前都只把状态置成
`RatingProCache_Error`，没有留下 `failure`、`requestSuccessful`、`statusCode` 与响应体，
排查只能靠猜。上传路径有 `LogError`，读路径完全没有。

## 改动（`l4d2_round_ratingpro.sp`，版本 1.1.0 → 1.1.1）

- 新增独立 logger `g_ApiLogger`，固定写 `addons/sourcemod/logs/l4d2_ratingpro_api.log`。
  不复用 `g_RatingLogger`：后者被 `RecordRatingSettlement()` 改成每局一个文件名，混写会把
  网络记录冲散在结算明细里。
- 新增 `sm_ratingpro_api_log`（0/1/2，**默认 2**）：排查期默认把证据记全，确认稳定后再降到 1。
  - `0` 关闭；
  - `1` 只记请求失败、上传结果与会话头；
  - `2` 另外记每次请求的 URL、成功响应体与上传载荷。
- 新增 `ApiLog()` / `ApiLogBody()`：直接调 `Logger.WritetoLogFile()` 而不是 `error()`/`warning()`，
  避免后端长期不可达时每个玩家两条消息刷满服务器控制台；响应体按 400 字节分块写，
  否则 512 字节的单行上限会把后端返回的错误 JSON 截掉。
- 失败分支全部落日志：
  - 传输失败：`failure` / `requestSuccessful` / `status` / body 长度 + 常见原因提示；
  - HTTP 非 200：状态码 + body；
  - 解析失败：明确写“HTTP 200 但缺少 elo / average 字段”，并附完整 body；
  - `CreateHTTPRequest` / `SendHTTPRequest` 返回失败也各记一条；
  - 上传保留原有的“可重试 / 不可重试”判定并写进日志。
- `g_sClientApiError[client]` 保存每个玩家最近一次失败原因，`sm_ratingpro_apidebug` 直接打印
  `最近错误=...`，并多打一行日志级别与文件路径 —— 不开详细日志也能先看到失败层。
- 会话头放在 `OnConfigsExecuted()`：`AutoExecConfig` 在 `OnPluginStart` 之后才执行 cfg，
  否则日志里记的是默认 base / server_key。
- `Authorization` 头（含 api_key）不进日志；只记 URL 与载荷。

## 读日志

| 日志里看到 | 含义 | 下一步 |
| --- | --- | --- |
| `传输失败 … status=0` | 请求没到后端：服务器出站 DNS/防火墙、域名解析、TLS 握手 | 在服务器上确认能访问 `sm_ratingpro_api_base` |
| `返回 HTTP 4xx` | 后端拒绝：路径不存在、鉴权、参数格式 | 看附带的响应体 JSON |
| `返回 HTTP 5xx` / `429` | 后端故障或限流 | 重试，必要时看后端日志 |
| `HTTP 200 但缺少 elo 字段` | 后端返回结构变了 | 对照 `response` 体修正解析 |
| `发送请求失败（SteamWorks_SendHTTPRequest 返回 false）` | Steam 网络栈未初始化/被拒绝 | 检查 SteamWorks 扩展与 Steam 客户端 |
| `丢弃过期响应` | 玩家退服/换人，属正常 | 忽略 |

## 已排除的假设

- 后端没起：`GET /api/v1/health` 返回 200 `{"status":"healthy","version":"1.1.0"}`。
- 读接口要 api_key：未认证的 `GET /api/v1/players/STEAM_1%3A0%3A12345678/elo/current`
  返回 **404**（与实现的 404 → `RatingProCache_NoRecord` 分支一致），不是 401/403。

所以剩余可能集中在服务器出站网络、后端在读接口上的行为变化，或响应结构变化 ——
这三者恰好是本次日志能区分开的。

## 第一份日志（2026-10-29 01:58）的结论

```
[Debug] [GET elo] ... url=https://l4d2rating.0721play.icu/api/v1/players/STEAM_1%3A0%3A526095818/elo/current
[Error] [GET elo] Sir.P(STEAM_1:0:526095818) 返回 HTTP 200（期望 200），body=0 字节
```

- 排除「连不上后端」：传输层成功，`statusCode=200`。
- 排除「后端拒绝 / 路径错」：没有任何 4xx。
- 排除「后端不返回 body」：同一 URL 用 4 种客户端实测（含 `User-Agent: Valve/Steam HTTP Client 1.0`、
  `Accept-Encoding: gzip` 与 `identity`）都是 200 + 526 字节 JSON，且无 `Content-Encoding`。
- 剩下的唯一事实：**SteamWorks 这一侧把 200 响应的 body 读成了 0 字节**。

`ReadResponseBody()` 有两种失败方式（size 原生失败 / data 原生失败），1.1.1 的日志分不出来。
1.1.2 追加 `LogResponseBodyReadFailure()`：分别记录 `GetHTTPResponseBodySize` 的返回值与 size，
以及 `Content-Length` / `Content-Encoding` / `Transfer-Encoding` / `Server` / `Content-Type`
五个响应头。响应头能读到 → 响应对象完好、只有 body 丢了；全都读不到 → 扩展侧根本没拿到响应体。

## 第二轮日志（2026-10-29 02:14）→ 根因

```
[http] GetHTTPResponseBodyData 读取失败：size=526，目标缓冲=32768
[GET elo] ... 返回 HTTP 200（期望 200），body=0 字节
```

size 正确（526 / 817），响应对象完好，**失败的只有 `GetHTTPResponseBodyData` 这一层**，
而它唯一的可疑入参就是缓冲区长度：插件一直传 `length + 1`。

Valve 的 `ISteamHTTP::GetHTTPResponseBodyData(hRequest, pBodyData, unBufferLen)` 把
`unBufferLen` 当“**缓冲区长度**”用，部分 Steam 客户端实现要求它与 body 大小完全一致，
多 1 字节留 null 结尾会被判成缓冲不匹配并返回 false。本仓库能正常读到 body 的
`sm_translator.sp` 传的正是精确大小（`iBufferSize`）。

**修复（1.1.3）：** 先按精确大小读，失败才退回 `length + 1`（兼容只认大缓冲的客户端），
两者都失败才记 Error。`buffer[length] = '\0'` 由插件自己补，不依赖 Valve 写终止符。

**影响面：** `ReadResponseBody()` 被 ELO、rating/average、上传响应三处共用，所以这个 bug
同时让上传响应体永远读不到 —— 上传的 HTTP 200 判定照旧，但 `duplicate` 与
`ApplyUploadResults()` 一直拿到空 body，后端回传的 `elo_before/elo_after` 从未生效。

## 验证

- `spcomp`（1.12.0.7221）编译通过：1.1.1 为 Code 130292 / Data 183760；1.1.2 为 Code 131744 / Data 184228；
  1.1.3 为 Code 131940 / Data 184320 / Stack-heap 19380。
- `python -m pytest tests -q` → 128 passed（`tests/test_l4d2_round_ratingpro_api_log.py` 14 条源码契约测试）。
- 未在真实 srcds 上加载验证：本机没有运行中的服务器，运行时日志内容待部署后确认。
