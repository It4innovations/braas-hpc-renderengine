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
	
	# Add HIP platform definition if using HIP backend
	if(GPUJPEG_USE_HIP)
		add_definitions(-D__HIP_PLATFORM_AMD__)
		# Set HIP path for includes and libraries
		if(NOT DEFINED ROCM_PATH)
			if(NOT DEFINED ENV{ROCM_PATH})
				set(ROCM_PATH "/opt/rocm" CACHE PATH "Path to ROCm installation")
			else()
				set(ROCM_PATH $ENV{ROCM_PATH} CACHE PATH "Path to ROCm installation")
			endif()
		endif()
		# Use DWARF-2 to avoid compatibility issues with older GNU assemblers
		set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -gdwarf-2")
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -gdwarf-2")
	endif()
endif()

if(WITH_CLIENT_EPOXY)
    add_definitions(-DWITH_CLIENT_EPOXY)
endif()

# find_package(OpenMP REQUIRED)

set(INC
	 .
     ${EPOXY_INCLUDE_DIR}
     #${GPUJPEG_INCLUDE_DIR}
     ../submodules/braas-hpc-gpujpeg
)

# Add GPU backend specific includes
if(WITH_CLIENT_GPUJPEG)
	if(GPUJPEG_USE_HIP)
		list(APPEND INC ${ROCM_PATH}/include)
	else()
		list(APPEND INC ${CUDA_INCLUDE_DIRS})
	endif()
endif()

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
    ${OPENGL_LIBRARIES}
    ${EPOXY_LIBRARIES}
    # OpenMP::OpenMP_CXX
)

# Add GPU backend specific libraries
if(WITH_CLIENT_GPUJPEG)
	if(GPUJPEG_USE_HIP)
		# Link against HIP runtime library directly
		find_library(HIP_LIBRARY amdhip64 HINTS ${ROCM_PATH}/lib)
		if(HIP_LIBRARY)
			target_link_libraries(braas_hpc_renderengine ${HIP_LIBRARY})
		else()
			message(WARNING "HIP library not found in ${ROCM_PATH}/lib")
		endif()
	else()
		target_link_libraries(braas_hpc_renderengine 
			${CUDA_LIBRARIES}
			${CUDA_CUDA_LIBRARY}
		)
	endif()
endif()

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