#####################################################################################################################
# Copyright(C) 2011-2025 IT4Innovations National Supercomputing Center, VSB - Technical University of Ostrava
#
# This program is free software : you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#####################################################################################################################
cmake_minimum_required(VERSION 3.20)
project (braas_hpc_renderengine)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(WITH_CLIENT_GPUJPEG "Enable GPUJPEG" OFF)
option(WITH_CLIENT_EPOXY "Enable EPOXY" OFF)

option(TCP_PIX_SIZE_F32 "Enable PIX_SIZE_F32" OFF)
option(TCP_PIX_SIZE_U16 "Enable PIX_SIZE_U16" OFF)

if(TCP_PIX_SIZE_U16)
    set(TCP_PIX_SIZE_F32 OFF)
endif()

find_package(CUDA REQUIRED)

if(WITH_CLIENT_GPUJPEG)
    #set(GPUJPEG_INCLUDE_DIR "" CACHE PATH "")
    #set(GPUJPEG_LIBRARIES "" CACHE FILEPATH "")
    #find_package(GPUJPEG REQUIRED)
    set(IS_SUBMODULE TRUE)
    add_subdirectory(submodules/braas-hpc-gpujpeg)
endif()

#find_package(OpenGL REQUIRED)

if(WITH_CLIENT_EPOXY)
    set(EPOXY_INCLUDE_DIR "" CACHE PATH "")
    set(EPOXY_LIBRARIES "" CACHE FILEPATH "")

    if(NOT EPOXY_INCLUDE_DIR OR NOT EPOXY_LIBRARIES)
        message(FATAL_ERROR "Epoxy library not configured. Please set EPOXY_INCLUDE_DIR and EPOXY_LIBRARIES cache variables.")
    endif()
endif()

#####################################################################################################################

include(CMakePackageConfigHelpers)

add_subdirectory(src)

# Generate package configuration files
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/braas_hpc_renderengineConfigVersion.cmake"
    VERSION 1.0.0
    COMPATIBILITY AnyNewerVersion
)

configure_package_config_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/Config.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/braas_hpc_renderengineConfig.cmake"
    INSTALL_DESTINATION lib/cmake/braas_hpc_renderengine
)

install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/braas_hpc_renderengineConfig.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/braas_hpc_renderengineConfigVersion.cmake"
    DESTINATION lib/cmake/braas_hpc_renderengine
)