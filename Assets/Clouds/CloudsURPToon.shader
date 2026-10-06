Shader "Custom/URPCloudShape"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _ShapeNoise ("Noise Texture (3D)", 3D) = "white" {}

        [Header(Toon Settings)]
        _ToonThreshold ("Light Cutoff", Range(0, 1)) = 0.5
        _ToonSoftness ("Edge Softness", Range(0.001, 0.5)) = 0.05
        _ToonSteps ("Banding Steps", Float) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZWrite Off Cull Off

        Pass
        {
            Name "URPCloudShape"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            // --------------------------------------------------------------------------
            // TEXTURES & SAMPLERS
            // --------------------------------------------------------------------------
            TEXTURE2D_X(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);

            TEXTURE2D(_GlobalScreenGrab);
            SAMPLER(sampler_GlobalScreenGrab);
            float4 _GlobalScreenGrab_TexelSize;

            TEXTURE2D_X(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            TEXTURE3D(_ShapeNoise);
            SAMPLER(sampler_ShapeNoise);

            // --------------------------------------------------------------------------
            // VARIABLES
            // --------------------------------------------------------------------------

            // Camera Params
            float NearPlane;
            float FarPlane;

            // Cloud Params
            float3 BoundsMin;
            float3 BoundsMax;
            
            float CloudScale;
            float3 CloudOffset;

            float DensityThreshold;
            float DensityMultiplier;

            float Absorption;
            float4 CloudColor;

            float AbsorptionThreshold;

            int NumSteps;
            int NumLightSteps;

            float SampleLightDistance;
            float TransmittanceContrast;

            float HGBias;
            float HGThreshold;
            float HGDualLobStrength;

            float Diffusion;
            float4 DiffusionColor;

            float _ToonThreshold;
            float _ToonSoftness;
            float _ToonSteps;

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Ray
            {
                float3 origin;
                float3 direction;
            };

            // --------------------------------------------------------------------------
            // VERTEX SHADER (Fixed)
            // --------------------------------------------------------------------------
            Varyings vert(uint vertexID : SV_VertexID)
            {
                Varyings o;

                // Standard Fullscreen Triangle positions
                float4 pos[3] = {
                    float4(-1.0, -1.0, 0.0, 1.0),
                    float4( 3.0, -1.0, 0.0, 1.0),
                    float4(-1.0,  3.0, 0.0, 1.0)
                };
                
                // Standard UVs
                float2 uvs[3] = {
                    float2(0.0, 0.0),
                    float2(2.0, 0.0),
                    float2(0.0, 2.0)
                };

                o.positionCS = pos[vertexID];
                o.uv = uvs[vertexID];

                // FIX: Handle RenderTexture vertical flip (DirectX vs OpenGL)
                // If _ProjectionParams.x is negative, it means we are on a platform 
                // where the projection is flipped (like DirectX), so we flip the UV Y.
                if (_ProjectionParams.x < 0.0)
                {
                    o.uv.y = 1.0 - o.uv.y;
                }

                return o;
            }

            // --------------------------------------------------------------------------
            // HELPER FUNCTIONS
            // --------------------------------------------------------------------------

            Ray GetRay(float2 uv) 
            {
                // 1. Convert UV to NDC
                float2 ndc = uv * 2.0 - 1.0; 
                
                // 2. Reconstruct View Position
                // We use unity_CameraInvProjection (Built-in URP)
                // float4 viewPos = mul(unity_CameraInvProjection, float4(ndc, 0.0, 1.0));
                // viewPos /= viewPos.w;

                // 3. Reconstruct World Direction
                // We use unity_CameraToWorld (Built-in URP)
                // Note: We use the 3x3 portion for direction rotation
                // float3 rayDirWS = mul((float3x3)unity_CameraToWorld, viewPos.xyz);

                // reconstruct view vector from screen UV

                // v.uv is in [0,1] range with 0.5 at center, so we convert to [-1, 1] range
                // z = 0 and w = -1 are placeholders
                // multiply with camera inverse projection to convert to view space (a 3D point on the near clip plane).
                // makes a vector pointing from the camera origin to the pixel on the near plane, in view space.
                float3 viewVector = mul(unity_CameraInvProjection, float4(ndc, 0, -1));

                //NDC to View Space: The inverse projection matrix "unprojects" the 2D pixel into 3D space.
                //View Space to World Space: The camera-to-world matrix rotates the direction into global coordinates.
                // go from view space to world space

                Ray ray;
                ray.origin = _WorldSpaceCameraPos; // Built-in URP camera position
                viewVector = mul(unity_CameraToWorld, float4(viewVector,0));
                ray.direction = normalize(viewVector.xyz);
                //ray.direction = normalize(rayDirWS);
                return ray;
            }

            float LinearEyeDepthCustom(float rawDepth)
            {
                // Note: Standard LinearEyeDepth usually works, but keeping your logic safe
                return (NearPlane * FarPlane) / (FarPlane - (1.0f - rawDepth) * (FarPlane - NearPlane));
            }

            // Returns (dstToBox, dstInsideBox). If ray misses box, dstInsideBox will be zero
            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 rayDir) {
                // Adapted from: http://jcgt.org/published/0007/03/04/

                float3 t0 = (boundsMin - rayOrigin) / rayDir;
                float3 t1 = (boundsMax - rayOrigin) / rayDir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);

                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));

                // CASE 1: ray intersects box from outside (0 <= dstA <= dstB)
                // dstA is dst to nearest intersection, dstB dst to far intersection

                // CASE 2: ray intersects box from inside (dstA < 0 < dstB)
                // dstA is the dst to intersection behind the ray, dstB is dst to forward intersection

                // CASE 3: ray misses box (dstA > dstB)

                float dstToBox = max(0, dstA);
                float dstInsideBox = max(0, dstB - dstToBox);
                return float2(dstToBox, dstInsideBox);
            }

            // float sampleDensity(float3 position)
            // {
            //     float3 uvw = position * CloudScale * 0.001 + CloudOffset * 0.01;
            //     float4 shape = ShapeNoise.SampleLevel(samplerShapeNoise, uvw, 0);
            //     float density = max(0, shape.r - DensityThreshold) * DensityMultiplier;
            //     return density;   // if density is closer to 1, then we are deeper in a cloud
            // }
            float sampleDensity(float3 position)
            {
                float3 uvw = position * CloudScale * 0.001 + CloudOffset * 0.01;
                uvw += 0.5f;
                float4 shape = SAMPLE_TEXTURE3D_LOD(_ShapeNoise, sampler_ShapeNoise, uvw, 0);
                float density = max(0, shape.r - DensityThreshold) * DensityMultiplier;
                return density;
            }

            float3 GetVolumeNormal(float3 p, float3 viewDir)
            {
                float eps = 2.0; // The offset distance. Higher = smoother normals, Lower = more detail/noise
    
                // Central Difference (High Quality, 6 samples)
                // float val1 = sampleDensity(p + float3(eps, 0, 0));
                // float val2 = sampleDensity(p - float3(eps, 0, 0));
                // float val3 = sampleDensity(p + float3(0, eps, 0));
                // float val4 = sampleDensity(p - float3(0, eps, 0));
                // float val5 = sampleDensity(p + float3(0, 0, eps));
                // float val6 = sampleDensity(p - float3(0, 0, eps));
                // float3 n = float3(val1 - val2, val3 - val4, val5 - val6);

                // Forward Difference (Cheaper, 4 samples total including center)
                float center = sampleDensity(p);
                float valX = sampleDensity(p + float3(eps, 0, 0));
                float valY = sampleDensity(p + float3(0, eps, 0));
                float valZ = sampleDensity(p + float3(0, 0, eps));
    
                float3 n = float3(valX - center, valY - center, valZ - center);

                // If gradient is zero (empty space), default to pointing back at camera
                if (length(n) < 0.001) return -viewDir;

                // The gradient points IN to the cloud (higher density), so we flip it (-) to point OUT
                return normalize(-n);
            }

            // TODO: what the fuck?
            // Henyey-Greenstein
            // takes in an angle and a "bias factor" and returns . Cloud bias factor ~1
            // returns a probability: How likely is it that a photon (light particle) will bounce off a particle and go in direction theta
            float hg(float angle, float g) 
            {
                float g2 = g*g;
                return (1-g2) / (4*3.1415*pow(1+g2-2*g*(angle), 1.5));
            }

            float duallobhg(float angle, float g, float k) 
            {
                return lerp(hg(angle, -g), hg(angle, g), k);
            }

            // returns a value from 1 to 0, 1 is a large amount of cloud weight, 0 is very bright
            float lightMarch(float3 startPos)
            {               
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);

                // now cast a ray to the light direction
                float dstLightTraveled = 0;

                float cloudWeight = 0;

                //float sampleDist = SampleLightDistance;

                // BIG IDEA: Get the distance inside the box to determine the step size. Further inside = larger step size
                float dstInsideBox = rayBoxDst(BoundsMin, BoundsMax, startPos, lightDir).y;
                
                float lightStepSize = dstInsideBox / NumLightSteps;   // I originally had constant distance, not constant steps

                float totalLight = 0;

                [loop]
                for (int step = 0; step < NumLightSteps; step++)
                {
                    float3 sampleLightPos = startPos + lightDir * step * lightStepSize;

                    float density = sampleDensity(sampleLightPos);

                    cloudWeight += max(0, density * lightStepSize);

                    dstLightTraveled += lightStepSize;
                }

                float transmittance = exp(-cloudWeight * Absorption);

                //totalLight = 1 - (cloudWeight); //exp(-cloudWeight);  // more cloud weight = the closer total light is to 0

                return max(AbsorptionThreshold, pow(transmittance, TransmittanceContrast));    // 1 = no cloud weight, 0 otherwise
            }

            // --------------------------------------------------------------------------
            // FRAGMENT SHADER
            // --------------------------------------------------------------------------
            half4 frag (Varyings input) : SV_Target
            {
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float3 lightColorInput = mainLight.color;

                // col is the scene color
                float4 col = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, input.uv);

                Ray ray = GetRay(input.uv); 

                // get camera ray origin and view direction!
                float3 rayOrigin = ray.origin;
                float3 viewDir = ray.direction;

                float2 rayBoxInfo = rayBoxDst(BoundsMin, BoundsMax, rayOrigin, viewDir);

                float dstToBox = rayBoxInfo.x;
                float dstInsideBox = rayBoxInfo.y;

                // sample depth texture
                float nonLinearDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, input.uv);
                // get linear value from depth texture then 
                float depth = LinearEyeDepth(nonLinearDepth, _ZBufferParams);

                // this is the masking shader thing, very cool
                bool withinBox = (dstInsideBox > 0) && dstToBox < depth;

                if (!withinBox) 
                {
                    discard;
                }

                // Phase function makes clouds brighter around sun (uses Harvey-Greenstein dual lob)
                float cosAngle = dot(viewDir, lightDir);
                float harv = duallobhg(cosAngle, HGBias, HGDualLobStrength);

                harv = max(HGThreshold, harv);

                // RAY MARCHING!
                float dstTraveled = 0;
                float weight = 0;

                // if depth is 0
                float stepSize = dstInsideBox / NumSteps;
                float limit = min(depth - dstToBox, dstInsideBox);
                // what is transmittance? -> beer's law applied to the weight (times Absorption)
                float transmittance = 1.0f;  // closer to 1 = less weight, closer to 0 = more weight (summed density)
                float3 lightSum = 0.0f;

                float3 cloudNormal = float3(0, 1, 0); // Default
                bool foundSurface = false;

                [loop]
                for (int i = 0; i < NumSteps; i++) {

                    float3 samplePos = rayOrigin + viewDir * (dstToBox + dstTraveled);
                    float density = sampleDensity(samplePos);

                    if (density > DensityThreshold && !foundSurface)
                    {
                        cloudNormal = GetVolumeNormal(samplePos, viewDir);
                        foundSurface = true;
                    }

                    // ----------------------------------------------------
                    // NEW: BOUNDS FADING (SDF Logic) 
                    // ----------------------------------------------------
                    
                    // 1. Calculate vector from point to Min and Max bounds
                    float3 distToMin = samplePos - BoundsMin;
                    float3 distToMax = BoundsMax - samplePos;

                    // 2. Find the smallest distance to any wall (x, y, or z)
                    float3 closestDist = min(distToMin, distToMax);
                    float distToEdge = min(min(closestDist.x, closestDist.y), closestDist.z);

                    // 3. Create a 0-1 multiplier. 
                    // If distToEdge is 0 (at wall), fade is 0. 
                    // If distToEdge is > _BoundFadeDist, fade is 1.
                    float edgeFade = saturate(distToEdge / max(0.001, 1000.0f));
                    
                    // 4. Apply fade to density
                    density *= edgeFade;

                    // ----------------------------------------------------

                    float gradient = dot(samplePos, lightDir) / NumSteps;

                    weight = density * stepSize;  // weight is essentially an approximate density over the step size

                    if (density > 0)  // optimize by skipping areas without clouds (automatically 1.0f transmittance)
                    {
                        float diffuse = saturate(dot(cloudNormal, lightDir)) * Diffusion;

                        // HOW DOES THIS WORK???
                        // at each step into the cloud, you need to find how much light is at that step.
                        // call lightmarch to get a normalized value describing the cloud's
                        // "thickness" at that point. multiply by summed transmittance
                        // multiply by weight (the density at that point)
                        // harv is the Harvey-Greenstein factor (forward anisotropy)
                        // diffuse is a slight lambert factor
                        // 1. Get raw Light intensity (0 to 1)

                        // Use toonLight instead of calling lightMarch again
                        lightSum += lightMarch(samplePos) * transmittance * weight * harv * diffuse;

                        // lightSum += lightMarch(samplePos) * transmittance * weight * harv * diffuse;  // add it up!
                        transmittance *= exp(-weight * Absorption);

                        if (transmittance < 0.01) 
                        {
                            break;
                        }
                    }

                    dstTraveled += stepSize;
                }

                float3 lightColor = lightSum * CloudColor * lightColorInput;

                if (transmittance >= 1.0f) 
                {
                    discard;
                }

                float fade = 1.0f - (dstToBox / FarPlane);
                transmittance = lerp(1.0, transmittance, fade);
                lightColor *= fade;

                // Optimization: if fully transparent, just return background
                if (transmittance >= 0.99f && length(lightColor) < 0.001f) 
                {
                    return col;
                }

                // 1. Get brightness (Luminance) using N dot L
                // saturate ensures it doesn't go negative (backface)
                // We assume lightDir is normalized
                float NdotL = saturate(dot(cloudNormal, lightDir));

                // You can mix the calculated light sum with this hard NdotL for a better look
                // But for pure toon, just use NdotL:
                float lum = NdotL; 

                // 2. Quantize (step) the brightness
                float steps = 4.0f; // 4 bands
                float steppedLum = floor(lum * steps) / steps;

                // 3. Smooth edges slightly
                steppedLum = lerp(steppedLum, lum, 0.01); 

                // 4. Apply
                lightColor = lerp(lightColor, steppedLum, 1.0f - transmittance); 

                return float4(transmittance * col * DiffusionColor + lightColor, 0);
            }

            ENDHLSL
        }
    }
}