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
if(WITH_CLIENT_GPUJPEG)
	add_definitions(-DWITH_CLIENT_GPUJPEG)
endif()

if(WITH_CLIENT_EPOXY)
    add_definitions(-DWITH_CLIENT_EPOXY)
endif()

find_package(OpenMP REQUIRED)

set(INC
	 .
     ${EPOXY_INCLUDE_DIR}
     #${GPUJPEG_INCLUDE_DIR}
     ${CUDA_INCLUDE_DIRS}
     #${OPENGL_INCLUDE_DIR}
     ../submodules/braas-hpc-gpujpeg
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

# Enable symbol export on Windows
if(WIN32)
    set_target_properties(braas_hpc_renderengine PROPERTIES
        WINDOWS_EXPORT_ALL_SYMBOLS ON
    )
endif()

target_link_libraries(braas_hpc_renderengine 
    ${CUDA_LIBRARIES}
    ${CUDA_CUDA_LIBRARY} # For CUDA Driver API
    ${OPENGL_LIBRARIES}
    ${EPOXY_LIBRARIES}
    OpenMP::OpenMP_CXX
)

target_include_directories(braas_hpc_renderengine PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(TARGETS braas_hpc_renderengine
    EXPORT braas_hpc_renderengine_targets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)

install(EXPORT braas_hpc_renderengine_targets
    FILE braas_hpc_renderengineTargets.cmake
    NAMESPACE braas_hpc_renderengine::
    DESTINATION lib/cmake/braas_hpc_renderengine
)

if(WITH_CLIENT_GPUJPEG)
    target_link_libraries(braas_hpc_renderengine 
        #${GPUJPEG_LIBRARIES}
        gpujpeg
    )
endif()
  
#install (TARGETS braas_hpc_renderengine DESTINATION lib)
install (FILES renderengine_api.h DESTINATION include)
install (FILES renderengine_data.h DESTINATION include)
install (FILES renderengine_tcp.h DESTINATION include)