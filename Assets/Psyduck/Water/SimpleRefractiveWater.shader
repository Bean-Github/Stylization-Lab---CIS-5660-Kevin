Shader "Custom/ThickRefractiveWaterCurved"
{
    Properties
    {
        [Header(Overall Volume Tint)]
        [HDR] _OverallTintColor ("Overall Tint Color", Color) = (1,1,1,1)
        _OverallTintStrength ("Overall Tint Strength", Range(0,1)) = 1
        _FarTintInfluence ("Deep Water Tint Influence", Range(0,1)) = 0

        [Header(Water Color)]
        [HDR] _NearColor ("Shallow Color", Color) = (0.05, 0.65, 0.75, 1)
        [HDR] _FarColor ("Deep Color", Color) = (0.01, 0.08, 0.18, 1)
        // Distances measure the view ray traveling THROUGH the water, in world units.
        // At Near Distance use Near Color; at Far Distance use Far Color.
        _NearFadeDistance ("Near Fade Distance (World Units)", Float) = 0.1
        _FarFadeDistance ("Far Fade Distance (World Units)", Float) = 3.0
        _TopNearColorStrength ("Top Near Color Mix", Range(0,1)) = 0.2
        _DepthColorStrength ("Top Far Color Mix", Range(0,1)) = 0.8

        [Header(Volume Thickness)]
        _AbsorptionDensity ("Side Absorption per Meter", Range(0,10)) = 1.5
        _SideScatterStrength ("Side Color Mix", Range(0,1)) = 1
        _SideNearTint ("Side Minimum Tint", Range(0,1)) = 0.18
        _SideRefractionStrength ("Side Refraction", Range(0,0.05)) = 0.004
        _SideWaveScale ("Side Wave Scale", Float) = 8
        [Header(Light Waterline Above Dark Waterline)]
        [HDR] _LightBandColor ("Light Waterline Color", Color) = (0.25,0.85,1.5,1)
        _LightBandWidth ("Light Waterline Width (World Units)", Float) = 0.06
        _LightBandStrength ("Light Waterline Strength", Range(0,3)) = 0.85

        [Header(Dark Waterline Below Light Waterline)]
        [HDR] _SurfaceBandColor ("Dark Waterline Color", Color) = (0.005,0.025,0.045,1)
        _SurfaceBandWidth ("Dark Waterline Width (World Units)", Float) = 0.18
        _SurfaceBandStrength ("Dark Waterline Strength", Range(0,3)) = 0.8
        _BandFeather ("Waterline Blend Width (World Units)", Float) = 0.012
        _TopRimWidth ("Top Light Edge Width (World Units)", Float) = 0.1
        _TopRimStrength ("Top Light Edge Strength", Range(0,1)) = 0.35

        [Header(Fresnel)]
        [HDR] _FresnelColor ("Fresnel Color", Color) = (0.2,0.5,0.7,1)
        _FresnelPower ("Fresnel Power", Range(0.5,10)) = 4
        _FresnelStrength ("Fresnel Strength", Range(0,1)) = 0.4

        [Header(Top Refraction Waves)]
        _RefractionStrength ("Top Refraction", Range(0,0.1)) = 0.015
        _WaveScale ("Large Wave Frequency", Range(0.01,10)) = 2
        _WaveSpeed ("Large Wave Speed", Range(0,10)) = 0.8
        _WaveStrength ("Large Wave Strength", Range(0,1)) = 0.12

        [Header(Top Surface Glimmer)]
        [HDR] _SpecularColor ("Specular Color", Color) = (1,1,1,1)
        _SpecularStrength ("Specular Strength", Range(0,20)) = 2
        _SpecularPower ("Specular Sharpness Power", Range(1,1024)) = 200
        _SpecularDirection ("Direction TO Glimmer Source (World)", Vector) = (0.3,1,0.2,0)
        _SpecWaveScale1 ("Small Wave 1 Frequency", Range(0.1,100)) = 16
        _SpecWaveSpeed1 ("Small Wave 1 Speed", Range(0,10)) = 1.2
        _SpecWaveScale2 ("Small Wave 2 Frequency", Range(0.1,100)) = 27
        _SpecWaveSpeed2 ("Small Wave 2 Speed", Range(0,10)) = 1.7
        _SpecWaveStrength ("Small Wave Strength", Range(0,1)) = 0.12
        _SpecularTexture ("Specular Mask Texture", 2D) = "white" {}
        _SpecularTextureStrength ("Specular Mask Amount", Range(0,1)) = 0
        _SpecularTextureScale ("Specular Mask Tiling", Float) = 8
        _SpecularTextureSpeed ("Specular Mask Speed", Float) = 0.2

        [Header(Curved Waterline and Mesh Bounds)]
        // Distance is baked in mesh UV4.x by WaterlineDistanceBaker.
        _VolumeMinOS ("Mesh Bounds Min (Local)", Vector) = (-0.5,-0.5,-0.5,0)
        _VolumeMaxOS ("Mesh Bounds Max (Local)", Vector) = (0.5,0.5,0.5,0)
        _TopNormalThreshold ("Upward Geometric Face Normal Threshold", Range(0,1)) = 0.75
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent" }
        Pass
        {
            Name "WaterVolume"
            Tags { "LightMode"="UniversalForward" }
            Cull Back
            ZWrite Off
            ZTest LEqual
            Blend One Zero

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            TEXTURE2D(_SpecularTexture);
            SAMPLER(sampler_SpecularTexture);

            CBUFFER_START(UnityPerMaterial)
                half4 _OverallTintColor;
                half _OverallTintStrength;
                half _FarTintInfluence;
                half4 _NearColor, _FarColor;
                float _NearFadeDistance, _FarFadeDistance;
                half _TopNearColorStrength, _DepthColorStrength;

                float _AbsorptionDensity;
                half _SideScatterStrength, _SideNearTint, _SideRefractionStrength, _SideWaveScale;
                half4 _LightBandColor, _SurfaceBandColor;
                float _LightBandWidth, _SurfaceBandWidth, _BandFeather, _TopRimWidth;
                half _LightBandStrength, _SurfaceBandStrength, _TopRimStrength;

                half4 _FresnelColor;
                half _FresnelPower, _FresnelStrength;
                half _RefractionStrength, _WaveScale, _WaveSpeed, _WaveStrength;

                half4 _SpecularColor;
                half _SpecularStrength;
                float _SpecularPower;
                float4 _SpecularDirection;
                half _SpecWaveScale1, _SpecWaveSpeed1, _SpecWaveScale2, _SpecWaveSpeed2, _SpecWaveStrength;
                half _SpecularTextureStrength;
                float _SpecularTextureScale, _SpecularTextureSpeed;

                float4 _VolumeMinOS, _VolumeMaxOS;
                float _TopNormalThreshold;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 waterlineData : TEXCOORD3; // UV4.x = surface distance in world units
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 normalOS : TEXCOORD2;
                float3 tangentWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
                float2 waveUV : TEXCOORD5;
                float waterlineDistance : TEXCOORD6;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(OUT.positionWS);
                OUT.normalOS = IN.normalOS;
                OUT.waterlineDistance = IN.waterlineData.x;
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.tangentWS = TransformObjectToWorldDir(float3(1,0,0));
                OUT.bitangentWS = TransformObjectToWorldDir(float3(0,0,1));
                OUT.waveUV = float2(dot(OUT.positionWS, OUT.tangentWS),
                                    dot(OUT.positionWS, OUT.bitangentWS));
                return OUT;
            }

            float SafeInverse(float x)
            {
                return 1.0 / ((abs(x) < 0.00001) ? ((x < 0) ? -0.00001 : 0.00001) : x);
            }

            // Estimate the exit point using the mesh's local bounding box.
            // Ray direction is object-space units PER WORLD METER, so t is world units.
            float BoxExitDistanceWS(float3 cameraWS, float3 rayDirWS)
            {
                float3 ro = TransformWorldToObject(cameraWS);
                float3 rd = mul((float3x3)GetWorldToObjectMatrix(), rayDirWS);
                float3 invDir = float3(SafeInverse(rd.x), SafeInverse(rd.y), SafeInverse(rd.z));
                float3 a = (_VolumeMinOS.xyz - ro) * invDir;
                float3 b = (_VolumeMaxOS.xyz - ro) * invDir;
                float3 farSlab = max(a, b);
                return min(farSlab.x, min(farSlab.y, farSlab.z));
            }

            // One smooth Near -> Far color fade shared by the top AND side faces.
            // The two distances are measured in world units through the water.
            float WaterDepthFade(float waterThickness)
            {
                float nearD = max(0.0, _NearFadeDistance);
                float farD = max(nearD + 0.0001, _FarFadeDistance);
                float t = saturate((waterThickness - nearD) / (farD - nearD));
                return t * t * (3.0 - 2.0 * t);
            }

            float2 LargeWave(float2 uv)
            {
                float2 p = uv * _WaveScale;
                float t = _Time.y * _WaveSpeed;
                return float2(
                    sin(p.x + p.y * 0.35 + t) + 0.5 * cos(p.y * 1.6 - t * 0.7),
                    cos(p.y - p.x * 0.25 - t * 0.83) + 0.5 * sin(p.x * 1.4 + t * 1.2)
                );
            }

            float2 SmallWaves(float2 uv)
            {
                float t = _Time.y;
                float2 p1 = uv * _SpecWaveScale1;
                float2 p2 = float2(uv.x * 0.73 + uv.y, uv.y * 1.17 - uv.x) * _SpecWaveScale2;
                float2 a = float2(sin(p1.x + p1.y * 0.6 + t * _SpecWaveSpeed1),
                                  cos(p1.y - p1.x * 0.4 - t * _SpecWaveSpeed1 * 0.83));
                float2 b = float2(cos(p2.x - t * _SpecWaveSpeed2),
                                  sin(p2.y + t * _SpecWaveSpeed2 * 0.71));
                return a + b * 0.65;
            }

            // Apply the art-direction tint to shallow water, then smoothly
            // reduce its influence as view-ray thickness approaches Far Fade Distance.
            // At depthFactor == 1, _FarTintInfluence == 0 preserves the entire
            // original deep-water appearance, including the authored _FarColor.
            half3 ApplyOverallTint(half3 color, float depthFactor)
            {
                half deepInfluence = saturate(_FarTintInfluence);
                half depthWeight = lerp(1.0h, deepInfluence, saturate(depthFactor));
                half tintStrength = saturate(_OverallTintStrength) * depthWeight;
                half3 tint = lerp(half3(1.0h, 1.0h, 1.0h),
                                  _OverallTintColor.rgb,
                                  tintStrength);
                return color * tint;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 screenUV = IN.positionCS.xy / _ScaledScreenParams.xy;
                float3 positionOS = TransformWorldToObject(IN.positionWS);
                float3 baseNormalWS = normalize(IN.normalWS);
                float3 normalOS = normalize(IN.normalOS);
                // Geometric face normal (not smooth-shaded vertex normal).
                // Flip to agree with the authored vertex normals.
                float3 geometricNormalOS = normalize(cross(ddx(positionOS), ddy(positionOS)));
                geometricNormalOS *= (dot(geometricNormalOS, normalOS) < 0.0) ? -1.0 : 1.0;
                bool isTop = geometricNormalOS.y > _TopNormalThreshold;

                // UV4.x is the shortest-path distance along the mesh from the
                // boundary between upward-facing and side-facing triangles.
                float distanceFromRimWS = max(0.0, IN.waterlineDistance);

                float3 cameraWS = GetCameraPositionWS();
                float3 viewDirWS = normalize(cameraWS - IN.positionWS);
                float3 rayDirWS = -viewDirWS;
                float distanceToEntry = distance(cameraWS, IN.positionWS);
                float distanceToExit = BoxExitDistanceWS(cameraWS, rayDirWS);

                // The depth buffer contains opaque objects, not the back face of water.
                // Clamp the liquid path to whichever is closer: opaque geometry or box exit.
                float rawDepth = SampleSceneDepth(screenUV);
                float sceneEyeDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                float waterEyeDepth = max(0.0001, -TransformWorldToView(IN.positionWS).z);
                float opaqueDistance = sceneEyeDepth * distanceToEntry / waterEyeDepth;
                float thickness = max(0.0, min(distanceToExit, opaqueDistance) - distanceToEntry);
                float depthFactor = WaterDepthFade(thickness);
                half3 depthColor = lerp(_NearColor.rgb, _FarColor.rgb, depthFactor);

                if (!isTop)
                {
                    // SIDE WALLS: refraction, color by water thickness, two stacked waterlines.
                    float2 sideWaves = float2(
                        sin(IN.positionWS.y * _SideWaveScale + IN.positionWS.x * 1.8 + _Time.y),
                        cos(IN.positionWS.y * _SideWaveScale * 0.8 + IN.positionWS.z * 1.7 - _Time.y * 0.7)
                    );
                    float2 sideUV = saturate(screenUV + sideWaves * _SideRefractionStrength);
                    half3 background = SampleSceneColor(sideUV);

                    // More water between camera and background = stronger depth tint.
                    float transmittance = exp(-max(0.0, _AbsorptionDensity) * thickness);
                    float sideTint = saturate(
                        lerp(_SideNearTint, 1.0, 1.0 - transmittance) * _SideScatterStrength
                    );
                    half3 sideColor = lerp(background, depthColor, sideTint);

                    // Distance ALONG the curved side surface, not world-space Y.
                    float belowSurfaceWS = distanceFromRimWS;

                    float lightWidth = max(0.0001, _LightBandWidth);
                    float darkWidth = max(0.0001, _SurfaceBandWidth);
                    float feather = max(0.0001, _BandFeather);

                    // Light waterline occupies the very top of the SIDE wall.
                    float lightMask = 1.0 - smoothstep(
                        max(0.0, lightWidth - feather), lightWidth + feather, belowSurfaceWS
                    );

                    // Dark waterline starts where the light one ends.
                    float darkStart = smoothstep(
                        max(0.0, lightWidth - feather), lightWidth + feather, belowSurfaceWS
                    );
                    float darkEnd = 1.0 - smoothstep(
                        max(lightWidth + 0.0001, lightWidth + darkWidth - feather),
                        lightWidth + darkWidth + feather, belowSurfaceWS
                    );
                    float darkMask = darkStart * darkEnd;

                    sideColor = lerp(sideColor, _SurfaceBandColor.rgb,
                                     saturate(darkMask * _SurfaceBandStrength));
                    sideColor = lerp(sideColor, _LightBandColor.rgb,
                                     saturate(lightMask * _LightBandStrength));
                    return half4(ApplyOverallTint(sideColor, depthFactor), 1);
                }

                // TOP: preserve the original depth/refraction/fresnel/glimmer workflow.
                // Use the real face normal so smoothed bevel normals won't turn
                // upward-facing polygons into side-wall shading.
                baseNormalWS = normalize(TransformObjectToWorldNormal(geometricNormalOS));
                float3 tangentWS = normalize(IN.tangentWS);
                tangentWS = normalize(tangentWS - baseNormalWS * dot(tangentWS, baseNormalWS));
                float3 bitangentWS = normalize(cross(tangentWS, baseNormalWS));

                float2 bigWave = LargeWave(IN.waveUV);
                float3 largeNormalWS = normalize(baseNormalWS
                    + tangentWS * bigWave.x * _WaveStrength
                    + bitangentWS * bigWave.y * _WaveStrength);

                float3 deltaNormalVS = TransformWorldToViewDir(largeNormalWS - baseNormalWS);
                float2 refractedUV = saturate(screenUV + deltaNormalVS.xy * _RefractionStrength);
                half3 backgroundTop = SampleSceneColor(refractedUV);

                // Near color shows even in shallow water; far color strengthens with thickness.
                float topTint = lerp(_TopNearColorStrength, _DepthColorStrength, depthFactor);
                half3 waterColor = lerp(backgroundTop, depthColor, saturate(topTint));

                float fresnel = pow(1.0 - saturate(dot(largeNormalWS, viewDirWS)), _FresnelPower);
                fresnel = saturate(fresnel * _FresnelStrength);
                half3 surfaceColor = lerp(waterColor, _FresnelColor.rgb, fresnel);

                // Top light rim follows the actual top/side contour too.
                float edgeDistance = distanceFromRimWS;
                float rim = 1.0 - smoothstep(0.0, max(0.0001, _TopRimWidth), edgeDistance);
                surfaceColor = lerp(surfaceColor, _LightBandColor.rgb, saturate(rim * _TopRimStrength));

                // Specular only on upward-facing polygons.
                float2 littleWave = SmallWaves(IN.waveUV);
                float3 specNormalWS = normalize(largeNormalWS
                    + tangentWS * littleWave.x * _SpecWaveStrength
                    + bitangentWS * littleWave.y * _SpecWaveStrength);
                float3 lightDirWS = normalize(_SpecularDirection.xyz + float3(0, 0.000001, 0));
                float3 h = normalize(lightDirWS + viewDirWS + float3(0,0.000001,0));
                float spec = pow(saturate(dot(specNormalWS,h)), _SpecularPower)
                           * saturate(dot(specNormalWS,lightDirWS));
                float2 texUV = IN.waveUV * _SpecularTextureScale
                             + _Time.y * _SpecularTextureSpeed * float2(1,0.67);
                half mask = SAMPLE_TEXTURE2D(_SpecularTexture, sampler_SpecularTexture, texUV).r;
                spec *= lerp(1.0, mask, _SpecularTextureStrength);
                surfaceColor += _SpecularColor.rgb * spec * _SpecularStrength;

                return half4(ApplyOverallTint(surfaceColor, depthFactor), 1);
            }
            ENDHLSL
        }
    }
}
