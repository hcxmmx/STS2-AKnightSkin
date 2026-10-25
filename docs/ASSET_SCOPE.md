# 资源与许可范围

根目录 [MIT License](../LICENSE) 仅适用于 Hcxmmx 可授权的代码与文档。源码与第三方资源分离保存；下表描述源码目录的内容。Release 附件是玩家运行包，其中实际使用的第三方资源仍保留原权利归属，不适用项目 MIT。

| 类别 | 来源及权利范围 | 本仓库 |
| --- | --- | --- |
| C# 桥接、GDScript、项目自编着色器、场景组织、速度曲线、构建脚本与文档 | Hcxmmx，自有部分采用 MIT；框架参考同作者 STS2-Sotheby | 保存代码 |
| 角色、衣着、立绘、小人、骨骼、动画、纹理、图标、剧情背景、档案界面美术 | 《重返未来：1999》，Bluepoch 及相应权利方；未取得可由本项目另行授予的开放许可 | 仅路径、大小和哈希 |
| 英文配音、角色音效、中英台词、档案文本、原始演出与布局配置 | 原作及相应权利方；解码、剪辑或变速不改变其权利归属 | 仅路径、大小和哈希 |
| 特效网格／粒子帧缓存、源材质参数、由客户端编译着色器转换的程序 | 原作素材的转换或衍生资源，不通过项目 MIT 重新授权 | 仅路径、大小和哈希 |
| 字体 | 字体权利方及其各自许可，见下文 | 仅路径、大小和哈希 |
| 游戏 DLL、GodotSharp、Harmony DLL、Spine runtime／开发扩展、解包与音频工具 | 各自权利方及相应许可 | 不分发 |
| 游戏原生场景、贴图、反编译源码 | Mega Crit 及相应权利方，仅供本地接口研究 | 不分发 |

## 字体文件

以下结论依据当前制作工程中实际字体文件的 `name` 表，不能直接套用其他版本的许可证。

- `AKnight_Hcxmmx/Archive/fonts/hwzs.ttf` 和开发工程的 `Assets/fonts/hwzs.ttf`：**STZhongsong／华文中宋**，内嵌 Changzhou SinoType Technology Co., Ltd.／常州华文印刷新技术有限公司版权声明。本项目不授予该字体的额外许可；源码目录不保存字体本体，运行包沿用已验收版本并附版权声明。
- `AKnight_Hcxmmx/Archive/fonts/subtitle_en.ttf`：**Source Han Sans CN Regular／思源黑体 CN Regular**，实际旧文件内嵌 Adobe Systems Incorporated 2014 版权声明与 **Apache License 2.0** 声明，许可文本见 [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)。源码目录不保存字体本体，运行包附该许可全文；不能用其他版本思源字体的 OFL 声明替代该文件自身的许可。

## 素材清单与恢复

`asset_manifest.json` 列出 **0.5.15 实际打包范围**中未随源码提交的资源。它不包含素材内容，不代表再分发授权。可从自己的同版本本地 PCK 或 Godot 制作目录恢复，并逐项核对 SHA-256。恢复文件、导入缓存与构建产物由 `.gitignore` 排除；`.fxc` 为原作特效网格的无损压缩容器，仍属于转换后的第三方素材，不适用项目 MIT。

原路径图片覆盖仅限以下五项，其导入设置保留游戏资源 UID；这些元数据不包含图片本体：

```text
images/packed/character_select/char_select_ironclad.png
images/packed/character_select/char_select_ironclad_locked.png
images/ui/top_panel/character_icon_ironclad.png
images/ui/top_panel/character_icon_ironclad_outline.png
images/packed/map/icons/map_marker_ironclad.png
```

其余资源使用 `res://AKnight_Hcxmmx/`。选人图来源为 `headskinicon_small/300702`，头像／地图为 `headicon_monster/300702`，多人续档背景为 `singlebg/storybg/story_atcg/1_7/1_7_at_weixiukaiyishi2`；均为原作资源的适配。
