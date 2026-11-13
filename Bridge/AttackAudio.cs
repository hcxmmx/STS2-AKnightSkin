using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Commands;
using MegaCrit.Sts2.Core.Commands.Builders;
using MegaCrit.Sts2.Core.Entities.Creatures;
using MegaCrit.Sts2.Core.Audio.Debug;

namespace Hcxmmx.AKnightSkin;

// Replace only the audio calls inside the native attack coroutine. Its waits,
// damage, animation, target selection, VFX and return value are untouched.
[HarmonyPatch]
internal static class AttackAudioPatch
{
    private static readonly Type State = typeof(AttackCommand).GetMethod(nameof(AttackCommand.Execute))!
        .GetCustomAttribute<AsyncStateMachineAttribute>()!.StateMachineType;
    private static readonly FieldInfo Command = State.GetField("<>4__this", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)!;
    private static MethodBase TargetMethod() => AccessTools.Method(State, "MoveNext");

    private static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> instructions, ILGenerator generator)
    {
        var original = AccessTools.Method(typeof(SfxCmd), nameof(SfxCmd.Play), new[] { typeof(string), typeof(float) });
        var replacement = AccessTools.Method(typeof(AttackAudioPatch), nameof(Play));
        var debugOriginal = AccessTools.Method(typeof(NDebugAudioManager), nameof(NDebugAudioManager.Play), new[] { typeof(string), typeof(float), typeof(PitchVariance) });
        var debugReplacement = AccessTools.Method(typeof(AttackAudioPatch), nameof(PlayDebug));
        var damage = ActualAttackTargetsPatch.ObserveAtCallSite ? ActualAttackTargetsPatch.TargetMethod() : null;
        var observe = AccessTools.Method(typeof(ActualAttackTargetsPatch), nameof(ActualAttackTargetsPatch.Observe));
        int damageCalls = 0;
        foreach (var instruction in instructions)
        {
            if (damage != null && instruction.Calls(damage))
            {
                damageCalls++;
                // Preserve evaluated arguments, original Task and all native waits.
                var arguments = damage.GetParameters().Select(parameter => generator.DeclareLocal(parameter.ParameterType)).ToArray();
                for (int i = arguments.Length - 1; i >= 0; i--)
                {
                    var save = new CodeInstruction(OpCodes.Stloc, arguments[i]);
                    if (i == arguments.Length - 1) save.MoveLabelsFrom(instruction).MoveBlocksFrom(instruction);
                    yield return save;
                }
                yield return new CodeInstruction(OpCodes.Ldloc, arguments[4]);
                yield return new CodeInstruction(OpCodes.Ldloc, arguments[1]);
                yield return new CodeInstruction(OpCodes.Ldloc, arguments[3]);
                yield return new CodeInstruction(OpCodes.Ldloc, arguments[5]);
                yield return new CodeInstruction(OpCodes.Call, observe);
                foreach (var argument in arguments) yield return new CodeInstruction(OpCodes.Ldloc, argument);
                yield return instruction;
                continue;
            }
            bool debug = instruction.Calls(debugOriginal);
            if (!debug && !instruction.Calls(original)) { yield return instruction; continue; }
            var load = new CodeInstruction(OpCodes.Ldarg_0);
            load.labels.AddRange(instruction.labels);
            load.blocks.AddRange(instruction.blocks);
            yield return load;
            yield return new CodeInstruction(OpCodes.Ldfld, Command);
            yield return new CodeInstruction(OpCodes.Call, debug ? debugReplacement : replacement);
        }
        if (damage != null && damageCalls != 1) throw new InvalidOperationException("Expected one native damage call, found " + damageCalls);
    }

    private static void Play(string sfx, float volume, AttackCommand command)
    {
        if (command.Attacker?.GetCreatureNode() is { } owner && Visuals.Skin(owner) is { } skin &&
            skin.Call("uses_original_sfx").AsBool()) return;
        SfxCmd.Play(sfx, volume);
    }

    private static int PlayDebug(NDebugAudioManager manager, string sfx, float volume, PitchVariance variance, AttackCommand command)
    {
        if (command.Attacker?.GetCreatureNode() is { } owner && Visuals.Skin(owner) is { } skin &&
            skin.Call("uses_original_sfx").AsBool()) return -1;
        return manager.Play(sfx,volume,variance);
    }
}
