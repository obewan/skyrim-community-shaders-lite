"""Generate the lite profile's SettingsDefault.json from a keep-list of features.

A feature named in "Disable at Boot" never reaches Feature::Load (State.cpp), so it
contributes no shader #define (ShaderCache.cpp GetLightingShaderDefines) and its folder
is dropped from the lite package (CMakeLists.txt, LITE_PACKAGE). Users can re-enable
anything from the in-game menu, so this is a default rather than a removal.

Feature names are the .ini basenames, which differ from the folder names
("Light Limit Fix" -> LightLimitFix, "IBL" -> ImageBasedLighting); unknown names are
rejected rather than silently ignored.

Example:
    python tools/lite_profile.py --keep LightLimitFix,Skylighting,... \\
        --out package/SKSE/Plugins/CommunityShaders/SettingsDefault.json
"""

import argparse
import json
import os
import sys


def feature_short_names(repo):
    """Map short name (the .ini basename Feature::Load looks for) -> feature folder."""
    names = {}
    features_dir = os.path.join(repo, 'features')
    for folder in sorted(os.listdir(features_dir)):
        config_dir = os.path.join(features_dir, folder, 'Shaders', 'Features')
        if not os.path.isdir(config_dir):
            continue
        for fn in os.listdir(config_dir):
            if fn.endswith('.ini'):
                names[fn[:-4]] = folder
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--repo', default='.')
    ap.add_argument('--keep', required=True, help='comma-separated feature short names to leave enabled')
    ap.add_argument('--out', required=True)
    ap.add_argument('--merge', default='', help='existing SettingsDefault.json to merge into')
    args = ap.parse_args()

    known = feature_short_names(args.repo)
    keep = {k.strip() for k in args.keep.split(',') if k.strip()}

    unknown = sorted(keep - set(known))
    if unknown:
        sys.exit(
            f'unknown feature short names {unknown}; '
            'check spelling against features/*/Shaders/Features/*.ini'
        )

    settings = {}
    if args.merge and os.path.exists(args.merge):
        with open(args.merge) as fh:
            settings = json.load(fh)

    settings['Disable at Boot'] = {name: (name not in keep) for name in sorted(known)}

    # newline='\n': .gitattributes normalises the repo to LF, and Python's text mode
    # would otherwise write CRLF on Windows, making every regeneration a whole-file diff.
    with open(args.out, 'w', newline='\n') as fh:
        json.dump(settings, fh, indent=2)
        fh.write('\n')

    disabled = sorted(n for n in known if n not in keep)
    print(f'wrote {args.out}', file=sys.stderr)
    print(f'  enabled  ({len(keep)}): {", ".join(sorted(keep))}', file=sys.stderr)
    print(f'  disabled ({len(disabled)}): {", ".join(disabled)}', file=sys.stderr)


if __name__ == '__main__':
    main()
