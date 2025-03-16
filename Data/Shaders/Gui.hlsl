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
    float4 color : COL;
};

Texture2D    mytexture : register(t0);
SamplerState mysampler : register(s0);

pixeldata vertex_shader(vertexdata vertex)
{
    pixeldata output;
    output.position = float4((vertex.position / ViewportSize * 2 - 1) * float2(1, -1), 0, 1);
    output.color = vertex.color;
    output.tex = vertex.tex;

    return output;
}

float4 pixel_shader(pixeldata pixel) : SV_TARGET
{
    if (mytexture.Sample(mysampler, pixel.tex).a == 0)
        discard;
    return float4(mytexture.Sample(mysampler, pixel.tex).xyzw) * pixel.color;
}