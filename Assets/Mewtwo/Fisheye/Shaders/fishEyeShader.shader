
Shader "Custom/fishEye"
{
    Properties
    {
            _Forward("Base (RGB)", 2D) = "white" {}
            _Right("Base (RGB)", 2D) = "white" {}
            _Left("Base (RGB)", 2D) = "white" {}
            _Back("Base (RGB)", 2D) = "white" {}
            _Top("Base (RGB)", 2D) = "white" {}
    }
   
    SubShader
    {
        Tags { "Queue"="Overlay" "RenderType"="Transparent" }

		ZWrite Off
        ZTest Always
 
        Pass
        {
            CGPROGRAM
            
            #pragma target 4.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma glsl
            #include "UnityCG.cginc"
  
            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 posLoc : TEXCOORD0;
            };

			sampler2D _Forward;
            sampler2D _Right;
            sampler2D _Left;
            sampler2D _Back;
            sampler2D _Top;

            v2f vert(appdata_full v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
				o.posLoc = v.vertex;
				return o;
            }
 
            float4 frag(v2f input) : COLOR
            {
                float heading = degrees(atan2(input.posLoc.z, input.posLoc.x));
                float xzProj = sqrt((input.posLoc.x*input.posLoc.x) + (input.posLoc.z*input.posLoc.z));
                float pitch = degrees(atan2(input.posLoc.y, xzProj));


				// compute normalization constants in xz plane y (forward and length = 1)
				float xmax = tan(radians(45.0));
				float xlen = 2.0 * xmax;
				float h = sqrt(xmax * xmax + 1);
				float zmax = h * tan(radians(45.0));
				float zlen = 2.0 * zmax;

				if (pitch < -45.0)
				{
					return float4(0, 0, 0, 1);
				}

				else if (heading > -45.0 && heading < 45.0 && pitch > -45.0)
				{
					// calculate x and z
					float x = -tan(radians(heading));
					float h = sqrt(x * x + 1);
					float z = h * tan(radians(pitch));

					// now compute uv
					float u = (x + xmax) / xlen;
					float v = (z + zmax) / zlen;

					if (v < 1.0)
					{
						float3 uv = float3(u, v, 0);
						return tex2D(_Right, uv.xy);
					}
					else if (v > 1.0)
					{
						float phi = 90.0 - pitch;
						float xzv45 = cos(radians(45.0));

						float xz = tan(radians(phi));
						z = xz * sin(radians(heading));
						x = xz * cos(radians(heading));

						u = (xzv45 + x) / (2.0 * xzv45);
						v = (xzv45 - z) / (2.0 * xzv45);

						float3 uv = float3(u, v, 0);
						return tex2D(_Top, uv.xy);

						// return float4(0, 0, 0, 1);
						
					}
					else
						return float4(0, 0, 0, 1);


				}
				// forward
				else if (heading > 45.0 && heading < 135.0 && pitch > -45.0)
				{
					// normalize heading from 45 to -45
					heading = heading - 90.0;

					// calculate x and z
					float x = -tan(radians(heading));
					float h = sqrt(x * x + 1);
					float z = h * tan(radians(pitch));

					// now compute uv
					float u = (x + xmax) / xlen;
					float v = (z + zmax) / zlen;

					if (v < 1.0)
					{
						float3 uv = float3(u, v, 0);
						return tex2D(_Forward, uv.xy);
					}
					else if (v > 1.0)
					{
						float phi = 90.0 - pitch;
						float xzv45 = cos(radians(45.0));

						float xz = tan(radians(phi));
						x = -xz * sin(radians(heading));
						z = xz * cos(radians(heading));

						u = (xzv45 + x) / (2.0 * xzv45);
						v = (xzv45 - z) / (2.0 * xzv45);

						float3 uv = float3(u, v, 0);
						return tex2D(_Top, uv.xy);

					}
					else
						return float4(0, 0, 0, 1);

				}


				// left
				else if ((heading > 135.0 || heading < -135.0) && pitch > -45.0)
				{
					// normalize heading from 40 to -45
					heading = heading + 180.0;

					// calculate x and z
					float x = -tan(radians(heading));
					float h = sqrt(x * x + 1);
					float z = h * tan(radians(pitch));

					// now compute uv
					float u = (x + xmax) / xlen;
					float v = (z + zmax) / zlen;

					if (v < 1.0)
					{
						float3 uv = float3(u, v, 0);
						return tex2D(_Left, uv.xy);
					}
					else if (v > 1.0)
					{
						float phi = 90.0 - pitch;
						float xzv45 = cos(radians(45.0));

						float xz = tan(radians(phi));
						z = -xz * sin(radians(heading));
						x = xz * cos(radians(heading));

						u = (xzv45 - x) / (2.0 * xzv45);
						v = (xzv45 - z) / (2.0 * xzv45);

						float3 uv = float3(u, v, 0);
						return tex2D(_Top, uv.xy);

					}
					else
						return float4(0, 0, 0, 1);

				}

				// back
				else if (heading > -135.0 && heading < -45.0 && pitch > -45.0)
				{
					// normalize heading from 40 to -45
					heading = heading + 90;

					// calculate x and z
					float x = -tan(radians(heading));
					float h = sqrt(x * x + 1);
					float z = h * tan(radians(pitch));

					// now compute uv
					float u = (x + xmax) / xlen;
					float v = (z + zmax) / zlen;

					if (v < 1.0)
					{
						float3 uv = float3(u, v, 0);
						return tex2D(_Back, uv.xy);
					}
					else if (v > 1.0)
					{

						float phi = 90.0 - pitch;
						float xzv45 = cos(radians(45.0));

						float xz = tan(radians(phi));
						x = xz * sin(radians(heading));
						z = xz * cos(radians(heading));

						u = (xzv45 + x) / (2.0 * xzv45);
						v = (xzv45 + z) / (2.0 * xzv45);

						float3 uv = float3(u, v, 0);
						return tex2D(_Top, uv.xy);

						// return float4(0, 0, 0, 1);

					}
					else
						return float4(0, 0, 0, 1);

				}

				else
				{
					return float4(0, 0, 0, 0);
				}


			}
 
            ENDCG
        }
    }
}