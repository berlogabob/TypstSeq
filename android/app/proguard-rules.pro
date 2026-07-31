# WorkManager's Room database: R8 full mode strips the generated
# WorkDatabase_Impl, and the Class.forName("...WorkDatabase_Impl") at process
# start then crashes the whole app before any Activity exists.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
