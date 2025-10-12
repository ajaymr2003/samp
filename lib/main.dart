import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/station_provider.dart';
import 'providers/vehicle_provider.dart';
import 'screens/main_screen.dart';
import 'services/api_service.dart';
import 'services/firebase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final firebaseService = FirebaseService();
    return MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider<VehicleProvider>(
          create: (_) => VehicleProvider(firebaseService: firebaseService),
        ),
        ChangeNotifierProvider<StationProvider>(
          create: (_) => StationProvider(firebaseService: firebaseService)
            // --- MODIFIED: Fetch stations as soon as the provider is created ---
            ..fetchStations(),
        ),
      ],
      child: MaterialApp(
        title: 'EV Flutter Simulator',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        home: const MainScreen(),
      ),
    );
  }
}