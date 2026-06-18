package com.example.cal_tracker_mobile

import com.example.cal_tracker_mobile.appfunctions.BetterCaloriesAppFunctionEngine
import io.flutter.app.FlutterApplication

class BetterCaloriesApplication : FlutterApplication() {
    companion object {
        lateinit var instance: BetterCaloriesApplication
            private set
    }

    override fun onCreate() {
        instance = this
        super.onCreate()
        BetterCaloriesAppFunctionEngine.ensureStarted(this)
    }
}
