import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
// import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Activar cuando tengas tu proyecto Supabase:
  // await SyncService.init(
  //   url: 'https://TU-PROYECTO.supabase.co',
  //   publishableKey: 'TU-PUBLISHABLE-KEY',
  // );

  runApp(const GestorDocsApp());
}

class GestorDocsApp extends StatelessWidget {
  const GestorDocsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestor de Documentos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
