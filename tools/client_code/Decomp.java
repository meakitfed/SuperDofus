// Decompiles the functions at the given RVAs (args: out file, rva...) or a file of RVAs (@file).
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class Decomp extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        List<String> rvas = new ArrayList<>();
        for (int i = 1; i < args.length; i++) {
            if (args[i].startsWith("@")) rvas.addAll(Files.readAllLines(Paths.get(args[i].substring(1))));
            else rvas.add(args[i]);
        }
        long base = currentProgram.getImageBase().getOffset();
        DecompInterface d = new DecompInterface();
        DecompileOptions o = new DecompileOptions();
        d.setOptions(o);
        d.openProgram(currentProgram);
        try (PrintWriter w = new PrintWriter(new FileWriter(args[0]))) {
            for (String r : rvas) {
                r = r.trim();
                if (r.isEmpty()) continue;
                Address a = toAddr(base + Long.decode(r));
                Function f = getFunctionAt(a);
                if (f == null) {
                    new DisassembleCommand(a, null, true).applyTo(currentProgram, monitor);
                    f = createFunction(a, null);
                }
                if (f == null) { w.println("// no function at " + r); continue; }
                // create callees so their names show
                DecompileResults res = d.decompileFunction(f, 120, monitor);
                w.println("// ===== " + r + " " + f.getName());
                w.println(res.decompileCompleted() ? res.getDecompiledFunction().getC() : "// failed: " + res.getErrorMessage());
            }
        }
    }
}
