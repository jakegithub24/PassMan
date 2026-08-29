import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/login_signup_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge immersive system UI for Android & iOS
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(const ProviderScope(child: PassManApp()));
}

class PassManApp extends StatelessWidget {
  const PassManApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PassMan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        splashFactory: InkSparkle.splashFactory,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.navy,
          primary: AppColors.navy,
          surface: AppColors.frameBg,
        ),
        scaffoldBackgroundColor: AppColors.frameBg,
      ),
      home: const LoginSignupScreen(),
    );
  }
}
