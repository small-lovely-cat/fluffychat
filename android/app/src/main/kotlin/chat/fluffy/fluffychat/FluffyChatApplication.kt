package chat.fluffy.fluffychat

import android.app.Application
import com.tencent.mmkv.MMKV

class FluffyChatApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        MMKV.initialize(this)
        AndroidHttpDnsManager.getInstance(this)
    }
}
