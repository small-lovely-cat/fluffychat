# -keep class net.sqlcipher.** { *; }
# WCDB AAR 自带 consumer ProGuard 规则，这里只保留显式入口兜底。
-keep class com.tencent.wcdb.** { *; }
