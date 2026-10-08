#ifndef GRASS_DEFORMATION_INCLUDED
#define GRASS_DEFORMATION_INCLUDED

struct PlayerStep
{
    float3 position;
    float time;
};

#if !defined(SHADERGRAPH_PREVIEW)
StructuredBuffer<PlayerStep> _PlayerStepsBuffer;
#endif

void GetGrassBend_float(float3 WorldPos, float CurrentTime, float Radius, float RecoveryTime, out float BendAmount, out float3 DebugColor)
{
    BendAmount = 0.0;
    
#if defined(SHADERGRAPH_PREVIEW)
    DebugColor = float3(0, 0, 0);
#else
    float minDist = 9999.0;
    float maxTime = -9999.0;

    // We do both the debug tracking and the bending math in a single loop
    for (int i = 0; i < 32; i++)
    {
        PlayerStep pStep = _PlayerStepsBuffer[i];
        
        // 1. Calculate 2D distance for both systems
        float dist = distance(WorldPos, pStep.position);
        
        // 2. Track data for the debug visualization
        minDist = min(minDist, dist);
        maxTime = max(maxTime, pStep.time);
        
        // 3. Calculate the actual bending physics
        float age = CurrentTime - pStep.time;
        
        // Is the step newer than our recovery time?
        if (age > 0.0 && age < RecoveryTime)
        {
            // Is the grass inside the player's radius?
            if (dist < Radius)
            {
                float distanceIntensity = 1.0 - (dist / Radius);
                float timeIntensity = 1.0 - (age / RecoveryTime);
                float totalIntensity = distanceIntensity * timeIntensity;
                
                BendAmount = max(BendAmount, totalIntensity);
            }
        }
    }
    
    // --- DEBUG COLORING ---
    // The history of the steps will glow white. 
    // The active bending area will overlay in bright RED.
    float glow = saturate(1.0 - (minDist / 5.0));
    
    if (maxTime < 0.0)
    {
        DebugColor = float3(0, 0, 1); // Solid Blue (Error)
    }
    else
    {
        // Mix the white trail with the red bend amount!
        DebugColor = float3(glow + BendAmount, glow - BendAmount, glow - BendAmount);
    }
#endif
}
#endif