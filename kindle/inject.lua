-- inject.lua: synthesize touch input on Kindle PW5 by writing MT protocol-B
-- events into the touchscreen evdev node. Run with KOReader's luajit.
--   luajit inject.lua tap X Y | swipe X1 Y1 X2 Y2 [ms] | next | prev | absinfo
local ffi = require("ffi")
ffi.cdef[[
int open(const char *path, int flags);
int close(int fd);
long write(int fd, const void *buf, unsigned long n);
int ioctl(int fd, unsigned long req, ...);
int usleep(unsigned int us);
struct input_event { long sec; long usec; uint16_t type; uint16_t code; int32_t value; };
struct input_absinfo { int32_t value, minimum, maximum, fuzz, flat, resolution; };
]]
local SCREEN_W, SCREEN_H = 1236, 1648
local DEV = os.getenv("TOUCH_DEV") or "/dev/input/event1"
local EV_SYN, EV_ABS, EV_KEY = 0, 3, 1
local ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR, ABS_MT_X, ABS_MT_Y, ABS_MT_TID, ABS_MT_PRESSURE, ABS_MT_DISTANCE = 0x2f, 0x30, 0x35, 0x36, 0x39, 0x3a, 0x3b
local fd = ffi.C.open(DEV, 2) -- O_RDWR
assert(fd >= 0, "cannot open " .. DEV)

local function absinfo(code)
  local a = ffi.new("struct input_absinfo")
  -- EVIOCGABS(code) = _IOR('E', 0x40 + code, struct input_absinfo[24 bytes])
  local req = bit.bor(bit.lshift(2, 30), bit.lshift(24, 16), bit.lshift(0x45, 8), 0x40 + code)
  assert(ffi.C.ioctl(fd, req, a) == 0, "EVIOCGABS failed")
  return a
end
local ax, ay = absinfo(ABS_MT_X), absinfo(ABS_MT_Y)
local function sx(x) return math.floor(ax.minimum + x * (ax.maximum - ax.minimum) / (SCREEN_W - 1) + 0.5) end
local function sy(y) return math.floor(ay.minimum + y * (ay.maximum - ay.minimum) / (SCREEN_H - 1) + 0.5) end

local ev = ffi.new("struct input_event")
local function emit(t, c, v) ev.type, ev.code, ev.value = t, c, v; ffi.C.write(fd, ev, ffi.sizeof(ev)) end
local function syn() emit(EV_SYN, 0, 0) end
local tid = 0  -- driver treats tracking id as a finger index: must be small

math.randomseed(os.time())
local function down(x, y)
  emit(EV_ABS, ABS_MT_SLOT, 0); emit(EV_ABS, ABS_MT_TID, tid)
  emit(EV_ABS, ABS_MT_X, sx(x)); emit(EV_ABS, ABS_MT_Y, sy(y))
  -- vary so the input core never drops them as "unchanged"
  emit(EV_ABS, ABS_MT_TOUCH_MAJOR, math.random(30, 60)); emit(EV_ABS, ABS_MT_PRESSURE, math.random(120, 200)); emit(EV_ABS, ABS_MT_DISTANCE, 0); syn()
end
local function move(x, y) emit(EV_ABS, ABS_MT_X, sx(x)); emit(EV_ABS, ABS_MT_Y, sy(y)); syn() end
local function up() emit(EV_ABS, ABS_MT_SLOT, 0); emit(EV_ABS, ABS_MT_TID, -1); syn() end

local cmd = arg[1]
local n = function(i) return tonumber(arg[i]) end
if cmd == "absinfo" then
  print(("x %d..%d  y %d..%d"):format(ax.minimum, ax.maximum, ay.minimum, ay.maximum))
elseif cmd == "tap" then
  down(n(2), n(3)); ffi.C.usleep(60000); move(n(2) + 1, n(3)); ffi.C.usleep(60000); up()
elseif cmd == "swipe" then
  local x1, y1, x2, y2, ms = n(2), n(3), n(4), n(5), n(6) or 300
  local steps = 12
  down(x1, y1)
  for i = 1, steps do
    ffi.C.usleep(ms * 1000 / steps)
    move(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
  end
  up()
elseif cmd == "next" then
  down(SCREEN_W - 120, SCREEN_H / 2); ffi.C.usleep(80000); up()
elseif cmd == "prev" then
  down(80, SCREEN_H / 2); ffi.C.usleep(80000); up()
else
  io.stderr:write("usage: tap X Y | swipe X1 Y1 X2 Y2 [ms] | next | prev | absinfo\n"); os.exit(2)
end
ffi.C.close(fd)
