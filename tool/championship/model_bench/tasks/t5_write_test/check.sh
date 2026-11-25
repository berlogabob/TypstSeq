set -e
flutter test test/macos_no_sandbox_test.dart
for f in macos/Runner/Release.entitlements macos/Runner/DebugProfile.entitlements; do
  cp "$f" /tmp/bench_ent.bak
  python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
n = re.sub(r'(<key>com\.apple\.security\.app-sandbox</key>\s*)<false/>', r'\1<true/>', s)
assert n != s; open(p, 'w').write(n)
PY
  if flutter test test/macos_no_sandbox_test.dart >/dev/null 2>&1; then cp /tmp/bench_ent.bak "$f"; echo "did not catch sandbox on in $f"; exit 1; fi
  cp /tmp/bench_ent.bak "$f"
done
echo ok
