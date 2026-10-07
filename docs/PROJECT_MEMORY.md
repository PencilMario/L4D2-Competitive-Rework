# Project Memory

## SourcePawn 编译方式

用于编译 `l4d2_round_ratingpro.sp` 的已确认命令：

```powershell
& 'E:\GithubKu\L4d2_0721sv_plugins\spcomp.exe' `
  'E:\GithubKu\L4D2-Competitive-Rework\addons\sourcemod\scripting\l4d2_round_ratingpro.sp' `
  -o'E:\GithubKu\L4D2-Competitive-Rework\addons\sourcemod\plugins\l4d2_round_ratingpro.smx' `
  -i'E:\GithubKu\L4D2-Competitive-Rework\addons\sourcemod\scripting\include' `
  -i'E:\GithubKu\L4D2-Competitive-Rework\addons\sourcemod\scripting' `
  -i'E:\GithubKu\L4D2-Competitive-Rework\addons\sourcemod\scripting\include' `
  -i'E:\GithubKu\L4D2-Not0721Here-CoopSvPlugins\addons\sourcemod\scripting\include'
```

编译器：SourcePawn Compiler `1.12.0.7221`。

用户提供的成功结果：

```text
Code size:         36660 bytes
Data size:         29340 bytes
Stack/heap size:      16976 bytes
Total requirements:   82976 bytes
Compilation successful.
```

以后修改该插件后，优先使用以上命令编译；实际编译结果以当前工作区命令输出为准。
