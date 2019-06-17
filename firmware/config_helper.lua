function default_name()
  return string.format('Sockit-%x', node.chipid())
end

local CONFIG_TEMPLATE = [[
return {
  name = %q,
  description = %q,
  wifi = {
    ap = %s,
    ssid = %q,
    pwd = %q
  }
}
]]
local DEFAULT_CONFIG = {
  name = default_name(),
  description = 'A brand new Sockit',
  wifi = {
    ap = true,
    ssid = '',
    pwd = ''
  }
}

function save_config(config)
  local conf_file = file.open('config.lua', 'w')
  if not conf_file then
    return false
  end

  local conf_str = string.format(CONFIG_TEMPLATE, config.name, config.description, tostring(config.wifi.ap), config.wifi.ssid, config.wifi.pwd)
  conf_file:write(conf_str)
  conf_file:close()
  return true
end

function load_config()
  if not file.exists('config.lua') then
    print('writing default config')
    if not save_config(DEFAULT_CONFIG) then
      print('warning: failed to write default config')
    end
    return DEFAULT_CONFIG
  end

  return dofile('config.lua')
end
