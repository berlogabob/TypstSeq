set -e
flutter analyze --no-pub lib/widgets/editor_panel.dart
python3 - <<'PY'
import re, subprocess, sys, collections
consts = {}
for m in re.finditer(r'^const (k\w+) = (?:Duration\(milliseconds: )?([\d.]+)', open('lib/widgets/constants.dart').read(), re.M):
    consts[m[1]] = m[2]
def numbers(src):
    src = re.sub(r'//.*', '', src)
    src = re.sub(r"'(?:\\.|[^'\\])*'", "''", src)
    used = 0
    def sub(m):
        nonlocal used
        if m[0] in consts: used += 1; return consts[m[0]]
        return m[0]
    src = re.sub(r'\bk[A-Z]\w+', sub, src)
    nums = collections.Counter(str(float(n)) for n in re.findall(r'(?<![\w.])\d+(?:\.\d+)?(?![\w.])', src))
    return nums, used
old = subprocess.check_output(['git', 'show', 'HEAD:lib/widgets/editor_panel.dart'], text=True)
new = open('lib/widgets/editor_panel.dart').read()
a, _ = numbers(old); b, used = numbers(new)
if a != b: sys.exit(f'values changed: removed {dict(a - b)} added {dict(b - a)}')
if used < 3: sys.exit(f'only {used} tokens used')
strip = lambda s: len([l for l in s.splitlines() if l.strip()])
if abs(strip(old) - strip(new)) > 25: sys.exit('file restructured')
print('ok', used, 'tokens')
PY
