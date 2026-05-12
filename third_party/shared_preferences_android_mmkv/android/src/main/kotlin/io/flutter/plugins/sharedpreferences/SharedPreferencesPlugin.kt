package io.flutter.plugins.sharedpreferences

import android.content.Context
import android.util.Base64
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.ObjectOutputStream

const val TAG = "SharedPreferencesPlugin"
const val SHARED_PREFERENCES_NAME = "FlutterSharedPreferences"
const val LIST_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"
const val JSON_LIST_PREFIX = LIST_PREFIX + "!"
const val DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"

/** SharedPreferencesPlugin backed by MMKV. */
class SharedPreferencesPlugin : FlutterPlugin, SharedPreferencesAsyncApi {
  private lateinit var context: Context
  private var backend: SharedPreferencesBackend? = null
  private var listEncoder: SharedPreferencesListEncoder = ListEncoder()

  private fun setUp(messenger: BinaryMessenger, context: Context) {
    this.context = context.applicationContext
    MMKVPreferencesStore.initialize(this.context)
    try {
      SharedPreferencesAsyncApi.setUp(messenger, this, "data_store")
      backend = SharedPreferencesBackend(messenger, this.context, listEncoder)
    } catch (error: Exception) {
      Log.e(TAG, "Received exception while setting up SharedPreferencesPlugin", error)
    }
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    setUp(binding.binaryMessenger, binding.applicationContext)
    LegacySharedPreferencesPlugin().onAttachedToEngine(binding)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    SharedPreferencesAsyncApi.setUp(binding.binaryMessenger, null, "data_store")
    backend?.tearDown()
    backend = null
  }

  /**
   * Adds a boolean property to the default MMKV store.
   *
   * @param key Stored key.
   * @param value Boolean value to persist.
   * @param options Backend options from Flutter. Kept for API compatibility.
   */
  override fun setBool(key: String, value: Boolean, options: SharedPreferencesPigeonOptions) {
    MMKVPreferencesStore.putBoolean(defaultStore(), key, value)
  }

  /**
   * Adds a string property to the default MMKV store.
   *
   * @param key Stored key.
   * @param value String value to persist.
   * @param options Backend options from Flutter. Kept for API compatibility.
   */
  override fun setString(key: String, value: String, options: SharedPreferencesPigeonOptions) {
    MMKVPreferencesStore.putString(defaultStore(), key, value, isStringList = false)
  }

  /**
   * Adds an integer property to the default MMKV store.
   *
   * @param key Stored key.
   * @param value Integer value represented as long.
   * @param options Backend options from Flutter. Kept for API compatibility.
   */
  override fun setInt(key: String, value: Long, options: SharedPreferencesPigeonOptions) {
    MMKVPreferencesStore.putLong(defaultStore(), key, value)
  }

  /**
   * Adds a double property to the default MMKV store.
   *
   * @param key Stored key.
   * @param value Double value to persist.
   * @param options Backend options from Flutter. Kept for API compatibility.
   */
  override fun setDouble(key: String, value: Double, options: SharedPreferencesPigeonOptions) {
    MMKVPreferencesStore.putDouble(defaultStore(), key, value)
  }

  /**
   * Adds an encoded string-list payload to the default MMKV store.
   *
   * @param key Stored key.
   * @param value Encoded string-list payload.
   * @param options Backend options from Flutter. Kept for API compatibility.
   */
  override fun setEncodedStringList(
      key: String,
      value: String,
      options: SharedPreferencesPigeonOptions
  ) {
    MMKVPreferencesStore.putString(defaultStore(), key, value, isStringList = true)
  }

  /**
   * Adds a deprecated platform-encoded string list to the default MMKV store.
   *
   * @param key Stored key.
   * @param value String list to encode.
   * @param options Backend options from Flutter. Kept for API compatibility.
   */
  @Deprecated("This is just for testing, use `setEncodedStringList`")
  override fun setDeprecatedStringList(
      key: String,
      value: List<String>,
      options: SharedPreferencesPigeonOptions
  ) {
    val valueString = LIST_PREFIX + listEncoder.encode(value)
    MMKVPreferencesStore.putString(defaultStore(), key, valueString, isStringList = true)
  }

  /**
   * Removes all properties from the default MMKV store.
   *
   * @param allowList Optional allow-list from Flutter.
   * @param options Backend options from Flutter. Kept for API compatibility.
   */
  override fun clear(allowList: List<String>?, options: SharedPreferencesPigeonOptions) {
    MMKVPreferencesStore.clear(defaultStore(), allowList = allowList?.toSet())
  }

  /**
   * Gets all properties from the default MMKV store.
   *
   * @param allowList Optional allow-list from Flutter.
   * @param options Backend options from Flutter. Kept for API compatibility.
   * @return Map of all visible key/value pairs.
   */
  override fun getAll(
      allowList: List<String>?,
      options: SharedPreferencesPigeonOptions
  ): Map<String, Any> = MMKVPreferencesStore.getAll(
      defaultStore(),
      allowList = allowList?.toSet(),
      listEncoder = listEncoder,
  )

  /**
   * Gets a stored integer from the default MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter. Kept for API compatibility.
   * @return Stored integer as long, or null when absent.
   */
  override fun getInt(key: String, options: SharedPreferencesPigeonOptions): Long? =
      MMKVPreferencesStore.getLong(defaultStore(), key)

  /**
   * Gets a stored boolean from the default MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter. Kept for API compatibility.
   * @return Stored boolean value, or null when absent.
   */
  override fun getBool(key: String, options: SharedPreferencesPigeonOptions): Boolean? =
      MMKVPreferencesStore.getBoolean(defaultStore(), key)

  /**
   * Gets a stored double from the default MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter. Kept for API compatibility.
   * @return Stored double value, or null when absent.
   */
  override fun getDouble(key: String, options: SharedPreferencesPigeonOptions): Double? =
      MMKVPreferencesStore.getDouble(defaultStore(), key)

  /**
   * Gets a stored raw string payload from the default MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter. Kept for API compatibility.
   * @return Raw string payload, or null when absent.
   */
  override fun getString(key: String, options: SharedPreferencesPigeonOptions): String? =
      MMKVPreferencesStore.getRawString(defaultStore(), key)

  /**
   * Gets the lookup result for a stored string list from the default MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter. Kept for API compatibility.
   * @return String list lookup result, or null when absent.
   */
  override fun getStringList(
      key: String,
      options: SharedPreferencesPigeonOptions
  ): StringListResult? = MMKVPreferencesStore.getStringListResult(defaultStore(), key)

  /**
   * Gets the decoded platform-encoded string list from the default MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter. Kept for API compatibility.
   * @return Decoded string list, or null when absent.
   */
  override fun getPlatformEncodedStringList(
      key: String,
      options: SharedPreferencesPigeonOptions
  ): List<String>? = MMKVPreferencesStore.getPlatformEncodedStringList(
      defaultStore(),
      key,
      listEncoder,
  )

  /**
   * Returns all visible keys from the default MMKV store.
   *
   * @param allowList Optional allow-list from Flutter.
   * @param options Backend options from Flutter. Kept for API compatibility.
   * @return List of visible keys.
   */
  override fun getKeys(
      allowList: List<String>?,
      options: SharedPreferencesPigeonOptions
  ): List<String> = MMKVPreferencesStore.getKeys(defaultStore(), allowList = allowList?.toSet())

  private fun defaultStore() = MMKVPreferencesStore.legacyStore(context)
}

/**
 * Async shared_preferences backend backed by MMKV.
 *
 * This preserves the public plugin protocol, including fileName-based separation.
 */
class SharedPreferencesBackend(
    private var messenger: BinaryMessenger,
    private var context: Context,
    private var listEncoder: SharedPreferencesListEncoder = ListEncoder()
) : SharedPreferencesAsyncApi {

  init {
    try {
      SharedPreferencesAsyncApi.setUp(messenger, this, "shared_preferences")
    } catch (error: Exception) {
      Log.e(TAG, "Received exception while setting up SharedPreferencesBackend", error)
    }
  }

  fun tearDown() {
    SharedPreferencesAsyncApi.setUp(messenger, null, "shared_preferences")
  }

  /**
   * Adds a boolean property to the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param value Boolean value to persist.
   * @param options Backend options from Flutter.
   */
  override fun setBool(key: String, value: Boolean, options: SharedPreferencesPigeonOptions) {
    MMKVPreferencesStore.putBoolean(store(options), key, value)
  }

  /**
   * Adds a string property to the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param value String value to persist.
   * @param options Backend options from Flutter.
   */
  override fun setString(key: String, value: String, options: SharedPreferencesPigeonOptions) {
    MMKVPreferencesStore.putString(store(options), key, value, isStringList = false)
  }

  /**
   * Adds an integer property to the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param value Integer value represented as long.
   * @param options Backend options from Flutter.
   */
  override fun setInt(key: String, value: Long, options: SharedPreferencesPigeonOptions) {
    MMKVPreferencesStore.putLong(store(options), key, value)
  }

  /**
   * Adds a double property to the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param value Double value to persist.
   * @param options Backend options from Flutter.
   */
  override fun setDouble(key: String, value: Double, options: SharedPreferencesPigeonOptions) {
    MMKVPreferencesStore.putDouble(store(options), key, value)
  }

  /**
   * Adds an encoded string-list payload to the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param value Encoded string-list payload.
   * @param options Backend options from Flutter.
   */
  override fun setEncodedStringList(
      key: String,
      value: String,
      options: SharedPreferencesPigeonOptions
  ) {
    MMKVPreferencesStore.putString(store(options), key, value, isStringList = true)
  }

  /**
   * Adds a deprecated platform-encoded string list to the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param value String list to encode.
   * @param options Backend options from Flutter.
   */
  @Deprecated("This is just for testing, use `setEncodedStringList`")
  override fun setDeprecatedStringList(
      key: String,
      value: List<String>,
      options: SharedPreferencesPigeonOptions
  ) {
    val valueString = LIST_PREFIX + listEncoder.encode(value)
    MMKVPreferencesStore.putString(store(options), key, valueString, isStringList = true)
  }

  /**
   * Removes all properties from the requested logical MMKV store.
   *
   * @param allowList Optional allow-list from Flutter.
   * @param options Backend options from Flutter.
   */
  override fun clear(allowList: List<String>?, options: SharedPreferencesPigeonOptions) {
    MMKVPreferencesStore.clear(store(options), allowList = allowList?.toSet())
  }

  /**
   * Gets all properties from the requested logical MMKV store.
   *
   * @param allowList Optional allow-list from Flutter.
   * @param options Backend options from Flutter.
   * @return Map of all visible key/value pairs.
   */
  override fun getAll(
      allowList: List<String>?,
      options: SharedPreferencesPigeonOptions
  ): Map<String, Any> = MMKVPreferencesStore.getAll(
      store(options),
      allowList = allowList?.toSet(),
      listEncoder = listEncoder,
  )

  /**
   * Gets a stored integer from the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter.
   * @return Stored integer as long, or null when absent.
   */
  override fun getInt(key: String, options: SharedPreferencesPigeonOptions): Long? =
      MMKVPreferencesStore.getLong(store(options), key)

  /**
   * Gets a stored boolean from the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter.
   * @return Stored boolean value, or null when absent.
   */
  override fun getBool(key: String, options: SharedPreferencesPigeonOptions): Boolean? =
      MMKVPreferencesStore.getBoolean(store(options), key)

  /**
   * Gets a stored double from the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter.
   * @return Stored double value, or null when absent.
   */
  override fun getDouble(key: String, options: SharedPreferencesPigeonOptions): Double? =
      MMKVPreferencesStore.getDouble(store(options), key)

  /**
   * Gets a stored raw string payload from the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter.
   * @return Raw string payload, or null when absent.
   */
  override fun getString(key: String, options: SharedPreferencesPigeonOptions): String? =
      MMKVPreferencesStore.getRawString(store(options), key)

  /**
   * Gets the lookup result for a stored string list from the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter.
   * @return String list lookup result, or null when absent.
   */
  override fun getStringList(
      key: String,
      options: SharedPreferencesPigeonOptions
  ): StringListResult? = MMKVPreferencesStore.getStringListResult(store(options), key)

  /**
   * Gets the decoded platform-encoded string list from the requested logical MMKV store.
   *
   * @param key Stored key.
   * @param options Backend options from Flutter.
   * @return Decoded string list, or null when absent.
   */
  override fun getPlatformEncodedStringList(
      key: String,
      options: SharedPreferencesPigeonOptions
  ): List<String>? = MMKVPreferencesStore.getPlatformEncodedStringList(
      store(options),
      key,
      listEncoder,
  )

  /**
   * Returns all visible keys from the requested logical MMKV store.
   *
   * @param allowList Optional allow-list from Flutter.
   * @param options Backend options from Flutter.
   * @return List of visible keys.
   */
  override fun getKeys(
      allowList: List<String>?,
      options: SharedPreferencesPigeonOptions
  ): List<String> = MMKVPreferencesStore.getKeys(store(options), allowList = allowList?.toSet())

  private fun store(options: SharedPreferencesPigeonOptions) =
      MMKVPreferencesStore.asyncStore(context, options)
}

/** Class that provides tools for encoding and decoding List<String> to String and back. */
class ListEncoder : SharedPreferencesListEncoder {
  override fun encode(list: List<String>): String {
    val byteStream = ByteArrayOutputStream()
    val stream = ObjectOutputStream(byteStream)
    stream.writeObject(list)
    stream.flush()
    return Base64.encodeToString(byteStream.toByteArray(), 0)
  }

  override fun decode(listString: String): List<String> {
    val byteArray = Base64.decode(listString, 0)
    val stream = StringListObjectInputStream(ByteArrayInputStream(byteArray))
    return (stream.readObject() as List<*>).filterIsInstance<String>()
  }
}

/**
 * Returns false for any preferences that are not included in [allowList].
 *
 * If no [allowList] is provided, this MMKV backend only exposes entries that carry valid
 * metadata written by the plugin itself.
 */
internal fun preferencesFilter(key: String, allowList: Set<String>?): Boolean {
  return allowList == null || allowList.contains(key)
}

/** Transforms preferences that are stored as Strings back to the original type. */
internal fun transformPref(value: Any?, listEncoder: SharedPreferencesListEncoder): Any? {
  if (value is String) {
    if (value.startsWith(LIST_PREFIX)) {
      return if (value.startsWith(JSON_LIST_PREFIX)) {
        value
      } else {
        listEncoder.decode(value.substring(LIST_PREFIX.length))
      }
    } else if (value.startsWith(DOUBLE_PREFIX)) {
      return value.substring(DOUBLE_PREFIX.length).toDouble()
    }
  }
  return value
}
