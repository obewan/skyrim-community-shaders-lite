"""Measure what the lite profile costs to compile, offline.

Compiles the real permutations captured in .github/configs/shader-validation.yaml with
fxc at shipping flags, so a profile can be evaluated without launching the game.

Two modes:

  ablate   one run per feature with that feature's define removed from an
           all-features baseline. The wall-clock delta is that feature's marginal
           cost. Use it to find what is actually expensive.

  compare  the shipped profile (read from SettingsDefault.json) against an
           all-features baseline, per shader family, reweighted by the real
           permutation counts. Use it for the headline number.

The profile is derived from the repo rather than hardcoded, so this cannot drift out of
sync with what actually ships.

Prerequisites: pip install git+https://github.com/alandtse/hlslkit.git, plus a **full**
(non-lite) shader tree, because the baseline compiles with every feature define set and
the base shaders include each feature's .hlsli under those guards:

    cmake -S . --preset=ALL && cmake --build --preset=Dev
    python tools/lite_shader_bench.py compare --shader-dir build/ALL/aio/Shaders ...

A lite tree is rejected up front rather than producing meaningless numbers.

Caveats worth remembering when reading the output:
  * Permutation counts come from Skyrim's descriptor bits, not from CS. Disabling
    features makes each permutation cheaper, never fewer.
  * The captured corpus predates some features; those are injected into the baseline
    so it reflects a real all-features install (see INJECTED).
  * These are fxc wall-clock numbers over a sampled corpus. The ranking holds; absolute
    times will not match a real game launch.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lite_shader_variant import build_variant  # noqa: E402

import yaml  # noqa: E402

# Defines a full install sets that the captured log never exercised. Injected into the
# baseline so "full" means a real all-features setup rather than whatever that one
# playthrough happened to load.
INJECTED = [
    'CS_SKIN', 'EFFECTS11', 'EXP_HEIGHT_FOG', 'HORIZON_FIX',
    'TERRAIN_BLENDING', 'TERRAIN_HELPER', 'UNIFIED_WATER', 'VOLUMETRIC_SHADOWS',
]

SUPPRESS = 'X1519,X3206,X3571,X4000'


def feature_defines(repo):
    """Map feature short name -> its shader define (None when it emits none)."""
    defines = {}
    pattern_short = re.compile(r'GetShortName\(\)\s*override\s*\{\s*return\s*"([^"]+)"')
    pattern_define = re.compile(r'GetShaderDefineName\(\)\s*override\s*\{\s*return\s*"([^"]*)"')
    for root in (os.path.join(repo, 'src', 'Features'), os.path.join(repo, 'src')):
        if not os.path.isdir(root):
            continue
        for fn in os.listdir(root):
            if not fn.endswith('.h'):
                continue
            text = open(os.path.join(root, fn), encoding='utf-8', errors='ignore').read()
            short = pattern_short.search(text)
            if short:
                found = pattern_define.search(text)
                defines[short.group(1)] = found.group(1) if found and found.group(1) else None
    return defines


def shipped_profile_defines(repo):
    """Defines emitted by the features the shipped SettingsDefault.json leaves enabled."""
    profile_path = os.path.join(
        repo, 'package', 'SKSE', 'Plugins', 'CommunityShaders', 'SettingsDefault.json')
    with open(profile_path) as fh:
        disabled = json.load(fh)['Disable at Boot']
    defines = feature_defines(repo)
    enabled = [name for name, off in disabled.items() if not off]
    return sorted({defines.get(n) for n in enabled if defines.get(n)}), enabled


def corpus_defines(config_path):
    """Every feature define the captured corpus carries, plus the injected ones."""
    with open(config_path) as fh:
        cfg = yaml.safe_load(fh)
    found = set()
    for _file, stages in (cfg.get('file_common_defines') or {}).items():
        for _stage, defines in stages.items():
            found.update(d.split('=')[0] for d in (defines or []))
    # Descriptor bits and compiler flags are not ours to toggle.
    not_features = {'WATER', 'FOG', 'VC', 'SHADOWSPLITCOUNT',
                    'D3DCOMPILE_DEBUG', 'D3DCOMPILE_SKIP_OPTIMIZATION',
                    'PSHADER', 'VSHADER', 'CSHADER'}
    return sorted((found - not_features) | set(INJECTED))


def require_full_shader_tree(repo, shader_dir):
    """Refuse a lite (feature-stripped) shader tree.

    The baseline compiles with every feature define set, and the base shaders include
    each feature's .hlsli under those guards. On a stripped tree those includes do not
    resolve, so the baseline fails to compile and every number is meaningless -- which
    is easy to miss, because hlslkit keeps going and still reports timings.
    """
    expected = set()
    features_dir = os.path.join(repo, 'features')
    for folder in sorted(os.listdir(features_dir)):
        shaders = os.path.join(features_dir, folder, 'Shaders')
        if not os.path.isdir(shaders):
            continue
        expected.update(
            sub for sub in os.listdir(shaders)
            if sub != 'Features' and os.path.isdir(os.path.join(shaders, sub))
        )

    missing = [sub for sub in expected if not os.path.isdir(os.path.join(shader_dir, sub))]
    if missing:
        sys.exit(
            f'{shader_dir} is missing {len(missing)} feature shader folders '
            f'({", ".join(sorted(missing)[:5])}...).\n'
            'This looks like a lite (feature-stripped) tree. The baseline needs every '
            'feature present, so point --shader-dir at a full build:\n'
            '  cmake -S . --preset=ALL && cmake --build --preset=Dev\n'
            '  ... then use build/ALL/aio/Shaders'
        )


def time_variant(args, drop, add, files, workdir, tag):
    """Compile one variant and return (best seconds, entries compiled)."""
    cfg_path = os.path.join(workdir, f'{tag}.yaml')
    out_dir = os.path.join(workdir, f'{tag}.out')

    cfg, kept, _total = build_variant(
        args.config, drop, add, set(files), args.sample, args.seed, True)
    with open(cfg_path, 'w') as fh:
        yaml.safe_dump(cfg, fh, default_flow_style=False, sort_keys=False)

    best = None
    for _ in range(args.repeat):
        # Never measure a warm output dir.
        shutil.rmtree(out_dir, ignore_errors=True)
        os.makedirs(out_dir, exist_ok=True)
        start = time.perf_counter()
        proc = subprocess.run(
            [args.hlslkit, '--fxc', args.fxc, '--shader-dir', args.shader_dir,
             '--output-dir', out_dir, '--config', cfg_path, '--jobs', str(args.jobs),
             '--optimization-level', '3', '--max-warnings', '99999',
             '--suppress-warnings', SUPPRESS],
            capture_output=True, text=True)
        elapsed = time.perf_counter() - start
        if proc.returncode != 0:
            print(f'  ! {tag}: hlslkit exit {proc.returncode}\n{proc.stderr[-500:]}', file=sys.stderr)
        best = elapsed if best is None else min(best, elapsed)
    shutil.rmtree(out_dir, ignore_errors=True)
    return best, kept


def run_ablate(args, workdir):
    all_defines = corpus_defines(args.config)
    files = [args.files] if args.files else []

    baseline, kept = time_variant(args, [], INJECTED, files, workdir, 'baseline')
    print(f'baseline ({kept} entries): {baseline:.2f}s\n')
    print(f'{"feature define":26}{"seconds":>9}{"saves":>9}{"pct":>8}')
    print(f'{"baseline":26}{baseline:9.2f}{"":>9}{"":>8}')

    rows = []
    for define in all_defines:
        seconds, _ = time_variant(
            args, [define], [d for d in INJECTED if d != define], files, workdir, f'no_{define}')
        delta = baseline - seconds
        rows.append((delta, define, seconds))
        print(f'-{define:25}{seconds:9.2f}{delta:+9.2f}{100 * delta / baseline:+7.1f}%')

    print('\nRanked by saving:')
    for delta, define, _s in sorted(rows, reverse=True):
        if delta > 0.02 * baseline:
            print(f'  {define:24}{delta:7.2f}s  {100 * delta / baseline:5.1f}%')
    print('\nAnything below a couple of percent is inside measurement noise.')


def run_compare(args, workdir):
    all_defines = corpus_defines(args.config)
    keep, enabled = shipped_profile_defines(args.repo)
    drop = [d for d in all_defines if d not in keep]

    print(f'shipped profile: {len(enabled)} features enabled, emitting {len(keep)} defines')
    print(f'dropped relative to full: {", ".join(drop) or "none"}\n')

    # Real permutation counts, so a uniform per-stage sample does not under-weight
    # Lighting -- which is a minority of permutations but most of the time.
    with open(args.config) as fh:
        cfg = yaml.safe_load(fh)
    counts = {}
    for shader in cfg.get('shaders') or []:
        counts[shader['file']] = sum(
            len(c.get('entries') or []) for c in (shader.get('configs') or {}).values())
    families = sorted(counts, key=counts.get, reverse=True)[:4]

    print(f'{"family":16}{"perms":>7}{"full":>10}{"lite":>10}')
    total_full = total_lite = 0.0
    for family in families:
        full_s, full_n = time_variant(args, [], INJECTED, [family], workdir, f'full_{family}')
        lite_s, lite_n = time_variant(
            args, drop, [d for d in INJECTED if d in keep], [family], workdir, f'lite_{family}')
        est_full = counts[family] * full_s / max(full_n, 1)
        est_lite = counts[family] * lite_s / max(lite_n, 1)
        total_full += est_full
        total_lite += est_lite
        print(f'{family:16}{counts[family]:7}{est_full:9.1f}s{est_lite:9.1f}s')

    print('-' * 43)
    print(f'{"TOTAL":16}{sum(counts[f] for f in families):7}{total_full:9.1f}s{total_lite:9.1f}s')
    if total_full:
        print(f'\n  lite vs full: {100 * (total_full - total_lite) / total_full:+.1f}%')
    print('\nExtrapolated from a sample at fixed parallelism; treat as a ratio, not a clock.')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('mode', choices=['ablate', 'compare'])
    ap.add_argument('--repo', default='.')
    ap.add_argument('--config', default='.github/configs/shader-validation.yaml')
    ap.add_argument('--shader-dir', required=True, help='built shader tree, e.g. build/LITE/aio/Shaders')
    ap.add_argument('--hlslkit', required=True, help='path to hlslkit-compile')
    ap.add_argument('--fxc', required=True, help='path to fxc.exe')
    ap.add_argument('--files', default='Lighting.hlsl', help='ablate: which shader file (default Lighting.hlsl)')
    ap.add_argument('--sample', type=int, default=50, help='entries per stage')
    ap.add_argument('--jobs', type=int, default=8)
    ap.add_argument('--repeat', type=int, default=2, help='runs per variant; the fastest is kept')
    ap.add_argument('--seed', type=int, default=1234)
    args = ap.parse_args()

    require_full_shader_tree(args.repo, args.shader_dir)

    workdir = tempfile.mkdtemp(prefix='lite-shader-bench-')
    try:
        if args.mode == 'ablate':
            run_ablate(args, workdir)
        else:
            run_compare(args, workdir)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == '__main__':
    main()
