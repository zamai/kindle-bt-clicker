-- longpress.lua: short press / long press on one key of a BT remote -> two commands.
-- Needed because the RL7's uhid device has no EV_REP, so kindle-button-mapper
-- never sees a long press (it waits for autorepeat events).
--
-- usage: luajit longpress.lua "Device Name" KEYCODE THRESHOLD_MS "short cmd" "long cmd"
-- Grabs the device, survives disconnects (rescans /proc/bus/input/devices).
--
-- Kindle power handling (powerd over lipc):
--  * a press while the screen saver is up only wakes the Kindle; it doesn't turn a page.
--  * every page turn resets the screen-saver timer, like a touch does.
local ffi = require("ffi")
ffi.cdef[[
struct ev { long sec; long usec; uint16_t type; uint16_t code; int32_t value; };
struct pollfd { int fd; short events; short revents; };
int open(const char*, int); int close(int); long read(int, void*, unsigned long);
int poll(struct pollfd*, unsigned long, int); int ioctl(int, unsigned long, ...);
struct timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int, struct timespec*);
unsigned int sleep(unsigned int);
]]
local C = ffi.C
local NAME, KEY = arg[1], tonumber(arg[2])
local THRESH, SHORT, LONG = tonumber(arg[3] or "500"), arg[4], arg[5]
local EVIOCGRAB = 0x40044590

local function now_ms()
  local ts = ffi.new("struct timespec"); C.clock_gettime(1, ts)
  return tonumber(ts.tv_sec) * 1000 + tonumber(ts.tv_nsec) / 1e6
end
local function log(...) io.write(os.date("%H:%M:%S "), string.format(...), "\n"); io.flush() end
local function run(cmd) log("run: %s", cmd); os.execute(cmd .. " >/dev/null 2>&1 &") end

local POWERD = "com.lab126.powerd"
local WAKE_GRACE_MS = 3000   -- after a wake, ignore presses until powerd says "active" (or this passes)

-- powerd state: "active", "screenSaver", "readyToSuspend", ... nil if lipc fails (then assume awake).
local function power_state()
  local h = io.popen("lipc-get-prop " .. POWERD .. " state 2>/dev/null"); if not h then return nil end
  local s = h:read("*l"); h:close(); return s
end
local function asleep() local s = power_state(); return s ~= nil and s ~= "" and s ~= "active", s end
local function wake() run("lipc-set-prop " .. POWERD .. " powerButton 1") end
local function activity() run("lipc-set-prop -i " .. POWERD .. " touchScreenSaverTimeout 1") end
local function turn(cmd) run(cmd); activity() end

local function find_dev()
  local f = io.open("/proc/bus/input/devices"); if not f then return nil end
  local txt = f:read("*a"); f:close()
  for block in (txt .. "\n\n"):gmatch("(.-)\n\n") do
    if block:find('N: Name="' .. NAME .. '"', 1, true) then
      local ev = block:match("Handlers=[^\n]-(event%d+)")
      if ev then return "/dev/input/" .. ev end
    end
  end
end

local e, p = ffi.new("struct ev"), ffi.new("struct pollfd[1]")
log("watching %q key %d, long >= %d ms", NAME, KEY, THRESH)
while true do
  local path = find_dev()
  local fd = path and C.open(path, 0) or -1
  if fd < 0 then C.sleep(3) else
    C.ioctl(fd, EVIOCGRAB, ffi.cast("int", 1))
    log("opened %s", path)
    p[0].fd, p[0].events = fd, 1
    local down_at, fired = nil, false   -- fired: this press is used up (long turn done, or it woke the Kindle)
    local woke_at = nil
    while true do
      local timeout = -1
      if down_at and not fired then timeout = math.max(0, math.floor(down_at + THRESH - now_ms())) end
      local r = C.poll(p, 1, timeout)
      if r == 0 then                       -- held past threshold: long press
        fired = true; turn(LONG)
      elseif r > 0 then
        if bit.band(p[0].revents, 0x18) ~= 0 then break end      -- POLLERR|POLLHUP
        if C.read(fd, e, ffi.sizeof(e)) ~= ffi.sizeof(e) then break end
        if e.type == 1 and e.code == KEY then
          if e.value == 1 then
            down_at, fired = now_ms(), false
            local zz, st = asleep()
            if zz then
              fired = true   -- this press only wakes; no page turn on press or release
              if woke_at and down_at - woke_at < WAKE_GRACE_MS then
                log("still waking (%s), press ignored", st)
              else
                log("asleep (%s), waking", st); woke_at = down_at; wake()
              end
            end
          elseif e.value == 0 and down_at then
            if not fired then turn(SHORT) end
            down_at = nil
          end
        end
      end
    end
    C.close(fd); log("device gone")
  end
end
