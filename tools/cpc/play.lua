-- Ninja CPC in MAME: boot from disk, menu keys, scripted joystick, snapshots.
-- env: NINJA_FRAMES, NINJA_SHOT_EVERY, NINJA_KEYS="f0-f1:R+F,..." (R L U D F = joystick),
--      NINJA_TYPE="frame:text,..." (typed via natural keyboard, e.g. 1800:2,1860:0)
local f = 0
local every = tonumber(os.getenv('NINJA_SHOT_EVERY') or '200')
local last = tonumber(os.getenv('NINJA_FRAMES') or '3000')
local names = {R='P1 Right', L='P1 Left', U='P1 Up', D='P1 Down', F='P1 Button 1'}
local keys, types = {}, {}
for item in string.gmatch(os.getenv('NINJA_KEYS') or '', '[^,]+') do
  local a, b, k = item:match('(%d+)-(%d+):(.+)')
  local list = {}
  for x in string.gmatch(k, '[^+]+') do table.insert(list, names[x] or x) end
  table.insert(keys, {tonumber(a), tonumber(b), list})
end
for item in string.gmatch(os.getenv('NINJA_TYPE') or '', '[^,]+') do
  local a, t = item:match('(%d+):(.+)')
  types[tonumber(a)] = t
end
-- any key: field name as MAME shows it (e.g. 0, 2, Space, Enter); R L U D F = joystick
local fields
local function all_fields()
  local t = {}
  for _, port in pairs(manager.machine.ioport.ports) do
    for name, fl in pairs(port.fields) do
      if not t[name] then t[name] = fl end
      local short = name:match('^(%S)  ')          -- '0  _' -> '0', 'p  P' -> 'p'
      if short and not t[short] then t[short] = fl end
    end
  end
  return t
end
local used, prev = {}, {}
-- NINJA_PEEK="FROM/EVERY:A-B" (hex range) prints memory to stdout
local peek_from, peek_every, peek_a, peek_b
do
  local pk = os.getenv('NINJA_PEEK')
  if pk then
    local fr, ev, a, b = pk:match('(%d+)/(%d+):(%x+)-(%x+)')
    peek_from, peek_every, peek_a, peek_b = tonumber(fr), tonumber(ev), tonumber(a, 16), tonumber(b, 16)
  end
end
for _, k in ipairs(keys) do for _, n in ipairs(k[3]) do used[n] = true end end
-- NINJA_POKES="frame:ADDR=VAL;ADDR=VAL,frame:..." (hex) writes memory at that frame
local pokes = {}
for item in string.gmatch(os.getenv('NINJA_POKES') or '', '[^,]+') do
  local fr, rest = item:match('(%d+):(.+)')
  local list = {}
  for a, v in string.gmatch(rest, '(%x+)=(%x+)') do table.insert(list, {tonumber(a, 16), tonumber(v, 16)}) end
  pokes[tonumber(fr)] = list
end
emu.register_frame_done(function()
  f = f + 1
  if pokes[f] then local sp = manager.machine.devices[':maincpu'].spaces['program']; for _, p in ipairs(pokes[f]) do sp:write_u8(p[1], p[2]) end end
  if not fields then fields = all_fields() end
  if f == 120 then manager.machine.natkeyboard:post('RUN"NINJA\n') end
  if types[f] then manager.machine.natkeyboard:post(types[f]) end
  local want = {}
  for _, k in ipairs(keys) do
    if f >= k[1] and f <= k[2] then for _, n in ipairs(k[3]) do want[n] = true end end
  end
  for n, _ in pairs(used) do
    local fl = fields[n]
    local v = want[n] and 1 or 0
    if fl and v ~= (prev[n] or 0) then
      if v == 1 then fl:set_value(1) else fl:clear_value() end
      prev[n] = v
    end
  end
  if peek_from and f >= peek_from and f % peek_every == 0 then
    local sp = manager.machine.devices[':maincpu'].spaces['program']
    local t = {}
    for a = peek_a, peek_b do table.insert(t, string.format('%02X', sp:read_u8(a))) end
    print(string.format('peek f%d %04X: %s', f, peek_a, table.concat(t, ' ')))
  end
  if f % every == 0 then manager.machine.video:snapshot() end
  if f >= last then manager.machine:exit() end
end)
