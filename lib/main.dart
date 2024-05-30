import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:live_location_v2/test_component.dart';

import 'firebase_options.dart';
import 'login_page/auth_gate.dart';
import 'new_login_page/login_page.dart';
import 'location/map_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: AuthGate(),
      debugShowCheckedModeBanner: false
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _checkUserLoggedIn(),
      builder: (context, snapshot) {
        // Show loading indicator while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // If user is logged in, navigate to MapScreen
        if (snapshot.data != null) {
          return MapScreen();
        }
        // If user is not logged in, navigate to LoginPage
        return LoginPage();
      },
    );
  }

  Future<User?> _checkUserLoggedIn() async {
    return FirebaseAuth.instance.currentUser;
  }
}
