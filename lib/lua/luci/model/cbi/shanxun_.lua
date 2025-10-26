local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"
local jsonc = require "luci.jsonc"

m = Map("shanxun", translate("闪讯自动拨号"),
  translate("拨号失败后通过短信自动取回密码，更新 PPPoE 密码并重拨。"))

s = m:section(TypedSection, "shanxun", translate("运行参数"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("启用"))
o.rmempty = false
o.default = o.enabled

-- 接口列表（优先列出 pppoe）- 修复版本
o = s:option(ListValue, "iface", translate("拨号接口"))
local ni = require "luci.model.network".init()
local ifaces = ni:get_interfaces() or {}
local added = {}

for _,ifc in ipairs(ifaces) do
  if ifc and type(ifc) == "table" then
    local n = ifc:name()
    local p = nil
    
    -- 安全地获取协议类型
    if ifc.proto then
      p = ifc:proto()
    elseif ifc.get_proto then
      p = ifc:get_proto()
    end
    
    -- 如果是 pppoe 协议或者是 wan 接口，则添加到列表
    if (p == "pppoe" or n == "wan") and n and not added[n] then 
      o:value(n)
      added[n] = true 
    end
  end
end

-- 如果没有找到任何接口，至少添加 wan
if not next(added) then
  o:value("wan")
  added["wan"] = true
end

-- 添加当前配置的接口（如果不在列表中）
local current_iface = uci:get("shanxun", "config", "iface") or "wan"
if current_iface and not added[current_iface] then
  o:value(current_iface)
end

o.default = current_iface

o = s:option(Value, "sms_device", translate("短信设备"), translate("例如 /dev/ttyUSB2 或 /dev/ttyACM0"))
o.datatype = "device"
o.default = "/dev/ttyUSB2"

o = s:option(Value, "sms_baud", translate("串口波特率"))
o.datatype = "uinteger"
o.default = "115200"

o = s:option(Value, "sms_number", translate("短信号码"))
o.datatype = "string"
o.default = "10000"

o = s:option(Value, "sms_text", translate("短信内容"))
o.datatype = "string"
o.default = "MM"

o = s:option(Value, "sms_sender_filter", translate("过滤短信来源"), translate("可选。例如仅接受来自 10000 的短信"))
o.datatype = "string"

o = s:option(Value, "password_regex", translate("密码正则(可选)"))
o.placeholder = "密码[^0-9]*([0-9]{4,32})"

o = s:option(Value, "expiry_regex", translate("有效期正则(可选)"))
o.placeholder = "([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})"

o = s:option(Value, "check_interval", translate("检测间隔(秒)"))
o.datatype = "uinteger"
o.default = "30"

o = s:option(Value, "dial_timeout", translate("拨号等待(秒)"))
o.datatype = "uinteger"
o.default = "20"

o = s:option(Value, "retries", translate("拨号重试次数"))
o.datatype = "uinteger"
o.default = "2"

o = s:option(Value, "sms_wait", translate("短信等待(秒)"))
o.datatype = "uinteger"
o.default = "60"

o = s:option(Value, "sms_send_cmd", translate("自定义发送命令"),
  translate("可使用 {dev} {baud} {num} {msg} 占位符；留空使用缺省的 sms-tool 语法"))
o.placeholder = "sms-tool -d {dev} -b {baud} send {num} \"{msg}\""

o = s:option(Value, "sms_recv_cmd", translate("自定义读取命令"),
  translate("可使用 {dev} {baud}；例如：sms-tool -d {dev} -b {baud} read --newest"))
o.placeholder = "sms-tool -d {dev} -b {baud} read --newest"
-- --- BEGIN ENHANCEMENT: ServerChan ---
o = s:option(Value, "sc_key", translate("ServerChan SendKey"),
  translate("可选。填入 SendKey 以便在获取新密码时推送通知。需要先安装 curl。"))
o.placeholder = "SCT..."
-- --- END ENHANCEMENT ---

-- 只读状态
o = s:option(DummyValue, "_status", translate("当前状态"))
function o.cfgvalue(self, section)
  local iface = uci:get("shanxun","config","iface") or "wan"
  local j = sys.exec("ubus -S call network.interface."..iface.." status 2>/dev/null")
  local d = jsonc.parse(j or "{}") or {}
  local up = (d.up == true)
  local ip = ""
  if d["ipv4-address"] and d["ipv4-address"][1] then ip = d["ipv4-address"][1].address or "" end
  return (up and translatef("已连接，IP：%s", ip)) or translate("未连接")
end

o = s:option(DummyValue, "_last", translate("最近一次取密"))
function o.cfgvalue(self, section)
  local pass = uci:get("shanxun","config","last_password") or ""
  local exp  = uci:get("shanxun","config","last_expiry") or ""
  local t    = uci:get("shanxun","config","last_sms_time") or ""
  local shown = (pass ~= "" and (pass:gsub("^(..).*","%1*******")) or "-")
  return string.format("密码：%s / 有效期：%s / 收到：%s", shown, (exp ~= "" and exp or "-"), (t ~= "" and t or "-"))
end

return m