import 'package:flutter/material.dart';
import 'responsive/responsive_layout.dart';
import 'screens/web/web_dashboard_screen.dart';
import 'screens/mobile/mobile_home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.init();
  runApp(const AutoRepairApp());
}

class AutoRepairApp extends StatelessWidget {
  const AutoRepairApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;

        Widget homeWidget;
        if (!auth.isInitialized) {
          homeWidget = const Scaffold(
            backgroundColor: Color(0xFFF1F5F9),
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (!auth.isAuthenticated) {
          homeWidget = const LoginScreen();
        } else {
          homeWidget = const ResponsiveLayout(
            mobileBody: MobileHomeScreen(),
            webBody: WebDashboardScreen(),
          );
        }

        return MaterialApp(
          title: 'AutoKe Workshop Management',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primaryColor: const Color(0xFF0F4C81),
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F4C81)),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
          ),
          home: homeWidget,
        );
      },
    );
  }
}
