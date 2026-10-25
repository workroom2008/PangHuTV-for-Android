package com.hongbo.panghutv

import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

/**
 * 远程输入服务桥。
 *
 * JS 侧：
 *   await RemoteInput.start()  -> { url }
 *   await RemoteInput.stop()
 *   RemoteInput.getLanIp()
 *   RemoteInput.emitReceived(text)   // 把手机发来的文本抛给 JS（走事件）
 *
 * 用原生 ServerSocket 而不是 react-native-tcp-socket：后者在 OEM Android 6 TV 上
 * accept 后读线程卡死，连接 ESTABLISHED 但零响应。
 */
class RemoteInputModule(private val ctx: ReactApplicationContext) :
    ReactContextBaseJavaModule(ctx) {

    override fun getName(): String = "RemoteInput"

    @ReactMethod
    fun start(promise: Promise) {
        try {
            RemoteInputServer.setHandler(object : RemoteInputServer.Handler {
                override fun onGetPage(): String = PageProvider.page

                override fun onConfig(body: String): String {
                    emit("onConfig", body)
                    return "{\"status\":\"ok\",\"message\":\"已发送到电视\"}"
                }

                override fun onMessage(body: String): String {
                    val text = extractJsonField(body, "message")
                    if (text.isNotEmpty()) emitText(text)
                    return "{\"status\":\"ok\"}"
                }

                override fun onHandshake(connected: Boolean): String {
                    emit("onHandshake", "")
                    return "{\"status\":\"ok\"}"
                }
            })
            val url = RemoteInputServer.start()
            val map: WritableMap = Arguments.createMap()
            map.putString("url", url)
            map.putInt("port", RemoteInputServer.PORT)
            promise.resolve(map)
        } catch (e: Throwable) {
            Log.e("RemoteInputModule", "start failed", e)
            promise.reject("E_START", e.message ?: "启动失败", e)
        }
    }

    @ReactMethod
    fun stop(promise: Promise) {
        try {
            RemoteInputServer.stop()
            promise.resolve(true)
        } catch (e: Throwable) {
            promise.reject("E_STOP", e.message ?: "停止失败", e)
        }
    }

    @ReactMethod
    fun isRunning(promise: Promise) {
        promise.resolve(RemoteInputServer.isRunning())
    }

    @ReactMethod
    fun getLanIp(promise: Promise) {
        promise.resolve(RemoteInputServer.getLanIp() ?: "")
    }

    /** 每台电视页面不同：JS 生成 HTML 后塞进来 */
    @ReactMethod
    fun setPage(html: String) {
        PageProvider.page = html
    }

    private fun emitText(text: String) {
        val map: WritableMap = Arguments.createMap()
        map.putString("text", text)
        ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit("RemoteInputText", map)
    }

    private fun emit(event: String, payload: String) {
        val map: WritableMap = Arguments.createMap()
        map.putString("payload", payload)
        ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(event, map)
    }

    /** 极简 JSON 取值，避免引入额外依赖 */
    private fun extractJsonField(json: String, field: String): String {
        val key = "\"$field\""
        val i = json.indexOf(key)
        if (i < 0) return ""
        val colon = json.indexOf(':', i + key.length)
        if (colon < 0) return ""
        var p = colon + 1
        while (p < json.length && json[p].isWhitespace()) p++
        if (p >= json.length || json[p] != '"') return ""
        p++
        val sb = StringBuilder()
        while (p < json.length) {
            val c = json[p]
            if (c == '\\' && p + 1 < json.length) {
                val n = json[p + 1]
                when (n) {
                    'n' -> sb.append('\n')
                    't' -> sb.append('\t')
                    'r' -> sb.append('\r')
                    '"' -> sb.append('"')
                    '\\' -> sb.append('\\')
                    'u' -> {
                        if (p + 5 < json.length) {
                            sb.append(json.substring(p + 2, p + 6).toInt(16).toChar())
                            p += 4
                        }
                    }
                    else -> sb.append(n)
                }
                p += 2
                continue
            }
            if (c == '"') break
            sb.append(c)
            p++
        }
        return sb.toString()
    }

    object PageProvider {
        @Volatile
        var page: String = "<html><body style=\"background:#121212;color:#fff;font-family:sans-serif\">胖虎TV 远程配置加载中…</body></html>"
    }
}
