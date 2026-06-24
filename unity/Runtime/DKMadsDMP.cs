using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using UnityEngine;

namespace DKMads.DMP
{
    [Serializable]
    public class DMPConsent
    {
        public bool? gdprApplies;
        public string tcfString;
        public string usPrivacy;
        public Dictionary<string, bool> purposes;
    }

    [Serializable]
    public class DMPInitConfig
    {
        public string appKey;
        public string workspaceId;
        public string propertyId;
        public string apiHost = "https://ingest.dmp.dkmads.com";
        public int flushIntervalMs = 10000;
        public int batchSize = 20;
        public bool collectDeviceIds = true;
        public bool debug;
    }

    [Serializable]
    public class DMPSharedIdentity
    {
        public string devicePid;
        public string userPid;

        public DMPSharedIdentity(string devicePid, string userPid = null)
        {
            this.devicePid = devicePid;
            this.userPid = userPid;
        }
    }

    public static class DMP
    {
        private static DMPInitConfig _config;
        private static string _workspaceId;
        private static string _propertyId;
        private static readonly List<Dictionary<string, object>> _queue = new();
        private static readonly Dictionary<string, object> _traits = new();
        private static readonly Dictionary<string, object> _context = new();
        private static string _userId;
        private static bool _optedOut;
        private static DMPConsent _consent;
        private static readonly HttpClient _http = new();
        private static float _flushTimer;

        private static bool CanCollect()
        {
            if (_optedOut) return false;
            if (!string.IsNullOrEmpty(_consent?.usPrivacy) && _consent.usPrivacy.Length >= 3 && _consent.usPrivacy[2] == 'Y')
                return false;
            if (_consent?.gdprApplies == true)
                return _consent.purposes != null && _consent.purposes.TryGetValue("1", out var p1) && p1;
            return true;
        }

        public static async Task Init(DMPInitConfig config)
        {
            _config = config;
            _workspaceId = config.workspaceId;
            _propertyId = config.propertyId;
            _optedOut = PlayerPrefs.GetInt("dkmads_dmp_opted_out", 0) == 1;

            if (string.IsNullOrEmpty(_workspaceId)) await ResolveBridge();
            await SyncOptOutFromServer();

            _flushTimer = config.flushIntervalMs / 1000f;
            Track("sdk_initialized", new Dictionary<string, object> { { "platform", GetPlatform() } });
        }

        public static void Update()
        {
            if (_config == null || !CanCollect() || _queue.Count == 0) return;
            _flushTimer -= Time.unscaledDeltaTime;
            if (_flushTimer <= 0)
            {
                _flushTimer = _config.flushIntervalMs / 1000f;
                _ = Flush();
            }
        }

        public static void Identify(string userId, Dictionary<string, object> traits = null)
        {
            if (!CanCollect()) return;
            _userId = userId;
            if (traits != null) foreach (var kv in traits) _traits[kv.Key] = kv.Value;
            Enqueue("identify", new Dictionary<string, object> { { "userId", userId } });
        }

        public static void Track(string eventName, Dictionary<string, object> properties = null)
        {
            if (!CanCollect()) return;
            Enqueue(eventName, properties);
        }

        public static void SetTrait(string key, object value)
        {
            if (!CanCollect()) return;
            _traits[key] = value;
        }

        public static void SetTraits(Dictionary<string, object> traits)
        {
            if (!CanCollect()) return;
            foreach (var kv in traits) _traits[kv.Key] = kv.Value;
        }

        public static void SetContext(Dictionary<string, object> context)
        {
            if (!CanCollect()) return;
            foreach (var kv in context) _context[kv.Key] = kv.Value;
        }

        public static async Task SetConsent(DMPConsent consent)
        {
            _consent = consent;
            var body = JsonSerializer.Serialize(new
            {
                gdprApplies = consent.gdprApplies,
                tcfString = consent.tcfString,
                usPrivacy = consent.usPrivacy,
                purposes = consent.purposes,
                devicePid = GetDevicePid(),
            });
            var req = new HttpRequestMessage(HttpMethod.Post, $"{_config.apiHost}/v1/ingest/consent");
            req.Headers.Add("X-DMP-App-Key", _config.appKey);
            req.Content = new StringContent(body, Encoding.UTF8, "application/json");
            await _http.SendAsync(req);
        }

        public static void OptOut()
        {
            _optedOut = true;
            PlayerPrefs.SetInt("dkmads_dmp_opted_out", 1);
            PlayerPrefs.Save();
            _ = SyncOptOutToServer();
            Reset();
        }

        public static void Reset() { _userId = null; _traits.Clear(); _context.Clear(); _queue.Clear(); }

        public static string GetDevicePid() => ResolveDevicePid();

        public static string GetUserPid() => _userId;

        public static DMPSharedIdentity GetSharedIdentity() =>
            new DMPSharedIdentity(ResolveDevicePid(), _userId);

        public static async Task Flush()
        {
            if (_queue.Count == 0 || _config == null || !CanCollect()) return;
            var events = _queue.GetRange(0, Math.Min(_queue.Count, _config.batchSize));
            _queue.RemoveRange(0, events.Count);
            var body = JsonSerializer.Serialize(new { workspaceId = _workspaceId, propertyId = _propertyId, sdkVersion = "0.1.0", events });
            var req = new HttpRequestMessage(HttpMethod.Post, $"{_config.apiHost}/v1/ingest/batch");
            req.Headers.Add("X-DMP-App-Key", _config.appKey);
            req.Content = new StringContent(body, Encoding.UTF8, "application/json");
            await _http.SendAsync(req);
        }

        private static async Task ResolveBridge()
        {
            var res = await _http.GetStringAsync($"{_config.apiHost}/v1/bridge/resolve?app_key={_config.appKey}");
            using var doc = JsonDocument.Parse(res);
            _workspaceId = doc.RootElement.GetProperty("workspaceId").GetString();
            _propertyId = doc.RootElement.GetProperty("propertyId").GetString();
        }

        private static async Task SyncOptOutFromServer()
        {
            var pid = Uri.EscapeDataString(GetDevicePid());
            var req = new HttpRequestMessage(HttpMethod.Get, $"{_config.apiHost}/v1/opt-out/status?device_pid={pid}");
            req.Headers.Add("X-DMP-App-Key", _config.appKey);
            var res = await _http.SendAsync(req);
            if (!res.IsSuccessStatusCode) return;
            var json = await res.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.GetProperty("optedOut").GetBoolean())
            {
                _optedOut = true;
                PlayerPrefs.SetInt("dkmads_dmp_opted_out", 1);
                PlayerPrefs.Save();
            }
        }

        private static async Task SyncOptOutToServer()
        {
            var body = JsonSerializer.Serialize(new { devicePid = GetDevicePid() });
            var req = new HttpRequestMessage(HttpMethod.Post, $"{_config.apiHost}/v1/ingest/opt-out");
            req.Headers.Add("X-DMP-App-Key", _config.appKey);
            req.Content = new StringContent(body, Encoding.UTF8, "application/json");
            await _http.SendAsync(req);
        }

        private static void Enqueue(string eventName, Dictionary<string, object> properties)
        {
            if (!CanCollect()) return;
            var ids = new List<Dictionary<string, string>>
            {
                new() { { "type", "device_pid" }, { "value", GetDevicePid() } },
                new() { { "type", "install_id" }, { "value", GetInstallId() } },
            };
            if (!string.IsNullOrEmpty(_userId))
            {
                ids.Add(new Dictionary<string, string> { { "type", "publisher_user_id" }, { "value", _userId } });
                ids.Add(new Dictionary<string, string> { { "type", "user_pid" }, { "value", _userId } });
            }
            foreach (var match in MatchIdentifiersFromTraits(_traits))
                ids.Add(match);

            var eventContext = new Dictionary<string, object> { { "platform", GetPlatform() } };
            foreach (var kv in _context) eventContext[kv.Key] = kv.Value;

            _queue.Add(new Dictionary<string, object>
            {
                { "eventName", eventName },
                { "timestamp", DateTime.UtcNow.ToString("o") },
                { "identifiers", ids },
                { "traits", new Dictionary<string, object>(_traits) },
                { "properties", properties ?? new Dictionary<string, object>() },
                { "context", eventContext },
            });
        }

        private static string ResolveDevicePid()
        {
            var key = "dkmads_dmp_device_pid";
            if (PlayerPrefs.HasKey(key)) return PlayerPrefs.GetString(key);
            var id = $"dkmads_{Guid.NewGuid()}";
            PlayerPrefs.SetString(key, id);
            return id;
        }

        private static string GetInstallId()
        {
            var key = "dkmads_install_id";
            if (PlayerPrefs.HasKey(key)) return PlayerPrefs.GetString(key);
            var id = Guid.NewGuid().ToString();
            PlayerPrefs.SetString(key, id);
            return id;
        }

        private static string GetPlatform()
        {
#if UNITY_WEBGL
            return "webgl";
#elif UNITY_IOS
            return "ios";
#elif UNITY_ANDROID
            return "android";
#elif UNITY_STANDALONE
            return "standalone";
#else
            return "unity";
#endif
        }

        private static string Sha256Hex(string value)
        {
            var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        private static IEnumerable<Dictionary<string, string>> MatchIdentifiersFromTraits(Dictionary<string, object> traits)
        {
            var results = new List<Dictionary<string, string>>();
            void AddHashed(string type, string? raw, Func<string, string> normalize)
            {
                if (string.IsNullOrWhiteSpace(raw)) return;
                var normalized = normalize(raw.Trim());
                var value = normalized.Length == 64 ? normalized.ToLowerInvariant() : Sha256Hex(normalized);
                results.Add(new Dictionary<string, string> { { "type", type }, { "value", value } });
            }

            traits.TryGetValue("email", out var emailObj);
            AddHashed("email_sha256", emailObj?.ToString(), s => s.ToLowerInvariant());
            traits.TryGetValue("trait.email", out var traitEmail);
            if (emailObj == null) AddHashed("email_sha256", traitEmail?.ToString(), s => s.ToLowerInvariant());

            traits.TryGetValue("phone", out var phoneObj);
            AddHashed("phone_sha256", phoneObj?.ToString(), s =>
            {
                var digits = new string(s.Where(char.IsDigit).ToArray());
                return s.StartsWith('+') ? $"+{digits}" : digits;
            });

            traits.TryGetValue("googleSubId", out var googleObj);
            AddHashed("google_sub_hash", googleObj?.ToString(), s => s);

            return results;
        }
    }
}
