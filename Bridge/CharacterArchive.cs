using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Helpers;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Nodes.Screens.CharacterSelect;
using MegaCrit.Sts2.Core.Saves;
namespace Hcxmmx.AKnightSkin;
internal static class CharacterArchive
{
    private const string NodeName = "AKnightArchive";
    private static PackedScene? _portrait;
    private static readonly HashSet<ulong> SoundNodes = new();
    internal static void Select(NCharacterSelectScreen screen, CharacterModel model)
    {
        if (Visuals.IsTarget(model)) AttachCover(screen, model);
    }
    internal static Control SelectHost(NCharacterSelectScreen screen)
    {
        // Follow the working Flandre skin: use the native cached container
        // reference and keep the game's existing selection controls intact.
        var bg = Traverse.Create(screen).Field("_bgContainer").GetValue<Control>();
        return bg?.GetParent<Control>() ?? screen;
    }

    private static void AttachCover(NCharacterSelectScreen screen, CharacterModel model)
    {
        try
        {
            var host = SelectHost(screen);
            var container = Traverse.Create(screen).Field("_bgContainer").GetValue<Control>() ?? host.GetNodeOrNull<Control>("AnimatedBg");
            if (container == null) throw new InvalidOperationException("AnimatedBg is missing from the current select screen.");
            GD.Print("[AKnightSkin] Cover host: sourceInside=" + screen.IsInsideTree() +
                ", hostInside=" + host.IsInsideTree() + ", background=" + container.Name);
            var node = host.GetNodeOrNull<Control>(NodeName);
            _portrait ??= ResourceLoader.Load<PackedScene>("res://AKnight_Hcxmmx/Archive/Portrait.tscn");
            if (_portrait == null) throw new InvalidOperationException("Portrait scene could not load.");
            if (node == null)
            {
                var warmer = screen.GetTree().GetFirstNodeInGroup("aknight_archive_warmup");
                node = warmer?.Call("acquire").AsGodotObject() as Control;
                node ??= _portrait.Instantiate<Control>();
                node.Name = NodeName;
                if (node.GetParent() != null) node.Reparent(host, false);
                else host.AddChild(node);
                node.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
                // Draw over both native backgrounds, below all native controls.
                host.MoveChild(node, container!.GetIndex() + 1);
                RegisterSoundNode(node);
                WireCoverControls(screen, host, node);
                warmer?.Call("watch", node);
            }
            if (!node.Call("is_ready").AsBool())
            {
                GD.PushWarning("[AKnightSkin] Portrait did not initialize on the live host.");
                node.QueueFree();
                return;
            }
            var relic = model.StartingRelics.FirstOrDefault();
            node.Call("configure", host, new Godot.Collections.Dictionary
            {
                ["hp"] = $"{model.StartingHp}/{model.StartingHp}", ["gold"] = model.StartingGold.ToString(),
                ["relic_title"] = relic?.Title.GetFormattedText() ?? "",
                ["relic_description"] = PlainText(relic?.DynamicDescription.GetFormattedText() ?? ""),
                ["relic_icon"] = relic is null ? default(Variant) : relic.Icon,
                ["ascension"] = Traverse.Create(screen).Field("_ascensionPanel").GetValue<NAscensionPanel>().Ascension,
                ["ascension_state"] = ReadAscension(screen)
            });
            UpdateSoundPolicy();
            GD.Print("[AKnightSkin] Archive cover and bilingual subtitles attached. selfVisible=" + node.Visible +
                ", treeVisible=" + node.IsVisibleInTree() + ", active=" + node.Get("active").AsBool());
        }
        catch (Exception ex) { GD.PushWarning("[AKnightSkin] Character select: " + ex); }
    }

    private static string PlainText(string value) => System.Text.RegularExpressions.Regex.Replace(value, @"\[[^\]]+\]", "");

    private static Godot.Collections.Dictionary ReadAscension(NCharacterSelectScreen screen)
    {
        var panel = Traverse.Create(screen).Field("_ascensionPanel").GetValue<NAscensionPanel>();
        int max = (int)(AccessTools.Field(typeof(NAscensionPanel), "_maxAscension").GetValue(panel) ?? 0);
        bool editable = (bool)(AccessTools.Field(typeof(NAscensionPanel), "_arrowsVisible").GetValue(panel) ?? false);
        return new Godot.Collections.Dictionary
        {
            ["level"] = panel.Ascension, ["max_level"] = max, ["editable"] = editable,
            ["title"] = PlainText(AscensionHelper.GetTitle(panel.Ascension).GetFormattedText()),
            ["description"] = PlainText(AscensionHelper.GetDescription(panel.Ascension).GetFormattedText())
        };
    }

    private static void WireCoverControls(NCharacterSelectScreen screen, Control host, Control cover)
    {
        var panel = Traverse.Create(screen).Field("_ascensionPanel").GetValue<NAscensionPanel>();
        void Refresh()
        {
            if (GodotObject.IsInstanceValid(cover) && !cover.IsQueuedForDeletion())
                cover.Call("update_ascension", ReadAscension(screen));
        }
        cover.Connect("ascension_requested", Callable.From<int>(direction =>
        {
            if (!cover.Visible || direction == 0) return;
            var state = ReadAscension(screen);
            if (!state["editable"].AsBool()) return;
            // Reuse the exact vanilla +/- handlers; native signals update the
            // lobby, preferences and multiplayer synchronization as before.
            AccessTools.Method(typeof(NAscensionPanel), direction < 0 ? "DecrementAscension" : "IncrementAscension").Invoke(panel, null);
            Refresh();
        }));
        cover.Connect("open_settings_requested", Callable.From(() => SkinSettings.Open(host)));
        var refresh = Callable.From(Refresh);
        panel.Connect(NAscensionPanel.SignalName.AscensionLevelChanged, refresh);
        cover.TreeExiting += () =>
        {
            if (GodotObject.IsInstanceValid(panel) && panel.IsConnected(NAscensionPanel.SignalName.AscensionLevelChanged, refresh))
                panel.Disconnect(NAscensionPanel.SignalName.AscensionLevelChanged, refresh);
        };
    }

    internal static void CloseSelect(NCharacterSelectScreen screen, string reason = "selection")
    {
        var node = SelectHost(screen).GetNodeOrNull<Control>(NodeName);
        if (node != null) GD.Print("[AKnightSkin] Cover close: " + reason + ", selfVisible=" + node.Visible);
        node?.Call("prepare_selection");
    }


    private static void RegisterSoundNode(Node node)
    {
        ulong id=node.GetInstanceId(); SoundNodes.Add(id);
        node.TreeExiting += () => SoundNodes.Remove(id);
    }
    internal static void UpdateSoundPolicy()
    {
        try {
            var save=SaveManager.Instance;
            float gain=Math.Clamp(save.SettingsSave.VolumeMaster*save.SettingsSave.VolumeSfx,0,1);
            foreach (var id in SoundNodes.ToArray())
                if (GodotObject.InstanceFromId(id) is Node node && GodotObject.IsInstanceValid(node)) node.Call("set_audio_policy",gain,save.PrefsSave.MuteInBackground);
                else SoundNodes.Remove(id);
        } catch (Exception ex) { GD.PushWarning("[AKnightSkin] Archive audio: "+ex.Message); }
    }
}
[HarmonyPatch(typeof(NCharacterSelectScreen), nameof(NCharacterSelectScreen.SelectCharacter))]
internal static class CharacterSelectPatch
{
    private static void Prefix(NCharacterSelectScreen __instance) => CharacterArchive.CloseSelect(__instance);
    private static void Postfix(NCharacterSelectScreen __instance, NCharacterSelectButton charSelectButton, CharacterModel characterModel)
    {
        if (!charSelectButton.IsLocked && !charSelectButton.IsRandom) CharacterArchive.Select(__instance,characterModel);
    }
}
[HarmonyPatch(typeof(NCharacterSelectScreen), nameof(NCharacterSelectScreen.OnSubmenuClosed))]
internal static class CharacterSelectClosedPatch
{
    private static void Prefix(NCharacterSelectScreen __instance) => CharacterArchive.CloseSelect(__instance);
}
