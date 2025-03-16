cbuffer SharedData : register(b0)
{
  float4x4 ViewProjMatrix;
  float3 LightDir;
  int MaxDepthReached;
  float2 ViewportSize;
  float3 CamPos;
}

cbuffer ModelData : register(b2)
{
    float4x4 ModelMatrix;
    float3 Color;
    int Voxel;
}

struct vertexdata
{
  float3 position : POS;
  float3 normals  : NOR;
  float2 texcoord : TEX;
  float4 color    : COL;
};

struct pixeldata
{
  float4 position : SV_POSITION;
  float3 normals  : NOR;
  float2 texcoord : TEX;
  float3 worldCoord : POS;
};

float3x3 adjugate(float4x4 m)
{
  return float3x3(cross(m[1].xyz, m[2].xyz), 
                  cross(m[2].xyz, m[0].xyz), 
                  cross(m[0].xyz, m[1].xyz));
}

pixeldata vertex_shader(vertexdata vertex)
{
  float4 world = mul(ModelMatrix, float4(vertex.position, 1));
  
  pixeldata output;
  output.position = mul(ViewProjMatrix, world);
  output.texcoord = vertex.texcoord;
  output.normals = normalize(mul(adjugate(ModelMatrix), vertex.normals));
  output.worldCoord = world.xyz;
  return output;
}

float4 pixel_shader(pixeldata pixel) : SV_TARGET
{
  int type = Voxel & 0x000000FF;

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
  
  float light = max(0.1, (dot(-LightDir, pixel.normals) + 1) * 0.5);
  
  float3 viewDir = normalize(pixel.worldCoord - CamPos);
  float3 reflectDir = reflect(-LightDir, pixel.normals);
  
  float spec = pow(max(dot(viewDir, reflectDir), 0), 8);
  float specular = specularStrength * spec + light;
  
  return float4(specular * lerp(float3(1, 0, 0), color.xyz, 1) , 1);
}