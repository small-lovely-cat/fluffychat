package chat.fluffy.fluffychat

import android.app.Application

class FluffyChatApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AndroidHttpDnsManager.getInstance(this)
    }
}
