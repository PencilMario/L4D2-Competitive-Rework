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

## 分队插件（mt_elo / mt_rating）

两个插件共用 `addons/sourcemod/scripting/include/mt_balance.inc`（分队算法，不单独编译），
编译命令与 CI 一致（工作目录 `addons/sourcemod/scripting`，SourcePawn Compiler 1.12）：

```powershell
.\sourcemod\spcomp.exe mt_elo.sp    -i include -w234 -w217 -O2 -v2 -o compiled\mt_elo.smx
.\sourcemod\spcomp.exe mt_rating.sp -i include -w234 -w217 -O2 -v2 -o compiled\mt_rating.smx
```

编译产物需要复制到 `addons/sourcemod/plugins/`（发布工作流只会更新已存在的同名 `.smx`）。

改动后的验证：

```powershell
python -m pytest tests/test_mt_balance_plugins.py -q
```

