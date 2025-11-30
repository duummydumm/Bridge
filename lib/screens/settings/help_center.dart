import 'package:flutter/material.dart';

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCategories = _getFilteredCategories();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Help Center'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for help...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00897B)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF00897B),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),

          // Content
          Expanded(
            child: _searchQuery.isEmpty
                ? _buildMainContent()
                : _buildSearchResults(filteredCategories),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF00897B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.help_outline, color: Colors.white, size: 40),
                SizedBox(height: 12),
                Text(
                  'How can we help you?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Find answers to common questions and learn how to use Bridge App',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Quick Actions
          _buildSectionTitle('Quick Actions'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.verified_user,
                  title: 'Verification',
                  onTap: () => _showCategoryContent('Getting Started'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.list_alt,
                  title: 'List Items',
                  onTap: () => _showCategoryContent('Listing Items'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.handshake,
                  title: 'Transactions',
                  onTap: () => _showCategoryContent('Transactions'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.security,
                  title: 'Safety',
                  onTap: () => _showCategoryContent('Safety & Security'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Help Categories
          _buildSectionTitle('Browse by Category'),
          const SizedBox(height: 12),
          ..._helpCategories.map((category) => _buildCategoryCard(category)),
          const SizedBox(height: 24),

          // Contact Support
          _buildContactSupport(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSearchResults(List<HelpCategory> categories) {
    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with different keywords',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Search Results (${categories.length})',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00897B),
          ),
        ),
        const SizedBox(height: 16),
        ...categories.map((category) => _buildCategoryCard(category)),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF00897B), size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(HelpCategory category) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: ExpansionTile(
        leading: Icon(category.icon, color: const Color(0xFF00897B)),
        title: Text(
          category.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${category.questions.length} articles',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        children: category.questions
            .map((question) => _buildQuestionItem(question))
            .toList(),
      ),
    );
  }

  Widget _buildQuestionItem(HelpQuestion question) {
    return ListTile(
      title: Text(
        question.question,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showQuestionDetail(question),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF00897B),
      ),
    );
  }

  Widget _buildContactSupport() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.support_agent, color: Colors.blue[700], size: 28),
              const SizedBox(width: 12),
              const Text(
                'Still need help?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00897B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Our support team is here to help you. Contact us through:',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          _buildContactOption(
            icon: Icons.email,
            title: 'Email Support',
            subtitle: 'support@bridgeapp.com',
            onTap: () {
              // Could open email client
            },
          ),
          const SizedBox(height: 12),
          _buildContactOption(
            icon: Icons.chat_bubble_outline,
            title: 'In-App Feedback',
            subtitle: 'Send feedback directly from settings',
            onTap: () {
              Navigator.pop(context);
              // Navigate to feedback screen
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContactOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF00897B), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }

  void _showCategoryContent(String categoryTitle) {
    final category = _helpCategories.firstWhere(
      (cat) => cat.title == categoryTitle,
      orElse: () => _helpCategories.first,
    );
    _showQuestionDetail(category.questions.first);
  }

  void _showQuestionDetail(HelpQuestion question) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question.question,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00897B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Text(
                          question.answer,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<HelpCategory> _getFilteredCategories() {
    if (_searchQuery.isEmpty) return _helpCategories;

    return _helpCategories
        .map((category) {
          final matchingQuestions = category.questions.where((q) {
            return q.question.toLowerCase().contains(_searchQuery) ||
                q.answer.toLowerCase().contains(_searchQuery);
          }).toList();

          if (matchingQuestions.isEmpty) return null;

          return HelpCategory(
            title: category.title,
            icon: category.icon,
            questions: matchingQuestions,
          );
        })
        .whereType<HelpCategory>()
        .toList();
  }
}

// Data Models
class HelpCategory {
  final String title;
  final IconData icon;
  final List<HelpQuestion> questions;

  HelpCategory({
    required this.title,
    required this.icon,
    required this.questions,
  });
}

class HelpQuestion {
  final String question;
  final String answer;

  HelpQuestion({required this.question, required this.answer});
}

// Help Content
final List<HelpCategory> _helpCategories = [
  HelpCategory(
    title: 'Getting Started',
    icon: Icons.rocket_launch,
    questions: [
      HelpQuestion(
        question: 'How do I create an account?',
        answer: '''
To create an account on Bridge App:
1. Open the app and tap "Register"
2. Enter your email address and create a password
3. Verify your email address through the link sent to your inbox
4. Complete your profile with personal information
5. Submit verification documents (Barangay ID) for account verification
6. Wait for admin approval (usually within 24-48 hours)

Once verified, you can start listing items, borrowing, renting, trading, and donating!
''',
      ),
      HelpQuestion(
        question: 'How do I verify my account?',
        answer: '''
Account verification is required to ensure safety and trust in our community:

1. Go to Settings > Verification
2. Fill in your personal information (name, address)
3. Select your Barangay ID type (Voter's ID, National ID, or Driver's License)
4. Upload a clear photo of your valid ID
5. Submit for review

Our admin team will review your submission within 24-48 hours. Once approved, you'll be able to:
- List items for rent, borrow, trade, or donation
- Complete transactions with other users
- Access all app features

If your verification is rejected, you'll receive a reason and can resubmit with corrected information.
''',
      ),
      HelpQuestion(
        question: 'What information do I need to provide?',
        answer: '''
To use Bridge App, you'll need to provide:
• Full name (first, middle initial, last)
• Email address
• Complete address (street, barangay, city, province)
• Government-issued ID for verification
• Profile photo (optional but recommended)

All information is kept secure and used only for account verification and transaction purposes. See our Privacy Policy for more details.
''',
      ),
    ],
  ),
  HelpCategory(
    title: 'Listing Items',
    icon: Icons.list_alt,
    questions: [
      HelpQuestion(
        question: 'How do I list an item for rent?',
        answer: '''
To list an item for rent:
1. Tap the "+" button on the home screen
2. Select "Rent" option
3. Choose the category (Apartment, Boarding House, Commercial Space, or Item)
4. Fill in the item details:
   - Title and description
   - Location
   - Price and pricing mode (per day, per week, per month)
   - Photos (at least one required)
   - Availability dates
5. Review and publish your listing

Your listing will be visible to all users once published. You can edit or remove it anytime from "My Listings".
''',
      ),
      HelpQuestion(
        question: 'How do I list an item for borrowing?',
        answer: '''
To list an item for borrowing:
1. Tap the "+" button on the home screen
2. Select "Lend" option
3. Fill in the item details:
   - Item name and description
   - Category
   - Condition
   - Photos
   - Borrowing terms (duration, deposit if any)
4. Set your availability
5. Publish the listing

Borrowers can request to borrow your item. You'll receive notifications when someone is interested.
''',
      ),
      HelpQuestion(
        question: 'Can I edit or delete my listing?',
        answer: '''
Yes! You can edit or delete your listings at any time:

• Go to "My Listings" from your profile
• Tap on the listing you want to modify
• Use the edit button to update details, photos, or pricing
• Use the delete button to remove the listing

Note: If there are active or pending transactions for a listing, you may need to resolve those first before making major changes.
''',
      ),
      HelpQuestion(
        question: 'What makes a good listing?',
        answer: '''
A great listing includes:
• Clear, high-quality photos from multiple angles
• Detailed and honest description
• Accurate condition assessment
• Fair and competitive pricing
• Clear terms and conditions
• Quick response to inquiries

Good listings get more views and successful transactions. Be honest about any defects or limitations to avoid disputes later.
''',
      ),
    ],
  ),
  HelpCategory(
    title: 'Transactions',
    icon: Icons.handshake,
    questions: [
      HelpQuestion(
        question: 'How does renting work?',
        answer: '''
Renting process:
1. Browse available rental listings
2. Select an item and check availability
3. Submit a rental request with your desired dates
4. Wait for the owner to approve your request
5. Pay the rental fee (and service fee if applicable)
6. Pick up or receive the item on the start date
7. Return the item on or before the end date
8. Both parties can leave reviews after completion

For long-term rentals (apartments, commercial spaces), payments may be monthly. Make sure to communicate clearly with the owner about pickup/return arrangements.
''',
      ),
      HelpQuestion(
        question: 'How does borrowing work?',
        answer: '''
Borrowing process:
1. Find an item you want to borrow
2. Send a borrow request to the lender
3. Wait for approval
4. Arrange pickup with the lender
5. Use the item for the agreed duration
6. Return the item in the same condition
7. Both parties leave reviews

Always return items on time and in good condition. Late returns may incur fees as agreed upon.
''',
      ),
      HelpQuestion(
        question: 'How do payments work?',
        answer: '''
Bridge App supports various payment methods:
• GCash
• GoTyme
• Cash (for meetups)

Payment process:
1. Agree on price and terms with the other party
2. Complete payment through the app or in person
3. Payment is held securely until transaction completion
4. Funds are released after both parties confirm completion

For rentals, there may be a platform service fee in addition to the rental price. This will be clearly shown before you confirm.
''',
      ),
      HelpQuestion(
        question: 'What if I need to cancel a transaction?',
        answer: '''
Cancellation policies:
• You can cancel a request before it's approved by the other party
• Once approved, cancellation may require mutual agreement
• Cancellation fees may apply depending on timing
• Check the specific terms for each transaction

To cancel:
1. Go to your transaction details
2. Tap "Cancel" or "Request Cancellation"
3. Provide a reason if required
4. Wait for confirmation

If you're having issues, contact support for assistance with cancellations.
''',
      ),
    ],
  ),
  HelpCategory(
    title: 'Safety & Security',
    icon: Icons.security,
    questions: [
      HelpQuestion(
        question: 'How do I stay safe when meeting users?',
        answer: '''
Safety tips for meetups:
• Meet in public, well-lit places
• Bring a friend if possible
• Verify the other person's identity
• Check item condition before completing payment
• Trust your instincts - if something feels wrong, don't proceed
• Use the app's messaging system to communicate
• Report suspicious behavior immediately

Bridge App verifies all users, but always exercise caution when meeting people in person.
''',
      ),
      HelpQuestion(
        question: 'What should I do if there\'s a dispute?',
        answer: '''
If you have a dispute:
1. Try to resolve it directly with the other party first
2. Use the app's messaging system to communicate
3. If unresolved, report the dispute through the app
4. Provide evidence (photos, messages, etc.)
5. Our support team will review and assist

Common disputes:
• Item condition issues
• Late returns
• Payment problems
• Misrepresentation of items

We aim to resolve disputes fairly and quickly. Both parties' accounts may be reviewed during the process.
''',
      ),
      HelpQuestion(
        question: 'How is my personal information protected?',
        answer: '''
We take your privacy seriously:
• All data is encrypted in transit and at rest
• ID documents are securely stored and only accessible to admins
• We never share your information with third parties without consent
• You control what information is visible to other users
• Account verification ensures all users are legitimate

See our Privacy Policy for complete details on how we protect your data.
''',
      ),
      HelpQuestion(
        question: 'What should I do if I suspect fraud?',
        answer: '''
If you suspect fraudulent activity:
1. Stop all communication and transactions immediately
2. Report the user through their profile or the transaction
3. Contact support immediately with details
4. Provide screenshots and evidence
5. Do not complete any payments

Warning signs:
• Requests to pay outside the app
• Suspiciously low prices
• Pressure to act quickly
• Requests for personal information beyond what's needed
• Inconsistent or vague communication

We investigate all fraud reports and take appropriate action, including account suspension or termination.
''',
      ),
    ],
  ),
  HelpCategory(
    title: 'Account & Profile',
    icon: Icons.person,
    questions: [
      HelpQuestion(
        question: 'How do I update my profile?',
        answer: '''
To update your profile:
1. Go to your Profile screen
2. Tap the edit icon
3. Update any information you want to change
4. Save your changes

You can update:
• Profile photo
• Personal information
• Address (may require re-verification)
• Notification preferences

Note: Some changes like address may require admin re-verification.
''',
      ),
      HelpQuestion(
        question: 'How do I change my password?',
        answer: '''
To change your password:
1. Go to Settings > Change Password
2. Enter your current password
3. Enter your new password
4. Confirm your new password
5. Save changes

Make sure your new password is strong:
• At least 8 characters
• Mix of letters, numbers, and symbols
• Not easily guessable

If you forgot your password, use the "Forgot Password" option on the login screen.
''',
      ),
      HelpQuestion(
        question: 'Can I delete my account?',
        answer: '''
Yes, you can delete your account:
1. Go to Settings
2. Scroll to Account Settings
3. Tap "Delete Account"
4. Confirm your decision

Before deleting:
• Complete or cancel any active transactions
• Resolve any disputes
• Download any data you want to keep

Account deletion is permanent and cannot be undone. Some information may be retained as required by law.
''',
      ),
    ],
  ),
  HelpCategory(
    title: 'Troubleshooting',
    icon: Icons.build,
    questions: [
      HelpQuestion(
        question: 'I\'m not receiving notifications',
        answer: '''
If you're not receiving notifications:
1. Check your device's notification settings for Bridge App
2. Go to Settings > Notifications in the app
3. Ensure notifications are enabled
4. Check if Do Not Disturb mode is on
5. Restart the app
6. Make sure you're logged in

If issues persist:
• Uninstall and reinstall the app
• Check your internet connection
• Contact support if the problem continues
''',
      ),
      HelpQuestion(
        question: 'The app is running slowly',
        answer: '''
To improve app performance:
1. Close other apps running in the background
2. Clear the app cache (device settings)
3. Check your internet connection
4. Update to the latest app version
5. Restart your device
6. Free up device storage space

If the app continues to be slow, it may be a server issue. Check our status page or contact support.
''',
      ),
      HelpQuestion(
        question: 'I can\'t upload photos',
        answer: '''
If you're having trouble uploading photos:
• Check your internet connection
• Ensure photos are under 10MB each
• Try using a different photo format (JPG, PNG)
• Grant camera/storage permissions if prompted
• Restart the app
• Clear app cache and try again

Supported formats: JPG, PNG
Maximum size: 10MB per photo
Recommended: Clear, well-lit photos work best
''',
      ),
      HelpQuestion(
        question: 'I forgot my password',
        answer: '''
To reset your password:
1. Go to the Login screen
2. Tap "Forgot Password"
3. Enter your email address
4. Check your email for a reset link
5. Click the link and create a new password

If you don't receive the email:
• Check your spam/junk folder
• Verify you're using the correct email
• Wait a few minutes and try again
• Contact support if the issue persists

The reset link expires after 24 hours for security.
''',
      ),
    ],
  ),
];
