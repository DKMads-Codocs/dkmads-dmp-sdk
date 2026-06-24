package com.dkmads.dmp

import android.content.Context
import android.content.SharedPreferences
import com.google.android.gms.ads.identifier.AdvertisingIdClient
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

data class DMPConsent(
    val gdprApplies: Boolean? = null,
    val tcfString: String? = null,
    val usPrivacy: String? = null,
    val purposes: Map<String, Boolean>? = null,
)

data class DMPInitConfig(
    val appKey: String,
    val workspaceId: String? = null,
    val propertyId: String? = null,
    val apiHost: String = "https://ingest.dmp.dkmads.com",
    val flushIntervalMs: Long = 10_000,
    val batchSize: Int = 20,
    val collectDeviceIds: Boolean = true,
    val debug: Boolean = false,
)

object DMP {
    private lateinit var config: DMPInitConfig
    private lateinit var appContext: Context
    private var workspaceId: String? = null
    private var propertyId: String? = null
    private val queue = mutableListOf<JSONObject>()
    private var traits = JSONObject()
    private var eventContext = JSONObject()
    private var userId: String? = null
    private var optedOut = false
    private var consent: DMPConsent? = null
    private var latEnabled = false
    private var initialized = false
    private var bridgeResolved = false
    private val client = OkHttpClient()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var flushJob: Job? = null

    /** True after successful [init] (bridge resolve + opt-out sync completed). */
    fun isInitialized(): Boolean = initialized

    /** True when workspace/property were resolved (config or bridge). */
    fun isBridgeResolved(): Boolean = bridgeResolved

    private fun prefs(): SharedPreferences =
        appContext.getSharedPreferences("dkmads_dmp", Context.MODE_PRIVATE)

    private fun canCollect(): Boolean {
        if (!initialized) return false
        if (optedOut) return false
        consent?.usPrivacy?.let { if (it.length >= 3 && it[2] == 'Y') return false }
        if (consent?.gdprApplies == true) {
            val p1 = consent?.purposes?.get("1") ?: return false
            if (!p1) return false
        }
        return true
    }

    fun init(context: Context, config: DMPInitConfig, callback: ((Boolean) -> Unit)? = null) {
        appContext = context.applicationContext
        this.config = config
        workspaceId = config.workspaceId
        propertyId = config.propertyId
        bridgeResolved = config.workspaceId != null && config.propertyId != null
        initialized = false
        optedOut = prefs().getBoolean("opted_out", false)

        scope.launch {
            var ok = true
            if (!bridgeResolved) {
                ok = resolveBridge()
            }
            if (ok) {
                syncOptOutFromServer()
                flushJob?.cancel()
                flushJob = scope.launch {
                    while (isActive) {
                        delay(config.flushIntervalMs)
                        flush()
                    }
                }
                initialized = true
                track("sdk_initialized", JSONObject().put("platform", "android"))
            }
            withContext(Dispatchers.Main) { callback?.invoke(ok) }
        }
    }

    fun identify(userId: String, traits: Map<String, Any?>? = null) {
        if (!canCollect()) return
        this.userId = userId
        traits?.forEach { (k, v) -> this.traits.put(k, v) }
        enqueue("identify", JSONObject().put("userId", userId))
    }

    fun track(event: String, properties: Map<String, Any?>? = null) {
        if (!canCollect()) return
        enqueue(event, properties?.let { mapToJson(it) })
    }

    fun setTrait(key: String, value: Any?) {
        if (!canCollect()) return
        traits.put(key, value)
    }

    fun setTraits(newTraits: Map<String, Any?>) {
        if (!canCollect()) return
        newTraits.forEach { (k, v) -> traits.put(k, v) }
    }

    fun setContext(values: Map<String, Any?>) {
        if (!canCollect()) return
        values.forEach { (k, v) -> eventContext.put(k, v) }
    }

    fun setConsent(consent: DMPConsent, callback: ((Boolean) -> Unit)? = null) {
        this.consent = consent
        scope.launch {
            val body = JSONObject()
                .put("gdprApplies", consent.gdprApplies)
                .put("tcfString", consent.tcfString)
                .put("usPrivacy", consent.usPrivacy)
                .put("devicePid", getDevicePid())
                .put("latEnabled", latEnabled)
            consent.purposes?.let { p ->
                val obj = JSONObject()
                p.forEach { (k, v) -> obj.put(k, v) }
                body.put("purposes", obj)
            }
            val req = Request.Builder()
                .url("${config.apiHost}/v1/ingest/consent")
                .addHeader("X-DMP-App-Key", config.appKey)
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .build()
            val ok = client.newCall(req).execute().isSuccessful
            withContext(Dispatchers.Main) { callback?.invoke(ok) }
        }
    }

    fun optOut() {
        optedOut = true
        prefs().edit().putBoolean("opted_out", true).apply()
        scope.launch { syncOptOutToServer() }
        reset()
    }

    fun reset() {
        userId = null
        traits = JSONObject()
        eventContext = JSONObject()
        queue.clear()
    }

    fun flush() {
        if (queue.isEmpty() || workspaceId == null || propertyId == null || !canCollect()) return
        val events = queue.take(config.batchSize)
        repeat(events.size) { queue.removeAt(0) }

        val eventsArray = JSONArray()
        events.forEach { eventsArray.put(it) }

        val body = JSONObject()
            .put("workspaceId", workspaceId)
            .put("propertyId", propertyId)
            .put("sdkVersion", "0.1.0")
            .put("events", eventsArray)

        val req = Request.Builder()
            .url("${config.apiHost}/v1/ingest/batch")
            .addHeader("X-DMP-App-Key", config.appKey)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        client.newCall(req).execute().close()
    }

    private fun enqueue(event: String, properties: JSONObject?) {
        if (!canCollect()) return
        val ids = JSONArray()
        ids.put(JSONObject().put("type", "device_pid").put("value", getDevicePid()))
        if (config.collectDeviceIds && !latEnabled) {
            try {
                val adInfo = AdvertisingIdClient.getAdvertisingIdInfo(appContext)
                latEnabled = adInfo.isLimitAdTrackingEnabled
                if (!latEnabled && adInfo.id != null) {
                    ids.put(JSONObject().put("type", "gaid").put("value", adInfo.id))
                }
            } catch (_: Exception) {}
        }
        userId?.let {
            ids.put(JSONObject().put("type", "publisher_user_id").put("value", it))
            ids.put(JSONObject().put("type", "user_pid").put("value", it))
        }
        matchIdentifiersFromTraits(traits).forEach { ids.put(it) }

        val ctx = JSONObject().put("platform", "android")
        eventContext.keys().forEach { key -> ctx.put(key, eventContext.get(key)) }

        val eventObj = JSONObject()
            .put("eventName", event)
            .put("identifiers", ids)
            .put("traits", traits)
            .put("properties", properties ?: JSONObject())
            .put("context", ctx)
        queue.add(eventObj)
        if (queue.size >= config.batchSize) flush()
    }

    private fun track(event: String, properties: JSONObject) = enqueue(event, properties)

    private suspend fun resolveBridge(): Boolean {
        return try {
            val req = Request.Builder()
                .url("${config.apiHost}/v1/bridge/resolve?app_key=${config.appKey}")
                .get().build()
            val res = client.newCall(req).execute()
            if (!res.isSuccessful) return false
            val body = res.body?.string() ?: return false
            val json = JSONObject(body)
            val ws = json.optString("workspaceId", "").trim()
            val prop = json.optString("propertyId", "").trim()
            if (ws.isEmpty() || prop.isEmpty()) return false
            workspaceId = ws
            propertyId = prop
            bridgeResolved = true
            true
        } catch (_: Exception) {
            false
        }
    }

    private suspend fun syncOptOutFromServer() {
        val req = Request.Builder()
            .url("${config.apiHost}/v1/opt-out/status?device_pid=${getDevicePid()}")
            .addHeader("X-DMP-App-Key", config.appKey)
            .get().build()
        val res = client.newCall(req).execute()
        if (res.isSuccessful) {
            val json = JSONObject(res.body?.string() ?: "{}")
            if (json.optBoolean("optedOut", false)) {
                optedOut = true
                prefs().edit().putBoolean("opted_out", true).apply()
            }
        }
    }

    private suspend fun syncOptOutToServer() {
        val body = JSONObject().put("devicePid", getDevicePid())
        val req = Request.Builder()
            .url("${config.apiHost}/v1/ingest/opt-out")
            .addHeader("X-DMP-App-Key", config.appKey)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        client.newCall(req).execute().close()
    }

    /** Stable device id for SSP bid-time eval — same value sent on DMP ingest. */
    fun getDevicePid(): String = resolveDevicePid()

    fun getUserPid(): String? = userId

    fun getSharedIdentity(): Map<String, String?> = mapOf(
        "devicePid" to resolveDevicePid(),
        "userPid" to userId,
    )

    private fun resolveDevicePid(): String {
        val prefs = prefs()
        val existing = prefs.getString("dkmads_dmp_device_pid", null)?.trim()?.takeIf { it.isNotEmpty() }
            ?: prefs.getString("device_pid", null)?.trim()?.takeIf { it.isNotEmpty() }
        if (existing != null) {
            if (!prefs.contains("dkmads_dmp_device_pid")) {
                prefs.edit().putString("dkmads_dmp_device_pid", existing).apply()
            }
            return existing
        }
        val created = "dkmads_${UUID.randomUUID()}"
        prefs.edit()
            .putString("dkmads_dmp_device_pid", created)
            .putString("device_pid", created)
            .apply()
        return created
    }

    private fun sha256Hex(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun matchIdentifiersFromTraits(traits: JSONObject): List<JSONObject> {
        val out = mutableListOf<JSONObject>()
        listOf("email", "trait.email").forEach { key ->
            val raw = traits.optString(key, "")
            if (raw.isNotBlank()) {
                val normalized = raw.trim().lowercase()
                val value = if (normalized.length == 64) normalized else sha256Hex(normalized)
                out.add(JSONObject().put("type", "email_sha256").put("value", value))
            }
        }
        listOf("phone", "trait.phone").forEach { key ->
            val raw = traits.optString(key, "")
            if (raw.isNotBlank()) {
                val digits = raw.filter { it.isDigit() }
                val normalized = if (raw.trim().startsWith("+")) "+$digits" else digits
                val value = if (normalized.length == 64) normalized else sha256Hex(normalized)
                out.add(JSONObject().put("type", "phone_sha256").put("value", value))
            }
        }
        listOf("googleSubId", "google_sub_hash").forEach { key ->
            val raw = traits.optString(key, "")
            if (raw.isNotBlank()) {
                val trimmed = raw.trim()
                val value = if (trimmed.length == 64) trimmed.lowercase() else sha256Hex(trimmed)
                out.add(JSONObject().put("type", "google_sub_hash").put("value", value))
            }
        }
        return out
    }

    private fun mapToJson(map: Map<String, Any?>): JSONObject {
        val obj = JSONObject()
        map.forEach { (k, v) -> obj.put(k, v) }
        return obj
    }
}
