// #####################################################################################################################
// # Copyright(C) 2011-2026 IT4Innovations National Supercomputing Center, VSB - Technical University of Ostrava
// #
// # This program is free software : you can redistribute it and/or modify
// # it under the terms of the GNU General Public License as published by
// # the Free Software Foundation, either version 3 of the License, or
// # (at your option) any later version.
// #
// # This program is distributed in the hope that it will be useful,
// # but WITHOUT ANY WARRANTY; without even the implied warranty of
// # MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the
// # GNU General Public License for more details.
// #
// # You should have received a copy of the GNU General Public License
// # along with this program.  If not, see <https://www.gnu.org/licenses/>.
// #
// #####################################################################################################################

#ifndef __RENDERENGINE_TCP_H__
#define __RENDERENGINE_TCP_H__

#include <stdlib.h>
#include <string>
#include "renderengine_api.h"
#include "renderengine_data.h"

#    ifdef _WIN32

#      include <iostream>
#      include <winsock2.h>
#      include <ws2tcpip.h>

#      pragma comment(lib, "Ws2_32.lib")
#      pragma comment(lib, "Mswsock.lib")
#      pragma comment(lib, "AdvApi32.lib")

#    else
#      include <arpa/inet.h>
#      include <netdb.h>
#      include <netinet/in.h>
#      include <netinet/tcp.h>
#      include <sys/socket.h>
#      include <unistd.h>
#    endif

#define TCP_OPTIMIZATION
#define MAX_CONNECTIONS 100


class TcpConnection {
protected:
	int g_port_offset = -1;

	int g_server_id_cam[MAX_CONNECTIONS];
	int g_client_id_cam[MAX_CONNECTIONS];

	int g_server_id_data[MAX_CONNECTIONS];
	int g_client_id_data[MAX_CONNECTIONS];

	int g_timeval_sec = 60;
	int g_connection_error = 0;

	sockaddr_in g_client_sockaddr_cam[MAX_CONNECTIONS];
	sockaddr_in g_server_sockaddr_cam[MAX_CONNECTIONS];

	sockaddr_in g_client_sockaddr_data[MAX_CONNECTIONS];
	sockaddr_in g_server_sockaddr_data[MAX_CONNECTIONS];

	bool g_is_server = true;
	int g_port_cam = 7001;
	int g_port_data = 7000;
	std::string g_server_cam = "localhost";
	std::string g_server_data = "localhost";

	int frame = 0;

#ifdef WITH_CLIENT_GPUJPEG
	void* g_encoder = NULL;
	uint8_t* g_image_compressed;

	int g_compressed_quality = -1; //0-100

	void* g_decoder = NULL;
#endif

#ifdef WITH_CLIENT_HDR_BLOCK_CODEC
    void* g_hdr_image_buffer = NULL;
	size_t g_hdr_image_buffer_size = 0;
	void* g_hdr_compressed_buffer = NULL;
	size_t g_hdr_compressed_buffer_size = 0;
	int g_hdr_codec_profile = 8; // Default to 8 bpp
#endif

	// Frame protocol (renderengine_frame_header). Declared unconditionally so the class layout
	// does not depend on compile definitions of the consumer.
	void* g_lhc_encoder = NULL;        // HalfCodec*
	void* g_lhc_decoder = NULL;        // HalfCodec*
	void* g_display_transform = NULL;  // DisplayTransform*
	char* g_frame_buffer = NULL;       // host staging buffer (pinned when CUDA is available)
	size_t g_frame_buffer_size = 0;
	bool g_frame_buffer_pinned = false;

	char* frame_buffer(size_t size);

public:
	TcpConnection();
	virtual void write_data_kernelglobal(void* data, size_t size);
	virtual bool read_data_kernelglobal(void* data, size_t size);
	virtual void close_kernelglobal();

	virtual bool is_error();

	virtual void init_sockets_cam(const char* server = NULL, int port_cam = 0, int port_data = 0, bool is_server = true);
	virtual void init_sockets_data(const char* server = NULL, int port = 0, bool is_server = true);

	virtual bool client_check();
	virtual bool server_check();

	virtual void client_close();
	virtual void server_close();

	virtual void send_data_cam(char* data, size_t size, char ack = 0);
	virtual void recv_data_cam(char* data, size_t size, char ack = 0);

	virtual void send_data_data(char* data, size_t size, char ack = 0);
	virtual void recv_data_data(char* data, size_t size, char ack = 0);

	virtual void send_gpujpeg(char* dmem, char* pixels, int width, int height, int format);
	virtual void recv_gpujpeg(char* dmem, char* pixels, int width, int height, int format);
	virtual void recv_decode(char* dmem, char* pixels, int width, int height, int frame_size);

	// Frame protocol for settings.codec != RENDERENGINE_CODEC_LEGACY (server side).
	// pixels: half4 RGBA scene linear frame, device or host pointer.
	// Returns the codec actually used (a fallback is announced in the frame header).
	virtual int send_frame(const renderengine_stream_settings& settings, char* pixels, int width, int height);

	// Client side. dmem: device output buffer (may be NULL without CUDA), pixels: host output
	// buffer of width*height*4*pixel_bits/8 bytes, filled when dmem is NULL.
	// Returns 0 on success, 1 if the frame was skipped (size/format mismatch, error) and
	// 2 if the temporal reference of the LHC codec was lost (request a key frame).
	virtual int recv_frame(char* dmem, char* pixels, int width, int height, int pixel_bits,
		renderengine_frame_header* header);

	// Server side color management for RENDERENGINE_CODEC_JPEG_DISPLAY (see display_transform.h).
	virtual int set_display_lut(const float* lut, int size, float log2_min, float log2_max);

	// Forget the temporal state of the codecs (new connection).
	virtual void reset_stream();

	virtual void rgb_to_yuv_i420(
		unsigned char* destination, unsigned char* source, int tile_h, int tile_w);

	virtual void yuv_i420_to_rgb(
		unsigned char* destination, unsigned char* source, int tile_h, int tile_w);

	virtual void yuv_i420_to_rgb_half(
		unsigned short* destination, unsigned char* source, int tile_h, int tile_w);

	virtual void rgb_to_half(
		unsigned short* destination, unsigned char* source, int tile_h, int tile_w);

	virtual void set_port_offset(int offset);

	virtual void save_bmp(
		int width,
		int height,
		char* pixels,
		int step);

	virtual void set_frame(int f) { frame = f; }
	virtual int get_frame() { return frame; }

protected:
	int setsock_tcp_windowsize(int inSock, int inTCPWin, int inSend);
	bool init_wsa();
	void init_port();
	void close_wsa();
	bool server_create(int port,
		int& server_id,
		int& client_id,
		sockaddr_in& server_sock,
		sockaddr_in& client_sock,
		bool only_accept);

	bool client_create(const char* server_name, int port, int& client_id, sockaddr_in& client_sock);
	void close_tcp(int id);

	void send_data(char* data, size_t size);
	void recv_data(char* data, size_t size);

#ifdef WITH_CLIENT_GPUJPEG
	int gpujpeg_encode(int width,
		int height,
		int format,
		uint8_t* input_image,
		uint8_t* image_compressed,
		size_t& image_compressed_size,
		int quality = -1);

	int gpujpeg_decode(int width,
		int height,
		int format,
		uint8_t* input_image,
		uint8_t* image_compressed,
		size_t image_compressed_size);
#endif

#ifdef WITH_CLIENT_HDR_BLOCK_CODEC
	int hdr_codec_encode(int width,
		int height,
		int format,
		uint8_t* input_image,
		size_t& image_compressed_size);

	int hdr_codec_decode(int width,
		int height,
		int format,
		uint8_t* output_image,
		uint8_t* compressed_data,
		size_t compressed_size);
#endif
};

#endif
