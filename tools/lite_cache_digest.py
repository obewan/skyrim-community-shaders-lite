"""Compute or compare the shader-tree digest used to validate the bundled shader cache.

An independent implementation of shader_tree_digest() from cmake/ShaderTreeDigest.cmake.
Two uses:

  * Cross-check the CMake function, whose whole job is to be trusted.
  * Pre-flight the SNAPSHOT_LITE_CACHE check before a ~9 minute compile run: if the
    deployed Data/Shaders does not match the build, the snapshot will be refused, and
    it is cheaper to find that out first.

Examples:
    python tools/lite_cache_digest.py build/LITE/aio/Shaders
    python tools/lite_cache_digest.py build/LITE/aio/Shaders "<Skyrim>/Data/Shaders"
"""

import hashlib
import os
import sys

BACKSLASH = chr(92)  # kept out of a literal so the file survives shell heredocs


def shader_tree_digest(root):
    """Return (digest, file count). Must match cmake/ShaderTreeDigest.cmake exactly."""
    if not os.path.isdir(root):
        return None, 0

    files = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            if name.endswith(('.hlsl', '.hlsli')):
                files.append(os.path.join(dirpath, name))
    files.sort()

    accumulated = ''
    for path in files:
        rel = os.path.relpath(path, root).replace(BACKSLASH, '/')
        with open(path, 'rb') as fh:
            file_hash = hashlib.sha256(fh.read()).hexdigest()
        accumulated += f'{rel}:{file_hash}\n'

    return hashlib.sha256(accumulated.encode()).hexdigest(), len(files)


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)

    build_digest, build_count = shader_tree_digest(sys.argv[1])
    if build_digest is None:
        sys.exit(f'no shader tree at {sys.argv[1]}')
    print(f'{sys.argv[1]}: {build_digest}:{build_count}')

    if len(sys.argv) == 2:
        return

    other_digest, other_count = shader_tree_digest(sys.argv[2])
    if other_digest is None:
        sys.exit(f'no shader tree at {sys.argv[2]}')
    print(f'{sys.argv[2]}: {other_digest}:{other_count}')
    print()

    if (build_digest, build_count) == (other_digest, other_count):
        print('MATCH -> snapshot will be accepted')
    else:
        print('MISMATCH -> snapshot would be refused; deploy this build and re-run the game')
        sys.exit(1)


if __name__ == '__main__':
    main()
