#!/usr/bin/env python3
"""resolve.py — turn sampler rips into a ranked symbol profile.

Usage: resolve.py <samples.txt> <maps.txt> <server.nm> [libc.nm]
  server.nm : output of  nm -nS --defined-only bin/server
  libc.nm   : output of  nm -D -nS /lib/x86_64-linux-gnu/libc.so.6  (optional)

Prints top individual symbols and module/function-group aggregates.
"""
import bisect
import collections
import re
import sys


def parse_nm(path):
    """nm -nS output -> sorted (addr, size, name) list."""
    syms = []
    pat = re.compile(r"^([0-9a-fA-F]+)\s+(?:([0-9a-fA-F]+)\s+)?\S+\s+(.+)$")
    with open(path) as f:
        for line in f:
            m = pat.match(line.strip())
            if not m:
                continue
            addr = int(m.group(1), 16)
            size = int(m.group(2), 16) if m.group(2) else 0
            name = m.group(3).strip()
            if name:
                syms.append((addr, size, name))
    syms.sort()
    return syms


def parse_maps(path):
    mods = []
    bases = {}  # module path -> lowest map start
    with open(path) as f:
        for line in f:
            parts = line.split(None, 5)
            if len(parts) < 6:
                parts.append("")
            rng, _perms, _off, _dev, _ino, p = parts[:6]
            start, end = (int(x, 16) for x in rng.split("-"))
            name = p.strip() or "[anon]"
            mods.append((start, end, name))
            if name in bases:
                bases[name] = min(bases[name], start)
            else:
                bases[name] = start
    mods.sort()
    return mods, bases


def module_for(addr, mods):
    i = bisect.bisect_right(mods, (addr, float("inf"), "")) - 1
    if i >= 0 and mods[i][0] <= addr < mods[i][1]:
        return mods[i][2]
    return None


def sym_lookup(addr, syms, addrs):
    """Nearest symbol at or below addr; requires addr < sym+size when size known."""
    i = bisect.bisect_right(addrs, addr) - 1
    if i < 0:
        return None, 0
    a, sz, name = syms[i]
    if sz and addr >= a + sz:
        # inside a gap (padding/rodata): still credit nearest symbol
        pass
    return name, addr - a


def classify(name):
    if name.startswith("sqlite3"):
        return "sqlite3*"
    if name.startswith(("vdbe", "Vdbe", "btree", "Btree", "pager", "Pager", "wal", "Wal", "pcache", "btreeMoveto")):
        return "sqlite3*"
    if name.startswith(("app_", "sha256", "hmac", "b64", "json_", "jv_", "utf8", "trim_", "cplen_", "streq", "prefix", "parseid", "parseexp", ".Lemit", "Lemit")):
        return "emitted asm (app layer)"
    if name.startswith(("x_", "io_uring", "http_", "db_", "main")):
        return "C runtime"
    if name.startswith(("pthread", "_int", "malloc", "free", "memcpy", "memset", "memmove", "__memcpy", "__memmove", "__memset")):
        return "libc mem/alloc"
    return "libc/syscalls/other"


def main():
    samples_f, maps_f, server_nm = sys.argv[1], sys.argv[2], sys.argv[3]
    libc_nm = sys.argv[4] if len(sys.argv) > 4 else None
    sqlite_nm = sys.argv[5] if len(sys.argv) > 5 else None

    syms_by_mod = {"server": parse_nm(server_nm)}
    if libc_nm:
        syms_by_mod["libc"] = parse_nm(libc_nm)
    if sqlite_nm:
        syms_by_mod["sqlite3"] = parse_nm(sqlite_nm)

    mods, bases = parse_maps(maps_f)
    rips = []
    with open(samples_f) as f:
        for line in f:
            line = line.strip()
            if line:
                rips.append(int(line, 16))
    if not rips:
        print("no samples")
        return

    sym_count = collections.Counter()
    group_count = collections.Counter()
    mod_count = collections.Counter()
    unresolved = 0

    for r in rips:
        mod = module_for(r, mods)
        if mod is None:
            unresolved += 1
            sym_count["?? unmapped"] += 1
            group_count["?? unmapped"] += 1
            continue
        base = mod.rsplit("/", 1)[-1]
        if "server" in base:
            table, key = "server", "bin/server"
        elif "libsqlite3" in base:
            table, key = "sqlite3", "libsqlite3.so.0"
        elif "libc" in base:
            table, key = "libc", "libc.so.6"
        elif base in ("ld-linux-x86-64.so.2", "[vdso]", "libm.so.6"):
            table, key = None, base
        else:
            table, key = None, base
        mod_count[key] += 1
        if table:
            syms = syms_by_mod[table]
            addrs = [s[0] for s in syms]
            # shared libs: nm addrs are ELF-vaddrs; rebase to module load base
            rel = r if table == "server" else r - bases[mod]
            name, off = sym_lookup(rel, syms, addrs)
            if name:
                label = f"{name}+{off:#x}"
                sym_count[label] += 1
                group_count[classify(name)] += 1
                continue
        sym_count[f"[{key}]"] += 1
        group_count[f"[{key}]"] += 1

    total = len(rips)
    print(f"=== {total} samples ({unresolved} unmapped) ===\n")
    print("--- top symbols ---")
    for name, c in sym_count.most_common(35):
        print(f"{100 * c / total:6.2f}%  {c:7d}  {name}")
    print("\n--- groups ---")
    for name, c in group_count.most_common(20):
        print(f"{100 * c / total:6.2f}%  {c:7d}  {name}")
    print("\n--- modules ---")
    for name, c in mod_count.most_common(15):
        print(f"{100 * c / total:6.2f}%  {c:7d}  {name}")


if __name__ == "__main__":
    main()
