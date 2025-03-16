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
  return output;
}

float4 pixel_shader(pixeldata pixel) : SV_TARGET
{
  float light = max(0.1, (dot(-LightDir, pixel.normals) + 1) * 0.5);
  return float4(float3(0.267, 0.816, 0.929) * light, 0.5);
}