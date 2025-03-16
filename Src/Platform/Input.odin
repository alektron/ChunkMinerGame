package Platform

import win32 "core:sys/windows"

Vec2 :: [2]f32

MouseButton :: enum {
  LEFT,
  MIDDLE,
  RIGHT
}

InternalFromMouseButton :: proc(button : MouseButton) -> i32 {
  switch button {
    case .LEFT  : return win32.VK_LBUTTON
    case .RIGHT : return win32.VK_RBUTTON
    case .MIDDLE: return win32.VK_MBUTTON
  }

  return 0
}

IsMouseButtonDown :: proc(button : MouseButton = .LEFT) -> bool {
  return win32.GetKeyState(InternalFromMouseButton(button)) < 0
}

GetMousePosScreen :: proc() -> Vec2 {
  p : win32.POINT
  win32.GetCursorPos(&p)
  return { f32(p.x), f32(p.y) }
}

GetMousePosWindow :: proc(window : Window) -> Vec2 {
  p : win32.POINT
  win32.GetCursorPos(&p)
  win32.ScreenToClient(window.Handle, &p)
  return { f32(p.x), f32(p.y) }
}

Key :: enum {
  NONE = 0,
  W,
  A,
  S,
  D,
  E,
  C,
  F,
  G,
  SHIFT,
  SPACEBAR,
  ESC,
  ARROW_LEFT,
  ARROW_RIGHT,
  ARROW_UP,
  ARROW_DOWN,
}

//Converts our platform agnostic Key type into a platform key code.
//It gets extended whenever necessary.
InternalFromKey :: proc(key : Key) -> i32 {
  switch key {
    case .W: return win32.VK_W
    case .A: return win32.VK_A
    case .S: return win32.VK_S
    case .D: return win32.VK_D
    case .E: return win32.VK_E
    case .C: return win32.VK_C
    case .F: return win32.VK_F
    case .G: return win32.VK_G
    case .SHIFT: return win32.VK_SHIFT
    case .SPACEBAR: return win32.VK_SPACE
    case .ESC: return win32.VK_ESCAPE
    case .ARROW_LEFT : return win32.VK_LEFT
    case .ARROW_RIGHT: return win32.VK_RIGHT
    case .ARROW_UP   : return win32.VK_UP
    case .ARROW_DOWN : return win32.VK_DOWN
    case .NONE: return -1
  }
  return -1
}


//Converts the platform key codes into our platform agnostic Key type.
//It gets extended whenever necessary.
KeyFromInternal :: proc(key : i32) -> Key {
  switch key {
    case win32.VK_W: return .W
    case win32.VK_A: return .A
    case win32.VK_S: return .S
    case win32.VK_D: return .D
    case win32.VK_E: return .E
    case win32.VK_C: return .C
    case win32.VK_F: return .F
    case win32.VK_G: return .G
    case win32.VK_SHIFT: return .SHIFT    
    case win32.VK_SPACE: return .SPACEBAR 
    case win32.VK_ESCAPE: return .ESC
    case win32.VK_LEFT : return .ARROW_LEFT 
    case win32.VK_RIGHT: return .ARROW_RIGHT
    case win32.VK_UP   : return .ARROW_UP   
    case win32.VK_DOWN : return .ARROW_DOWN 
  }
  return .NONE
}

IsKeyPressed :: proc(key : Key) -> bool {
  return win32.GetKeyState(InternalFromKey(key)) < 0
}