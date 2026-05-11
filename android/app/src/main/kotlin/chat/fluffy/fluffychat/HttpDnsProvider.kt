package chat.fluffy.fluffychat

/**
 * Supported HTTPDNS provider identifiers exchanged with Flutter.
 */
enum class HttpDnsProvider(val storageValue: String) {
    NONE("none"),
    ALIYUN("aliyun");

    companion object {
        /**
         * Parses the stored provider value from Flutter.
         *
         * @param value Provider identifier from shared preferences or method channel.
         * @return Matching provider enum, or [NONE] when the value is unknown.
         */
        fun fromStorageValue(value: String?): HttpDnsProvider =
            entries.firstOrNull { it.storageValue == value } ?: NONE
    }
}
