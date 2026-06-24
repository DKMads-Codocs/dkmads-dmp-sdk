package com.dkmads.dmp

import android.content.Context
import com.google.android.gms.ads.identifier.AdvertisingIdClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DmpFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.dkmads.dmp/sdk")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestATT" -> result.success("not_applicable")
            "isLatEnabled" -> {
                try {
                    val info = AdvertisingIdClient.getAdvertisingIdInfo(context)
                    result.success(info.isLimitAdTrackingEnabled)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "getAdvertisingId" -> {
                try {
                    val info = AdvertisingIdClient.getAdvertisingIdInfo(context)
                    if (info.isLimitAdTrackingEnabled) {
                        result.success(null)
                    } else {
                        result.success(info.id)
                    }
                } catch (e: Exception) {
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
