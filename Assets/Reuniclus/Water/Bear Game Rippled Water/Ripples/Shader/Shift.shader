Shader "Hidden/ShiftWithBlackBorder"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "black" {}
        _ShiftOffset ("Shift Offset", Vector) = (0,0,0,0) // Custom variable Unity won't overwrite
    }
    SubShader
    {
        Pass
        {
            ZTest Always Cull Off ZWrite Off
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata_t {
                float4 vertex : POSITION;
                float2 texcoord : TEXCOORD0;
            };

            struct v2f {
                float4 vertex : SV_POSITION;
                float2 texcoord : TEXCOORD0;
            };

            sampler2D _MainTex;
            float4 _ShiftOffset; // Using our custom offset

            v2f vert (appdata_t v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                // Apply the shift offset manually
                o.texcoord = v.texcoord + _ShiftOffset.xy; 
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                // If the UV is pushed outside 0-1, output black
                if (i.texcoord.x < 0.0 || i.texcoord.x > 1.0 || i.texcoord.y < 0.0 || i.texcoord.y > 1.0)
                {
                    return float4(0, 0, 0, 0);
                }

                return tex2D(_MainTex, i.texcoord);
            }
            ENDCG
        }
    }
}