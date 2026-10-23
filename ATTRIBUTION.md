# 引用与致谢

项目制作、演出与交互适配、整合及验收：**Hcxmmx**。使用 AI 辅助进行资源研究、代码编写与问题排查。

## 原作与复用

- **《重返未来：1999》／Reverse: 1999**：深蓝互动／Bluepoch 及相应权利方。未锈铠／A Knight、「加百列的圣勋」衣着、角色美术、Spine 骨骼动画、技能特效、英文配音、台词、档案资料与界面美术来自原作。素材研究基于本机安装的国际服客户端。
- **《杀戮尖塔 2》／Slay the Spire 2**：Mega Crit 及相应权利方。模组使用游戏已有的铁甲战士角色、卡牌与表现接口，不分发游戏程序集或原生场景、贴图、运行库。
- **[STS2-Sotheby](https://github.com/hcxmmx/STS2-Sotheby)**：同一作者的苏芙比模组，参考基准 0.6.7。复用／适配桥接、Spine 加载、档案交互、声音、设置、特效播放与预加载框架；自有代码沿用其 [MIT 许可](https://github.com/hcxmmx/STS2-Sotheby/blob/main/LICENSE)。
- **[St-Pavlov-Foundation/re1999-data](https://github.com/St-Pavlov-Foundation/re1999-data)**：角色资料、语音配置、Timeline 处理与条件羽毛逻辑的研究依据；使用固定快照 `44588969ffe317e7a4d84a5a8d2106e66137c052`。原始配置与 Lua 内容未提交本仓库。

## 工具与依赖

| 项目 | 用途与许可说明 |
| --- | --- |
| [Godot Engine](https://godotengine.org/) | 场景、GDScript、着色器、导入与打包；[MIT](https://godotengine.org/license/)，不捆绑引擎。 |
| [Harmony](https://github.com/pardeike/Harmony) | C# 表现事件钩子；[MIT](https://github.com/pardeike/Harmony/blob/master/LICENSE)，引用目标游戏已有 DLL，不捆绑。 |
| [Spine／Esoteric Software](https://esotericsoftware.com/) | 原作骨骼格式，游戏内调用已有运行支持；[独立运行库许可](https://esotericsoftware.com/spine-runtimes-license)。不分发 runtime、编辑器或开发扩展。 |
| [UnityPy](https://github.com/K0lb3/UnityPy) | 开发期本地 Unity 对象与依赖读取；[MIT](https://github.com/K0lb3/UnityPy/blob/master/LICENSE)，不捆绑。 |
| [wwiser](https://github.com/bnnm/wwiser) | 开发期分析 Wwise bank 的事件、媒体与播放关系；不捆绑，以原项目声明为准。 |
| [vgmstream](https://github.com/vgmstream/vgmstream) | 开发期将本地音频解码为 WAV；许可见原项目 [COPYING](https://github.com/vgmstream/vgmstream/blob/master/COPYING)，不捆绑工具及其依赖。 |

字体的实际文件身份及许可边界单列在 [资源与许可范围](docs/ASSET_SCOPE.md)。工具与资料的许可不等于原作游戏素材的使用或再分发授权；上述致谢也不表示原作或工具作者参与、认可本模组。
