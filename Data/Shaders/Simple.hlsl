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
  uint vertexid : SV_VertexID;
};

struct pixeldata
{
  float4 position : SV_POSITION;
  float3 normals  : NOR;
  float2 texcoord : TEX;
  //float4 color : COL;
};

float3x3 adjugate(float4x4 m)
{
  return float3x3(cross(m[1].xyz, m[2].xyz), 
                  cross(m[2].xyz, m[0].xyz), 
                  cross(m[0].xyz, m[1].xyz));
}

pixeldata vertex_shader(vertexdata vertex, uint id : SV_InstanceID)
{
  pixeldata output;
  output.position = mul(ViewProjMatrix, mul(ModelMatrix, float4(vertex.position, 1.0f)));
  output.texcoord = vertex.texcoord;
  output.normals  = normalize(mul(adjugate(ModelMatrix), vertex.normals));
  //output.color    = float4(vertex.position, 1);
  return output;
}

float4 pixel_shader(pixeldata pixel) : SV_TARGET
{
  //return float4(pixel.color.xyz, 1);
  //return mytexture.Sample(mysampler, pixel.texcoord);
  return float4((dot(-LightDir, pixel.normals) + 1) * 0.5 * Color, 1);
}