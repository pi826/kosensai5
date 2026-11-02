"""Rebake only waterway masonry and regional backgrounds; verify byte stability."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
import build_art as b
import build_stage3 as stage3


def main():
    qa = b.ROOT / 'builds/qa/art/polish'
    qa.mkdir(parents=True, exist_ok=True)
    b.QA = qa / 'previews'
    b.QA.mkdir(exist_ok=True)
    stage3.b = b
    paths = [b.OUT / 'terrain/waterway.png', b.OUT / 'terrain/special.png']
    paths += sorted((b.OUT / 'backdrops').glob('*.png'))
    snapshots = []
    for _ in range(2):
        b.bake_terrain()
        stage3.backgrounds()
        snapshots.append({p.relative_to(b.ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
    assert snapshots[0] == snapshots[1], 'PNG regeneration is not byte-identical'
    for p in paths:
        a = np.array(Image.open(p).convert('RGBA'))
        assert set(np.unique(a[:, :, 3])) <= {0, 255}, p
        assert len(np.unique(a.reshape(-1, 4), axis=0)) <= 64, p
    atlas = np.array(Image.open(paths[0]).convert('RGBA'))
    interiors = [atlas[v*32:(v+1)*32, 8160:8192] for v in range(4)]
    for a in interiors:
        for other in interiors:
            assert np.array_equal(a[:, -1], other[:, 0]), 'horizontal waterway seam'
            assert np.array_equal(a[-1, :], other[0, :]), 'vertical waterway seam'
    manifest_path = b.OUT / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    manifest['hashes'].update(snapshots[1])
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True)+'\n', encoding='utf-8')
    report = {'byte_identical': True, 'binary_alpha': True, 'max_colors': 64, 'waterway_edges_match': True, 'hashes': snapshots[1], 'new_generations': 0}
    (qa / 'build-verification.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
