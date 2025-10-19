using UnityEngine;

public static class MobileInput
{
    private static float h; // -1..1
    private static float v; // -1..1
    private static int writers;

    public static void ResetFrame()
    {
        h = 0f;
        v = 0f;
        writers = 0;
    }

    public static void AddHorizontal(float value)
    {
        h = Mathf.Clamp(h + value, -1f, 1f);
        writers++;
    }
    public static void AddVertical(float value)
    {
        v = Mathf.Clamp(v + value, -1f, 1f);
        writers++;
    }

    public static float GetHorizontal() => h;
    public static float GetVertical() => v;
    public static bool IsActive() => writers > 0;
}

