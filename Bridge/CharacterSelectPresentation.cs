using System.Reflection;
using System.Reflection.Emit;
using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Commands;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Nodes;
using MegaCrit.Sts2.Core.Nodes.Screens.CharacterSelect;
using MegaCrit.Sts2.Core.Nodes.Vfx.Utilities;

namespace Hcxmmx.AKnightSkin;

// Guard each call in place. Keeping the existing call lets other character
// skins keep their own wrappers, in either Harmony transpiler order.
[HarmonyPatch(typeof(NCharacterSelectScreen), nameof(NCharacterSelectScreen.SelectCharacter))]
internal static class CharacterSelectPresentation
{
    private static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> instructions, ILGenerator generator)
    {
        var sound = AccessTools.Method(typeof(SfxCmd), nameof(SfxCmd.Play), [typeof(string), typeof(float)]);
        var shake = AccessTools.Method(typeof(NGame), nameof(NGame.ScreenShake), [typeof(ShakeStrength), typeof(ShakeDuration), typeof(float)]);
        var guard = AccessTools.Method(typeof(CharacterSelectPresentation), nameof(IsTarget));
        int sounds = 0, shakes = 0;
        foreach (var original in instructions)
        {
            var method = original.operand as MethodInfo;
            bool sotheby = method?.DeclaringType?.FullName == "Hcxmmx.SothebySkin.CharacterSelectPresentation";
            bool isSound = original.Calls(sound) || (sotheby && method!.Name == "PlaySelectionSound");
            bool isShake = original.Calls(shake) || (sotheby && method!.Name == "ShakeSelection");
            if (!isSound && !isShake) { yield return original; continue; }
            if (isSound) sounds++; else shakes++;
            var callOriginal = generator.DefineLabel();
            var end = generator.DefineLabel();
            yield return new CodeInstruction(OpCodes.Ldarg_2).MoveLabelsFrom(original).MoveBlocksFrom(original);
            yield return new CodeInstruction(OpCodes.Call, guard);
            yield return new CodeInstruction(OpCodes.Brfalse, callOriginal);
            // The target character skips only this visual/audio call. Dispose
            // exactly its existing arguments, including an instance receiver.
            int arguments = method!.GetParameters().Length + (method.IsStatic ? 0 : 1);
            for (int i = 0; i < arguments; i++) yield return new CodeInstruction(OpCodes.Pop);
            yield return new CodeInstruction(OpCodes.Br, end);
            original.labels.Add(callOriginal);
            yield return original;
            var tail = new CodeInstruction(OpCodes.Nop); tail.labels.Add(end); yield return tail;
        }
        // An optional selection-presentation change must not abort combat hooks.
        if (sounds != 1 || shakes != 1)
            GD.PushWarning($"[AKnightSkin] Selection presentation coverage: sound={sounds}, shake={shakes}; keeping unmatched calls unchanged.");
    }
    private static bool IsTarget(CharacterModel character) => Visuals.IsTarget(character);
}
