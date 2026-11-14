"""Patch kindle-hid-passthrough's bundled bumble 0.0.226 (bytecode inside dist/main.bin)
so ClassicChannel.on_configure_request no longer rejects unknown L2CAP options
(macOS sends FLUSH_TIMEOUT on the A2DP media channel and gives up after 10 s of rejects).

Same-length edit: in the `case _:` branch the stores to `result` and `replied_options`
are redirected to the unused local `enabled`, so the response stays SUCCESS.
Run with python3.11:  python3.11 patch_flush_timeout.py <bumble/l2cap.py> <main.bin> <out.bin>
"""
import dis, sys, types
src, inp, out = sys.argv[1:4]
mod = compile(open(src).read(), "bumble/l2cap.py", "exec", optimize=2)
def walk(co):
    yield co
    for c in co.co_consts:
        if isinstance(c, types.CodeType): yield from walk(c)
f = next(c for c in walk(mod) if c.co_qualname == "ClassicChannel.on_configure_request")
data = bytearray(open(inp, "rb").read())
assert data.count(f.co_code) == 1, "bytecode not found exactly once"
base = data.find(f.co_code)
ins = list(dis.get_instructions(f))
i = next(k for k, x in enumerate(ins) if x.argval == "FAILURE_UNKNOWN_OPTIONS")
targets = [x for x in ins[i:i + 6] if x.opname == "STORE_FAST" and x.argval in ("result", "replied_options")]
assert len(targets) == 2, targets
dead = f.co_varnames.index("enabled")
for x in targets:
    assert data[base + x.offset] == dis.opmap["STORE_FAST"]
    data[base + x.offset + 1] = dead
    print(f"patched STORE_FAST {x.argval} @+{x.offset} -> enabled")
open(out, "wb").write(data)
