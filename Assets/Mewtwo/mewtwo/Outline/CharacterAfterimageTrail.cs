using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class CharacterAfterimageTrail : MonoBehaviour
{
    [Header("Trail Settings")]
    public float meshRefreshRate = 0.05f;  // How often to spawn a ghost mesh
    public float meshDestroyDelay = 1f;    // How long it takes for a ghost to disappear

    [Tooltip("Minimum distance to move before a new trail spawns (Prevents Z-Fighting)")]
    public float minSpawnDistance = 0.05f;
    [Tooltip("Minimum rotation angle before a new trail spawns (Prevents Z-Fighting)")]
    public float minSpawnAngle = 2f;

    [Header("References")]
    public Transform spawnTransform;       // The transform of the character (usually the root)
    public Material trailMaterial;         // The transparent material applied to the ghosts

    public string trailMaterialPropertyName = "_Color";

    private SkinnedMeshRenderer[] skinnedMeshRenderers;
    private bool isTrailActive;

    private Vector3 lastSpawnPos;
    private Quaternion lastSpawnRot;

    // --- OBJECT POOLING SETUP ---
    // A helper class to hold our pooled object components so we don't have to call GetComponent
    private class PooledGhost
    {
        public GameObject gameObject;
        public MeshRenderer meshRenderer;
        public MeshFilter meshFilter;
        public Mesh mesh;
    }

    private Queue<PooledGhost> ghostPool = new Queue<PooledGhost>();

    void Start()
    {
        if (spawnTransform == null) spawnTransform = transform;

        if (skinnedMeshRenderers == null || skinnedMeshRenderers.Length == 0)
        {
            skinnedMeshRenderers = spawnTransform.GetComponentsInChildren<SkinnedMeshRenderer>();
        }

        lastSpawnPos = spawnTransform.position;
        lastSpawnRot = spawnTransform.rotation;

        StartCoroutine(ActivateTrail());
    }

    IEnumerator ActivateTrail()
    {
        isTrailActive = true;

        while (true)
        {
            // 1. Z-FIGHTING PREVENTION: Check if we have moved or rotated enough
            bool movedEnough = Vector3.Distance(spawnTransform.position, lastSpawnPos) >= minSpawnDistance;
            bool rotatedEnough = Quaternion.Angle(spawnTransform.rotation, lastSpawnRot) >= minSpawnAngle;

            if (movedEnough || rotatedEnough)
            {
                foreach (var smr in skinnedMeshRenderers)
                {
                    // 2. OBJECT POOLING: Get a ghost from the pool (or create one)
                    PooledGhost ghost = GetOrCreateGhost();

                    // Align the ghost perfectly with the specific SkinnedMeshRenderer
                    // (Using smr.transform prevents multiple body parts from clumping at the root)
                    ghost.gameObject.transform.SetPositionAndRotation(smr.transform.position, smr.transform.rotation);
                    ghost.gameObject.transform.localScale = smr.transform.lossyScale;

                    // Overwrite the existing mesh instead of creating a new one (saves memory)
                    smr.BakeMesh(ghost.mesh);
                    ghost.meshFilter.sharedMesh = ghost.mesh;

                    // Match material arrays to the current SMR
                    SetupGhostMaterials(ghost, smr.materials.Length);

                    ghost.gameObject.SetActive(true);
                    StartCoroutine(FadeOutAndReturn(ghost, meshDestroyDelay));
                }

                // Update last known position/rotation
                lastSpawnPos = spawnTransform.position;
                lastSpawnRot = spawnTransform.rotation;
            }

            yield return new WaitForSeconds(meshRefreshRate);
        }
    }

    // Fetches an inactive ghost from the pool, or creates a new one if the pool is empty
    private PooledGhost GetOrCreateGhost()
    {
        if (ghostPool.Count > 0)
        {
            return ghostPool.Dequeue();
        }

        // Pool is empty, instantiate a new ghost
        PooledGhost newGhost = new PooledGhost();
        newGhost.gameObject = new GameObject("Trail_Ghost");
        newGhost.meshRenderer = newGhost.gameObject.AddComponent<MeshRenderer>();
        newGhost.meshFilter = newGhost.gameObject.AddComponent<MeshFilter>();

        // Create the mesh exactly ONCE for this pooled object
        newGhost.mesh = new Mesh();

        return newGhost;
    }

    // Ensures the ghost has the correct number of independent material instances
    private void SetupGhostMaterials(PooledGhost ghost, int requiredMaterialCount)
    {
        // Only allocate a new array and new material instances if the sizes don't match.
        // This stops Unity from leaking materials by continuously accessing .materials
        if (ghost.meshRenderer.sharedMaterials.Length != requiredMaterialCount)
        {
            Material[] newMaterials = new Material[requiredMaterialCount];
            for (int i = 0; i < requiredMaterialCount; i++)
            {
                newMaterials[i] = new Material(trailMaterial); // Create an instance safely
            }
            ghost.meshRenderer.sharedMaterials = newMaterials;
        }
    }

    IEnumerator FadeOutAndReturn(PooledGhost ghost, float delay)
    {
        float timeElapsed = 0;

        // Use sharedMaterials to avoid Unity allocating copies under the hood during the loop
        Material[] mats = ghost.meshRenderer.sharedMaterials;

        string colorPropertyName = (mats.Length > 0 && mats[0].HasProperty(trailMaterialPropertyName))
            ? trailMaterialPropertyName
            : "_BaseColor";

        Color initialColor = mats.Length > 0 ? mats[0].GetColor(colorPropertyName) : Color.white;

        while (timeElapsed < delay)
        {
            timeElapsed += Time.deltaTime;

            float alpha = Mathf.Lerp(1, 0, timeElapsed / delay);
            initialColor.a = alpha;

            for (int i = 0; i < mats.Length; i++)
            {
                mats[i].SetColor(colorPropertyName, initialColor);
            }

            yield return null;
        }

        // Return the object to the pool instead of destroying it
        ghost.gameObject.SetActive(false);
        ghostPool.Enqueue(ghost);
    }
}