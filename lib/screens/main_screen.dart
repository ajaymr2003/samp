import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'station_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isVehicleView = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isVehicleView ? 'EV Vehicle Simulator' : 'Station Control Center'),
        elevation: 2,
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() {
                _isVehicleView = !_isVehicleView;
              });
            },
            icon: Icon(
              _isVehicleView ? Icons.ev_station_rounded : Icons.directions_car_rounded,
              color: Colors.white,
            ),
            label: Text(
              _isVehicleView ? 'Stations' : 'Vehicle',
              style: const TextStyle(color: Colors.white),
            ),
          )
        ],
      ),
      // By using a Stack and Offstage, we keep the state of both screens alive.
      // This is what allows the vehicle simulation to continue in the background.
      body: Stack(
        children: [
          Offstage(
            offstage: !_isVehicleView,
            child: const HomeScreen(),
          ),
          Offstage(
            offstage: _isVehicleView,
            child: const StationScreen(),
          ),
        ],
      ),
    );
  }
}