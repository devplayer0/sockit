MULTICAST_GROUP = '224.0.0.220'
PORT = 40420
MAGIC = 'SKIT'

DISC_SEARCH = 0x00

local name = 'Real device'
local description = 'A real Sockit!'

net.multicastJoin('any', MULTICAST_GROUP)
local disc_socket = net.createUDPSocket()
disc_socket:listen(PORT)
disc_socket:on('receive', function(sock, data, port, addr)
  if string.sub(data, 1, 4) ~= MAGIC then
    print(string.format('ignoring packet from %s with invalid magic', addr))
    return
  end
  if string.len(data) < 5 then
    print(string.format('ignoring discovery request from %s (too short)', addr))
    return
  end

  local req_type = struct.unpack('B', string.sub(data, 5))
  if req_type == DISC_SEARCH then
    print(string.format('sending beacon to %s', addr))
    local beacon = struct.pack('c0>HBc0c0', MAGIC, PORT, string.len(name), name, description)
    sock:send(port, addr, beacon)
  else
    print(string.format('ignoring invalid discovery request 0x%02x from %s', req_type, addr))
  end
end)
-- vim:ts=2 sw=2 expandtab
