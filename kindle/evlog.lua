-- evlog.lua DEV SECONDS : print evdev key/rel/abs/msc events (32-bit input_event)
local ffi = require("ffi")
ffi.cdef[[
struct ev { long sec; long usec; uint16_t type; uint16_t code; int32_t value; };
int open(const char*, int); long read(int, void*, unsigned long);
struct pollfd { int fd; short events; short revents; };
int poll(struct pollfd*, unsigned long, int);
]]
local dev, secs = arg[1] or "/dev/input/event2", tonumber(arg[2] or "60")
local fd = ffi.C.open(dev, 0)
assert(fd >= 0, "open failed " .. dev)
local names = {[1]="KEY", [2]="REL", [3]="ABS", [4]="MSC"}
local e, p = ffi.new("struct ev"), ffi.new("struct pollfd[1]")
p[0].fd, p[0].events = fd, 1
local deadline = os.time() + secs
io.write("listening on ", dev, " for ", secs, "s\n"); io.flush()
while os.time() < deadline do
  if ffi.C.poll(p, 1, 1000) > 0 and ffi.C.read(fd, e, ffi.sizeof(e)) == ffi.sizeof(e) and e.type ~= 0 then
    io.write(string.format("%d.%06d %s code=%d (0x%x) value=%d\n", tonumber(e.sec), tonumber(e.usec),
      names[e.type] or tostring(e.type), e.code, e.code, e.value)); io.flush()
  end
end
