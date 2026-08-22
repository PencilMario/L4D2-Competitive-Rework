# TankFight 双语本地化设计

## 目标

为 \`l4d_tankfight.sp\` 的所有玩家可见消息增加 SourceMod 标准多语言支持，当前提供英文和简体中文两套文本，同时保持 TankFight 的游戏逻辑和控制台调试输出不变。

## 基线与事实

- 目标插件为 \`addons/sourcemod/scripting/l4d_tankfight.sp\`。
- 插件当前使用 \`<colors>\` 的 \`CPrintToChat\`/\`CPrintToChatAll\`，但没有加载自己的翻译文件。
- 仓库现有翻译约定是根目录 Phrase 文件提供 \`en\`，\`translations/chi/\` 提供 \`chi\`。
- \`CPrintToChat(client, ...)\` 会按玩家语言翻译；\`CPrintToChatAll(...)\` 使用服务器语言广播。
- 玩家可见文本包括聊天广播、\`sm_health\`/\`sm_tank\`/\`sm_witch\` 回复、特殊感染者复活提示，以及 ReadyUp 页脚的 \`Tank:\` 标签。

## 方案

新增 \`l4d_tankfight.phrases.txt\` Phrase 目录，并在 \`OnPluginStart()\` 调用 \`LoadTranslations("l4d_tankfight.phrases")\`。插件中的玩家可见字符串改为 \`%t\` 短语键；聊天颜色标记和格式参数保留在 Phrase 文本中。ReadyUp 页脚通过 \`LANG_SERVER\` 翻译短标签后，再拼接已有的流程百分比列表。

英文基准文件位于 \`addons/sourcemod/translations/l4d_tankfight.phrases.txt\`，中文文件位于 \`addons/sourcemod/translations/chi/l4d_tankfight.phrases.txt\`。两份文件必须拥有相同的短语键集合和相同的格式参数。

## 方案取舍

1. 采用 SourceMod Phrase 文件（选定）：复用仓库既有语言加载机制，英文可作为缺失语言的基准，改动只集中在消息层。
2. 在源码中根据语言条件拼接中英文：无需额外文件，但会把翻译内容和语言分支耦合进游戏逻辑，难以维护。
3. 为每个玩家手动循环广播：可支持同一服务器内不同玩家看到不同语言，但会扩大广播路径改动，偏离现有 \`CPrintToChatAll\` 约定。

## 兼容性边界与非目标

- 不修改 Tank 位置生成、轮次、计分、补给或 ReadyUp 行为。
- 不翻译控制台调试日志、源码注释或 ConVar 描述。
- 广播消息继续遵循服务器语言；个人指令回复继续遵循玩家语言。
- 不新增语言设置命令或持久化配置。

## 验收与验证

- Phrase 文件包含完整且一致的中英短语键集合。
- 玩家可见聊天调用全部使用 \`%t\` 翻译键，不再直接嵌入中文文本。
- \`spcomp\` 能在仓库现有 include 环境下编译 \`l4d_tankfight.sp\`。
- 静态测试覆盖 Phrase 文件存在、语言覆盖、键集合一致、插件加载翻译及调用键一致。

## 风险

本地环境无法启动实际 L4D2 服务器，因此无法在真实客户端上切换语言并观察聊天窗口；最终仍需在服务器上分别使用英文和简体中文语言设置验证广播、指令回复及 ReadyUp 页脚显示。
