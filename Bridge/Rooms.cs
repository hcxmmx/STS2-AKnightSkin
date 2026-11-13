using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Entities.Players;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Nodes.Combat;
using MegaCrit.Sts2.Core.Nodes.Events.Custom;
using MegaCrit.Sts2.Core.Nodes.RestSite;
using MegaCrit.Sts2.Core.Nodes.Rooms;
using System.Reflection;
using System.Reflection.Emit;

namespace Hcxmmx.AKnightSkin;

internal static class IdleRooms
{
    private static PackedScene? _scene;
    private static void Attach(Node2D root, string kind)
    {
        if (root.GetNodeOrNull("AKnightIdle") != null) return;
        var originals = new Godot.Collections.Array<Node2D>();
        foreach (var child in root.GetChildren())
            if (child is Node2D node && node.GetClass() == "SpineSprite") originals.Add(node);
        if (originals.Count == 0) return;
        _scene ??= ResourceLoader.Load<PackedScene>("res://AKnight_Hcxmmx/RoomIdle.tscn");
        if (_scene == null) return;
        var idle = _scene.Instantiate<Node2D>();
        idle.Name = "AKnightIdle";
        root.AddChild(idle);
        // Keep native characters, animations, hitboxes and thought bubbles alive.
        // Hide only their drawing after the replacement's resources are ready.
        idle.CallDeferred("configure", originals, kind);
    }

    internal static void Merchant(NMerchantRoom room)
    {
        try
        {
            var players = AccessTools.Field(typeof(NMerchantRoom), "_players").GetValue(room) as IReadOnlyList<Player>;
            if (players == null || players.Count != room.PlayerVisuals.Count) return;
            for (int i = 0; i < players.Count; i++)
                if (Visuals.IsTarget(players[i].Character)) Attach(room.PlayerVisuals[i], "merchant");
        }
        catch (Exception ex) { GD.PushWarning("[AKnightSkin] Merchant idle: " + ex.Message); }
    }

    internal static void Rest(NRestSiteCharacter character)
    {
        try
        {
            if (Visuals.IsTarget(character.Player?.Character)) Attach(character, "rest");
        }
        catch (Exception ex) { GD.PushWarning("[AKnightSkin] Rest idle: " + ex.Message); }
    }

    internal static void FakeMerchant(NCreatureVisuals visuals)
    {
        try
        {
            if (!GodotObject.IsInstanceValid(visuals) || !visuals.IsInsideTree()) return;
            for (Node? parent = visuals.GetParent(); parent != null; parent = parent.GetParent())
                if (parent is NFakeMerchant) { Attach(visuals, "fake_merchant"); return; }
        }
        catch (Exception ex) { GD.PushWarning("[AKnightSkin] Fake merchant idle: " + ex.Message); }
    }
}

// Only observe the visuals created by this event. Keep the CharacterModel next
// to its own result instead of guessing ownership from reordered scene children.
[HarmonyPatch(typeof(NFakeMerchant), "AfterRoomIsLoaded")]
internal static class FakeMerchantIdlePatch
{
    private static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> instructions)
    {
        var create = AccessTools.Method(typeof(CharacterModel), nameof(CharacterModel.CreateVisuals));
        var observe = AccessTools.Method(typeof(FakeMerchantIdlePatch), nameof(CreateVisuals));
        foreach (var instruction in instructions)
        {
            if (instruction.Calls(create))
            {
                instruction.opcode = OpCodes.Call;
                instruction.operand = observe;
            }
            yield return instruction;
        }
    }

    private static NCreatureVisuals CreateVisuals(CharacterModel model)
    {
        var visuals = model.CreateVisuals();
        // Native parenting, relaxed_loop setup and its RNG calls finish first.
        // The deferred callback only adds the existing cosmetic idle overlay.
        if (Visuals.IsTarget(model) && GodotObject.IsInstanceValid(visuals))
            Callable.From(() => IdleRooms.FakeMerchant(visuals)).CallDeferred();
        return visuals;
    }
}

[HarmonyPatch(typeof(NMerchantRoom), nameof(NMerchantRoom._Ready))]
internal static class MerchantIdlePatch
{
    private static void Postfix(NMerchantRoom __instance) => IdleRooms.Merchant(__instance);
}

[HarmonyPatch(typeof(NRestSiteCharacter), nameof(NRestSiteCharacter._Ready))]
internal static class RestIdlePatch
{
    private static void Postfix(NRestSiteCharacter __instance) => IdleRooms.Rest(__instance);
}
