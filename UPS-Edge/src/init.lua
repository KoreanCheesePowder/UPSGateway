local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local ltn12 = require "ltn12"
local json = require "st.json"

local CAP_STATUS = "buildbook37604.eatonUpsStatus"
local CAP_RUNTIME = "buildbook37604.upsRuntime"
local CAP_LOAD = "buildbook37604.eatonUpsLoad"
local CAP_INFO = "buildbook37604.driverInformation"
local CAP_SYNC = "buildbook37604.eatonUpsGatewaySyncV2"
local CAP_SUMMARY = "buildbook37604.eatonupssummaryv294"

local status_cap = capabilities[CAP_STATUS]
local runtime_cap = capabilities[CAP_RUNTIME]
local load_cap = capabilities[CAP_LOAD]
local info_cap = capabilities[CAP_INFO]
local summary_cap = capabilities[CAP_SUMMARY]

local DRIVER_VERSION = "v3.0.0"
local GATEWAY_DNI = "eaton-ups-gateway"
local UPS_PROFILE = "cp-eaton-ups-device-dashboard"
local POLL_TIMER_FIELD = "eaton_ups_local_poll_timer_v1"
local FAILURES_FIELD = "eaton_ups_local_failures_v1"

http.TIMEOUT = 10

local function fmt_runtime(seconds)
  local n = tonumber(seconds) or 0
  local mins = math.floor(n / 60)
  local secs = n % 60
  if mins >= 60 then
    local hours = math.floor(mins / 60)
    mins = mins % 60
    return string.format("%d시간 %d분 %d초", hours, mins, secs)
  end
  return string.format("%d분 %d초", mins, secs)
end

local function friendly_status(raw, ok)
  if ok == false then return "통신 오류" end
  raw = tostring(raw or "")
  if string.find(raw, "OB") and string.find(raw, "LB") then return "배터리 부족" end
  if string.find(raw, "LB") then return "배터리 부족" end
  if string.find(raw, "OB") then return "배터리 운전" end
  if string.find(raw, "OL") then return "정상 전원" end
  return "통신 오류"
end

local function power_source(raw, ok)
  if ok == false then return "unknown" end
  raw = tostring(raw or "")
  if string.find(raw, "OB") then return "battery" end
  if string.find(raw, "OL") then return "mains" end
  return "unknown"
end

local function find_by_dni(driver, dni)
  for _, d in ipairs(driver:get_devices()) do
    if d.device_network_id == dni then
      return d
    end
  end
  return nil
end

local function ensure_gateway(driver)
  if find_by_dni(driver, GATEWAY_DNI) then
    return
  end
  local metadata = {
    type = "LAN",
    device_network_id = GATEWAY_DNI,
    label = "C.P Eaton UPS Gateway",
    profile = "cp-eaton-ups-gateway",
    manufacturer = "C.P",
    model = "Eaton UPS Gateway",
    vendor_provided_label = "C.P Eaton UPS Gateway"
  }
  log.info("Creating Eaton UPS Gateway")
  driver:try_create_device(metadata)
end

local function discovery_handler(driver, opts, should_continue)
  ensure_gateway(driver)
end

local function find_ups(driver, ups_id)
  return find_by_dni(driver, "eaton-ups-" .. tostring(ups_id))
end

local function create_ups(driver, ups_id, name)
  local dni = "eaton-ups-" .. tostring(ups_id)
  if find_by_dni(driver, dni) then return end
  local metadata = {
    type = "LAN",
    device_network_id = dni,
    label = tostring(name),
    profile = UPS_PROFILE,
    manufacturer = "EATON",
    model = "Ellipse ECO",
    vendor_provided_label = tostring(name)
  }
  driver:try_create_device(metadata)
end

local function emit_info(device)
  if info_cap then
    if info_cap.author then device:emit_event(info_cap.author("치즈가루")) end
    if info_cap.driverVersion then device:emit_event(info_cap.driverVersion(DRIVER_VERSION)) end
  end
end

local function emit_ups(device, a)
  local b = tonumber(a.battery) or 0
  local rt = tonumber(a.runtime) or 0
  local ld = tonumber(a.load) or 0
  local rw = tonumber(a.ratedWatts) or 400

  device:emit_event(capabilities.battery.battery({value=b}))
  device:emit_event(capabilities.powerSource.powerSource(power_source(a.status, a.ok)))
  device:emit_event(capabilities.powerMeter.power({value=(rw * ld / 100.0), unit="W"}))

  if status_cap and status_cap.status then
    device:emit_event(status_cap.status(friendly_status(a.status, a.ok)))
  end
  if summary_cap and summary_cap.summary then
    device:emit_event(summary_cap.summary(string.format("%s    %g%%", fmt_runtime(rt), ld), {state_change=true}))
  end
  if runtime_cap and runtime_cap.runtimeText then
    device:emit_event(runtime_cap.runtimeText(fmt_runtime(rt)))
  end
  if load_cap and load_cap.load then
    device:emit_event(load_cap.load(ld))
  end
  emit_info(device)
end

local function local_api_url(device)
  local ip = tostring((device.preferences or {}).nasIp or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if ip == "" then return nil end
  local port = tonumber((device.preferences or {}).apiPort) or 8766
  return string.format("http://%s:%d/api/ups/latest", ip, port)
end

local function stop_poll_timer(device)
  local timer = device:get_field(POLL_TIMER_FIELD)
  if timer then
    pcall(function() device.thread:cancel_timer(timer) end)
    device:set_field(POLL_TIMER_FIELD, nil)
  end
end

local function apply_local_results(driver, gateway, payload)
  local active = {}
  local created = false
  for _, item in ipairs(payload.ups or {}) do
    local ups_id = tostring(item.id or "")
    if ups_id ~= "" then
      active[ups_id] = true
      local ups = find_ups(driver, ups_id)
      if not ups then
        create_ups(driver, ups_id, item.name or ups_id)
        created = true
      else
        emit_ups(ups, {
          battery = item.battery,
          status = item.status,
          runtime = item.runtime,
          load = item.load,
          ratedWatts = item.ratedWatts,
          ok = item.ok,
          error = item.error
        })
        if item.ok == true then ups:online() else ups:offline() end
      end
    end
  end

  for _, device in ipairs(driver:get_devices()) do
    if device.device_network_id ~= GATEWAY_DNI then
      local ups_id = tostring(device.device_network_id):match("^eaton%-ups%-(.+)$")
      if ups_id and not active[ups_id] then device:offline() end
    end
  end

  gateway:set_field(FAILURES_FIELD, 0)
  gateway:online()
  return created
end

local function fetch_local_data(driver, gateway)
  local url = local_api_url(gateway)
  if not url then error("NAS IP is not configured") end

  local chunks = {}
  local ok, code, _, status = http.request({
    url = url,
    method = "GET",
    sink = ltn12.sink.table(chunks),
    headers = {Accept = "application/json"}
  })
  if not ok or tonumber(code) ~= 200 then
    error(string.format("Local API request failed: %s %s", tostring(code), tostring(status)))
  end

  local payload = json.decode(table.concat(chunks))
  if type(payload) ~= "table" or payload.ok ~= true or type(payload.ups) ~= "table" then
    error("Local API returned invalid UPS data")
  end
  local created = apply_local_results(driver, gateway, payload)
  log.info("Eaton UPS local API sync complete: " .. url)
  if created then
    gateway.thread:call_with_delay(3, function()
      pcall(fetch_local_data, driver, gateway)
    end, "eaton-ups-created-device-refresh")
  end
end

local function poll_local_data(driver, gateway)
  local ok, err = pcall(fetch_local_data, driver, gateway)
  if ok then return end
  local failures = (tonumber(gateway:get_field(FAILURES_FIELD)) or 0) + 1
  gateway:set_field(FAILURES_FIELD, failures)
  log.warn(string.format("Eaton UPS local API sync failed (%d): %s", failures, tostring(err)))
  if failures >= 3 then gateway:offline() end
end

local function start_poll_timer(driver, gateway)
  stop_poll_timer(gateway)
  local seconds = tonumber((gateway.preferences or {}).refreshSeconds) or 60
  seconds = math.max(10, math.min(3600, seconds))
  gateway.thread:call_with_delay(2, function()
    poll_local_data(driver, gateway)
  end, "eaton-ups-local-initial")
  local timer = gateway.thread:call_on_schedule(seconds, function()
    poll_local_data(driver, gateway)
  end, "eaton-ups-local-poll")
  gateway:set_field(POLL_TIMER_FIELD, timer)
end

local function upsert_handler(driver, device, command)
  local a = command.args or {}
  local ups_id = tostring(a.upsId or "")
  if ups_id == "" then return end

  local ups = find_ups(driver, ups_id)
  if not ups then
    create_ups(driver, ups_id, a.name or ups_id)
    return
  end
  emit_ups(ups, a)
end

local function emit_summary_from_cached_state(device)
  if not summary_cap or not summary_cap.summary then return end
  if device.device_network_id == GATEWAY_DNI then return end

  local runtime_text = device:get_latest_state("main", CAP_RUNTIME, "runtimeText")
  local load_value = device:get_latest_state("main", CAP_LOAD, "load")
  local load_num = tonumber(load_value)

  if runtime_text ~= nil and tostring(runtime_text) ~= "" and load_num ~= nil then
    local text = string.format("%s    %g%%", tostring(runtime_text), load_num)
    device:emit_event(summary_cap.summary(text, {state_change=true}))
    log.info("Dashboard summary restored: " .. text)
  end
end

local function added(driver, device)
  emit_info(device)

  if device.device_network_id == GATEWAY_DNI then
    start_poll_timer(driver, device)
  else
    -- Force existing UPS devices onto the refreshed profile/VID. Repackaging a
    -- driver does not always move an existing LAN device to the new presentation.
    device:try_update_metadata({profile = UPS_PROFILE})

    -- Restore the dashboard state from the persisted runtime/load states even
    -- before the gateway sends its next upsert. Retry after the profile switch.
    emit_summary_from_cached_state(device)
    device.thread:call_with_delay(3.0, function() emit_summary_from_cached_state(device) end, "restore-ups-summary-3s")
    device.thread:call_with_delay(10.0, function() emit_summary_from_cached_state(device) end, "restore-ups-summary-10s")
  end
end

local function info_changed(driver, device, event, args)
  if device.device_network_id == GATEWAY_DNI then
    device:set_field(FAILURES_FIELD, 0)
    start_poll_timer(driver, device)
  end
end

local function removed(driver, device)
  if device.device_network_id == GATEWAY_DNI then stop_poll_timer(device) end
end

local driver = Driver("cp-eaton-ups-gateway", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    added = added,
    init = added,
    infoChanged = info_changed,
    removed = removed
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = function(driver, device)
        if device.device_network_id == GATEWAY_DNI then poll_local_data(driver, device) end
      end
    },
    [CAP_SYNC] = {
      upsert = upsert_handler,
      reconcile = function() end
    }
  }
})

driver:run()
