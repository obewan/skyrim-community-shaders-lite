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

# Guard against shipping a cache the runtime will reject. ValidateDiskCache
# compares Info.ini's PluginVersion and every feature's Enabled/Version against
# the running build and, on any mismatch, calls remove_all("Data/ShaderCache")
# and recompiles everything -- so a stale bundled cache is strictly worse than
# none: users download it, it is deleted on first launch, and they compile
# anyway. Fail the build instead, because that failure is otherwise silent.
if(DEFINED EXPECT_FILE AND EXISTS "${EXPECT_FILE}")
    # Parse Info.ini into _ini_<Section>_<Key> variables. Done line-wise rather
    # than by regex over the whole file because the file starts with a BOM and
    # CMake regexes have no multiline mode.
    file(STRINGS "${CACHE_SRC}/Info.ini" _ini_lines)
    set(_section "")
    foreach(_line IN LISTS _ini_lines)
        if(_line MATCHES "^[^[]*\\[([^]]+)\\]")
            set(_section "${CMAKE_MATCH_1}")
        elseif(_section AND _line MATCHES "^[ \t]*([A-Za-z]+)[ \t]*=[ \t]*(.*)$")
            set(_key "${CMAKE_MATCH_1}")
            string(STRIP "${CMAKE_MATCH_2}" _value)
            set("_ini_${_section}_${_key}" "${_value}")
        endif()
    endforeach()

    set(_cache_problems "")
    file(STRINGS "${EXPECT_FILE}" _expect_lines)
    foreach(_line IN LISTS _expect_lines)
        string(REPLACE "|" ";" _parts "${_line}")
        list(GET _parts 0 _name)
        if(_name STREQUAL "PluginVersion")
            list(GET _parts 1 _want_version)
            if(NOT "${_ini_Cache_PluginVersion}" STREQUAL "${_want_version}")
                list(
                    APPEND _cache_problems
                    "plugin version: cache has '${_ini_Cache_PluginVersion}', build is '${_want_version}'"
                )
            endif()
        else()
            list(GET _parts 1 _want_enabled)
            set(_want_version "")
            list(LENGTH _parts _part_count)
            if(_part_count GREATER 2)
                list(GET _parts 2 _want_version)
            endif()
            # Test definedness, not truthiness: a disabled feature's value is the
            # string "false", which CMake's if() treats as boolean false and would
            # misreport as a missing entry.
            set(_enabled_var "_ini_${_name}_Enabled")
            set(_version_var "_ini_${_name}_Version")
            set(_have_enabled "${${_enabled_var}}")
            set(_have_version "${${_version_var}}")
            if(NOT DEFINED ${_enabled_var})
                list(APPEND _cache_problems "${_name}: missing from cache Info.ini")
            elseif(NOT "${_have_enabled}" STREQUAL "${_want_enabled}")
                list(
                    APPEND _cache_problems
                    "${_name}: cache says Enabled=${_have_enabled}, profile says ${_want_enabled}"
                )
            elseif(_want_enabled STREQUAL "true" AND NOT "${_have_version}" STREQUAL "${_want_version}")
                list(
                    APPEND _cache_problems
                    "${_name}: cache built against ${_have_version}, shipping ${_want_version}"
                )
            endif()
        endif()
    endforeach()

    list(LENGTH _cache_problems _cache_problem_count)
    if(_cache_problem_count GREATER 0)
        string(REPLACE ";" "\n    " _cache_problem_text "${_cache_problems}")
        set(_cache_message
            "Precompiled shader cache at ${CACHE_SRC} does not match this build:\n"
            "    ${_cache_problem_text}\n"
            "The runtime would delete it on first launch and recompile everything, so users "
            "would download it for nothing. Regenerate it: build, run the game once with the "
            "lite profile, then copy Data/ShaderCache over ${CACHE_SRC}.\n"
            "To ship without a cache, point LITE_SHADER_CACHE_DIR elsewhere. To bypass this "
            "check for local iteration, configure with -DLITE_CACHE_REQUIRE_MATCH=OFF."
        )
        string(REPLACE ";" "" _cache_message "${_cache_message}")
        if(REQUIRE_MATCH)
            message(FATAL_ERROR "${_cache_message}")
        else()
            message(WARNING "${_cache_message}")
        endif()
    endif()
endif()

set(_dest "${AIO_DIR}/ShaderCache")
file(COPY "${CACHE_SRC}/" DESTINATION "${_dest}")

file(GLOB_RECURSE _staged LIST_DIRECTORIES FALSE "${_dest}/*")
list(LENGTH _staged _staged_count)
if(_staged_count GREATER 0)
    file(TOUCH_NOCREATE ${_staged})
endif()

message(STATUS "Staged ${_staged_count} precompiled shader cache files into ${_dest}")
