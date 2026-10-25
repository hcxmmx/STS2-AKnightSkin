using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Entities.Cards;
using MegaCrit.Sts2.Core.Entities.Creatures;
using MegaCrit.Sts2.Core.Hooks;
using MegaCrit.Sts2.Core.Nodes.Combat;
using MegaCrit.Sts2.Core.Commands.Builders;

namespace Hcxmmx.AKnightSkin;

internal static class TargetSnapshot
{
    internal static Godot.Collections.Dictionary? Read(Creature target)
    {
        var node = target.GetCreatureNode();
        if (node == null || !GodotObject.IsInstanceValid(node)) return null;
        return new Godot.Collections.Dictionary { ["node"] = node, ["ground"] = node.GetBottomOfHitbox() };
    }
}

// Visual notification only: no Task replacement, awaits, mutations or RNG calls.
[HarmonyPatch(typeof(Hook), nameof(Hook.BeforeCardPlayed))]
internal static class CardPerformancePatch
{
    private static void Prefix(CardPlay cardPlay)
    {
        try
        {
            var card = cardPlay.Card;
            if (!Visuals.IsTarget(card.Owner.Character)) return;
            var skin = card.Owner.Creature.GetCreatureNode() is { } owner ? Visuals.Skin(owner) : null;
            if (skin == null) return;
            var featherTicket = FeatherFeedback.Begin(cardPlay, skin);
            if (!cardPlay.IsFirstInSeries) return;
            var targets = new Godot.Collections.Array<Godot.Collections.Dictionary>();
            IEnumerable<Creature> candidates = cardPlay.Target is { } target && target.Side != card.Owner.Creature.Side
                ? new[] { target } : card.TargetType == TargetType.AllEnemies
                    ? card.CombatState?.HittableEnemies ?? Enumerable.Empty<Creature>() : Enumerable.Empty<Creature>();
            foreach (var candidate in candidates)
                if (candidate.IsAlive && TargetSnapshot.Read(candidate) is { } row) targets.Add(row);
            skin.Call("card_played", card.Id.Entry, card.Type.ToString(), card.TargetType.ToString(), targets, featherTicket);
        }
        catch (Exception ex) { GD.PushWarning("[AKnightSkin] Card: " + ex.Message); }
    }
}

[HarmonyPatch]
internal static class ActualAttackTargetsPatch
{
    private static System.Reflection.MethodBase TargetMethod() => typeof(MegaCrit.Sts2.Core.Commands.CreatureCmd).GetMethods().Single(method =>
        method.Name == "Damage" && method.GetParameters() is var args && args.Length is 6 or 7 &&
        args[1].ParameterType == typeof(IEnumerable<Creature>) && args[2].ParameterType == typeof(decimal));

    private static void Prefix(IEnumerable<Creature>? targets, MegaCrit.Sts2.Core.ValueProps.ValueProp props, Creature? dealer, MegaCrit.Sts2.Core.Models.CardModel? cardSource)
    {
        if (targets is not IReadOnlyList<Creature> actual || dealer?.GetCreatureNode() is not { } owner ||
            !props.HasFlag(MegaCrit.Sts2.Core.ValueProps.ValueProp.Move)) return;
        var skin=Visuals.Skin(owner);
        if (skin==null) return;
        var rows=new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach (var target in actual)
            if (TargetSnapshot.Read(target) is { } row) rows.Add(row);
        skin.Call("actual_targets",cardSource?.Id.Entry ?? "",rows);
    }
}

// Update multi-target information for attacks not originating in a normal card
// animation. The original result is read once; target selection stays native.
[HarmonyPatch(typeof(AttackCommand), "GetPossibleTargets")]
internal static class AttackTargetsPatch
{
    private static void Postfix(AttackCommand __instance, IReadOnlyList<Creature> __result)
    {
        try
        {
            var dealer = __instance.Attacker;
            var skin = dealer?.GetCreatureNode() is { } owner ? Visuals.Skin(owner) : null;
            if (skin == null) return;
            var targets = new Godot.Collections.Array<Godot.Collections.Dictionary>();
            // Random attacks use the existing scene FX placement, without a new
            // candidate-range fit or following each individual random hit.
            if (!__instance.IsRandomlyTargeted)
                foreach (var target in __result)
                    if (target.IsAlive && TargetSnapshot.Read(target) is { } row) targets.Add(row);
            skin.Call("attack_targets", targets, __instance.IsMultiTargeted && !__instance.IsRandomlyTargeted, __instance.IsRandomlyTargeted);
        }
        catch (Exception ex) { GD.PushWarning("[AKnightSkin] Attack targets: " + ex.Message); }
    }
}
