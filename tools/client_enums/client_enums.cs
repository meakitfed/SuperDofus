// Client enums -> docs/client_enums.md (roadmap P1.13e).
//   dotnet run tools/client_enums/client_enums.cs -- docs/client_enums.md
// Reads the assemblies MelonLoader's Cpp2IL leaves in the Dofus 3 install
// (MelonLoader/Dependencies/Il2CppAssemblyGenerator/Cpp2IL/cpp2il_out): the method bodies are
// native, but the enums' names and values are there. Writes the ones the rules cite:
// Metadata.Effect.ActionId (effect ids), Metadata.Enums.SpellZoneShape (zone letters) and the
// trigger codes (the string constants of the class holding "CMPARR"; its field names are obfuscated).
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Text;

string outPath = args.Length > 0 ? args[0] : "docs/client_enums.md";
string dir = Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? "", "Ankama", "Dofus-dofus3",
    "MelonLoader", "Dependencies", "Il2CppAssemblyGenerator", "Cpp2IL", "cpp2il_out");
var sb = new StringBuilder();
sb.AppendLine("# Enums du client Dofus 3");
sb.AppendLine();
sb.AppendLine("Généré par `tools/client_enums/client_enums.cs` depuis les assemblys que Cpp2IL (MelonLoader) laisse dans");
sb.AppendLine("l'installation du jeu. Le code est natif, mais les noms et valeurs des enums y sont : c'est la source");
sb.AppendLine("citée par les règles (« client enum … »). Ne donne que des noms, pas la logique (la géométrie d'une zone,");
sb.AppendLine("ce que fait un effet).");
sb.AppendLine();

void Section(string dll, string typeName, string title, Func<object, string> key)
{
    using var fs = File.OpenRead(Path.Combine(dir, dll));
    using var pe = new PEReader(fs);
    var md = pe.GetMetadataReader();
    foreach (var th in md.TypeDefinitions)
    {
        var t = md.GetTypeDefinition(th);
        string full = md.GetString(t.Namespace) + "." + md.GetString(t.Name);
        if (full != typeName) continue;
        sb.AppendLine($"## {title} (`{typeName}`)");
        sb.AppendLine();
        sb.AppendLine("| Valeur | Nom |");
        sb.AppendLine("|---|---|");
        foreach (var fh in t.GetFields())
        {
            var f = md.GetFieldDefinition(fh);
            var v = Constant(md, f);
            if (v != null) sb.AppendLine($"| {key(v)} | {md.GetString(f.Name)} |");
        }
        sb.AppendLine();
    }
}

object? Constant(MetadataReader md, FieldDefinition f)
{
    var ch = f.GetDefaultValue();
    if (ch.IsNil) return null;
    var c = md.GetConstant(ch);
    var br = md.GetBlobReader(c.Value);
    return c.TypeCode switch
    {
        ConstantTypeCode.Int32 => br.ReadInt32(), ConstantTypeCode.UInt32 => (long)br.ReadUInt32(),
        ConstantTypeCode.Int16 => (int)br.ReadInt16(), ConstantTypeCode.UInt16 => (int)br.ReadUInt16(),
        ConstantTypeCode.Byte => (int)br.ReadByte(), ConstantTypeCode.SByte => (int)br.ReadSByte(),
        ConstantTypeCode.String => br.ReadUTF16(br.Length), _ => null
    };
}

Section("Ankama.Dofus.Core.DataCenter.dll", "Core.DataCenter.Metadata.Effect.ActionId", "Effets", v => v.ToString()!);
Section("Ankama.Dofus.Core.DataCenter.dll", "Metadata.Enums.SpellZoneShape", "Formes de zone",
    v => v is int i && i > 32 && i < 127 ? $"`{(char)i}` ({i})" : v.ToString()!);

// trigger codes: the obfuscated class whose string constants include "CMPARR"
using (var fs = File.OpenRead(Path.Combine(dir, "Core.dll")))
using (var pe = new PEReader(fs))
{
    var md = pe.GetMetadataReader();
    foreach (var th in md.TypeDefinitions)
    {
        var t = md.GetTypeDefinition(th);
        var codes = t.GetFields().Select(fh => Constant(md, md.GetFieldDefinition(fh))).OfType<string>().ToList();
        if (!codes.Contains("CMPARR")) continue;
        sb.AppendLine("## Codes de déclencheurs");
        sb.AppendLine();
        sb.AppendLine("Constantes d'une classe obfusquée de `Core.dll` (à côté de `Core.Features.Fight.Spells.Triggers`) :");
        sb.AppendLine("la liste complète des codes que le client connaît, sans leur sens.");
        sb.AppendLine();
        sb.AppendLine(string.Join(", ", codes.Where(c => c != "").Select(c => $"`{c}`")));
        sb.AppendLine();
        break;
    }
}
File.WriteAllText(outPath, sb.ToString());
Console.WriteLine($"-> {outPath}");
