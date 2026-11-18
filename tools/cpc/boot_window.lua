-- Windowed play: only type RUN"NINJA after BASIC is up; everything else is the player's.
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f == 120 then manager.machine.natkeyboard:post('RUN"NINJA\n') end
end)
