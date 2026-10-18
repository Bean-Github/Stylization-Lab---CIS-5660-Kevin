float LightingSpecular(float3 L, float3 N, float3 V, float smoothness)
{

}

void MainLighting_float(float3 normalWS, float3 positionWS, float3 viewWS, float smoothness, out float specular)
{
    specular = 0.0;

    smoothness = exp2(10 * smoothness + 1);

    normalWS = normalize(normalWS);
    viewWS = normalize(viewWS);

    Light mainLight = GetMainLight(TransformWorldToShadowCoord(positionWS));
    
    float3 H = normalize(float3(mainLight.direction) + float3(viewWS));
    float NdotH = saturate(dot(normalWS, H));
    
    specular = pow(NdotH, smoothness);
    
}

void AdditionalLighting_float(float3 normalWS, float3 positionWS, float3 viewWS, float smoothness, float hardness, out float3 specular)
{
    specular = 0;

    smoothness = exp2(10 * smoothness + 1);

    normalWS = normalize(normalWS);
    viewWS = normalize(viewWS);

    // additional lights
    int pixelLightCount = GetAdditionalLightsCount();
    for (int i = 0; i < pixelLightCount; ++i)
    {
        Light light = GetAdditionalLight(i, positionWS);
        float3 attenuatedLight = light.color * light.distanceAttenuation * light.shadowAttenuation;

        float3 H = normalize(float3(light.direction) + float3(viewWS));
        float NdotH = saturate(dot(normalWS, H));
        float specular_soft = pow(NdotH, smoothness);
        float specular_hard = smoothstep(0.005, 0.01, specular_soft);
        
        float specular_term = lerp(specular_soft, specular_hard, hardness);

        specular += specular_term * attenuatedLight;
    }
}
