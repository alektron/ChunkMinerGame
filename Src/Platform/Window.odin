package Platform

import "base:runtime"
import "core:mem/virtual"
import "core:container/intrusive/list"
import "base:intrinsics"
import "core:log"
import "Scratch"
import win32 "core:sys/windows"

Window :: struct {
  Handle : win32.HWND,
}

SetMouseCapture     :: proc(window: Window) { win32.SetCapture(window.Handle) }
ReleaseMouseCapture :: proc(window: Window) { win32.ReleaseCapture() }

EventKeyDown   :: struct { Key : Key, Repeat : bool }
EventKeyUp     :: struct { Key : Key }
EventMouseDown :: struct { Button : MouseButton, Window : Window }
EventMouseUp   :: struct { Button : MouseButton, Window : Window }
EventMouseWheel:: struct { Delta : [2]f32 }
EventMouseMove :: struct {
  ScreenPos : Vec2,
  WindowPos : Vec2
}
EventResize :: struct {
  Size : Vec2,
}
EventClose :: struct {}

Event :: union {
  EventMouseDown,
  EventMouseUp,
  EventMouseMove,
  EventMouseWheel,
  EventResize,
  EventClose,
  EventKeyDown,
  EventKeyUp,
}

EventNode :: struct {
  Node: list.Node,
  Event: Event,
}

EventContext :: struct {
  Arena: ^virtual.Arena,
  Events: list.List,
  NumEvents: i32,
  Context: runtime.Context,
}

//The Windows Unicode APIs use UTF-16. In Odin strings are UTF-8, including string literals.
//This intrinsic here allows us to specify string literals directly in UTF-16 (like the L prefix in C++).
//This works fine here, where we know the strings at compile time. Should you have to use the Windows API with runtime strings
//you must use converters like 'utf8_to_utf16' from 'core/sys/windows'.
UTF_16_LIT :: intrinsics.constant_utf16_cstring

@(private)
WINDOW_CLASS_NAME := UTF_16_LIT("MyGameWindowClass")

WindowInit :: proc() -> bool {
  hInstance := win32.GetModuleHandleW(nil)

  wndClass: win32.WNDCLASSEXW
  wndClass.cbSize = size_of(win32.WNDCLASSEXW)
  wndClass.style  = win32.CS_OWNDC | win32.CS_BYTEALIGNCLIENT
  wndClass.lpfnWndProc = WndProc
  wndClass.hInstance   = win32.HINSTANCE(hInstance);
  wndClass.lpszClassName = WINDOW_CLASS_NAME
  wndClass.hCursor = win32.LoadCursorA(nil, win32.IDC_ARROW)
  
  reg := win32.RegisterClassExW(&wndClass)
  if reg == 0 {
    log.error("RegisterClass failed")
    return false
  }
  return true
}

//The WndProc callback procecure gets called from Windows whenever our code calls 'PeekMessage' (see below) and
//messages are available (e.g. a key got pressed, the mosue moved etc.).
//Traditionally the application is supposed to use 'GetMessage' which will block the program if no messages are available.
//For a game however, this does not really work. We want the game to always update at a stable frequency, even if there is
//no user interaction.
//Also note that we are not directly reacting to the messages. Instead we queue them and return back a list of events via our
//EventContext.
WndProc :: proc "system" (hwnd : win32.HWND, msg : win32.UINT, wParam : win32.WPARAM, lParam : win32.LPARAM) -> win32.LRESULT {
  ctx := (^EventContext)(uintptr(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA)))
  if ctx == nil do return win32.DefWindowProcW(hwnd, msg, wParam, lParam);
  
  context = ctx.Context
  
  PushEvent :: proc(ctx: ^EventContext, event: $T) {
    e := new(EventNode, virtual.arena_allocator(ctx.Arena))
    e.Event = event
    list.push_back(&ctx.Events, &e.Node)
    ctx.NumEvents += 1
  }
  
  switch msg {
    case win32.WM_CLOSE:
      PushEvent(ctx, EventClose{})
      return 0
    case win32.WM_KEYDOWN: fallthrough
    case win32.WM_SYSKEYDOWN:
      PushEvent(ctx, EventKeyDown{ KeyFromInternal(i32(wParam)), (lParam & 0x0000000040000000) > 0 })
      return 0
    case win32.WM_LBUTTONDOWN: fallthrough
    case win32.WM_RBUTTONDOWN: fallthrough
    case win32.WM_MBUTTONDOWN:
      mb : MouseButton
      if msg == win32.WM_LBUTTONDOWN || msg == win32.WM_NCLBUTTONDOWN do mb = MouseButton.LEFT
      if msg == win32.WM_MBUTTONDOWN || msg == win32.WM_NCMBUTTONDOWN do mb = MouseButton.MIDDLE
      if msg == win32.WM_RBUTTONDOWN || msg == win32.WM_NCRBUTTONDOWN do mb = MouseButton.RIGHT
      PushEvent(ctx, EventMouseDown{ mb, { hwnd } })
    case win32.WM_LBUTTONUP: fallthrough
    case win32.WM_RBUTTONUP: fallthrough
    case win32.WM_MBUTTONUP:
      mb : MouseButton
      if msg == win32.WM_LBUTTONUP || msg == win32.WM_NCLBUTTONUP do mb = MouseButton.LEFT
      if msg == win32.WM_MBUTTONUP || msg == win32.WM_NCMBUTTONUP do mb = MouseButton.MIDDLE
      if msg == win32.WM_RBUTTONUP || msg == win32.WM_NCRBUTTONUP do mb = MouseButton.RIGHT
      PushEvent(ctx, EventMouseUp{ mb , { hwnd }})
    case win32.WM_MOUSEMOVE:
      clientPos := win32.POINT { win32.GET_X_LPARAM(lParam), win32.GET_Y_LPARAM(lParam) }
      screenPos := clientPos
      win32.ClientToScreen(hwnd, &screenPos)
      PushEvent(ctx, EventMouseMove { WindowPos = { f32(clientPos.x), f32(clientPos.y) }, ScreenPos = { f32(screenPos.x), f32(screenPos.y) } })
    case win32.WM_MOUSEWHEEL:
      PushEvent(ctx, EventMouseWheel{ { 0, f32(win32.GET_WHEEL_DELTA_WPARAM(wParam) / win32.WHEEL_DELTA) } })
    case win32.WM_SIZE:
      PushEvent(ctx, EventResize { Size = { f32(win32.LOWORD(u32(lParam))), f32(win32.HIWORD(u32(lParam))) } })
  }

  return win32.DefWindowProcW(hwnd, msg, wParam, lParam);
}

GetEvents :: proc(window: Window, permanent: ^virtual.Arena) -> []Event {
  temp := Scratch.Begin({ permanent })
  ctx := EventContext {
    Arena = temp.arena,
    Context = context,
  }
  
  win32.SetWindowLongPtrW(window.Handle, win32.GWLP_USERDATA, int(uintptr(&ctx)))
  msg : win32.MSG
  for win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE) {
    win32.TranslateMessage(&msg)
    win32.DispatchMessageW(&msg)
  }
  
  //Our EventContext uses a linked list to store the events. This is a bit more arena friendly when
  //we don't know how many events there will be in advance.
  //For the rest of our game loop however I prefer to work with an event array/slice instead. It's just personal preference.
  //So we copy the linked list into a slice.
  events := make([]Event, ctx.NumEvents, virtual.arena_allocator(permanent))
  iter := list.iterator_head(ctx.Events, EventNode, "Node")
  index: i32
  for e in list.iterate_next(&iter) {
    events[index] = e.Event
    index += 1
  }
  Scratch.End(temp)
  return events
}

WindowIsValid :: proc(window: Window) -> bool {
  return window.Handle != nil
}

WindowIsFocused :: proc(window: Window) -> bool {
  return win32.GetFocus() == window.Handle
}

WindowIsMinimized :: proc(window: Window) -> bool {
  return win32.IsIconic(window.Handle) == win32.TRUE
}

GetWindowClientSize :: proc(window: Window) -> [2]f32 {
  rect : win32.RECT;
  win32.GetClientRect(window.Handle, &rect);
  width  := rect.right  - rect.left;
  height := rect.bottom - rect.top ;
  return { f32(width), f32(height) }
}

CreateAndShowWindow :: proc(title: string) -> Window {
  //The following is just regular boiler plate code to get a window up and running on Windows.
  //If you have written applications with graphical user interfaces on Windows before you have probably encountered
  //code more or less just like this.
  hInstance := win32.GetModuleHandleW(nil)
  
  temp := Scratch.Begin()
  titleUtf16 := win32.utf8_to_utf16(title, virtual.arena_allocator(temp.arena))
  window := win32.CreateWindowW(
    WINDOW_CLASS_NAME,
    raw_data(titleUtf16),
    win32.WS_CAPTION | win32.WS_SYSMENU | win32.WS_MAXIMIZEBOX | win32.WS_MINIMIZEBOX | win32.WS_SIZEBOX,
    win32.CW_USEDEFAULT,
    win32.CW_USEDEFAULT,
    win32.CW_USEDEFAULT,
    win32.CW_USEDEFAULT,
    nil,
    nil,
    win32.HINSTANCE(hInstance),
    nil
  )
  Scratch.End(temp)
  
  if window == nil {
    log.error("CreateWindow failed")
    return {}
  }
  
  win32.ShowWindow(window, win32.SW_MAXIMIZE)
  return { Handle = window }
}