using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Combat;
using MegaCrit.Sts2.Core.Context;
using MegaCrit.Sts2.Core.Modding;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Nodes.Combat;
using MegaCrit.Sts2.Core.Rooms;
using MegaCrit.Sts2.Core.Saves;

namespace Hcxmmx.AKnightSkin;

[ModInitializer(nameof(Init))]
public static class Entry
{
    private static bool _initialized;
    public static void Init()
    {
        if (_initialized) return;
        new Harmony("hcxmmx.aknight.visuals").PatchAll(typeof(Entry).Assembly);
        CombatManager.Instance.CombatWon += OnCombatWon;
        if (Engine.GetMainLoop() is SceneTree tree)
        {
            var timer = new Godot.Timer { Name = "AKnightAudioPolicy", WaitTime = .5, Autostart = true, ProcessMode = Node.ProcessModeEnum.Always };
            timer.Timeout += Visuals.UpdateSoundPolicy;
            timer.Timeout += CharacterArchive.UpdateSoundPolicy;
            tree.Root.CallDeferred(Node.MethodName.AddChild, timer);
            var warmupScript = ResourceLoader.Load<GDScript>("res://AKnight_Hcxmmx/CombatWarmup.gd");
            if (warmupScript?.New().AsGodotObject() is Node warmup)
            {
                warmup.Name = "AKnightCombatWarmup";
                tree.Root.CallDeferred(Node.MethodName.AddChild, warmup);
            }
            var archiveScript = ResourceLoader.Load<GDScript>("res://AKnight_Hcxmmx/ArchiveWarmup.gd");
            if (archiveScript?.New().AsGodotObject() is Node archiveWarmup)
            {
                archiveWarmup.Name = "AKnightArchiveWarmup";
                tree.Root.CallDeferred(Node.MethodName.AddChild, archiveWarmup);
            }
        }
        _initialized = true;
        GD.Print("[AKnightSkin] Initialized v0.5.15; IRONCLAD combat visuals/audio; F8 full/rhythm; ultimate=PACTS_END; rest/merchant idle; SkinChanger target declaration; explicit attack screen copy; public/beta settings cleanup.");
    }

    private static void OnCombatWon(CombatRoom room)
    {
        foreach (ulong id in Visuals.Active.ToArray())
            if (GodotObject.InstanceFromId(id) is Node node && GodotObject.IsInstanceValid(node)) node.Call("request_victory");
            else Visuals.Active.Remove(id);
    }
}

internal static class Visuals
{
    // Skin Changer scans this declaration without running our initializer.
    // Keep the runtime predicate and the managed skin's ownership identical.
    internal const string TargetCharacterId = "IRONCLAD";
    internal const string NodeName = "AKnightSkin";
    internal static readonly HashSet<ulong> Active = new();
    private static PackedScene? _battle;
    internal static bool IsTarget(CharacterModel? model) => model?.Id.Entry.Equals(TargetCharacterId, StringComparison.OrdinalIgnoreCase) == true;
    internal static Node2D? Skin(NCreature creature) => IsTarget(creature.Entity?.Player?.Character) ? creature.Visuals?.GetNodeOrNull<Node2D>(NodeName) : null;

    internal static void Attach(NCreature creature)
    {
        if (!IsTarget(creature.Entity?.Player?.Character) || Skin(creature) != null) return;
        try
        {
            var visuals = creature.Visuals;
            var original = visuals?.GetNodeOrNull<Node2D>("%Visuals");
            if (visuals == null || original == null) return;
            _battle ??= ResourceLoader.Load<PackedScene>("res://AKnight_Hcxmmx/Battle.tscn");
            if (_battle == null) return;
            var node = _battle.Instantiate<Node2D>();
            node.Name = NodeName;
            visuals.AddChild(node);
            if (!node.Call("is_ready").AsBool() || !node.Call("configure", original, visuals.Bounds.Position, visuals.Bounds.Size, LocalContext.IsMe(creature.Entity)).AsBool())
            { node.QueueFree(); return; }
            ulong id = node.GetInstanceId();
            Active.Add(id);
            node.TreeExiting += () => Active.Remove(id);
            UpdateSoundPolicy();
            GD.Print("[AKnightSkin] Combat attached; local=" + LocalContext.IsMe(creature.Entity));
        }
        catch (Exception ex) { GD.PushWarning("[AKnightSkin] Attach: " + ex); }
    }

    internal static void Trigger(NCreature creature, string trigger)
    {
        var skin = Skin(creature);
        if (skin == null) return;
        skin.Call("_hide_original");
        skin.Call("handle_trigger", trigger);
    }

    internal static void UpdateSoundPolicy()
    {
        try
        {
            var save = SaveManager.Instance;
            float gain = Math.Clamp(save.SettingsSave.VolumeMaster * save.SettingsSave.VolumeSfx, 0, 1);
            foreach (ulong id in Active.ToArray())
                if (GodotObject.InstanceFromId(id) is Node node && GodotObject.IsInstanceValid(node)) node.Call("set_audio_policy", gain, save.PrefsSave.MuteInBackground);
                else Active.Remove(id);
        }
        catch (Exception ex) { GD.PushWarning("[AKnightSkin] Audio: " + ex.Message); }
    }
}

[HarmonyPatch(typeof(NCreature), nameof(NCreature._Ready))]
internal static class CreatureReadyPatch { private static void Postfix(NCreature __instance) => Visuals.Attach(__instance); }

[HarmonyPatch(typeof(NCreature), nameof(NCreature.SetAnimationTrigger))]
internal static class AnimationPatch { private static void Postfix(NCreature __instance, string trigger) => Visuals.Trigger(__instance, trigger); }
