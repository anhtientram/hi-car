package com.hicar.ora.limited

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BluetoothReceiver : BroadcastReceiver() {

    companion object {
        /**
         * Returns list of paired Bluetooth devices as maps for Flutter MethodChannel.
         */
        fun getPairedDevices(context: Context): List<Map<String, Any>> {
            return try {
                val bluetoothManager =
                    context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                val adapter = bluetoothManager?.adapter ?: return emptyList()
                adapter.bondedDevices?.map { device ->
                    mapOf(
                        "name" to (device.name ?: "Unknown Device"),
                        "address" to device.address,
                        "isConnected" to isDeviceConnected(device)
                    )
                } ?: emptyList()
            } catch (e: SecurityException) {
                emptyList()
            }
        }

        /**
         * Check if a classic Bluetooth device is connected using reflection.
         */
        private fun isDeviceConnected(device: BluetoothDevice): Boolean {
            return try {
                val method = device.javaClass.getMethod("isConnected")
                method.invoke(device) as? Boolean ?: false
            } catch (e: Exception) {
                false
            }
        }

        fun isAddressConnected(context: Context, address: String): Boolean {
            if (address.isEmpty()) return false
            return try {
                val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                val adapter = bluetoothManager?.adapter ?: return false
                val device = adapter.getRemoteDevice(address) ?: return false
                isDeviceConnected(device)
            } catch (e: Exception) {
                false
            }
        }

        private var a2dpProxy: BluetoothProfile? = null
        private var proxyRequestedAt = 0L
        private var lastProfileErrorAt = 0L

        fun releaseProfile(context: Context) {
            val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            a2dpProxy?.let { try { adapter?.closeProfileProxy(BluetoothProfile.A2DP, it) } catch (_: Exception) {} }
            a2dpProxy = null
            proxyRequestedAt = 0L
        }

        /** Public profile API: aggregate A2DP + ACL can accidentally match a different headset. */
        fun isA2dpConnected(context: Context, address: String): Boolean {
            if (address.isEmpty()) return false
            return try {
                val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
                    ?: return false
                val proxy = a2dpProxy
                if (proxy != null) {
                    proxy.getConnectionState(adapter.getRemoteDevice(address)) == BluetoothProfile.STATE_CONNECTED
                } else {
                    val now = android.os.SystemClock.elapsedRealtime()
                    if (proxyRequestedAt == 0L || now - proxyRequestedAt > 10_000L) {
                        proxyRequestedAt = now
                        adapter.getProfileProxy(context.applicationContext, object : BluetoothProfile.ServiceListener {
                            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                                a2dpProxy = proxy
                                proxyRequestedAt = 0L
                            }
                            override fun onServiceDisconnected(profile: Int) {
                                a2dpProxy = null
                                proxyRequestedAt = 0L
                            }
                        }, BluetoothProfile.A2DP)
                    }
                    false // Unknown is waiting, never route-ready.
                }
            } catch (e: Exception) {
                val now = android.os.SystemClock.elapsedRealtime()
                if (now - lastProfileErrorAt > 30_000L) {
                    lastProfileErrorAt = now
                    HiCarDiagnosticLog.e("HiCarBT", "A2DP state unavailable mode=phone_bluetooth api=${Build.VERSION.SDK_INT} ${e.stackTraceToString()}")
                }
                false
            }
        }

        fun startDiscovery(context: Context): Boolean {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = bluetoothManager?.adapter ?: return false
            return try {
                if (adapter.isDiscovering) {
                    adapter.cancelDiscovery()
                }
                adapter.startDiscovery()
            } catch (e: SecurityException) {
                false
            }
        }

        fun stopDiscovery(context: Context): Boolean {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = bluetoothManager?.adapter ?: return false
            return try {
                if (adapter.isDiscovering) {
                    adapter.cancelDiscovery()
                } else {
                    true
                }
            } catch (e: SecurityException) {
                false
            }
        }

        /**
         * Connect to A2DP and Headset profiles of a device using reflection.
         */
        fun connectDevice(context: Context, address: String, callback: (Boolean) -> Unit) {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = bluetoothManager?.adapter ?: run {
                callback(false)
                return
            }
            val device = try {
                adapter.getRemoteDevice(address)
            } catch (e: Exception) {
                null
            }
            if (device == null) {
                callback(false)
                return
            }

            // Connect A2DP (Music)
            adapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    try {
                        val connectMethod = proxy.javaClass.getMethod("connect", BluetoothDevice::class.java)
                        connectMethod.invoke(proxy, device)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    } finally {
                        adapter.closeProfileProxy(BluetoothProfile.A2DP, proxy)
                    }
                }
                override fun onServiceDisconnected(profile: Int) {}
            }, BluetoothProfile.A2DP)

            // Connect HEADSET (Calls)
            adapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    try {
                        val connectMethod = proxy.javaClass.getMethod("connect", BluetoothDevice::class.java)
                        connectMethod.invoke(proxy, device)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    } finally {
                        adapter.closeProfileProxy(BluetoothProfile.HEADSET, proxy)
                    }
                }
                override fun onServiceDisconnected(profile: Int) {}
            }, BluetoothProfile.HEADSET)

            callback(true)
        }

        /**
         * Disconnect from A2DP and Headset profiles using reflection.
         */
        fun disconnectDevice(context: Context, address: String, callback: (Boolean) -> Unit) {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = bluetoothManager?.adapter ?: run {
                callback(false)
                return
            }
            val device = try {
                adapter.getRemoteDevice(address)
            } catch (e: Exception) {
                null
            }
            if (device == null) {
                callback(false)
                return
            }

            // Disconnect A2DP
            adapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    try {
                        val disconnectMethod = proxy.javaClass.getMethod("disconnect", BluetoothDevice::class.java)
                        disconnectMethod.invoke(proxy, device)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    } finally {
                        adapter.closeProfileProxy(BluetoothProfile.A2DP, proxy)
                    }
                }
                override fun onServiceDisconnected(profile: Int) {}
            }, BluetoothProfile.A2DP)

            // Disconnect HEADSET
            adapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    try {
                        val disconnectMethod = proxy.javaClass.getMethod("disconnect", BluetoothDevice::class.java)
                        disconnectMethod.invoke(proxy, device)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    } finally {
                        adapter.closeProfileProxy(BluetoothProfile.HEADSET, proxy)
                    }
                }
                override fun onServiceDisconnected(profile: Int) {}
            }, BluetoothProfile.HEADSET)

            callback(true)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        HiCarDiagnosticLog.init(context)
        // ⚠️ Android 12+ (API 31): đọc BluetoothDevice.address/name YÊU CẦU quyền BLUETOOTH_CONNECT.
        //    Nếu chưa được cấp, truy cập sẽ ném SecurityException → nếu không bắt, receiver "chết"
        //    âm thầm và auto-play (đặc biệt Android Auto KHÔNG DÂY) không bao giờ chạy.
        try {
            handleReceive(context, intent)
        } catch (e: SecurityException) {
            val message = "BluetoothReceiver thiếu quyền BLUETOOTH_CONNECT: ${e.message}"
            HiCarDiagnosticLog.e("HiCarBT", message)
            HiCarPlugin.instance?.invokeServiceMethod("onNativeError", message)
        } catch (e: Exception) {
            val message = "BluetoothReceiver lỗi: ${e.message}"
            HiCarDiagnosticLog.e("HiCarBT", message)
            HiCarPlugin.instance?.invokeServiceMethod("onNativeError", message)
        }
    }

    private fun handleReceive(context: Context, intent: Intent) {
        if (intent.action == BluetoothAdapter.ACTION_DISCOVERY_FINISHED) {
            HiCarPlugin.instance?.invokeBluetoothMethod("onDiscoveryFinished", null)
            return
        }
        val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

        val deviceAddress = device?.address ?: return
        
        // Load target and mode directly from SharedPreferences to ensure they are available even if the Service isn't running
        val unlocked = Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
            (context.getSystemService(Context.USER_SERVICE) as? android.os.UserManager)?.isUserUnlocked == true
        val regularPrefs = if (unlocked) context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE) else null
        val storageContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
        val protectedPrefs = storageContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        // Priority: Regular prefs (latest from UI) -> Protected prefs (boot sequence)
        val prefs = if (regularPrefs != null && regularPrefs.all.isNotEmpty()) regularPrefs else protectedPrefs
        
        val connectionMode = prefs.getString("flutter.connection_mode", "phone_bluetooth") ?: "phone_bluetooth"
        val targetAddress = prefs.getString("flutter.target_device_address", "") ?: ""
        val autoPlayEnabled = prefs.getBoolean("flutter.auto_play_enabled", true)


        // 🟢 SỬA ĐỔI CHÍNH: Thay đổi từ gọi instance sang biến tĩnh tĩnh toàn cục để tránh lỗi Unresolved reference
        // Send Bluetooth events to Flutter via Plugin
        when (intent.action) {
            BluetoothDevice.ACTION_FOUND -> {
                HiCarPlugin.instance?.invokeBluetoothMethod("onDeviceFound", mapOf(
                    "name" to (device.name ?: "Unknown Device"),
                    "address" to deviceAddress,
                    "isConnected" to false
                ))
            }
            BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                HiCarPlugin.instance?.invokeBluetoothMethod("onDiscoveryFinished", null)
            }
            else -> {
                val actionStr = when (intent.action) {
                    BluetoothDevice.ACTION_ACL_CONNECTED -> "connected"
                    BluetoothDevice.ACTION_ACL_DISCONNECTED -> "disconnected"
                    else -> intent.action ?: "unknown"
                }

                // Connection state changes
                HiCarPlugin.instance?.invokeBluetoothMethod("onDeviceConnectionChanged", mapOf(
                    "address" to deviceAddress,
                    "action" to actionStr
                ))
            }
        }

        when (intent.action) {
            BluetoothDevice.ACTION_ACL_CONNECTED -> {
                HiCarDiagnosticLog.d("HiCarBT", "ACL Connected: $deviceAddress")
                HiCarDiagnosticLog.d("HiCarBT", "Conditions: autoPlayEnabled=$autoPlayEnabled, mode=$connectionMode, target=$targetAddress")
                
                if (autoPlayEnabled && !prefs.getString("flutter.auth_token", "").isNullOrEmpty()) {
                    if (connectionMode == "phone_android_auto") {
                        // AA không dây: BT nối trước projection → KHÔNG phát ngay, chỉ bật watch.
                        HiCarDiagnosticLog.d("HiCarAA", "AA Mode: BT connected → watch CarConnection projection")
                        val serviceIntent = Intent(context, AudioForegroundService::class.java).apply {
                            action = AudioForegroundService.ACTION_AA_WATCH_PROJECTION
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(serviceIntent)
                        } else {
                            context.startService(serviceIntent)
                        }
                    } else if (connectionMode == "phone_bluetooth" && targetAddress.isNotEmpty() && deviceAddress.equals(targetAddress, ignoreCase = true)) {
                        // 🟢 AUTO-PLAY (Bluetooth): đúng xe mục tiêu → KHÔNG phát ngay.
                        // ACL connect xảy ra trước khi sink A2DP của màn hình xe sẵn sàng; nếu phát
                        // ngay, âm thanh ra loa điện thoại. Bật watch A2DP: service sẽ đợi tới khi
                        // route A2DP = CONNECTED rồi mới phát → tiếng luôn ra loa xe.
                        HiCarDiagnosticLog.d("HiCarBT", "Bluetooth Mode: Target Match! → watch A2DP trước khi phát")
                        val serviceIntent = Intent(context, AudioForegroundService::class.java).apply {
                            action = AudioForegroundService.ACTION_BT_WATCH_A2DP
                            putExtra("deviceAddress", deviceAddress)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(serviceIntent)
                        } else {
                            context.startService(serviceIntent)
                        }
                    }
                }
            }
            BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                // AA không dây: BT handshake có thể ngắt/nối lại TRƯỚC khi projection xong → không dừng nhạc
                // theo BT. Chỉ dừng khi CarConnection=0 (service). Bluetooth mode: dừng đúng xe mục tiêu.
                val shouldStop = connectionMode == "phone_bluetooth" &&
                    targetAddress.isNotEmpty() &&
                    deviceAddress.equals(targetAddress, ignoreCase = true)
                if (!shouldStop) return

                val serviceIntent = Intent(context, AudioForegroundService::class.java).apply {
                    action = AudioForegroundService.ACTION_BLUETOOTH_DISCONNECTED
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }
        }
    }
}
