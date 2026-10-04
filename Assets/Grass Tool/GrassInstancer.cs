using UnityEngine;
using System.Collections.Generic;

namespace GrassTool
{
    [ExecuteAlways]
    public class GrassInstancer : MonoBehaviour
    {
        public Mesh grassMesh;
        public Material grassMaterial;

        [HideInInspector]
        public List<Matrix4x4> instances = new List<Matrix4x4>();

        // We store reusable arrays here to stop the Garbage Collector from freezing the editor
        private List<Matrix4x4[]> batchPool = new List<Matrix4x4[]>();
        private List<int> batchCounts = new List<int>();

#if UNITY_EDITOR
        private void OnEnable()
        {
            UnityEditor.Undo.undoRedoPerformed += OnUndoRedo;
            UpdateBatches();
        }

        private void OnDisable()
        {
            UnityEditor.Undo.undoRedoPerformed -= OnUndoRedo;
        }

        private void OnUndoRedo()
        {
            UpdateBatches();
        }
#else
        private void OnEnable()
        {
            UpdateBatches();
        }
#endif

        public void UpdateBatches()
        {
            if (instances == null) instances = new List<Matrix4x4>();
            if (batchPool == null) batchPool = new List<Matrix4x4[]>();
            if (batchCounts == null) batchCounts = new List<int>();

            int total = instances.Count;
            int requiredBatches = Mathf.CeilToInt(total / 1023f);

            // 1. Expand the pool only if we need more arrays
            while (batchPool.Count < requiredBatches)
            {
                batchPool.Add(new Matrix4x4[1023]);
            }

            batchCounts.Clear();

            // 2. Overwrite the data in the existing arrays instead of creating new ones
            for (int i = 0; i < total; i += 1023)
            {
                int length = Mathf.Min(1023, total - i);
                int batchIndex = i / 1023;
                Matrix4x4[] batch = batchPool[batchIndex];

                for (int j = 0; j < length; j++)
                {
                    batch[j] = instances[i + j];
                }

                batchCounts.Add(length); // Record how many items are actually in this batch
            }
        }

        private void Update()
        {
            if (grassMesh == null || grassMaterial == null || instances == null || instances.Count == 0) return;

            // Failsafe if data gets desynced
            if (batchCounts.Count != Mathf.CeilToInt(instances.Count / 1023f))
            {
                UpdateBatches();
            }

            for (int i = 0; i < batchCounts.Count; i++)
            {
                if (batchCounts[i] > 0)
                {
                    // CRITICAL: We pass the array, but tell Unity exactly how many items (batchCounts[i]) to draw
                    Graphics.DrawMeshInstanced(grassMesh, 0, grassMaterial, batchPool[i], batchCounts[i]);
                }
            }
        }
    }
}