using UnityEngine;

[DefaultExecutionOrder(-10000)]
public class MobileInputFrameResetter : MonoBehaviour
{
    void Update()
    {
        MobileInput.ResetFrame();
    }
}

