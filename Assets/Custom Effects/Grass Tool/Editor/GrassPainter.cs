using UnityEngine;
using UnityEditor;

namespace GrassTool
{

    public class GrassPainter : EditorWindow
    {
        private GrassInstancer targetInstancer;

        // Brush Settings
        private float brushSize = 2f;
        private int density = 5;

        // Scale & Height Settings
        private float grassScale = 1f;
        private Vector2 heightRandomRange = new Vector2(0.8f, 1.5f); // x = min, y = max

        // Rotation Settings
        private Vector2 rotationXRange = new Vector2(0f, 0f);
        private Vector2 rotationYRange = new Vector2(0f, 360f);
        private Vector2 rotationZRange = new Vector2(0f, 0f);

        private Vector3 lastPaintPos = Vector3.zero;

        [MenuItem("Tools/Grass Painter")]
        public static void ShowWindow()
        {
            GetWindow<GrassPainter>("Grass Painter");
        }

        private void OnGUI()
        {
            GUILayout.Label("Grass Brush Settings", EditorStyles.boldLabel);

            targetInstancer = (GrassInstancer)EditorGUILayout.ObjectField("Target Instancer", targetInstancer, typeof(GrassInstancer), true);

            brushSize = EditorGUILayout.Slider("Brush Size", brushSize, 0.5f, 20f);
            density = EditorGUILayout.IntSlider("Density (per tick)", density, 1, 50);

            EditorGUILayout.Space();

            GUILayout.Label("Scale & Height Customization", EditorStyles.boldLabel);
            grassScale = EditorGUILayout.Slider("Base Scale", grassScale, 0.1f, 5f);
            heightRandomRange = EditorGUILayout.Vector2Field("Height Multiplier (Min / Max)", heightRandomRange);

            EditorGUILayout.Space();

            GUILayout.Label("Rotation Customization (Degrees)", EditorStyles.boldLabel);
            rotationXRange = EditorGUILayout.Vector2Field("X Rotation (Min / Max)", rotationXRange);
            rotationYRange = EditorGUILayout.Vector2Field("Y Rotation (Min / Max)", rotationYRange);
            rotationZRange = EditorGUILayout.Vector2Field("Z Rotation (Min / Max)", rotationZRange);

            EditorGUILayout.Space();

            if (GUILayout.Button("Clear All Grass"))
            {
                if (targetInstancer != null)
                {
                    Undo.RecordObject(targetInstancer, "Clear Grass");
                    targetInstancer.instances.Clear();
                    targetInstancer.UpdateBatches();
                }
            }

            EditorGUILayout.HelpBox("Left Click to Paint\nShift + Left Click to Erase", MessageType.Info);
        }

        private void OnEnable()
        {
            SceneView.duringSceneGui += OnSceneGUI;
        }

        private void OnDisable()
        {
            SceneView.duringSceneGui -= OnSceneGUI;
        }

        private void OnSceneGUI(SceneView sceneView)
        {
            if (targetInstancer == null) return;

            Event e = Event.current;
            int controlID = GUIUtility.GetControlID(FocusType.Passive);

            if (e.type == EventType.Layout)
            {
                HandleUtility.AddDefaultControl(controlID);
            }

            Ray ray = HandleUtility.GUIPointToWorldRay(e.mousePosition);
            if (Physics.Raycast(ray, out RaycastHit hit))
            {
                // Change brush color to red if holding Shift (Erase Mode)
                Handles.color = e.shift ? Color.red : Color.green;
                Handles.DrawWireDisc(hit.point, hit.normal, brushSize);

                // Paint or Erase when dragging/clicking left mouse button
                if ((e.type == EventType.MouseDrag || e.type == EventType.MouseDown) && e.button == 0 && !e.alt)
                {
                    if (e.type == EventType.MouseDown)
                    {
                        Undo.RecordObject(targetInstancer, e.shift ? "Erase Grass" : "Paint Grass");
                        lastPaintPos = hit.point; // Reset the distance tracker on click
                    }

                    // THROTTLE: Only run the heavy math if the mouse actually moved enough distance
                    if (e.type == EventType.MouseDown || Vector3.Distance(hit.point, lastPaintPos) > (brushSize * 0.1f))
                    {
                        if (e.shift)
                        {
                            EraseGrass(hit.point);
                        }
                        else
                        {
                            PaintGrass(hit.point, hit.normal);
                        }

                        lastPaintPos = hit.point; // Save the position of this stroke
                    }

                    e.Use(); // Consume the event so we don't accidentally select other objects while dragging
                }
            }

            sceneView.Repaint();
        }

        private void PaintGrass(Vector3 center, Vector3 normal)
        {
            bool addedGrass = false;

            for (int i = 0; i < density; i++)
            {
                Vector2 randomCircle = Random.insideUnitCircle * brushSize;
                Vector3 randomPos = center + new Vector3(randomCircle.x, 0, randomCircle.y);

                Ray ray = new Ray(randomPos + normal * 2f, -normal);
                if (Physics.Raycast(ray, out RaycastHit hit))
                {
                    Vector3 position = hit.point;

                    // Calculate Rotation
                    float randRotX = Random.Range(rotationXRange.x, rotationXRange.y);
                    float randRotY = Random.Range(rotationYRange.x, rotationYRange.y);
                    float randRotZ = Random.Range(rotationZRange.x, rotationZRange.y);

                    Quaternion rotation = Quaternion.FromToRotation(Vector3.up, hit.normal);
                    rotation *= Quaternion.Euler(randRotX, randRotY, randRotZ);

                    // Calculate Scale & Height
                    float randomBaseScale = grassScale * Random.Range(0.8f, 1.2f);
                    float randomHeightMult = Random.Range(heightRandomRange.x, heightRandomRange.y);

                    Vector3 scale = new Vector3(randomBaseScale, randomBaseScale * randomHeightMult, randomBaseScale);

                    Matrix4x4 matrix = Matrix4x4.TRS(position, rotation, scale);
                    targetInstancer.instances.Add(matrix);
                    addedGrass = true;
                }
            }

            if (addedGrass)
            {
                targetInstancer.UpdateBatches();
                EditorUtility.SetDirty(targetInstancer);
            }
        }

        private void EraseGrass(Vector3 center)
        {
            float sqrBrushSize = brushSize * brushSize;
            bool removedGrass = false;
            var instances = targetInstancer.instances;

            // Iterate backwards so we can remove elements safely without messing up the loop index
            for (int i = instances.Count - 1; i >= 0; i--)
            {
                Matrix4x4 matrix = instances[i];
                Vector3 position = new Vector3(matrix.m03, matrix.m13, matrix.m23);

                if ((position - center).sqrMagnitude <= sqrBrushSize)
                {
                    int lastIndex = instances.Count - 1;

                    // Overwrite the current element with the last element in the list
                    instances[i] = instances[lastIndex];

                    // Remove the now-duplicate last element (fast because it doesn't shift the array)
                    instances.RemoveAt(lastIndex);

                    removedGrass = true;
                }
            }

            if (removedGrass)
            {
                targetInstancer.UpdateBatches();
                EditorUtility.SetDirty(targetInstancer);
            }
        }
    }

}