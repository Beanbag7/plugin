module("luci.controller.shanxun", package.seeall)

function index()
if not nixio.fs.access("/etc/config/shanxun") then return end
local page = entry({"admin","network","shanxun"}, firstchild(), _("闪讯自动拨号"), 60)
page.dependent = false
entry({"admin","network","shanxun","status"}, template("shanxun/status"), _("状态"), 1)
entry({"admin","network","shanxun","settings"}, cbi("shanxun"), _("设置"), 2).leaf = true
entry({"admin","network","shanxun","action"}, call("do_action")).leaf = true
end

function do_action()
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local m = http.formvalue("m") or ""
local iface = uci:get("shanxun","config","iface") or "wan"
local ok = false

if m == "refresh" then
ok = (os.execute("/usr/bin/shanxun-autodial refresh >/dev/null 2>&1 &") == 0)
elseif m == "redial" then
ok = (os.execute("ubus call network.interface."..iface.." up >/dev/null 2>&1 &") == 0)
elseif m == "check" then
ok = (os.execute("/usr/bin/shanxun-autodial once >/dev/null 2>&1 &") == 0)
elseif m == "uninstall" then
ok = (os.execute("/usr/bin/shanxun-uninstall >/dev/null 2>&1 &") == 0)
else
http.status(400, "bad request")
http.write_json({ok=false, msg="unknown action"})
return
end

http.prepare_content("application/json")
http.write_json({ok=ok})
end
