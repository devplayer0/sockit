#!/usr/bin/env python
from enum import Enum
import argparse
import struct
import socket
import socketserver

import zeroconf

socketserver.TCPServer.allow_reuse_address = True

MAGIC = b'SKIT'

class ReqType(Enum):
    GET_STATE = 0x00
    SET_STATE = 0x01
    SET_NAME  = 0x02
    SET_DESC  = 0x03
class ResType(Enum):
    OK = 0x00
    ERROR = 0xff
class ErrType(Enum):
    BAD_REQ = 0x00
    FAILED = 0x01

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
            print(f'sending state to {self.request.getpeername()}')
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
            ref.reregister()
            res = struct.pack('B', ResType.OK.value)
            self.request.sendall(res)
        elif req_type == ReqType.SET_DESC:
            new_desc = self._recv_string()
            if not new_desc:
                return

            print(f'setting description to {new_desc}')
            ref.description = new_desc
            ref.reregister()
            res = struct.pack('B', ResType.OK.value)
            self.request.sendall(res)

class Emulator:
    def __init__(self, name, description, address, port):
        self.state = False

        self.name = name
        self.description = description
        self.address = address
        self.port = port

        self.info = None
        self.zc = zeroconf.Zeroconf()
        self.reregister()

    def reregister(self):
        if self.info:
            self.zc.unregister_service(self.info)
        self.info = zeroconf.ServiceInfo('_sockit._tcp.local.',
            f'{self.name}._sockit._tcp.local.', address=socket.inet_aton(self.address),
            port=self.port, properties={'description': self.description})
        self.zc.register_service(self.info)

    def run(self):
        print(f'binding on {self.address}:{self.info.port}')
        with socketserver.TCPServer((self.address, self.info.port), SockitHandler) as server:
            server.ref = self
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass
            server.server_close()

    def __enter__(self):
        return self
    def __exit__(self, ex_type, ex_value, ex_traceback):
        print('unregistering...')
        self.zc.close()

def main():
    parser = argparse.ArgumentParser(description='Sockit device emulator',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('-p', '--port', type=int, default=40420, help='Bind port')
    parser.add_argument('-n', '--name', default='My Sockit', help='Device name')
    parser.add_argument('-d', '--description', default='My first Sockit', help='Device description')
    args = parser.parse_args()

    address = socket.gethostbyname(socket.getfqdn())
    with Emulator(args.name, args.description, address, args.port) as emulator:
        emulator.run()

if __name__ == '__main__':
    main()
