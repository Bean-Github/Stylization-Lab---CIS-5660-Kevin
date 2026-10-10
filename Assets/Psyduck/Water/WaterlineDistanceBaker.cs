using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

// One-time editor bake for Custom/ThickRefractiveWaterCurvedFixed.
// UV4.x = distance in WORLD METERS along either top or sides, from their boundary.
// UV4.y = validity/region: 3 = top, 2 = sides; 0 = unbaked.
// Splits vertices only where the top/side region changes; the classification
// therefore exactly matches the boundary used to generate the distance field.
[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class WaterlineDistanceBaker : MonoBehaviour
{
    [Tooltip("Optional original mesh. Stored on first bake so rebaking won't compound splits.")]
    public Mesh sourceMesh;

    [Tooltip("If >= 0, this submesh is the TOP. Use a separate Blender material ID to mark the top; this is the most reliable option.")]
    public int topSubmeshIndex = -1;

    [Tooltip("Used only if Top Submesh Index is -1. Classifies local-space triangle normals against local +Y. Also reads material's _TopNormalThreshold when present.")]
    [Range(-1, 1)] public float topNormalThreshold = 0.4f;

    [Min(0.000001f)] public float weldTolerance = 0.0001f;

    struct Edge : IEquatable<Edge>
    {
        public int a, b;
        public Edge(int x, int y) { a = Math.Min(x, y); b = Math.Max(x, y); }
        public bool Equals(Edge other) => a == other.a && b == other.b;
        public override bool Equals(object obj) => obj is Edge edge && Equals(edge);
        public override int GetHashCode() { unchecked { return (a * 397) ^ b; } }
    }

    struct PositionKey : IEquatable<PositionKey>
    {
        public long x, y, z;
        public PositionKey(Vector3 p, double reciprocalTolerance)
        {
            x = (long)Math.Round(p.x * reciprocalTolerance);
            y = (long)Math.Round(p.y * reciprocalTolerance);
            z = (long)Math.Round(p.z * reciprocalTolerance);
        }
        public bool Equals(PositionKey other) => x == other.x && y == other.y && z == other.z;
        public override bool Equals(object obj) => obj is PositionKey key && Equals(key);
        public override int GetHashCode()
        {
            unchecked { return (x.GetHashCode() * 397 ^ y.GetHashCode()) * 397 ^ z.GetHashCode(); }
        }
    }

    struct Link
    {
        public int target;
        public float cost;
        public Link(int to, float distance) { target = to; cost = distance; }
    }

    struct Pending
    {
        public int vertex;
        public float distance;
        public Pending(int v, float d) { vertex = v; distance = d; }
    }

    class Heap
    {
        readonly List<Pending> nodes = new List<Pending>();
        public int Count => nodes.Count;
        public void Push(Pending value)
        {
            int i = nodes.Count;
            nodes.Add(value);
            while (i > 0)
            {
                int p = (i - 1) / 2;
                if (nodes[p].distance <= value.distance) break;
                nodes[i] = nodes[p]; i = p;
            }
            nodes[i] = value;
        }
        public Pending Pop()
        {
            Pending first = nodes[0];
            Pending last = nodes[nodes.Count - 1];
            nodes.RemoveAt(nodes.Count - 1);
            if (nodes.Count == 0) return first;
            int i = 0;
            while (2 * i + 1 < nodes.Count)
            {
                int child = 2 * i + 1;
                if (child + 1 < nodes.Count && nodes[child + 1].distance < nodes[child].distance) child++;
                if (last.distance <= nodes[child].distance) break;
                nodes[i] = nodes[child]; i = child;
            }
            nodes[i] = last;
            return first;
        }
    }

    static void AddEdge(int a, int b, byte kind,
        Dictionary<Edge, byte> edgeTypes,
        List<Link>[] topGraph, List<Link>[] sideGraph, Vector3[] points)
    {
        if (a == b) return;
        Edge edge = new Edge(a, b);
        byte old;
        edgeTypes.TryGetValue(edge, out old);
        edgeTypes[edge] = (byte)(old | kind);
        float d = Vector3.Distance(points[a], points[b]);
        List<Link>[] graph = kind == 1 ? topGraph : sideGraph;
        graph[a].Add(new Link(b, d));
        graph[b].Add(new Link(a, d));
    }

    static float[] Distances(List<Link>[] graph, HashSet<int> seeds)
    {
        float[] dist = new float[graph.Length];
        for (int i = 0; i < dist.Length; i++) dist[i] = float.PositiveInfinity;
        Heap heap = new Heap();
        foreach (int v in seeds) { dist[v] = 0; heap.Push(new Pending(v, 0)); }
        while (heap.Count > 0)
        {
            Pending current = heap.Pop();
            if (current.distance > dist[current.vertex]) continue;
            foreach (Link link in graph[current.vertex])
            {
                float candidate = current.distance + link.cost;
                if (candidate >= dist[link.target]) continue;
                dist[link.target] = candidate;
                heap.Push(new Pending(link.target, candidate));
            }
        }
        return dist;
    }

    [ContextMenu("Bake Fixed Curved Waterline")]
    public void Bake()
    {
        MeshFilter mf = GetComponent<MeshFilter>();
        MeshRenderer mr = GetComponent<MeshRenderer>();
        if (sourceMesh == null) sourceMesh = mf.sharedMesh;
        Mesh src = sourceMesh;
        if (src == null || !src.isReadable)
        {
            Debug.LogError("Waterline bake: assign a source mesh with Read/Write enabled.", this);
            return;
        }
        if (topSubmeshIndex >= src.subMeshCount)
        {
            Debug.LogError("Waterline bake: topSubmeshIndex exceeds the mesh's submesh count.", this);
            return;
        }

        float cutoff = topNormalThreshold;
        if (mr.sharedMaterial != null && mr.sharedMaterial.HasProperty("_TopNormalThreshold"))
            cutoff = mr.sharedMaterial.GetFloat("_TopNormalThreshold");

        Vector3[] vertices = src.vertices;
        Vector3[] normals = src.normals;
        Vector4[] tangents = src.tangents;
        Color[] colors = src.colors;
        bool hasNormals = normals.Length == vertices.Length;
        bool hasTangents = tangents.Length == vertices.Length;
        bool hasColors = colors.Length == vertices.Length;

        var srcUVs = new List<Vector4>[8];
        for (int channel = 0; channel < 8; channel++)
        {
            if (channel == 3) continue; // Reserved for our baked waterline.
            srcUVs[channel] = new List<Vector4>();
            src.GetUVs(channel, srcUVs[channel]);
            if (srcUVs[channel].Count != vertices.Length) srcUVs[channel].Clear();
        }

        // Weld solely for the distance graph, not for rendering normals or UV seams.
        int[] welded = new int[vertices.Length];
        var uniquePoints = new List<Vector3>();
        var weldLookup = new Dictionary<PositionKey, int>();
        double invTolerance = 1.0 / Math.Max(1e-6, weldTolerance);
        for (int i = 0; i < vertices.Length; i++)
        {
            PositionKey key = new PositionKey(vertices[i], invTolerance);
            int id;
            if (!weldLookup.TryGetValue(key, out id))
            {
                id = uniquePoints.Count;
                weldLookup.Add(key, id);
                uniquePoints.Add(transform.TransformPoint(vertices[i]));
            }
            welded[i] = id;
        }
        Vector3[] points = uniquePoints.ToArray();
        int weldedCount = points.Length;
        var topGraph = new List<Link>[weldedCount];
        var sideGraph = new List<Link>[weldedCount];
        for (int i = 0; i < weldedCount; i++)
        {
            topGraph[i] = new List<Link>();
            sideGraph[i] = new List<Link>();
        }
        var edgeTypes = new Dictionary<Edge, byte>();
        var trianglesBySubmesh = new List<(int a, int b, int c, bool top)>[src.subMeshCount];
        int tops = 0, sides = 0;
        for (int submesh = 0; submesh < src.subMeshCount; submesh++)
        {
            trianglesBySubmesh[submesh] = new List<(int, int, int, bool)>();
            int[] indices = src.GetTriangles(submesh);
            for (int t = 0; t + 2 < indices.Length; t += 3)
            {
                int a = indices[t], b = indices[t + 1], c = indices[t + 2];
                Vector3 geometricNormal = Vector3.Cross(vertices[b] - vertices[a], vertices[c] - vertices[a]);
                if (geometricNormal.sqrMagnitude < 1e-15f) continue;
                bool top = topSubmeshIndex >= 0
                    ? submesh == topSubmeshIndex
                    : geometricNormal.normalized.y > cutoff;
                trianglesBySubmesh[submesh].Add((a, b, c, top));
                if (top) tops++; else sides++;
                byte kind = top ? (byte)1 : (byte)2;
                AddEdge(welded[a], welded[b], kind, edgeTypes, topGraph, sideGraph, points);
                AddEdge(welded[b], welded[c], kind, edgeTypes, topGraph, sideGraph, points);
                AddEdge(welded[c], welded[a], kind, edgeTypes, topGraph, sideGraph, points);
            }
        }
        if (tops == 0 || sides == 0)
        {
            Debug.LogError("Waterline bake: mesh must have both top and side triangles. Adjust the top threshold or choose a top submesh.", this);
            return;
        }
        var seeds = new HashSet<int>();
        foreach (KeyValuePair<Edge, byte> kv in edgeTypes)
        {
            if (kv.Value != 3) continue; // This edge borders top AND side.
            seeds.Add(kv.Key.a);
            seeds.Add(kv.Key.b);
        }
        if (seeds.Count == 0)
        {
            Debug.LogError("Waterline bake: no shared top/side edges. Ensure the top and sides are connected, or weld the mesh boundary.", this);
            return;
        }
        float[] topDist = Distances(topGraph, seeds);
        float[] sideDist = Distances(sideGraph, seeds);

        // Split ONLY vertex indices used by BOTH regions so that UV4.y is a
        // per-triangle classification, NEVER an interpolated 0..1 guess.
        var mapping = new Dictionary<long, int>();
        var newVertices = new List<Vector3>();
        var newNormals = new List<Vector3>();
        var newTangents = new List<Vector4>();
        var newColors = new List<Color>();
        var newUV = new List<Vector4>[8];
        for (int channel = 0; channel < 8; channel++)
            if (channel != 3) newUV[channel] = new List<Vector4>();
        var waterlineUV = new List<Vector2>();
        var outputIndices = new List<int>[src.subMeshCount];
        int disconnected = 0;

        for (int submesh = 0; submesh < src.subMeshCount; submesh++)
        {
            outputIndices[submesh] = new List<int>();
            foreach (var triangle in trianglesBySubmesh[submesh])
            {
                int[] corners = { triangle.a, triangle.b, triangle.c };
                int region = triangle.top ? 1 : 0;
                for (int j = 0; j < 3; j++)
                {
                    int oldVertex = corners[j];
                    long key = ((long)oldVertex << 1) | (uint)region;
                    int newIndex;
                    if (!mapping.TryGetValue(key, out newIndex))
                    {
                        newIndex = newVertices.Count;
                        mapping.Add(key, newIndex);
                        newVertices.Add(vertices[oldVertex]);
                        if (hasNormals) newNormals.Add(normals[oldVertex]);
                        if (hasTangents) newTangents.Add(tangents[oldVertex]);
                        if (hasColors) newColors.Add(colors[oldVertex]);
                        for (int channel = 0; channel < 8; channel++)
                            if (channel != 3 && srcUVs[channel].Count > 0)
                                newUV[channel].Add(srcUVs[channel][oldVertex]);
                        float d = triangle.top ? topDist[welded[oldVertex]] : sideDist[welded[oldVertex]];
                        if (float.IsPositiveInfinity(d)) { d = 1000000f; disconnected++; }
                        waterlineUV.Add(new Vector2(d, region == 1 ? 3f : 2f));
                    }
                    outputIndices[submesh].Add(newIndex);
                }
            }
        }

        Mesh baked = new Mesh();
        baked.name = src.name + "_CurvedFixed";
        baked.indexFormat = newVertices.Count > 65535 ? IndexFormat.UInt32 : IndexFormat.UInt16;
        baked.SetVertices(newVertices);
        if (hasNormals) baked.SetNormals(newNormals);
        if (hasTangents) baked.SetTangents(newTangents);
        if (hasColors) baked.SetColors(newColors);
        for (int channel = 0; channel < 8; channel++)
            if (channel != 3 && newUV[channel].Count == newVertices.Count)
                baked.SetUVs(channel, newUV[channel]);
        baked.SetUVs(3, waterlineUV);
        baked.subMeshCount = src.subMeshCount;
        for (int submesh = 0; submesh < src.subMeshCount; submesh++)
            baked.SetTriangles(outputIndices[submesh], submesh, true);
        if (!hasNormals) baked.RecalculateNormals();
        baked.RecalculateBounds();

#if UNITY_EDITOR
        if (!Application.isPlaying)
        {
            const string folder = "Assets/GeneratedWaterMeshes";
            if (!UnityEditor.AssetDatabase.IsValidFolder(folder))
                UnityEditor.AssetDatabase.CreateFolder("Assets", "GeneratedWaterMeshes");
            string path = UnityEditor.AssetDatabase.GenerateUniqueAssetPath(
                folder + "/" + baked.name.Replace('/', '_').Replace('\\', '_') + ".asset");
            UnityEditor.AssetDatabase.CreateAsset(baked, path);
            UnityEditor.AssetDatabase.SaveAssets();
        }
#endif
        mf.sharedMesh = baked;
        MaterialPropertyBlock props = new MaterialPropertyBlock();
        mr.GetPropertyBlock(props);
        props.SetVector("_VolumeMinOS", baked.bounds.min);
        props.SetVector("_VolumeMaxOS", baked.bounds.max);
        mr.SetPropertyBlock(props);

        Debug.Log($"Waterline bake FIXED: top tris={tops}, side tris={sides}, " +
                  $"shared rim vertices={seeds.Count}, top/side split verts={newVertices.Count}, " +
                  $"disconnected verts={disconnected}. " +
                  "UV4.x=distance, UV4.y=3 top/2 side. Set Waterline Debug View=Regions to inspect. " +
                  "Rebake if you change threshold, submesh, or scale.", this);
        if (seeds.Count > weldedCount * 0.35f)
            Debug.LogWarning("An unusually large fraction of vertices are rim seeds. " +
                "The top/side threshold may be creating boundaries across the entire mesh. " +
                "Use Debug View=Regions or explicitly choose a Top Submesh Index.", this);
    }
}
