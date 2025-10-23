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

if(WITH_CLIENT_GPUJPEG)
    set(GPUJPEG_INCLUDE_DIR "" CACHE PATH "")
    set(GPUJPEG_LIBRARIES "" CACHE FILEPATH "")
endif()

find_package(CUDA REQUIRED)
#find_package(OpenGL REQUIRED)

set(EPOXY_INCLUDE_DIR "" CACHE PATH "")
set(EPOXY_LIBRARIES "" CACHE FILEPATH "")

if(WITH_CLIENT_GPUJPEG)
	add_definitions(-DWITH_CLIENT_GPUJPEG)
endif()

set(INC
	 .
     ${EPOXY_INCLUDE_DIR}
     ${GPUJPEG_INCLUDE_DIR}
     ${CUDA_INCLUDE_DIRS}
     #${OPENGL_INCLUDE_DIR}
)

set(SRC
	renderengine.cpp
    renderengine_tcp.cpp
)

set(SRC_HEADERS
    renderengine_api.h
    renderengine_data.h
    
    renderengine_tcp.h
)

include_directories(${INC})
add_library(braas_hpc_renderengine SHARED ${SRC} ${SRC_HEADERS})

target_link_libraries(braas_hpc_renderengine 
    ${CUDA_LIBRARIES}
    ${CUDA_CUDA_LIBRARY} # For CUDA Driver API
    ${OPENGL_LIBRARIES}
    ${EPOXY_LIBRARIES}
)

if(WITH_CLIENT_GPUJPEG)
    target_link_libraries(braas_hpc_renderengine 
        ${GPUJPEG_LIBRARIES}
    )
endif()
  
install (TARGETS braas_hpc_renderengine DESTINATION lib)
install (FILES renderengine_api.h DESTINATION include)
install (FILES renderengine_data.h DESTINATION include)
install (FILES renderengine_tcp.h DESTINATION include)