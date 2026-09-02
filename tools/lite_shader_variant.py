"""Generate a shader-validation config variant with a chosen feature-define set applied.

Mirrors the runtime: Feature::GetLightingShaderDefines appends one #define per *loaded*
feature, so disabling a feature in the lite profile is equivalent to removing its define
from every shader's common_defines. That makes the captured permutations in
.github/configs/shader-validation.yaml a reproducible corpus for measuring what a
profile costs to compile, without launching the game.

Used by lite_shader_bench.py; also usable directly to produce a config for
hlslkit-compile.
"""

import argparse
import copy
import random
import sys

import yaml


def strip_defines(defines, drop):
    """Drop entries whose name (before any '=') is in `drop`."""
    return [d for d in (defines or []) if d.split('=')[0] not in drop]


def build_variant(config_path, drop, add, keep_files, sample, seed, release_flags):
    """Return (config dict, kept entry count, total matching entry count)."""
    drop = set(drop)
    add = [d for d in add if d not in drop]
    if release_flags:
        # The captured config is a CI debug config. Timings only mean something at the
        # flags the shipping build uses, so strip the debug defines.
        drop |= {'D3DCOMPILE_DEBUG', 'D3DCOMPILE_SKIP_OPTIMIZATION'}

    with open(config_path) as fh:
        cfg = yaml.safe_load(fh)

    cfg['common_defines'] = strip_defines(cfg.get('common_defines'), drop)
    for _file, stages in (cfg.get('file_common_defines') or {}).items():
        for stage in stages:
            stages[stage] = strip_defines(stages[stage], drop)

    rng = random.Random(seed)
    out_shaders, kept, total = [], 0, 0
    for shader in cfg.get('shaders') or []:
        if keep_files and shader['file'] not in keep_files:
            continue
        shader = copy.deepcopy(shader)
        for _stage, conf in (shader.get('configs') or {}).items():
            common = strip_defines(conf.get('common_defines'), drop)
            common += [d for d in add if d not in common]
            conf['common_defines'] = common

            entries = conf.get('entries') or []
            total += len(entries)
            if sample and len(entries) > sample:
                # Deterministic subsample so the same entries are used for every
                # variant; otherwise variant-to-variant deltas measure the sample,
                # not the defines.
                entries = sorted(rng.sample(entries, sample), key=lambda e: e['entry'])
            for entry in entries:
                entry['defines'] = strip_defines(entry.get('defines'), drop)
            conf['entries'] = entries
            kept += len(entries)
        out_shaders.append(shader)
    cfg['shaders'] = out_shaders
    return cfg, kept, total


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--config', required=True, help='shader-validation.yaml to derive from')
    ap.add_argument('--out', required=True)
    ap.add_argument('--drop', default='', help='comma-separated defines to remove')
    ap.add_argument(
        '--add',
        default='',
        help='comma-separated defines to add to every stage; needed for features a full '
        'install loads but the captured log never exercised',
    )
    ap.add_argument('--files', default='', help='comma-separated shader files to keep (default: all)')
    ap.add_argument('--sample', type=int, default=0, help='max entries per stage (0 = all)')
    ap.add_argument('--seed', type=int, default=1234)
    ap.add_argument(
        '--release-flags',
        action='store_true',
        help='drop the debug defines so timings match the shipping build',
    )
    args = ap.parse_args()

    csv = lambda s: [x.strip() for x in s.split(',') if x.strip()]  # noqa: E731
    cfg, kept, total = build_variant(
        args.config, csv(args.drop), csv(args.add), set(csv(args.files)),
        args.sample, args.seed, args.release_flags,
    )

    with open(args.out, 'w') as fh:
        yaml.safe_dump(cfg, fh, default_flow_style=False, sort_keys=False)
    print(f'{args.out}: {kept} of {total} matching entries', file=sys.stderr)


if __name__ == '__main__':
    main()
