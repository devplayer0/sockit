require 'config_helper'

STATUS_PIN = 7
gpio.mode(STATUS_PIN, gpio.OUTPUT)

function stop_wifi_timer()
  if wifi_timer then
    wifi_timer:unregister()
  end
  gpio.write(STATUS_PIN, gpio.HIGH)
end
function apply_wifi_config(config, cb)
  if wifi.getmode() == wifi.STATION then
    wifi.sta.disconnect()
  end
  stop_wifi_timer()

  if config.wifi.ap then
    local ssid = default_name()
    print('setting up ap '..ssid)

    gpio.write(STATUS_PIN, gpio.LOW)
    wifi.setmode(wifi.STATIONAP, false)
    wifi.sta.config({
      ssid = '',
      pwd = '',
      save = false,
      auto = false
    })
    wifi.ap.config({
      ssid = ssid,
      auth = wifi.OPEN,
      max = 1,
      save = false,
    })

    cb()
  else
    wifi.eventmon.unregister(wifi.eventmon.STA_CONNECTED)
    wifi.eventmon.unregister(wifi.eventmon.STA_GOT_IP)
    wifi.eventmon.unregister(wifi.eventmon.STA_DISCONNECTED)
    wifi.eventmon.unregister(wifi.eventmon.STA_DHCP_TIMEOUT)

    attempts = 0
    wifi.eventmon.register(wifi.eventmon.STA_CONNECTED, function(event)
      print('connected to '..event.SSID)
    end)
    wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, function(event)
      wifi.eventmon.unregister(wifi.eventmon.STA_CONNECTED)

      print('got ip '..event.IP..' from '..config.wifi.ssid)
      stop_wifi_timer()
      cb()
    end)
    wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, function(event)
      print('disconnected from '..event.SSID)
      if event.reason == wifi.eventmon.reason.ASSOC_LEAVE then
        -- we requested the disconnect (?)
        return
      end

      for key, val in pairs(wifi.eventmon.reason) do
        if val == event.reason then
          print('disconnect reason: '..val..' ('..key..')')
          break
        end
      end

      --if attempts < 3 then
      if true then
        attempts = attempts + 1
        print('retrying connection to '..event.SSID..' (attempt '..attempts..')')
      else
        wifi.eventmon.unregister(wifi.eventmon.STA_DISCONNECTED)

        config.wifi.ap = true
        apply_wifi_config(config, cb)
      end
    end)
    wifi.eventmon.register(wifi.eventmon.STA_DHCP_TIMEOUT, function()
      print('dhcp timeout connecting to '..config.wifi.ssid)
      config.wifi.ap = true
      save_config(config)
      apply_wifi_config(config, cb)
    end)

    print('connecting to '..config.wifi.ssid)

    wifi_timer = tmr.create()
    wifi_timer:alarm(500, tmr.ALARM_AUTO, function(timer)
      gpio.write(STATUS_PIN, gpio.read(STATUS_PIN) == gpio.HIGH and gpio.LOW or gpio.HIGH)
    end)
    wifi.setmode(wifi.STATION, false)
    wifi.sta.sethostname(default_name())
    wifi.sta.config({
      ssid = config.wifi.ssid,
      pwd = config.wifi.pwd,
      auto = true,
      save = false
    })
  end
end

function wifi_scan(cb)
  wifi.sta.getap(0, function(list)
    local count = 0
    local t = {}
    for ssid, info in pairs(list) do
      local authmode, rssi, bssid, channel = string.match(info, '([^,]+),([^,]+),([^,]+),([^,]+)')
      t[ssid] = {
        bssid = bssid,
        channel = channel,
        authmode = tonumber(authmode),
        rssi = tonumber(rssi)
      }
      count = count + 1
    end

    cb(count, t)
  end)
end
