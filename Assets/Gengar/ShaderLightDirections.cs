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

// One shared mode for every ShaderLightDirections component.
// This exists independently of the currently selected object's editor.
[InitializeOnLoad]
public static class ShaderLightDirectionsSceneMode
{
    private const string PreferenceKey =
        "ShaderLightDirections.GlobalEditMode";

    private const string MenuPath =
        "Tools/Shader Light Directions/Edit Light Directions";

    private static bool editingLights;
    private static bool ownsToolVisibility;
    private static bool previousToolsHidden;

    public static event System.Action ModeChanged;

    public static bool EditingLights
    {
        get => editingLights;
        set
        {
            if (editingLights == value)
                return;

            editingLights = value;
            EditorPrefs.SetBool(PreferenceKey, value);

            UpdateToolVisibility();
            ModeChanged?.Invoke();
            SceneView.RepaintAll();
        }
    }

    static ShaderLightDirectionsSceneMode()
    {
        // Start in Object mode unless the user previously chose otherwise.
        editingLights = EditorPrefs.GetBool(PreferenceKey, false);

        SceneView.duringSceneGui += DrawSceneToolbar;
        Selection.selectionChanged += OnSelectionChanged;
        EditorApplication.update += UpdateToolVisibility;

        AssemblyReloadEvents.beforeAssemblyReload += RestoreTools;
        EditorApplication.quitting += RestoreTools;
    }

    public static ShaderLightDirections SelectedComponent()
    {
        // Use standard Transform tools for multi-object selections.
        if (Selection.gameObjects.Length != 1)
            return null;

        GameObject selected = Selection.activeGameObject;

        if (selected == null || EditorUtility.IsPersistent(selected))
            return null;

        var component = selected.GetComponent<ShaderLightDirections>();

        return component != null && component.isActiveAndEnabled
            ? component
            : null;
    }

    private static void OnSelectionChanged()
    {
        UpdateToolVisibility();
        SceneView.RepaintAll();
    }

    private static void UpdateToolVisibility()
    {
        bool shouldHide =
            editingLights && SelectedComponent() != null;

        if (shouldHide && !ownsToolVisibility)
        {
            previousToolsHidden = Tools.hidden;
            Tools.hidden = true;
            ownsToolVisibility = true;
            SceneView.RepaintAll();
        }
        else if (!shouldHide && ownsToolVisibility)
        {
            RestoreTools();
            SceneView.RepaintAll();
        }
    }

    private static void RestoreTools()
    {
        if (!ownsToolVisibility)
            return;

        Tools.hidden = previousToolsHidden;
        ownsToolVisibility = false;
    }

    [MenuItem(MenuPath)]
    private static void ToggleFromMenu()
    {
        EditingLights = !EditingLights;
    }

    [MenuItem(MenuPath, true)]
    private static bool ValidateMenu()
    {
        Menu.SetChecked(MenuPath, EditingLights);
        return true;
    }

    private static void DrawSceneToolbar(SceneView sceneView)
    {
        Event evt = Event.current;

        // Avoid changing modes halfway through a handle drag.
        if (evt.type == EventType.KeyDown &&
            evt.keyCode == KeyCode.L &&
            evt.shift &&
            !evt.control &&
            !evt.command &&
            !evt.alt &&
            !EditorGUIUtility.editingTextField &&
            GUIUtility.hotControl == 0)
        {
            EditingLights = !EditingLights;
            evt.Use();
        }

        Rect panel = new Rect(
            12f,
            Mathf.Max(12f, sceneView.position.height - 110f),
            280f,
            74f);

        // Prevent clicking through the panel into scene objects.
        int panelControl = GUIUtility.GetControlID(
            734812,
            FocusType.Passive);

        if (evt.type == EventType.Layout &&
            panel.Contains(evt.mousePosition))
        {
            HandleUtility.AddControl(panelControl, 0f);
        }

        Handles.BeginGUI();

        GUI.Box(panel, GUIContent.none, EditorStyles.helpBox);
        GUI.BeginGroup(panel);

        GUI.Label(
            new Rect(10f, 5f, 260f, 18f),
            "Shader Light Controls   |   Shift + L",
            EditorStyles.boldLabel);

        int mode = GUI.Toolbar(
            new Rect(10f, 27f, 260f, 22f),
            EditingLights ? 1 : 0,
            new[] { "Object", "Light Directions" });

        if (mode != (EditingLights ? 1 : 0))
            EditingLights = mode == 1;

        string hint = !EditingLights
            ? "Normal Move / Rotate / Scale controls"
            : SelectedComponent() != null
                ? "Select an endpoint, then rotate its rings"
                : "Select an object with ShaderLightDirections";

        GUI.Label(
            new Rect(10f, 51f, 260f, 18f),
            hint,
            EditorStyles.miniLabel);

        GUI.EndGroup();
        Handles.EndGUI();

        if (evt.type == EventType.MouseDown &&
            panel.Contains(evt.mousePosition))
        {
            evt.Use();
        }
    }
}

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

    // Preserve the full orientation instead of rebuilding LookRotation
    // every redraw, which would discard roll and cause snapping.
    private readonly Quaternion[] handleRotations =
    {
        Quaternion.identity,
        Quaternion.identity,
        Quaternion.identity,
        Quaternion.identity
    };

    private readonly int[] endpointIds = new int[4];

    private int selectedDirection;
    private bool rotating;
    private int draggingControl;
    private Vector3 dragPoint;

    private void OnEnable()
    {
        Undo.undoRedoPerformed += RefreshPreview;
        ShaderLightDirectionsSceneMode.ModeChanged += OnModeChanged;
    }

    private void OnDisable()
    {
        Undo.undoRedoPerformed -= RefreshPreview;
        ShaderLightDirectionsSceneMode.ModeChanged -= OnModeChanged;
    }

    private void OnModeChanged()
    {
        rotating = false;
        draggingControl = 0;
        Repaint();
    }

    public override void OnInspectorGUI()
    {
        if (DrawDefaultInspector())
            RefreshPreview();

        EditorGUILayout.Space();

        bool editLights = EditorGUILayout.Toggle(
            "Edit Light Directions",
            ShaderLightDirectionsSceneMode.EditingLights);

        if (editLights != ShaderLightDirectionsSceneMode.EditingLights)
            ShaderLightDirectionsSceneMode.EditingLights = editLights;

        if (ShaderLightDirectionsSceneMode.EditingLights)
        {
            EditorGUI.BeginChangeCheck();

            selectedDirection = GUILayout.Toolbar(
                selectedDirection,
                DirectionNames);

            if (EditorGUI.EndChangeCheck())
                SceneView.RepaintAll();
        }

        EditorGUILayout.HelpBox(
            "Switch modes using the Scene-view panel or Shift + L.\n\n" +
            "Object: normal Transform controls.\n" +
            "Light Directions: drag endpoints or rotation rings.\n\n" +
            "The mode is shared by all objects and remembered.",
            MessageType.Info);
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

    private void OnSceneGUI()
    {
        var component = (ShaderLightDirections)target;

        // In Object mode, draw no custom handles at all.
        if (!ShaderLightDirectionsSceneMode.EditingLights ||
            ShaderLightDirectionsSceneMode.SelectedComponent() != component)
        {
            rotating = false;
            draggingControl = 0;
            return;
        }

        Vector3 origin = component.transform.position;

        float radius =
            HandleUtility.GetHandleSize(origin) *
            Mathf.Max(0.1f, component.arrowSize);

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

                if (selectedDirection == index)
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