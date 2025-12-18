import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/calamity_provider.dart';
import '../../models/calamity_event_model.dart';
import '../../providers/auth_provider.dart';

class CalamityEventsScreen extends StatefulWidget {
  const CalamityEventsScreen({super.key});

  @override
  State<CalamityEventsScreen> createState() => _CalamityEventsScreenState();
}

class _CalamityEventsScreenState extends State<CalamityEventsScreen> {
  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEvents();
    });
  }

  void _loadEvents() {
    Provider.of<CalamityProvider>(
      context,
      listen: false,
    ).loadActiveCalamityEvents();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.uid ?? '';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            );
          },
        ),
        title: const Text(
          'Calamity Relief',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _primaryColor,
                    _primaryColor.withValues(alpha: 0.8),
                    _primaryColor.withValues(alpha: 0.6),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.emergency_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Calamity Relief',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Help those in need',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (currentUserId.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('My Donations'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/calamity/my-donations');
                },
              ),
          ],
        ),
      ),
      body: Consumer<CalamityProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.activeCalamityEvents.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                await provider.loadActiveCalamityEvents();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No active calamity events',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Check back later for relief efforts',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _loadEvents(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await provider.loadActiveCalamityEvents();
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: provider.activeCalamityEvents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final event = provider.activeCalamityEvents[index];
                return _buildEventCard(context, event);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, CalamityEventModel event) {
    final isExpired = event.deadline.isBefore(DateTime.now());
    final daysRemaining = event.deadline.difference(DateTime.now()).inDays;

    String _formatDate(DateTime date) {
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
    }

    String _formatTime(DateTime date) {
      final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
      final minute = date.minute.toString().padLeft(2, '0');
      final amPm = date.hour < 12 ? 'AM' : 'PM';
      return '$hour:$minute $amPm';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Image
          if (event.bannerUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Stack(
                children: [
                  Image.network(
                    event.bannerUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 180,
                        color: Colors.grey[300],
                        child: const Icon(Icons.image_not_supported, size: 48),
                      );
                    },
                  ),
                  if (isExpired)
                    Container(
                      height: 180,
                      color: Colors.black54,
                      child: const Center(
                        child: Text(
                          'EXPIRED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Calamity Type
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Text(
                        event.calamityType,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Description
                Text(
                  event.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                ),
                const SizedBox(height: 12),
                // Needed Items Preview
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: event.neededItems.take(4).map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 11,
                          color: _primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (event.neededItems.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+${event.neededItems.length - 4} more items',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ),
                const SizedBox(height: 12),
                // Location
                Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: _primaryColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        event.dropoffLocation,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Deadline
                Row(
                  children: [
                    Icon(
                      Icons.event,
                      size: 16,
                      color: isExpired ? Colors.red[700] : Colors.orange[700],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isExpired
                            ? 'Deadline passed: ${_formatDate(event.deadline)}'
                            : daysRemaining > 0
                            ? 'Deadline: ${_formatDate(event.deadline)} ($daysRemaining days left)'
                            : 'Deadline: ${_formatDate(event.deadline)} ${_formatTime(event.deadline)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isExpired ? Colors.red[700] : Colors.grey[700],
                          fontWeight: isExpired
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isExpired
                        ? null
                        : () {
                            Navigator.pushNamed(
                              context,
                              '/calamity/detail',
                              arguments: {'eventId': event.eventId},
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      isExpired ? 'Event Expired' : 'View Details & Donate',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
