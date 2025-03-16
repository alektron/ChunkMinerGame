cbuffer SharedData : register(b0)
{
  float4x4 ViewProjMatrix;
  float3 LightDir;
  int MaxDepthReached;
  float2 ViewportSize;
  float3 CamPos;
}

cbuffer VoxelChunkData : register(b1)
{
  uint IdOffset;
  int3 JiggleCoord;
  float3 Rand;
}

struct vertexdata
{
  float3 position : POS;
  float3 normals  : NOR;
  float2 texcoord : TEX;
  float4 color    : COL;
  uint vertexid : SV_VertexID;
};

struct pixeldata
{
  float4 position : SV_POSITION;
  nointerpolation int3 coord : COORD;
  nointerpolation int3 id : ID;
  float3 normals  : NOR;
  float2 texcoord : TEX;
  float4 color : COL;
  float3 worldCoord : POS;
};

Texture3D<int> voxelTex : register(t0);
Texture2D cracksTex : register(t1);
SamplerState mysampler : register(s0);

pixeldata vertex_shader(vertexdata vertex, uint id : SV_InstanceID)
{
  id += IdOffset;
  const float CUBE_SPACING = 1;
  const int CHUNK_SIZE = 10;
  const int CUBES_PER_LAYER = CHUNK_SIZE * CHUNK_SIZE;
  int3 coord = int3(
    (id % CHUNK_SIZE),
    (id / CUBES_PER_LAYER),
    ((id % CUBES_PER_LAYER) / CHUNK_SIZE)
  );
  
  float3 pos = float3(coord.x, -coord.y, coord.z);
  pos += all(JiggleCoord == coord) ? Rand : 0;
  
  int voxel = voxelTex.Load(int4(coord.xzy, 0));
  int health = (voxel >> 8) & 0x000000FF;
  int type = voxel & 0x000000FF;
  
  float scale = 1;
  if (type > 13) {
    scale = 0.5;
    
    if (type == 10) pos.x += 0.5;
    if (type == 11) pos.x -= 0.5;
    if (type == 12) pos.y += 0.5;
    if (type == 13) pos.y -= 0.5;
    if (type == 14) pos.z += 0.5;
    if (type == 15) pos.z -= 0.5;
  }
  
  float3 world = vertex.position * scale * ((health / 255.0) * 0.1 + 0.9) + float3(pos.x, pos.y, pos.z) * CUBE_SPACING;
  pixeldata output;
  output.position = mul(ViewProjMatrix, float4(world, 1.0f));
  output.texcoord = vertex.texcoord;
  output.normals = vertex.normals;
  output.color = vertex.color;
  output.coord = coord;
  output.id = id;
  output.worldCoord = world;

  return output;
}


float4 pixel_shader(pixeldata pixel) : SV_TARGET
{
  int voxel = voxelTex.Load(int4(pixel.coord.xzy, 0));
  //int voxel = pixel.voxel;
  int type = voxel & 0x000000FF;

  if (type == 0)
    discard;
    
  float4 color = float4(0, 0, 0, 1);
  switch (type) {
    case 1 : color = float4(0.459, 0.224, 0.000, 1); break; //DIRT
    case 2 : color = float4(0.400, 0.400, 0.400, 1); break; //ROCK
    case 3 : color = float4(0.229, 0.229, 0.229, 1); break; //ROCK2
    case 4 : color = float4(0.100, 0.100, 0.100, 1); break; //COAL
    case 5 : color = float4(0.608, 0.184, 0.110, 1); break; //IRON
    case 6 : color = float4(0.745, 0.760, 0.796, 1); break; //SILVER
    case 7 : color = float4(0.858, 0.674, 0.203, 1); break; //GOLD
    case 8 : color = float4(0.058, 0.321, 0.729, 1); break; //SAPHIRE
    case 9 : color = float4(0.000, 0.815, 0.384, 1); break; //EMERALD
    case 10: color = float4(0.607, 0.066, 0.117, 1); break; //RUBY
    case 11: color = float4(0.725, 0.949, 1.000, 1); break; //DIAMOND
    case 12: color = float4(0.05 , 0.05 , 0.05 , 1); break; //SOLID
    default: break;
  }
  
  float specularStrength = 0;
  switch (type) {
    case 5 : specularStrength = 10; break; //IRON
    case 6 : specularStrength = 10; break; //SILVER
    case 7 : specularStrength = 10; break; //GOLD
    case 8 : specularStrength = 10; break; //SAPHIRE
    case 9 : specularStrength = 10; break; //EMERALD
    case 10: specularStrength = 10; break; //RUBY
    case 11: specularStrength = 10; break; //DIAMOND
    case 12: specularStrength = 1; break; //SOLID
    default: break;
  }
  
  int health     = (voxel >> 8 ) & 0x000000FF;
  int voxelLight = (voxel >> 16) & 0x000000FF;
  
  float light = max(0.1, (dot(-LightDir, pixel.normals) + 1) * 0.5);
  
  float3 viewDir = normalize(pixel.worldCoord - CamPos);
  float3 reflectDir = reflect(-LightDir, pixel.normals);
  
  float spec = pow(max(dot(viewDir, reflectDir), 0), 4);
  float specular = specularStrength * spec;
  
  float2 uv;
  if      (health > 191) uv = pixel.texcoord * 0.5;
  else if (health > 128) uv = pixel.texcoord * 0.5 + float2(0.5, 0);
  else if (health > 64 ) uv = pixel.texcoord * 0.5 + float2(0, 0.5);
  else if (health > 0  ) uv = pixel.texcoord * 0.5 + float2(0.5, 0.5);
  float4 cracks = cracksTex.Sample(mysampler, uv);
  
  const int FOG_OF_WAR_START_DEPTH = 1;
  float3 worldPosNorm = pixel.worldCoord.y - (MaxDepthReached - FOG_OF_WAR_START_DEPTH);
  float fogOfWar = worldPosNorm < 0 ? 1 - clamp(distance(pixel.worldCoord.y, MaxDepthReached - FOG_OF_WAR_START_DEPTH) * 0.2, 0, 1) : 1;
  
  //https://madebyevan.com/shaders/grid/
  const float HEIGHT_MARKS = 50;
  float heightMark = abs(frac(pixel.worldCoord.y * (1 / HEIGHT_MARKS) - 0.5) - 0.5) / fwidth(pixel.worldCoord.y * (1 / HEIGHT_MARKS));
  heightMark = 1 - min(heightMark, 1);
  if (pixel.worldCoord.y > -1)
    heightMark = 0;

  
  return float4(cracks.xyz * (specular + light) * color.xyz * fogOfWar + heightMark, 1);
}