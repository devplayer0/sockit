#!/usr/bin/env python
import argparse
import struct
import getpass
import errno
import os
import sys
import time
import socket

from common import *

class SockitError(Exception):
    def __init__(self, code):
        Exception.__init__(self, ErrType(code))

DISC_DATA = MAGIC + struct.pack('B', DiscType.SEARCH.value)

def encode_str(s):
    s_enc = s.encode('utf-8')
    return struct.pack('B', len(s_enc)) + s_enc
def decode_str(data):
    return data[1:1+data[0]].decode('utf-8')

def discover_devices(search_time=3, target=None, stop_after_first=False):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM | socket.SOCK_NONBLOCK)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)

    devices = []
    start = time.time()
    print('Searching for devices...')
    while time.time() - start < search_time:
        sock.sendto(DISC_DATA, (MULTICAST_GROUP, DISCOVERY_PORT))
        while True:
            try:
                packet, src = sock.recvfrom(4096)
                if not packet.startswith(MAGIC):
                    print(f'Ignoring invalid discovery message from {src}')
                    continue

                port, name_len, = struct.unpack('!HB', packet[len(MAGIC):len(MAGIC)+3])
                if list(filter(lambda d: d['address'] == (src[0], port), devices)):
                    continue
                name = packet[len(MAGIC)+3:len(MAGIC)+3+name_len].decode('utf-8')
                description = packet[len(MAGIC)+3+name_len:].decode('utf-8')

                print(f' - {name} ("{description}") at {src[0]}:{port}')
                devices.append({
                    'address': (src[0], port),
                    'name': name,
                    'description': description
                })
                if name == target or stop_after_first:
                    return devices
            except socket.error as err:
                if err.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                    break
                raise err

        time.sleep(0.3)

    return devices
def get_device(args):
    if args.address:
        split = args.address.split(':')
        port = 40420
        if len(split) > 1:
            port = int(split[-1])

        return (split[0], port)

    if args.name:
        results = discover_devices(target=args.name)
        if not results:
            print(f'Device "{args.name}" not found')
            sys.exit(-1)
        return results[0]['address']

    results = discover_devices(stop_after_first=True)
    if not results:
        print('No devices found')
        sys.exit(-1)

    return results[0]['address']

def make_req(addr, type_, payload=None):
    data = MAGIC + struct.pack('B', type_.value)
    if payload:
        data += payload

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(addr)
    sock.sendall(data)
    res = sock.recv(4096)
    sock.close()

    if res[0] == ResType.ERROR:
        raise SockitError(res[1])
    return res[1:]
def fd_req(args, type_, payload=None):
    return make_req(get_device(args), type_, payload=payload)

def cmd_search(_args):
    discover_devices()

def cmd_state(args):
    res = fd_req(args, ReqType.GET_STATE)
    state, = struct.unpack('?', res)
    state = 'on' if state else 'off'
    print(f'Current state: {state}')
def cmd_on(args):
    fd_req(args, ReqType.SET_STATE, b'\x01')
def cmd_off(args):
    fd_req(args, ReqType.SET_STATE, b'\x00')
def cmd_toggle(args):
    addr = get_device(args)
    res = make_req(addr, ReqType.GET_STATE)
    state, = struct.unpack('?', res)

    s_state = 'off' if state else 'on'
    print(f'Switching device {s_state}')
    make_req(addr, ReqType.SET_STATE, struct.pack('?', not state))

def cmd_name(args):
    fd_req(args, ReqType.SET_NAME, encode_str(args.new_name))
def cmd_desc(args):
    fd_req(args, ReqType.SET_DESC, encode_str(args.new_desc))

def cmd_get_net(args):
    res = fd_req(args, ReqType.GET_NET)
    is_ap, = struct.unpack('?', res[:1])

    if is_ap:
        print('Standalone AP mode')
    else:
        print(f'Current network: {decode_str(res[1:])}')
def cmd_standalone(args):
    fd_req(args, ReqType.SET_NET, b'\x01')
def cmd_set_net(args):
    pwd = getpass.getpass(f'Password for "{args.network}": ')
    fd_req(args, ReqType.SET_NET, b'\x00' + encode_str(args.network) + encode_str(pwd))

def cmd_upgrade(args):
    with open(args.firmware, 'rb') as firm:
        firm.seek(0, os.SEEK_END)
        if firm.tell() > 0xffff:
            print(f'Firmware {args.firmware} is too big')
            sys.exit(1)

        firm.seek(0, os.SEEK_SET)
        data = firm.read()

    fd_req(args, ReqType.UPGRADE, struct.pack('!H', len(data)) + data)

def main():
    parser = argparse.ArgumentParser(description='Sockit CLI',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.set_defaults(func=cmd_search)

    disc_group = parser.add_mutually_exclusive_group()
    disc_group.add_argument('-a', '--address', help='Device address to use instead of discovery - format is host[:port]')
    disc_group.add_argument('-n', '--name', help='Device name (for address discovery)')
    commands = parser.add_subparsers(dest='command')

    p_search = commands.add_parser('search', help='Search for devices')
    p_search.set_defaults(func=cmd_search)

    p_state = commands.add_parser('state', help='Get current state')
    p_state.set_defaults(func=cmd_state)
    p_on = commands.add_parser('on', help='Switch device on')
    p_on.set_defaults(func=cmd_on)
    p_off = commands.add_parser('off', help='Switch device off')
    p_off.set_defaults(func=cmd_off)
    p_toggle = commands.add_parser('toggle', help='Toggle device state')
    p_toggle.set_defaults(func=cmd_toggle)

    p_name = commands.add_parser('name', help='Set device name')
    p_name.set_defaults(func=cmd_name)
    p_name.add_argument('new_name', help='New name for the device')
    p_name = commands.add_parser('description', help='Set device description')
    p_name.set_defaults(func=cmd_desc)
    p_name.add_argument('new_desc', help='New description for the device')

    p_get_net = commands.add_parser('get_net', help='Get device current network')
    p_get_net.set_defaults(func=cmd_get_net)
    p_standalone = commands.add_parser('standalone', help='Put device into standalone AP mode')
    p_standalone.set_defaults(func=cmd_standalone)
    p_set_net = commands.add_parser('set_net', help='Set device network')
    p_set_net.set_defaults(func=cmd_set_net)
    p_set_net.add_argument('network', help='WiFi network to connect device to')

    p_upgrade = commands.add_parser('upgrade', help='Upgrade device firmware')
    p_upgrade.set_defaults(func=cmd_upgrade)
    p_upgrade.add_argument('firmware', help='Firmware file')

    args = parser.parse_args()
    args.func(args)

if __name__ == '__main__':
    main()
