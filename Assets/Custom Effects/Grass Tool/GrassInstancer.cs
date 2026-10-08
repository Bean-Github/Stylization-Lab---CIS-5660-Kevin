using UnityEngine;
using UnityEngine.Rendering;
using System.Collections.Generic;

namespace GrassTool
{
    [ExecuteAlways]
    public class GrassInstancer : MonoBehaviour
    {
        // ============================================================
        // GLOBAL REGISTRY
        //
        // Other rendering systems can discover grass instancers
        // without GrassInstancer knowing anything about those systems.
        // ============================================================

        public static readonly List<GrassInstancer> ActiveInstancers =
            new List<GrassInstancer>();


        // ============================================================
        // GRASS SETTINGS
        // ============================================================

        public Mesh grassMesh;
        public Material grassMaterial;

        [Tooltip(
            "Unity GameObject layer used to categorize this grass. " +
            "This is NOT a stencil value.")]
        [Range(0, 31)]
        public int grassLayer = 0;

        [Tooltip(
            "If enabled, this component renders grass normally using " +
            "Graphics.DrawMeshInstanced, preserving the old behavior.\n\n" +
            "Disable this if a custom Renderer Feature is taking over " +
            "the grass rendering, otherwise the grass can be drawn twice.")]
        public bool renderNormally = true;


        // ============================================================
        // INSTANCE DATA
        // ============================================================

        [HideInInspector]
        public List<Matrix4x4> instances =
            new List<Matrix4x4>();


        // Keep batching private.
        // Other systems can access it through the methods below.
        private List<Matrix4x4[]> batchPool =
            new List<Matrix4x4[]>();

        private List<int> batchCounts =
            new List<int>();


        // ============================================================
        // PUBLIC BATCH ACCESS
        //
        // This lets custom render systems draw the grass without
        // owning or rebuilding its batching system.
        // ============================================================

        public int BatchCount
        {
            get
            {
                return batchCounts != null
                    ? batchCounts.Count
                    : 0;
            }
        }

        public Matrix4x4[] GetBatchMatrices(int batchIndex)
        {
            return batchPool[batchIndex];
        }

        public int GetBatchInstanceCount(int batchIndex)
        {
            return batchCounts[batchIndex];
        }

        public bool HasRenderableInstances
        {
            get
            {
                return grassMesh != null &&
                       grassMaterial != null &&
                       instances != null &&
                       instances.Count > 0;
            }
        }


        // ============================================================
        // LAYER HELPERS
        // ============================================================

        public bool IsInLayerMask(LayerMask layerMask)
        {
            int layerBit = 1 << grassLayer;

            return (layerMask.value & layerBit) != 0;
        }


        // ============================================================
        // UNITY LIFETIME
        // ============================================================

        private void OnEnable()
        {
            if (!ActiveInstancers.Contains(this))
            {
                ActiveInstancers.Add(this);
            }

            UpdateBatches();

#if UNITY_EDITOR
            UnityEditor.Undo.undoRedoPerformed += OnUndoRedo;
#endif
        }

        private void OnDisable()
        {
            ActiveInstancers.Remove(this);

#if UNITY_EDITOR
            UnityEditor.Undo.undoRedoPerformed -= OnUndoRedo;
#endif
        }

#if UNITY_EDITOR
        private void OnUndoRedo()
        {
            UpdateBatches();
        }
#endif

        private void OnValidate()
        {
            grassLayer = Mathf.Clamp(grassLayer, 0, 31);
        }


        // ============================================================
        // BATCHING
        // ============================================================

        public void UpdateBatches()
        {
            if (instances == null)
            {
                instances = new List<Matrix4x4>();
            }

            if (batchPool == null)
            {
                batchPool = new List<Matrix4x4[]>();
            }

            if (batchCounts == null)
            {
                batchCounts = new List<int>();
            }

            int total = instances.Count;

            int requiredBatches =
                Mathf.CeilToInt(total / 1023.0f);


            // Reuse already-created arrays.
            while (batchPool.Count < requiredBatches)
            {
                batchPool.Add(
                    new Matrix4x4[1023]);
            }


            batchCounts.Clear();


            for (int i = 0; i < total; i += 1023)
            {
                int length =
                    Mathf.Min(
                        1023,
                        total - i);

                int batchIndex =
                    i / 1023;

                Matrix4x4[] batch =
                    batchPool[batchIndex];


                for (int j = 0; j < length; j++)
                {
                    batch[j] =
                        instances[i + j];
                }


                batchCounts.Add(length);
            }
        }


        private void EnsureBatchesAreValid()
        {
            int expectedBatchCount =
                Mathf.CeilToInt(
                    instances.Count / 1023.0f);

            if (batchCounts == null ||
                batchCounts.Count != expectedBatchCount)
            {
                UpdateBatches();
            }
        }


        // ============================================================
        // NORMAL / OLD RENDERING PATH
        //
        // Completely independent of stencil rendering.
        // ============================================================

        private void Update()
        {
            if (!renderNormally)
            {
                return;
            }

            if (!HasRenderableInstances)
            {
                return;
            }

            EnsureBatchesAreValid();


            for (int i = 0; i < batchCounts.Count; i++)
            {
                int instanceCount =
                    batchCounts[i];

                if (instanceCount <= 0)
                {
                    continue;
                }


                Graphics.DrawMeshInstanced(
                    grassMesh,
                    0,
                    grassMaterial,
                    batchPool[i],
                    instanceCount,
                    null,
                    ShadowCastingMode.On,
                    true,
                    grassLayer
                );
            }
        }
    }
}