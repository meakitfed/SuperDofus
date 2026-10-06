// Applies names.tsv (RVA \t Type::method) as labels.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.symbol.SourceType;
import java.nio.file.*;
import java.util.*;

public class Label extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String path = getScriptArgs()[0];
        long base = currentProgram.getImageBase().getOffset();
        int n = 0;
        Set<Long> seen = new HashSet<>();
        for (String line : Files.readAllLines(Paths.get(path))) {
            String[] p = line.split("\t");
            if (p.length < 2) continue;
            long rva = Long.decode(p[0]);
            if (rva == 0 || !seen.add(rva)) continue;
            Address a = toAddr(base + rva);
            String name = p[1].replaceAll("[^A-Za-z0-9_.:/<>`]", "_").replace("::", "__");
            try {
                currentProgram.getSymbolTable().createLabel(a, name, SourceType.USER_DEFINED);
                n++;
            } catch (Exception e) { }
        }
        println("labels: " + n);
    }
}
