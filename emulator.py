#!/usr/bin/env python
from enum import Enum
import argparse
import struct
import socket
import socketserver

import zeroconf

MAGIC = b'SKIT'

class ReqType(Enum):
    GET_STATE = 0x00
    SET_STATE = 0x01
class ResType(Enum):
    OK = 0x00
    ERROR = 0xff
class ErrType(Enum):
    BAD_REQ = 0x00
    FAILED = 0x01

state = False
class SockitHandler(socketserver.BaseRequestHandler):
    def _send_error(self, type_):
        print(f'sending {type_} to {self.request.getpeername()}')
        err = struct.pack('BB', ResType.ERROR.value, type_.value)
        self.request.sendall(err)

    def handle(self):
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

        global state
        if req_type == ReqType.GET_STATE:
            print(f'sending state to {self.request.getpeername()}')
            res = struct.pack('B?', ResType.OK.value, state)
            self.request.sendall(res)
        elif req_type == ReqType.SET_STATE:
            data = self.request.recv(1, socket.MSG_WAITALL)
            if not data:
                return
            new_state, = struct.unpack('?', data)

            print(f'setting state to {new_state} (currently {state})')
            res = struct.pack('B?', ResType.OK.value, state)
            state = new_state
            self.request.sendall(res)

def main():
    parser = argparse.ArgumentParser(description='Sockit device emulator',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('-p', '--port', type=int, default=40420, help='Bind port')
    parser.add_argument('-n', '--name', default='My Sockit', help='Device name')
    parser.add_argument('-d', '--description', default='My first Sockit', help='Device description')
    args = parser.parse_args()

    address = socket.gethostbyname(socket.getfqdn())
    info = zeroconf.ServiceInfo('_sockit._tcp.local.',
        f'{args.name}._sockit._tcp.local.', address=socket.inet_aton(address),
        port=args.port, properties={'description': args.description})

    zc = zeroconf.Zeroconf()
    zc.register_service(info)
    try:
        print(f'binding on {address}:{args.port}')
        with socketserver.TCPServer((address, args.port), SockitHandler) as server:
            server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        print('unregistering...')
        zc.unregister_service(info)
        zc.close()

if __name__ == '__main__':
    main()
