using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Attach to a parent and animate Rotation in the Animation window.
/// Applies the float shader property _Rotation to renderers on this object
/// and all descendants, including inactive children and every material slot.
/// Values are passed through unchanged: units are determined by your shader.
/// </summary>
/// <remarks>
/// Uses renderer overrides, so material assets and other objects sharing those
/// assets are not changed. Material Inspector values will not reflect overrides.
/// Disabling/removing this component stops updates but leaves the last override.
/// Avoid multiple components/scripts controlling _Rotation on the same renderer.
/// MaterialPropertyBlocks can prevent SRP Batcher batching in URP/HDRP.
/// </remarks>
/// 
[ExecuteAlways]
[DisallowMultipleComponent]
[AddComponentMenu("Rendering/Child Shader Rotation")]
public sealed class ChildShaderRotation : MonoBehaviour
{
    [Tooltip("Animatable value sent directly to the shader float property _Rotation.")]
    public float rotation;

    private static readonly int RotationId = Shader.PropertyToID("_Rotation");

    private readonly List<Renderer> renderers = new List<Renderer>();
    private readonly List<Material> materials = new List<Material>();
    private MaterialPropertyBlock rendererBlock;
    private MaterialPropertyBlock materialBlock;

    private void OnEnable()
    {
        ApplyRotation();
    }

    private void Update()
    {
        // ExecuteAlways runs this when the scene changes in Edit/Prefab mode.
        // Unity APIs run here on the main thread, not inside OnValidate.
        if (!Application.IsPlaying(gameObject))
            ApplyRotation();
    }

    private void LateUpdate()
    {
        // Apply after the Animator and normal Update scripts in Play mode.
        if (Application.IsPlaying(gameObject))
            ApplyRotation();
    }

    private void OnDidApplyAnimationProperties()
    {
        // Also handles Animation-window preview and scrubbing.
        ApplyRotation();
    }

    [ContextMenu("Apply Rotation Now")]
    public void ApplyRotation()
    {
        if (!isActiveAndEnabled)
            return;

        if (rendererBlock == null)
            rendererBlock = new MaterialPropertyBlock();
        if (materialBlock == null)
            materialBlock = new MaterialPropertyBlock();

        // Reused lists avoid allocating material/renderer arrays each frame.
        // Rescanning also picks up newly added descendants and material changes.
        renderers.Clear();
        GetComponentsInChildren<Renderer>(true, renderers);

        foreach (Renderer target in renderers)
        {
            if (target == null)
                continue;

            materials.Clear();
            target.GetSharedMaterials(materials);
            bool hasRotationMaterial = false;

            for (int slot = 0; slot < materials.Count; slot++)
            {
                Material material = materials[slot];
                if (material == null || !material.HasProperty(RotationId))
                    continue;

                hasRotationMaterial = true;

                // A slot-level block takes precedence over a renderer-level
                // block. Update existing slot blocks without clearing their
                // other values. Don't create new slot blocks, which would mask
                // unrelated renderer-level overrides from other components.
                target.GetPropertyBlock(materialBlock, slot);
                if (!materialBlock.isEmpty)
                {
                    materialBlock.SetFloat(RotationId, rotation);
                    target.SetPropertyBlock(materialBlock, slot);
                }
            }

            if (!hasRotationMaterial)
                continue;

            // The renderer-level override covers all remaining material slots.
            target.GetPropertyBlock(rendererBlock);
            rendererBlock.SetFloat(RotationId, rotation);
            target.SetPropertyBlock(rendererBlock);
        }
    }
}
