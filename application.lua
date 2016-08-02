-- file : application.lua

local module = {}

local temperature = nil
local humidity

local polling = 20		-- hw polling period in seconds
local update  = 60		-- send message to broker (sec)
local waitForReconnect = 120	-- time to wait before reconnecting
local numReconnects = 0		-- times we have reconnected
local maxReconnects = 10	-- restart node when reached

local m = nil


-- send a simple ping to the broker
--local function send_ping()
--  m:publish(config.ENDPOINT .. "ping", "id=" .. config.ID,0,0)
--end


-- send my id to the broker for registration
local function register_myself()
  m:subscribe(config.ENDPOINT .. config.VALVE,0,function(conn)
      print("Subscribed to: " .. config.ENDPOINT .. config.VALVE)
      print()
    end)
  m:subscribe(config.ENDPOINT .. config.QUERY,0,function(conn)
      print("Subscribed to: " .. config.ENDPOINT .. config.QUERY)
      print()
    end)
  m:subscribe(config.ENDPOINT .. config.RESTART,0,function(conn)
      print("Subscribed to: " .. config.ENDPOINT .. config.RESTART)
      print()
    end)
end

local function updateBroker()
  if (temperature == nil) then
    return
  end
  

  --local msg = {}
  --msg.temperature = temperature
  --msg.humdity = humidity
  --msg.irrigation = hardware.isValveOpen()
  -- m:publish(config.ENDPOINT .. config.ID, cjson.encode(msg),0,0)

  print("Publishing topic=" .. config.ENDPOINT .. config.TEMPERATURE .. " data=" .. temperature)
  print("Publishing topic=" .. config.ENDPOINT .. config.HUMIDITY .. " data=" .. humidity)
  print("Publishing topic=" .. config.ENDPOINT .. config.IRRIGATING .. " data=" .. tostring(hardware.isValveOpen()))

  m:publish(config.ENDPOINT .. config.TEMPERATURE, temperature,0,1)
  m:publish(config.ENDPOINT .. config.HUMIDITY, humidity,0,1)
  m:publish(config.ENDPOINT .. config.IRRIGATING, tostring(hardware.isValveOpen()),1,1)
end


local function mqtt_start()
  print("MQTT setup: clientId=" .. config.ID .. " User=" .. config.USER .. " Password=" .. config.PASSWORD)
  m = mqtt.Client(config.ID, 120, config.USER, config.PASSWORD)  -- 120 sec keepalive

  m:lwt(config.ENDPOINT .. config.OFFLINE, "",0,0)

  -- register message callback beforehead
  m:on("message", function(conn, topic, data)
    if data ~= nil then
      print("Received topic=" .. topic .. " data=" .. data)
    else
      print("Received topic=" .. topic .. " no-data")
    end
    if data ~= nil then
      -- do domething, we have received a message
      if (topic == config.ENDPOINT .. config.QUERY) then
        updateBroker()
      elseif (topic == config.ENDPOINT .. config.RESTART) then
        print("Restarting...")
        node.restart()
      elseif (topic == config.ENDPOINT .. config.VALVE) then
        if (data == "open") then
          hardware.openValve()
	elseif (data == "close") then
	  hardware.closeValve()
	else
	  print("Ignoring \"valve\" topic with data=\"data\"")
	end
	updateBroker()
      else
	print("Ignoring unexpected message")
      end
    end
  end)

  -- connect to broker
  -- host, port, not_secure, autoreconnect, callback when connected
  print("Connecting to MQTT " .. config.HOST .. ":" .. config.PORT)
  m:connect(config.HOST, config.PORT, 1, 1, function(con)
    print("Connected to MQTT");
    numReconnects = 0
    register_myself()
  end
  , function(conn, reason)
      print("Could not connect to MQTT! Reason = " .. reason)
      numReconnects = numReconnects + 1
      if (numReconnects == maxReconnects) then
        print("Too many MQTT reconnects! Restarting")
        node.restart()
      end
      tmr.alarm(config.MQTT_CONN, waitForReconnect * 1000, tmr.ALARM_SINGLE, mqtt_start)
  end)
end


local function pollHW()
  temperature = hardware.readTemp()
  humidity = hardware.readSoilHumidity()
end


local function hardware_start()
  hardware.setup()
  pollHW()
  tmr.stop(config.HW_POLL)
  tmr.alarm(config.HW_POLL, polling * 1000, tmr.ALARM_AUTO, pollHW)
  tmr.stop(config.MQTT_UPD)
  tmr.alarm(config.MQTT_UPD, update * 1000, tmr.ALARM_AUTO, updateBroker)
end
 

function module.start()
  mqtt_start()
  hardware_start()
end






function module.send(data)
  m:publish(config.ENDPOINT .. config.ID, data, 0,0)
end


return module
