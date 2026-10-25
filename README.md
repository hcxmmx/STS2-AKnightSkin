# STS2-AKnightSkin

《杀戮尖塔 2》未锈铠外观模组，将《重返未来：1999》未锈铠的洞悉衣着「加百列的圣勋」适配为铁甲战士外观。个人兴趣项目，非官方制作。

包含战斗动作与特效、英文配音、完整／节奏模式、五页选人档案、模组设置、休息处与商店待机，以及头像和地图标记。仅调整表现，不修改卡牌、数值、伤害、随机数或结算。

当前版本 **0.5.14**：修复对战瀑布巨兽时，单体／群攻期间双方消失、待机后恢复的问题；完整与节奏模式均已通过实机验收，保留全部攻击特效与原有玩法。保留 Skin Changer 1.0.19 兼容，不增加前置依赖；PCK 约 169 MB。目前仅适用于游戏测试分支（beta），验收版本 v0.111.0；开发使用 Godot 4.5.1、.NET 9。联机续档背景未进行双客户端实测。

本仓库用于源码备份。自有代码与文档采用 [MIT](LICENSE)；原作素材、字体、演出数据及由客户端着色器转换的资源另有权利归属，不包含在 MIT 授权中，源码目录仅保存其清单与哈希。Release 运行包包含实际使用的资源及声明。详见 [资源与许可范围](docs/ASSET_SCOPE.md)、[引用与致谢](ATTRIBUTION.md)。

创意工坊：[未锈铠 · 铁甲战士外观](https://steamcommunity.com/sharedfiles/filedetails/?id=3825224241)。

直接下载：[GitHub Releases](https://github.com/hcxmmx/STS2-AKnightSkin/releases/latest)。解压后将 `AKnightSkin` 文件夹放入游戏 `mods/` 并启用；与工坊版选择一种安装方式。

## 本地构建

需要自己的游戏安装、Godot 4.5.1、.NET 9 SDK，以及本机已安装的同版本模组 PCK 或制作工程素材。构建仅恢复本地素材并校验哈希，不提供额外的资源授权。

```powershell
# 从本机 mods/AKnightSkin/AKnightSkin.pck 恢复所需素材
.\build.ps1 -GameDir 'D:\SteamLibrary\steamapps\common\Slay the Spire 2' `
  -Godot 'D:\Tools\Godot_v4.5.1-stable_win64_console.exe'

# 也可增加 -AssetRoot 'D:\MyAKnightProject\Godot'，从制作工程恢复素材
```

输出为 `dist/AKnightSkin/`，不会自动安装。将构建生成的 `AKnightSkin` 文件夹复制到游戏 `mods/` 后启用；设置入口在游戏模组详情页及选人档案的「启程」页，F8 切换普通演出模式。

`Bridge/` 为 C# 接入；`Godot/AKnight_Hcxmmx/` 为本版本运行代码；`tools/` 为本地素材恢复与打包工具。`asset_manifest.json` 只记录素材路径、大小与 SHA-256，`runtime_files.json` 固定本版本打包范围。原始解包数据、开发扩展、游戏 DLL 和本地研究记录均不上传。
