# WAV音频兼容修复交接（2026-10-26）

适用于复用未锈铠／苏芙比框架的皮肤及其他运行时加载WAV的Godot模组。未锈铠0.5.16已按本文修正，并由用户通过本地实机验收。其他项目应各自修正、打包和验收，不直接复制未锈铠身份或整包。

## 症状与真正原因

与海克斯共用时，选择／刷新海克斯可能闪退，日志首先出现：

```text
System.TypeInitializationException: Godot.AudioStreamWav
NativeMethodBindNotFoundException: AudioStreamWAV.load_from_file
```

随后可能出现strong_gchandle／script_binding错误。报错发生在海克斯的GetSfxStream → ResourceLoader.Load<AudioStream>，并不代表海克斯就是触发源，也不意味着一定装错了GodotSharp版本。

独立官方Godot4.5.1 Mono最小复现确认：GD省略options调用`AudioStreamWAV.load_from_file(path)`，会让引擎共享默认Dictionary从空字典变成含8个null选项键的字典。Godot方法绑定的兼容哈希包含默认参数值，默认值变化后，随后首次初始化C# AudioStreamWav就无法匹配生成绑定的原哈希。

因此这是引擎缺陷，被我们的音频调用触发，后加载C# WAV的模组受到影响。是否触发也与加载顺序有关；“某次能运行”不能证明单参数调用安全。未锈铠未加载时仍可能由同架构的另一个皮肤触发，排查时必须考虑所有相关皮肤。

## 需要移植的修改

```gdscript
# 旧：可能污染共享默认参数
stream = AudioStreamWAV.load_from_file(path)

# 新：每次调用建立新的独立options
stream = AudioStreamWAV.load_from_file(path, {})
```

如使用load_from_buffer，同样显式传入每次新建的options。已有自定义选项应保留值，并确保传入独立字典，必要时`options.duplicate(true)`。不要用一个全局共享空字典替代，也不要改循环／压缩／采样选项来“修复”。

查找范围：战斗配音、技能音效、选人问候／语音、预加载、预览、动态嵌入的GD源码，以及独立音频兼容辅助模组。可运行：

```powershell
rg -n 'AudioStreamWAV\.load_from_(file|buffer)' '自己的制作工程'
```

先修真正源文件，再按该项目生成流程更新Runtime副本。未锈铠的`Runtime/CombatSfx.gd`来自`PreviewSfx.gd`，0.5.16使用`prepare_runtime.py --audio-scripts-only`同步，无需重新烘焙声音或特效。其他角色必须核对自己的生成关系。

未锈铠运行PCK实际只有四个脚本变化：`CombatAudio.gd`、`ArchiveWarmup.gd`、`Archive/Voice.gd`、`Runtime/CombatSfx.gd`，共7处运行时加载；预览源同步修正。音频文件、音量、播放节奏、动画、特效和游戏逻辑未变。

## 必要验证与部署

1. 构建和脚本编译通过；检查最终PCK里的调用，防止源码改了但包没更新。
2. 在全新独立引擎进程，先执行修复后的GD音频加载，再首次构造C# `new AudioStreamWav()`；确认成功。查看`ClassDB.class_get_method_list("AudioStreamWAV", true)`的load_from_file默认参数，加载前后均应为`[{}]`。
3. 在另一个全新进程执行旧单参数调用应复现同一绑定异常，作为定位对照；不要在已失败的进程里继续验证修复。C#调用应隔离到NoInlining方法中，避免类型初始化被提前到GD调用前。
4. 用实际包执行选人／战斗／预加载相关声音，确认声音正常且C# WAV后续仍可初始化；只改加载参数时，无需重烘焙声音或扩大全量视觉测试。
5. 由用户操作游戏实测海克斯选择／刷新及正常声音；测试时暂时移出其他仍未修正的同架构皮肤，否则会继续触发同一问题。

未锈铠本轮实际PCK检查覆盖17个战斗语音缓存、21个音效和30个档案音流；1202个打包文件中仅上述四脚本变化，全部素材字节一致。其最小实验源码及日志属于本项目研究产物，不需要装入任何玩家运行包。

## 旧绕行补丁的处理边界

过去给海克斯PlaySfx打前置补丁、把四个音效改由GD播放，只是绕过了受影响的C#入口，没有消除触发源；不能作为“与皮肤无关”的证明。旧HextechWavCompat及苏芙比内置绕行受固定版本哈希约束，新版不命中时不会生效。

优先修自己的WAV调用，不扩大旧哈希白名单、不改海克斯文件、不换游戏GodotSharp，也不把临时补丁塞入皮肤发布包。如另行维护独立补丁，它自身的GD WAV加载也应显式传options。是否移除旧补丁，需由其项目另行判断，不能本轮顺手改动。

官方源码依据：[WAV加载实现](https://github.com/godotengine/godot/blob/4.5/scene/resources/audio_stream_wav.cpp)、[MethodBind哈希](https://github.com/godotengine/godot/blob/4.5/core/object/method_bind.cpp)、[默认参数进入兼容哈希](https://github.com/godotengine/godot/blob/4.5/core/object/object.cpp#L184-L210)。本项目先前“纯海克斯问题／宿主DLL错配／没有未锈铠即可排除”的结论已撤回，以本文及0.5.16修复记录为准。
