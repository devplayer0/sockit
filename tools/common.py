from enum import Enum

MAGIC = b'SKIT'
DISCOVERY_PORT = 40420
MULTICAST_GROUP = '224.0.0.220'

class DiscType(Enum):
    SEARCH = 0x00
class ReqType(Enum):
    GET_STATE     = 0x00
    SET_STATE     = 0x01
    SET_NAME      = 0x02
    SET_DESC      = 0x03
    GET_NET       = 0x04
    GET_NETS      = 0x05
    SET_NET       = 0x06
class ResType(Enum):
    OK = 0x00
    ERROR = 0xff
class ErrType(Enum):
    BAD_REQ = 0x00
    FAILED  = 0x01
class AuthMode(Enum):
    OPEN     = 0
    WEP      = 1
    WPA      = 2
    WPA2     = 3
    WPA_WPA2 = 4
