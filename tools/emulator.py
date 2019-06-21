#!/usr/bin/env python
import argparse
import struct
import socket
import socketserver
import threading
import select

from eventfd import EventFD
import netifaces

from common import *

socketserver.TCPServer.allow_reuse_address = True

def default_iface():
    iface = netifaces.gateways()['default']
    if netifaces.AF_INET not in iface:
        return None

    return iface[netifaces.AF_INET][1]

class SockitHandler(socketserver.BaseRequestHandler):
    def _send_error(self, type_):
        print(f'sending {type_} to {self.request.getpeername()}')
        err = struct.pack('BB', ResType.ERROR.value, type_.value)
        self.request.sendall(err)
    def _recv_string(self):
        data = self.request.recv(1, socket.MSG_WAITALL)
        if not data:
            return None
        s_len, = struct.unpack('B', data)

        data = self.request.recv(s_len, socket.MSG_WAITALL)
        if not data:
            return None
        return data.decode('utf-8')

    def handle(self):
        ref = self.server.ref
        src = self.request.getpeername()
        header = self.request.recv(5, socket.MSG_WAITALL)
        if not header:
            return
        if not header.startswith(MAGIC):
            self._send_error(ErrType.BAD_REQ)
            return
        try:
            t, = struct.unpack('B', header[-1:])
            req_type = ReqType(t)
        except:
            self._send_error(ErrType.BAD_REQ)
            return

        if req_type == ReqType.GET_STATE:
            print(f'sending state to {src}')
            res = struct.pack('B?', ResType.OK.value, ref.state)
            self.request.sendall(res)
        elif req_type == ReqType.SET_STATE:
            data = self.request.recv(1, socket.MSG_WAITALL)
            if not data:
                return
            new_state, = struct.unpack('?', data)

            print(f'setting state to {new_state} (currently {ref.state})')
            ref.state = new_state
            res = struct.pack('B?', ResType.OK.value, ref.state)
            self.request.sendall(res)
        elif req_type == ReqType.SET_NAME:
            new_name = self._recv_string()
            if not new_name:
                return

            print(f'setting name to {new_name}')
            ref.name = new_name
            res = struct.pack('B', ResType.OK.value)
            self.request.sendall(res)
        elif req_type == ReqType.SET_DESC:
            new_desc = self._recv_string()
            if not new_desc:
                return

            print(f'setting description to {new_desc}')
            ref.description = new_desc
            res = struct.pack('B', ResType.OK.value)
            self.request.sendall(res)
        elif req_type == ReqType.GET_NET:
            if ref.ap:
                print(f'telling {src} we are an ap')
                res = struct.pack('BB', ResType.OK.value, 1)
            else:
                print(f'telling {src} our current net')
                ssid_enc = ref.ssid.encode('utf-8')
                res = struct.pack('BBB', ResType.OK.value, 0, len(ssid_enc)) + \
                    ssid_enc
            self.request.sendall(res)
        elif req_type == ReqType.GET_NETS:
            print(f'sending fake network list to {src}')
            res = struct.pack('BB', ResType.OK.value, len(ref.fake_scanned))
            for ssid, info in ref.fake_scanned.items():
                ssid_enc = ssid.encode('utf-8')
                res += struct.pack('BbB', info['authmode'].value, info['rssi'], len(ssid_enc)) + \
                    ssid_enc
            self.request.sendall(res)
        elif req_type == ReqType.SET_NET:
            mode = self.request.recv(1, socket.MSG_WAITALL)
            if not mode:
                return
            is_ap, = struct.unpack('?', mode)

            if is_ap:
                print(f'{src} setting ap mode')
                ref.ap = True
            else:
                ssid = self._recv_string()
                if not ssid:
                    return
                pwd = self._recv_string()
                if not pwd:
                    return

                print(f'{src} setting network to {ssid}')
                ref.ap = False
                ref.ssid = ssid
                ref.password = pwd

            res = struct.pack('B', ResType.OK.value)
            self.request.sendall(res)
        elif req_type == ReqType.UPGRADE:
            size = self.request.recv(2, socket.MSG_WAITALL)
            size, = struct.unpack('!H', size)

            print(f'{src} upgrading firmware ({size} bytes)')
            assert len(self.request.recv(size, socket.MSG_WAITALL)) == size
            res = struct.pack('B', ResType.OK.value)
            self.request.sendall(res)

class Emulator:
    def __init__(self, name, description, iface, port):
        self.state = False

        self.name = name
        self.description = description
        self.port = port
        self.ap = True
        self.ssid = 'TestWifi'
        self.fake_scanned = {
            'lol': {
                'rssi': -60,
                'authmode': AuthMode.OPEN,
            },
            'dude': {
                'rssi': -90,
                'authmode': AuthMode.WPA2,
            },
            'hello': {
                'rssi': -30,
                'authmode': AuthMode.WPA_WPA2,
            }
        }

        addr_info = netifaces.ifaddresses(iface)[netifaces.AF_INET][0]
        self.address = addr_info['addr']

        self.disc_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.disc_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.disc_socket.bind((MULTICAST_GROUP, DISCOVERY_PORT))

        mreq = socket.inet_aton(MULTICAST_GROUP) + socket.inet_aton(self.address)
        self.disc_socket.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

        self.disc_thread = threading.Thread(target=self._run_discovery)
        self.disc_thread.start()

    def _run_discovery(self):
        self.should_stop = EventFD()
        while True:
            r, _, _ = select.select([self.should_stop, self.disc_socket], [], [])
            if self.should_stop in r:
                break

            msg, src = self.disc_socket.recvfrom(4096)
            if not msg.startswith(MAGIC):
                print(f'ignoring packet from {src} with invalid magic')
                continue

            try:
                disc_type, = struct.unpack('B', msg[len(MAGIC):len(MAGIC)+1])
                disc_type = DiscType(disc_type)
            except Exception as ex:
                print(f'ignoring invalid discovery request from {src}: {ex}')
                continue

            if disc_type == DiscType.SEARCH:
                print(f'sending beacon to {src}')
                name_enc = self.name.encode('utf-8')
                res = MAGIC + \
                    struct.pack('!HB', self.port, len(name_enc)) + \
                    name_enc + \
                    self.description.encode('utf-8')
                self.disc_socket.sendto(res, src)

        self.disc_socket.close()
    def run(self):
        print(f'binding on {self.address}:{self.port}')
        with socketserver.TCPServer((self.address, self.port), SockitHandler) as server:
            server.ref = self
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass
            server.server_close()

    def __enter__(self):
        return self
    def __exit__(self, ex_type, ex_value, ex_traceback):
        print('shutting down...')
        self.should_stop.set()

def main():
    parser = argparse.ArgumentParser(description='Sockit device emulator',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('-i', '--interface', default=default_iface(), help='Bind interface')
    parser.add_argument('-p', '--port', type=int, default=40420, help='Bind port')
    parser.add_argument('-n', '--name', default='My Sockit', help='Device name')
    parser.add_argument('-d', '--description', default='My first Sockit', help='Device description')
    args = parser.parse_args()

    with Emulator(args.name, args.description, args.interface, args.port) as emulator:
        emulator.run()

if __name__ == '__main__':
    main()
