#ifndef GLOBAL_FOG_INCLUDED
#define GLOBAL_FOG_INCLUDED

#ifndef SHADERGRAPH_PREVIEW
float _GlobalFogMinDist;
float _GlobalFogMaxDist;

    TEXTURE2D(_GlobalFogGradient);
    SAMPLER(sampler_GlobalFogGradient);
#endif

void GetGlobalFogValues_float(
    float GradientT,
    out float MinDistance,
    out float MaxDistance,
    out float4 FogColor)
{
#ifdef SHADERGRAPH_PREVIEW
    MinDistance = 0;
    MaxDistance = 100;
    FogColor = float4(0.5, 0.5, 0.5, 1);
#else
    MinDistance = _GlobalFogMinDist;
    MaxDistance = _GlobalFogMaxDist;
    FogColor = SAMPLE_TEXTURE2D_LOD(_GlobalFogGradient, sampler_GlobalFogGradient,
                                    float2(saturate(GradientT), 0.5), 0);
#endif
}


#endif