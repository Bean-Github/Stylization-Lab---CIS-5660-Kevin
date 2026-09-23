#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

//void MainLightCustom_float(float3 WorldPos, float3 Normal, float3 Albedo, out float3 Direction, out float3 Color, out float DistanceAtten)
//{
//#ifdef SHADERGRAPH_PREVIEW
//    Direction = normalize(float3(0.5f, 0.5f, 0.25f));
//    Color = float3(1.0f, 1.0f, 1.0f);
//    DistanceAtten = 1.0f;
//#else
//    float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
//    Light mainLight = GetMainLight(shadowCoord);
 
//    Direction = mainLight.direction;
//    Color = mainLight.color;
//    DistanceAtten = mainLight.distanceAttenuation;
//#endif
//}

//void ComputeAdditionalLighting_float(float3 WorldPosition, float3 WorldNormal,
//    float2 Thresholds, float3 RampedDiffuseValues,
//    out float3 Color, out float Diffuse)
//{
//    Color = float3(0, 0, 0);
//    Diffuse = 1;

//#ifndef SHADERGRAPH_PREVIEW

//    int pixelLightCount = GetAdditionalLightsCount();
    
//    for (int i = 0; i < pixelLightCount; ++i)
//    {
//        Light light = GetAdditionalLight(i, WorldPosition);
//        half shadowAtten = light.shadowAttenuation;


//        half NdotL = saturate(dot(WorldNormal, light.direction));
//        half distanceAtten = light.distanceAttenuation;

//        half thisDiffuse = distanceAtten * shadowAtten * NdotL;
        
//        half rampedDiffuse = 0;
        
//        if (thisDiffuse < Thresholds.x)
//        {
//            rampedDiffuse = RampedDiffuseValues.x;
//        }
//        else if (thisDiffuse < Thresholds.y)
//        {
//            rampedDiffuse = RampedDiffuseValues.y;
//        }
//        else
//        {
//            rampedDiffuse = RampedDiffuseValues.z;
//        }
        
        
//        if (shadowAtten * NdotL == 0)
//        {
//            rampedDiffuse = 0;

//        }
        
//        if (light.distanceAttenuation <= 0)
//        {
//            rampedDiffuse = 0.0;
//        }

//        Color += max(rampedDiffuse, 0) * light.color.rgb;
//        Diffuse += rampedDiffuse;
//    }
//#endif
//}



/*
- Samples the Shadowmap for the Main Light, based on the World Position passed in. (Position node)
- For shadows to work in the Unlit Graph, the following keywords must be defined in the blackboard :
	- Enum Keyword, Global Multi-Compile "_MAIN_LIGHT", with entries :
		- "SHADOWS"
		- "SHADOWS_CASCADE"
		- "SHADOWS_SCREEN"
	- Boolean Keyword, Global Multi-Compile "_SHADOWS_SOFT"
- For a PBR/Lit Graph, these keywords are already handled for you.
*/
void MainLightShadows_float(float3 WorldPos, half4 Shadowmask, out float ShadowAtten)
{
#ifdef SHADERGRAPH_PREVIEW
		ShadowAtten = 1;
#else
#if defined(_MAIN_LIGHT_SHADOWS_SCREEN) && !defined(_SURFACE_TYPE_TRANSPARENT)
		float4 shadowCoord = ComputeScreenPos(TransformWorldToHClip(WorldPos));
#else
    float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
#endif
    ShadowAtten = MainLightShadow(shadowCoord, WorldPos, Shadowmask, _MainLightOcclusionProbes);
#endif
}


#endif