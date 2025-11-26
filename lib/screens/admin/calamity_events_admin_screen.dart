import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/calamity_provider.dart';
import '../../models/calamity_event_model.dart';
import 'create_edit_calamity_event_screen.dart';
import 'calamity_event_detail_admin_screen.dart';

class CalamityEventsAdminScreen extends StatefulWidget {
  const CalamityEventsAdminScreen({super.key});

  @override
  State<CalamityEventsAdminScreen> createState() =>
      _CalamityEventsAdminScreenState();
}

class _CalamityEventsAdminScreenState extends State<CalamityEventsAdminScreen> {
  static const Color _primaryColor = Color(0xFF2A7A9E);

  // Search and Filter Controllers
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatusFilter = 'All';
  String _selectedCalamityTypeFilter = 'All';
  String _selectedSortBy = 'Date Created (Newest)';
  Map<String, int> _donationCounts = {}; // Cache donation counts per event
  bool _isFiltersExpanded = false; // Track filter expansion state

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<CalamityProvider>(context, listen: false);
      provider.loadAllCalamityEvents().then((_) {
        _loadDonationCounts(provider);
      });
    });
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDonationCounts(CalamityProvider provider) async {
    final counts = <String, int>{};
    for (final event in provider.calamityEvents) {
      try {
        final count = await provider.getDonationCountByEvent(event.eventId);
        counts[event.eventId] = count;
      } catch (_) {
        counts[event.eventId] = 0;
      }
    }
    if (mounted) {
      setState(() {
        _donationCounts = counts;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calamity Events Management'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create New Event',
            onPressed: () {
              CreateEditCalamityEventScreen.show(context).then((_) {
                final provider = Provider.of<CalamityProvider>(
                  context,
                  listen: false,
                );
                provider.loadAllCalamityEvents().then((_) {
                  _loadDonationCounts(provider);
                });
              });
            },
          ),
        ],
      ),
      body: Consumer<CalamityProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.calamityEvents.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          // Get filtered and sorted events
          final filteredEvents = _getFilteredAndSortedEvents(provider);

          return Column(
            children: [
              // Statistics Dashboard
              _buildStatisticsDashboard(provider),
              // Search and Filter Bar
              _buildSearchAndFilterBar(),
              // Events Grid
              Expanded(
                child: filteredEvents.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No events found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try adjusting your search or filters',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          int crossAxisCount = 1;
                          if (width >= 1200) {
                            crossAxisCount = 3;
                          } else if (width >= 800) {
                            crossAxisCount = 2;
                          }

                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  childAspectRatio: 1.05,
                                ),
                            itemCount: filteredEvents.length,
                            itemBuilder: (context, index) {
                              final event = filteredEvents[index];
                              return _buildEventCard(context, event, provider);
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          CreateEditCalamityEventScreen.show(context).then((_) {
            final provider = Provider.of<CalamityProvider>(
              context,
              listen: false,
            );
            provider.loadAllCalamityEvents().then((_) {
              _loadDonationCounts(provider);
            });
          });
        },
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Create New Event'),
      ),
    );
  }

  // Statistics Dashboard
  Widget _buildStatisticsDashboard(CalamityProvider provider) {
    final events = provider.calamityEvents;
    final activeEvents = events.where((e) {
      final isExpired = e.deadline.isBefore(DateTime.now());
      return e.isActive && !isExpired;
    }).length;
    final closedEvents = events
        .where((e) => e.status == CalamityEventStatus.closed)
        .length;
    final expiredEvents = events.where((e) {
      return e.deadline.isBefore(DateTime.now()) ||
          e.status == CalamityEventStatus.expired;
    }).length;

    final totalDonations = _donationCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final totalDonors = _donationCounts.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildStatCard(
                  'Total Events',
                  events.length.toString(),
                  Icons.event,
                  Colors.blue,
                  180,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  'Active',
                  activeEvents.toString(),
                  Icons.check_circle,
                  Colors.green,
                  180,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  'Closed',
                  closedEvents.toString(),
                  Icons.close,
                  Colors.orange,
                  180,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  'Expired',
                  expiredEvents.toString(),
                  Icons.event_busy,
                  Colors.red,
                  180,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  'Total Donations',
                  totalDonations.toString(),
                  Icons.favorite,
                  Colors.pink,
                  180,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  'Total Donors',
                  totalDonors.toString(),
                  Icons.people,
                  Colors.purple,
                  180,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
    double width,
  ) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Search and Filter Bar
  Widget _buildSearchAndFilterBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search Bar with Toggle Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText:
                          'Search by title, description, or calamity type...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                // Filter Toggle Button
                Tooltip(
                  message: _isFiltersExpanded ? 'Hide Filters' : 'Show Filters',
                  child: IconButton(
                    icon: Icon(
                      _isFiltersExpanded
                          ? Icons.filter_list
                          : Icons.filter_list_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        _isFiltersExpanded = !_isFiltersExpanded;
                      });
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: _isFiltersExpanded
                          ? _primaryColor.withOpacity(0.1)
                          : Colors.grey[100],
                      foregroundColor: _isFiltersExpanded
                          ? _primaryColor
                          : Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Collapsible Filters Section
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _isFiltersExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 600;
                  return isWide
                      ? Row(
                          children: [
                            Expanded(child: _buildStatusFilter()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildCalamityTypeFilter()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildSortDropdown()),
                          ],
                        )
                      : Column(
                          children: [
                            _buildStatusFilter(),
                            const SizedBox(height: 12),
                            _buildCalamityTypeFilter(),
                            const SizedBox(height: 12),
                            _buildSortDropdown(),
                          ],
                        );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilter() {
    return DropdownButtonFormField<String>(
      value: _selectedStatusFilter,
      decoration: InputDecoration(
        labelText: 'Status',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'All', child: Text('All Status')),
        DropdownMenuItem(value: 'Active', child: Text('Active')),
        DropdownMenuItem(value: 'Closed', child: Text('Closed')),
        DropdownMenuItem(value: 'Expired', child: Text('Expired')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedStatusFilter = value ?? 'All';
        });
      },
    );
  }

  Widget _buildCalamityTypeFilter() {
    return DropdownButtonFormField<String>(
      value: _selectedCalamityTypeFilter,
      decoration: InputDecoration(
        labelText: 'Calamity Type',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'All', child: Text('All Types')),
        DropdownMenuItem(value: 'Flood', child: Text('Flood')),
        DropdownMenuItem(value: 'Fire', child: Text('Fire')),
        DropdownMenuItem(value: 'Typhoon', child: Text('Typhoon')),
        DropdownMenuItem(value: 'Earthquake', child: Text('Earthquake')),
        DropdownMenuItem(value: 'Landslide', child: Text('Landslide')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedCalamityTypeFilter = value ?? 'All';
        });
      },
    );
  }

  Widget _buildSortDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedSortBy,
      decoration: InputDecoration(
        labelText: 'Sort By',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
      ),
      items: const [
        DropdownMenuItem(
          value: 'Date Created (Newest)',
          child: Text('Date Created (Newest)'),
        ),
        DropdownMenuItem(
          value: 'Date Created (Oldest)',
          child: Text('Date Created (Oldest)'),
        ),
        DropdownMenuItem(
          value: 'Deadline (Upcoming)',
          child: Text('Deadline (Upcoming)'),
        ),
        DropdownMenuItem(
          value: 'Deadline (Expired)',
          child: Text('Deadline (Expired)'),
        ),
        DropdownMenuItem(
          value: 'Donations (Most)',
          child: Text('Donations (Most)'),
        ),
        DropdownMenuItem(
          value: 'Donations (Least)',
          child: Text('Donations (Least)'),
        ),
        DropdownMenuItem(value: 'Title (A-Z)', child: Text('Title (A-Z)')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedSortBy = value ?? 'Date Created (Newest)';
        });
      },
    );
  }

  // Filter and Sort Logic
  List<CalamityEventModel> _getFilteredAndSortedEvents(
    CalamityProvider provider,
  ) {
    var events = List<CalamityEventModel>.from(provider.calamityEvents);

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      events = events.where((event) {
        return event.title.toLowerCase().contains(query) ||
            event.description.toLowerCase().contains(query) ||
            event.calamityType.toLowerCase().contains(query) ||
            event.dropoffLocation.toLowerCase().contains(query);
      }).toList();
    }

    // Apply status filter
    if (_selectedStatusFilter != 'All') {
      events = events.where((event) {
        final isExpired = event.deadline.isBefore(DateTime.now());
        switch (_selectedStatusFilter) {
          case 'Active':
            return event.isActive && !isExpired;
          case 'Closed':
            return event.status == CalamityEventStatus.closed;
          case 'Expired':
            return isExpired || event.status == CalamityEventStatus.expired;
          default:
            return true;
        }
      }).toList();
    }

    // Apply calamity type filter
    if (_selectedCalamityTypeFilter != 'All') {
      events = events.where((event) {
        return event.calamityType == _selectedCalamityTypeFilter;
      }).toList();
    }

    // Apply sorting
    events.sort((a, b) {
      switch (_selectedSortBy) {
        case 'Date Created (Newest)':
          return b.createdAt.compareTo(a.createdAt);
        case 'Date Created (Oldest)':
          return a.createdAt.compareTo(b.createdAt);
        case 'Deadline (Upcoming)':
          return a.deadline.compareTo(b.deadline);
        case 'Deadline (Expired)':
          return b.deadline.compareTo(a.deadline);
        case 'Donations (Most)':
          final countA = _donationCounts[a.eventId] ?? 0;
          final countB = _donationCounts[b.eventId] ?? 0;
          return countB.compareTo(countA);
        case 'Donations (Least)':
          final countA = _donationCounts[a.eventId] ?? 0;
          final countB = _donationCounts[b.eventId] ?? 0;
          return countA.compareTo(countB);
        case 'Title (A-Z)':
          return a.title.compareTo(b.title);
        default:
          return 0;
      }
    });

    return events;
  }

  Widget _buildEventCard(
    BuildContext context,
    CalamityEventModel event,
    CalamityProvider provider,
  ) {
    final isExpired = event.deadline.isBefore(DateTime.now());

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

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner Image
          if (event.bannerUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              child: Image.network(
                event.bannerUrl,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 120,
                    color: Colors.grey[300],
                    child: const Icon(Icons.image_not_supported, size: 32),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Calamity Type
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue),
                            ),
                            child: Text(
                              event.calamityType,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: event.isActive && !isExpired
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: event.isActive && !isExpired
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                      child: Text(
                        isExpired ? 'Expired' : event.statusDisplay,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: event.isActive && !isExpired
                              ? Colors.green[700]
                              : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Description
                Text(
                  event.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 8),
                // Donation Count Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.pink.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.pink),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite,
                            size: 12,
                            color: Colors.pink[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_donationCounts[event.eventId] ?? 0} donations',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.pink[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Needed Items - compact
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: event.neededItems.take(4).map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 10,
                          color: _primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (event.neededItems.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '+${event.neededItems.length - 4} more',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  ),
                const SizedBox(height: 8),
                // Location and Deadline in one row
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: _primaryColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        event.dropoffLocation,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.event, size: 14, color: Colors.orange[700]),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(event.deadline),
                      style: TextStyle(
                        fontSize: 11,
                        color: isExpired ? Colors.red[700] : Colors.grey[600],
                        fontWeight: isExpired
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Action Buttons - compact horizontal layout
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          CalamityEventDetailAdminScreen.show(
                            context,
                            eventId: event.eventId,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryColor,
                          side: BorderSide(color: _primaryColor),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text(
                          'Details',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          CreateEditCalamityEventScreen.show(
                            context,
                            event: event,
                          ).then((_) {
                            provider.loadAllCalamityEvents().then((_) {
                              _loadDonationCounts(provider);
                            });
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange[700],
                          side: BorderSide(color: Colors.orange[700]!),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text(
                          'Edit',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (event.isActive && !isExpired)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              _showCloseEventDialog(context, event, provider),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: OutlinedButton(
                          onPressed: null,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey[400]!),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: Text(
                            event.status == CalamityEventStatus.closed
                                ? 'Closed'
                                : 'Expired',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Colors.red,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () =>
                          _showDeleteDialog(context, event, provider),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    CalamityEventModel event,
    CalamityProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text(
          'Are you sure you want to delete "${event.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await provider.deleteCalamityEvent(event.eventId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Event deleted successfully'
                          : 'Failed to delete event: ${provider.errorMessage}',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
                if (success) {
                  _loadDonationCounts(provider);
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCloseEventDialog(
    BuildContext context,
    CalamityEventModel event,
    CalamityProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Event'),
        content: Text(
          'Are you sure you want to close "${event.title}"? Users will no longer be able to donate to this event.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await provider.updateCalamityEvent(
                eventId: event.eventId,
                status: CalamityEventStatus.closed,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Event closed successfully'
                          : 'Failed to close event: ${provider.errorMessage}',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
                if (success) {
                  provider.loadAllCalamityEvents().then((_) {
                    _loadDonationCounts(provider);
                  });
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange[700]),
            child: const Text('Close Event'),
          ),
        ],
      ),
    );
  }
}
