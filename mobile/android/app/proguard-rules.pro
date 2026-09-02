# Flutter itself needs no rules, but the protobuf runtime reflects over
# generated message classes; keep them so release builds do not strip fields.
-keep class com.google.protobuf.** { *; }
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
