package Platform

import win32 "core:sys/windows"

Timer :: struct {
  StartTime : i64
}

TimerStart :: proc(t : ^Timer) {
  ticks : win32.LARGE_INTEGER
  win32.QueryPerformanceCounter(&ticks)
  t.StartTime = i64(ticks)
}

TimerGetMicroseconds :: proc(t : ^Timer) -> i64 {
  freq : win32.LARGE_INTEGER
  win32.QueryPerformanceFrequency(&freq)

  ticks : win32.LARGE_INTEGER
  win32.QueryPerformanceCounter(&ticks)
  
  return ((i64(ticks) - t.StartTime) * 1000000) / GetTicksPerSecond()
}

GetTicksPerSecond :: proc() -> i64 {
  freq : win32.LARGE_INTEGER
  win32.QueryPerformanceFrequency(&freq)
  return i64(freq)
}