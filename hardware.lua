-- File : hardware.lua
-- Management of hardware events

local module = {}

local tempPin = 1	-- DS18B20 (GPIO_05)
local valvePin = 2	-- relais for valve (GPIO_04)
local valvePin2 = 7	-- valve #2 (GPIO_13)

local addr		-- address of 1wire DS18B20

local valveOpen = false		-- valve status
local valveOpen2 = false	-- valve2 status


function module.setup()

  --ensure that ADC is reading internal voltage
  if adc.force_init_mode(adc.INIT_VDD33) then
    node.restart()
    return  -- restart is scheduled, just wait for reboot
  end

  -- setup ralais pin
  gpio.mode(valvePin, gpio.OUTPUT)
  gpio.mode(valvePin2, gpio.OUTPUT)

  -- setup DS18B20 wire
  ow.setup(tempPin)
  local count = 0
  local crc
  repeat
    count = count + 1
    ow.reset_search(tempPin)
    addr = ow.search(tempPin)
    tmr.wdclr()
  until ( (addr == nil) or (count > 100) )
  if (addr == nul) then
    print("No address for temperature sensor!")
  else
    print(addr:byte(1,8))
    crc = ow.crc8(string.sub(addr,1,7))
    if (crc == addr:byte(8)) then
      if ((addr:byte(1) == 0x10) or (addr:byte(1) == 0x28)) then
        print("Device is a DS18S20 family device")
      else
        print("Device family is not recognized")
	addr = nil
      end
    else
      print("CRC is not valid")
      addr = nil
    end
  end

  -- setup timer for valve closing
  tmr.register(config.CLOSEVALVE, config.VALVE_TO*1000, tmr.ALARM_SEMI, module.closeValve)
  tmr.register(config.CLOSEVALVE2, config.VALVE_TO2*1000, tmr.ALARM_SEMI, module.closeValve2)
  -- just in case.... close valve
  module.closeValve()
  module.closeValve2()
end



function module.openValve()
  gpio.write(valvePin, gpio.HIGH)
  valveOpen = true

  -- close valve after timeout
  tmr.start(config.CLOSEVALVE)
end


function module.openValve2()
  gpio.write(valvePin2, gpio.HIGH)
  valveOpen2 = true

  -- close valve after timeout
  tmr.start(config.CLOSEVALVE2)
end


function module.closeValve()
  -- stop timer
  tmr.stop(config.CLOSEVALVE)

  gpio.write(valvePin, gpio.LOW)
  valveOpen = false
end


function module.closeValve2()
  -- stop timer
  tmr.stop(config.CLOSEVALVE2)

  gpio.write(valvePin2, gpio.LOW)
  valveOpen2 = false
end


function module.isValveOpen()
  return valveOpen
end


function module.isValveOpen2()
  return valveOpen2
end


function module.readVoltage()
  return adc.readvdd33()
end


function module.readTemp()
  local present
  local data
  local i
  local crc
  local t

  if (addr == nil) then
    print "Temperature sensor not ready"
    return "Not ready"
  end

  ow.reset(tempPin)
  ow.select(tempPin, addr)
  ow.write(tempPin, 0x44, 1)
  tmr.delay(1000000)
  present = ow.reset(tempPin)
  ow.select(tempPin, addr)
  ow.write(tempPin, 0xBE, 1)
  -- print("P="..present)
  data = nil
  data = string.char(ow.read(tempPin))
  for i = 1, 8 do
    data = data .. string.char(ow.read(tempPin))
  end
  -- print(data:byte(1,9))
  crc = ow.crc8(string.sub(data,1,8))
  -- print("CRC="..crc)
  if (crc == data:byte(9)) then
    t = (data:byte(1) + data:byte(2) * 256)

    -- handle negative temperatures
    if (t > 0x7fff) then
      t = t - 0x10000
    end

    if (addr:byte(1) == 0x28) then
      t = t * 625      -- DS18B20, 4 fractional bits
    else
      t = t * 5000     -- DS18S20, 1 fractional bit
    end

    local sign = ""
    if (t<0) then
      sign = "-"
      t = -1 * t
    end

    -- Separate integral and decimal portions, for integer firmware only
    local t1 = string.format("%d", t / 10000)
    local t2 = string.format("%04u", t % 10000)
    local temp = sign .. t1 .. "." .. t2
    print("Temperature= " .. temp .. " Celsius")
    return temp
  end
  tmr.wdclr()
end

return module
