package main

Rectangle :: struct {
  Min : [2]f32,
  Max : [2]f32,
}

Contains :: proc(rect : Rectangle, p : [2]f32) -> bool {
  return (
    p.x >= rect.Min.x && p.y >= rect.Min.y &&
    p.x <= rect.Max.x && p.y <= rect.Max.y
  )
}