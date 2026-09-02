# Snapshots a game-generated shader cache into the repo for bundling.
#
# Run after launching the game once with the lite profile, so Data/ShaderCache
# holds a full set of compiled shaders and a matching Info.ini. Copies both into
# LITE_SHADER_CACHE_DIR and records a digest of the shader tree the cache was
# built from, which StageShaderCache.cmake later compares against the shaders
# being packaged.
#
# Required: CACHE_SRC (the game's Data/ShaderCache), CACHE_DEST, SHADER_DIR
# (the shader tree that produced it, i.e. the AIO's Shaders folder).

foreach(_required CACHE_SRC CACHE_DEST SHADER_DIR)
    if(NOT DEFINED ${_required})
        message(FATAL_ERROR "SnapshotShaderCache.cmake requires ${_required}")
    endif()
endforeach()

if(NOT IS_DIRECTORY "${CACHE_SRC}")
    message(
        FATAL_ERROR
        "No shader cache at ${CACHE_SRC}.\n"
        "Launch the game once with the lite profile installed, let compilation "
        "finish, then re-run this target.\n"
        "Set the path with -DLITE_GAME_SHADERCACHE=<Skyrim>/Data/ShaderCache."
    )
endif()

if(NOT EXISTS "${CACHE_SRC}/Info.ini")
    message(
        FATAL_ERROR
        "${CACHE_SRC} has no Info.ini, so the runtime never finished writing the "
        "cache. Let shader compilation complete before snapshotting."
    )
endif()

include("${CMAKE_CURRENT_LIST_DIR}/ShaderTreeDigest.cmake")
shader_tree_digest("${SHADER_DIR}" _digest)
if(NOT _digest)
    message(FATAL_ERROR "No shader tree at ${SHADER_DIR}; build the lite package first.")
endif()

# The recorded digest describes SHADER_DIR (what this build ships), but the
# blobs come from whatever the game actually compiled. If the deployed shaders
# differ from this build's, snapshotting would pair new shaders with old blobs
# and stamp that mismatch as valid -- defeating the whole guard. Data/Shaders
# sits beside Data/ShaderCache, so compare the two directly.
get_filename_component(_game_data "${CACHE_SRC}" DIRECTORY)
set(_game_shaders "${_game_data}/Shaders")
if(IS_DIRECTORY "${_game_shaders}")
    shader_tree_digest("${_game_shaders}" _deployed_digest)
    if(NOT "${_deployed_digest}" STREQUAL "${_digest}")
        message(
            FATAL_ERROR
            "The deployed shaders at ${_game_shaders} do not match this build's "
            "(${SHADER_DIR}), so the cache in ${CACHE_SRC} was compiled from different "
            "source.\n"
            "Deploy this build, delete Data/ShaderCache, launch the game once and let "
            "compilation finish, then re-run this target.\n"
            "  deployed: ${_deployed_digest}\n"
            "  building: ${_digest}"
        )
    endif()
else()
    message(
        WARNING
        "No deployed shaders at ${_game_shaders}; cannot confirm the cache was built "
        "from this build's shaders. Snapshotting anyway."
    )
endif()

file(REMOVE_RECURSE "${CACHE_DEST}")
file(COPY "${CACHE_SRC}/" DESTINATION "${CACHE_DEST}")
file(WRITE "${CACHE_DEST}.digest" "${_digest}\n")

file(GLOB_RECURSE _copied LIST_DIRECTORIES FALSE "${CACHE_DEST}/*")
list(LENGTH _copied _copied_count)
message(STATUS "Snapshotted ${_copied_count} cache files into ${CACHE_DEST}")
message(STATUS "Recorded shader digest ${_digest}")
