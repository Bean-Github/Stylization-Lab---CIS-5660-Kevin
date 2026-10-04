using UnityEngine;
using UnityEditor;

namespace GrassTool
{
    public class GrassModifier : EditorWindow
    {
        private GrassInstancer targetInstancer;

        // Scale & Height Modifiers
        private float scaleMultiplier = 1.0f;
        private float heightMultiplier = 1.0f;

        // Rotation Modifiers
        private float addRotationX = 0f;
        private float addRotationY = 0f;
        private float addRotationZ = 0f;

        [MenuItem("Tools/Grass Modifier")]
        public static void ShowWindow()
        {
            GetWindow<GrassModifier>("Grass Modifier");
        }

        private void OnGUI()
        {
            GUILayout.Label("Target Settings", EditorStyles.boldLabel);
            targetInstancer = (GrassInstancer)EditorGUILayout.ObjectField("Target Instancer", targetInstancer, typeof(GrassInstancer), true);

            if (targetInstancer == null)
            {
                EditorGUILayout.HelpBox("Please assign a Target Instancer to modify grass.", MessageType.Warning);
                return;
            }

            EditorGUILayout.Space();

            // --- SCALE & HEIGHT ---
            GUILayout.Label("Bulk Scale & Height (Multiplies Current Size)", EditorStyles.boldLabel);
            scaleMultiplier = EditorGUILayout.Slider("Overall Scale Multiplier", scaleMultiplier, 0.1f, 3f);
            heightMultiplier = EditorGUILayout.Slider("Height (Y) Multiplier", heightMultiplier, 0.1f, 3f);

            if (GUILayout.Button("Apply Scale/Height Multiplier"))
            {
                ModifyGrass(true, false);
                // Reset sliders back to 1 after applying so you don't accidentally double-apply
                scaleMultiplier = 1.0f;
                heightMultiplier = 1.0f;
            }

            EditorGUILayout.Space();

            // --- ROTATION ---
            GUILayout.Label("Bulk Rotation (Adds to Current Rotation)", EditorStyles.boldLabel);
            addRotationX = EditorGUILayout.Slider("Add X Rotation", addRotationX, -180f, 180f);
            addRotationY = EditorGUILayout.Slider("Add Y Rotation", addRotationY, -180f, 180f);
            addRotationZ = EditorGUILayout.Slider("Add Z Rotation", addRotationZ, -180f, 180f);

            if (GUILayout.Button("Apply Rotation Offset"))
            {
                ModifyGrass(false, true);
                // Reset sliders back to 0
                addRotationX = 0f;
                addRotationY = 0f;
                addRotationZ = 0f;
            }

            EditorGUILayout.Space();

            // --- RANDOMIZATION ---
            GUILayout.Label("Randomization Tools", EditorStyles.boldLabel);
            if (GUILayout.Button("Re-roll Random Y Rotation (0 to 360)"))
            {
                ReRollRotations();
            }
        }

        private void ModifyGrass(bool applyScale, bool applyRotation)
        {
            Undo.RecordObject(targetInstancer, "Modify Grass Instances");

            for (int i = 0; i < targetInstancer.instances.Count; i++)
            {
                Matrix4x4 mat = targetInstancer.instances[i];

                // 1. Extract Position, Rotation, and Scale from the Matrix
                Vector3 pos = new Vector3(mat.m03, mat.m13, mat.m23);
                Vector3 scale = new Vector3(mat.GetColumn(0).magnitude, mat.GetColumn(1).magnitude, mat.GetColumn(2).magnitude);
                Quaternion rot = Quaternion.LookRotation(mat.GetColumn(2), mat.GetColumn(1));

                // 2. Modify Scale
                if (applyScale)
                {
                    scale.x *= scaleMultiplier;
                    scale.y *= (scaleMultiplier * heightMultiplier);
                    scale.z *= scaleMultiplier;
                }

                // 3. Modify Rotation
                if (applyRotation)
                {
                    rot *= Quaternion.Euler(addRotationX, addRotationY, addRotationZ);
                }

                // 4. Repack the Matrix and save it back to the list
                targetInstancer.instances[i] = Matrix4x4.TRS(pos, rot, scale);
            }

            // Update the GPU batches to reflect the changes instantly
            targetInstancer.UpdateBatches();
            EditorUtility.SetDirty(targetInstancer);
        }

        private void ReRollRotations()
        {
            Undo.RecordObject(targetInstancer, "Re-roll Grass Rotations");

            for (int i = 0; i < targetInstancer.instances.Count; i++)
            {
                Matrix4x4 mat = targetInstancer.instances[i];

                Vector3 pos = new Vector3(mat.m03, mat.m13, mat.m23);
                Vector3 scale = new Vector3(mat.GetColumn(0).magnitude, mat.GetColumn(1).magnitude, mat.GetColumn(2).magnitude);

                // Keep original Up direction based on the ground normal, but randomize the Y spin
                Quaternion baseRot = Quaternion.LookRotation(mat.GetColumn(2), mat.GetColumn(1));
                Vector3 euler = baseRot.eulerAngles;
                euler.y = Random.Range(0f, 360f);

                Quaternion newRot = Quaternion.Euler(euler);

                targetInstancer.instances[i] = Matrix4x4.TRS(pos, newRot, scale);
            }

            targetInstancer.UpdateBatches();
            EditorUtility.SetDirty(targetInstancer);
        }
    }
}