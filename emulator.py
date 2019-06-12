#!/usr/bin/env python
import argparse
import signal
import socket
import socketserver

import zeroconf

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
    signal.sigwait({signal.SIGINT, signal.SIGTERM})

    print('unregistering...')
    zc.unregister_service(info)
    zc.close()

if __name__ == '__main__':
    main()
