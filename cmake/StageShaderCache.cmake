# Stages a precompiled shader cache into the AIO package.
#
# The runtime accepts a disk-cached shader only when Data/ShaderCache/Info.ini
# matches the plugin version and every feature's Enabled/Version state, and --
# with "Skip Unchanged Shaders" on, which is the default -- only when the cached
# blob is not older than its .hlsl source (ShaderCache.cpp, CompileShader).
#
# Copying preserves source timestamps, and the staged cache is generated from an
# earlier build, so its files would look older than the shaders shipped beside
# them and be discarded wholesale. Touching them after the copy fixes that while
# keeping the safety property intact: a shader file installed *later* by another
# mod is still newer than the cache, so the affected shaders recompile rather
# than silently rendering from a stale blob.
#
# Required: CACHE_SRC (staged cache dir), AIO_DIR (package root).

if(NOT DEFINED CACHE_SRC)
    message(FATAL_ERROR "StageShaderCache.cmake requires CACHE_SRC")
endif()

if(NOT DEFINED AIO_DIR)
    message(FATAL_ERROR "StageShaderCache.cmake requires AIO_DIR")
endif()

if(NOT IS_DIRECTORY "${CACHE_SRC}")
    message(STATUS "No precompiled shader cache at ${CACHE_SRC}; skipping")
    return()
endif()

if(NOT EXISTS "${CACHE_SRC}/Info.ini")
    # Without Info.ini the runtime logs "Disk cache outdated: no plugin version
    # found" and deletes the whole cache on first launch, so shipping one would
    # be pure download weight.
    message(
        WARNING
        "Precompiled shader cache at ${CACHE_SRC} has no Info.ini; refusing to stage it. "
        "Generate it by running the game once with the lite profile."
    )
    return()
endif()

set(_dest "${AIO_DIR}/ShaderCache")
file(COPY "${CACHE_SRC}/" DESTINATION "${_dest}")

file(GLOB_RECURSE _staged LIST_DIRECTORIES FALSE "${_dest}/*")
list(LENGTH _staged _staged_count)
if(_staged_count GREATER 0)
    file(TOUCH_NOCREATE ${_staged})
endif()

message(STATUS "Staged ${_staged_count} precompiled shader cache files into ${_dest}")
