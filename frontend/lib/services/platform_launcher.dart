export 'platform_launcher_stub.dart'
    if (dart.library.html) 'platform_launcher_web.dart'
    if (dart.library.io) 'platform_launcher_io.dart';
