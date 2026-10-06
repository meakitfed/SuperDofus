// Method addresses of the Dofus 3 client (roadmap P1.13g), read from the Cpp2IL assemblies MelonLoader
// leaves in the install ([Address(RVA=..)] on every method). Used by tools/client_code/client_code.py.
//   dotnet run methods.cs -- all <out.tsv>                          every method: RVA, tab, Type::method
//   dotnet run methods.cs -- <dll> <type regex> [method regex] [x]  one assembly's matching types (x: + fields)
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Text.RegularExpressions;

string dir = Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? "", "Ankama", "Dofus-dofus3",
    "MelonLoader", "Dependencies", "Il2CppAssemblyGenerator", "Cpp2IL", "cpp2il_out");
if (args[0] == "all")
{
    using var w = new StreamWriter(args[1]);
    foreach (var f in Directory.GetFiles(dir, "*.dll"))
    {
        using var fs2 = File.OpenRead(f);
        using var pe2 = new PEReader(fs2);
        var md2 = pe2.GetMetadataReader();
        foreach (var th2 in md2.TypeDefinitions)
        {
            var t2 = md2.GetTypeDefinition(th2);
            string tn = md2.GetString(t2.Namespace) + "." + md2.GetString(t2.Name);
            if (!t2.GetDeclaringType().IsNil) tn = md2.GetString(md2.GetTypeDefinition(t2.GetDeclaringType()).Name) + "/" + md2.GetString(t2.Name);
            foreach (var mh2 in t2.GetMethods())
            {
                var m2 = md2.GetMethodDefinition(mh2);
                foreach (var cah in m2.GetCustomAttributes())
                {
                    var ca = md2.GetCustomAttribute(cah);
                    var br = md2.GetBlobReader(ca.Value);
                    if (br.Length < 8) continue;
                    br.ReadUInt16(); int n = br.ReadUInt16();
                    if (n < 1 || n > 4) continue;
                    try {
                        br.ReadByte(); var ty = br.ReadByte(); var nm = br.ReadSerializedString();
                        if (nm == "RVA" && ty == 0x0e) w.WriteLine($"{br.ReadSerializedString()}	{tn}::{md2.GetString(m2.Name)}");
                    } catch { }
                }
            }
        }
    }
    return;
}
if (args[0] == "chars")
{
    // types with char constants (single-letter codes the native code switches on)
    foreach (var f in Directory.GetFiles(dir, "*.dll"))
    {
        using var fs3 = File.OpenRead(f);
        using var pe3 = new PEReader(fs3);
        var md3 = pe3.GetMetadataReader();
        foreach (var th3 in md3.TypeDefinitions)
        {
            var t3 = md3.GetTypeDefinition(th3);
            var cs = new List<string>();
            foreach (var fh in t3.GetFields())
            {
                var fd = md3.GetFieldDefinition(fh);
                var ch = fd.GetDefaultValue();
                if (ch.IsNil) continue;
                var c = md3.GetConstant(ch);
                var cb = md3.GetBlobReader(c.Value);
                if (c.TypeCode == ConstantTypeCode.Char)
                    cs.Add($"{md3.GetString(fd.Name)}='{(char)cb.ReadUInt16()}'");
                else if (c.TypeCode == ConstantTypeCode.String && cb.Length <= 4)
                    cs.Add($"{md3.GetString(fd.Name)}=\"{cb.ReadUTF16(cb.Length)}\"");
            }
            if (cs.Count >= int.Parse(args[1]))
                Console.WriteLine($"{Path.GetFileName(f)} {md3.GetString(t3.Namespace)}.{md3.GetString(t3.Name)}: {string.Join(" ", cs)}");
        }
    }
    return;
}
var dll = args[0];
var typeRe = new Regex(args[1]);
var methRe = new Regex(args.Length > 2 ? args[2] : ".");
using var fs = File.OpenRead(Path.Combine(dir, dll));
using var pe = new PEReader(fs);
var md = pe.GetMetadataReader();

string AttrName(CustomAttribute ca)
{
    if (ca.Constructor.Kind == HandleKind.MemberReference)
    {
        var mr = md.GetMemberReference((MemberReferenceHandle)ca.Constructor);
        if (mr.Parent.Kind == HandleKind.TypeReference) return md.GetString(md.GetTypeReference((TypeReferenceHandle)mr.Parent).Name);
        if (mr.Parent.Kind == HandleKind.TypeDefinition) return md.GetString(md.GetTypeDefinition((TypeDefinitionHandle)mr.Parent).Name);
    }
    else if (ca.Constructor.Kind == HandleKind.MethodDefinition)
    {
        var m = md.GetMethodDefinition((MethodDefinitionHandle)ca.Constructor);
        return md.GetString(md.GetTypeDefinition(m.GetDeclaringType()).Name);
    }
    return "?";
}

string Named(CustomAttribute ca)
{
    var br = md.GetBlobReader(ca.Value);
    br.ReadUInt16();
    // ctor args: AddressAttribute has none; named args follow
    var parts = new List<string>();
    try
    {
        int n = br.ReadUInt16();
        for (int i = 0; i < n; i++)
        {
            br.ReadByte(); var t = br.ReadByte();
            var name = br.ReadSerializedString();
            string val = t == 0x0e ? br.ReadSerializedString() ?? "" : t == 0x08 ? br.ReadInt32().ToString() : "?";
            parts.Add($"{name}={val}");
        }
    }
    catch { }
    return string.Join(" ", parts);
}

string TypeFull(TypeDefinition t)
{
    var name = md.GetString(t.Name);
    var ns = md.GetString(t.Namespace);
    if (t.GetDeclaringType().IsNil == false)
        return TypeFull(md.GetTypeDefinition(t.GetDeclaringType())) + "/" + name;
    return (ns.Length > 0 ? ns + "." : "") + name;
}

// A field's type, roughly (class / value type / generic instance / primitive code).
string FieldType(MetadataReader md, FieldDefinition f)
{
    var br = md.GetBlobReader(f.Signature);
    br.ReadByte(); // FIELD
    string Elem(ref BlobReader r)
    {
        var e = r.ReadByte();
        if (e == 0x12 || e == 0x11) return TypeName(r.ReadTypeHandle());
        if (e == 0x15) { r.ReadByte(); var g = TypeName(r.ReadTypeHandle()); var n = r.ReadCompressedInteger(); var a = new List<string>(); for (int i = 0; i < n; i++) a.Add(Elem(ref r)); return g + "<" + string.Join(",", a) + ">"; }
        if (e == 0x1d) return Elem(ref r) + "[]";
        return "0x" + e.ToString("x");
    }
    string TypeName(EntityHandle h) => h.Kind == HandleKind.TypeDefinition ? TypeFull(md.GetTypeDefinition((TypeDefinitionHandle)h))
        : h.Kind == HandleKind.TypeReference ? md.GetString(md.GetTypeReference((TypeReferenceHandle)h).Name) : "?";
    try { return Elem(ref br); } catch { return "?"; }
}

foreach (var th in md.TypeDefinitions)
{
    var t = md.GetTypeDefinition(th);
    var full = TypeFull(t);
    if (!typeRe.IsMatch(full)) continue;
    Console.WriteLine($"== {full}");
    foreach (var fh in t.GetFields())
    {
        var f = md.GetFieldDefinition(fh);
        var ch = f.GetDefaultValue();
        string v = "";
        if (!ch.IsNil) { var c = md.GetConstant(ch); var br = md.GetBlobReader(c.Value); v = c.TypeCode == ConstantTypeCode.String ? "\"" + br.ReadUTF16(br.Length) + "\"" : c.TypeCode == ConstantTypeCode.Int32 ? br.ReadInt32().ToString() : ""; }
        string off = "";
        foreach (var cah in f.GetCustomAttributes())
        {
            var ca = md.GetCustomAttribute(cah);
            if (AttrName(ca) == "FieldOffsetAttribute") off = Named(ca);
        }
        if (args.Length > 3) Console.WriteLine($"   field {md.GetString(f.Name)} {v} {off} : {FieldType(md, f)}");
    }
    foreach (var mh in t.GetMethods())
    {
        var m = md.GetMethodDefinition(mh);
        var name = md.GetString(m.Name);
        if (!methRe.IsMatch(name)) continue;
        string addr = "";
        foreach (var cah in m.GetCustomAttributes())
        {
            var ca = md.GetCustomAttribute(cah);
            if (AttrName(ca) == "AddressAttribute") addr = Named(ca);
        }
        var ps = string.Join(",", m.GetParameters().Select(p => md.GetString(md.GetParameter(p).Name)));
        Console.WriteLine($"   {name}({ps})  {addr}");
    }
}
