import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/station_model.dart';
import '../providers/station_provider.dart';

class StationScreen extends StatefulWidget {
  const StationScreen({Key? key}) : super(key: key);

  @override
  State<StationScreen> createState() => _StationScreenState();
}

class _StationScreenState extends State<StationScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch stations when the widget is first built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<StationProvider>(context, listen: false).fetchStations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<StationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.stations.isEmpty) {
            return const Center(child: Text('No stations found.'));
          }
          return RefreshIndicator(
            onRefresh: () => provider.fetchStations(),
            child: Column(
              children: [
                _buildPresetButtons(provider),
                const Divider(height: 1),
                Expanded(child: _buildStationList(provider)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPresetButtons(StationProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Environment Presets (Automated)",
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: ElevatedButton(
                      onPressed: () => provider.applyPreset(Preset.ideal),
                      child: const Text('Ideal'))),
              const SizedBox(width: 8),
              Expanded(
                  child: ElevatedButton(
                      onPressed: () => provider.applyPreset(Preset.normal),
                      child: const Text('Normal'))),
              const SizedBox(width: 8),
              Expanded(
                  child: ElevatedButton(
                      onPressed: () => provider.applyPreset(Preset.busy),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                      child: const Text('Busy'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStationList(StationProvider provider) {
    return ListView.builder(
      itemCount: provider.stations.length,
      itemBuilder: (context, index) {
        final station = provider.stations[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ExpansionTile(
            title: Text(station.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(station.address),
            trailing: Chip(
              label: Text('${station.availableSlots} / ${station.slots.length}'),
              backgroundColor: station.availableSlots > 0 ? Colors.green.shade100 : Colors.red.shade100,
            ),
            children: station.slots.asMap().entries.map((entry) {
              int slotIndex = entry.key;
              Slot slot = entry.value;
              return SwitchListTile(
                title: Text('Slot ${slotIndex + 1} (${slot.powerKw}kW)'),
                subtitle: Text(slot.chargerType),
                value: slot.isAvailable,
                onChanged: (bool value) {
                  provider.updateSlot(station, slotIndex, value);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}