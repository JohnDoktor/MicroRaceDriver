using UnityEngine;

[CreateAssetMenu(fileName = "BuildInfo", menuName = "Build/Info", order = 0)]
public class BuildInfo : ScriptableObject
{
    public int buildNumber = 0;
    public string lastBuildUtc = "";
}

