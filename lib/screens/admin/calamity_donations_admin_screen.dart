import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/calamity_provider.dart';
import '../../models/calamity_donation_model.dart';

class CalamityDonationsAdminScreen extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const CalamityDonationsAdminScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<CalamityDonationsAdminScreen> createState() =>
      _CalamityDonationsAdminScreenState();
}

class _CalamityDonationsAdminScreenState
    extends State<CalamityDonationsAdminScreen> {
  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CalamityProvider>(
        context,
        listen: false,
      ).loadDonationsByEvent(widget.eventId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Donations - ${widget.eventTitle}'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Consumer<CalamityProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.calamityDonations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No donations yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }

          // Group by status
          final pendingDonations = provider.calamityDonations
              .where((d) => d.isPending)
              .toList();
          final receivedDonations = provider.calamityDonations
              .where((d) => d.isReceived)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Statistics
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard(
                        'Total',
                        provider.calamityDonations.length.toString(),
                        Colors.blue,
                      ),
                      _buildStatCard(
                        'Pending',
                        pendingDonations.length.toString(),
                        Colors.orange,
                      ),
                      _buildStatCard(
                        'Received',
                        receivedDonations.length.toString(),
                        Colors.green,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Pending Donations
              if (pendingDonations.isNotEmpty) ...[
                Text(
                  'Pending Donations (${pendingDonations.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...pendingDonations.map(
                  (donation) =>
                      _buildDonationCard(context, donation, provider, true),
                ),
                const SizedBox(height: 24),
              ],
              // Received Donations
              if (receivedDonations.isNotEmpty) ...[
                Text(
                  'Received Donations (${receivedDonations.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...receivedDonations.map(
                  (donation) =>
                      _buildDonationCard(context, donation, provider, false),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildDonationCard(
    BuildContext context,
    CalamityDonationModel donation,
    CalamityProvider provider,
    bool isPending,
  ) {
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
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        donation.itemType,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Quantity: ${donation.quantity}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isPending ? Colors.orange : Colors.green,
                    ),
                  ),
                  child: Text(
                    donation.statusDisplay,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isPending ? Colors.orange[700] : Colors.green[700],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.email_outlined, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    donation.donorEmail,
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '${_formatDate(donation.createdAt)} ${_formatTime(donation.createdAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            if (donation.notes != null && donation.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notes:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      donation.notes!,
                      style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                    ),
                  ],
                ),
              ),
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _markAsReceived(context, donation, provider),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Mark as Received'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _markAsReceived(
    BuildContext context,
    CalamityDonationModel donation,
    CalamityProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Received'),
        content: Text(
          'Mark donation of ${donation.quantity} ${donation.itemType} as received?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await provider.updateDonationStatus(
                donationId: donation.donationId,
                status: CalamityDonationStatus.received,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Donation marked as received'
                          : 'Failed to update: ${provider.errorMessage}',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
                if (success) {
                  provider.loadDonationsByEvent(widget.eventId);
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}
