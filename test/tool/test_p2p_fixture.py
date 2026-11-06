import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class ScratchFixtureTest(unittest.TestCase):
    def test_generates_reproducible_pair_and_refuses_existing_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = Path('tool/p2p6/scratch_fixture.py')
            def run(name, variant):
                return subprocess.run(
                    [sys.executable, str(script), str(root / name), '--variant', variant,
                     '--notes', '3', '--asset-mib', '1'],
                    capture_output=True, text=True,
                )
            self.assertEqual(run('base', 'base').returncode, 0)
            self.assertEqual(run('repeat', 'base').returncode, 0)
            self.assertEqual(run('changed', 'changed').returncode, 0)
            base = root / 'base'
            files = sorted(p.relative_to(base) for p in base.rglob('*') if p.is_file())
            self.assertEqual(len(files), 5)
            changed = []
            for path in files:
                data = (base / path).read_bytes()
                self.assertEqual(data, (root / 'repeat' / path).read_bytes())
                if data != (root / 'changed' / path).read_bytes():
                    changed.append(path)
            self.assertEqual(changed, [Path('assets/asset-1.bin'), Path('notes/note-0000.typ')])
            self.assertEqual((base / 'assets/asset-0.bin').stat().st_size, 1024 * 1024)
            self.assertNotEqual(run('base', 'changed').returncode, 0)
            self.assertEqual((base / 'notes/note-0000.typ').read_bytes(), (root / 'repeat/notes/note-0000.typ').read_bytes())


if __name__ == '__main__':
    unittest.main()
