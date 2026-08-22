# TaskIntentDraft

## Requested outcome

为 \`addons/sourcemod/scripting/l4d_tankfight.sp\` 增加中英双语支持，覆盖全部玩家可见文本。

## In scope

- 加载 \`l4d_tankfight.phrases\`。
- 新增英文 Phrase 文件和 \`chi\` 简体中文 Phrase 文件。
- 将聊天广播、指令反馈、特殊提示和 ReadyUp 页脚标签改为翻译键。

## Non-goals

- 不改动游戏逻辑。
- 不翻译控制台调试日志、注释和 ConVar 描述。
- 不增加语言切换命令或配置项。

## Risk hints

- SourcePawn \`%t\` 参数顺序必须与 Phrase 文件格式参数一致。
- 广播使用服务器语言，个人回复使用玩家语言，这是现有 Colors/SourceMod 约定。
- 需要通过静态契约测试和 \`spcomp\` 编译；真实服务器语言切换仍需手工验证。
