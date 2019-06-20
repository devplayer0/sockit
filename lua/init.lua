require 'config_helper'
require 'wifi_helper'
require 'pins'
require 'main'

gpio.mode(RELAY_PIN, gpio.OUTPUT)

button_start = 0
BUTTON_PIN = 3
gpio.mode(BUTTON_PIN, gpio.INT)
gpio.trig(BUTTON_PIN, 'both', function(level, when, count)
  if level == gpio.LOW then
    button_start = when
  elseif when - button_start > 5*1000*1000 then
    if when - button_start > 20*1000*1000 then
      file.remove('config.lua')
    end
    node.restart()
  elseif when - button_start > 1*1000*1000 then
    print('forcing ap mode')
    local config = load_config()
    config.wifi.ap = true
    apply_wifi_config(config, function()
      main_stop()
      main_start(config)
    end)
  else
    print('button toggle output')
    gpio.write(RELAY_PIN, gpio.read(RELAY_PIN) == 1 and gpio.LOW or gpio.HIGH)
  end
end)

local config = load_config()
if not config then
  print('failed to load config')
  return
end

apply_wifi_config(config, function()
  main_start(config)
end)
