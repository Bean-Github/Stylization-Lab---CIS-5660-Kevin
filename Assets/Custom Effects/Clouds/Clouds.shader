// Upgrade NOTE: replaced '_CameraToWorld' with 'unity_CameraToWorld'

Shader "Hidden/CloudShape"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                    
                float3 viewVector : TEXCOORD1;
            };

            v2f vert (appdata v)
            {
                v2f o;
                float4 worldPos = mul(unity_ObjectToWorld, v.vertex);

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;

                // reconstruct view vector from screen UV

                // v.uv is in [0,1] range with 0.5 at center, so we convert to [-1, 1] range
                // z = 0 and w = -1 are placeholders
                // multiply with camera inverse projection to convert to view space (a 3D point on the near clip plane).
                // makes a vector pointing from the camera origin to the pixel on the near plane, in view space.
                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1));

                //NDC to View Space: The inverse projection matrix "unprojects" the 2D pixel into 3D space.

                //View Space to World Space: The camera-to-world matrix rotates the direction into global coordinates.
                // go from view space to world space
                o.viewVector = mul(unity_CameraToWorld, float4(viewVector,0));

                return o;
            }

            // WHERE THE SHADER STARTS

            sampler2D _MainTex;
            sampler2D _CameraDepthTexture;

            float4 _LightColor0;

            float3 BoundsMin;
            float3 BoundsMax;
            Texture3D<float4> ShapeNoise;
            //Texture3D<float4> DetailNoise;
            
            SamplerState samplerShapeNoise;

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

            float sampleDensity(float3 position)
            {
                float3 uvw = position * CloudScale * 0.001 + CloudOffset * 0.01;
                float4 shape = ShapeNoise.SampleLevel(samplerShapeNoise, uvw, 0);
                float density = max(0, shape.r - DensityThreshold) * DensityMultiplier;
                return density;   // if density is closer to 1, then we are deeper in a cloud
            }

            // TODO: what the fuck?
            // Henyey-Greenstein
            // takes in an angle and a "bias factor" and returns . Cloud bias factor ~1
            // returns a probability: How likely is it that a photon (light particle) will bounce off a particle and go in direction theta
            float hg (float angle, float g) {
                float g2 = g*g;
                return (1-g2) / (4*3.1415*pow(1+g2-2*g*(angle), 1.5));
            }

            float duallobhg (float angle, float g, float k) {
                return lerp(hg(angle, -g), hg(angle, g), k);
            }

            // returns a value from 1 to 0, 1 is a large amount of cloud weight, 0 is very bright
            float lightMarch(float3 startPos)
            {
                // now cast a ray to the light direction
                float dstLightTraveled = 0;

                float cloudWeight = 0;

                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);

                //float sampleDist = SampleLightDistance;

                // BIG IDEA: Get the distance inside the box to determine the step size. Further inside = larger step size
                float dstInsideBox = rayBoxDst(BoundsMin, BoundsMax, startPos, 1/lightDir).y;
                
                float lightStepSize = dstInsideBox / NumLightSteps;   // I originally had constant distance, not constant steps

                float totalLight = 0;

                for (int step = 0; step < NumLightSteps; step++)
                {
                    float3 sampleLightPos = startPos + step * (lightStepSize);

                    float density = sampleDensity(sampleLightPos);

                    cloudWeight += max(0, density * lightStepSize);

                    dstLightTraveled += lightStepSize;
                }

                float transmittance = exp(-cloudWeight * Absorption);

                //totalLight = 1 - (cloudWeight); //exp(-cloudWeight);  // more cloud weight = the closer total light is to 0

                return max(AbsorptionThreshold, pow(transmittance, TransmittanceContrast));    // 1 = no cloud weight, 0 otherwise
            }
            
            float4 frag (v2f i) : SV_Target
            {
                // col is the scene color
                fixed4 col = tex2D(_MainTex, i.uv);

                // get camera ray origin and view direction!
                float3 rayOrigin = _WorldSpaceCameraPos;
                float3 viewDir = normalize(i.viewVector);

                float2 rayBoxInfo = rayBoxDst(BoundsMin, BoundsMax, rayOrigin, viewDir);

                float dstToBox = rayBoxInfo.x;
                float dstInsideBox = rayBoxInfo.y;

                // sample depth texture
                float nonLinearDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
                // get linear value from depth texture then 
                float depth = LinearEyeDepth(nonLinearDepth) * length(i.viewVector);

                // RAY MARCHING!

                float dstTraveled = 0;
                float weight = 0;

                // if depth is 0
                float stepSize = dstInsideBox / NumSteps;
                float limit = min(depth - dstToBox, dstInsideBox);


                // this is the masking shader thing, very cool
                bool withinBox = (dstInsideBox > 0) && dstToBox < depth;

                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);

                // Phase function makes clouds brighter around sun (uses Harvey-Greenstein dual lob)
                float cosAngle = dot(viewDir, lightDir);
                float harv = duallobhg(cosAngle, HGBias, HGDualLobStrength);

                harv = max(HGThreshold, harv);

                // what is transmittance? -> beer's law applied to the weight (times Absorption)
                float transmittance = 1.0f;  // closer to 1 = less weight, closer to 0 = more weight (summed density)
                float3 lightSum = 0.0f;

                while (dstTraveled < limit) {
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

                float3 l = _LightColor0;

                float3 lightColor = lightSum * CloudColor * l;

                //lightColor += dot(viewDir, _WorldSpaceLightPos0.xyz);

                //float diffuse = max(0, dot(viewDir, _WorldSpaceLightPos0.xyz));

                //lightColor *= diffuse;

                return float4(1.0f, 0.0f, 0.0f, 1.0f);

                return float4(transmittance * col * DiffusionColor + lightColor, 0);

            }

            ENDCG
        }
    }
}
