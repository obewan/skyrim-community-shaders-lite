# Detects whether compiled shader blobs carry debug info.
#
# Raising the Community Shaders log level to debug makes State::IsDeveloperMode()
# true, which swaps D3DCOMPILE_ENABLE_STRICTNESS|OPTIMIZATION_LEVEL3 for plain
# D3DCOMPILE_DEBUG. The resulting cache is unoptimized and must never be shipped,
# but nothing in Info.ini records it -- it only records versions. The evidence is
# in the blobs themselves: a debug compile emits an extra DXBC chunk (SDBG/SPDB/
# ILDB) that an optimized build does not.
#
# Compile flags are per-run, so every blob in a cache shares them. Sampling a
# spread of files is therefore conclusive and keeps the scan cheap.

# "aabbccdd" (little-endian hex bytes) -> integer 0xddccbbaa
function(_dxbc_le32 _hex _out)
    string(SUBSTRING "${_hex}" 0 2 _b0)
    string(SUBSTRING "${_hex}" 2 2 _b1)
    string(SUBSTRING "${_hex}" 4 2 _b2)
    string(SUBSTRING "${_hex}" 6 2 _b3)
    math(EXPR _v "0x${_b3}${_b2}${_b1}${_b0}")
    set(${_out} "${_v}" PARENT_SCOPE)
endfunction()

# scan_shader_blobs_for_debug_info(<dir> <max_samples> <out_bad> <out_scanned> <out_example>)
function(scan_shader_blobs_for_debug_info _dir _max_samples _out_bad _out_scanned _out_example)
    set(_bad 0)
    set(_scanned 0)
    set(_example "")

    file(GLOB_RECURSE _blobs LIST_DIRECTORIES FALSE "${_dir}/*.pso" "${_dir}/*.vso")
    list(LENGTH _blobs _total)
    if(_total EQUAL 0)
        set(${_out_bad} 0 PARENT_SCOPE)
        set(${_out_scanned} 0 PARENT_SCOPE)
        set(${_out_example} "" PARENT_SCOPE)
        return()
    endif()

    # Walk the list with a stride so the sample spans the whole tree rather than
    # just the first directory, which would only cover one shader type.
    math(EXPR _stride "(${_total} + ${_max_samples} - 1) / ${_max_samples}")
    if(_stride LESS 1)
        set(_stride 1)
    endif()

    set(_i 0)
    foreach(_blob IN LISTS _blobs)
        math(EXPR _take "${_i} % ${_stride}")
        math(EXPR _i "${_i} + 1")
        if(NOT _take EQUAL 0)
            continue()
        endif()

        file(READ "${_blob}" _hex HEX)
        string(LENGTH "${_hex}" _hexlen)
        if(_hexlen LESS 64)
            continue()
        endif()
        # "DXBC"
        string(SUBSTRING "${_hex}" 0 8 _magic)
        if(NOT _magic STREQUAL "44584243")
            continue()
        endif()

        # chunk count is a little-endian u32 at byte offset 28
        string(SUBSTRING "${_hex}" 56 8 _count_hex)
        _dxbc_le32("${_count_hex}" _chunks)

        math(EXPR _table_end "(32 + 4 * ${_chunks}) * 2")
        if(_hexlen LESS _table_end)
            continue()
        endif()

        math(EXPR _scanned "${_scanned} + 1")

        set(_k 0)
        while(_k LESS _chunks)
            math(EXPR _pos "(32 + 4 * ${_k}) * 2")
            string(SUBSTRING "${_hex}" ${_pos} 8 _off_hex)
            _dxbc_le32("${_off_hex}" _off)
            math(EXPR _fourcc_pos "${_off} * 2")
            math(EXPR _fourcc_end "${_fourcc_pos} + 8")
            if(_hexlen GREATER_EQUAL _fourcc_end)
                string(SUBSTRING "${_hex}" ${_fourcc_pos} 8 _fourcc)
                # SDBG / SPDB / ILDB
                if(_fourcc STREQUAL "53444247"
                   OR _fourcc STREQUAL "53504442"
                   OR _fourcc STREQUAL "494c4442")
                    math(EXPR _bad "${_bad} + 1")
                    if(NOT _example)
                        set(_example "${_blob}")
                    endif()
                    break()
                endif()
            endif()
            math(EXPR _k "${_k} + 1")
        endwhile()
    endforeach()

    set(${_out_bad} "${_bad}" PARENT_SCOPE)
    set(${_out_scanned} "${_scanned}" PARENT_SCOPE)
    set(${_out_example} "${_example}" PARENT_SCOPE)
endfunction()
