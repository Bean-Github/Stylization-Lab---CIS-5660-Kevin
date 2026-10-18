using UnityEngine;

#if UNITY_EDITOR
using UnityEditor;
#endif

[ExecuteAlways]
[DisallowMultipleComponent]
public class ShaderLightDirections : MonoBehaviour
{
    public enum DirectionSpace { World, Object }

    [Header("Shader property reference names")]
    public string lightProperty = "_CustomLightDir";
    public string backlightProperty = "_CustomBacklitLightDir";
    public string midtoneProperty = "_CustomMidtoneLightDir";
    public string shadowProperty = "_CustomShadowLightDir";

    [Header("Space expected by the shader")]
    public DirectionSpace directionSpace = DirectionSpace.World;

    [Header("Unit directions")]
    public Vector3 lightDirection = Vector3.up;
    public Vector3 backlightDirection = Vector3.down;
    public Vector3 midtoneDirection = Vector3.right;
    public Vector3 shadowDirection = Vector3.forward;

    [Header("Scene gizmo")]
    [Min(0.1f)]
    public float arrowSize = 1f;

    private Renderer targetRenderer;
    private MaterialPropertyBlock block;
    private MaterialPropertyBlock originalBlock;
    private bool capturedOriginal;

    public static Vector3 Unit(Vector3 value, Vector3 fallback)
    {
        return value.sqrMagnitude > 0.000001f
            ? value.normalized
            : fallback;
    }

    private void OnEnable()
    {
        targetRenderer = GetComponent<Renderer>();

        if (targetRenderer == null)
            return;

        block = new MaterialPropertyBlock();
        originalBlock = new MaterialPropertyBlock();

        targetRenderer.GetPropertyBlock(originalBlock);
        capturedOriginal = true;

        Apply();
    }

    private void Update()
    {
        Apply();
    }

    private void OnValidate()
    {
        NormalizeDirections();
        arrowSize = Mathf.Max(0.1f, arrowSize);
    }

    private void NormalizeDirections()
    {
        lightDirection = Unit(lightDirection, Vector3.up);
        backlightDirection = Unit(backlightDirection, Vector3.down);
        midtoneDirection = Unit(midtoneDirection, Vector3.right);
        shadowDirection = Unit(shadowDirection, Vector3.forward);
    }

    public void Apply()
    {
        if (targetRenderer == null || block == null)
            return;

        NormalizeDirections();

        targetRenderer.GetPropertyBlock(block);

        SetDirection(lightProperty, lightDirection);
        SetDirection(backlightProperty, backlightDirection);
        SetDirection(midtoneProperty, midtoneDirection);
        SetDirection(shadowProperty, shadowDirection);

        targetRenderer.SetPropertyBlock(block);
    }

    private void SetDirection(string propertyName, Vector3 direction)
    {
        if (string.IsNullOrEmpty(propertyName))
            return;

        block.SetVector(propertyName, new Vector4(
            direction.x,
            direction.y,
            direction.z,
            0f));
    }

    private void OnDisable()
    {
        if (targetRenderer != null && capturedOriginal)
        {
            targetRenderer.SetPropertyBlock(
                originalBlock.isEmpty ? null : originalBlock);
        }

        capturedOriginal = false;
    }

    public Vector3 ToWorldDirection(Vector3 direction)
    {
        direction = Unit(direction, Vector3.up);

        return directionSpace == DirectionSpace.Object
            ? transform.TransformDirection(direction).normalized
            : direction;
    }

    public Vector3 FromWorldDirection(Vector3 direction)
    {
        return directionSpace == DirectionSpace.Object
            ? transform.InverseTransformDirection(direction).normalized
            : direction.normalized;
    }
}

#if UNITY_EDITOR

[CustomEditor(typeof(ShaderLightDirections))]
public class ShaderLightDirectionsEditor : Editor
{
    private static readonly string[] DirectionNames =
    {
        "Light", "Backlight", "Midtone", "Shadow"
    };

    private static readonly Color[] DirectionColors =
    {
        new Color(1f, 0.8f, 0.15f),
        new Color(0.15f, 0.85f, 1f),
        new Color(1f, 0.35f, 0.7f),
        new Color(0.65f, 0.4f, 1f)
    };

    // Retain full rotations, including roll, across redraws.
    // Rebuilding these using LookRotation every frame causes jumps.
    private readonly Quaternion[] handleRotations =
    {
        Quaternion.identity,
        Quaternion.identity,
        Quaternion.identity,
        Quaternion.identity
    };

    private readonly int[] endpointIds = new int[4];

    private int selectedDirection;
    private bool showRotation = true;
    private bool rotating;

    private int draggingControl;
    private Vector3 dragPoint;

    private bool hidTransformTools;
    private bool previousToolsHidden;

    private void OnEnable()
    {
        Undo.undoRedoPerformed += RefreshPreview;
    }

    private void OnDisable()
    {
        Undo.undoRedoPerformed -= RefreshPreview;
        RestoreTransformTools();
    }

    public override void OnInspectorGUI()
    {
        if (DrawDefaultInspector())
            RefreshPreview();

        EditorGUILayout.Space();
        EditorGUILayout.LabelField(
            "Direction Controls",
            EditorStyles.boldLabel);

        EditorGUI.BeginChangeCheck();

        showRotation = EditorGUILayout.Toggle(
            "Show Rotation Rings",
            showRotation);

        selectedDirection = GUILayout.Toolbar(
            selectedDirection,
            DirectionNames);

        if (EditorGUI.EndChangeCheck())
            RefreshPreview();

        EditorGUILayout.HelpBox(
            "Click or drag an endpoint to select its direction.\n" +
            "Use the rotation rings to rotate the selected direction.\n\n" +
            "Yellow = Light\n" +
            "Cyan = Backlight\n" +
            "Pink = Midtone\n" +
            "Purple = Shadow\n\n" +
            "All four endpoints remain draggable. " +
            "Shader vectors always have length 1.\n\n" +
            "Turn off Show Rotation Rings to use the object's " +
            "normal Transform tools.",
            MessageType.Info);

        UpdateTransformTools();
    }

    private void RefreshPreview()
    {
        if (target == null)
            return;

        var component = (ShaderLightDirections)target;

        if (component.isActiveAndEnabled)
            component.Apply();

        Repaint();
        SceneView.RepaintAll();
    }

    private void UpdateTransformTools()
    {
        var component = target as ShaderLightDirections;

        bool shouldHide =
            component != null &&
            component.isActiveAndEnabled &&
            showRotation &&
            Selection.gameObjects.Length == 1 &&
            Selection.activeGameObject == component.gameObject;

        if (shouldHide && !hidTransformTools)
        {
            previousToolsHidden = Tools.hidden;
            Tools.hidden = true;
            hidTransformTools = true;
        }
        else if (!shouldHide)
        {
            RestoreTransformTools();
        }
    }

    private void RestoreTransformTools()
    {
        if (!hidTransformTools)
            return;

        Tools.hidden = previousToolsHidden;
        hidTransformTools = false;
    }

    private void OnSceneGUI()
    {
        var component = (ShaderLightDirections)target;

        UpdateTransformTools();

        if (!component.isActiveAndEnabled)
            return;

        Vector3 origin = component.transform.position;

        float radius =
            HandleUtility.GetHandleSize(origin) *
            Mathf.Max(0.1f, component.arrowSize);

        // Allocate the same controls in the same order on each event.
        for (int i = 0; i < endpointIds.Length; i++)
        {
            endpointIds[i] = GUIUtility.GetControlID(
                187300 + i,
                FocusType.Passive);
        }

        var previousDepthTest = Handles.zTest;

        try
        {
            Handles.zTest =
                UnityEngine.Rendering.CompareFunction.Always;

            using (new Handles.DrawingScope(Matrix4x4.identity))
            {
                for (int i = 0; i < DirectionNames.Length; i++)
                {
                    DrawEndpoint(
                        component,
                        i,
                        endpointIds[i],
                        origin,
                        radius * (1f + i * 0.25f));
                }

                if (showRotation)
                    DrawRotationControl(component, origin);
            }
        }
        finally
        {
            Handles.zTest = previousDepthTest;
        }

        if (GUIUtility.hotControl == 0)
        {
            rotating = false;

            if (draggingControl != 0)
            {
                draggingControl = 0;
                SceneView.RepaintAll();
            }
        }
    }

    private void DrawEndpoint(
        ShaderLightDirections component,
        int index,
        int controlId,
        Vector3 origin,
        float displayLength)
    {
        Vector3 worldDirection = component.ToWorldDirection(
            GetDirection(component, index));

        bool isDragging =
            draggingControl == controlId &&
            GUIUtility.hotControl == controlId;

        // Keep the actual dragged point under the cursor.
        // Normalize only the direction written to the component.
        Vector3 point = isDragging
            ? dragPoint
            : origin + worldDirection * displayLength;

        float pointSize =
            HandleUtility.GetHandleSize(point) * 0.085f;

        using (new Handles.DrawingScope(DirectionColors[index]))
        {
            EditorGUI.BeginChangeCheck();

            Vector3 movedPoint = Handles.FreeMoveHandle(
                controlId,
                point,
                pointSize,
                Vector3.zero,
                Handles.SphereHandleCap);

            bool changed = EditorGUI.EndChangeCheck();

            if (GUIUtility.hotControl == controlId)
            {
                draggingControl = controlId;
                dragPoint = movedPoint;

                if (selectedDirection != index)
                {
                    selectedDirection = index;
                    Repaint();
                    SceneView.RepaintAll();
                }
            }

            if (changed)
            {
                Vector3 offset = movedPoint - origin;

                // There is no valid direction at the origin.
                if (offset.sqrMagnitude > 0.000001f)
                    WriteWorldDirection(component, index, offset);

                point = movedPoint;
            }

            if (Event.current.type == EventType.Repaint)
            {
                Handles.DrawAAPolyLine(
                    selectedDirection == index ? 5f : 3f,
                    origin,
                    point);

                Vector3 labelOffset =
                    Vector3.up *
                    HandleUtility.GetHandleSize(point) * 0.12f;

                string label = DirectionNames[index];

                if (selectedDirection == index && showRotation)
                    label += " [Rotate]";

                Handles.Label(point + labelOffset, label);
            }
        }
    }

    private void DrawRotationControl(
        ShaderLightDirections component,
        Vector3 origin)
    {
        int index = selectedDirection;

        // Match Inspector edits, endpoint changes, Undo/Redo, and
        // object rotation without throwing away the handle's roll.
        // Never rebuild its orientation during a rotation drag.
        if (!rotating)
        {
            Vector3 desiredDirection = component.ToWorldDirection(
                GetDirection(component, index));

            Vector3 currentDirection =
                handleRotations[index] * Vector3.forward;

            handleRotations[index] =
                Quaternion.FromToRotation(
                    currentDirection,
                    desiredDirection) *
                handleRotations[index];
        }

        int hotControlBefore = GUIUtility.hotControl;

        EditorGUI.BeginChangeCheck();

        Quaternion newRotation = Handles.RotationHandle(
            handleRotations[index],
            origin);

        bool changed = EditorGUI.EndChangeCheck();

        if (hotControlBefore == 0 && GUIUtility.hotControl != 0)
            rotating = true;

        if (changed)
        {
            // Preserve the complete returned rotation.
            handleRotations[index] = newRotation;

            WriteWorldDirection(
                component,
                index,
                newRotation * Vector3.forward);
        }

        if (GUIUtility.hotControl == 0)
            rotating = false;
    }

    private void WriteWorldDirection(
        ShaderLightDirections component,
        int index,
        Vector3 worldDirection)
    {
        if (worldDirection.sqrMagnitude <= 0.000001f)
            return;

        Vector3 direction = component.FromWorldDirection(
            worldDirection.normalized);

        Undo.RecordObject(
            component,
            "Edit " + DirectionNames[index] + " Direction");

        switch (index)
        {
            case 0:
                component.lightDirection = direction;
                break;

            case 1:
                component.backlightDirection = direction;
                break;

            case 2:
                component.midtoneDirection = direction;
                break;

            case 3:
                component.shadowDirection = direction;
                break;
        }

        PrefabUtility.RecordPrefabInstancePropertyModifications(
            component);

        EditorUtility.SetDirty(component);
        component.Apply();

        Repaint();
        SceneView.RepaintAll();
    }

    private static Vector3 GetDirection(
        ShaderLightDirections component,
        int index)
    {
        switch (index)
        {
            case 0:
                return component.lightDirection;

            case 1:
                return component.backlightDirection;

            case 2:
                return component.midtoneDirection;

            default:
                return component.shadowDirection;
        }
    }
}

#endif