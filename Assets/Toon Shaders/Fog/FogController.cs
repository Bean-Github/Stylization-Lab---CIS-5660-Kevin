using UnityEngine;

[ExecuteAlways]
public class GlobalFogController : MonoBehaviour
{
    [Header("Global Fog Settings")]
    [GradientUsage(true)]   // CHANGED: default color space, HDR enabled
    public Gradient fogGradient = new Gradient();

    public float minDistance = 10f;
    public float maxDistance = 100f;

    private Texture2D gradientTexture;

    private static readonly int FogMinDistID =
        Shader.PropertyToID("_GlobalFogMinDist");

    private static readonly int FogMaxDistID =
        Shader.PropertyToID("_GlobalFogMaxDist");

    private static readonly int FogGradientID =
        Shader.PropertyToID("_GlobalFogGradient");

    private void OnEnable()
    {
        UpdateGlobalShaderVariables();
    }

    private void OnValidate()
    {
        UpdateGlobalShaderVariables();
    }

    private void UpdateGlobalShaderVariables()
    {
        Shader.SetGlobalFloat(FogMinDistID, minDistance);
        Shader.SetGlobalFloat(FogMaxDistID, maxDistance);

        if (fogGradient == null)
            return;

        GenerateGradientTexture();

        Shader.SetGlobalTexture(
            FogGradientID,
            gradientTexture
        );
    }

    private void GenerateGradientTexture()
    {
        if (gradientTexture == null)
        {
            gradientTexture = new Texture2D(
                256,
                1,
                TextureFormat.RGBAFloat,
                false,
                true
            );

            gradientTexture.wrapMode = TextureWrapMode.Clamp;
            gradientTexture.filterMode = FilterMode.Bilinear;
            gradientTexture.name = "GlobalFogGradientTex";
        }

        bool linear = QualitySettings.activeColorSpace == ColorSpace.Linear;

        for (int i = 0; i < gradientTexture.width; i++)
        {
            float t = i / (float)(gradientTexture.width - 1);

            Color color = fogGradient.Evaluate(t);

            gradientTexture.SetPixel(i, 0, color);
        }

        gradientTexture.Apply(false, false);
    }
}