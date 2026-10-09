python3 - <<'PY'
p = 'lib/workspace_controller.dart'; s = open(p).read()
a = "String friendlySyncError(Object error) {\n"
assert s.count(a) == 1
open(p, 'w').write(s.replace(a, a + """  if (error is WebDavStatusException &&
      (const {502, 503, 504}.contains(error.statusCode) ||
          error.statusCode >= 520 && error.statusCode <= 530)) {
    return 'Nextcloud server is unreachable (${error.statusCode}). '
        'Your notes are saved on this device; sync will retry.';
  }
"""))
PY
