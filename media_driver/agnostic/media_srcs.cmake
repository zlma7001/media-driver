# Copyright (c) 2017-2021, Intel Corporation
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

if (BUILD_KERNELS)
    # Here we define build steps to generate c-array binary shaders (kernels)
    # and their header files. If you don't use BUILD_KERNELS option these
    # kernels will just be used from pre-built form. If you will regenerate
    # kernels you may notice the difference from the per-built kernels in git-diff.

    function(platform_to_genx platform genx kind)
        if(platform STREQUAL "gen11")
            set(genx "11" PARENT_SCOPE)
            set(kind "" PARENT_SCOPE)
        elseif(platform STREQUAL "gen11_icllp")
            set(genx "11" PARENT_SCOPE)
            set(kind "icllp" PARENT_SCOPE)
        elseif(platform STREQUAL "gen12_tgllp")
            set(genx "12" PARENT_SCOPE)
            set(kind "tgllp" PARENT_SCOPE)
        endif()
    endfunction()

    

    # This function describes object files generated by cmc from the given input cm-file.
    # If cm-file has changed, it may be required to adjust this function.
    function(get_cm_dat_objs file objs)
        get_filename_component(name ${src} NAME)
        if(name STREQUAL "downscale_kernel_genx.cpp")
            set(objs
                downscale_kernel_genx_0.dat
                downscale_kernel_genx_1.dat
                PARENT_SCOPE)
        elseif(name STREQUAL "hme_kernel_genx.cpp")
            set(objs
                hme_kernel_genx_0.dat
                hme_kernel_genx_1.dat
                hme_kernel_genx_2.dat
                PARENT_SCOPE)
        elseif(name STREQUAL "downscale_convert_kernel_genx.cpp")
            set(objs
                downscale_convert_kernel_genx_0.dat
                PARENT_SCOPE)
        else()
            set(objs "" PARENT_SCOPE)
        endif()
    endfunction()

    # Function parses the given c-file and extracts the value from the defined macro.
    # Parser expects the first occurence in the following format:
    #   "#define name xxx" - whitespaces are important!!
    function(get_c_macro_int file name value)
        file(STRINGS ${file} value_str REGEX "#define ${name}" LIMIT_COUNT 1)
        if(value_str STREQUAL "") # old style version
            message(FATAL_ERROR "Failed to find macro ${name} in the file: ${file}")
        endif()
        string(REPLACE "#define ${name} " "" value_str ${value_str})
        set(${value} ${value_str} PARENT_SCOPE)
    endfunction()

    # Function generates kernel for the specified platform. It assumes that generated
    # kernel should be placed in the certain directory (see ${krn_dir}).
    function(gen_kernel_from_cm name platform index sources)
        platform_to_genx(${platform} genx kind)

        set(krn ig${name}krn_g${genx})
        set(krn_dir ${CMAKE_SOURCE_DIR}/media_driver/agnostic/${platform}/codec/kernel_free)
        set(out_dir "${CMAKE_CURRENT_BINARY_DIR}/kernels/codec/${platform}")

        message("krn: ${krn}")
        message("krn_dir: ${krn_dir}")
        message("out_dir: ${out_dir}")

        add_custom_command(
            OUTPUT ${out_dir}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${out_dir}
            COMMENT "Create codec kernels output directory: ${out_dir}")

        # Compiling all the given sources
        set(dats "")
        set(cm_genx ${platform})
        if(cm_genx STREQUAL "gen11")
            # Forcing gen11lp platform for the whole gen11 family since LP instruction set
            # is a subset of other platforms in the family.
            set(cm_genx "gen11lp")
        endif()
        foreach(src ${sources})
            get_cm_dat_objs(${src} objs) # there are other otputs from cmc command, but we use only .dat
            add_custom_command(
                OUTPUT ${objs}
                DEPENDS ${out_dir} ${src}
                WORKING_DIRECTORY ${out_dir}
                COMMAND ${CMC}
                    -c -Qxcm -Qxcm_jit_target=${cm_genx}
                    -mCM_emit_common_isa -mCM_no_input_reorder -mCM_jit_option="-nocompaction"
                    ${src}
                COMMENT "Compiling ${src}..."        
            )
            set(dats ${dats} ${objs})
        endforeach()

        # Generating source from the .krn file
        get_c_macro_int(${CMAKE_CURRENT_LIST_DIR}/common/codec/kernel/codeckrnheader.h
            "IDR_CODEC_TOTAL_NUM_KERNELS" IDR_CODEC_TOTAL_NUM_KERNELS)
        add_custom_command(
            OUTPUT ${krn_dir}/${krn}.c ${krn_dir}/${krn}.h
            DEPENDS KernelBinToSource ${CMAKE_CURRENT_LIST_DIR}/common/codec/kernel/merge.py ${dats}
            WORKING_DIRECTORY ${out_dir}
            COMMAND ${PYTHON} ${CMAKE_CURRENT_LIST_DIR}/common/codec/kernel/merge.py -o ${krn}.krn ${dats}
            # ${index} is needed to match a description in the following file:
            #   media_driver/agnostic/common/codec/kernel/codeckrnheader.h
            COMMAND KernelBinToSource -i ${krn}.krn -o ${krn_dir}/ -v ${krn} -index ${index} -t ${IDR_CODEC_TOTAL_NUM_KERNELS}
            COMMENT "Generate source file from krn")
    endfunction()

    # Function generates vp cmfc kernel for the specified platform. It assumes that generated
    # kernel should be placed in the certain directory (see ${krn_dir}).
    function(gen_vpkernel_from_cm name platform)
        platform_to_genx(${platform} genx kind)

        set(krn ig${name}krn_g${genx}_${kind}_cmfc)
        set(krnpatch ig${name}krn_g${genx}_${kind}_cmfcpatch)
        set(krn_dir ${CMAKE_SOURCE_DIR}/media_driver/agnostic/${platform}/vp/kernel_free)
        set(link_file ${krn_dir}/component_release/LinkFile.txt)
        set(out_dir ${CMAKE_SOURCE_DIR}/media_driver/agnostic/${platform}/vp/kernel_free/cache_kernel)
        set(kernel_dir ${out_dir}/kernel)
        set(patch_dir ${out_dir}/fcpatch)
        set(kernel_hex_dir ${kernel_dir}/hex)
        set(patch_hex_dir ${patch_dir}/hex)
        set(krn_header ${CMAKE_CURRENT_LIST_DIR}/common/vp/kernel/${name}krnheader.h)

        add_custom_command(
            OUTPUT ${out_dir} ${kernel_dir} ${patch_dir} ${kernel_hex_dir} ${patch_hex_dir}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${out_dir}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${kernel_dir}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${patch_dir}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${kernel_hex_dir}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${patch_hex_dir}
            COMMENT "Creating VP cmfc kernels output directory")

        # Compiling all the sources in the kernel source directory.
        file(GLOB_RECURSE srcs ${krn_dir}/Source/*.cpp)

        set(objsname "")
        set(cm_genx ${kind})

        foreach(src ${srcs})
            get_filename_component(obj ${src} NAME_WE) # there are other outputs from cmc command, but we use only .dat and .fcpatch
            if(obj STREQUAL "EOT" OR obj STREQUAL "Secure_Block_Copy") # "EOT" and "Secure_Block_Copy" don't generate the related .fcpatch file.
            add_custom_command(
                OUTPUT ${out_dir}/${obj}_0.dat
                DEPENDS ${src} ${out_dir}
                WORKING_DIRECTORY ${out_dir}
                COMMAND ${CMC}
                    -c -Qxcm -Qxcm_jit_target=${cm_genx} -I ${krn_dir}/Source/ -I ${krn_dir}/Source/Common -I ${krn_dir}/Source/Components
                    -I ${krn_dir}/Source/Core_Kernels -Qxcm_jit_option="-nocompaction" -mCM_emit_common_isa -mCM_no_input_reorder -mCM_unique_labels=MDF_FC -mCM_printregusage
                    ${src})
            else()
            add_custom_command(
                OUTPUT ${out_dir}/${obj}_0.dat ${out_dir}/${obj}.fcpatch
                DEPENDS ${src} ${out_dir}
                WORKING_DIRECTORY ${out_dir}
                COMMAND ${CMC}
                    -c -Qxcm -Qxcm_jit_target=${cm_genx} -I ${krn_dir}/Source/ -I ${krn_dir}/Source/Common -I ${krn_dir}/Source/Components
                    -I ${krn_dir}/Source/Core_Kernels -Qxcm_jit_option="-nocompaction" -mCM_emit_common_isa -mCM_no_input_reorder -mCM_unique_labels=MDF_FC -mCM_printregusage
                    ${src})
            endif()
            set(objsname ${objsname} ${obj})
        endforeach()

        #Generate the .hex files from the .dat files by using KrnToHex.
        set(hexs "")

         foreach(objname ${objsname})
            add_custom_command(
            OUTPUT ${kernel_dir}/${objname}.krn
            DEPENDS ${out_dir}/${objname}_0.dat ${kernel_dir}
            WORKING_DIRECTORY ${out_dir}
            COMMAND ${CMAKE_COMMAND} -E copy ${out_dir}/${objname}_0.dat ${kernel_dir}/${objname}.krn
            )
         endforeach()

         foreach(objname ${objsname})
            add_custom_command(
            OUTPUT ${kernel_hex_dir}/${objname}.hex
            DEPENDS KrnToHex ${kernel_dir}/${objname}.krn ${kernel_hex_dir}
            WORKING_DIRECTORY ${kernel_dir}
            COMMAND KrnToHex ${kernel_dir}/${objname}.krn
            COMMAND ${CMAKE_COMMAND} -E copy ${kernel_dir}/${objname}.hex ${kernel_hex_dir}/${objname}.hex
            COMMAND ${CMAKE_COMMAND} -E remove ${kernel_dir}/${objname}.hex
            COMMENT "Generate the hex files of cmfc kernel")
            set(hexs ${hexs} ${kernel_hex_dir}/${objname}.hex)
         endforeach()

         ##Generate the .hex files from the .fcpatch files by using KrnToHex.

         list(REMOVE_ITEM objsname "EOT" "Secure_Block_Copy") # Remove "EOT" and "Secure_Block_Copy".

         foreach(objname ${objsname})
            add_custom_command(
            OUTPUT ${patch_dir}/${objname}.krn
            DEPENDS ${out_dir}/${objname}.fcpatch ${patch_dir}
            WORKING_DIRECTORY ${out_dir}
            COMMAND ${CMAKE_COMMAND} -E copy ${out_dir}/${objname}.fcpatch ${patch_dir}/${objname}.krn
            )
         endforeach()

         set(fcpatch_hexs "")
         foreach(objname ${objsname})
            add_custom_command(
            OUTPUT ${patch_hex_dir}/${objname}.hex
            DEPENDS KrnToHex ${patch_dir}/${objname}.krn ${patch_hex_dir}
            WORKING_DIRECTORY ${patch_dir}
            COMMAND KrnToHex ${patch_dir}/${objname}.krn
            COMMAND ${CMAKE_COMMAND} -E copy ${patch_dir}/${objname}.hex ${patch_hex_dir}/${objname}.hex
            COMMAND ${CMAKE_COMMAND} -E remove ${patch_dir}/${objname}.hex
            COMMENT "Generate the hex files of cmfc patch")
            set(fcpatch_hexs ${fcpatch_hexs} ${patch_hex_dir}/${objname}.hex)
         endforeach()

        # Generating the .bin files for cmfc kernel and patch respectively.

        add_custom_command(
            OUTPUT ${kernel_hex_dir}/${krn}.bin ${krn_header}
            DEPENDS GenDmyHex GenKrnBin ${hexs} ${link_file}   #Generate the dummy hexs from the pre-built header
            WORKING_DIRECTORY ${kernel_hex_dir}
            COMMAND GenDmyHex ${kernel_hex_dir} ${krn_header}
            COMMAND ${CMAKE_COMMAND} -E copy ${link_file} ${kernel_hex_dir}
            COMMAND GenKrnBin ${kernel_hex_dir} ${name} ${genx} tgllp_cmfc
            COMMAND ${CMAKE_COMMAND} -E copy ${krn}.h ${krn_header})

        add_custom_command(
            OUTPUT ${patch_hex_dir}/${krnpatch}.bin
            DEPENDS GenKrnBin ${fcpatch_hexs} ${link_file}
            WORKING_DIRECTORY ${patch_hex_dir}
            COMMAND ${CMAKE_COMMAND} -E copy ${link_file} ${patch_hex_dir}
            COMMAND GenKrnBin ${patch_hex_dir} ${name} ${genx} tgllp_cmfcpatch)

        # Generating kernel source files for cmfc kernel and patch.

        add_custom_command(
            OUTPUT ${krn_dir}/cmfc/${krn}.c ${krn_dir}/cmfc/${krn}.h
            DEPENDS KernelBinToSource ${kernel_hex_dir}/${krn}.bin
            COMMAND KernelBinToSource -i ${kernel_hex_dir}/${krn}.bin -o ${krn_dir}/cmfc)

        add_custom_command(
            OUTPUT ${krn_dir}/cmfcpatch/${krnpatch}.c ${krn_dir}/cmfcpatch/${krnpatch}.h
            DEPENDS KernelBinToSource ${patch_hex_dir}/${krnpatch}.bin
            COMMAND KernelBinToSource -i ${patch_hex_dir}/${krnpatch}.bin -o ${krn_dir}/cmfcpatch)
    endfunction()

    # List of kernel sources to build.
    # NOTE: Order is important!! It should match the order in which sub-kernels are described
    # in the corresponding strcuture in the driver. For example, HME kernel should
    # match HmeDsScoreboardKernelHeaderG11
    list(APPEND HME_KRN_SOURCES
        ${CMAKE_CURRENT_LIST_DIR}/gen11/codec/kernel_free/Source/downscale_kernel_genx.cpp
        ${CMAKE_CURRENT_LIST_DIR}/gen11/codec/kernel_free/Source/hme_kernel_genx.cpp
        ${CMAKE_CURRENT_LIST_DIR}/gen11/codec/kernel_free/Source/downscale_convert_kernel_genx.cpp)

    get_c_macro_int(${CMAKE_CURRENT_LIST_DIR}/common/codec/kernel/codeckrnheader.h
        "IDR_CODEC_HME_DS_SCOREBOARD_KERNEL" IDR_CODEC_HME_DS_SCOREBOARD_KERNEL)

    if(GEN11_ICLLP)
        #gen_kernel_from_asm(vp gen11_icllp)
        #gen_kernel_from_cm(codec gen11 ${IDR_CODEC_HME_DS_SCOREBOARD_KERNEL} "${HME_KRN_SOURCES}")
    endif()

    if(GEN12_TGLLP)
        #gen_vpkernel_from_cm(vp gen12_tgllp)
    endif()
endif()

media_include_subdirectory(common)

if(GEN8)
    media_include_subdirectory(gen8)
endif()

if(GEN8_BDW)
    media_include_subdirectory(gen8_bdw)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN9)
    media_include_subdirectory(gen9)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN9_CML)
    media_include_subdirectory(gen9_cml)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN9_CMPV)
    media_include_subdirectory(gen9_cmpv)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN9_BXT)
    media_include_subdirectory(gen9_bxt)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN9_SKL)
    media_include_subdirectory(gen9_skl)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN9_GLK)
    media_include_subdirectory(gen9_glk)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN9_KBL)
    media_include_subdirectory(gen9_kbl)
endif()

if(GEN10)
    media_include_subdirectory(gen10)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN11)
    media_include_subdirectory(gen11)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN11_ICLLP)
    media_include_subdirectory(gen11_icllp)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN11_JSL)
    media_include_subdirectory(gen11_jsl_ehl)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN12)
    media_include_subdirectory(gen12)
    media_include_subdirectory(g12)
    media_include_subdirectory(../media_softlet/agnostic/gen12)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN12_TGLLP)
    media_include_subdirectory(gen12_tgllp)
endif()

if(ENABLE_REQUIRED_GEN_CODE OR GEN12)
media_include_subdirectory(Xe_M)
media_include_subdirectory(Xe_R)
endif()

include(${MEDIA_EXT}/agnostic/media_srcs_ext.cmake OPTIONAL)
