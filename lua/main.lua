require 'config_helper'
require 'wifi_helper'
require 'pins'

MULTICAST_GROUP = '224.0.0.220'
PORT = 40420
MAGIC = 'SKIT'
UPGRADE_FILE = 'upgrade.img.gz'

DISC_SEARCH   = 0x00

REQ_GET_STATE = 0x00
REQ_SET_STATE = 0x01
REQ_SET_NAME  = 0x02
REQ_SET_DESC  = 0x03
REQ_GET_NET   = 0x04
REQ_GET_NETS  = 0x05
REQ_SET_NET   = 0x06
REQ_UPGRADE   = 0xcc

RES_OK        = 0x00
RES_ERROR     = 0xff

ERR_BAD_REQ   = 0x00
ERR_FAILED    = 0x01

function send_error(sock, e_type)
  local port, addr = sock:getpeer()
  print(string.format('sending error 0x%02x to %s', e_type, addr))

  local err = struct.pack('BB', RES_ERROR, e_type)
  sock:send(err, function()
    sock:close()
  end)
end
function check_string(sock, data)
  if #data == 0 then
    send_error(sock, ERR_BAD_REQ)
    return
  end

  local len = struct.unpack('B', string.sub(data, 1, 1))
  if #data < 1 + len then
    send_error(sock, ERR_BAD_REQ)
    return
  end

  return string.sub(data, 2, 1 + len)
end

function handle_upgrade(sock, data)
    if #data + upgrade_received > upgrade_size then
      print('warning: truncating incoming upgrade data')
      data = string.sub(data, 1, upgrade_size - upgrade_received)
    end

    if not upgrade_file:write(data) then
      upgrade_file:close()
      upgrade_file = nil
      send_error(sock, ERR_FAILED)
      return
    end
    upgrade_received = upgrade_received + #data
    print(string.format('received %d / %d bytes of upgrade data', upgrade_received, upgrade_size))

    if upgrade_received ~= upgrade_size then
      return
    end

    print(string.format('upgrade file sha1: %s', crypto.toHex(crypto.fhash('sha1', UPGRADE_FILE))))

    local res = struct.pack('B', RES_OK)
    sock:send(res, function()
      sock:close()
      upgrade_file:close()

      print('starting upgrade...')
      local err = node.flashreload(UPGRADE_FILE)
      if err then
        print(string.format("failed to apply upgrade: %s", err))
        local blinker = tmr.create()
        blinker:alarm(100, tmr.ALARM_AUTO, function(t)
          gpio.write(STATUS_PIN, gpio.read(STATUS_PIN) == gpio.HIGH and gpio.LOW or gpio.HIGH)
        end)

        tmr.create():alarm(3000, tmr.ALARM_SINGLE, function(t)
          blinker:unregister()
          node.restart()
        end)
      end
    end)
end
-- we assume a request fits within one packet
function handle_req(sock, data)
  if #data < 5 or string.sub(data, 1, 4) ~= MAGIC then
    send_error(sock, ERR_BAD_REQ)
    return
  end

  local port, addr = sock:getpeer()
  local req_type = struct.unpack('B', string.sub(data, 5))
  if req_type == REQ_GET_STATE then
    print(string.format('sending state to %s', addr))
    res = struct.pack('BB', RES_OK, gpio.read(RELAY_PIN))
  elseif req_type == REQ_SET_STATE then
    if #data < 6 then
      send_error(sock, ERR_BAD_REQ)
      return
    end

    local state = gpio.read(RELAY_PIN)
    local new_state = struct.unpack('B', string.sub(data, 6)) > 0 and gpio.HIGH or gpio.LOW
    print(string.format('%s setting state to %s (currently %d)', addr, tostring(new_state), state))
    gpio.write(RELAY_PIN, new_state)
    res = struct.pack('BB', RES_OK, state)
  elseif req_type == REQ_SET_NAME then
    local new_name = check_string(sock, string.sub(data, 6))
    if not new_name then
      return
    end

    print(string.format('%s setting name to %s', addr, new_name))
    config.name = new_name
    save_config(config)
    res = struct.pack('B', RES_OK)
  elseif req_type == REQ_SET_DESC then
    local new_desc = check_string(sock, string.sub(data, 6))
    if not new_desc then
      return
    end

    print(string.format('%s setting description to %s', addr, new_desc))
    config.description = new_desc
    save_config(config)
    res = struct.pack('B', RES_OK)
  elseif req_type == REQ_GET_NET then
    if config.wifi.ap then
      print(string.format('telling %s we have an ap', addr))
      res = struct.pack('BB', RES_OK, 1)
    else
      print(string.format('telling %s we\'re connected to %s', addr, config.wifi.ssid))
      res = struct.pack('BBBc0', RES_OK, 0, #config.wifi.ssid, config.wifi.ssid)
    end
  elseif req_type == REQ_GET_NETS then
    print('scanning for networks...')
    wifi_scan(function(count, list)
      print(string.format('sending %d networks to %s', count, addr))
      local res = struct.pack('BB', RES_OK, count)
      for ssid, info in pairs(list) do
        res = res .. struct.pack('BbBc0', info.authmode, info.rssi, #ssid, ssid)
      end

      sock:send(res, function()
        sock:close()
      end)
    end)
    return
  elseif req_type == REQ_SET_NET then
    if #data < 6 then
      send_error(sock, ERR_BAD_REQ)
      return
    end

    local mode = struct.unpack('B', string.sub(data, 6))
    if mode == 0 then
      local ssid = check_string(sock, string.sub(data, 7))
      if not ssid then
        return
      end
      local pwd = check_string(sock, string.sub(data, 8 + #ssid))
      if not pwd then
        return
      end

      print(string.format('%s setting wifi network to %s', addr, ssid))
      config.wifi.ap = false
      config.wifi.ssid = ssid
      config.wifi.pwd = pwd
    elseif mode == 1 then
      print(string.format('%s setting ap mode', addr))
      config.wifi.ap = true
    else
      send_error(sock, ERR_BAD_REQ)
      return
    end

    save_config(config)
    local res = struct.pack('B', RES_OK)
    sock:send(res, function()
      sock:close()
      apply_wifi_config(config, function()
        print('applied new config')
        main_stop()
        main_start(config)
      end)
    end)
    return
  elseif req_type == REQ_UPGRADE then
    if #data < 7 then
      send_error(sock, ERR_BAD_REQ)
      return
    end

    upgrade_size = struct.unpack('>H', string.sub(data, 6))
    print(string.format('expecting to receive %d byte firmware from %s', upgrade_size, addr))

    main_stop()
    upgrade_file = file.open(UPGRADE_FILE, 'w+')
    if not upgrade_file then
      send_error(sock, ERR_FAILED)
      return
    end

    upgrade_received = 0
    local initial_data = string.sub(data, 8)
    handle_upgrade(sock, initial_data)
    return
  else
    send_error(sock, ERR_BAD_REQ)
    return
  end

  sock:send(res, function()
    sock:close()
  end)
end

function main_start(conf)
  print('starting sockets')
  config = conf

  server = net.createServer()
  server:listen(PORT, function(sock)
    sock:on('receive', function(sock, data)
      if upgrade_file then
        handle_upgrade(sock, data)
        return
      end

      handle_req(sock, data)
    end)
  end)

  net.multicastJoin('any', MULTICAST_GROUP)
  disc_socket = net.createUDPSocket()
  disc_socket:listen(PORT)
  disc_socket:on('receive', function(sock, data, port, addr)
    if #data < 5 or string.sub(data, 1, 4) ~= MAGIC then
      print(string.format('ignoring invalid discovery request from %s', addr))
      return
    end

    local req_type = struct.unpack('B', string.sub(data, 5))
    if req_type == DISC_SEARCH then
      print(string.format('sending beacon to %s', addr))
      local beacon = struct.pack('c0>HBc0c0', MAGIC, PORT, #config.name, config.name, config.description)
      sock:send(port, addr, beacon)
    else
      print(string.format('ignoring invalid discovery request 0x%02x from %s', req_type, addr))
    end
  end)
end
function main_stop()
  print('closing sockets')
  if disc_socket then
    disc_socket:close()
    disc_socket = nil
  end
  if server then
    server:close()
    server = nil
  end
end
