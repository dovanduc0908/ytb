# ExtraFieldUtils instantiates ZIP field implementations reflectively while unpacking Python.
# Keeping this package preserves concrete classes and public no-argument constructors.
-keep class org.apache.commons.compress.archivers.zip.** { *; }
