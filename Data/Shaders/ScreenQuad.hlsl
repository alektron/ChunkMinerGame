cbuffer SharedData : register(b0)
{
  float4x4 ViewProjMatrix;
  float3 LightDir;
  int MaxDepthReached;
  float2 ViewportSize;
  float3 CamPos;
}

struct vertexdata
{
    float2 position : POS;
    float2 tex      : TEX;
    float4 color    : COL;
};

struct pixeldata
{
    float4 position : SV_POSITION;
    float2 tex   : TEX;
};


pixeldata vertex_shader(vertexdata vertex)
{
    pixeldata output;
    output.position = float4(vertex.position, 0, 1).xyww;
    output.tex = vertex.tex;
    return output;
}

float3 GetSky(float2 uv)
{
  float3 BLUE   = float3(0.196, 0.604, 1);
  float3 ORANGE = float3(0, 0.0, 0.0);
  float3 BLACK  = float3(0, 0, 0);
  
  float atmosphere = sqrt(1 - uv.y);
  float3 skyColor = lerp(BLUE, ORANGE, -CamPos.y / 512);
  
  float scatter = pow(0.5, 1 / 15.0);
  scatter = 1 - clamp(scatter, 0.8, 1.0);
  
  float3 scatterColor = lerp(float3(1, 1, 1), float3(1, 0.3, 0) * 1.5, scatter);
  return lerp(skyColor, float3(scatterColor), atmosphere / 1.3);
}

float4 pixel_shader(pixeldata pixel) : SV_TARGET
{
  return float4(GetSky(pixel.position.xy / ViewportSize), 1);
}