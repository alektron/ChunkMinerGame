package main

import "core:math"
import "core:math/linalg"

import "core:fmt"

import "Platform"

ORBIT_MIN_RADIUS :: 0.01

Camera3d :: struct {
  Position: [3]f32,
  Forward : [3]f32,
  Right    : [3]f32,
  
  AspectRatio: f32,
  FieldOfView: f32,
  
  Near: f32,
  Far: f32,
}

OrbitController :: struct {
  DegPerPixel : f32,
  RadiusPerScroll : f32,
  HeightPerScroll : f32,
  SmoothSpeed : f32,
  SmoothThreshold : f32,
  
  RadiusLinear : f32,
  Angle : [2]f32,
  Height: f32,
  
  TargetRadius : f32,
  TargetAngle  : [2]f32,
  TargetHeight : f32,
  
  MaxHeight: f32,
  MinHeight: f32,
  
  MouseIsDown : bool,
  MouseDownPosScreen : [2]f32,
  MouseDownAngle : [2]f32,
}

DEFAULT_ORBIT := OrbitController {
  DegPerPixel = 0.5,
  RadiusPerScroll = 0.2,
  HeightPerScroll = 2,
  SmoothSpeed = 15,
  SmoothThreshold = 0.001,
  
  RadiusLinear = 3,
  MaxHeight = math.inf_f32(+1),
  MinHeight = math.inf_f32(-1),
}

OrbitControllerRadiusFunc :: proc(x : f32) -> f32 {
  return (math.exp(x) - 1) / 4;
}


OrbitControllerRadiusFuncInvert :: proc(x : f32) -> f32 {
  return math.log2_f32((x * 4) + 1)
}

OrbitControllerGetForward :: proc(cont: OrbitController) -> Vec3 {
  return {
    math.cos(cont.Angle.x) * math.cos(cont.Angle.y),
    math.sin(cont.Angle.y),
    math.sin(cont.Angle.x) * math.cos(cont.Angle.y),
  }
}

OrbitControllerGetRight :: proc(cont: OrbitController) -> Vec3 {
  angle := cont.Angle.x + math.to_radians_f32(90)
  
  return { math.cos(angle), 0, math.sin(angle) }
}

OrbitControllerGetUp :: proc(cont: OrbitController) -> Vec3 {
  forward := OrbitControllerGetForward(cont)
  right   := OrbitControllerGetRight  (cont)
  return linalg.cross(forward, right)
}

OrbitControllerGetPos :: proc(cont: OrbitController) -> Vec3 {
  forward := OrbitControllerGetForward(cont)
  right   := OrbitControllerGetRight  (cont)
  radius  := OrbitControllerRadiusFunc(cont.RadiusLinear)
  camPos  := -forward * radius + { 0, cont.Height, 0 }
  return camPos
}

OrbitControllerApplyToCamera :: proc(cont: OrbitController, camera: ^Camera3d) {
  forward := OrbitControllerGetForward(cont)
  right   := OrbitControllerGetRight  (cont)
  radius  := OrbitControllerRadiusFunc(cont.RadiusLinear)
  camPos  := -forward * radius + { 0, cont.Height, 0 }
  
  camera.Forward = forward
  camera.Right = right
  camera.Position = camPos
}

Camera3dGetViewMatrix :: proc(cam: Camera3d) -> Mat4 {
  up := linalg.cross(-cam.Forward, cam.Right)

  return Mat4 {
    cam.Right.x, up.x, cam.Forward.x, cam.Position.x,
    cam.Right.y, up.y, cam.Forward.y, cam.Position.y,
    cam.Right.z, up.z, cam.Forward.z, cam.Position.z,
    0, 0, 0, 1
  }
}

OrbitControllerGetViewMatrix :: proc(cont: OrbitController) -> Mat4 {
  forward := OrbitControllerGetForward(cont)
  right   := OrbitControllerGetRight  (cont)
  radius  := OrbitControllerRadiusFunc(cont.RadiusLinear)
  camPos  := -forward * radius + { 0, cont.Height, 0 }

  up := linalg.cross(-forward, right)

  return Mat4 {
    right.x, up.x, forward.x, camPos.x,
    right.y, up.y, forward.y, camPos.y,
    right.z, up.z, forward.z, camPos.z,
    0, 0, 0, 1
  }
}

OrbitControllerOnEvent :: proc(cont: ^OrbitController, event: Platform.Event) {
  if e, ok := event.(Platform.EventMouseDown); ok {
    if e.Button == .RIGHT || e.Button == .MIDDLE {
      cont.MouseIsDown = true
      Platform.SetMouseCapture(e.Window)
      cont.MouseDownPosScreen = Platform.GetMousePosScreen()
      cont.MouseDownAngle = cont.Angle
    }
  }
  
  if e, ok := event.(Platform.EventMouseUp); ok {
    if e.Button == .RIGHT || e.Button == .MIDDLE {
      cont.MouseIsDown = false
      Platform.ReleaseMouseCapture(e.Window)
    }
  }
  
  if e, ok := event.(Platform.EventMouseWheel); ok {
    cont.TargetHeight += e.Delta.y * cont.HeightPerScroll
    cont.TargetHeight = math.min(cont.TargetHeight, cont.MaxHeight)
    cont.TargetHeight = math.max(cont.TargetHeight, cont.MinHeight)
  }

  if e, ok := event.(Platform.EventMouseMove); ok {
    //Usually we'd prefer to just call Input.IsMouseButtonDown() here and save ourselves
    //the stateful 'MouseIsDown'. However in that case a MouseMove event
    //can come in while Input.IsMouseButtonDown() returns true but the MouseDown event was not yet fired.
    //We then get stale MousePosDown values which causes a camera jump
    if cont.MouseIsDown {
      offset := cont.MouseDownPosScreen - e.ScreenPos
      radius := OrbitControllerRadiusFunc(cont.RadiusLinear)
      
      forward := OrbitControllerGetForward(cont^)
      right   := OrbitControllerGetRight  (cont^)
      up      := linalg.cross(forward, right)
      
      cont.TargetAngle.x = cont.MouseDownAngle.x - offset.x * math.to_radians(cont.DegPerPixel)
      cont.TargetAngle.y = cont.MouseDownAngle.y + offset.y * math.to_radians(cont.DegPerPixel)
      cont.TargetAngle.y = math.clamp(cont.TargetAngle.y, math.to_radians_f32(-55), math.to_radians_f32(55))
    }
  }
}

OrbitControllerOnUpdate :: proc(cont: ^OrbitController, dt: f32) {
  using cont
  
  NormalizeAngle :: proc(angleRad : f32) -> f32 {
    return angleRad - math.TAU * math.ceil((angleRad / math.TAU) - 0.5)
  }
  
  if linalg.distance(TargetAngle, Angle) >= SmoothThreshold {
    delta := TargetAngle - Angle
    offset := delta * dt * SmoothSpeed
    Angle += offset
  }
  
  if linalg.distance([1]f32{TargetRadius}, RadiusLinear) >= SmoothThreshold {
    delta := TargetRadius - RadiusLinear
    offset := delta * dt * SmoothSpeed
    RadiusLinear += offset
  }
  
  if linalg.distance([1]f32{TargetHeight}, Height) >= SmoothThreshold {
    delta := TargetHeight - Height
    offset := delta * dt * SmoothSpeed * 0.75
    Height += offset
  }
}