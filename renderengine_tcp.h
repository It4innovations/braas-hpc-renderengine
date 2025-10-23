// #####################################################################################################################
// # Copyright(C) 2011-2025 IT4Innovations National Supercomputing Center, VSB - Technical University of Ostrava
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

#ifdef WITH_CLIENT_GPUJPEG
#  include <libgpujpeg/gpujpeg_common.h>
#  include <libgpujpeg/gpujpeg_decoder.h>
#  include <libgpujpeg/gpujpeg_encoder.h>
#endif

#define TCP_OPTIMIZATION
//#define TCP_FLOAT
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

	int frame = 0;

#ifdef WITH_CLIENT_GPUJPEG
	gpujpeg_encoder* g_encoder = NULL;
	uint8_t* g_image_compressed;

	int g_compressed_quality = -1; //0-100

	gpujpeg_decoder* g_decoder = NULL;
#endif
public:
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

	virtual void send_data_cam(char* data, size_t size, bool ack = false);
	virtual void recv_data_cam(char* data, size_t size, bool ack = false);

	virtual void send_data_data(char* data, size_t size, bool ack = false);
	virtual void recv_data_data(char* data, size_t size, bool ack = false);

	virtual void send_gpujpeg(char* dmem, char* pixels, int width, int height, int format);
	virtual void recv_gpujpeg(char* dmem, char* pixels, int width, int height, int format);
	virtual void recv_decode(char* dmem, char* pixels, int width, int height, int frame_size);

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
		int& image_compressed_size);

	int gpujpeg_decode(int width,
		int height,
		int format,
		uint8_t* input_image,
		uint8_t* image_compressed,
		int& image_compressed_size);
#endif
};

#endif
