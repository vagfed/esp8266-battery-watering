-- file : application.lua

local module = {}

local m = nil



local function register_myself()
  m:subscribe(config.ENDPOINT .. config.VALVE,0)
  m:subscribe(config.ENDPOINT .. config.VALVE2,0)
end

local function updateBroker()
  print("Publishing topic=" .. config.ENDPOINT .. config.TEMPERATURE .. " data=" .. hardware.readTemp())
  m:publish(config.ENDPOINT .. config.TEMPERATURE, hardware.readTemp(),0,0)
  
  print("Publishing topic=" .. config.ENDPOINT .. config.IRRIGATING .. " data=" .. tostring(hardware.isValveOpen()))
  m:publish(config.ENDPOINT .. config.IRRIGATING, tostring(hardware.isValveOpen()),0,0)

  print("Publishing topic=" .. config.ENDPOINT .. config.IRRIGATING2 .. " data=" .. tostring(hardware.isValveOpen2()))
  m:publish(config.ENDPOINT .. config.IRRIGATING2, tostring(hardware.isValveOpen2()),0,0)

  print("Publishing topic=" .. config.ENDPOINT .. config.VOLTAGE .. " data=" .. hardware.readVoltage())
  m:publish(config.ENDPOINT .. config.VOLTAGE, hardware.readVoltage(),0,0)
end


local function messageReceived(conn, topic, data)
    if data ~= nil then
      print("Received topic=" .. topic .. " data=" .. data)
    else
      print("Received topic=" .. topic .. " no-data")
    end
    if data ~= nil then
      -- do domething, we have received a message
      if (topic == config.ENDPOINT .. config.VALVE) then
        if (data == "open") then
          hardware.openValve()
	elseif (data == "close") then
	  hardware.closeValve()
	else
	  print("Ignoring \"valve\" topic with data=\"data\"")
	end
	updateBroker()
      elseif (topic == config.ENDPOINT .. config.VALVE2) then
        if (data == "open") then
          hardware.openValve2()
	elseif (data == "close") then
	  hardware.closeValve2()
	else
	  print("Ignoring \"valve2\" topic with data=\"data\"")
	end
	updateBroker()
      else
	print("Ignoring unexpected message")
      end
    end
end


local function mqtt_connected(conn)
    print(node.heap())
    print("Connected to MQTT");
    register_myself()
    updateBroker()
    m:publish(config.ENDPOINT .. config.CONNECTED, "1",0,0)
end

local function mqtt_disconnected(conn, reason)
   print("Could not connect to MQTT! Reason = " .. reason)
   print("Deep sleeping for " .. config.DSLEEP .. " minutes")
   node.dsleep(config.DSLEEP * 60 * 1000000, 1)
end

local function mqtt_start()
  print("MQTT setup: clientId=" .. config.ID .. " User=" .. config.USER .. " Password=" .. config.PASSWORD)
  m = mqtt.Client(config.ID, 30, config.USER, config.PASSWORD, 1)  -- 30 sec keepalive

  -- last will: tell I am offline when I deep sleep
  m:lwt(config.ENDPOINT .. config.CONNECTED, "0", 0, 0)

  -- register message callback beforehead
  m:on("message", messageReceived)

  -- connect to broker
  -- host, port, secure, autoreconnect, callback when connected
  print("Connecting to MQTT " .. config.HOST .. ":" .. config.PORT)
  print(node.heap())
  m:connect(config.HOST, config.PORT, 1, 1, mqtt_connected, mqtt_disconnected)
end




local function hardware_start()
  hardware.setup()
end
 

local function check_status()
  print("Checking hardware status")
  if (hardware.isValveOpen() or hardware.isValveOpen2()) then
    print("A valve is still open. Waiting...")
    print("Valve = " .. tostring(hardware.isValveOpen()))
    print("Valve2 = " .. tostring(hardware.isValveOpen2()))
    tmr.start(config.CHECKSTATUS)
    return
  end

  print("All valves are closed. Updating broker and deep sleeping...")
  updateBroker()
  m:publish(config.ENDPOINT .. config.CONNECTED, "0", 0, 0)

  print("Deep sleeping in 15 secs for " .. config.DSLEEP .. " mins")

  tmr.alarm(config.WAIT4DSLEEP, 15000, tmr.ALARM_SINGLE, function()
      m:close();
      print("dsleep NOW!")
      node.dsleep(config.DSLEEP * 60 * 1000000, 1)
    end)
end






function module.start()
  hardware_start()
  mqtt_start()
  
  tmr.register(config.CHECKSTATUS, config.CHECK_TO * 1000, tmr.ALARM_SEMI, check_status)
  tmr.start(config.CHECKSTATUS)
end




return module
