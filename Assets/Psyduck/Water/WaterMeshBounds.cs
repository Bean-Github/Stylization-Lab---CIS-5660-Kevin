using UnityEngine;

[ExecuteAlways]
[RequireComponent(typeof(MeshFilter), typeof(Renderer))]
public class WaterMeshBounds : MonoBehaviour
{
    private MeshFilter meshFilter;
    private Renderer meshRenderer;
    private MaterialPropertyBlock block;

    void OnEnable()
    {
        UpdateBounds();
    }

    void LateUpdate()
    {
        UpdateBounds();
    }

    void UpdateBounds()
    {
        if (meshFilter == null)
            meshFilter = GetComponent<MeshFilter>();

        if (meshRenderer == null)
            meshRenderer = GetComponent<Renderer>();

        if (block == null)
            block = new MaterialPropertyBlock();

        if (meshFilter.sharedMesh == null)
            return;

        Bounds bounds = meshFilter.sharedMesh.bounds;

        meshRenderer.GetPropertyBlock(block);

        block.SetVector("_VolumeMinOS", bounds.min);
        block.SetVector("_VolumeMaxOS", bounds.max);

        meshRenderer.SetPropertyBlock(block);
    }
}