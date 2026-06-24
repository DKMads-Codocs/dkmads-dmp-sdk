using System.Collections.Generic;
using UnityEngine;

namespace DKMads.DMP.Samples
{
    /// <summary>
    /// Minimal sample: init DMP, read shared identity, pass to your SSP ad SDK.
    /// Attach to a GameObject in the IdentityHandoff sample scene.
    /// </summary>
    public class IdentityHandoffSample : MonoBehaviour
    {
        [SerializeField] private string appKey = "dmp_live_your_key_here";

        private async void Start()
        {
            await DMP.Init(new DMPInitConfig
            {
                appKey = appKey,
                debug = true,
            });

            DMP.Identify("demo-user-1", new Dictionary<string, object>
            {
                { "plan", "premium" },
                { Demographics.DemographicAgeRangeKey, Demographics.AgeRangeFromDateOfBirth("1992-03-15") },
            });

            DMP.SetContext(new Dictionary<string, object> { { "screen", "main_menu" } });
            DMP.Track("screen_view");

            var identity = DMP.GetSharedIdentity();
            Debug.Log($"[DMP] devicePid={identity.devicePid} userPid={identity.userPid}");
            Debug.Log("[DMP] Pass identity.DevicePid to SSP linkDmpIdentity() at bid time.");

            // Example SSP handoff (pseudo):
            // SspSdk.LinkDmpIdentity(identity.devicePid, identity.userPid);
        }
    }
}
