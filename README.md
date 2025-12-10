# BRaaS-HPC RenderEngine

A high-performance client-server rendering engine library designed for HPC (High-Performance Computing) environments. This library enables distributed rendering capabilities, optimized for remote visualization and network-based rendering workflows.

## Overview

**BRaaS-HPC RenderEngine** is a C++ shared library with Python bindings that provides:

- **Client-Server Architecture**: TCP-based network communication for distributed rendering
- **Camera Synchronization**: Real-time camera data transmission between client and server
- **Pixel Buffer Management**: Efficient pixel data transfer with support for different pixel formats
- **OpenGL Integration**: Optional OpenGL/Epoxy support for texture rendering
- **Cross-Platform**: Supports Windows, Linux, and macOS

### Key Features

- **Network Rendering**: Stream rendered images between rendering servers and client applications
- **Multiple Pixel Formats**: Support for U8, U16, and F32 pixel formats
- **Real-time Performance Monitoring**: Built-in FPS counters for local and remote rendering
- **Flexible Architecture**: Can operate as both client and server

## What is it for?

This library is designed for scenarios where:

1. **Remote Rendering**: You need to render on a powerful HPC cluster and stream results to a lighter client
2. **Blender Integration**: Integrate HPC rendering capabilities into Blender or other 3D applications
3. **Distributed Visualization**: Stream high-resolution rendered frames across networks
4. **Scientific Visualization**: Handle large-scale data visualization with remote rendering

### Typical Use Cases

- **Remote HPC Rendering**: Render complex scenes on supercomputer clusters, stream to local workstations
- **Interactive Visualization**: Real-time visualization of scientific data with low latency
- **Cloud Rendering Services**: Build rendering-as-a-service infrastructure
- **Virtual Production**: Stream rendered frames for virtual production pipelines

## Architecture

The library consists of:

- **Core C++ Engine** (`src/`): Main rendering engine with TCP communication
- **Python Bindings** (`python/braas_hpc_renderengine_dll/`): Python wrapper for easy integration

### Communication Flow

```
Server (Renderer)                    Client (Viewer)
     |                                      |
     |<------- Camera Data (TCP) -----------|
     |                                      |
     |-------- Pixel Data (TCP) ----------->|
     |                                      |
```

## Prerequisites

### Required

- **CMake** 3.20 or higher
- **C++17** compatible compiler
  - Windows: Visual Studio 2019 or newer
  - Linux: GCC 7+ or Clang 5+
  - macOS: Xcode 10+
- **Python 3.11+** (for Python bindings)

### Optional

- **CUDA Toolkit** 11.0+ (optional)
- **Epoxy** library (for OpenGL texture rendering)
- **OpenGL** 3.3+ (for texture operations)

## Building from Source

### 1. Clone the Repository

```bash
git clone --recursive https://github.com/It4innovations/braas-hpc-renderengine.git
cd braas-hpc-renderengine
```

### 2. Configure Build Options

The build system provides several configuration options:

| Option | Default | Description |
|--------|---------|-------------|
| `WITH_CLIENT_EPOXY` | OFF | Enable Epoxy/OpenGL support |

### 3. Build on Windows

```powershell
# Create build directory
mkdir build
cd build

# Configure (basic build)
cmake ..

# Configure with Epoxy support
cmake -DWITH_CLIENT_EPOXY=ON -DEPOXY_INCLUDE_DIR="C:\path\to\epoxy\include" -DEPOXY_LIBRARIES="C:\path\to\epoxy\lib\epoxy.lib" ..

# Build
cmake --build . --config Release

# Install (optional)
cmake --install . --prefix "C:\Program Files\braas_hpc_renderengine"
```

### 4. Build on Linux/macOS

```bash
# Create build directory
mkdir build
cd build

# Configure (basic build)
cmake ..

# Configure with Epoxy support
cmake -DWITH_CLIENT_EPOXY=ON -DEPOXY_INCLUDE_DIR="/path/to/epoxy/include" -DEPOXY_LIBRARIES="/path/to/epoxy/lib/libepoxy.a" ..

# Build
make -j$(nproc)

# Install (optional)
sudo make install
```

### Build Output

After building, you'll find:

- **Shared Library**:
  - Windows: `braas_hpc_renderengine.dll`
  - Linux: `libbraas_hpc_renderengine.so`
  - macOS: `libbraas_hpc_renderengine.dylib`
- **Headers**: `renderengine_api.h`, `renderengine_data.h`, `renderengine_tcp.h`
- **Python Module**: `python/braas_hpc_renderengine_dll/`

## Installation

### System-wide Installation

After building, install the library system-wide:

```bash
# Linux/macOS
sudo cmake --install build

# Windows (run as Administrator)
cmake --install build --prefix "C:\Program Files\braas_hpc_renderengine"
```

### Python Package Installation

To use the Python bindings, you need to place the shared library in the Python module directory:

```bash
# Copy the built library to the Python module
cp build/src/braas_hpc_renderengine.dll python/braas_hpc_renderengine_dll/  # Windows
cp build/src/libbraas_hpc_renderengine.so python/braas_hpc_renderengine_dll/  # Linux
cp build/src/libbraas_hpc_renderengine.dylib python/braas_hpc_renderengine_dll/  # macOS

# Install Python module
cd python
pip install -e .
```

Or add the Python module to your PYTHONPATH:

```bash
export PYTHONPATH=/path/to/braas-hpc-renderengine/python:$PYTHONPATH
```

## Usage

### C++ API

#### Server-Side Example

```cpp
#include "renderengine_api.h"

int main() {
    // Initialize server on port 7001
    server_init(nullptr, 7001, 1920, 1080);
    
    // Main rendering loop
    while (running) {
        // Receive camera data from client
        if (recv_cam_data() == 0) {
            // Render frame
            unsigned char* pixels = render_scene();
            
            // Send pixels to client
            set_pixels(pixels, false);
            send_pixels_data();
        }
    }
    
    // Cleanup
    server_close_connection();
    return 0;
}
```

#### Client-Side Example

```cpp
#include "renderengine_api.h"

int main() {
    // Connect to server at localhost:7001
    client_init("localhost", 7001, 1920, 1080);
        
    // Main loop
    while (running) {
        // Update camera
        float view_matrix[16] = { /* ... */ };
        set_camera(view_matrix, 50.0f, 0.1f, 100.0f,
                   36.0f, 24.0f, 0, 1.0f, 0.0f, 0.0f,
                   0, 0.0f, 0.0f, 1);
        
        // Send camera to server
        send_cam_data();
        
        // Receive rendered pixels
        if (recv_pixels_data() == 0) {
            unsigned char* pixels = new unsigned char[1920 * 1080 * 4];
            get_pixels(pixels);
            
            // Display pixels
            display_image(pixels);
            
            delete[] pixels;
        }
    }
    
    // Cleanup
    client_close_connection();
    return 0;
}
```

### Python API

#### Server Script

```python
import braas_hpc_renderengine_dll as render_engine
import numpy as np

# Initialize server
render_engine.server_init(None, 7001, 1920, 1080)

try:
    while True:
        # Receive camera data
        if render_engine.recv_cam_data() == 0:
            # Render your scene here
            pixels = render_scene()  # Your rendering function
            
            # Send pixels to client
            render_engine.set_pixels(pixels.ctypes.data, False)
            render_engine.send_pixels_data()
            
            # Print statistics
            fps = render_engine.get_local_fps()
            print(f"FPS: {fps:.2f}")
finally:
    render_engine.server_close_connection()
```

#### Client Script

```python
import braas_hpc_renderengine_dll as render_engine
import numpy as np

# Connect to server
render_engine.client_init(b"localhost", 7001, 1920, 1080)

try:
    while True:
        # Set camera parameters
        view_matrix = np.eye(4, dtype=np.float32)
        render_engine.set_camera(
            view_matrix.ctypes.data,
            50.0,   # lens
            0.1,    # near clip
            100.0,  # far clip
            36.0,   # sensor width
            24.0,   # sensor height
            0,      # sensor fit
            1.0,    # zoom
            0.0, 0.0,  # camera offset
            0,      # use view camera
            0.0, 0.0,  # shift
            1       # perspective
        )
        
        # Send camera to server
        render_engine.send_cam_data()
        
        # Receive pixels
        if render_engine.recv_pixels_data() == 0:
            width = render_engine.get_width()
            height = render_engine.get_height()
            pixels = np.zeros((height, width, 4), dtype=np.uint8)
            render_engine.get_pixels(pixels.ctypes.data)
            
            # Display image
            display_image(pixels)
            
            # Get statistics
            fps = render_engine.get_remote_fps()
            print(f"Remote FPS: {fps:.2f}")
finally:
    render_engine.client_close_connection()
```

## API Reference

### Connection Management

| Function | Description |
|----------|-------------|
| `client_init(server, port, width, height)` | Initialize client connection |
| `server_init(server, port, width, height)` | Initialize server |
| `client_close_connection()` | Close client connection |
| `server_close_connection()` | Close server connection |

### Camera Operations

| Function | Description |
|----------|-------------|
| `set_camera(...)` | Set camera parameters (view matrix, lens, clipping, etc.) |
| `get_camera(...)` | Get current camera parameters |
| `send_cam_data()` | Send camera data over network |
| `recv_cam_data()` | Receive camera data from network |

### Pixel Operations

| Function | Description |
|----------|-------------|
| `set_pixels(pixels, device)` | Set pixel buffer (host or device memory) |
| `get_pixels(pixels)` | Get pixel buffer |
| `send_pixels_data()` | Send pixel data over network |
| `recv_pixels_data()` | Receive pixel data from network |
| `resize(width, height)` | Resize buffers |
| `set_resolution(width, height)` | Set resolution |
| `set_pixsize(size)` | Set pixel size (1=U8, 2=U16, 4=F32) |
| `get_pixsize()` | Get current pixel size |

### Statistics

| Function | Description |
|----------|-------------|
| `get_current_samples()` | Get current sample count |
| `get_remote_fps()` | Get remote rendering FPS |
| `get_local_fps()` | Get local FPS |
| `com_error()` | Check for communication errors |

### Utility

| Function | Description |
|----------|-------------|
| `reset()` | Reset render engine state |
| `set_frame(frame)` | Set current frame number |
| `set_timestep(timestep)` | Set simulation timestep |
| `get_width()` | Get current width |
| `get_height()` | Get current height |

## GUI Integration

While this library doesn't provide a built-in GUI, it's designed to integrate with:

### Blender Integration

The library can be integrated into Blender as a render engine addon:

1. Import the Python module in your Blender addon
2. Use `client_init()` to connect to a remote HPC render server
3. Implement `RenderEngine` class methods to send camera data and receive pixels
4. Display received pixels using Blender's `RenderResult` API

**Example Blender Integration Flow:**
```
Blender Client                   HPC Server
     |                                |
     |----- Camera/Scene Data ------->|
     |                                |
     |                           [Renders Frame]
     |                                |
     |<----- Rendered Pixels ---------|
     |                                |
[Display in Viewport/Render Result]
```

### Custom GUI Applications

For custom applications:

1. Initialize the library as a client
2. Capture user input (camera movements, settings)
3. Send updates to server via `set_camera()` and `send_cam_data()`
4. Receive rendered frames via `recv_pixels_data()` and `get_pixels()`
5. Display using your GUI framework (Qt, GTK, Dear ImGui, etc.)

### OpenGL Texture Rendering

If built with `WITH_CLIENT_EPOXY=ON`:

```cpp
// Get OpenGL texture ID
int texture_id = get_texture_id();

// Draw texture to current OpenGL context
draw_texture();
```

This enables direct rendering to OpenGL windows without CPU memory copies.

## Network Configuration

### Port Configuration

Default ports:
- **Camera Data**: 7000 (can be configured)
- **Pixel Data**: 7001 (can be configured)

### Environment Variables

You can override default settings using environment variables:

```bash
# Server name
export SOCKET_SERVER_NAME_CAM=192.168.1.100
export SOCKET_SERVER_NAME_DATA=192.168.1.100

# Port numbers
export SOCKET_SERVER_PORT_CAM=7000
export SOCKET_SERVER_PORT_DATA=7001
```

### Firewall Configuration

Ensure your firewall allows TCP connections on the configured ports:

**Linux (ufw):**
```bash
sudo ufw allow 7000/tcp
sudo ufw allow 7001/tcp
```

**Windows (PowerShell as Administrator):**
```powershell
New-NetFirewallRule -DisplayName "BRaaS HPC Render Engine" -Direction Inbound -Protocol TCP -LocalPort 7000,7001 -Action Allow
```

## Performance Tips

2. **Adjust Pixel Format**: Use U8 for preview, F32 for final renders
3. **Network Optimization**: Use low-latency networks (10GbE or faster) for best results
4. **Multi-Connection Support**: The library supports up to 100 simultaneous connections (configurable)

## Troubleshooting

### Connection Issues

**Problem**: Cannot connect to server
- Check firewall settings
- Verify server is running and listening on correct port
- Ensure network connectivity: `ping server_address`

**Problem**: Connection drops frequently
- Check network stability
- Increase timeout values in code if needed
- Verify server resources (CPU/memory)

# License
This software is licensed under the terms of the [GNU General Public License](https://github.com/It4innovations/braas-hpc/blob/main/LICENSE).

# Acknowledgement
This work was supported by the Ministry of Education, Youth and Sports of the Czech Republic through the e-INFRA CZ (ID:90254).

This work was supported by the SPACE project. This project has received funding from the European High- Performance Computing Joint Undertaking (JU) under grant agreement No 101093441. This project has received funding from the Ministry of Education, Youth and Sports of the Czech Republic (ID: MC2304).