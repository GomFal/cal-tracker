package com.example.cal_tracker_mobile.appfunctions

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

object BetterCaloriesAppFunctionEngine {
    @Volatile
    private var engine: FlutterEngine? = null

    @Volatile
    private var appIntentsChannel: MethodChannel? = null

    @Synchronized
    fun ensureStarted(context: Context): FlutterEngine {
        engine?.let { return it }

        val appContext = context.applicationContext
        val flutterLoader = FlutterInjector.instance().flutterLoader()
        flutterLoader.startInitialization(appContext)
        flutterLoader.ensureInitializationComplete(appContext, null)

        val newEngine = FlutterEngine(appContext)
        GeneratedPluginRegistrant.registerWith(newEngine)
        appIntentsChannel = MethodChannel(
            newEngine.dartExecutor.binaryMessenger,
            "app_intents",
        )
        newEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                flutterLoader.findAppBundlePath(),
                "appIntentsMain",
            ),
        )
        engine = newEngine
        return newEngine
    }

    fun appIntentsChannel(context: Context): MethodChannel {
        ensureStarted(context)
        return checkNotNull(appIntentsChannel) {
            "AppFunctions MethodChannel was not initialized."
        }
    }
}
