package io.flutter.plugins.sharedpreferences

import android.content.Context
import com.tencent.mmkv.MMKV

private const val DEFAULT_MMKV_ID = SHARED_PREFERENCES_NAME
private const val TYPE_KEY_PREFIX = "__flutter_mmkv_type__:"
private const val DEFAULT_SHARED_PREFERENCES_SUFFIX = "_preferences"

private enum class StoredValueType {
  BOOL,
  INT,
  DOUBLE,
  STRING,
  STRING_LIST,
}

/**
 * Provides a MMKV-backed implementation that keeps the shared_preferences wire protocol intact.
 *
 * This store is now MMKV-only. No legacy SharedPreferences/DataStore migration is performed.
 */
internal object MMKVPreferencesStore {
  /**
   * Initializes MMKV on first access.
   *
   * @param context Application context used for MMKV init.
   */
  @JvmStatic
  fun initialize(context: Context) {
    MMKV.initialize(context)
  }

  /**
   * Returns the MMKV instance used by the legacy `SharedPreferences` API.
   *
   * @param context Application context.
   * @return MMKV instance for the default Flutter shared preferences store.
   */
  @JvmStatic
  fun legacyStore(context: Context): MMKV {
    initialize(context)
    return mmkvForId(DEFAULT_MMKV_ID)
  }

  /**
   * Returns the MMKV instance used by the async API for the requested backend.
   *
   * @param context Application context.
   * @param options Backend options coming from the Flutter plugin API.
   * @return MMKV instance matching the requested logical store.
   */
  @JvmStatic
  fun asyncStore(context: Context, options: SharedPreferencesPigeonOptions): MMKV {
    initialize(context)
    return when {
      options.useDataStore -> mmkvForId(DEFAULT_MMKV_ID)
      options.fileName != null -> mmkvForId(options.fileName!!)
      else -> mmkvForId("${context.packageName}$DEFAULT_SHARED_PREFERENCES_SUFFIX")
    }
  }

  /**
   * Stores a boolean value and its type metadata.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @param value Boolean value to persist.
   * @return True when MMKV accepts the write.
   */
  @JvmStatic
  fun putBoolean(store: MMKV, key: String, value: Boolean): Boolean {
    putType(store, key, StoredValueType.BOOL)
    return store.encode(key, value)
  }

  /**
   * Stores a long value and its type metadata.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @param value Integer value represented as long.
   * @return True when MMKV accepts the write.
   */
  @JvmStatic
  fun putLong(store: MMKV, key: String, value: Long): Boolean {
    putType(store, key, StoredValueType.INT)
    return store.encode(key, value)
  }

  /**
   * Stores a double value and its type metadata.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @param value Double value to persist.
   * @return True when MMKV accepts the write.
   */
  @JvmStatic
  fun putDouble(store: MMKV, key: String, value: Double): Boolean {
    putType(store, key, StoredValueType.DOUBLE)
    return store.encode(key, value)
  }

  /**
   * Stores a raw string value and its type metadata.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @param value String value to persist.
   * @param isStringList Whether this string actually represents an encoded string list.
   * @return True when MMKV accepts the write.
   */
  @JvmStatic
  fun putString(store: MMKV, key: String, value: String, isStringList: Boolean = false): Boolean {
    putType(store, key, if (isStringList) StoredValueType.STRING_LIST else StoredValueType.STRING)
    return store.encode(key, value)
  }

  /**
   * Removes a value together with its type metadata.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @return True when the operation completes.
   */
  @JvmStatic
  fun remove(store: MMKV, key: String): Boolean {
    store.removeValueForKey(key)
    store.removeValueForKey(typeKey(key))
    return true
  }

  /**
   * Clears matching values from a MMKV instance.
   *
   * @param store MMKV instance.
   * @param prefix Optional prefix filter.
   * @param allowList Optional explicit allow-list.
   * @return True when the operation completes.
   */
  @JvmStatic
  fun clear(store: MMKV, prefix: String? = null, allowList: Set<String>? = null): Boolean {
    val keys = store.allKeys() ?: return true
    for (key in keys) {
      if (isInternalKey(key)) {
        continue
      }
      if (prefix != null && !key.startsWith(prefix)) {
        continue
      }
      if (allowList != null && !allowList.contains(key)) {
        continue
      }
      remove(store, key)
    }
    return true
  }

  /**
   * Reads all visible values from MMKV using the same transformed value rules as the plugin.
   *
   * @param store MMKV instance.
   * @param prefix Optional prefix filter.
   * @param allowList Optional explicit allow-list.
   * @param listEncoder Decoder for legacy platform-encoded string lists.
   * @return Key/value map visible to Flutter.
   */
  @JvmStatic
  fun getAll(
      store: MMKV,
      prefix: String? = null,
      allowList: Set<String>? = null,
      listEncoder: SharedPreferencesListEncoder
  ): Map<String, Any> {
    val filteredPrefs = HashMap<String, Any>()
    val keys = store.allKeys() ?: return filteredPrefs
    for (key in keys) {
      if (isInternalKey(key)) {
        continue
      }
      if (prefix != null && !key.startsWith(prefix)) {
        continue
      }
      if (allowList != null && !allowList.contains(key)) {
        continue
      }
      val value = getTransformedValue(store, key, listEncoder) ?: continue
      filteredPrefs[key] = value
    }
    return filteredPrefs
  }

  /**
   * Returns all visible keys from MMKV.
   *
   * @param store MMKV instance.
   * @param prefix Optional prefix filter.
   * @param allowList Optional explicit allow-list.
   * @return List of external keys.
   */
  @JvmStatic
  fun getKeys(store: MMKV, prefix: String? = null, allowList: Set<String>? = null): List<String> {
    val keys = store.allKeys() ?: return emptyList()
    return keys
        .filterNot(::isInternalKey)
        .filter { prefix == null || it.startsWith(prefix) }
        .filter { allowList == null || allowList.contains(it) }
  }

  /**
   * Reads a boolean value if the stored type matches.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @return Stored boolean value, or null when absent/type-mismatched.
   */
  @JvmStatic
  fun getBoolean(store: MMKV, key: String): Boolean? {
    if (getType(store, key) != StoredValueType.BOOL || !store.containsKey(key)) {
      return null
    }
    return store.decodeBool(key)
  }

  /**
   * Reads a long value if the stored type matches.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @return Stored long value, or null when absent/type-mismatched.
   */
  @JvmStatic
  fun getLong(store: MMKV, key: String): Long? {
    if (getType(store, key) != StoredValueType.INT || !store.containsKey(key)) {
      return null
    }
    return store.decodeLong(key)
  }

  /**
   * Reads a double value if the stored type matches.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @return Stored double value, or null when absent/type-mismatched.
   */
  @JvmStatic
  fun getDouble(store: MMKV, key: String): Double? {
    if (getType(store, key) != StoredValueType.DOUBLE || !store.containsKey(key)) {
      return null
    }
    return store.decodeDouble(key)
  }

  /**
   * Reads the raw stored string for string and string-list types.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @return Raw string payload, or null when absent/type-mismatched.
   */
  @JvmStatic
  fun getRawString(store: MMKV, key: String): String? {
    val type = getType(store, key)
    if ((type != StoredValueType.STRING && type != StoredValueType.STRING_LIST) || !store.containsKey(key)) {
      return null
    }
    return store.decodeString(key)
  }

  /**
   * Returns the async API string-list lookup result for a stored list.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @return StringListResult describing the stored representation, or null if absent.
   */
  @JvmStatic
  fun getStringListResult(store: MMKV, key: String): StringListResult? {
    val rawValue = getRawString(store, key) ?: return null
    return when {
      rawValue.startsWith(JSON_LIST_PREFIX) ->
          StringListResult(rawValue, StringListLookupResultType.JSON_ENCODED)
      rawValue.startsWith(LIST_PREFIX) ->
          StringListResult(null, StringListLookupResultType.PLATFORM_ENCODED)
      else -> StringListResult(null, StringListLookupResultType.UNEXPECTED_STRING)
    }
  }

  /**
   * Decodes a legacy platform-encoded list when that representation is present.
   *
   * @param store MMKV instance.
   * @param key Stored key.
   * @param listEncoder Decoder for the legacy binary list format.
   * @return Decoded string list, or null when the key is absent/not platform-encoded.
   */
  @JvmStatic
  fun getPlatformEncodedStringList(
      store: MMKV,
      key: String,
      listEncoder: SharedPreferencesListEncoder
  ): List<String>? {
    val rawValue = getRawString(store, key) ?: return null
    if (!rawValue.startsWith(LIST_PREFIX) || rawValue.startsWith(JSON_LIST_PREFIX)) {
      return null
    }
    return listEncoder.decode(rawValue.substring(LIST_PREFIX.length))
  }

  private fun getTransformedValue(
      store: MMKV,
      key: String,
      listEncoder: SharedPreferencesListEncoder
  ): Any? {
    return when (getType(store, key)) {
      StoredValueType.BOOL -> store.decodeBool(key)
      StoredValueType.INT -> store.decodeLong(key)
      StoredValueType.DOUBLE -> store.decodeDouble(key)
      StoredValueType.STRING -> store.decodeString(key)
      StoredValueType.STRING_LIST -> {
        val rawValue = store.decodeString(key) ?: return null
        transformPref(rawValue, listEncoder)
      }
      null -> null
    }
  }

  private fun putType(store: MMKV, key: String, type: StoredValueType) {
    store.encode(typeKey(key), type.name)
  }

  private fun getType(store: MMKV, key: String): StoredValueType? {
    val rawType = store.decodeString(typeKey(key)) ?: return null
    return StoredValueType.entries.firstOrNull { it.name == rawType }
  }

  private fun mmkvForId(id: String): MMKV = MMKV.mmkvWithID(id, MMKV.MULTI_PROCESS_MODE)

  private fun typeKey(key: String): String = TYPE_KEY_PREFIX + key

  private fun isInternalKey(key: String): Boolean =
      key.startsWith(TYPE_KEY_PREFIX)
}
