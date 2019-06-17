require 'config_helper'
require 'wifi_helper'

local config = load_config()
if not config then
  print('failed to load config')
  return
end

apply_wifi_config(config, function()
  dofile('main.lua')(config)
end)
