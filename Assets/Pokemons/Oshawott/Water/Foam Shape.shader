Shader "Custom/Foam/Slow FBM Ribbon"
{
    Properties
    {
        // XZ remaps a native Unity Plane into an XY ribbon before deformation.
        // All OUTPUT width and displacement are along local Y in either mode.
        [Enum(XY,0,XZ,1)] _SourcePlane ("Source Mesh Plane", Float) = 1

        _Amplitude ("Y Displacement (Local Units)", Range(0, 5)) = 0.35
        _Frequency ("Shape Frequency (Per Local X Unit)", Range(0.01, 5)) = 0.6
        _EvolutionSpeed ("Evolution Speed", Range(0, 0.25)) = 0.025
        _Seed ("Noise Seed", Float) = 0

        _WidthScale ("Base Width Multiplier", Range(0.01, 2)) = 0.1
        _WidthVariation ("Width Variation", Range(0, 0.95)) = 0.65
        _WidthFrequency ("Width Frequency (Per Local X Unit)", Range(0.01, 5)) = 0.45
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            // Deformation depends on the original object-space positions.
            "DisableBatching" = "True"
        }

        Pass
        {
            Name "FoamPreview"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Cull Off
            ZWrite On

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _SourcePlane;
                float _Amplitude;
                float _Frequency;
                float _EvolutionSpeed;
                float _Seed;
                float _WidthScale;
                float _WidthVariation;
                float _WidthFrequency;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            // Quintic interpolation: smooth first and second derivatives.
            float FoamSmooth(float x)
            {
                return x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
            }

            // Deterministic lattice value in [-1, 1]. No textures required.
            float FoamHash(float n)
            {
                n = frac(n * 0.1031);
                n *= n + 33.33;
                n *= n + n;
                return frac(n) * 2.0 - 1.0;
            }

            float FoamNoise1D(float x, float seed)
            {
                float cell = floor(x);
                float blend = FoamSmooth(frac(x));
                float a = FoamHash(cell + seed);
                float b = FoamHash(cell + 1.0 + seed);
                return lerp(a, b, blend);
            }

            // Morph between successive 1D fields, keeping their spatial
            // coordinates fixed. Time changes the shape rather than scrolling it.
            float FoamEvolvingNoise1D(float x, float time, float seed)
            {
                float frame = floor(time);
                float blend = FoamSmooth(frac(time));
                float a = FoamNoise1D(x, seed + frame * 71.713);
                float b = FoamNoise1D(x, seed + (frame + 1.0) * 71.713);
                return lerp(a, b, blend);
            }

            // Four octaves of spatial 1D FBM, normalized to [-1, 1].
            // Staggered temporal phases keep all octaves from pausing together.
            float FoamFBM1D(float x, float time, float seed)
            {
                float sum = 0.0;
                float weight = 0.5;
                float totalWeight = 0.0;

                [unroll]
                for (int octave = 0; octave < 4; ++octave)
                {
                    float octaveTime = time * (1.0 + 0.17 * octave)
                                     + 0.37 * octave;
                    sum += weight * FoamEvolvingNoise1D(x, octaveTime, seed);
                    totalWeight += weight;

                    x = x * 2.03 + 13.71;
                    seed += 31.91;
                    weight *= 0.5;
                }

                return sum / totalWeight;
            }

            float3 DeformFoam(float3 positionOS, float timeSeconds)
            {
                // XY: leave the mesh orientation alone.
                // XZ: rotate -90 degrees about local X, mapping Z width to Y.
                // This changes the OUTPUT orientation to XY; the Transform can
                // then rotate the entire ribbon into your desired world plane.
                if (_SourcePlane > 0.5)
                    positionOS = float3(positionOS.x, positionOS.z, -positionOS.y);

                float restX = positionOS.x;
                float restY = positionOS.y;
                float time = timeSeconds * max(_EvolutionSpeed, 0.0);

                // Every vertex in a cross-section shares one centerline offset.
                float centerY = _Amplitude * FoamFBM1D(
                    restX * _Frequency, time, _Seed);

                // Independent field so the widest spots need not match peaks.
                float widthNoise = FoamFBM1D(
                    restX * _WidthFrequency + 47.23,
                    time * 0.83 + 0.61,
                    _Seed + 113.17);

                // Positive width prevents the strip from inverting or collapsing.
                float widthMultiplier = max(_WidthScale, 0.001)
                    * (1.0 + clamp(_WidthVariation, 0.0, 0.95) * widthNoise);

                // Width is measured along Y, not perpendicular to the curve.
                // Assumes the source strip's width is centered about local zero.
                positionOS.y = centerY + restY * widthMultiplier;
                return positionOS;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 positionOS = DeformFoam(IN.positionOS.xyz, _Time.y);
                OUT.positionCS = TransformObjectToHClip(positionOS);
                return OUT;
            }

            // Minimal preview only. All effect logic above runs in the vertex stage.
            half4 frag(Varyings IN) : SV_Target
            {
                return half4(1.0, 1.0, 1.0, 1.0);
            }
            ENDHLSL
        }
    }

    FallBack Off
}
