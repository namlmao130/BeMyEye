package com.bemyeye.bemyeye_vn

import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.bemyeye/device_health"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceHealth" -> {
                    val healthData = getDeviceHealth()
                    result.success(healthData)
                }
                "getBatteryLevel" -> {
                    result.success(getBatteryLevel())
                }
                "getThermalStatus" -> {
                    result.success(getThermalStatus())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getBatteryLevel(): Int {
        return try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        } catch (e: Exception) {
            -1
        }
    }

    private fun getThermalStatus(): Int {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                pm?.currentThermalStatus ?: 0
            } else {
                0
            }
        } catch (e: Exception) {
            0
        }
    }

    private fun getDeviceHealth(): Map<String, Any> {
        val battery = getBatteryLevel()
        val thermal = getThermalStatus()
        val isThrottling = thermal >= 3 // 3 = THERMAL_STATUS_SEVERE
        return mapOf(
            "batteryLevel" to battery,
            "thermalStatus" to thermal,
            "isThermalThrottling" to isThrottling
        )
    }
}
