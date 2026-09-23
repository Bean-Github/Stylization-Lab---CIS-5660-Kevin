inline float2 randomVector(float2 UV, float offset)
{
    float2x2 m = float2x2(15.27, 47.63, 99.41, 89.98);
    UV = frac(sin(mul(UV, m)) * 46839.32);
    return float2(sin(UV.y * +offset) * 0.5 + 0.5, cos(UV.x * offset) * 0.5 + 0.5);
}

// Based on code by Inigo Quilez: https://iquilezles.org/articles/voronoilines/
void CustomVoronoi_float(float2 UV, float AngleOffset, float CellDensity, out float DistFromCenter, out float DistFromEdge, out float Area)
{
    int2 cell = floor(UV * CellDensity);
    float2 posInCell = frac(UV * CellDensity);

    DistFromCenter = 8.0f;
    float2 closestOffset;
    Area = 0.0f;
    for (int y = -1; y <= 1; ++y)
    {
        for (int x = -1; x <= 1; ++x)
        {
            int2 cellToCheck = int2(x, y);
            
            float2x2 m = float2x2(15.27, 47.63, 99.41, 89.98);
            float2 UV = frac(sin(mul(cell + cellToCheck, m)) * 46839.32);
            float2 randomVec = float2(sin(UV.y * +AngleOffset) * 0.5 + 0.5, cos(UV.x * AngleOffset) * 0.5 + 0.5);
            

            float2 cellOffset = float2(cellToCheck) - posInCell + randomVec;

            float distToPoint = dot(cellOffset, cellOffset);

            if (distToPoint < DistFromCenter)
            {
                DistFromCenter = distToPoint;
                closestOffset = cellOffset;
                
                Area = randomVec.x;
            }
        }
    }

    DistFromCenter = sqrt(DistFromCenter);

    DistFromEdge = 8.0f;

    for (int y = -1; y <= 1; ++y)
    {
        for (int x = -1; x <= 1; ++x)
        {
            int2 cellToCheck = int2(x, y);
            
            float2x2 m = float2x2(15.27, 47.63, 99.41, 89.98);
            float2 UV = frac(sin(mul(cell + cellToCheck, m)) * 46839.32);
            float2 randomVec = float2(sin(UV.y * +AngleOffset) * 0.5 + 0.5, cos(UV.x * AngleOffset) * 0.5 + 0.5);
            float2 cellOffset = float2(cellToCheck) - posInCell + randomVec;

            float distToEdge = dot(0.5f * (closestOffset + cellOffset), normalize(cellOffset - closestOffset));

            DistFromEdge = min(DistFromEdge, distToEdge);
        }
    }
}
