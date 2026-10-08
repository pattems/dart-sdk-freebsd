--- runtime/bin/directory_linux.cc.orig	2026-09-29 08:00:52 UTC
+++ runtime/bin/directory_linux.cc
@@ -22,6 +22,7 @@
 #include "bin/file.h"
 #include "bin/namespace.h"
 #include "bin/platform.h"
+#include "platform/largefile.h"
 #include "platform/signal_blocker.h"
 
 namespace dart {
