using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Nodes.Screens.CharacterSelect;

namespace Hcxmmx.AKnightSkin;

// The native child name comes from the LOCAL saved character, for host/client.
[HarmonyPatch(typeof(NMultiplayerLoadGameScreen), "AfterMultiplayerStarted")]
internal static class MultiplayerResumeBackground
{
    private static Texture2D? _texture;

    private static void Postfix(NMultiplayerLoadGameScreen __instance)
    {
        try
        {
            var container = Traverse.Create(__instance).Field("_bgContainer").GetValue<Control>();
            var original = container?.GetNodeOrNull<Control>("IRONCLAD_bg");
            if (container == null || original == null) return;
            _texture ??= ResourceLoader.Load<Texture2D>("res://AKnight_Hcxmmx/Assets/ui/multiplayer_resume.png");
            if (_texture == null) return;
            const string name = "AKnightResumeBackground";
            if (container.GetNodeOrNull<TextureRect>(name) == null)
            {
                var background = new TextureRect
                {
                    Name = name,
                    Texture = _texture,
                    ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize,
                    StretchMode = TextureRect.StretchModeEnum.KeepAspectCovered,
                    MouseFilter = Control.MouseFilterEnum.Ignore,
                    FocusMode = Control.FocusModeEnum.None
                };
                container.AddChild(background);
                background.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
            }
            original.Hide();
        }
        catch (Exception ex) { GD.PushWarning("[AKnightSkin] Multiplayer resume background: " + ex.Message); }
    }
}
