import sys, re

def strip_previews(path):
    src = open(path).read()
    out, i, removed = [], 0, 0
    while True:
        m = re.search(r'#Preview\s*(?:\([^)]*\))?\s*\{', src[i:])
        if not m:
            out.append(src[i:])
            break
        start = i + m.start()
        out.append(src[i:start])
        # walk balanced braces from the opening brace
        j = i + m.end()
        depth = 1
        while depth > 0 and j < len(src):
            if src[j] == '{': depth += 1
            elif src[j] == '}': depth -= 1
            j += 1
        i = j
        removed += 1
    open(path, 'w').write(''.join(out))
    return removed

for p in sys.argv[1:]:
    n = strip_previews(p)
    print(f"{p}: removed {n} preview block(s)")
