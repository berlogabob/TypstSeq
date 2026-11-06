"""Create a disposable deterministic folder for P2P transfer experiments."""
import argparse
import hashlib
from pathlib import Path


def positive(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError('must be positive')
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path, help='new directory; never an existing vault')
    parser.add_argument('--variant', choices=['base', 'changed'], required=True)
    parser.add_argument('--notes', type=positive, default=200)
    parser.add_argument('--asset-mib', type=positive, default=8, help='size of each of two assets')
    args = parser.parse_args()

    # mkdir without exist_ok prevents modifying an existing folder or vault.
    args.destination.mkdir()
    notes = args.destination / 'notes'
    assets = args.destination / 'assets'
    notes.mkdir()
    assets.mkdir()
    for index in range(args.notes):
        text = f'= Synthetic note {index}\n\nDisposable P2P transfer fixture.\n'
        if args.variant == 'changed' and index == 0:
            text += 'Changed for incremental transfer.\n'
        (notes / f'note-{index:04d}.typ').write_text(text, encoding='utf-8')
    for index in range(2):
        with (assets / f'asset-{index}.bin').open('xb') as asset:
            for block in range(args.asset_mib):
                variant = args.variant if index == 1 else 'base'
                seed = f'p2p scratch asset {index} block {block} {variant}'.encode()
                asset.write(hashlib.shake_256(seed).digest(1024 * 1024))
    print(f'Created {args.notes} notes and two {args.asset_mib} MiB assets in {args.destination}')


if __name__ == '__main__':
    main()
