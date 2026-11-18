-- Ninja Atari 8-bit in MAME: log POKEY writes ($D200-$D208 AUDF/AUDC/AUDCTL), snapshots, joystick script.
-- env: NINJA_FRAMES, NINJA_SHOT_EVERY, NINJA_LOG (file), NINJA_KEYS="f0-f1:R+F,..." (R L U D F)
local m = manager.machine
local sp = m.devices[':maincpu'].spaces['program']
local f = 0
local every = tonumber(os.getenv('NINJA_SHOT_EVERY') or '300')
-- NINJA_SHOT_FROM / NINJA_SHOT_TO: снимки только в этом окне кадров
local shot_from = tonumber(os.getenv('NINJA_SHOT_FROM') or '0')
local shot_to = tonumber(os.getenv('NINJA_SHOT_TO') or '999999')
local last = tonumber(os.getenv('NINJA_FRAMES') or '3000')
local log = io.open(os.getenv('NINJA_LOG') or 'pokey.log', 'w')
local buf = {}
local cpu = m.devices[':maincpu']
-- NINJA_DUMP=frame: write 64K memory image (I/O area D000-D7FF zeroed) to OUTDIR given by NINJA_DUMPFILE
-- NINJA_PEEK="EVERY:addr,addr,..." (hex) prints bytes to stdout every EVERY frames
local peek_every, peek_list = nil, {}
do
  local pk = os.getenv('NINJA_PEEK')
  if pk then
    local ev, l = pk:match('(%d+):(.+)')
    peek_every = tonumber(ev)
    for x in string.gmatch(l, '[^,]+') do table.insert(peek_list, tonumber(x, 16)) end
  end
end
local dump_at = tonumber(os.getenv('NINJA_DUMP') or '-1')
local function pc() return cpu.state['PC'].value end
pokey_tap = sp:install_write_tap(0xD200, 0xD20F, 'pokeylog', function(offset, data, mask)
  local a = offset & 0x0F
  if a <= 8 then buf[#buf + 1] = string.format('%d %X %02X %04X', f, a, data & 0xFF, pc()) end
  return data
end)
-- NINJA_TRIG=1: on sound triggers (effect start, thud, whistle, score, music mode) snapshot the
-- frame and print 'trig f N addr val pc caller shot#' (caller = JSR return address - 2 from stack)
if os.getenv('NINJA_TRIG') then
  local shots, last_shot = 0, -1
  local function caller()
    local spv = cpu.state['SP'].value & 0xFF
    local lo, hi = sp:read_u8(0x100 + ((spv + 1) & 0xFF)), sp:read_u8(0x100 + ((spv + 2) & 0xFF))
    return ((hi << 8) | lo) - 2
  end
  local function trig(offset, data, mask)
    local p = pc()
    local game = not ((p >= 0x2418 and p <= 0x249E) or (p >= 0x24EA and p <= 0x255C) or (p >= 0x2BE8 and p <= 0x2C30))
    if game and p < 0xE000 then
      local shot = -1
      if f ~= last_shot then m.video:snapshot(); last_shot = f; shot = shots; shots = shots + 1 end
      print(string.format('trig f%d %04X %02X pc=%04X caller=%04X shot=%d', f, offset, data & 0xFF, p, caller(), shot))
    end
    return data
  end
  trig_taps = {}
  for _, r in ipairs({{0x240D, 0x240F}, {0x2416, 0x2417}, {0x9F5A, 0x9F5A}, {0x00CC, 0x00CC}}) do
    trig_taps[#trig_taps + 1] = sp:install_write_tap(r[1], r[2], 't' .. r[1], trig)
  end
end
-- NINJA_FULL=1: one ordered stream to OUTDIR log: POKEY writes, RANDOM reads, sound variable writes
if os.getenv('NINJA_FULL') then
  local function wlog(tag)
    return function(offset, data, mask)
      buf[#buf + 1] = string.format('%d W %04X %02X %04X', f, offset, data & 0xFF, pc())
      return data
    end
  end
  taps = {}
  for _, r in ipairs({{0x2400, 0x2420}, {0x24E4, 0x24E9}, {0x9F5A, 0x9F5C}, {0x9F46, 0x9F48}, {0x00CC, 0x00CC},
                      {0x0014, 0x0014}, {0xBD9A, 0xBDBC}, {0x0084, 0x008F}}) do
    taps[#taps + 1] = sp:install_write_tap(r[1], r[2], 'w' .. r[1], wlog())
  end
  taps[#taps + 1] = sp:install_read_tap(0xD20A, 0xD20A, 'rnd', function(offset, data, mask)
    buf[#buf + 1] = string.format('%d R D20A %02X %04X', f, data & 0xFF, pc())
    return data
  end)
end
local names = {R='P1 Right', L='P1 Left', U='P1 Up', D='P1 Down', F='P1 Button 1'}
local keys, prev = {}, {}
for item in string.gmatch(os.getenv('NINJA_KEYS') or '', '[^,]+') do
  local a, b, k = item:match('(%d+)-(%d+):(.+)')
  local list = {}
  for x in string.gmatch(k, '[^+]+') do table.insert(list, names[x] or x) end
  table.insert(keys, {tonumber(a), tonumber(b), list})
end
local fields = {}
for _, port in pairs(m.ioport.ports) do
  for name, fl in pairs(port.fields) do if not fields[name] then fields[name] = fl end end
end
emu.register_frame_done(function()
  if #buf > 0 then log:write(table.concat(buf, '\n'), '\n'); buf = {} end
  f = f + 1
  local want = {}
  for _, k in ipairs(keys) do
    if f >= k[1] and f <= k[2] then for _, n in ipairs(k[3]) do want[n] = true end end
  end
  for _, k in ipairs(keys) do for _, n in ipairs(k[3]) do
    local v = want[n] and 1 or 0
    if fields[n] and v ~= (prev[n] or 0) then
      if v == 1 then fields[n]:set_value(1) else fields[n]:clear_value() end
      prev[n] = v
    end
  end end
  if peek_every and f % peek_every == 0 then
    local t = {}
    for _, a in ipairs(peek_list) do table.insert(t, string.format('%04X=%02X', a, sp:read_u8(a))) end
    print('peek f' .. f .. ' ' .. table.concat(t, ' '))
  end
  if f == dump_at then
    local r = {}
    for a = 0, 0xFFFF do
      if a >= 0xD000 and a < 0xD800 then r[#r + 1] = '\0' else r[#r + 1] = string.char(sp:read_u8(a)) end
    end
    local g = io.open(os.getenv('NINJA_DUMPFILE') or 'mem.bin', 'wb'); g:write(table.concat(r)); g:close()
  end
  if f % every == 0 and f >= shot_from and f <= shot_to then m.video:snapshot() end
  if f >= last then log:close(); m:exit() end
end)
