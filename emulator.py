#!/usr/bin/env python
import signal
import socket

import zeroconf

def main():
    info = zeroconf.ServiceInfo('_sockit._tcp.local.',
        'Living room Sockit._sockit._tcp.local.', address=socket.inet_aton('172.16.0.10'),
        port=40420, properties={'description':'test service, please ignore', 'name': 'lol'})

    zc = zeroconf.Zeroconf()
    zc.register_service(info)
    signal.sigwait({signal.SIGINT, signal.SIGTERM})

    print('unregistering...')
    zc.unregister_service(info)
    zc.close()

if __name__ == '__main__':
    main()
