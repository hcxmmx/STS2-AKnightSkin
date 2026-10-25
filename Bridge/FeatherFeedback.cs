using System.Runtime.CompilerServices;
using System.Reflection;
using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Entities.Cards;
using MegaCrit.Sts2.Core.Entities.Creatures;
using MegaCrit.Sts2.Core.Combat;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Hooks;
using MegaCrit.Sts2.Core.Commands.Builders;

namespace Hcxmmx.AKnightSkin;

internal static class FeatherFeedback
{
    private sealed class Ticket { public long Id; public ulong Skin; public bool Fired; }
    private static long _next;
    private static readonly ConditionalWeakTable<CardPlay, Ticket> Plays = new();
    private static readonly ConditionalWeakTable<CardModel, Ticket> Series = new();
    private static readonly PropertyInfo? CommandCardPlay = typeof(AttackCommand).GetProperty("CardPlay");
    private static readonly ConditionalWeakTable<CardModel, List<CardPlay>> ActivePlays = new();
    internal static long Begin(CardPlay play, Node skin)
    {
        Ticket? ticket;
        if (play.IsFirstInSeries)
        {
            ticket = new Ticket { Id = ++_next, Skin = skin.GetInstanceId() };
            Series.Remove(play.Card); Series.Add(play.Card, ticket);
        }
        else if (!Series.TryGetValue(play.Card, out ticket)) return 0;
        Plays.Remove(play); Plays.Add(play, ticket);
        // Public v0.107.1 carries the source card but not CardPlay on attacks.
        // Track only the native Before/AfterCardPlayed lifetime in that host;
        // beta keeps its exact per-command CardPlay association.
        if (CommandCardPlay == null)
        {
            var active = ActivePlays.GetOrCreateValue(play.Card);
            active.Remove(play); active.Add(play);
        }
        return ticket.Id;
    }
    private static Node? Skin(Ticket ticket) => GodotObject.InstanceFromId(ticket.Skin) is Node node && GodotObject.IsInstanceValid(node) && node.IsInsideTree() ? node : null;

    // Results are populated and CreatureCmd.Kill has finished here. A lethal
    // result alone also includes resurrection, so require actual enemy removal.
    internal static void Observe(ICombatState combatState, AttackCommand command)
    {
        var play = CommandCardPlay != null ? CommandCardPlay.GetValue(command) as CardPlay :
            command.ModelSource is CardModel source && ActivePlays.TryGetValue(source, out var active) ? active.LastOrDefault() : null;
        if (play == null || !Plays.TryGetValue(play, out var ticket) || ticket.Fired ||
            command.Attacker != play.Card.Owner.Creature || !Visuals.IsTarget(play.Card.Owner.Character)) return;
        if (!command.Results.SelectMany(row => row).Any(result => ConfirmedKill(result, command.Attacker, combatState.Enemies))) return;
        if (Skin(ticket) is not { } skin) return;
        ticket.Fired = true; skin.Call("feather_kill", ticket.Id);
    }
    internal static bool ConfirmedKill(DamageResult result, Creature attacker, IReadOnlyList<Creature> enemies) =>
        result.WasTargetKilled && result.Receiver.IsDead && result.Receiver.Side != attacker.Side && !enemies.Contains(result.Receiver);
    internal static void Finish(CardPlay play)
    {
        if (CommandCardPlay == null && ActivePlays.TryGetValue(play.Card, out var active))
        {
            active.Remove(play);
            if (active.Count == 0) ActivePlays.Remove(play.Card);
        }
        if (!play.IsLastInSeries || !Plays.TryGetValue(play, out var ticket)) return;
        Skin(ticket)?.Call("feather_finished", ticket.Id);
    }
}

[HarmonyPatch(typeof(Hook), nameof(Hook.AfterAttack))]
internal static class FeatherAttackPatch
{
    private static void Prefix(ICombatState combatState, AttackCommand command)
    { try { FeatherFeedback.Observe(combatState, command); } catch (Exception ex) { GD.PushWarning("[AKnightSkin] Feather result: " + ex.Message); } }
}
[HarmonyPatch(typeof(Hook), nameof(Hook.AfterCardPlayed))]
internal static class FeatherCardFinishedPatch
{
    private static void Prefix(CardPlay cardPlay)
    { try { FeatherFeedback.Finish(cardPlay); } catch (Exception ex) { GD.PushWarning("[AKnightSkin] Feather finish: " + ex.Message); } }
}
