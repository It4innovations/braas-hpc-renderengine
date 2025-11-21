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

"""
BRAAS HPC Rendering Engine DLL Interface Module

This module provides a Python interface to the BRAAS HPC rendering engine DLL,
exposing rendering, network communication, camera operations, and statistics functions.
"""

import os
import sys
import ctypes
from ctypes import cdll, c_void_p, c_char_p, c_int32, c_uint32, c_float, c_bool, c_ulong, POINTER

####################################################################################################
# Platform specific library loading
if sys.platform == "win32":
    _renderengine_dll_name = "braas_hpc_renderengine.dll"
elif sys.platform == "darwin":
    _renderengine_dll_name = "libbraas_hpc_renderengine.dylib"
else:  # Linux and other Unix-like systems
    _renderengine_dll_name = "libbraas_hpc_renderengine.so"

# Load library
_renderengine_dll_name = os.path.join(os.path.dirname(__file__), _renderengine_dll_name)
_renderengine_dll = cdll.LoadLibrary(_renderengine_dll_name)

####################################################################################################
# Function definitions for _renderengine_dll

# Basic rendering functions
_renderengine_dll.resize.argtypes = [c_int32, c_int32]
_renderengine_dll.set_resolution.argtypes = [c_int32, c_int32]
_renderengine_dll.set_frame.argtypes = [c_int32]

# Pixel operations
_renderengine_dll.get_pixels.argtypes = [c_void_p]
_renderengine_dll.set_pixels.argtypes = [c_void_p, c_bool]

# Network communication
_renderengine_dll.recv_pixels_data.restype = c_int32
_renderengine_dll.send_pixels_data.restype = c_int32
_renderengine_dll.send_cam_data.restype = c_int32
_renderengine_dll.recv_cam_data.restype = c_int32
_renderengine_dll.set_timestep.argtypes = [c_int32]

# Server/Client connection
_renderengine_dll.client_init.argtypes = [c_char_p, c_int32, c_int32, c_int32]
_renderengine_dll.server_init.argtypes = [c_char_p, c_int32, c_int32, c_int32]
_renderengine_dll.client_close_connection.argtypes = []
_renderengine_dll.server_close_connection.argtypes = []

# Camera operations
_renderengine_dll.set_camera.argtypes = [c_void_p, c_float, c_float, c_float,
                                        c_float, c_float, c_int32, c_float, c_float, c_float, c_int32, c_float, c_float, c_int32]

_renderengine_dll.get_camera.argtypes = [c_void_p,
                                        POINTER(c_float), POINTER(c_float), POINTER(c_float),
                                        POINTER(c_float), POINTER(c_float), POINTER(c_int32),
                                        POINTER(c_float), POINTER(c_float), POINTER(c_float),
                                        POINTER(c_int32), POINTER(c_float), POINTER(c_float), POINTER(c_int32)]

# Rendering operations
_renderengine_dll.draw_texture.argtypes = []

# Statistics
_renderengine_dll.get_current_samples.restype = c_int32
_renderengine_dll.get_remote_fps.restype = c_float
_renderengine_dll.get_local_fps.restype = c_float

# Reset
_renderengine_dll.reset.argtypes = []

# Data transfer
_renderengine_dll.send_braas_hpc_renderengine_data_render.argtypes = [c_char_p, c_int32]
_renderengine_dll.recv_braas_hpc_renderengine_data.argtypes = [c_char_p, c_int32]

# Range queries
_renderengine_dll.get_braas_hpc_renderengine_range.argtypes = [c_void_p, c_void_p, c_void_p]
_renderengine_dll.set_braas_hpc_renderengine_range.argtypes = [c_void_p, c_void_p, c_void_p, c_int32, c_float]

# Texture operations
_renderengine_dll.get_texture_id.restype = c_int32

# Error handling
_renderengine_dll.com_error.restype = c_int32

# GPU Buffer access
_renderengine_dll.get_gpu_buffer.restype = c_ulong

# Resolution operations
_renderengine_dll.get_width.restype = c_int32
_renderengine_dll.get_height.restype = c_int32

####################################################################################################
# Public API - Expose the DLL functions

# Basic rendering functions
resize = _renderengine_dll.resize
set_resolution = _renderengine_dll.set_resolution
set_frame = _renderengine_dll.set_frame

# Pixel operations
get_pixels = _renderengine_dll.get_pixels
set_pixels = _renderengine_dll.set_pixels

# Network communication
recv_pixels_data = _renderengine_dll.recv_pixels_data
send_pixels_data = _renderengine_dll.send_pixels_data
send_cam_data = _renderengine_dll.send_cam_data
recv_cam_data = _renderengine_dll.recv_cam_data
set_timestep = _renderengine_dll.set_timestep

# Server/Client connection
client_init = _renderengine_dll.client_init
server_init = _renderengine_dll.server_init
client_close_connection = _renderengine_dll.client_close_connection
server_close_connection = _renderengine_dll.server_close_connection

# Camera operations
set_camera = _renderengine_dll.set_camera
get_camera = _renderengine_dll.get_camera

# Rendering operations
draw_texture = _renderengine_dll.draw_texture

# Statistics
get_current_samples = _renderengine_dll.get_current_samples
get_remote_fps = _renderengine_dll.get_remote_fps
get_local_fps = _renderengine_dll.get_local_fps

# Reset
reset = _renderengine_dll.reset

# Data transfer
send_braas_hpc_renderengine_data_render = _renderengine_dll.send_braas_hpc_renderengine_data_render
recv_braas_hpc_renderengine_data = _renderengine_dll.recv_braas_hpc_renderengine_data

# Range queries
get_braas_hpc_renderengine_range = _renderengine_dll.get_braas_hpc_renderengine_range
set_braas_hpc_renderengine_range = _renderengine_dll.set_braas_hpc_renderengine_range

# Texture operations
get_texture_id = _renderengine_dll.get_texture_id

# Error handling
com_error = _renderengine_dll.com_error

# GPU Buffer access
get_gpu_buffer = _renderengine_dll.get_gpu_buffer

# Resolution operations
get_width = _renderengine_dll.get_width
get_height = _renderengine_dll.get_height

####################################################################################################
# Module exports
__all__ = [
    # Basic rendering functions
    'resize',
    'set_resolution',
    'set_frame',
    # Pixel operations
    'get_pixels',
    'set_pixels',
    # Network communication
    'recv_pixels_data',
    'send_pixels_data',
    'send_cam_data',
    'recv_cam_data',
    'set_timestep',
    # Server/Client connection
    'client_init',
    'server_init',
    'client_close_connection',
    'server_close_connection',
    # Camera operations
    'set_camera',
    'get_camera',
    # Rendering operations
    'draw_texture',
    # Statistics
    'get_current_samples',
    'get_remote_fps',
    'get_local_fps',
    # Reset
    'reset',
    # Data transfer
    'send_braas_hpc_renderengine_data_render',
    'recv_braas_hpc_renderengine_data',
    # Range queries
    'get_braas_hpc_renderengine_range',
    'set_braas_hpc_renderengine_range',
    # Texture operations
    'get_texture_id',
    # Error handling
    'com_error',
    # GPU Buffer access
    'get_gpu_buffer',
    # Resolution operations
    'get_width',
    'get_height',
]

