using UnityEngine;

public static class MobileInputRuntime
{
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void EnsureResetter()
    {
        if (Object.FindObjectOfType<MobileInputFrameResetter>() == null)
        {
            new GameObject("MobileInputResetter").AddComponent<MobileInputFrameResetter>();
        }
    }
}

