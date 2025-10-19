using UnityEngine;

// Simple parallax follow: moves relative to the target with a multiplier to exaggerate motion.
// Useful for a foreground/rooftop camera layer to enhance the 3D illusion.
public class ParallaxFollow : MonoBehaviour
{
    public Transform target;
    public Vector3 baseOffset = new Vector3(0f, 30f, -18f);
    [Range(0.5f, 2.0f)] public float parallaxFactor = 1.2f; // >1 moves more than main cam
    public float followLerp = 12f;

    private Vector3 origin;

    void Awake()
    {
        origin = Vector3.zero;
    }

    void LateUpdate()
    {
        if (target == null) return;
        var t = new Vector3(target.position.x, 0f, target.position.z);
        var desired = origin + baseOffset + (t - origin) * parallaxFactor;
        transform.position = Vector3.Lerp(transform.position, desired, 1f - Mathf.Exp(-followLerp * Time.deltaTime));
    }
}

