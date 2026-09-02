# Content digest of a shipped shader tree, used to detect a precompiled shader
# cache that no longer matches the shaders beside it.
#
# The version guard in StageShaderCache.cmake only catches plugin and feature
# version changes. A shader-only fix -- an upstream .hlsl change with no version
# bump -- passes it, and the runtime's own mtime check cannot catch it either
# because staging deliberately touches the cache newer than the sources. Without
# a content digest such a build ships the fix in source while rendering from
# stale blobs, with nothing to indicate it.
#
# Hashes .hlsl/.hlsli only: feature .ini version changes are already covered by
# the version guard, and other files in the tree do not affect compiled output.

function(shader_tree_digest _dir _out_var)
    if(NOT IS_DIRECTORY "${_dir}")
        set(${_out_var} "" PARENT_SCOPE)
        return()
    endif()

    file(GLOB_RECURSE _files LIST_DIRECTORIES FALSE "${_dir}/*.hlsl" "${_dir}/*.hlsli")
    list(SORT _files)

    set(_accumulated "")
    foreach(_file IN LISTS _files)
        file(RELATIVE_PATH _rel "${_dir}" "${_file}")
        file(SHA256 "${_file}" _file_hash)
        string(APPEND _accumulated "${_rel}:${_file_hash}\n")
    endforeach()

    string(SHA256 _digest "${_accumulated}")
    list(LENGTH _files _count)
    # Carry the file count so a mismatch can say whether shaders were added or
    # removed rather than only edited.
    set(${_out_var} "${_digest}:${_count}" PARENT_SCOPE)
endfunction()
