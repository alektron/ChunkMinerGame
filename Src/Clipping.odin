package main

Region :: bit_set[enum {
  NEAR  ,
  FAR   ,
  LEFT  ,
  RIGHT ,
  BOTTOM,
  TOP   ,
}]

ClipType :: enum {
  FULLY_VISIBLE,
  FULLY_INVISIBLE,
  CLIPPING,
}

GetRegion2d :: proc(pointZeroToOne: [2]f32) -> Region {
  region: Region
  
  if pointZeroToOne.x < 0 do region |= { .LEFT   }
  if pointZeroToOne.x > 1 do region |= { .RIGHT  }
  if pointZeroToOne.y < 0 do region |= { .BOTTOM }
  if pointZeroToOne.y > 1 do region |= { .TOP    }
  return region
}

GetRegion3d :: proc(pointClipSpace: [4]f32) -> Region {
  CLIP_EPSILON :: 1e-5
  
  w := pointClipSpace.w * (1 + CLIP_EPSILON)
  region: Region
  
  if pointClipSpace.z < -w do region |= { .NEAR   }
  if pointClipSpace.z >  w do region |= { .FAR    }
  if pointClipSpace.x < -w do region |= { .LEFT   }
  if pointClipSpace.x >  w do region |= { .RIGHT  }
  if pointClipSpace.y < -w do region |= { .BOTTOM }
  if pointClipSpace.y >  w do region |= { .TOP    }
  return region
}

GetRegion :: proc { GetRegion2d, GetRegion3d }

GetClipType :: proc(a, b: Region) -> ClipType {
  if (a | b) == {} do return .FULLY_VISIBLE

  //Regions that are in the same outer row or column are never the empty set when ANDed.
  //'outer' meaning rows and colums that do not include the center
  if (a & b) != {} do return .FULLY_INVISIBLE

  //Note that this result might be a false positive.
  //There are still pairs of regions left that do not result in clipping.
  //e.g. a line going from TOP to RIGHT does not necessarily go through CENTER.
  //However by only looking at the regions we can not know that so we have to treat them as clipping.
  return .CLIPPING
}

//Line clipping algorithm after Cohen-Sutherland
//https://en.wikipedia.org/wiki/Cohen%E2%80%93Sutherland_algorithm
Clip2d :: proc(point0, point1: ^[2]f32) -> ClipType {
  p0 := point0^
  p1 := point1^
  region0 := GetRegion(p0)
  region1 := GetRegion(p1)
  clipType := GetClipType(region0, region1)

  for clipType == .CLIPPING {
    regionOut := region0 == {} ? region1 : region0

    clipped: [2]f32
    if      regionOut & { .TOP    } != {} do clipped = { p0.x + (p1.x - p0.x) * (1 - p0.y) / (p1.y - p0.y), 1 }
    else if regionOut & { .BOTTOM } != {} do clipped = { p0.x + (p1.x - p0.x) * (0 - p0.y) / (p1.y - p0.y), 0 }
    else if regionOut & { .RIGHT  } != {} do clipped = { 1, p0.y + (p1.y - p0.y) * (1 - p0.x) / (p1.x - p0.x) }
    else if regionOut & { .LEFT   } != {} do clipped = { 0, p0.y + (p1.y - p0.y) * (0 - p0.x) / (p1.x - p0.x) }

    if regionOut == region0 {
      p0 = clipped
    }
    else {
      p1 = clipped
    }

    region0 = GetRegion(p0)
    region1 = GetRegion(p1)
    clipType = GetClipType(region0, region1)
  }
  
  point0^ = p0
  point1^ = p1
  return clipType
}

//Line clipping algorithm after Cohen-Sutherland (adapted for 3D)
//https://en.wikipedia.org/wiki/Cohen%E2%80%93Sutherland_algorithm
Clip3d :: proc(point0, point1: ^[4]f32) -> ClipType {
  p0 := point0^
  p1 := point1^
  
  region0 := GetRegion(p0)
  region1 := GetRegion(p1)
  
  clipType := GetClipType(region0, region1);
  if clipType == .CLIPPING {
    d := p1 - p0
    tmin : f32 = 0
    tmax : f32 = 1
    if (ClipLine( d.x + d.w, -p0.x - p0.w, &tmin, &tmax) &&
        ClipLine(-d.x + d.w,  p0.x - p0.w, &tmin, &tmax) &&
        ClipLine( d.y + d.w, -p0.y - p0.w, &tmin, &tmax) &&
        ClipLine(-d.y + d.w,  p0.y - p0.w, &tmin, &tmax) &&
        ClipLine( d.z + d.w, -p0.z - p0.w, &tmin, &tmax) &&
        ClipLine(-d.z + d.w,  p0.z - p0.w, &tmin, &tmax))
    {
      temp := p0
      p0 = temp + (d * tmin)
      p1 = temp + (d * tmax)
    }
  }
  
  point0^ = p0
  point1^ = p1
  return clipType
}

Clip :: proc{ Clip2d, Clip3d }

ClipLine :: proc(denom, num: f32, tMin, tMax: ^f32) -> bool {
  t: f32
  if denom > 0 {
    t = num / denom
    if t > tMax^ do return false
    if t > tMin^ do tMin^ = t
  }
  else if denom < 0 {
    t = num / denom
    if t < tMin^ do return false
    if t < tMax^ do tMax^ = t;
  }
  else if num > 0 do return false;
  return true;
}