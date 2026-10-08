using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode, ImageEffectAllowedInSceneView]
public class RenderClouds : MonoBehaviour
{
    public Shader shader;
    Material material;

    public Transform container;

    public Texture3D cloudTex;

    [Header("Static")]
    public float CloudScale;
    public Vector3 CloudOffset;

    public Color CloudColor;

    public float Absorption;

    public float AbsorptionThreshold;

    public float DensityThreshold;
    public float DensityMultiplier;

    public float TransmittanceContrast;

    [Range(0f, 1f)]
    public float HarveyGreensteinBias;

    public float HarveyGreensteinThreshold;

    [Range(0f, 1f)]
    public float HarveyGreensteinDualLobStrength;

    public float Diffusion = 0.5f;

    public Color DiffusionColor;

    [Range(3, 400)]
    public int NumSteps;

    [Range(1, 20)]
    public int NumLightSteps;

    public float SampleLightDist = 10f;

    [Header("Realtime")]
    public Vector3 moveSpeed;

    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (material == null)
        {
            material = new Material(shader);
        }

        material.SetVector("BoundsMin", container.position - container.localScale / 2f);
        material.SetVector("BoundsMax", container.position + container.localScale / 2f);

        material.SetTexture("ShapeNoise", cloudTex);

        Vector3 scale = new Vector3(container.localScale.x, CloudScale / container.localScale.y, CloudScale / container.localScale.z);

        material.SetFloat("CloudScale", CloudScale);
        material.SetVector("CloudOffset", CloudOffset);

        material.SetFloat("DensityThreshold", DensityThreshold);
        material.SetFloat("DensityMultiplier", DensityMultiplier);

        material.SetFloat("Absorption", Absorption);
        material.SetFloat("AbsorptionThreshold", AbsorptionThreshold);

        material.SetFloat("TransmittanceContrast", TransmittanceContrast);

        material.SetInt("NumSteps", NumSteps);

        material.SetInt("NumLightSteps", NumLightSteps);

        material.SetFloat("SampleLightDistance", SampleLightDist);

        material.SetColor("CloudColor", CloudColor);

        material.SetFloat("HGBias", HarveyGreensteinBias);

        material.SetFloat("HGThreshold", HarveyGreensteinThreshold);

        material.SetFloat("HGDualLobStrength", HarveyGreensteinDualLobStrength);

        material.SetFloat("Diffusion", Diffusion);

        material.SetColor("DiffusionColor", DiffusionColor);

        Graphics.Blit(source, destination, material);
    }

    private void Update()
    {
        if (!Application.isPlaying)
        {
            return;
        }
        DensityThreshold += Mathf.Sin(Time.time) * 0.000001f;

        CloudOffset += moveSpeed * Time.deltaTime;
    }
}


