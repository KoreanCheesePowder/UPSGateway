local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

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

local DRIVER_VERSION = "v2.9.3"
local GATEWAY_DNI = "eaton-ups-gateway"
local UPS_PROFILE = "cp-eaton-ups-device-dashboard"

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

  if device.device_network_id ~= GATEWAY_DNI then
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

local driver = Driver("cp-eaton-ups-gateway", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    added = added,
    init = added
  },
  capability_handlers = {
    [CAP_SYNC] = {
      upsert = upsert_handler,
      reconcile = function() end
    }
  }
})

driver:run()
