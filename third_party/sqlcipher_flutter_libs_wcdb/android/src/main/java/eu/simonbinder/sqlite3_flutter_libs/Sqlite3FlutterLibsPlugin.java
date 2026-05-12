package eu.simonbinder.sqlite3_flutter_libs;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Sqlite3FlutterLibsPlugin */
public class Sqlite3FlutterLibsPlugin implements FlutterPlugin {

  private static final String CHANNEL = "sqlcipher_flutter_libs";

  private MethodChannel channel;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    // 保持原插件 API 不变，但 Android 底层已经切换到 WCDB 的 libWCDB.so。
    // 某些旧系统必须先走一次 System.loadLibrary，Dart FFI 才能成功 dlopen。
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);

    channel.setMethodCallHandler(new MethodChannel.MethodCallHandler() {
      @Override
      public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
          System.loadLibrary("WCDB");
          result.success(null);
        } catch (Throwable e) {
          result.error(e.toString(), null, null);
        }
      }
    });
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
  }

}
