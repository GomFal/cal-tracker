package com.example.cal_tracker_mobile.appfunctions

import com.example.cal_tracker_mobile.BetterCaloriesApplication
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

object BetterCaloriesAppFunctionBridge {
    private const val maxDartHandlerAttempts = 30
    private const val retryDelayMillis = 100L

    suspend fun executeIntent(
        identifier: String,
        params: Map<String, Any?>,
    ): String {
        val channel = BetterCaloriesAppFunctionEngine.appIntentsChannel(
            BetterCaloriesApplication.instance,
        )
        var lastNotReady: Throwable? = null
        repeat(maxDartHandlerAttempts) {
            try {
                return invokeFlutter(channel, identifier, params)
            } catch (error: DartHandlerNotReadyException) {
                lastNotReady = error
                delay(retryDelayMillis)
            }
        }
        throw lastNotReady ?: IllegalStateException("Dart AppFunction handler is not ready.")
    }

    private suspend fun invokeFlutter(
        channel: MethodChannel,
        identifier: String,
        params: Map<String, Any?>,
    ): String = withContext(Dispatchers.Main) {
        suspendCancellableCoroutine { continuation ->
            channel.invokeMethod(
                "executeIntent",
                mapOf("identifier" to identifier, "params" to params),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (continuation.isActive) {
                            continuation.resume(stringifyResult(result))
                        }
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        if (continuation.isActive) {
                            continuation.resumeWithException(
                                RuntimeException("$code: ${message ?: "AppFunction failed"}"),
                            )
                        }
                    }

                    override fun notImplemented() {
                        if (continuation.isActive) {
                            continuation.resumeWithException(DartHandlerNotReadyException())
                        }
                    }
                },
            )
        }
    }

    private fun stringifyResult(result: Any?): String = when (result) {
        null -> "{}"
        is String -> result
        is Map<*, *> -> JSONObject(result).toString()
        is List<*> -> JSONArray(result).toString()
        else -> result.toString()
    }
}

private class DartHandlerNotReadyException : RuntimeException(
    "Dart AppFunction MethodChannel handler is not ready.",
)
