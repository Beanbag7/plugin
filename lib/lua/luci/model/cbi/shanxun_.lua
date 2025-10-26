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
o.default = "1"

-- 接口列表（优先列出 pppoe）- 修复版本
o = s:option(ListValue, "iface", translate("拨号接口"))
local ni = require "luci.model.network".init()
local ifaces = ni:get_interfaces() or {}
local added = {}

for _,ifc in ipairs(ifaces) do
  if ifc and type(ifc) == "table" then
    local n = ifc:name()
    local p = nil

    -- 安全地获取协议类型（兼容不同实现）
    if ifc.proto then
      p = ifc:proto()
    elseif ifc.get_proto then
      p = ifc:get_proto()
    end

    if (p == "pppoe" or n == "wan") and n and not added[n] then 
      o:value(n)
      added[n] = true 
    end
  end
end

if not next(added) then
  o:value("wan")
  added["wan"] = true
end

local current_iface = uci:get("shanxun", "config", "iface") or "wan"
if current_iface and not current_iface:match("^[%w%-]+$") then
  current_iface = "wan"
end
if current_iface and not added[current_iface] then
  o:value(current_iface)
end

o.default = current_iface

o = s:option(Value, "sms_device", translate("短信设备"), translate("例如 /dev/ttyUSB2 或 /dev/ttyACM0"))
o.datatype = "device"
o.default = "/dev/ttyUSB2"

-- ... rest unchanged ...

-- 只读状态（增强：对 iface 做白名单校验，防止命令注入）
o = s:option(DummyValue, "_status", translate("当前状态"))
function o.cfgvalue(self, section)
  local iface = uci:get("shanxun","config","iface") or "wan"
  if not iface:match("^[%w%-]+$") then
    iface = "wan"
  end
  local j = sys.exec("ubus -S call network.interface."..iface.." status 2>/dev/null")
  local d = jsonc.parse(j or "{}") or {}
  local up = (d.up == true)
  local ip = ""
  if d["ipv4-address"] and d["ipv4-address"][1] then ip = d["ipv4-address"][1].address or "" end
  return (up and translatef("已连接，IP：%s", ip)) or translate("未连接")
end

return m
