# Compares a shader cache's Info.ini against the feature state a build expects.
#
# Info.ini is what the runtime checks in Feature::ValidateCache: it records each
# feature's Enabled (which mirrors Feature::loaded, not the boot toggle) and its
# Version, plus the plugin version. On any mismatch the runtime calls
# remove_all("Data/ShaderCache") and recompiles everything, so a cache that
# disagrees with the build is strictly worse than shipping none at all.
#
# Shared by StageShaderCache.cmake (refuses to package such a cache) and
# SnapshotShaderCache.cmake (refuses to record one in the first place). Kept in
# one place because the two must agree exactly -- a snapshot the packaging step
# would later reject is a wasted regeneration run, and regenerating means a full
# game launch.
#
# cache_info_problems(<cache_dir> <expect_file> <out_var>)
#   <cache_dir>   directory holding Info.ini
#   <expect_file> lines of "PluginVersion|<version>" or "<Feature>|<enabled>[|<version>]",
#                 where <enabled> is "true", "false", or "gated" for a feature
#                 whose Enabled depends on the player's setup (an external plugin
#                 being installed, a mod conflict) and so cannot be asserted --
#                 its version is still compared
#   <out_var>     set to a list of human-readable problems, empty when they agree
function(cache_info_problems _cache_dir _expect_file _out_var)
    set(_problems "")

    if(NOT EXISTS "${_cache_dir}/Info.ini")
        list(APPEND _problems "no Info.ini in ${_cache_dir}")
        set(${_out_var} "${_problems}" PARENT_SCOPE)
        return()
    endif()

    # Parse Info.ini into _ini_<Section>_<Key> variables. Done line-wise rather
    # than by regex over the whole file because the file starts with a BOM and
    # CMake regexes have no multiline mode.
    file(STRINGS "${_cache_dir}/Info.ini" _ini_lines)
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

    file(STRINGS "${_expect_file}" _expect_lines)
    foreach(_line IN LISTS _expect_lines)
        string(REPLACE "|" ";" _parts "${_line}")
        list(GET _parts 0 _name)
        if(_name STREQUAL "PluginVersion")
            list(GET _parts 1 _want_version)
            if(NOT "${_ini_Cache_PluginVersion}" STREQUAL "${_want_version}")
                list(
                    APPEND _problems
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
                list(APPEND _problems "${_name}: missing from cache Info.ini")
            elseif(_want_enabled STREQUAL "gated")
                # Enabled is the player's business here, but the runtime records
                # the version either way, so that much stays checkable.
                if(_want_version
                   AND _have_version
                   AND NOT "${_have_version}" STREQUAL "${_want_version}"
                )
                    list(
                        APPEND _problems
                        "${_name}: cache built against ${_have_version}, shipping ${_want_version}"
                    )
                endif()
            elseif(NOT "${_have_enabled}" STREQUAL "${_want_enabled}")
                list(
                    APPEND _problems
                    "${_name}: cache says Enabled=${_have_enabled}, profile says ${_want_enabled}"
                )
            elseif(_want_enabled STREQUAL "true" AND NOT "${_have_version}" STREQUAL "${_want_version}")
                list(
                    APPEND _problems
                    "${_name}: cache built against ${_have_version}, shipping ${_want_version}"
                )
            endif()
        endif()
    endforeach()

    set(${_out_var} "${_problems}" PARENT_SCOPE)
endfunction()
