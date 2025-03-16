package main

import "core:math/linalg"
import "core:container/small_array"
import win32 "core:sys/windows"

import "Platform"

UiColorVar :: enum {
  TEXT, 
  TEXT_HOVERED,
}

UiColorMod :: struct {
  Var : UiColorVar,
  Col : [4]f32,
}

UiColors :: [UiColorVar][4]f32

UiContext :: struct {
  Cursor : [2]f32,
  Colors : UiColors,
  
  ColorStack : small_array.Small_Array(32, UiColorMod),
  Disabled: bool,
  
  Hovered : bool,
  
  PlatformWindow : Platform.Window,
  
  Texts : small_array.Small_Array(32, UiText), 
  Events: []Platform.Event
}

ALIGN_UPPER_RIGHT :: [2]f32 { 0, 0 }
WINDOW_PADDING : f32 : 10

UiText :: struct {
  Text : string,
  Pos : [2]f32,
  Col : [4]f32,
}

UiStartFrame :: proc(ctx: ^UiContext, events: []Platform.Event) {
  ctx.Cursor = { WINDOW_PADDING, WINDOW_PADDING }
  ctx.Events = events
}

UiEndFrame :: proc(ctx: ^UiContext) {
  assert(small_array.len(ctx.ColorStack) == 0)
  small_array.clear(&ctx.Texts)
  ctx.Hovered = false
}

UiPushColor :: proc(ctx : ^UiContext, var : UiColorVar, col : [4]f32, enable := true) {
  //This enables the caller to write 'UiPushColor(&ctx, col, condition)
  //instead of  'if condition do UiPushColor(...)' which I find a little neater.
  //Same goes for 'UiPopColor'
  if !enable do return
  
  backup := UiColorMod { Var = var, Col = ctx.Colors[var] }
  small_array.push_back(&ctx.ColorStack, backup)
  ctx.Colors[var] = col
}

UiPopColor :: proc(ctx : ^UiContext, enable := true) {
  if !enable do return 
  restore := small_array.pop_back(&ctx.ColorStack)
  ctx.Colors[restore.Var] = restore.Col
}

UiSignal :: struct {
  Clicked: bool,
  Hovered: bool,
}

IsMouseClicked :: proc(events : []Platform.Event, mb: Platform.MouseButton = .LEFT) -> bool {
  for ev in events {
    if e, ok := ev.(Platform.EventMouseDown); ok do return e.Button == mb
  }
  
  return false
}

IsMouseReleased :: proc(events : []Platform.Event, mb: Platform.MouseButton = .LEFT) -> bool {
  for ev in events {
    if e, ok := ev.(Platform.EventMouseUp); ok do return e.Button == mb
  }
  
  return false
}

UiNewLine :: proc(ctx: ^UiContext) {
  ctx.Cursor.y += f32(FONT_ATLAS_LINE_HEIGHT)
  ctx.Cursor.x = 0
}

UiAddText :: proc(ctx : ^UiContext, str : string, align : [2]f32 = ALIGN_UPPER_RIGHT) {
  defer ctx.Cursor += { 0, f32(FONT_ATLAS_LINE_HEIGHT) }
  
  size := linalg.to_f32(CalcTextSize(str))
  pos := ctx.Cursor - size * align
  rect := Rectangle{ pos, pos + size }
  
  hovered := Contains(rect, Platform.GetMousePosWindow(ctx.PlatformWindow))
  ctx.Hovered |= hovered

  text := UiText {
    Text = str,
    Col = ctx.Colors[.TEXT],
    Pos = pos
  }
  
  small_array.push_back(&ctx.Texts, text)
}

UiAddButton :: proc(ctx : ^UiContext, str : string, align : [2]f32 = ALIGN_UPPER_RIGHT) -> UiSignal {
  defer ctx.Cursor += { 0, f32(FONT_ATLAS_LINE_HEIGHT) }
  
  size := linalg.to_f32(CalcTextSize(str))
  pos := ctx.Cursor - size * align
  rect := Rectangle{ pos, pos + size }
  
  canHover := !ctx.Disabled
  hovered := Contains(rect, Platform.GetMousePosWindow(ctx.PlatformWindow))
  clicked := canHover && hovered && IsMouseReleased(ctx.Events)
  ctx.Hovered |= hovered
  
  col := ctx.Colors[.TEXT]
  if canHover && hovered do col = ctx.Colors[.TEXT_HOVERED]
  if ctx.Disabled do col *= { 1, 1, 1, 0.5 }
  
  text := UiText {
    Text = str,
    Col = col,
    Pos = pos
  }
  small_array.push_back(&ctx.Texts, text)

  return { clicked, hovered }
}