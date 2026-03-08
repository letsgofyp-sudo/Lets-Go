import 'package:flutter/material.dart';

import '../../services/chat_service.dart';
import '../../services/api_service.dart';
import 'driver_individual_chat_screen.dart';

class DriverChatMembersScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String tripId;

  const DriverChatMembersScreen({
    super.key,
    required this.userData,
    required this.tripId,
  });

  @override
  State<DriverChatMembersScreen> createState() => _DriverChatMembersScreenState();
}

class _DriverChatMembersScreenState extends State<DriverChatMembersScreen> {
  final Set<int> _selectedPassengerIds = <int>{};
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _passengers = const [];

  @override
  void initState() {
    super.initState();
    _loadPassengers();
  }

  Future<void> _loadPassengers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final passengers = await ApiService.getTripPassengers(widget.tripId);
      setState(() {
        _passengers = passengers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show confirmed / active bookings
    final filteredPassengers = _passengers.where((p) {
      final status = p['booking_status']?.toString().toUpperCase();
      return status == 'CONFIRMED';
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Passengers'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : filteredPassengers.isEmpty
                  ? const Center(
                      child: Text('No confirmed passengers for this trip'),
                    )
                  : ListView.builder(
                      itemCount: filteredPassengers.length,
                      itemBuilder: (context, index) {
                        final passenger = filteredPassengers[index];
                final name = passenger['name']?.toString() ??
                    passenger['full_name']?.toString() ??
                    'Passenger';
                final rating =
                    passenger['passenger_rating']?.toString() ?? 'N/A';
                final seats =
                    passenger['seats_booked']?.toString() ?? '1';

                final int totalSeats = int.tryParse(seats) ?? 1;
                int maleSeats = int.tryParse((passenger['male_seats'] ?? 0).toString()) ?? 0;
                int femaleSeats = int.tryParse((passenger['female_seats'] ?? 0).toString()) ?? 0;
                final String seatDisplay = (maleSeats + femaleSeats) > 0
                    ? '$totalSeats (M:$maleSeats F:$femaleSeats)'
                    : seats;

                final passengerId = int.tryParse(
                      passenger['id']?.toString() ??
                          passenger['user_id']?.toString() ??
                          '',
                    ) ??
                    0;

                final isSelected = _selectedPassengerIds.contains(passengerId);

                final rawPhoto = passenger['profile_photo'] ??
                    passenger['photo_url'] ??
                    passenger['profile_image'];
                final photoUrl = rawPhoto?.toString();

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: (photoUrl != null && photoUrl.startsWith('http'))
                        ? NetworkImage(photoUrl)
                        : null,
                    child: (photoUrl == null || !photoUrl.startsWith('http'))
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'P',
                          )
                        : null,
                  ),
                  title: Text(name),
                  subtitle: Text('Seats: $seatDisplay  •  Rating: $rating'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chat),
                      const SizedBox(width: 8),
                      Checkbox(
                        value: isSelected,
                        onChanged: passengerId == 0
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedPassengerIds.add(passengerId);
                                  } else {
                                    _selectedPassengerIds.remove(passengerId);
                                  }
                                });
                              },
                      ),
                    ],
                  ),
                  onTap: () {
                    if (passengerId == 0) {
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DriverIndividualChatScreen(
                          userData: widget.userData,
                          tripId: widget.tripId,
                          chatRoomId: widget.tripId, // same convention as passenger chat
                          passengerInfo: passenger,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: _selectedPassengerIds.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.campaign),
                label: const Text('Send Broadcast'),
                onPressed: () async {
                  final controller = TextEditingController();
                  final messageText = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Broadcast message'),
                      content: TextField(
                        controller: controller,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Type your announcement...',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                          child: const Text('Send'),
                        ),
                      ],
                    ),
                  );

                  if (messageText == null || messageText.isEmpty) {
                    return;
                  }

                  try {
                    final driverId = int.tryParse(
                          widget.userData['id']?.toString() ?? '',
                        ) ??
                        0;
                    final driverName =
                        widget.userData['name']?.toString() ?? 'Driver';

                    await ChatService.sendBroadcast(
                      chatRoomId: widget.tripId,
                      senderId: driverId,
                      senderName: driverName,
                      senderRole: 'driver',
                      messageText: messageText,
                      recipientIds: _selectedPassengerIds.toList(),
                    );

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Broadcast sent')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to send broadcast: $e')),
                    );
                  }
                },
              ),
            ),
    );
  }
}