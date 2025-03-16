package main 

import "core:fmt"
import "base:runtime"
import "core:c"
import "core:os"
import "core:strings"
import "core:mem/virtual"
import "core:mem"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:math/rand"
import "core:math/noise"
import "core:slice"
import "core:bytes"
import "core:time"
import "core:log"
import arr "core:container/small_array"

//Preferably we do not want to import platform specific packages in our main package.
//Instead, our 'Platform' package should be used.
import win32 "core:sys/windows"

import "vendor:directx/dxgi"
import d3d "vendor:directx/d3d11"
import "vendor:directx/d3d_compiler"

import stbi "vendor:stb/image"
import ma "vendor:miniaudio"

import "Platform"
import "Platform/Scratch"
import "ObjLoader"

//Aliases purely due to personal preference
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4, 4]f32

//Enable/Disable Multisample Anti-Aliasing for our render targets.
//Set to 1 to disable MSAA. Be aware that we still render to a separate render target and then blit it
//to the backbuffer rendertarget even if it doesn't effectively do anything.
//Also be aware that we are not currently checking if MSAA is even supported and for how high of a sample count.
MSAA_SAMPLES : u32 : 4

Gpu :: struct {
  Swapchain     : ^dxgi.ISwapChain,
  Device        : ^d3d.IDevice,
  DeviceContext : ^d3d.IDeviceContext,
}

GpuVertexBuffer :: struct {
  Buffer: ^d3d.IBuffer,
  Len: int,
}

//All GPU resources get stored here.
//We create all our GPU render targets, buffers etc. at startup. There is no fancy dynamic asset managment system.
//Some of the vertex buffer's data get streamed every frame but for the most part the GPU resources do not
//change much after initialization
GpuRes :: struct {
  //Backbuffer render targets
  RenderTarget: ^d3d.ITexture2D,
  RenderTargetView: ^d3d.IRenderTargetView,
  
  //(Potentially) multisampled render buffers
  ColorBufferMS: ^d3d.ITexture2D,
  DepthBuffer: ^d3d.ITexture2D,
  RenderTargetMSView: ^d3d.IRenderTargetView,
  
  //Render state (rasterizer, blend state etc.)
  DepthStencilView: ^d3d.IDepthStencilView,
  DepthStencilStateDefault: ^d3d.IDepthStencilState,
  DepthStencilStateNoWrite: ^d3d.IDepthStencilState,
  DepthStencilStateSkybox: ^d3d.IDepthStencilState,
  Rasterizer3d: ^d3d.IRasterizerState,
  Rasterizer2d: ^d3d.IRasterizerState,
  SamplerState: ^d3d.ISamplerState,
  BlendState: ^d3d.IBlendState,
  
  FontTexture: ^d3d.ITexture2D,
  FontTextureView: ^d3d.IShaderResourceView,
  
  CrackTexture: ^d3d.ITexture2D,
  CrackTextureView: ^d3d.IShaderResourceView,
  
  SharedBuffer: ^d3d.IBuffer,
  ModelBuffer: ^d3d.IBuffer,
  VoxelChunkBuffer: ^d3d.IBuffer,
  
  VsSimple: ^d3d.IVertexShader,
  PsSimple: ^d3d.IPixelShader,
  LayoutSimple: ^d3d.IInputLayout,
  
  VsVoxel: ^d3d.IVertexShader,
  PsVoxel: ^d3d.IPixelShader,
  LayoutVoxel: ^d3d.IInputLayout,
  
  VsVoxelSimple: ^d3d.IVertexShader,
  PsVoxelSimple: ^d3d.IPixelShader,
  LayoutVoxelSimple: ^d3d.IInputLayout,
  
  VsHologram: ^d3d.IVertexShader,
  PsHologram: ^d3d.IPixelShader,
  LayoutHologram: ^d3d.IInputLayout,
  
  VsUi: ^d3d.IVertexShader,
  PsUi: ^d3d.IPixelShader,
  LayoutUi: ^d3d.IInputLayout,
  
  VsScreenQuad: ^d3d.IVertexShader,
  PsScreenQuad: ^d3d.IPixelShader,
  LayoutScreenQuad: ^d3d.IInputLayout,
  
  VBufferOrigin: ^d3d.IBuffer,
  VBufferQuad: ^d3d.IBuffer,
  
  VBufferCube: GpuVertexBuffer,
  VBufferCubeLow: GpuVertexBuffer,
  VBufferDrill: GpuVertexBuffer,
  VBufferWheels: GpuVertexBuffer,
  VBufferCar: GpuVertexBuffer,
  VBufferMechanic: GpuVertexBuffer,
  VBufferUpgrade: GpuVertexBuffer,
  VBufferCoins: GpuVertexBuffer,
  
  VBufferUi: ^d3d.IBuffer,
  VBufferGameUi: ^d3d.IBuffer,
  
  VoxelTex: ^d3d.ITexture3D,
  VoxelTexView: ^d3d.IShaderResourceView,
}

VoxelType :: enum u8 {
  NONE    = 0,
  DIRT    = 1,
  ROCK    = 2,
  ROCK2   = 3,
  COAL    = 4,
  IRON    = 5,
  SILVER  = 6,
  GOLD    = 7,
  SAPHIRE = 8,
  EMERALD = 9,
  RUBY    = 10,
  DIAMOND = 11,
  SOLID   = 12,
  BOUNDS  = 13,
}

VoxelProp :: struct {
  Name: string,
  Health: u8,
  Worth: i32,
  Strength: i32, //The drill upgrade required to mine this voxel
  Damage: i32, //The hull damage we receive when destroying this voxel
}

//Contains all the properties that apply to all voxels of the same type.
//Values like 'Health' get used to initialize voxels (they store it) but other values like 'Strength' does not have to be 
//stored per voxel. If a voxel of a specific type gets drilled, we can just look the strength of that type up in this table.
//No need to store it in every voxel.
VoxelProps := [VoxelType]VoxelProp {
  .NONE     = { Name = "None"     , Health = 0 , Worth = 0, Strength = 0, Damage = 0 },
  .DIRT     = { Name = "Dirt"     , Health = 4 , Worth = 0, Strength = 0, Damage = 0 },
  .ROCK     = { Name = "Rock"     , Health = 8, Worth = 0, Strength = 1, Damage = 1 },
  .ROCK2    = { Name = "Hard Rock", Health = 16, Worth = 0, Strength = 2, Damage = 2 },
  .COAL     = { Name = "Coal"     , Health = 4 , Worth = 20, Strength = 0, Damage = 0 },
  .IRON     = { Name = "Iron"     , Health = 6 , Worth = 50, Strength = 0, Damage = 0 },
  .SILVER   = { Name = "Silver"   , Health = 12, Worth = 50, Strength = 0, Damage = 0 },
  .GOLD     = { Name = "Gold"     , Health = 16, Worth = 150, Strength = 0, Damage = 0 },
  .SAPHIRE  = { Name = "Saphire"  , Health = 16, Worth = 150, Strength = 0, Damage = 0 },
  .EMERALD  = { Name = "Emerald"  , Health = 16, Worth = 150, Strength = 0, Damage = 0 },
  .RUBY     = { Name = "Ruby"     , Health = 16, Worth = 150, Strength = 0, Damage = 0 },
  .DIAMOND  = { Name = "Diamond"  , Health = 22, Worth = 400, Strength = 0, Damage = 0 },
  .SOLID    = { Name = "Solid"    , Health = 0 , Worth = 0, Strength = 1000, Damage = 0 },
  .BOUNDS   = { Name = "Bounds"   , Health = 0 , Worth = 0, Strength = 0, Damage = 0 },
}

//The actual per-voxel data that we are going to store in our big voxel array
Voxel :: struct {
  Type : VoxelType,
  Health : u8,
}

//The per-voxel data in the format that we will use on the GPU in a big 3D texture.
//For efficiency we are trying to press all necessary information into as little memory as possible.
//Currently we can easily fit everything into a u32
VoxelGpu :: bit_field u32 {
  Type   : VoxelType | 8,
  Health : u8 | 8,
  Light  : u8 | 8,
}

//NOTE: CHUNK_SIZE is also a constant in the shader. They do NOT get synced,
//so make sure to always adjust here AND in the shader
CHUNK_SIZE : i32 : 10
CHUNK_HEIGHT : i32 : 1000
VOXEL_PER_LAYER : i32 : CHUNK_SIZE * CHUNK_SIZE

//The number of big particles to spawn when a block is destroyed
NUM_BLOCK_PARTICLES :: 16

//TextParticles are usually short lived, animated UI texts that can be used to
//show e.g. value changes, notifications, warnings (about game state, like "low fuel").
//See 'UiEffects' for an explanation on how we use them.
TextParticle :: struct {
  Text : string,
  TimeToLiveS : f32,
  
  Pos : [2]f32,
  Align : [2]f32,
  
  Col : [4]f32,
  Velocity : [2]f32,
}

ValueChangeType :: enum {
  FUEL,
  HULL,
  MONEY,
  CARGO
}

UiEffectValueChange :: struct {
  Type: ValueChangeType, 
  Value: i32,
  VoxelType: VoxelType,
}

UiEffectDisclaimer :: enum {
  LOW_FUEL,
  NO_FUEL,
  CARGO_FULL,
}

//UiEffects get triggered by gameplay code to notify the user of various things.
//UiEffects usually spawn TextParticles. Gameplay code does not spawn TextParticles directly since we
//do not want to pollute it with knowledge about details like "where on screen is the UI element for which we want to show a '+1' particle".
//Instead it just says "spawn a '+1' fuel notification" and later when we handle the UI code, we figure out where to 
//spawn the TextParticle for it. This separates the gameplay nicely from the UI.
UiEffect :: union {
  UiEffectValueChange,
  UiEffectDisclaimer,
}

//Data for a simple 3D particle system.
//Not to be confused with TextParticle which is for UI.
Particle :: struct {
  Pos: [3]f32,
  Vel: [3]f32,
  TimeToLiveS: f32,
  Size: f32,
  Type: VoxelType,
}

UpgradeType :: enum {
  NONE,
  FUEL,
  HULL,
  SPEED,
  DRILL,
  CARGO,
}

UpgradeProp :: struct {
  Price: i32,
  Value: i32,
}

//Lookup table for upgrade prices and values.
//This is currently the game's biggest weak point. It is terribly balanced, if at all.
//I am certainly more of a programmer than I am a game designer and lost interest here quite quickly.
//Suggestions and/or pull requests are more than welcome.
UpgradeProps := [UpgradeType][5]UpgradeProp {
  .NONE = {},
  .FUEL = {
    { Price = 0 , Value = 100  },
    { Price = 200, Value = 200  },
    { Price = 4000, Value = 400  },
    { Price = 25000, Value = 8000  },
    { Price = 50000, Value = 1600 },
  },
  .HULL = {
    { Price = 0 , Value = 100  },
    { Price = 400, Value = 200  },
    { Price = 8000, Value = 400  },
    { Price = 25000, Value = 800  },
    { Price = 50000, Value = 1600 },
  },
  .SPEED = {
    //Value is move cooldown in milliseconds
    { Price = 0 , Value = 220  },
    { Price = 250, Value = 200  },
    { Price = 8000, Value = 180  },
    { Price = 25000, Value = 150  },
    { Price = 50000, Value = 120 },
  },
  .DRILL = {
    //Value is drill time in milliseconds to remove one voxel health 
    //Additionally at least Upgrade 1 is required to drill ROCK and Upgrda2 for ROCK2
    { Price = 0 , Value = 400 },
    { Price = 250, Value = 250 },
    { Price = 8000, Value = 100 },
    { Price = 20000, Value = 50  },
    { Price = 80000, Value = 25  },
  },
  .CARGO = {
    { Price = 0 , Value = 10 },
    { Price = 200, Value = 20 },
    { Price = 400, Value = 60 },
    { Price = 800, Value = 80 },
    { Price = 1000, Value = 100 },
  },
}

TutorialStep :: enum {
  CAMERA,
  MOVE,
  BUY_FUEL,
  DRILL
}

//For balancing purposes we want more than one fuel per dollar.
//That would require a PRICE_PER_UNIT of <1 which we can't do with integers.
//Instead we just invert the meaning of the unit. UNIT_PER_DOLLAR sounds a bit weird but works.
FUEL_UNIT_PER_DOLLAR : i32 : 3
REPAIR_UNIT_PER_DOLLAR : i32 : 2
HORIZONTAL_CLIMB_PRICE : i32 : 20000

Player :: struct {
  //Note that all player coordinates are integer vectors.
  //The player location is a discrete state, however we interpolate motion between those states while rendering.
  //This makes the drill look like it's moving smoothly even if it actually doesn't.
  DrillCoord: [3]i32,
  WheelDir  : [3]i32,
  DrillDir  : [3]i32,
  DriveDir  : [3]i32,
  
  //To do the previously mentioned interpolation we always need the players previous location state.
  PrevDrillCoord: [3]i32,
  PrevDrillDir  : [3]i32,
  PrevWheelDir  : [3]i32,
  PrevDriveDir  : [3]i32,
  
  PosInterpolationT: f32,
  RotInterpolationT: f32,
  
  Upgrades: [UpgradeType]i32,
  
  Fuel : i32,
  Hull : i32,
  
  StorageVoxel : VoxelType,
  Cargo: [VoxelType]i32,
  
  DrillRotation: f32,
  DrillDuration: f32,
  MoveCooldown : f32,
  
  //Some upgrade ideas that I toyed around with in the beginning. The idea was to crash land and gradually build
  //up and learn the basic movement abilities. I scrubbed the idea but the mechanics are still there.
  //'CanClimbHorizontal' is the only exception. That is still a buyable upgrade.
  CanDrive : bool,
  CanSteer : bool,
  CanClimb : bool,
  CanClimbHorizontal : bool,
  
  MoneyTotal : i32,
}

//The meat of our game data.
//The whole game state is just a regular ol' struct. A single allocation.
//One could argue that we are limiting ourselves a little bit by only using fixed sized buffers,
//but you can get incredibly far with a simple approach like that.
//Unless you have an ACTUAL requirement for some data to be unbounded, I highly recommend doing the simple thing first.
//You will see that this has many advantages. Trivial memory managment, trivial serializion and more.
GameState :: struct #align(size_of(mem.Buddy_Block)) {
  ParticleTextBuff : [512]u8, //IMPORTANT: Due to how the Buddy_Allocator works this field must be 16 byte aligned
  ParticleAllocator : mem.Buddy_Allocator,
  TextParticles : arr.Small_Array(64, TextParticle),
  UiEffects: arr.Small_Array(64, UiEffect),
  
  Particles: arr.Small_Array(256, Particle),
  
  //When voxel data changes we have to upload those changes to the GPU.
  //In gamplay code we just mark voxels as 'dirty' and upload them to the GPU before rendering.
  UpdateVoxels : arr.Small_Array(1228, [3]i32),
  ForceUpdateAllVoxels : bool,
  
  //Our voxel data. Just a simple array.
  //By far the biggest data structure in our game.
  Voxels : [VOXEL_PER_LAYER * CHUNK_HEIGHT]Voxel,

  //We are using 'using' here for convenience.
  //It was a bit of a mistake made early on in development.
  //I would recommend not doing that and properly typing out 'game.Player.X' where you need it.
  using Player: Player,
  
  MaxDepthReached: i32,
  
  ShopCoordSell: [3]i32,
  ShopCoordMech: [3]i32,
  ShopCoordUpgrade: [3]i32,
  
  FreeCam : bool,
  FreeCamTransition: f32,
  Tutorial: TutorialStep,
  
  ShowMenu: bool,
  ShowConfirmationPrompt: bool,
  
  CamController: OrbitController,
  Camera: Camera3d,
}

VOXEL_BLOCK : Voxel = { Type = .BOUNDS }
VOXEL_NONE  : Voxel = { Type = .NONE  }

//Calculates the array index of a voxel from it's 3D coordinate.
//This procedure is the recommended way of accessing voxel data.
GetVoxel :: proc(game : ^GameState, coord : [3]i32) -> ^Voxel {
  if InBounds(game, coord) {
    index := -coord.y * VOXEL_PER_LAYER + coord.z * CHUNK_SIZE + coord.x
    return &game.Voxels[index]
  }
  else {
    if coord.y > 0 && coord.x >= 0 && coord.x < CHUNK_SIZE && coord.z >= 0 && coord.z < CHUNK_SIZE {
      return &VOXEL_NONE
    }
    else {
      return &VOXEL_BLOCK
    }
  }
}

InBounds :: proc(game : ^GameState, coord : [3]i32) -> bool {
  return (
    coord.y <= 0 && 
    coord.x >= 0 && coord.x < CHUNK_SIZE &&
    coord.z >= 0 && coord.z < CHUNK_SIZE
  )
}

SpawnTextParticle :: proc(game : ^GameState, str : string, particle := TextParticle {
  Col = { 1, 1, 1, 1 },
  Velocity = { 0, 60, },
  TimeToLiveS = 1,
}) {
  arr.push_back(&game.TextParticles, particle)
  arr.slice(&game.TextParticles)[game.TextParticles.len - 1].Text = strings.clone(str, mem.buddy_allocator(&game.ParticleAllocator))
}

//Changes the current fuel value, does the necessary checks to prevent values going out of range
//and triggers the corresponding UiEffects
DeltaFuel :: proc(game : ^GameState, delta : i32) {
  delta := delta
  max := UpgradeProps[.FUEL][game.Upgrades[.FUEL]].Value
  if delta < 0 do delta = math.max(delta, -game.Fuel)
  if delta > 0 do delta = math.min(delta, max - game.Fuel)
  
  fuelWasAboveCritical := f32(game.Fuel) / f32(UpgradeProps[.FUEL][game.Upgrades[.FUEL]].Value) >  0.15
  game.Fuel += delta
  fuelIsBelowCritical  := f32(game.Fuel) / f32(UpgradeProps[.FUEL][game.Upgrades[.FUEL]].Value) <= 0.15
  
  arr.push_back(&game.UiEffects, UiEffectValueChange { Type = .FUEL, Value = delta })
  
  if fuelWasAboveCritical && fuelIsBelowCritical {
    arr.push_back(&game.UiEffects, UiEffectDisclaimer.LOW_FUEL)
  }
}

//Changes the current hull value, does the necessary checks to prevent values going out of range
//and triggers the corresponding UiEffects
DeltaHull :: proc(game : ^GameState, delta : i32) {
  delta := delta
  max := UpgradeProps[.HULL][game.Upgrades[.HULL]].Value
  if delta < 0 do delta = math.max(delta, -game.Hull)
  if delta > 0 do delta = math.max(delta, max - game.Hull)
  game.Hull += delta
  
  arr.push_back(&game.UiEffects, UiEffectValueChange { Type = .HULL, Value = delta })
}

//Changes the current money value, does the necessary checks to prevent values going out of range
//and triggers the corresponding UiEffects
DeltaMoney :: proc(game : ^GameState, delta : i32) {
  delta := delta
  if delta < 0 do delta = math.max(delta, -game.MoneyTotal)
  game.MoneyTotal += delta
  
  arr.push_back(&game.UiEffects, UiEffectValueChange { Type = .MONEY, Value = delta })
}

//After upgrade balancing, the world generation is probably our second biggest weakness.
//It's not very well balanced. As mentioned before, balancing is not my strong suit.
//Suggestions and/or pull requests are more than welcome.
GenerateWorld :: proc(game: ^GameState, seed: u64) {
  Range :: struct {
    EaseInMin: i32,
    EaseInMax: i32,
    EaseOutMin: i32,
    EaseOutMax: i32,
    ThresholdMax: f32,
  }
  
  RANGES :: #partial [VoxelType]Range {
    .NONE = Range {
      EaseInMin = 20,
      EaseInMax = 150,
      EaseOutMin = CHUNK_HEIGHT,
      EaseOutMax = CHUNK_HEIGHT,
      ThresholdMax = 0.25,
    },
    
    .ROCK = Range {
      EaseInMin = 3,
      EaseInMax = 100,
      EaseOutMin = CHUNK_HEIGHT,
      EaseOutMax = CHUNK_HEIGHT,
      ThresholdMax = 1,
    },
    
    .ROCK2 = Range {
      EaseInMin = 400,
      EaseInMax = 700,
      EaseOutMin = CHUNK_HEIGHT,
      EaseOutMax = CHUNK_HEIGHT,
      ThresholdMax = 1,
    },
    
    .COAL = Range {
      EaseInMin = 1,
      EaseInMax = 2,
      EaseOutMin = 400,
      EaseOutMax = 800,
      ThresholdMax = 0.2,
    },
    
    .IRON = Range {
      EaseInMin = 8,
      EaseInMax = 12,
      EaseOutMin = 200,
      EaseOutMax = 400,
      ThresholdMax = 0.11,
    },
    
    .SILVER = Range {
      EaseInMin = 60,
      EaseInMax = 100,
      EaseOutMin = 300,
      EaseOutMax = 600,
      ThresholdMax = 0.1,
    },
    
    .GOLD = Range {
      EaseInMin = 150,
      EaseInMax = 200,
      EaseOutMin = 400,
      EaseOutMax = 400,
      ThresholdMax = 0.1,
    },
    
    .SAPHIRE = Range {
      EaseInMin = 240,
      EaseInMax = 320,
      EaseOutMin = 500,
      EaseOutMax = 500,
      ThresholdMax = 0.1,
    },
    
    .EMERALD = Range {
      EaseInMin = 400,
      EaseInMax = 500,
      EaseOutMin = 850,
      EaseOutMax = 850,
      ThresholdMax = 0.1,
    },
    
    .RUBY = Range {
      EaseInMin = 700,
      EaseInMax = 850,
      EaseOutMin = 900,
      EaseOutMax = 900,
      ThresholdMax = 0.1,
    },
    
    .DIAMOND = Range {
      EaseInMin = 900,
      EaseInMax = 1000,
      EaseOutMin = CHUNK_HEIGHT,
      EaseOutMax = CHUNK_HEIGHT,
      ThresholdMax = 0.1,
    },
  }
  
  ThreshFromRange :: proc(range: Range, depth: i32) -> f32 {
    if depth < range.EaseInMin do return 0
    if depth > range.EaseInMax do return range.ThresholdMax
    
    t := f32(depth - range.EaseInMin) / f32(range.EaseInMax - range.EaseInMin)
    assert(t <= 1)
    threshold := linalg.lerp(f32(0), range.ThresholdMax, t) 
    return threshold
  }

  noiseMin: f32 = math.inf_f32(+1)
  noiseMax: f32 = math.inf_f32(-1)
    
  rand.reset(seed)
  seeds : [16]i64
  for &n in seeds do n = rand.int63()
  for depth in 0..< CHUNK_HEIGHT {
    for row in 0..< CHUNK_SIZE {
      for col in 0..< CHUNK_SIZE {
        coord := [3]i32{ row, depth, col }
        voxel := GetVoxel(game, {row, -depth, col})
        voxel.Type = .DIRT
                
        if row > 1 && row < CHUNK_SIZE - 2 && col > 1 && col < CHUNK_SIZE - 2 {
          voxel.Type = .SOLID
          continue;
        }
        
        if depth == 0 && (row == 0 || row == CHUNK_SIZE - 1 || col == 0 || col == CHUNK_SIZE - 1) {
          voxel.Type = .NONE
          continue;
        }
                  
        if depth < 1 {
          voxel.Type = .DIRT
          continue
        }
        
        if depth == CHUNK_HEIGHT - 1 {
          voxel.Type = .SOLID
          continue
        }
        
        Helix :: proc(t, radius, h: f32) -> [3]f32 {
          return {
            radius * math.cos(2 * math.PI * t),
            h * t,
            radius * math.sin(2 * math.PI * t),
          }
        }
        
        hardness := f32(depth) / f32(CHUNK_HEIGHT)
        HELIX_PITCH : f32 : 20
        helix := linalg.dot(Helix(f32(depth) / HELIX_PITCH, 1, HELIX_PITCH).xz, linalg.normalize([2]f32{f32(row), f32(col) } - { f32(CHUNK_SIZE) / 2, f32(CHUNK_SIZE / 2) }))
        hardness += ((helix + 1) * 0.5) * 0
                
        {
          noise := (noise.noise_3d_improve_xz(seeds[0], {f64(row), f64(-depth), f64(col)} / 10) + 1) * 0.5
          hardness += noise
          if hardness / 3 > 0.3 do voxel.Type = .ROCK
          if hardness / 3 > 0.4 do voxel.Type = .ROCK2
        }
        
        {
          noise := (noise.noise_3d_improve_xz(seeds[1], {f64(row), f64(-depth), f64(col)}) + 1) * 0.5
          if noise < ThreshFromRange(RANGES[.COAL ], depth) do voxel.Type = .COAL
        }
        
        {
          noise := (noise.noise_3d_improve_xz(seeds[2], {f64(row), f64(-depth), f64(col)}) + 1) * 0.5
          if noise < ThreshFromRange(RANGES[.IRON ], depth) do voxel.Type = .IRON
        }
        
        {
          noise := (noise.noise_3d_improve_xz(seeds[3], {f64(row), f64(-depth), f64(col)}) + 1) * 0.5
          if noise < ThreshFromRange(RANGES[.SILVER ], depth) do voxel.Type = .SILVER
        }
        
        {
          noise := (noise.noise_3d_improve_xz(seeds[4], {f64(row), f64(-depth), f64(col)}) + 1) * 0.5
          if noise < ThreshFromRange(RANGES[.GOLD ], depth) do voxel.Type = .GOLD
        }
        
        {
          noise := (noise.noise_3d_improve_xz(seeds[5], {f64(row), f64(-depth), f64(col)}) + 1) * 0.5
          if noise < ThreshFromRange(RANGES[.SAPHIRE], depth) do voxel.Type = .SAPHIRE
        }
        
        {
          noise := (noise.noise_3d_improve_xz(seeds[6], {f64(row), f64(-depth), f64(col)}) + 1) * 0.5
          if noise < ThreshFromRange(RANGES[.EMERALD], depth) do voxel.Type = .EMERALD
        }
        
        {
          noise := (noise.noise_3d_improve_xz(seeds[7], {f64(row), f64(-depth), f64(col)}) + 1) * 0.5
          if noise < ThreshFromRange(RANGES[.RUBY], depth) do voxel.Type = .RUBY
        }
        
        {
          noise := (noise.noise_3d_improve_xz(seeds[8], {f64(row), f64(-depth), f64(col)}) + 1) * 0.5
          if noise < ThreshFromRange(RANGES[.DIAMOND], depth) do voxel.Type = .DIAMOND
        }
        
        {
          noise := (noise.noise_3d_improve_xz(seeds[9], {f64(row), f64(-depth), f64(col)} / 10 + 0.1) + 1) * 0.5
          if noise < ThreshFromRange(RANGES[.NONE], depth) do voxel.Type = .NONE
        }
      }
    }
  }
  
  for &v in game.Voxels {
    v.Health = VoxelProps[v.Type].Health
  }
}

//We used to have a world generator that did no guarantee the first layer to be intact or even exist.
//This is not really the case anymore but for good measure we keep and use this procedure anyways
FindAndSetPlayerStartLoc :: proc(game: ^GameState) -> bool {
  for depth in 0..< CHUNK_HEIGHT {
    for row in 0..< CHUNK_SIZE {
      for col in 0..< CHUNK_SIZE {
        if GetVoxel(game, { row, -depth, col }).Type != .NONE && GetVoxel(game, { row, -depth + 1, col }).Type == .NONE {
          game.DrillCoord = { row, -depth + 1, col }
          game.PrevDrillCoord = game.DrillCoord
          game.WheelDir = { 0, -1, 0 }
          
          game.DriveDir = { 1, 0, 0 }
          game.DrillDir = { 1, 0, 0 }
          return true
        }
      }
    }
  }
  return false
}

ResetGame :: proc(game: ^GameState) {
  game.Player = {}
  game.MaxDepthReached = 0
  
  game.DrillCoord.y = 1
  game.DriveDir.x = 1
  
  game.DrillDir.x = 1
  game.WheelDir.y = -1
  
  game.Fuel = UpgradeProps[.FUEL][game.Upgrades[.FUEL]].Value
  game.Hull = UpgradeProps[.HULL][game.Upgrades[.HULL]].Value
  
  game.CanDrive = true
  game.CanSteer = true
  game.CanClimb = true
    
  //We used to have a world generation that did not guarantee
  //a solid layer of blocks on the surface for the player to start.
  //That is not really the case anymore but be run the full logic anyways.
  for i : u64 = 0; !FindAndSetPlayerStartLoc(game) || i == 0; i += 1 {
    GenerateWorld(game, i + u64(time.time_to_unix_nano(time.now())))
  }
  game.ForceUpdateAllVoxels = true
}

Rescue :: proc(game: ^GameState) {
  for cargo, type in game.Cargo {
    if cargo > 0 {
      arr.push_back(&game.UiEffects, UiEffectValueChange { .CARGO, -cargo, type })
    }
  }

  FindAndSetPlayerStartLoc(game)
  game.Hull = UpgradeProps[.HULL][game.Upgrades[.HULL]].Value
  game.Fuel = UpgradeProps[.FUEL][game.Upgrades[.FUEL]].Value
  game.Cargo = {}
  game.FreeCam = false
}

main :: proc() {
  //We will replace all default allocators with our own below.
  //It's not technically necessary to set them to a panic_allocator first but this way we will
  //notice very early should we mess something up.
  context.allocator      = runtime.panic_allocator()
  context.temp_allocator = runtime.panic_allocator()
  
  //A good chunk of our data will stay alive until the application is exited.
  //This includes e.g. GameState and UiContext.
  //Stuff like this goes into the 'lifetimeArena', it never gets freed.
  //For short lived allocations we use scratch arenas or the 'frameArena' you will enocounter below.
  lifetimeArena: virtual.Arena
  _ = virtual.arena_init_static(&lifetimeArena, mem.Megabyte, mem.Megabyte)
  //context.allocator = virtual.arena_allocator(&lifetimeArena)
  
	frameArena: virtual.Arena 
	_ = virtual.arena_init_growing(&frameArena, 1024 * 4)
	context.temp_allocator = virtual.arena_allocator(&frameArena)

  //Enable logging only in debug builds
  when ODIN_DEBUG && ODIN_OS == .Windows {
		//Enable color code support for windows console.
		//Makes the logging look a bit better
    console := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE);
    if (console != win32.INVALID_HANDLE_VALUE) {
      mode: win32.DWORD
      win32.GetConsoleMode(console, &mode);
      mode |= win32.ENABLE_VIRTUAL_TERMINAL_PROCESSING;
      win32.SetConsoleMode(console, mode);
    }
		context.logger = log.create_console_logger(allocator = virtual.arena_allocator(&lifetimeArena))
	}
	
	//Initialize scratch arenas
	Scratch.Init()
	
	//Through our window abstraction layer, creating and showing a window becomes trivial.
	//Look into the 'Platform' package for more info.
	Platform.WindowInit()
	window := Platform.CreateAndShowWindow("Chunk Miner")
	
	if !Platform.WindowIsValid(window) {
	  log.error("Could not create window")
	  return
	}
  
  //Audio is probably the least mature part of this game.
  //Admitedly that is partly because it is also the part of game dev that I have the least experience with.
  //Getting something simple up and running with 'miniaudio' as we do here is simple enough.
  //However I do NOT recommend taking the audio code in this project as a best practice or anything.
  //It works for the simplest case but take it with a grain of salt. You probably want to build a different system.
  //This code mostly just follows the 'miniaudio' docs: https://miniaud.io/docs/examples/simple_looping.html
  Sound :: struct {
    Data: []byte,
    Decoder: ma.decoder,
  }
  
  SoundType :: enum {
    DRILL_AIR,
    DRILL_SOLID,
  }
  
  Audio :: struct {
    Sounds: [SoundType]Sound,
    Active: SoundType,
  }
  
  audio: Audio = {
    Sounds = {
      .DRILL_AIR   = { Data = #load("../data/sounds/drill2.wav", []byte)  },
      .DRILL_SOLID = { Data = #load("../data/sounds/drill.wav", []byte) },
    }
  }
  
  for &sound in audio.Sounds {
    ma.decoder_init_memory(rawptr(raw_data(sound.Data)), len(sound.Data), nil, &sound.Decoder)
    ma.data_source_set_looping((^ma.data_source)(&sound.Decoder), true)
  }
  
  audio_callback :: proc "cdecl" (pDevice: ^ma.device, pOutput: rawptr, pInput: rawptr, frameCount: u32) {
    audio := (^Audio)(pDevice.pUserData)
    
    ma.data_source_read_pcm_frames((^ma.data_source)(&audio.Sounds[audio.Active] .Decoder), pOutput, u64(frameCount), nil)
  }
  
  audioDevice: ma.device
  audioConfig: ma.device_config
  
  audioConfig = ma.device_config_init(.playback)
  audioConfig.playback.format = audio.Sounds[.DRILL_AIR].Decoder.outputFormat
  audioConfig.playback.channels = audio.Sounds[.DRILL_AIR].Decoder.outputChannels
  audioConfig.sampleRate = audio.Sounds[.DRILL_AIR].Decoder.outputSampleRate
  audioConfig.dataCallback = audio_callback
  audioConfig.pUserData = &audio
  
  ma.device_init(nil, &audioConfig, &audioDevice)
  ma.device_set_master_volume(&audioDevice, 0.2)

  gpu    := new(Gpu   , virtual.arena_allocator(&lifetimeArena))
  gpuRes := new(GpuRes, virtual.arena_allocator(&lifetimeArena))
  
  game: ^GameState
  {
    temp := Scratch.Begin()
    defer Scratch.End(temp)
    
    game = new(GameState, virtual.arena_allocator(&lifetimeArena))
    assert(mem.is_aligned(raw_data(&game.ParticleTextBuff), size_of(mem.Buddy_Block)))
    if saveData, ok := os.read_entire_file_from_filename("ChunkMiner.save", allocator = virtual.arena_allocator(temp.arena)); ok {
      //One of the bigges benefits of keeping the whole game state in a simple struct is that serialization becomes trivial.
      //On game exit we just take the GameState struct and write it to disk 'as is' (in a more mature game you would want to do this more often
      //than just on exit).
      //To load the save we just read the data back and cast it into a GameState struct. That's pretty much it (with some caveats, see below).
      
      //DISCLAMER (Endianness):
      //In theory there is an issue with this.
      //Different architectures might use a different 'endianness'. You should look it up for more info but in short it defines the order of bytes
      //in memory for e.g. integers. This means that a save file created on a little endian (LE) system could not be loaded on a big endian (BE) system.
      //In practice however you'd be hard pressed to find a platform those days that uses BE. At least a platform that you would realistically want to run your game on.
      
      //DISCLAIMER (Changes):
      //There is one thing that you must keep in mind. This approach only works as long as no changes to the memory layout of 'GameState'
      //are being made. As soon as you e.g. add a new field to GameState the save file not only becomes invalid, there is also nothing
      //in place to stop you from blindly loading it anyways and running your game in an undefined state.
      //If the game is already published this would also mean that an update could/will break your player's save files.
      //This is an issue that absolutely needs to be addressed for a real game. We are just not doing it to keep this as simple as possible.
      //Possible approaches would be:
      //- A version number that must be manually incremented with each change to GameState
      //- Some kind of compile time check that automatically compares the currentGameState to the previously compiled GameState
      //- (In addition to the other options) Some kind of conversion/migration system to load old save files
      
      //We can not read the file directly into our game memory because read_entire_file_from_filename does not 
      //guarantee us the memory alignment we need.
      mem.copy_non_overlapping(game, raw_data(saveData), len(saveData))
      
      //Should the GameState contain pointers (directly or in nested structs) they will not be valid anymore.
      //In our case that is only an issue for the ParticleAllocator. We have to freshly initialize it to point to ParticleTextBuff
      //which will now be at a different memory location than last session.
      mem.buddy_allocator_init(&game.ParticleAllocator, game.ParticleTextBuff[:], size_of(u8))
      
      //The strings in text particles were using the 'frameArena' and are not valid anymore. We have to reset them.
      game.TextParticles = {}
      
      game.ForceUpdateAllVoxels = true
    }
    else {
      //Our normal initialization routine when no save file was loaded
      game.ShopCoordSell    = { 3, 1, 3 }
      game.ShopCoordMech    = { 3, 1, 6 }
      game.ShopCoordUpgrade = { 6, 1, 3 }
      
      game.CamController = DEFAULT_ORBIT
      game.CamController.TargetAngle = { math.to_radians_f32(-135), math.to_radians_f32(-20) }
      game.CamController.TargetRadius = 3.95
      
      game.Camera.FieldOfView = math.to_radians_f32(60)
      game.Camera.Near = 0.1
      game.Camera.Far = 1000
      OrbitControllerApplyToCamera(game.CamController, &game.Camera)
  
      mem.buddy_allocator_init(&game.ParticleAllocator, game.ParticleTextBuff[:], size_of(u8))
      ResetGame(game)
    }
  }

  game.CamController.DegPerPixel = 0.5
  game.CamController.RadiusPerScroll = 0.2
  game.CamController.HeightPerScroll = 2
  game.CamController.SmoothSpeed = 15
  game.CamController.SmoothThreshold = 0.001
  game.CamController.MaxHeight = 0.5
  game.CamController.MinHeight = -f32(CHUNK_HEIGHT) 
  
  //The following few hundreds lines of code are mostly Direct3D 11 initialization.
  //If you intend to support other graphics APIs (like OpenGL) you would want to abstract this away.
  //For this project however we are going all in on D3D and don't bother.
  //I will not explain too much of this code in detail. If you are a complete beginner when it comes to graphics programming/APIs,
  //I recommend https://learnopengl.com/. As the name implies, it does not teach D3D, but OpenGL.
  //However the concepts are mostly the same. When you know either D3D or OpenGL it is relatively easy to get into the other.
  //If you already know D3D (or OpenGL) all of this should be pretty straightforward to understand.
  {
    windowSize := Platform.GetWindowClientSize(window)
  
    swapchaindesc : dxgi.SWAP_CHAIN_DESC
    swapchaindesc.BufferDesc.Width  = u32(windowSize.x)
    swapchaindesc.BufferDesc.Height = u32(windowSize.y)
    swapchaindesc.BufferDesc.Format = dxgi.FORMAT.B8G8R8A8_UNORM
    swapchaindesc.SampleDesc.Count  = 1
    swapchaindesc.BufferUsage       = { .RENDER_TARGET_OUTPUT }
    swapchaindesc.BufferCount       = 2
    swapchaindesc.OutputWindow      = window.Handle
    swapchaindesc.Windowed          = true
    swapchaindesc.SwapEffect        = dxgi.SWAP_EFFECT.FLIP_DISCARD
  
when ODIN_DEBUG {
    d3d.CreateDeviceAndSwapChain(nil, d3d.DRIVER_TYPE.HARDWARE, nil, { .DEBUG }, nil, 0, 7, &swapchaindesc, &gpu.Swapchain, &gpu.Device, nil, &gpu.DeviceContext);
}
else {
    d3d.CreateDeviceAndSwapChain(nil, d3d.DRIVER_TYPE.HARDWARE, nil, { }, nil, 0, 7, &swapchaindesc, &gpu.Swapchain, &gpu.Device, nil, &gpu.DeviceContext);
}
    gpu.Swapchain->GetDesc(&swapchaindesc);
  }

  gpu.Swapchain->GetBuffer(0, d3d.ITexture2D_UUID, (^rawptr)(&gpuRes.RenderTarget))
  gpu.Device->CreateRenderTargetView(gpuRes.RenderTarget, nil, &gpuRes.RenderTargetView)
  
  {
    colorbufferdesc : d3d.TEXTURE2D_DESC
    gpuRes.RenderTarget->GetDesc(&colorbufferdesc);
    colorbufferdesc.SampleDesc.Count = MSAA_SAMPLES
  
    gpu.Device->CreateTexture2D(&colorbufferdesc, nil, &gpuRes.ColorBufferMS)
    gpu.Device->CreateRenderTargetView(gpuRes.ColorBufferMS, nil, &gpuRes.RenderTargetMSView)
  }

  {
    depthbufferdesc : d3d.TEXTURE2D_DESC
    gpuRes.RenderTarget->GetDesc(&depthbufferdesc);
    depthbufferdesc.SampleDesc.Count = MSAA_SAMPLES
    depthbufferdesc.Format = dxgi.FORMAT.D32_FLOAT
    depthbufferdesc.BindFlags = { .DEPTH_STENCIL }
  
    gpu.Device->CreateTexture2D(&depthbufferdesc, nil, &gpuRes.DepthBuffer)
    gpu.Device->CreateDepthStencilView(gpuRes.DepthBuffer, nil, &gpuRes.DepthStencilView)
  }

  {
    depthstencildesc : d3d.DEPTH_STENCIL_DESC
    depthstencildesc.DepthEnable = true
    depthstencildesc.DepthWriteMask = .ALL
    depthstencildesc.DepthFunc = .LESS
    
    gpu.Device->CreateDepthStencilState(&depthstencildesc, &gpuRes.DepthStencilStateDefault)
  }
  
  {
    depthstencildesc : d3d.DEPTH_STENCIL_DESC
    depthstencildesc.DepthEnable = true
    depthstencildesc.DepthWriteMask = .ALL
    depthstencildesc.DepthFunc = .LESS_EQUAL
    
    gpu.Device->CreateDepthStencilState(&depthstencildesc, &gpuRes.DepthStencilStateSkybox)
  }
  
  {
    depthstencildesc : d3d.DEPTH_STENCIL_DESC
    depthstencildesc.DepthEnable = true
    depthstencildesc.DepthWriteMask = .ZERO
    depthstencildesc.DepthFunc = .LESS
    
    gpu.Device->CreateDepthStencilState(&depthstencildesc, &gpuRes.DepthStencilStateNoWrite)
  }

  {
    samplerdesc : d3d.SAMPLER_DESC
    samplerdesc.Filter         = d3d.FILTER.MIN_MAG_MIP_POINT
    samplerdesc.AddressU       = d3d.TEXTURE_ADDRESS_MODE.CLAMP
    samplerdesc.AddressV       = d3d.TEXTURE_ADDRESS_MODE.CLAMP
    samplerdesc.AddressW       = d3d.TEXTURE_ADDRESS_MODE.CLAMP
    samplerdesc.ComparisonFunc = d3d.COMPARISON_FUNC.NEVER
  
    gpu.Device->CreateSamplerState(&samplerdesc, &gpuRes.SamplerState);
  }
    
  {
    //Load the texture for our UI font
    FONT_ATLAS_PNG :: #load("../data/textures/BoldBlocks.png", []byte)

    x, y, channels : c.int
    data := stbi.load_from_memory(raw_data(FONT_ATLAS_PNG), i32(len(FONT_ATLAS_PNG)), &x, &y, &channels, 4)[:x * y * channels] 
    
    texturedesc : d3d.TEXTURE2D_DESC
    texturedesc.Width  = u32(x)
    texturedesc.Height = u32(y)
    texturedesc.MipLevels = 1
    texturedesc.ArraySize = 1
    texturedesc.Format = dxgi.FORMAT.R8G8B8A8_UNORM
    texturedesc.SampleDesc.Count = 1
    texturedesc.Usage = d3d.USAGE.IMMUTABLE
    texturedesc.BindFlags = { .SHADER_RESOURCE }
  
    textureData : d3d.SUBRESOURCE_DATA
    textureData.pSysMem = raw_data(data)
    textureData.SysMemPitch = u32(x * channels * size_of(byte))
    
    gpu.Device->CreateTexture2D(&texturedesc, &textureData, &gpuRes.FontTexture)
    gpu.Device->CreateShaderResourceView(gpuRes.FontTexture, nil, &gpuRes.FontTextureView)
    
    //The texture was uploaded to the GPU, we don't need it anymore and can free it.
    //We do not really have control over how stb_image allocates memory so this is the only exception
    //in our project where we can not use a ScratchArena
    stbi.image_free(raw_data(data))
  }
  
  {
    CRACKS_PNG :: #load("../data/textures/Cracks.png", []byte)

    x, y, channels : c.int
    data := stbi.load_from_memory(raw_data(CRACKS_PNG), i32(len(CRACKS_PNG)), &x, &y, &channels, 4)[:x * y * channels] 
    
    texturedesc : d3d.TEXTURE2D_DESC
    texturedesc.Width  = u32(x)
    texturedesc.Height = u32(y)
    texturedesc.MipLevels = 1
    texturedesc.ArraySize = 1
    texturedesc.Format = dxgi.FORMAT.R8G8B8A8_UNORM
    texturedesc.SampleDesc.Count = 1
    texturedesc.Usage = d3d.USAGE.IMMUTABLE
    texturedesc.BindFlags = { .SHADER_RESOURCE }
  
    textureData : d3d.SUBRESOURCE_DATA
    textureData.pSysMem = raw_data(data)
    textureData.SysMemPitch = u32(x * channels * size_of(byte))
    
    gpu.Device->CreateTexture2D(&texturedesc, &textureData, &gpuRes.CrackTexture)
    gpu.Device->CreateShaderResourceView(gpuRes.CrackTexture, nil, &gpuRes.CrackTextureView)
    
    //The texture was uploaded to the GPU, we don't need it anymore and can free it.
    stbi.image_free(raw_data(data))
  }

  {
    texturedesc : d3d.TEXTURE3D_DESC
    texturedesc.Width  = u32(CHUNK_SIZE)
    texturedesc.Height = u32(CHUNK_SIZE)
    texturedesc.Depth  = u32(CHUNK_HEIGHT)
    texturedesc.MipLevels = 1
    texturedesc.Format = dxgi.FORMAT.R32_SINT
    texturedesc.Usage = d3d.USAGE.DEFAULT
    texturedesc.BindFlags = { .SHADER_RESOURCE }
    texturedesc.CPUAccessFlags = { .WRITE };
  
    textureData : d3d.SUBRESOURCE_DATA
    textureData.pSysMem = nil
    textureData.SysMemPitch      = u32(CHUNK_SIZE * size_of(VoxelGpu))
    textureData.SysMemSlicePitch = u32(CHUNK_SIZE * CHUNK_SIZE * size_of(VoxelGpu))
    
    //Create the 3D texture that will contain our voxel data
    gpu.Device->CreateTexture3D(&texturedesc, nil, &gpuRes.VoxelTex)
    gpu.Device->CreateShaderResourceView(gpuRes.VoxelTex, nil, &gpuRes.VoxelTexView)
  }
  
  CreateShaderAndInputLayout :: proc(gpu: ^Gpu, source: string, layout: ^^d3d.IInputLayout, desc: []d3d.INPUT_ELEMENT_DESC, vShader: ^^d3d.IVertexShader, pShader: ^^d3d.IPixelShader) {
    shaderCompilationOutput : ^d3d.IBlob
    errorBlob : ^d3d.IBlob
    if d3d_compiler.Compile(raw_data(source), len(source), nil, nil, nil, "vertex_shader", "vs_5_0", 0, 0, &shaderCompilationOutput, &errorBlob) != 0 {
      log.error(cstring(errorBlob->GetBufferPointer()))
      errorBlob->Release()
    }
    gpu.Device->CreateVertexShader(shaderCompilationOutput->GetBufferPointer(), shaderCompilationOutput->GetBufferSize(), nil, vShader);

    gpu.Device->CreateInputLayout(raw_data(desc), u32(len(desc)), shaderCompilationOutput->GetBufferPointer(), shaderCompilationOutput->GetBufferSize(), layout);
    shaderCompilationOutput->Release()
  
    d3d_compiler.Compile(raw_data(source), len(source), nil, nil, nil, "pixel_shader", "ps_5_0", 0, 0, &shaderCompilationOutput, nil)
    gpu.Device->CreatePixelShader(shaderCompilationOutput->GetBufferPointer(), shaderCompilationOutput->GetBufferSize(), nil, pShader);
    shaderCompilationOutput->Release()  
  }
  
  DEFAULT_3D_LAYOUT_DESC := [?]d3d.INPUT_ELEMENT_DESC {
    { "POS", 0, dxgi.FORMAT.R32G32B32_FLOAT, 0, 0, d3d.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
    { "NOR", 0, dxgi.FORMAT.R32G32B32_FLOAT, 0, d3d.APPEND_ALIGNED_ELEMENT, d3d.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
    { "TEX", 0, dxgi.FORMAT.R32G32_FLOAT   , 0, d3d.APPEND_ALIGNED_ELEMENT, d3d.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
    { "COL", 0, dxgi.FORMAT.R32G32B32A32_FLOAT, 0, d3d.APPEND_ALIGNED_ELEMENT, d3d.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
  }
    
  //The game is simple enough that we are going to just embed all game files into the executable.
  //We then load and initialize all our game data on startup and keep them around until the program exits.
  //For a small game this works just fine but keep in mind that this increases the size of the executable, which may or may not cause issues at some point.
  //For bigger games this is usually not the way to go. Game files are usually stored separately to the executable. Maybe even in a packaged format optimized
  //for loading or even streaming in and out at runtime. Not always is loading everything at startup an option.
  CreateShaderAndInputLayout(gpu, #load("../data/shaders/Simple.hlsl", string), &gpuRes.LayoutSimple, DEFAULT_3D_LAYOUT_DESC[:], &gpuRes.VsSimple, &gpuRes.PsSimple)
  CreateShaderAndInputLayout(gpu, #load("../data/shaders/Voxel.hlsl" , string) , &gpuRes.LayoutVoxel , DEFAULT_3D_LAYOUT_DESC[:], &gpuRes.VsVoxel, &gpuRes.PsVoxel )
  CreateShaderAndInputLayout(gpu, #load("../data/shaders/VoxelSimple.hlsl", string), &gpuRes.LayoutVoxelSimple, DEFAULT_3D_LAYOUT_DESC[:], &gpuRes.VsVoxelSimple, &gpuRes.PsVoxelSimple)
  CreateShaderAndInputLayout(gpu, #load("../data/shaders/Hologram.hlsl", string), &gpuRes.LayoutHologram, DEFAULT_3D_LAYOUT_DESC[:], &gpuRes.VsHologram, &gpuRes.PsHologram)
  
  DEFAULT_2D_LAYOUT_DESC := [?]d3d.INPUT_ELEMENT_DESC {
    { "POS", 0, dxgi.FORMAT.R32G32_FLOAT, 0, 0, d3d.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
    { "TEX", 0, dxgi.FORMAT.R32G32_FLOAT   , 0, d3d.APPEND_ALIGNED_ELEMENT, d3d.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
    { "COL", 0, dxgi.FORMAT.R32G32B32A32_FLOAT, 0, d3d.APPEND_ALIGNED_ELEMENT, d3d.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
  }

  CreateShaderAndInputLayout(gpu, #load("../data/shaders/Gui.hlsl", string), &gpuRes.LayoutUi, DEFAULT_2D_LAYOUT_DESC[:], &gpuRes.VsUi, &gpuRes.PsUi)
  CreateShaderAndInputLayout(gpu, #load("../data/shaders/ScreenQuad.hlsl", string), &gpuRes.LayoutScreenQuad, DEFAULT_2D_LAYOUT_DESC[:], &gpuRes.VsScreenQuad, &gpuRes.PsScreenQuad)

  //We use the #align directive and some manual padding to make sure our struct layout matches the expected HLSL layout.
  //I recommend https://maraneshi.github.io/HLSL-ConstantBufferLayoutVisualizer/ if you need help figuring out struct layouts.
  
  //Data that is shared by most, if not all, shaders.
  GpuSharedData :: struct #align(16) {
    ViewProjMatrix  : matrix[4, 4]f32,
    LightDir    : [3]f32,
    MaxDepthReached: i32,
    ViewportSize : [2]f32,
    _ : [2]f32,
    CamPos : [3]f32,
  }
  
  //Data that is specifically relevant for rendering the voxel chunk.
  GpuVoxelChunkData :: struct #align(16) {
    IdOffset: u32,
    JiggleCoord: [3]i32,
    Rand: [3]f32,
  }
  
  //Data that is specifically relevant for rendering 'normal' 3D models (not voxels)
  GpuModelData :: struct #align(16) {
    ModelMatrix : matrix[4, 4]f32,
    Color : [3]f32,
    Voxel: VoxelGpu,
  }
  
  CreateConstantBuffer :: proc($T: typeid, gpu: ^Gpu) -> ^d3d.IBuffer {
    bufferdesc : d3d.BUFFER_DESC;
    bufferdesc.ByteWidth      = size_of(T);
    bufferdesc.Usage          = d3d.USAGE.DYNAMIC;
    bufferdesc.BindFlags      = { .CONSTANT_BUFFER };
    bufferdesc.CPUAccessFlags = { .WRITE };
    
    result: ^d3d.IBuffer
    gpu.Device->CreateBuffer(&bufferdesc, nil, &result);
    return result
  }
  
  gpuRes.SharedBuffer     = CreateConstantBuffer(GpuSharedData    , gpu)
  gpuRes.ModelBuffer      = CreateConstantBuffer(GpuModelData     , gpu)
  gpuRes.VoxelChunkBuffer = CreateConstantBuffer(GpuVoxelChunkData, gpu)
  
  {
    rasterizerdesc : d3d.RASTERIZER_DESC 
    rasterizerdesc.FillMode = d3d.FILL_MODE.SOLID
    rasterizerdesc.CullMode = d3d.CULL_MODE.BACK
    rasterizerdesc.FrontCounterClockwise = true
    rasterizerdesc.DepthClipEnable = true
  
    gpu.Device->CreateRasterizerState(&rasterizerdesc, &gpuRes.Rasterizer3d);
  }
  
  {
    rasterizerdesc : d3d.RASTERIZER_DESC 
    rasterizerdesc.FillMode = d3d.FILL_MODE.SOLID
    rasterizerdesc.CullMode = d3d.CULL_MODE.BACK
  
    gpu.Device->CreateRasterizerState(&rasterizerdesc, &gpuRes.Rasterizer2d);
  }
  
  {
    blendDesc : d3d.BLEND_DESC
    blendDesc.RenderTarget[0].BlendEnable = true
    blendDesc.RenderTarget[0].RenderTargetWriteMask = 255;
    blendDesc.RenderTarget[0].SrcBlend = d3d.BLEND.SRC_ALPHA;
    blendDesc.RenderTarget[0].DestBlend = d3d.BLEND.INV_SRC_ALPHA;
    blendDesc.RenderTarget[0].BlendOp = d3d.BLEND_OP.ADD;
    blendDesc.RenderTarget[0].SrcBlendAlpha = d3d.BLEND.SRC_ALPHA;
    blendDesc.RenderTarget[0].DestBlendAlpha = d3d.BLEND.DEST_ALPHA;
    blendDesc.RenderTarget[0].BlendOpAlpha = d3d.BLEND_OP.ADD;
    blendDesc.RenderTarget[0].RenderTargetWriteMask = u8(d3d.COLOR_WRITE_ENABLE_ALL);
    gpu.Device->CreateBlendState(&blendDesc, &gpuRes.BlendState)
  }
  
  Vertex2D :: struct {
    Pos : Vec2,
    Tex : Vec2,
    Col : Vec4
  }

  Vertex3D :: struct {
    Pos : Vec3,
    Nor : Vec3,
    Tex : Vec2,
    Col : Vec4,
  }
    
  //The .obj file format stores vertex data in a format that is a bit annoying to convert to an index based
  //vertex buffer. Instead we do the simple (but wasteful) thing and do not use an index buffer at all.
  //Instead we naively create new vertices for every face, even if some of the vertex data could maybe be 
  //shared between faces.
  VerticesFromObj :: proc(arena: ^virtual.Arena, obj: ObjLoader.Object) -> []Vertex3D {
    vertices := make([]Vertex3D, len(obj.Faces) * 3, virtual.arena_allocator(arena))
    it := vertices
    
    for face in obj.Faces {
      for v, i in face {
        vert: Vertex3D
        vert.Pos = obj.Coords[v.Coord - 1].xyz
        vert.Tex = obj.TexCoords[v.TexCoord - 1].xy
        vert.Nor = obj.Normals[v.Normal - 1]
        vert.Col = { 0.5, 0.5, 0.5, 1 }
        it[0] = vert
        it = it[1:]
      }
    }
    
    return vertices
  }
  
  //Creates the vertex buffer on the GPU and transfers the vertex data.
  //Afterwards the vertex data can be freed on the CPU side.
  CreateVertexBufferImmutable :: proc(gpu: ^Gpu, dst: ^^d3d.IBuffer, vertices: []$V) {
    vertexbufferdesc : d3d.BUFFER_DESC
    vertexbufferdesc.ByteWidth = u32(len(vertices) * size_of(V))
    vertexbufferdesc.Usage     = d3d.USAGE.IMMUTABLE
    vertexbufferdesc.BindFlags = { .VERTEX_BUFFER }

    vertexbufferData : d3d.SUBRESOURCE_DATA = { pSysMem = raw_data(vertices) }
    gpu.Device->CreateBuffer(&vertexbufferdesc, &vertexbufferData, dst)
  }
  
  //Loads vertex data from an .obj string, converts it into a vertex buffer that is suitable for our renderer,
  //uploads it to the GPU and then frees the .obj data.
  VBufferFromObj :: proc(gpu: ^Gpu, objData: string) -> GpuVertexBuffer {
    vBuffer: GpuVertexBuffer
    
    temp := Scratch.Begin()
    obj, ok := ObjLoader.LoadFromMemory(temp.arena, objData)
    vertices := VerticesFromObj(temp.arena, obj)
    CreateVertexBufferImmutable(gpu, &vBuffer.Buffer, vertices)
    vBuffer.Len = len(vertices)
    Scratch.End(temp)
    
    return vBuffer
  }
  
  gpuRes.VBufferCube     = VBufferFromObj(gpu, #load("../data/meshes/Cube.obj"    , string))
  gpuRes.VBufferCubeLow  = VBufferFromObj(gpu, #load("../data/meshes/CubeLow.obj" , string))
  gpuRes.VBufferDrill    = VBufferFromObj(gpu, #load("../data/meshes/Driller.obj" , string))
  gpuRes.VBufferWheels   = VBufferFromObj(gpu, #load("../data/meshes/Wheels.obj"  , string))
  gpuRes.VBufferCar      = VBufferFromObj(gpu, #load("../data/meshes/Car.obj"     , string))
  gpuRes.VBufferMechanic = VBufferFromObj(gpu, #load("../data/meshes/Mechanic.obj", string))
  gpuRes.VBufferUpgrade  = VBufferFromObj(gpu, #load("../data/meshes/Upgrade.obj" , string))
  gpuRes.VBufferCoins    = VBufferFromObj(gpu, #load("../data/meshes/Coins.obj"   , string))
  
  verticesQuad := [?]Vertex2D {
    { Pos = { -1, +1 }, Tex = { 0, 0 }, Col = { 0, 0, 0, 0 } },
    { Pos = { +1, +1 }, Tex = { 1, 0 }, Col = { 0, 0, 0, 0 } },
    { Pos = { +1, -1 }, Tex = { 1, 1 }, Col = { 0, 0, 0, 0 } },
    
    { Pos = { +1, -1 }, Tex = { 1, 1 }, Col = { 0, 0, 0, 0 } },
    { Pos = { -1, -1 }, Tex = { 0, 1 }, Col = { 0, 0, 0, 0 } },
    { Pos = { -1, +1 }, Tex = { 0, 0 }, Col = { 0, 0, 0, 0 } },
  }
  
  verticesOrigin := [?]Vertex3D {
    { { 0, 0, 0 }, {}, { 1, 1 }, { 1, 0, 0, 1} },
    { { 2, 0, 0 }, {}, { 1, 1 }, { 1, 0, 0, 1} },
    
    { { 0, 0, 0 }, {}, { 1, 1 }, { 0, 1, 0, 1} },
    { { 0, 2, 0 }, {}, { 1, 1 }, { 0, 1, 0, 1} },
    
    { { 0, 0, 0 }, {}, { 1, 1 }, { 0, 0, 1, 1} },
    { { 0, 0, 2 }, {}, { 1, 1 }, { 0, 0, 1, 1} },
  };
  
  CreateVertexBufferImmutable(gpu, &gpuRes.VBufferQuad  , verticesQuad  [:])
  CreateVertexBufferImmutable(gpu, &gpuRes.VBufferOrigin, verticesOrigin[:])

  {
    vertexbufferdesc : d3d.BUFFER_DESC
    vertexbufferdesc.ByteWidth = size_of(Vertex2D) * 100
    vertexbufferdesc.CPUAccessFlags = { .WRITE }
    vertexbufferdesc.Usage     = d3d.USAGE.DYNAMIC
    vertexbufferdesc.BindFlags = { .VERTEX_BUFFER }

    gpu.Device->CreateBuffer(&vertexbufferdesc, nil, &gpuRes.VBufferUi)
  }
  
  {
    vertexbufferdesc : d3d.BUFFER_DESC
    vertexbufferdesc.ByteWidth = size_of(Vertex2D) * 100
    vertexbufferdesc.CPUAccessFlags = { .WRITE }
    vertexbufferdesc.Usage     = d3d.USAGE.DYNAMIC
    vertexbufferdesc.BindFlags = { .VERTEX_BUFFER }

    gpu.Device->CreateBuffer(&vertexbufferdesc, nil, &gpuRes.VBufferGameUi)
  }
  
  matrix_persp_right_handed_zero_to_one :: proc(fovY, aspect, zNear, zFar : f32) -> matrix[4, 4]f32 {
    result : Mat4 = f32(0)

    tanHalfFovY := math.tan(fovY / 2.0)
    result[0, 0] = 1 / (aspect * tanHalfFovY);
		result[1, 1] = 1 / (tanHalfFovY);
		result[2, 2] = zFar / (zFar - zNear);
		result[3, 2] = 1;
		result[2, 3] = -(zFar * zNear) / (zFar - zNear);
    return result
  }
  
  //Initialize our UiContext. It is allocated on the lifetimeArena and will persist until the application exits.
  //We use a very simple immediate mode UI similar to the popular UI library DearImgui (just very, VERY simplified).
  //For more information about immediate mode UIs I recommend:
  //- https://www.rfleury.com/p/ui-series-table-of-contents
  //- https://github.com/ocornut/imgui
  uiCtx := new(UiContext, virtual.arena_allocator(&lifetimeArena))
  uiCtx.Colors = {
    .TEXT = { 1, 1, 1, 1 },
    .TEXT_HOVERED = { 0.8, 0.8, 0.8, 1 }, 
  }
  uiCtx.PlatformWindow = window
  
  Time :: struct {
    Total: f64,
    Delta: f64,
  }

  time: Time
  time.Delta = 0.016 //Initialize to a non-zero value for the first frame
  shouldExit := false
  for !shouldExit {
    frameTimer: Platform.Timer
    Platform.TimerStart(&frameTimer)
    
    frameArenaBytesUsed     := frameArena.total_used
    frameArenaBytesReserved := frameArena.total_reserved
    
    //At the beginning of every frame we have to clear the temp allocator, which is our per frame arena.
    //This also clear everything that was allocated with the temp allocator during startup.
    free_all(context.temp_allocator)
    
    events := Platform.GetEvents(window, &frameArena)
    
    windowSize := Platform.GetWindowClientSize(window)
    aspectRatio := f32(windowSize.x) / f32(windowSize.y)
    game.Camera.AspectRatio = aspectRatio

    //Create UI
    //Keep in mind that all strings that we push into the UI system via e.g. UiAddText, UiAddButton
    //must stay valid until we render the UI later.
    //Admittedly this is a bit of a pitfall.
    //A bigger, more mature UI system might want to have it's own allocator to store its strings.
    //Note that UI systems like DearImGui work a bit different. It uses the text only temporarily to create a vertex buffer directly.
    //Our UI systems stores the text and only creates the vertex buffer just before rendering.
    {
      UiStartFrame(uiCtx, events[:])
      COL_WHITE :: [4]f32 { 1, 1, 1, 1 }
      COL_GOLD  :: [4]f32 { 1, 215 / 255.0, 0, 1 }
      COL_WARNING  :: [4]f32 { 1, 0.624, 0, 1 }
      COL_CRITICAL :: [4]f32 { 1, 0, 0, 1 }
      
      fuelEndCursor: [2]f32
      fuelText := fmt.tprintf("Fuel: {}/{}", game.Fuel, UpgradeProps[.FUEL][game.Upgrades[.FUEL]].Value)
      hullText := fmt.tprintf("Hull: {}/{}", game.Hull, UpgradeProps[.HULL][game.Upgrades[.HULL]].Value)
      maxFuelText := fmt.tprintf("Fuel: {}/{}", UpgradeProps[.FUEL][game.Upgrades[.FUEL]].Value, UpgradeProps[.FUEL][game.Upgrades[.FUEL]].Value)
      maxHullText := fmt.tprintf("Hull: {}/{}", UpgradeProps[.HULL][game.Upgrades[.HULL]].Value, UpgradeProps[.HULL][game.Upgrades[.HULL]].Value)
      xPosBars := f32(math.max(CalcTextSize(maxFuelText).x, CalcTextSize(maxHullText).x))
      {
        fuelCritical := game.Fuel < 10
        fuelEmpty    := game.Fuel == 0
        
        if fuelCritical do UiPushColor(uiCtx, .TEXT, { 1, 0.608, 0, 1 }) 
        defer if fuelCritical do UiPopColor(uiCtx)
        
        if fuelEmpty do UiPushColor(uiCtx, .TEXT, { 0.878, 0, 0, 1 }) 
        defer if fuelEmpty do UiPopColor(uiCtx)
        
        cursor := uiCtx.Cursor
        UiAddText(uiCtx, fuelText, { 0, 0 })
        
        uiCtx.Cursor = cursor + { f32(WINDOW_PADDING + xPosBars) + 10, -3 }
        {
          fuelPercent := f32(game.Fuel) / f32(UpgradeProps[.FUEL][game.Upgrades[.FUEL]].Value)
          fuelSlots := game.Fuel / 10
        
          data := make([]u8, fuelSlots, virtual.arena_allocator(&frameArena))
          for &slot, i in data do slot = '|'
          UiPushColor(uiCtx, .TEXT, { 0, 1, 0, 1 })
          UiAddText(uiCtx, string(data))        
          UiPopColor(uiCtx)
          
          fuelEndCursor = uiCtx.Cursor - { 0, f32(FONT_ATLAS_LINE_HEIGHT) }
        }
      }
      
      uiCtx.Cursor.x = WINDOW_PADDING
      {
        hullCritical := game.Hull < 5
        hullEmpty    := game.Hull == 0
        
        if hullCritical do UiPushColor(uiCtx, .TEXT, { 1, 0.608, 0, 1 }) 
        defer if hullCritical do UiPopColor(uiCtx)
        
        if hullEmpty do UiPushColor(uiCtx, .TEXT, { 0.878, 0, 0, 1 }) 
        defer if hullEmpty do UiPopColor(uiCtx)
        
        cursor := uiCtx.Cursor
        UiAddText(uiCtx, hullText, { 0, 0 })
        
        uiCtx.Cursor = cursor + { f32(WINDOW_PADDING + xPosBars) + 10, -3 }
        {
          hullPercent := f32(game.Hull) / f32(UpgradeProps[.HULL][game.Upgrades[.HULL]].Value)
          hullSlots := game.Hull / 10
        
          data := make([]u8, hullSlots, virtual.arena_allocator(&frameArena))
          for &slot, i in data do slot = '|'
          UiPushColor(uiCtx, .TEXT, { 0, 1, 0, 1 })
          UiAddText(uiCtx, string(data))        
          UiPopColor(uiCtx)
        }
      }
            
      uiCtx.Cursor.x = WINDOW_PADDING
      when ODIN_DEBUG {
        UiAddText(uiCtx, fmt.tprintf("FPS: %f", (1 / time.Delta)))
        UiAddText(uiCtx, "Memory usage (bytes)")
        UiAddText(uiCtx, fmt.tprintf("Frame arena: {}/{}", frameArenaBytesUsed, frameArenaBytesReserved))
        UiAddText(uiCtx, fmt.tprintf("Scratch arena0: {}", Scratch.Arenas[0].total_reserved))
        UiAddText(uiCtx, fmt.tprintf("Scratch arena1: {}", Scratch.Arenas[1].total_reserved))
        UiAddText(uiCtx, fmt.tprintf("GameState: {}", size_of(GameState) - size_of(game.Voxels)))
        UiAddText(uiCtx, fmt.tprintf("Voxels: {}", size_of(game.Voxels)))
      }
      UiAddText(uiCtx, "--- Cargo ---")
      cargoFillTotal: i32
      for type in VoxelType {
        if game.Cargo[type] > 0 do UiAddText(uiCtx, fmt.tprintf("{} x{}", VoxelProps[type].Name, game.Cargo[type]))
        cargoFillTotal += game.Cargo[type]
      }
      
      if cargoFillTotal == 0 {
        UiPushColor(uiCtx, .TEXT, { 0.5, 0.5, 0.5, 1 })
        UiAddText(uiCtx, "Empty")
        UiPopColor(uiCtx)
      }
      else {
        UiAddText(uiCtx, "-------------")
        UiAddText(uiCtx, fmt.tprintf("Total: {}/{}", cargoFillTotal, UpgradeProps[.CARGO][game.Upgrades[.CARGO]].Value))
      }
      
      if game.Fuel == 0 || game.Hull == 0 {
        cursor := uiCtx.Cursor
        defer uiCtx.Cursor = cursor
        
        uiCtx.Cursor.x = windowSize.x * 0.5
        uiCtx.Cursor.y = windowSize.y * 0.75
        UiPushColor(uiCtx, .TEXT, COL_CRITICAL)
        if game.Fuel == 0 do UiAddText(uiCtx, "Fuel empty!", { 0.5, 0 })
        if game.Hull == 0 do UiAddText(uiCtx, "Hull broken!", { 0.5, 0 })
        UiPopColor(uiCtx)
        
        if UiAddButton(uiCtx, "Click here to send rescue mission", { 0.5, 0 }).Clicked {
          Rescue(game)
        }
      }
            
      uiCtx.Cursor = { windowSize.x - WINDOW_PADDING, WINDOW_PADDING }
      
      UiPushColor(uiCtx, .TEXT, COL_GOLD)
      UiAddText(uiCtx, fmt.tprintf("Money: {}$", game.MoneyTotal), { 1, 0 })
      UiPopColor(uiCtx)
      
      if game.DrillCoord == game.ShopCoordUpgrade {
        UiAddText(uiCtx, "--- Upgrades ---", { 1, 0 })
        
        tooltipType: UpgradeType
        climbUpgradeTooltip: bool
        
        if game.Upgrades[.FUEL] < len(UpgradeProps[.FUEL]) - 1 {
          prop := UpgradeProps[.FUEL][game.Upgrades[.FUEL] + 1]
          canAfford := game.MoneyTotal >= prop.Price
          uiCtx.Disabled = !canAfford
          signal := UiAddButton(uiCtx, fmt.tprintf("Fuel tank {}l ({}$)", prop.Value, prop.Price), { 1, 0 })
          uiCtx.Disabled = false
          
          if signal.Clicked {
            if canAfford {
              DeltaMoney(game, -prop.Price)
              game.Upgrades[.FUEL] += 1
            }
          }
          if signal.Hovered do tooltipType = .FUEL
        }
        else do UiAddText(uiCtx, "- Sold out -", { 1, 0 })
        
        if game.Upgrades[.DRILL] < len(UpgradeProps[.DRILL]) - 1 {
          prop := UpgradeProps[.DRILL][game.Upgrades[.DRILL] + 1]
          canAfford := game.MoneyTotal >= prop.Price
          uiCtx.Disabled = !canAfford
          signal := UiAddButton(uiCtx, fmt.tprintf("Drill strength+ ({}$)", prop.Price), { 1, 0 })
          uiCtx.Disabled = false
          
          if signal.Clicked {
            if canAfford {
              DeltaMoney(game, -prop.Price)
              game.Upgrades[.DRILL] += 1
            }
          }
          if signal.Hovered do tooltipType = .DRILL
        }
        else do UiAddText(uiCtx, "- Sold out -", { 1, 0 })
        
        if game.Upgrades[.SPEED] < len(UpgradeProps[.SPEED]) - 1 {
          prop := UpgradeProps[.SPEED][game.Upgrades[.SPEED] + 1]
          canAfford := game.MoneyTotal >= prop.Price
          uiCtx.Disabled = !canAfford
          signal := UiAddButton(uiCtx, fmt.tprintf("Drive speed+ ({}$)", prop.Price), { 1, 0 })
          uiCtx.Disabled = false
          
          if signal.Clicked {
            if canAfford {
              DeltaMoney(game, -prop.Price)
              game.Upgrades[.SPEED] += 1
            }
          }
          if signal.Hovered do tooltipType = .SPEED
        }
        else do UiAddText(uiCtx, "- Sold out -", { 1, 0 })
        
        if game.Upgrades[.CARGO] < len(UpgradeProps[.CARGO]) - 1 {
          prop := UpgradeProps[.CARGO][game.Upgrades[.CARGO] + 1]
          canAfford := game.MoneyTotal >= prop.Price
          uiCtx.Disabled = !canAfford
          signal := UiAddButton(uiCtx, fmt.tprintf("Cargo size {}l ({}$)", prop.Value, prop.Price), { 1, 0 })
          uiCtx.Disabled = false
          
          if signal.Clicked {
            if canAfford {
              DeltaMoney(game, -prop.Price)
              game.Upgrades[.CARGO] += 1
            }
          }
          if signal.Hovered do tooltipType = .CARGO
        }
        else do UiAddText(uiCtx, "- Sold out -", { 1, 0 })
        
        if game.Upgrades[.HULL] < len(UpgradeProps[.HULL]) - 1 {
          prop := UpgradeProps[.HULL][game.Upgrades[.HULL] + 1]
          canAfford := game.MoneyTotal >= prop.Price
          uiCtx.Disabled = !canAfford
          signal := UiAddButton(uiCtx, fmt.tprintf("Hull strength {} ({}$)", prop.Value, prop.Price), { 1, 0 })
          uiCtx.Disabled = false
          
          if signal.Clicked {
            if canAfford {
              DeltaMoney(game, -prop.Price)
              game.Upgrades[.HULL] += 1
            }
          }
          if signal.Hovered do tooltipType = .HULL
        }
        else do UiAddText(uiCtx, "- Sold out -", { 1, 0 })
        
        if !game.CanClimbHorizontal {
          canAfford := game.MoneyTotal >= HORIZONTAL_CLIMB_PRICE
          uiCtx.Disabled = !canAfford
          signal := UiAddButton(uiCtx, fmt.tprintf("Sideways climbing ({}$)", HORIZONTAL_CLIMB_PRICE), { 1, 0 })
          uiCtx.Disabled = false
          
          if signal.Clicked {
            if canAfford {
              DeltaMoney(game, -HORIZONTAL_CLIMB_PRICE)
              game.CanClimbHorizontal = true
            }
          }
          climbUpgradeTooltip = signal.Hovered
        }
        
        if tooltipType != .NONE || climbUpgradeTooltip {
          UiAddText(uiCtx, "-----------------", { 1, 0 })
          
          tip: string
          switch tooltipType {
            case .FUEL: tip = 
              "Drilling and climbing\n"+
              "consumes fuel. Mine\n"+
              "for longer without\n"+
              "the need to refuel.\n"+
              "(Fuel not included\n"+
              "in upgrade)"
            case .DRILL: tip =
              "Speed up your mining\n"+
              "and drill through harder\n"+
              "materials, like rock\n"
            case .SPEED: tip =
              "Get from A to B faster.\n"+
              "Increases drive speed but\n"+
              "does not affect drill speed\n"+
              "or fuel consumption"
            case .CARGO: tip = 
              "More storage means less\n"+
              "trips to the surface\n"
            case .HULL: tip = 
              "Reduce the damage from\n"+
              "breaking through hard\n"+
              "material, like rock"
            case .NONE:
          }
          
          if climbUpgradeTooltip {
            tip = 
              "Allows sideways movement\n"+
              "while driving on walls.\n"+
              "Makes getting back to\n"+
              "the surface much easier\n"
          }
          
          UiAddText(uiCtx, tip, { 1, 0 })
        }
      }
      
      if game.DrillCoord == game.ShopCoordMech {
        UiAddText(uiCtx, "--- Mechanic ---", { 1, 0 })
        
        {
          maxFuel := UpgradeProps[.FUEL][game.Upgrades[.FUEL]].Value
          maxAfford := game.MoneyTotal * FUEL_UNIT_PER_DOLLAR
          amount := math.min(maxAfford, (maxFuel - game.Fuel))
          isMax := amount == (maxFuel - game.Fuel)
          price := math.min(maxAfford / FUEL_UNIT_PER_DOLLAR, (maxFuel - game.Fuel) / FUEL_UNIT_PER_DOLLAR)
          text := isMax ? fmt.tprintf("Refuel (max) ({}$)", price) : fmt.tprintf("Refuel ({}l) ({}$)", amount, price)
          if UiAddButton(uiCtx, text, { 1, 0 }).Clicked {
            if game.Fuel != maxFuel {
              DeltaMoney(game, -price)
              DeltaFuel(game, amount)
            }
          }
        }
        
        {
          maxHull := UpgradeProps[.HULL][game.Upgrades[.HULL]].Value
          maxAfford := game.MoneyTotal * REPAIR_UNIT_PER_DOLLAR
          amount := math.min(maxAfford, (maxHull - game.Hull))
          isMax := amount == (maxHull - game.Hull)
          price := math.min(maxAfford / REPAIR_UNIT_PER_DOLLAR, (maxHull - game.Hull) / REPAIR_UNIT_PER_DOLLAR)
          text := isMax ? fmt.tprintf("Repair (max) ({}$)", price) : fmt.tprintf("Repair ({}) ({}$)", amount, price)
          if UiAddButton(uiCtx, text, { 1, 0 }).Clicked {
            if game.Hull != maxHull {
              DeltaMoney(game, -price)
              DeltaHull(game, amount)
            }
          }
        }
      }
      
      if game.DrillCoord == game.ShopCoordSell {
        UiAddText(uiCtx, "--- Market ---", { 1, 0 })
        
        total: i32
        for type in VoxelType do total += game.Cargo[type] * VoxelProps[type].Worth
        
        if total > 0 {
          for type in VoxelType {
            if game.Cargo[type] > 0 {
               UiAddText(uiCtx, fmt.tprintf("{} {}x{}$ -> {}$", VoxelProps[type].Name, game.Cargo[type], VoxelProps[type].Worth, game.Cargo[type] * VoxelProps[type].Worth), { 1, 0 })
            }
          }
          
          UiPushColor(uiCtx, .TEXT, COL_GOLD)
          if UiAddButton(uiCtx, fmt.tprintf("Sell: {}$", total), { 1, 0 }).Clicked {
            game.Cargo = {}
            DeltaMoney(game, total)
          }
          UiPopColor(uiCtx)
        }
        else {
          UiPushColor(uiCtx, .TEXT, COL_WARNING)
          UiAddText(uiCtx, "Nothing to sell", { 1, 0 })
          UiPopColor(uiCtx)
        }
      
      }
      
      uiCtx.Cursor = { 10, windowSize.y - WINDOW_PADDING }
      UiAddText(uiCtx, fmt.tprintf("Depth: {}", game.DrillCoord.y - 1), { 0, 1 })
      
      if game.FreeCam {
        uiCtx.Cursor = { (windowSize.x - WINDOW_PADDING * 2) * 0.5, windowSize.y - WINDOW_PADDING }
        if UiAddButton(uiCtx, "Reset cam", { 0.5, 1 }).Clicked {
          game.FreeCam = false
        }
      }
      
      NormalizedScreenSpaceFromWorldSpace :: proc(camera: Camera3d, worldPos: [3]f32) -> [2]f32 {
        viewMatrix := linalg.inverse(Camera3dGetViewMatrix(camera))
        projMatrix := matrix_persp_right_handed_zero_to_one(camera.FieldOfView, camera.AspectRatio, camera.Near, camera.Far)
        viewProj := (projMatrix * viewMatrix)
      
        clipSpace := viewProj * [4]f32{ worldPos.x, worldPos.y, worldPos.z, 1 }
        clipSpace /= clipSpace.w
        clipSpace.y *= -1
        
        return (clipSpace.xy + 1) * 0.5
      }
      
      HEIGHT_MARKER_DISTANCE : i32 = 50
      for i in 1..= CHUNK_HEIGHT / HEIGHT_MARKER_DISTANCE {
        heightMarker := [3]f32{ f32(CHUNK_SIZE) / 2, -f32(i * HEIGHT_MARKER_DISTANCE), f32(CHUNK_SIZE) / 2 }
        heightMarkerNormScreen := NormalizedScreenSpaceFromWorldSpace(game.Camera, heightMarker)
        
        if heightMarkerNormScreen.y >= 0 && heightMarkerNormScreen.y <= 1 {
          heightMarkerAbsoluteScreen := heightMarkerNormScreen * windowSize
          
          uiCtx.Cursor = { windowSize.x - WINDOW_PADDING, heightMarkerAbsoluteScreen.y }
          UiAddText(uiCtx, fmt.tprintf("%vm", i * HEIGHT_MARKER_DISTANCE), { 1, 0 })
        }
      }
      
      drillWorldPos := [3]f32{ f32(game.DrillCoord.x), f32(game.DrillCoord.y), f32(game.DrillCoord.z) }
      drillAbsoluteScreenPos := NormalizedScreenSpaceFromWorldSpace(game.Camera, drillWorldPos) * windowSize
      offset: f32
      for effect in arr.slice(&game.UiEffects) {
        switch e in effect {
          case UiEffectValueChange: {
            switch e.Type {
              case .FUEL: {
                text := fmt.aprintf("%+v", e.Value, allocator = mem.buddy_allocator(&game.ParticleAllocator))
                arr.push_back(&game.TextParticles, TextParticle {
                  Col = { 1, 1, 1, 1 },
                  Pos = { 0.1 * windowSize.x,  e.Value < 0 ? 10 : 10 + f32(FONT_ATLAS_LINE_HEIGHT) },
                  Velocity = { 0, e.Value < 0 ? 60 : -60, },
                  TimeToLiveS = 1,
                })
                arr.slice(&game.TextParticles)[game.TextParticles.len - 1].Text = text
              }
              case .HULL: {
                text := fmt.aprintf("%+v", e.Value, allocator = mem.buddy_allocator(&game.ParticleAllocator))
                arr.push_back(&game.TextParticles, TextParticle {
                  Col = { 1, 1, 1, 1 },
                  Pos = { 0.1 * windowSize.x,  e.Value < 0 ? 10 : 10 + f32(FONT_ATLAS_LINE_HEIGHT) * 2 },
                  Velocity = { 0, e.Value < 0 ? 60 : -60, },
                  TimeToLiveS = 1,
                })
                arr.slice(&game.TextParticles)[game.TextParticles.len - 1].Text = text
              }
              case .MONEY: {
                text := fmt.aprintf("%+v$", e.Value, allocator = mem.buddy_allocator(&game.ParticleAllocator))
                arr.push_back(&game.TextParticles, TextParticle {
                  Col = COL_GOLD,
                  Pos = { 0.95 * windowSize.x,  e.Value < 0 ? 10 : 10 + f32(FONT_ATLAS_LINE_HEIGHT) },
                  Velocity = { 0, e.Value < 0 ? 60 : -60, },
                  TimeToLiveS = 1,
                })
                arr.slice(&game.TextParticles)[game.TextParticles.len - 1].Text = text
              }
              case .CARGO: {                               
                text := fmt.aprintf("%+v %v", e.Value, VoxelProps[e.VoxelType].Name, allocator = mem.buddy_allocator(&game.ParticleAllocator))
                arr.push_back(&game.TextParticles, TextParticle {
                  Col = { 1, 1, 1, 1 },
                  Pos = drillAbsoluteScreenPos + { 0, offset },
                  Velocity = { 0, e.Value < 0 ? 60 : -60, },
                  TimeToLiveS = 1,
                })
                //When we lose multiple cargos at the same time we want
                //the values to show up below each other, not all overlapping
                offset += f32(FONT_ATLAS_LINE_HEIGHT)
                arr.slice(&game.TextParticles)[game.TextParticles.len - 1].Text = text
              }
            }
          
          }
          case UiEffectDisclaimer: {
            
            switch e {
              case .NO_FUEL: {
                SpawnTextParticle(game, "No Fuel!", {
                  Col = COL_CRITICAL,
                  Pos = drillAbsoluteScreenPos,
                  Velocity = { 0, 60, },
                  TimeToLiveS = 1,
                })
              }
              case .LOW_FUEL: {
                SpawnTextParticle(game, "Low Fuel!", {
                  Col = COL_WARNING,
                  Pos = drillAbsoluteScreenPos,
                  Velocity = { 0, 40, },
                  TimeToLiveS = 3,
                })
              }
              case .CARGO_FULL: {
                SpawnTextParticle(game, "Cargo full!", {
                  Col = COL_WARNING,
                  Pos = drillAbsoluteScreenPos,
                  Velocity = { 0, 40, },
                  TimeToLiveS = 3,
                })
              }
            }
          
          }
        }
      }
      arr.clear(&game.UiEffects)
      
      //Add text particle to UI
      for &particle in arr.slice(&game.TextParticles) {
        arr.push_back(&uiCtx.Texts, UiText{ strings.clone(particle.Text, virtual.arena_allocator(&frameArena)), particle.Pos, particle.Col })
      }
      
      if game.ShowMenu {
        uiCtx.Cursor = { windowSize.x * 0.5, windowSize.y * 0.5 - f32(FONT_ATLAS_LINE_HEIGHT * 4) }
        UiPushColor(uiCtx, .TEXT, COL_WARNING)
        UiAddText(uiCtx, "Menu", { 0.5, 0 })
        UiAddText(uiCtx, "-------------", { 0.5, 0 })
        UiPopColor(uiCtx)
        
        if UiAddButton(uiCtx, "Resume", { 0.5, 0 }).Clicked {
          game.ShowMenu = false
        }
        
        UiPushColor(uiCtx, .TEXT, COL_WARNING)
        if UiAddButton(uiCtx, "Rescue (lose all cargo)", { 0.5, 0 }).Clicked {
          Rescue(game)
          game.ShowMenu = false
        }
        
        if UiAddButton(uiCtx, "Start new game", { 0.5, 0 }).Clicked {
          game.ShowConfirmationPrompt = true
          game.ShowMenu = false
        }
        UiPopColor(uiCtx)
        
        if UiAddButton(uiCtx, "Exit to Desktop", { 0.5, 0 }).Clicked {
          shouldExit = true
        }
      }
      else if game.ShowConfirmationPrompt {
        uiCtx.Cursor = { windowSize.x * 0.5, windowSize.y * 0.5 - f32(FONT_ATLAS_LINE_HEIGHT * 3) }
        UiPushColor(uiCtx, .TEXT, COL_WARNING)
        UiAddText(uiCtx, "A new world will be generated", { 0.5, 0 })
        UiAddText(uiCtx, "All progress will be lost", { 0.5, 0 })
        UiAddText(uiCtx, "Are you sure?", { 0.5, 0 })
        UiPopColor(uiCtx)
        if UiAddButton(uiCtx, "Yes", { 0.5, 0 }).Clicked {
          ResetGame(game)
          game.ForceUpdateAllVoxels = true
          game.ShowConfirmationPrompt = false
        }
        
        if UiAddButton(uiCtx, "No", { 0.5, 0 }).Clicked {
          game.ShowConfirmationPrompt = false
          game.ShowMenu = true
        }
      }
    }

    for ev in events {
      if e, ok := ev.(Platform.EventMouseWheel); ok {
        game.FreeCam = true
        game.FreeCamTransition = 1
      }
      
      if e, ok := ev.(Platform.EventKeyDown); ok && e.Key == .ESC {
        game.ShowMenu = !game.ShowMenu
      }
      
      if e, ok := ev.(Platform.EventClose); ok {
        shouldExit = true
      }
    
      OrbitControllerOnEvent(&game.CamController, ev)
    }
  
    OrbitControllerOnUpdate(&game.CamController, f32(time.Delta))
        
    for &particle in arr.slice(&game.TextParticles) {
      using particle
      Pos += Velocity * f32(time.Delta)
      TimeToLiveS -= f32(time.Delta)
    }
    
    #reverse for &particle, i in arr.slice(&game.TextParticles) {
      using particle
      if TimeToLiveS <= 0 {
        mem.buddy_allocator_free(&game.ParticleAllocator, raw_data(Text))
        arr.ordered_remove(&game.TextParticles, i)
      }
    }
        
    IsSolid :: proc(type : VoxelType) -> bool { return type != .BOUNDS && type != .NONE && type < .BOUNDS }
    
    drillCoord := game.DrillCoord + game.DrillDir
    isDrilling: bool
    if Platform.WindowIsFocused(window) {
      if game.MoveCooldown > 0 do game.MoveCooldown -= f32(time.Delta)
      
      isDrilling = !uiCtx.Hovered && (Platform.IsKeyPressed(.SHIFT) || Platform.IsMouseButtonDown(.LEFT)) && game.Fuel > 0
      if isDrilling do game.DrillRotation += f32(time.Delta) * 5
      
      if isDrilling {
        if IsSolid(GetVoxel(game, drillCoord).Type) {
          audio.Active = .DRILL_SOLID
        }
        else {
          audio.Active = .DRILL_AIR
        }
        ma.device_start(&audioDevice)
      }
      else do ma.device_stop(&audioDevice)
      
      if isDrilling && IsSolid(GetVoxel(game, drillCoord).Type) && VoxelProps[GetVoxel(game, drillCoord).Type].Strength <= UpgradeProps[.DRILL][game.Upgrades[.DRILL]].Value {
        drillVoxel := GetVoxel(game, game.DrillCoord + game.DrillDir)
        if arr.space(game.Particles) > NUM_BLOCK_PARTICLES {
          vel := ([3]f32{ rand.float32(), rand.float32(), rand.float32() } - 0.5) * 8 - linalg.to_f32(game.DrillDir)
          pos := linalg.to_f32(game.DrillCoord) + linalg.to_f32(game.DrillDir) * 0.45
          arr.push_back(&game.Particles, Particle{ Pos = pos, Vel = vel, TimeToLiveS = rand.float32() * 2, Type = drillVoxel.Type, Size = 0.1 })
        }
      
        game.DrillDuration += f32(time.Delta)
        timeToDamageSeconds := f32(UpgradeProps[.DRILL][game.Upgrades[.DRILL]].Value) / 1000
        if game.DrillDuration > timeToDamageSeconds {
          game.DrillDuration -= timeToDamageSeconds
        
          totalCargo: i32
          for type in VoxelType do totalCargo += i32(game.Cargo[type])
            
          if drillVoxel.Health > 0 {
            drillVoxel.Health -= 1
            arr.push(&game.UpdateVoxels, drillCoord)
            DeltaFuel(game, -1)
            
            cargoFull := totalCargo >= UpgradeProps[.CARGO][game.Upgrades[.CARGO]].Value
            if cargoFull && VoxelProps[drillVoxel.Type].Worth > 0 {
              arr.push_back(&game.UiEffects, UiEffectDisclaimer.CARGO_FULL)
            }
          }
          
          isIndestructible := VoxelProps[drillVoxel.Type].Health == 0
          if drillVoxel.Health == 0 && !isIndestructible {
            if game.StorageVoxel == .NONE && VoxelProps[drillVoxel.Type].Worth == 0 {
              game.StorageVoxel = drillVoxel.Type
            }
            
            if VoxelProps[drillVoxel.Type].Worth > 0 {
              if totalCargo < UpgradeProps[.CARGO][game.Upgrades[.CARGO]].Value {
                game.Player.Cargo[drillVoxel.Type] += 1
                
                arr.push_back(&game.UiEffects, UiEffectValueChange { .CARGO, 1, drillVoxel.Type })
              }
            }
            
            if VoxelProps[drillVoxel.Type].Strength > 0 {
              DeltaHull(game, -VoxelProps[drillVoxel.Type].Strength)
            }
            
            for i := 0; arr.space(game.Particles) > 0 && i < NUM_BLOCK_PARTICLES; i += 1 {
              vel := ([3]f32{ rand.float32(), rand.float32(), rand.float32() } - 0.5) * 15
              pos := linalg.to_f32(game.DrillCoord + game.DrillDir)
              arr.push_back(&game.Particles, Particle{ Pos = pos, Vel = vel, TimeToLiveS = rand.float32() * 5, Type = drillVoxel.Type, Size = 0.25 })
            }
            
            drillVoxel.Type = .NONE
          }
        }
      }
      else do game.DrillDuration = 0
      
      for ev in events {
        #partial switch e in ev {
          case Platform.EventKeyDown:
            if e.Key == .F {
              if game.StorageVoxel != .NONE && (game.DrillCoord - game.DrillDir).y <= 0 && GetVoxel(game, game.DrillCoord - game.DrillDir).Type == .NONE {
                voxel := GetVoxel(game, game.DrillCoord - game.DrillDir)
                voxel.Type = game.StorageVoxel
                voxel.Health = 1
                game.StorageVoxel = .NONE
                
                arr.push(&game.UpdateVoxels, game.DrillCoord - game.DrillDir)
              }
            }
          }
        }
      
      MoveAction :: enum {
        NONE,
        LEFT,
        RIGHT,
        UP,
        DOWN,
      }
      
      moveAction: MoveAction
      switch {
        case Platform.IsKeyPressed(.W) || Platform.IsKeyPressed(.ARROW_UP   ): moveAction = .UP
        case Platform.IsKeyPressed(.A) || Platform.IsKeyPressed(.ARROW_LEFT ): moveAction = .LEFT
        case Platform.IsKeyPressed(.S) || Platform.IsKeyPressed(.ARROW_DOWN ): moveAction = .DOWN
        case Platform.IsKeyPressed(.D) || Platform.IsKeyPressed(.ARROW_RIGHT): moveAction = .RIGHT
        
        case Platform.IsKeyPressed(.E) || Platform.IsKeyPressed(.ARROW_RIGHT): moveAction = .UP
        case Platform.IsKeyPressed(.C) || Platform.IsKeyPressed(.ARROW_RIGHT): moveAction = .DOWN
      }
      
      if moveAction != .NONE && game.MoveCooldown <= 0 && game.Hull != 0 {
        //Make movement directions dependent on the camera
        x := linalg.dot(game.Camera.Forward, [3]f32{ 1, 0, 0 })
        z := linalg.dot(game.Camera.Forward, [3]f32{ 0, 0, 1 })
        
        forward : [3]i32
        if math.abs(x) > math.abs(z) do forward = { x > 0 ? -1 : 1, 0, 0 }
        else do forward = { 0, 0,  z > 0 ? -1 : 1 }
        
        right := [3]i32 { forward.z, 0,  -forward.x }
        
        moveCooldownSec := f32(UpgradeProps[.SPEED][game.Upgrades[.SPEED]].Value) / 1000
        game.MoveCooldown += moveCooldownSec
        game.FreeCam = false
      
        nextCoord := game.DrillCoord
        if moveAction == .UP    do nextCoord = game.DrillCoord - forward
        if moveAction == .DOWN  do nextCoord = game.DrillCoord + forward 
        if moveAction == .LEFT  do nextCoord = game.DrillCoord - right  
        if moveAction == .RIGHT do nextCoord = game.DrillCoord + right            
        
        nextVoxel := GetVoxel(game, nextCoord)
        confirmCoord := game.DrillCoord   
        confirmDrillDir := game.DrillDir
        confirmWheelDir := game.WheelDir
        confirmDriveDir := game.DriveDir

        nextCoordDir := nextCoord - game.DrillCoord
        if game.DrillDir == nextCoordDir && nextVoxel.Type != .BOUNDS && game.CanDrive {
          canSteer := game.CanSteer || nextCoordDir.x != 0
          
          if !IsSolid(GetVoxel(game, nextCoord).Type) && IsSolid(GetVoxel(game, nextCoord + game.WheelDir).Type) && canSteer{
            if game.WheelDir.y != 0 || (game.CanClimb && game.DrillDir.y != 0) || (game.CanClimbHorizontal) {
               confirmCoord = nextCoord
            }
          }
          if game.CanClimb && !isDrilling {
            //Climb down over ledge
            if !IsSolid(GetVoxel(game, nextCoord).Type) && !IsSolid(GetVoxel(game, nextCoord + game.WheelDir).Type) && (game.WheelDir.y != 0) {
              confirmCoord = nextCoord + game.WheelDir;
              confirmDrillDir = game.WheelDir
              confirmWheelDir = (game.DrillCoord + game.WheelDir) - confirmCoord
              confirmDriveDir = game.DriveDir == nextCoordDir ? game.WheelDir : -game.WheelDir
              log.debug("Climb down over ledge");
            }
            
            //Climb onto wall
            if IsSolid(GetVoxel(game, nextCoord).Type) && (game.WheelDir.y != 0 || game.CanClimbHorizontal) {
              confirmDrillDir = -game.WheelDir
              confirmWheelDir = (nextCoord - game.DrillCoord)
              confirmDriveDir = game.DriveDir == nextCoordDir ? -game.WheelDir : game.WheelDir
              log.debug("Climb onto wall");
            }
          }
        }
        else if nextCoordDir == game.WheelDir && nextCoordDir.y == 0 {
          //Player is moving 'inside' the wall so interpret that as climbing
          if game.DrillDir != { 0, 1, 0 } {
            confirmDrillDir = { 0, 1, 0 }
            
            //Only change drive dir if it is currently neither up nor down.
            //It wouldn't 'feel' right to rotate the wheels when they can just drive backwards
            if game.DriveDir.y == 0 {
              confirmDriveDir = { 0, 1, 0 }
            }
          }
          else {
            //Climb up over ledge
            if !IsSolid(GetVoxel(game, game.DrillCoord + game.WheelDir + game.DrillDir).Type) && !IsSolid(GetVoxel(game, nextCoord + game.DrillDir).Type) {
              confirmCoord = game.DrillCoord + game.WheelDir + game.DrillDir
              confirmWheelDir = -game.DrillDir
              confirmDrillDir = nextCoordDir
              confirmDriveDir = game.DriveDir.y > 0 ? game.WheelDir : -game.WheelDir
              log.debug("Climb up over ledge");
            }
            
            //Climb up wall
            if !IsSolid(GetVoxel(game, game.DrillCoord + game.DrillDir).Type) && IsSolid(GetVoxel(game, game.DrillCoord + game.DrillDir + game.WheelDir).Type) {
              confirmCoord = game.DrillCoord  + game.DrillDir
              confirmDriveDir = game.DriveDir.y > 0 ? game.WheelDir : -game.WheelDir
              log.debug("Climb up wall");
            }
          }
        }
        else if nextCoordDir == -game.WheelDir && nextCoordDir.y == 0 {
          //Player is moving 'away' from wall so interpet that as descending
          if game.DrillDir != { 0, -1, 0 } {
            confirmDrillDir = { 0, -1, 0 }
            
            //Only change drive dir if it is currently neither up nor down.
            //It wouldn't 'feel' right to rotate the wheels when they can just drive backwards
            if game.DriveDir.y == 0 {
              confirmDriveDir = { 0, -1, 0 }
            }
          }
          else {
            //Step down from wall
            if !isDrilling && IsSolid(GetVoxel(game, game.DrillCoord + game.DrillDir).Type) {
              confirmWheelDir = game.DrillDir
              confirmDrillDir = nextCoordDir
              confirmDriveDir = game.DriveDir.y > 0 ? game.WheelDir : -game.WheelDir
              log.debug("Step down from wall");
            }
            else if !IsSolid(GetVoxel(game, game.DrillCoord + game.DrillDir).Type) && IsSolid(GetVoxel(game, game.DrillCoord + game.DrillDir + game.WheelDir).Type) {
              //Descend wall
              confirmCoord = game.DrillCoord  + game.DrillDir
              log.debug("Descend wall");
            }
          }
        }
        else {
          confirmDrillDir = nextCoordDir
        
          isOnFloor := game.WheelDir.y != 0
          if (isOnFloor || game.CanClimbHorizontal) && linalg.abs(game.DrillDir) != linalg.abs(nextCoordDir) {
            //Only change drive dir if it is currently neither up nor down.
            //It wouldn't 'feel' right to rotate the wheels when they can just drive backwards
            confirmDriveDir = nextCoordDir
          }
        }
        
        hasMoved := (game.DrillCoord != confirmCoord || game.WheelDir != confirmWheelDir)
        if hasMoved {
          confirmHasFloor := GetVoxel(game, confirmCoord - { 0, 1, 0 }).Type != .NONE
          if !confirmHasFloor && confirmCoord.y > game.DrillCoord.y {
            if game.Fuel > 0 {
              DeltaFuel(game, -1)
              game.PrevDrillCoord = game.DrillCoord
              game.DrillCoord = confirmCoord
              game.PosInterpolationT = 0
            }
            else {
              effect: UiEffect = .NO_FUEL
              arr.push_back(&game.UiEffects, effect)
            }
          }
          else {
            game.PrevDrillCoord = game.DrillCoord
            game.DrillCoord = confirmCoord
            game.PosInterpolationT = 0
          }
        }
        
        hasRotated := game.WheelDir != confirmWheelDir || game.DrillDir != confirmDrillDir
        if hasRotated {
          game.PrevWheelDir = game.WheelDir
          game.WheelDir = confirmWheelDir
          
          game.PrevDrillDir = game.DrillDir
          game.DrillDir = confirmDrillDir
          
          game.PrevDriveDir = game.DriveDir
          game.DriveDir = confirmDriveDir
          
          game.RotInterpolationT = 0
        }
      }
      
      game.MaxDepthReached = math.min(game.MaxDepthReached, game.DrillCoord.y)
    }
    
    //The particle is relatively simple. It's just points in space with a position and a velocity that get moved by said velocity
    //every frame.
    //The more complicated part is collision detection with the voxel world but that's pretty straightforward as well.
    for &particle in arr.slice(&game.Particles) {
      GRAVITY :: [3]f32{ 0, -9.81, 0 }
      
      posOld := particle.Pos
      particle.Vel += f32(time.Delta) * GRAVITY
      particle.Pos += f32(time.Delta) * particle.Vel
      posNew := particle.Pos

      posOld += { 0.5, -0.5, 0.5 }
      posNew += { 0.5, -0.5, 0.5 }
      
      isInVoxelBounds := (
        posNew.x >= 0 && posNew.x < f32(CHUNK_SIZE) &&
        posNew.y <= 0 && posNew.y > f32(-CHUNK_HEIGHT) &&
        posNew.z >= 0 && posNew.z < f32(CHUNK_SIZE)
      )
      
      DAMPING : f32 : 0.75
      if isInVoxelBounds {
        coordOld := [3]i32{ i32(math.floor(posOld.x)), i32(math.ceil(posOld.y)), i32(math.floor(posOld.z)) }
        coordNew := [3]i32{ i32(math.floor(posNew.x)), i32(math.ceil(posNew.y)), i32(math.floor(posNew.z)) }
        
        isColliding := IsSolid(GetVoxel(game, coordNew).Type) && !IsSolid(GetVoxel(game, coordOld).Type)
        if isColliding {
          coordOldF := linalg.to_f32(coordOld)
          coordNewF := linalg.to_f32(coordNew)
          
          //Offset our coordinates so the collision point lies on one of 
          //the coordinate origin planes. This simplifies the following calculations
          offset := -coordOldF - { 0.5, -0.5, 0.5 } + (coordOldF - coordNewF) * 0.5
          posOld += offset
          posNew += offset
          
          //The following is just your usual lerp function (e.g. linalg.lerp()) but solved for t.
          //We want to know the t that gives us a value of zero on one of the axis. That is the point of collision
          tVec := (0 - posOld) / (posNew - posOld)
          t: f32
          collisionNormal: [3]f32
          if tVec.x >= 0 && tVec.x <= 1 { t = tVec.x; collisionNormal.x = 1 }
          if tVec.y >= 0 && tVec.y <= 1 { t = tVec.y; collisionNormal.y = 1 }
          if tVec.z >= 0 && tVec.z <= 1 { t = tVec.z; collisionNormal.z = 1 }
          
          collisionNormal = linalg.normalize(collisionNormal * linalg.sign(posOld - posNew))
          collisionPos := linalg.lerp(posOld - offset, posNew - offset, t) - { 0.5, -0.5, 0.5 }
          
          particle.Pos = collisionPos
          particle.Vel = linalg.reflect(particle.Vel, collisionNormal) * DAMPING
        }
      }
    }
    
    //Reverse loop because we will remove particles during the loop
    #reverse for &particle, i in arr.slice(&game.Particles) {
      particle.TimeToLiveS -= f32(time.Delta)
      if particle.TimeToLiveS <= 0 {
        //Order of particles does not matter so we can do an efficient swap and pop to remove dead ones
        slice.swap(arr.slice(&game.Particles), i, arr.len(game.Particles) - 1)
        arr.pop_back(&game.Particles)      
      }
    }
    
    //When the window gets continuously resized for a longer period of time, resize events accumulate.
    //It doesn't make much sense to react to all of them since the program is stalling during the resize anyways.
    //By doing a reverse loop and breaking at the first resize event we only react to the last one.
    #reverse for eBase in events {
      if e, ok := eBase.(Platform.EventResize); ok && e.Size.x > 0 && e.Size.y > 0 {
        gpuRes.RenderTargetView->Release()
        gpuRes.DepthStencilView->Release()
        gpuRes.DepthBuffer->Release()
        gpuRes.RenderTarget->Release()

        gpu.Swapchain->ResizeBuffers(0, 0, 0, .UNKNOWN, {})       

        gpu.Swapchain->GetBuffer(0, d3d.ITexture2D_UUID, (^rawptr)(&gpuRes.RenderTarget))
        gpu.Device->CreateRenderTargetView(gpuRes.RenderTarget, nil, &gpuRes.RenderTargetView)
        
        {
          colorbufferdesc : d3d.TEXTURE2D_DESC
          gpuRes.RenderTarget->GetDesc(&colorbufferdesc);
          colorbufferdesc.SampleDesc.Count = MSAA_SAMPLES
        
          gpu.Device->CreateTexture2D(&colorbufferdesc, nil, &gpuRes.ColorBufferMS)
          gpu.Device->CreateRenderTargetView(gpuRes.ColorBufferMS, nil, &gpuRes.RenderTargetMSView)
        }
  
        {
          depthbufferdesc : d3d.TEXTURE2D_DESC
          gpuRes.RenderTarget->GetDesc(&depthbufferdesc)
          depthbufferdesc.Format = dxgi.FORMAT.D32_FLOAT
          depthbufferdesc.BindFlags = { .DEPTH_STENCIL }
          depthbufferdesc.SampleDesc.Count = MSAA_SAMPLES
  
          gpu.Device->CreateTexture2D(&depthbufferdesc, nil, &gpuRes.DepthBuffer)
          gpu.Device->CreateDepthStencilView(gpuRes.DepthBuffer, nil, &gpuRes.DepthStencilView)
        }
        
        break;
      }
    }
    

    //Create vertex data from UI and upload to GPU
    numVerticesGameUi : u32
    {
      temp := Scratch.Begin()
      defer Scratch.End(temp)
      context.allocator = virtual.arena_allocator(temp.arena)
      
      Rect :: struct {
        x, y, w, h : f32,
      }
      
      ColRect :: struct {
        Rect : Rect,
        Tex  : [4]Vec2,
        Color : Vec4,
      }
      
      RectToVertices :: proc(colRect : ColRect) -> [6]Vertex2D {
        using colRect
        UPPER_L : Vec2 = { f32(Rect.x), f32(Rect.y) }
        UPPER_R : Vec2 = { f32(Rect.x + Rect.w), f32(Rect.y) }
        LOWER_L : Vec2 = { f32(Rect.x), f32(Rect.y + Rect.h) }
        LOWER_R : Vec2 = { f32(Rect.x + Rect.w), f32(Rect.y + Rect.h) }
  
        return {
          { UPPER_L, Tex[0], Color },
          { UPPER_R, Tex[1], Color },
          { LOWER_R, Tex[2], Color },
          { LOWER_R, Tex[2], Color },
          { LOWER_L, Tex[3], Color },
          { UPPER_L, Tex[0], Color },
        }
      }
      
      UiRect :: struct { x, y, w, h: i32 }
      RectToTexCorners :: proc(rect : UiRect) -> [4]Vec2 {
        x := f32(rect.x) / f32(FONT_ATLAS_WIDTH)
        y := f32(rect.y) / f32(FONT_ATLAS_HEIGHT)
        w := f32(rect.w) / f32(FONT_ATLAS_WIDTH)
        h := f32(rect.h) / f32(FONT_ATLAS_HEIGHT)
        return {
          { x, y },
          { x + w, y },
          { x + w, y + h },
          { x, y + h },
        }
      }
    
      estimateNumRects: i32 //Will include e.g. line breaks
      for uiText in arr.slice(&uiCtx.Texts) {
        estimateNumRects += i32(len(uiText.Text))
      }
      
      rects : [dynamic]ColRect
      reserve(&rects, estimateNumRects)
      for uiText in arr.slice(&uiCtx.Texts) {
        offset : [2]f32
        for c in uiText.Text {
          if c == '\n' {
            offset.x = 0
            offset.y += f32(FONT_ATLAS_LINE_HEIGHT)
            continue
          }
        
          info := FONT_ATLAS_INFO[c - 32]
        
          rect := ColRect {
            Rect = { 
              x = uiText.Pos.x + offset.x,
              y = uiText.Pos.y + offset.y + f32(info.OffsetY),
              w = f32(info.Width),
              h = f32(info.Height),
            },
            
            Tex = RectToTexCorners({
              x = info.X,
              y = info.Y,
              w = info.Width,
              h = info.Height,
            }),
            
            Color = uiText.Col
          }
          
          append(&rects, rect)
          offset += { f32(info.AdvanceX), 0 }
        }
      }

      //Resize GPU vertex buffer if necessary      
      vertexbufferdesc : d3d.BUFFER_DESC
      gpuRes.VBufferGameUi->GetDesc(&vertexbufferdesc)
      if vertexbufferdesc.ByteWidth < u32(len(rects) * size_of(Vertex2D) * 6) {
        vertexbufferdesc.ByteWidth = u32(len(rects) * size_of(Vertex2D) * 6 * 2)
        vertexbufferdesc.Usage     = d3d.USAGE.DYNAMIC
        vertexbufferdesc.BindFlags = { .VERTEX_BUFFER }

        if gpuRes.VBufferGameUi != nil do gpuRes.VBufferGameUi->Release()
        gpu.Device->CreateBuffer(&vertexbufferdesc, nil, &gpuRes.VBufferGameUi)
      }

      {   
        //Upload vertices to GPU    
        mapped : d3d.MAPPED_SUBRESOURCE
        gpu.DeviceContext->Map(gpuRes.VBufferGameUi, 0, d3d.MAP.WRITE_DISCARD, { }, &mapped)
        
        data := slice.from_ptr((^Vertex2D)(mapped.pData), 6 * len(rects))
        for r, index in rects {
          vertices := RectToVertices(r)
          copy_slice(data[index*6:index*6+6], vertices[0:6])
        }

        gpu.DeviceContext->Unmap(gpuRes.VBufferGameUi, 0)
        numVerticesGameUi = u32(6 * len(rects))
      }
    }
    UiEndFrame(uiCtx)  
    
    //Update voxel texture on GPU if necessary
    if game.UpdateVoxels.len > 0 || game.ForceUpdateAllVoxels {
      ConvertToGpuVoxel :: proc(voxel: ^Voxel) -> VoxelGpu {
        voxelGpu: VoxelGpu
        voxelGpu.Type = voxel.Type
        //voxelGpu.Light = voxel.Light
        
        initHealth := VoxelProps[voxel.Type].Health
        if initHealth != 0 {
          percent := f32(voxel.Health) / f32(initHealth)
          health := u8(percent * 255)
          voxelGpu.Health = health
        }
        else {
          voxelGpu.Health = 255
        }
        
        return voxelGpu
      }
      
      VoxelIndicesFromCoord :: proc(coord: [3]i32, depthPitch, rowPitch: i32) -> (cpuIndex, gpuIndex: i32) {
        gpuIndex = coord.y * i32(depthPitch / size_of(i32)) + coord.z * i32(rowPitch / size_of(i32)) + coord.x
        cpuIndex = coord.y * VOXEL_PER_LAYER + coord.z * CHUNK_SIZE + coord.x
        return cpuIndex, gpuIndex
      }
      
      if game.ForceUpdateAllVoxels {
        temp := Scratch.Begin()
        gpuVoxels := make([]VoxelGpu, len(game.Voxels), virtual.arena_allocator(temp.arena))
        for &voxel, i in game.Voxels {
          gpuVoxels[i] = ConvertToGpuVoxel(&voxel)
        }
        
        box : d3d.BOX
        box.top    = 0
        box.left   = 0
        box.front  = 0
        box.bottom = u32(CHUNK_SIZE - 1)
        box.right  = u32(CHUNK_SIZE - 1)
        box.back   = u32(CHUNK_HEIGHT - 1)
        gpu.DeviceContext->UpdateSubresource(gpuRes.VoxelTex, 0, nil, &gpuVoxels[0], u32(CHUNK_SIZE) * size_of(VoxelGpu), u32(VOXEL_PER_LAYER) * size_of(VoxelGpu))
        Scratch.End(temp)
      }
      else {
        for coord in arr.slice(&game.UpdateVoxels) {
          iCpu, iGpu := VoxelIndicesFromCoord({ coord.x, -coord.y, coord.z }, 0, 0)              
          gpuVoxel := ConvertToGpuVoxel(&game.Voxels[iCpu])
          
          box : d3d.BOX
          box.top    = u32(coord.z)
          box.left   = u32(coord.x)
          box.front  = u32(-coord.y)
          box.bottom = box.top   + 1
          box.right  = box.left  + 1
          box.back   = box.front + 1
          gpu.DeviceContext->UpdateSubresource(gpuRes.VoxelTex, 0, &box, &gpuVoxel, u32(CHUNK_SIZE) * size_of(VoxelGpu), u32(VOXEL_PER_LAYER) * size_of(VoxelGpu))
        }
      }
      
      // gpu.DeviceContext->Unmap(gpuRes.VoxelTex, 0)
      
      arr.clear(&game.UpdateVoxels)
      game.ForceUpdateAllVoxels = false
    }
    
    
    viewport : d3d.VIEWPORT = { 0, 0, windowSize.x, windowSize.y,  0, 1 };
    gpu.DeviceContext->RSSetViewports(1, &viewport);
    
    col := [4]f32{ 0, 0, 0, 1 }
    gpu.DeviceContext->OMSetRenderTargets(1, &gpuRes.RenderTargetMSView, gpuRes.DepthStencilView)
    gpu.DeviceContext->ClearRenderTargetView(gpuRes.RenderTargetMSView, &col);
    gpu.DeviceContext->ClearRenderTargetView(gpuRes.RenderTargetView, &col);
    gpu.DeviceContext->ClearDepthStencilView(gpuRes.DepthStencilView, { .DEPTH }, 1, 0)    
    gpu.DeviceContext->OMSetDepthStencilState(gpuRes.DepthStencilStateDefault, 0)

    buffers := [?]^d3d.IBuffer{ gpuRes.SharedBuffer, gpuRes.VoxelChunkBuffer, gpuRes.ModelBuffer }
    gpu.DeviceContext->VSSetConstantBuffers(0, 3, raw_data(&buffers))
    gpu.DeviceContext->PSSetConstantBuffers(0, 3, raw_data(&buffers))
    
    gpu.DeviceContext->VSSetShader(gpuRes.VsSimple, nil, 0)
    gpu.DeviceContext->PSSetShader(gpuRes.PsSimple, nil, 0)
    
    gpu.DeviceContext->VSSetShaderResources(0, 1, &gpuRes.VoxelTexView)
    gpu.DeviceContext->PSSetShaderResources(0, 1, &gpuRes.VoxelTexView)
    gpu.DeviceContext->PSSetShaderResources(1, 1, &gpuRes.CrackTextureView)
    
    gpu.DeviceContext->PSSetSamplers(0, 1, &gpuRes.SamplerState)
    
    blendFactor := [?]f32{ 1, 1, 1, 1 }
    sampleMask : u32 = 0xffffffff
    gpu.DeviceContext->OMSetBlendState(gpuRes.BlendState, &blendFactor, sampleMask)
    gpu.DeviceContext->RSSetState(gpuRes.Rasterizer3d)

    gpu.DeviceContext->IASetInputLayout(gpuRes.LayoutVoxel)

    stride : u32 = size_of(Vertex3D)
    offset : u32 = 0
    
    SetModelData :: proc(dc : ^d3d.IDeviceContext, buff : ^d3d.IBuffer, mat : matrix[4, 4]f32, col := [3]f32{ 1, 1, 1 }, voxel := VoxelGpu{}) {
      constantbufferMapped : d3d.MAPPED_SUBRESOURCE
      dc->Map(buff, 0, d3d.MAP.WRITE_DISCARD, { }, &constantbufferMapped)
  
      data := (^GpuModelData)(constantbufferMapped.pData)
      data.ModelMatrix = mat
      data.Color = col
      data.Voxel = voxel

      dc->Unmap(buff, 0)
    }
    
    gpu.DeviceContext->IASetPrimitiveTopology(d3d.PRIMITIVE_TOPOLOGY.TRIANGLELIST)
    gpu.DeviceContext->IASetVertexBuffers(0, 1, &gpuRes.VBufferCube.Buffer, &stride, &offset)
    
    moveCooldownSec := f32(UpgradeProps[.SPEED][game.Upgrades[.SPEED]].Value) / 1000
    interpolationSpeed := 1 / moveCooldownSec

    moveDir := game.DrillCoord - game.PrevDrillCoord
    isGoingAroundCorner := (math.abs(moveDir.x) + math.abs(moveDir.y) + math.abs(moveDir.z)) == 2
    drillPosA := [3]f32{ f32(game.PrevDrillCoord.x), f32(game.PrevDrillCoord.y), f32(game.PrevDrillCoord.z) }
    drillPosB := [3]f32{ f32(game.DrillCoord    .x), f32(game.DrillCoord    .y), f32(game.DrillCoord    .z) }
    drillPos: [3]f32
    if isGoingAroundCorner {
      //A linear interpolation between two diagonal points will clip our wheels through the edge of the voxel.
      //So we do some magic here to instead interpolate in a circular motion.
      rotCenterCoord := game.DrillCoord + game.WheelDir
      rotCenter := [3]f32{ f32(rotCenterCoord.x), f32(rotCenterCoord.y), f32(rotCenterCoord.z) }
      rotAxis := linalg.cross(linalg.to_f32(drillPosA - rotCenter), linalg.to_f32(drillPosB - rotCenter))
      
      angle := math.clamp(game.PosInterpolationT * interpolationSpeed, 0, 1) * math.to_radians_f32(90)
      dir := linalg.quaternion_mul_vector3(linalg.quaternion_angle_axis_f32(angle, rotAxis), (drillPosA - rotCenter))
      
      //The sin() gives it a little extra bump when nearing the 45 deg angle to lift it juuuust over the edge without any clipping
      drillPos = dir * (math.sin(angle * 2) * 0.1 + 1) + rotCenter
    }
    else {
      drillPos = math.lerp(drillPosA, drillPosB, math.clamp(game.PosInterpolationT * interpolationSpeed, 0, 1))
    }
    
    //Preferably we would apply the camera controller to the camera before entering the rendering code.
    //However we can only lock the camera to the drill when we know its exact interpolated position.
    //And we only calculate that when rendering it.
    if !game.FreeCam {
      //We set Height AND TargetHeight to 'override' smooth camera motion and lock it the drill.
      //After resetting the FreeCam however we do give it a bit of transition time until we fully lock again
      //so the smooth transition back to TargetHeight can play out first
      if game.FreeCamTransition >  0 do game.FreeCamTransition -= f32(time.Delta)
      if game.FreeCamTransition <= 0 do game.CamController.Height = drillPos.y - 2
      
      game.CamController.TargetHeight = drillPos.y - 2
    }
    OrbitControllerApplyToCamera(game.CamController, &game.Camera)
    game.Camera.Position.xz += { f32(CHUNK_SIZE) * 0.5 - 0.5, f32(CHUNK_SIZE) * 0.5 - 0.5 }
    
    //Rendering the whole voxel chunk when only a part of it is visible would be wasteful.
    //Instead we perform clipping to figure out the highest and lowest visible layer.
    //Similar to what the GPU does with triangles, we transform the outer edges of our chunk to clip-space,
    //perform the clipping and then transform it back to world-space.
    
    highestVisibleLayer, lowestVisibleLayer: i32
    {
      viewMatrix := linalg.inverse(Camera3dGetViewMatrix(game.Camera))
      projMatrix := matrix_persp_right_handed_zero_to_one(game.Camera.FieldOfView, game.Camera.AspectRatio, game.Camera.Near, game.Camera.Far)
      viewProj := projMatrix * viewMatrix
      
      chunkCorners := [?][3]f32 {
        //TOP CORNERS
        [3]f32{ 0, 0, 0 },
        [3]f32{ 1, 0, 0 },
        [3]f32{ 0, 0, 1 },
        [3]f32{ 1, 0, 1 },
        
        //BOTTOM CORNERS
        [3]f32{ 0, -f32(CHUNK_HEIGHT), 0 },
        [3]f32{ 1, -f32(CHUNK_HEIGHT), 0 },
        [3]f32{ 0, -f32(CHUNK_HEIGHT), 1 },
        [3]f32{ 1, -f32(CHUNK_HEIGHT), 1 },
      }
      
      for &corner in chunkCorners {
        corner.xz = corner.xz * f32(CHUNK_SIZE)
      }
      
      {
        corner0 := [3]f32{ 0, 0, 0 }
        corner1 := [3]f32{ 0, 4, 0 }
        clipSpace0 := viewProj * [4]f32{ corner0.x, corner0.y, corner0.z, 1 }
        clipSpace1 := viewProj * [4]f32{ corner1.x, corner1.y, corner1.z, 1 }
        Clip(&clipSpace0, &clipSpace1)
      }

      for i in 0..<4 {
        corner0 := &chunkCorners[i + 0]
        corner1 := &chunkCorners[i + 4]
        clipSpace0 := viewProj * [4]f32{ corner0.x, corner0.y, corner0.z, 1 }
        clipSpace1 := viewProj * [4]f32{ corner1.x, corner1.y, corner1.z, 1 }
        
        clip := Clip(&clipSpace0, &clipSpace1)
        corner0^ = (linalg.inverse(viewProj) * clipSpace0).xyz
        corner1^ = (linalg.inverse(viewProj) * clipSpace1).xyz
        
        if clip == .FULLY_INVISIBLE {
          if clipSpace0.y > 0 {
            corner0.y = -f32(CHUNK_HEIGHT)
            corner1.y = -f32(CHUNK_HEIGHT)
          }
          else {
            corner0.y = 0
            corner1.y = 0
          }
        }
      }
      
      highest := math.max(chunkCorners[0].y, chunkCorners[1].y, chunkCorners[2].y, chunkCorners[3].y)
      lowest  := math.min(chunkCorners[4].y, chunkCorners[5].y, chunkCorners[6].y, chunkCorners[7].y)
      highestVisibleLayer = math.min(0, i32(math.ceil(highest)))
      lowestVisibleLayer  = i32(math.ceil(lowest ))
    }
    
    highestRenderLayer := math.min(0, math.max(highestVisibleLayer, i32(math.ceil(game.Camera.Position.y))) + 2)
    lowestRenderLayer  := math.max(-CHUNK_HEIGHT, math.min(lowestVisibleLayer , i32(math.ceil(game.Camera.Position.y))) - 2)
    
    {
      constantbufferMapped : d3d.MAPPED_SUBRESOURCE
      gpu.DeviceContext->Map(gpuRes.SharedBuffer, 0, d3d.MAP.WRITE_DISCARD, { }, &constantbufferMapped)
      
      sharedData := (^GpuSharedData)(constantbufferMapped.pData)
      viewMatrix := (linalg.inverse(Camera3dGetViewMatrix(game.Camera)))
      projMatrix := matrix_persp_right_handed_zero_to_one(game.Camera.FieldOfView, game.Camera.AspectRatio, game.Camera.Near, game.Camera.Far)
      sharedData.ViewProjMatrix = projMatrix * viewMatrix
      sunHeightAngle := math.to_radians_f32(-50)
      sharedData.LightDir =  {
        math.cos(game.CamController.Angle.x - 0.8) * math.cos(sunHeightAngle),
        math.sin(sunHeightAngle),
        math.sin(game.CamController.Angle.x - 0.8) * math.cos(sunHeightAngle),
      }
      
      sharedData.ViewportSize = windowSize
      sharedData.CamPos = OrbitControllerGetPos(game.CamController)
      sharedData.MaxDepthReached = game.MaxDepthReached
      sharedData.MaxDepthReached = -CHUNK_HEIGHT
  
      gpu.DeviceContext->Unmap(gpuRes.SharedBuffer, 0)
    }
    
    rightDirA := linalg.to_f32(linalg.cross(game.PrevWheelDir, game.PrevDrillDir))
    rightDirB := linalg.to_f32(linalg.cross(game.WheelDir    , game.DrillDir    ))
    rightDir := math.lerp(rightDirA, rightDirB, math.clamp(game.RotInterpolationT * interpolationSpeed, 0, 1))
    
    matrix3_from_vec :: proc(x, y, z: [3]f32) -> matrix[3, 3]f32 {
      result: matrix[3, 3]f32
      result[0] = x
      result[1] = y
      result[2] = z
      return result
    }
    
    drillRotA := linalg.quaternion_from_matrix3_f32(matrix3_from_vec(linalg.to_f32(game.PrevDrillDir), -linalg.to_f32(game.PrevWheelDir), rightDirA))
    drillRotB := linalg.quaternion_from_matrix3_f32(matrix3_from_vec(linalg.to_f32(game.DrillDir    ), -linalg.to_f32(game.WheelDir    ), rightDirB))
    drillRot := linalg.quaternion_slerp(drillRotA, drillRotB, math.clamp(game.RotInterpolationT * interpolationSpeed, 0, 1))
    
    wheelRotA := linalg.quaternion_from_matrix3_f32(matrix3_from_vec(linalg.to_f32(game.PrevDriveDir), linalg.to_f32(-game.PrevWheelDir), linalg.cross(linalg.to_f32(game.PrevDriveDir), linalg.to_f32(-game.PrevWheelDir))))
    wheelRotB := linalg.quaternion_from_matrix3_f32(matrix3_from_vec(linalg.to_f32(game.DriveDir    ), linalg.to_f32(-game.WheelDir    ), linalg.cross(linalg.to_f32(game.DriveDir    ), linalg.to_f32(-game.WheelDir    ))))
    wheelRot := linalg.quaternion_slerp(wheelRotA, wheelRotB, math.clamp(game.RotInterpolationT * interpolationSpeed, 0, 1))
            
    game.PosInterpolationT += f32(time.Delta)
    game.RotInterpolationT += f32(time.Delta)
    
    Transform :: struct {
      Pos: [3]f32,
      Rot: quaternion128,
    }
    DEFAULT_TRANSFORM := Transform { Rot = linalg.Quaternionf32(1) }
    
    MatrixFromTransform :: proc(trans: Transform, scale := [3]f32{ 1, 1, 1 }) -> matrix[4, 4]f32 {
      return linalg.matrix4_from_trs_f32(trans.Pos, trans.Rot, scale)
    }
    
    carTransform := Transform { Pos = drillPos, Rot = drillRot }
    wheelTransform := Transform { Pos = drillPos, Rot = wheelRot }
    wheelTransformL := Transform { Pos = { 0, -0.35, +0.3 }, Rot = linalg.Quaternionf32(1) }
    wheelTransformR := Transform { Pos = { 0, -0.35, -0.3 }, Rot = linalg.Quaternionf32(1) }
    drillTransform := Transform { Pos = { 0.35, -0.1, 0 }, Rot = linalg.quaternion_angle_axis_f32(game.DrillRotation, { 1, 0, 0 }) }
    
    gpu.DeviceContext->IASetVertexBuffers(0, 1, &gpuRes.VBufferCar.Buffer, &stride, &offset)
    SetModelData(gpu.DeviceContext, gpuRes.ModelBuffer, MatrixFromTransform(carTransform) , { 0, 0.388, 0.216 })
    gpu.DeviceContext->Draw(u32(gpuRes.VBufferCar.Len), 0);
    
    gpu.DeviceContext->IASetVertexBuffers(0, 1, &gpuRes.VBufferDrill.Buffer, &stride, &offset)
    SetModelData(gpu.DeviceContext, gpuRes.ModelBuffer, MatrixFromTransform(carTransform) * MatrixFromTransform(drillTransform), { 1, 1, 1 })
    gpu.DeviceContext->Draw(u32(gpuRes.VBufferDrill.Len), 0);
    
    matrix4_from_tr_f32 :: proc "contextless" (t: [3]f32, r: quaternion128) -> matrix[4, 4]f32 {
    	translation := linalg.matrix4_translate(t)
    	rotation := linalg.matrix4_from_quaternion(r)
    	return linalg.mul(translation, rotation)
    }
    
    gpu.DeviceContext->IASetVertexBuffers(0, 1, &gpuRes.VBufferWheels.Buffer, &stride, &offset)
    SetModelData(gpu.DeviceContext, gpuRes.ModelBuffer, MatrixFromTransform(wheelTransform) * MatrixFromTransform(wheelTransformL), { 0.1, 0.1, 0.1 })
    gpu.DeviceContext->Draw(u32(gpuRes.VBufferWheels.Len), 0);
    SetModelData(gpu.DeviceContext, gpuRes.ModelBuffer, MatrixFromTransform(wheelTransform) * MatrixFromTransform(wheelTransformR), { 0.1, 0.1, 0.1 })
    gpu.DeviceContext->Draw(u32(gpuRes.VBufferWheels.Len), 0);

    if game.StorageVoxel != .NONE {
      storageTrans : Transform
      storageTrans.Pos.x -= 0.25
      gpu.DeviceContext->IASetInputLayout(gpuRes.LayoutVoxelSimple)
      gpu.DeviceContext->IASetVertexBuffers(0, 1, &gpuRes.VBufferCube.Buffer, &stride, &offset) 
      gpu.DeviceContext->VSSetShader(gpuRes.VsVoxelSimple, nil, 0)
      gpu.DeviceContext->PSSetShader(gpuRes.PsVoxelSimple, nil, 0)
      SetModelData(gpu.DeviceContext, gpuRes.ModelBuffer, MatrixFromTransform(carTransform) * MatrixFromTransform(storageTrans, {0.4, 0.4, 0.4}), { 0.1, 0.1, 0.1 }, { Type = game.StorageVoxel })
      gpu.DeviceContext->Draw(u32(gpuRes.VBufferCube.Len), 0);
    }
    
    {
      gpu.DeviceContext->IASetInputLayout(gpuRes.LayoutVoxelSimple)
      gpu.DeviceContext->IASetVertexBuffers(0, 1, &gpuRes.VBufferCube.Buffer, &stride, &offset) 
      gpu.DeviceContext->VSSetShader(gpuRes.VsVoxelSimple, nil, 0)
      gpu.DeviceContext->PSSetShader(gpuRes.PsVoxelSimple, nil, 0)
      for particle in arr.slice(&game.Particles) {
        SetModelData(gpu.DeviceContext, gpuRes.ModelBuffer, MatrixFromTransform({ Pos = particle.Pos }, particle.Size), { 1, 1, 1 }, { Type = particle.Type })
        gpu.DeviceContext->Draw(u32(gpuRes.VBufferCube.Len), 0);
      }
    }
    
    gpu.DeviceContext->IASetVertexBuffers(0, 1, &gpuRes.VBufferCube.Buffer, &stride, &offset) 
    gpu.DeviceContext->VSSetShader(gpuRes.VsVoxel, nil, 0)
    gpu.DeviceContext->PSSetShader(gpuRes.PsVoxel, nil, 0)
    
    SetIdOffset :: proc(dc : ^d3d.IDeviceContext, buff : ^d3d.IBuffer, id: u32, jiggleCoord: [3]i32, rand: [3]f32) {
      constantbufferMapped : d3d.MAPPED_SUBRESOURCE
      dc->Map(buff, 0, d3d.MAP.WRITE_DISCARD, { }, &constantbufferMapped)
  
      constants := (^GpuVoxelChunkData)(constantbufferMapped.pData)
      
      constants.IdOffset = id
      constants.JiggleCoord = jiggleCoord
      constants.Rand = rand

      dc->Unmap(buff, 0)
    }
    
    LOD_ENABLED :: false
    if LOD_ENABLED {
      USE_LOD_DISTANCE : i32: 40
      highestRenderLayer = math.min(highestRenderLayer, i32(game.Camera.Position.y) + USE_LOD_DISTANCE)
      lowestRenderLayer  = math.max(lowestRenderLayer , i32(game.Camera.Position.y) - USE_LOD_DISTANCE)
    }
     
    drillVoxel := GetVoxel(game, drillCoord)
    jiggle := ([3]f32{ rand.float32(), rand.float32(), rand.float32() } - 0.5) * 0.1
    jiggle *= UpgradeProps[.DRILL][game.Upgrades[.DRILL]].Value >= VoxelProps[drillVoxel.Type].Strength ? 1 : 0.2
    SetIdOffset(gpu.DeviceContext, gpuRes.VoxelChunkBuffer,
      u32(math.abs(highestRenderLayer) * VOXEL_PER_LAYER),
      { drillCoord.x, -drillCoord.y, drillCoord.z },
      isDrilling ? jiggle : {}
    )
    
    numDrawVoxels := VOXEL_PER_LAYER * math.clamp(math.abs(lowestRenderLayer - highestRenderLayer), 0, CHUNK_HEIGHT)
    gpu.DeviceContext->DrawInstanced(u32(gpuRes.VBufferCube.Len), u32(numDrawVoxels), 0, 0);
    
    {
      gpu.DeviceContext->OMSetDepthStencilState(gpuRes.DepthStencilStateSkybox, 0)
      gpu.DeviceContext->VSSetShader(gpuRes.VsScreenQuad, nil, 0)
      gpu.DeviceContext->PSSetShader(gpuRes.PsScreenQuad, nil, 0)
      
      gpu.DeviceContext->RSSetState(gpuRes.Rasterizer2d)

      stride : u32 = size_of(Vertex2D)
      offset : u32 = 0
      gpu.DeviceContext->IASetInputLayout(gpuRes.LayoutScreenQuad)
      gpu.DeviceContext->IASetVertexBuffers(0, 1, &gpuRes.VBufferQuad, &stride, &offset)
      gpu.DeviceContext->Draw(len(verticesQuad), 0);
    }
    
    Hologram :: struct {
      Coord: [3]i32,
      Mesh: GpuVertexBuffer,
    }
    
    holograms := [?]Hologram {
      { game.ShopCoordSell, gpuRes.VBufferCoins },
      { game.ShopCoordMech, gpuRes.VBufferMechanic },
      { game.ShopCoordUpgrade, gpuRes.VBufferUpgrade },
    }
    
    gpu.DeviceContext->OMSetDepthStencilState(gpuRes.DepthStencilStateNoWrite, 0)
    gpu.DeviceContext->VSSetShader(gpuRes.VsHologram, nil, 0)
    gpu.DeviceContext->PSSetShader(gpuRes.PsHologram, nil, 0)
    
    gpu.DeviceContext->IASetInputLayout(gpuRes.LayoutHologram)
    gpu.DeviceContext->RSSetState(gpuRes.Rasterizer3d)
    
    hologramInitRot := linalg.quaternion_from_euler_angles(math.to_radians_f32(0), math.to_radians_f32(0), 0, .XYZ)
    hologramAnimRot := linalg.quaternion_angle_axis_f32(f32(time.Delta), { 0, 1, 0 })
    
    for holo in holograms {
      holo := holo
      if holo.Coord == game.DrillCoord do holo.Coord.y += 1
      
      pos := linalg.to_f32(holo.Coord)
      
      SetModelData(gpu.DeviceContext, gpuRes.ModelBuffer, MatrixFromTransform({ Pos = pos }, {0.5, 0.5, 0.5}) * linalg.matrix4_from_quaternion(hologramAnimRot * hologramInitRot))
      gpu.DeviceContext->IASetVertexBuffers(0, 1, &holo.Mesh.Buffer, &stride, &offset) 
      gpu.DeviceContext->Draw(u32(holo.Mesh.Len), 0);
    }
    
    gpu.DeviceContext->ResolveSubresource(gpuRes.RenderTarget, 0, gpuRes.ColorBufferMS, 0, .B8G8R8A8_UNORM)


    {
      gpu.DeviceContext->OMSetRenderTargets(1, &gpuRes.RenderTargetView, nil)
      gpu.DeviceContext->ClearDepthStencilView(gpuRes.DepthStencilView, { .DEPTH }, 1, 0)
      
      gpu.DeviceContext->VSSetShader(gpuRes.VsUi, nil, 0)
      gpu.DeviceContext->PSSetShader(gpuRes.PsUi, nil, 0)
      gpu.DeviceContext->PSSetSamplers(0, 1, &gpuRes.SamplerState)
      gpu.DeviceContext->PSSetShaderResources(0, 1, &gpuRes.FontTextureView)
      
      gpu.DeviceContext->RSSetState(gpuRes.Rasterizer2d)

      stride : u32 = size_of(Vertex2D)
      offset : u32 = 0
      gpu.DeviceContext->IASetInputLayout(gpuRes.LayoutUi)
      gpu.DeviceContext->IASetVertexBuffers(0, 1, &gpuRes.VBufferGameUi, &stride, &offset)
      gpu.DeviceContext->Draw(numVerticesGameUi, 0);
    }
    
    if !Platform.WindowIsMinimized(window) {
      gpu.Swapchain->Present(1, { })
    }
    else {
      win32.Sleep(30)
    }
    
    assert(Scratch.Arenas[0].total_used == 0)
    assert(Scratch.Arenas[1].total_used == 0)

    time.Delta = f64(Platform.TimerGetMicroseconds(&frameTimer)) / 1000000
    time.Total += time.Delta
  }    
  
  err := os.write_entire_file_or_err("ChunkMiner.save", slice.bytes_from_ptr(game, size_of(GameState)), false) 

  free_all(virtual.arena_allocator(&lifetimeArena))
}