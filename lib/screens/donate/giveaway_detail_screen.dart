import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/giveaway_listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/giveaway_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/report_block_service.dart';
import '../../reusable_widgets/report_dialog.dart';

class GiveawayDetailScreen extends StatefulWidget {
  const GiveawayDetailScreen({super.key});

  @override
  State<GiveawayDetailScreen> createState() => _GiveawayDetailScreenState();
}

class _GiveawayDetailScreenState extends State<GiveawayDetailScreen> {
  final FirestoreService _firestore = FirestoreService();
  final ReportBlockService _reportBlockService = ReportBlockService();
  GiveawayListingModel? _giveaway;
  bool _isLoading = true;
  bool _hasPendingClaim = false;
  final TextEditingController _messageController = TextEditingController();
  bool _showClaimDialog = false;

  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && args['giveawayId'] != null) {
      _loadGiveaway(args['giveawayId'] as String);
    }
  }

  Future<void> _loadGiveaway(String giveawayId) async {
    setState(() {
      _isLoading = true;
    });

    final giveawayProvider = Provider.of<GiveawayProvider>(
      context,
      listen: false,
    );
    final giveaway = await giveawayProvider.getGiveaway(giveawayId);

    if (giveaway != null) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid;

      if (currentUserId != null && giveaway.isAvailable) {
        // Check if user has pending claim request
        final hasPending = await _firestore.hasPendingClaimRequest(
          giveawayId: giveawayId,
          claimantId: currentUserId,
        );
        setState(() {
          _hasPendingClaim = hasPending;
        });
      }
    }

    setState(() {
      _giveaway = giveaway;
      _isLoading = false;
    });
  }

  Future<void> _handleClaim() async {
    if (_giveaway == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    final currentUser = Provider.of<UserProvider>(
      context,
      listen: false,
    ).currentUser;

    if (currentUserId == null || currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to claim a giveaway'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Don't allow claiming own giveaway
    if (currentUserId == _giveaway!.donorId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot claim your own giveaway'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_giveaway!.claimMode == ClaimMode.firstCome) {
      // First come, first served - claim immediately
      final giveawayProvider = Provider.of<GiveawayProvider>(
        context,
        listen: false,
      );
      final success = await giveawayProvider.markGiveawayAsClaimed(
        giveawayId: _giveaway!.id,
        claimedBy: currentUserId,
        claimedByName: currentUser.fullName,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully claimed!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadGiveaway(_giveaway!.id);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              giveawayProvider.errorMessage ?? 'Failed to claim giveaway',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      // Approval required - create claim request
      setState(() {
        _showClaimDialog = true;
      });
    }
  }

  Future<void> _submitClaimRequest() async {
    if (_giveaway == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    final currentUser = Provider.of<UserProvider>(
      context,
      listen: false,
    ).currentUser;

    if (currentUserId == null || currentUser == null) return;

    final giveawayProvider = Provider.of<GiveawayProvider>(
      context,
      listen: false,
    );
    final claimRequestId = await giveawayProvider.createClaimRequest(
      giveawayId: _giveaway!.id,
      claimantId: currentUserId,
      claimantName: currentUser.fullName,
      donorId: _giveaway!.donorId,
      message: _messageController.text.trim().isNotEmpty
          ? _messageController.text.trim()
          : null,
    );

    if (claimRequestId != null && mounted) {
      setState(() {
        _showClaimDialog = false;
        _hasPendingClaim = true;
        _messageController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Claim request submitted! Waiting for approval.'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            giveawayProvider.errorMessage ?? 'Failed to submit claim request',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          title: const Text('Giveaway Details'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_giveaway == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          title: const Text('Giveaway Details'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Giveaway not found',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.uid;
    final isOwner = currentUserId == _giveaway!.donorId;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Giveaway Details'),
        actions: [
          if (!isOwner && _giveaway!.isAvailable)
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Report',
              onPressed: () => _reportGiveaway(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Image Gallery
          if (_giveaway!.hasImages) ...[
            Container(
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.grey[200],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: PageView.builder(
                  itemCount: _giveaway!.images.length,
                  itemBuilder: (context, index) {
                    return Image.network(
                      _giveaway!.images[index],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(Icons.image_not_supported, size: 64),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            if (_giveaway!.images.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    '${_giveaway!.images.length} photos - Swipe to view',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ] else
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.grey[200],
              ),
              child: const Center(
                child: Icon(Icons.image_not_supported_outlined, size: 64),
              ),
            ),
          const SizedBox(height: 24),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _giveaway!.isAvailable
                  ? const Color(0xFF2ECC71).withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _giveaway!.isAvailable
                    ? const Color(0xFF2ECC71)
                    : Colors.grey,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _giveaway!.isAvailable ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: _giveaway!.isAvailable
                      ? const Color(0xFF2ECC71)
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _giveaway!.statusDisplay,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _giveaway!.isAvailable
                        ? const Color(0xFF2ECC71)
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            _giveaway!.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),

          // Category and Claim Mode
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _giveaway!.category,
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _giveaway!.claimModeDisplay,
                  style: TextStyle(
                    color: Colors.orange[700],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_giveaway!.condition != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _giveaway!.condition!,
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Description
          Text(
            'Description',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _giveaway!.description,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Donor Info
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _primaryColor.withOpacity(0.2),
                    child: Icon(Icons.person, color: _primaryColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Donor',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _giveaway!.donorName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Location
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: _primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Location',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _giveaway!.location,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Pickup Notes
          if (_giveaway!.pickupNotes != null &&
              _giveaway!.pickupNotes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.note, color: _primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Pickup Notes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _giveaway!.pickupNotes!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Claimed Info
          if (_giveaway!.isClaimed) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              color: Colors.grey[100],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Claimed',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _giveaway!.claimedByName ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (_giveaway!.claimedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Claimed on ${_formatDate(_giveaway!.claimedAt!)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Action Button
          if (!isOwner && _giveaway!.isAvailable)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                onPressed: _hasPendingClaim ? null : _handleClaim,
                child: _hasPendingClaim
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.hourglass_empty),
                          SizedBox(width: 8),
                          Text(
                            'Claim Request Pending',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        _giveaway!.claimMode == ClaimMode.firstCome
                            ? 'Claim Now'
                            : 'Request to Claim',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
      // Claim Request Dialog
      bottomSheet: _showClaimDialog
          ? Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Request to Claim',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _showClaimDialog = false;
                            _messageController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Message (Optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Add a message for the donor...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryColor, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _showClaimDialog = false;
                              _messageController.clear();
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _submitClaimRequest,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Submit Request',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                ],
              ),
            )
          : null,
    );
  }

  void _reportGiveaway() {
    if (_giveaway == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    if (authProvider.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to report a giveaway'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    ReportDialog.showReportContentDialog(
      context: context,
      contentType: 'giveaway',
      onSubmit:
          ({
            required String reason,
            String? description,
            List<String>? evidenceImageUrls,
          }) async {
            final reporterName =
                userProvider.currentUser?.fullName ??
                authProvider.user!.email ??
                'Unknown';

            await _reportBlockService.reportContent(
              reporterId: authProvider.user!.uid,
              reporterName: reporterName,
              contentType: 'giveaway',
              contentId: _giveaway!.id,
              contentTitle: _giveaway!.title,
              ownerId: _giveaway!.donorId,
              ownerName: _giveaway!.donorName,
              reason: reason,
              description: description,
              evidenceImageUrls: evidenceImageUrls,
            );
          },
      successMessage:
          'Giveaway has been reported successfully. Thank you for keeping the community safe.',
      errorMessage: 'Error reporting giveaway',
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
