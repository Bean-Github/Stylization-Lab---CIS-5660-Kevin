Shader "Custom/URPCloudShape"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _ShapeNoise ("Noise Texture (3D)", 3D) = "white" {}
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
            // TEXTURE2D_X(_CameraOpaqueTexture);
            // SAMPLER(sampler_CameraOpaqueTexture);

            TEXTURE2D_X(_BlitTexture);
            SAMPLER(sampler_BlitTexture);

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

            // Generates a pseudo-random value based on screen UVs and Time
            float randomHash(float2 uv, float time)
            {
                // We add a time-based offset to the UVs. 
                // Multiplying time by different arbitrary numbers prevents obvious diagonal scrolling.
                float2 timeOffset = float2(time * 0.131, time * 0.273);
                return frac(sin(dot(uv + timeOffset, float2(12.9898, 78.233))) * 43758.5453123);
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
                float4 col = SAMPLE_TEXTURE2D_X(
                    _BlitTexture,
                    sampler_BlitTexture,
                    input.uv
                );

                Ray ray = GetRay(input.uv); 

                // get camera ray origin and view direction!
                float3 rayOrigin = ray.origin;

                // TODO: randomize to avoid banding artifacts
                float3 viewDir = ray.direction;

                float2 rayBoxInfo = rayBoxDst(BoundsMin, BoundsMax, rayOrigin, viewDir);

                float dstToBox = rayBoxInfo.x;
                float dstInsideBox = rayBoxInfo.y;

                // sample depth texture
                float nonLinearDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, input.uv);
                // get linear value from depth texture then 
                float depth = LinearEyeDepthCustom(nonLinearDepth) * length(viewDir);

                // Calculate the maximum possible thickness of the cloud volume
                float maxThickness = length(BoundsMax - BoundsMin);

                // Step size is now a CONSTANT physical distance
                float stepSize = maxThickness / NumSteps;
                float limit = min(depth - dstToBox, dstInsideBox);

                // RAY MARCHING!
                float weight = 0;

                // --- NEW JITTER LOGIC ---
                // Get a random value between 0.0 and 1.0 for this specific pixel
                float jitter = randomHash(input.uv, _Time.y / 1000000.0f);

                // Offset the starting distance by a fraction of a single step
                float dstTraveled = jitter * stepSize;

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

                // what is transmittance? -> beer's law applied to the weight (times Absorption)
                float transmittance = 1.0f;  // closer to 1 = less weight, closer to 0 = more weight (summed density)
                float3 lightSum = 0.0f;

                [loop]
                for (int i = 0; i < NumSteps; i++) {
                    if (dstTraveled > limit) 
                    {
                        break;
                    }

                    float3 samplePos = rayOrigin + viewDir * (dstToBox + dstTraveled);
                    float density = sampleDensity(samplePos);

                    float gradient = dot(samplePos, lightDir) / NumSteps;

                    weight = density * stepSize;  // weight is essentially an approximate density over the step size

                    if (density > 0)  // optimize by skipping areas without clouds (automatically 1.0f transmittance)
                    {
                        float diffuse = max(1, dot(samplePos, lightDir) / NumSteps * Diffusion);

                        // HOW DOES THIS WORK???
                        // at each step into the cloud, you need to find how much light is at that step.
                        // call lightmarch to get a normalized value describing the cloud's
                        // "thickness" at that point. multiply by summed transmittance
                        // multiply by weight (the density at that point)
                        // harv is the Harvey-Greenstein factor (forward anisotropy)
                        // diffuse is a slight lambert factor

                        lightSum += lightMarch(samplePos) * transmittance * weight * harv * diffuse;  // add it up!
                        transmittance *= exp(-weight * Absorption);

                        if (transmittance < 0.01) 
                        {
                            break;
                        }
                    }

                    dstTraveled += stepSize;
                }

                // // exp is e^-x, where x is weight, therefore final will be calculated 0-1, 0 is cloud, 1 is blank
                // float final = exp(-weight);

                // final = 1 - final;   // final is now 1 = cloud, 0 = blank

                float3 lightColor = lightSum * CloudColor * lightColorInput;

                //lightColor += dot(viewDir, _WorldSpaceLightPos0.xyz);

                //float diffuse = max(0, dot(viewDir, _WorldSpaceLightPos0.xyz));

                //lightColor *= diffuse;

                if (transmittance >= 1.0f) 
                {
                    discard;
                }

                //return col;

                // --------------------------------------------------------
                // EDGE FADE LOGIC 
                // --------------------------------------------------------
                
                // //1. Calculate distance from screen center (0.5, 0.5)
                // float distFromCenter = distance(input.uv, float2(0.5, 0.5));

                // //2. Create the lerp value (0 = edge, 1 = center)
                // //smoothstep creates a smooth gradient between Start and Start+Falloff
                // float FadeFalloff = 0.2f;
                // float FadeStart = 0.4f;
                // float fade = 1.0 - smoothstep(FadeStart, FadeStart + FadeFalloff, distFromCenter);

                // //3. Apply Fade
                // //Lerp transmittance towards 1 (fully transparent/background)
                // transmittance = lerp(1.0, transmittance, fade);
                
                // //Fade out the cloud lighting to black
                // lightColor *= fade;
                
                // --------------------------------------------------------

                float fade = 1.0f - (dstToBox / FarPlane);
                transmittance = lerp(1.0, transmittance, fade);
                lightColor *= fade;

                // Optimization: if fully transparent, just return background
                if (transmittance >= 0.99f && length(lightColor) < 0.001f) 
                {
                    return col;
                }

                return float4(transmittance * col * DiffusionColor + lightColor, 0);
            }

            ENDHLSL
        }
    }
}