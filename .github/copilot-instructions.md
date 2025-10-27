## Purpose

This repository is a small LuCI plugin for OpenWrt that provides "闪讯自动拨号" (automatic PPPoE password retrieval and redial via SMS). These instructions give AI coding agents the minimal, concrete knowledge needed to be productive when making changes to this codebase.

## Big picture

- Layout: LuCI Lua MVC style under `lib/lua/luci`:
  - `controller/` registers web endpoints and invokes actions (`shanxun.lua`).
  - `model/cbi/` defines the configuration UI (CBI forms) (`shanxun_.lua`).
  - `view/` contains the page template used to show status and call actions (`shanxun/status.htm`).
- There is a helper binary `bin/shanxun-autodial` invoked by the controller/view for status, refresh, once, etc. The project relies on system services (ubus, network interface) and on filesystem UCI config `shanxun`.

## Key files and examples

- `lib/lua/luci/controller/shanxun.lua`
  - Registers pages under `admin/network/shanxun` and an action endpoint `.../action` (GET param `m`).
  - Recognized actions: `refresh`, `redial`, `check`, `uninstall`.
  - Uses `exec_bg(cmd)` to run background commands like `/usr/bin/shanxun-autodial refresh >/dev/null 2>&1 &` and `ubus call network.interface.<iface> up`.
  - Whitelists `iface` with pattern `^[%w%-]+$` before embedding into shell commands.

- `lib/lua/luci/model/cbi/shanxun_.lua`
  - Builds the CBI settings page. Reads interfaces via `luci.model.network` and prefers `pppoe` or `wan`.
  - Uses UCI cursor: `uci:get("shanxun","config","iface")` and validates the value before use.
  - Status DummyValue calls `ubus -S call network.interface.<iface> status` and parses JSON with `luci.jsonc`.

- `lib/lua/luci/view/shanxun/status.htm`
  - Renders current status by executing `/usr/bin/shanxun-autodial status` and shows last 20 log lines (default `/var/log/shanxun.log`).
  - JS uses `fetch()` against the action URL built with `luci.dispatcher.build_url("admin","network","shanxun","action")?m=<action>`.
  - Log path is validated with an allowlist regex and rejects `..`.

## Project-specific patterns and conventions

- Security-first shell usage: any user/uci-provided value is validated before concatenating into shell commands. Examples:
  - `iface` allowed only `^[%w%-]+$` in both controller and model.
  - `log_file` validated against `^[a-zA-Z0-9_./-]+$` and blocked if it contains `..`.
- Background tasks: long-running ops are started with stdout/stderr redirected and `&` to background. Controller expects the command to start and returns a JSON {ok=boolean}.
- Use of system primitives: `ubus` for network control/status, `luci.sys.exec` for running commands and collecting output, `luci.model.uci` for configuration.

## Integration points and external dependencies

- Runtime: OpenWrt LuCI environment (Lua 5.x, ubus, uci, luci modules). The view/controller assume these modules are present.
- Binaries: `bin/shanxun-autodial` and an uninstall helper `shanxun-uninstall` are invoked; tests/changes should consider their presence or mock them.
- Network: interacts with `network.interface.<iface>` over `ubus` (e.g., `ubus call network.interface.wan up`).

## Concrete examples for edits/tests

- To add a new action `m=foo`, update `controller/shanxun.lua` do_action() to handle it and call an executable safely. Validate any query parameters before using in commands.
- To change the status display, modify `view/shanxun/status.htm` — use `luci.sys.exec()` for server-side output and sanitize file paths like the existing code.
- To mock behavior during unit testing (if adding tests), avoid calling binaries directly; wrap external calls in small helper functions that can be replaced.

## Quick check-list for changes an agent might make

1. Find the relevant file under `lib/lua/luci`.
2. Keep UCI usage consistent (`luci.model.uci`.cursor()).
3. Preserve or add input validation when values are used in shell commands (follow `iface` / `log_file` patterns).
4. When adding background commands, follow redirect-and-ampersand style: `... >/dev/null 2>&1 &`.
5. If touching the UI, update both the CBI model and view where appropriate.

## What I could not infer (ask the maintainer)

- Exact build/install workflow for packaging this LuCI app into an OpenWrt package (Makefile or SDK usage isn't present). If you expect CI packaging or opkg packaging, provide the repository's OpenWrt package Makefile and CI instructions.
- Any runtime configuration assumptions about the helper binaries (location, expected behavior) beyond what is referenced in code.

If anything here is unclear or you want extra lines (packaging steps, tests, or CI), tell me what to add and I'll iterate.
