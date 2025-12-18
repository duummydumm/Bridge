import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF00897B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip, color: Colors.white, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Last Updated: $_lastUpdatedDate',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Introduction
            _buildSection(
              title: '1. Introduction',
              content: '''
Welcome to Bridge App. We are committed to protecting your privacy and ensuring the security of your personal information. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application and services.

By using Bridge App, you agree to the collection and use of information in accordance with this policy. If you do not agree with our policies and practices, please do not use our services.
''',
            ),

            // Information We Collect
            _buildSection(
              title: '2. Information We Collect',
              content: '''
We collect several types of information to provide and improve our services:

2.1 Personal Information
• Name, email address, and contact information
• Profile photo and biographical information
• Address and location data (street, barangay, city, province)
• Government-issued identification documents (for verification purposes)
• Phone number (if provided)

2.2 Account Information
• User credentials and authentication data
• Account preferences and settings
• Verification status and related documentation

2.3 Transaction Information
• Items you list, borrow, rent, trade, or donate
• Transaction history and records
• Payment information (processed through secure third-party services)
• Communication records with other users

2.4 Usage Data
• Device information (model, operating system, unique identifiers)
• App usage patterns and interactions
• Log files and analytics data
• Location data (if location services are enabled)

2.5 Content You Provide
• Photos and images of items
• Messages and communications with other users
• Reviews and ratings
• Feedback and support requests
''',
            ),

            // How We Use Your Information
            _buildSection(
              title: '3. How We Use Your Information',
              content: '''
We use the collected information for various purposes:

3.1 Service Provision
• To create and manage your account
• To facilitate transactions between users
• To verify user identity and prevent fraud
• To process and complete transactions
• To enable communication between users

3.2 Safety and Security
• To monitor and prevent fraudulent or illegal activities
• To enforce our Terms of Service
• To protect the rights and safety of our users
• To investigate and resolve disputes

3.3 Communication
• To send you important updates about your account and transactions
• To respond to your inquiries and provide customer support
• To send notifications about relevant activities
• To inform you about changes to our services

3.4 Improvement and Analytics
• To analyze usage patterns and improve our services
• To develop new features and functionality
• To conduct research and analytics
• To personalize your experience
''',
            ),

            // Information Sharing
            _buildSection(
              title: '4. Information Sharing and Disclosure',
              content: '''
We do not sell your personal information. We may share your information in the following circumstances:

4.1 With Other Users
• Your profile information (name, photo, ratings) is visible to other users
• Transaction-related information is shared with parties involved in the transaction
• Your public listings and posts are visible to all users

4.2 Service Providers
• We may share information with third-party service providers who perform services on our behalf (payment processing, cloud storage, analytics)
• These providers are contractually obligated to protect your information

4.3 Legal Requirements
• We may disclose information if required by law, court order, or government regulation
• We may share information to protect our rights, property, or safety, or that of our users

4.4 Business Transfers
• In the event of a merger, acquisition, or sale of assets, your information may be transferred to the new entity
''',
            ),

            // Data Security
            _buildSection(
              title: '5. Data Security',
              content: '''
We implement appropriate technical and organizational measures to protect your personal information:

• Encryption of data in transit and at rest
• Secure authentication and access controls
• Regular security assessments and updates
• Limited access to personal information on a need-to-know basis
• Secure storage of identification documents

However, no method of transmission over the internet or electronic storage is 100% secure. While we strive to protect your information, we cannot guarantee absolute security.
''',
            ),

            // Your Rights
            _buildSection(
              title: '6. Your Rights and Choices',
              content: '''
You have certain rights regarding your personal information:

6.1 Access and Correction
• You can access and update your profile information through the app settings
• You can request corrections to inaccurate information

6.2 Account Deletion
• You can request deletion of your account and personal information
• Some information may be retained as required by law or for legitimate business purposes

6.3 Communication Preferences
• You can manage notification settings in the app
• You can opt out of certain non-essential communications

6.4 Location Data
• You can control location sharing through your device settings
• Location data is used only for service functionality (e.g., showing nearby items)

6.5 Data Portability
• You can request a copy of your personal data in a structured format
''',
            ),

            // Children's Privacy
            _buildSection(
              title: '7. Children\'s Privacy',
              content: '''
Our services are not intended for individuals under the age of 18. We do not knowingly collect personal information from children. If you become aware that a child has provided us with personal information, please contact us immediately. If we discover that we have collected information from a child, we will delete it promptly.
''',
            ),

            // Third-Party Links
            _buildSection(
              title: '8. Third-Party Links and Services',
              content: '''
Our app may contain links to third-party websites or services. We are not responsible for the privacy practices of these external sites. We encourage you to review the privacy policies of any third-party services you access through our app.
''',
            ),

            // Data Retention
            _buildSection(
              title: '9. Data Retention',
              content: '''
We retain your personal information for as long as necessary to:
• Provide our services to you
• Comply with legal obligations
• Resolve disputes and enforce agreements
• Maintain security and prevent fraud

When you delete your account, we will delete or anonymize your personal information, except where we are required to retain it by law.
''',
            ),

            // Changes to Privacy Policy
            _buildSection(
              title: '10. Changes to This Privacy Policy',
              content: '''
We may update this Privacy Policy from time to time. We will notify you of any material changes by:
• Posting the new Privacy Policy in the app
• Updating the "Last Updated" date
• Sending you a notification (for significant changes)

Your continued use of the app after changes become effective constitutes acceptance of the updated policy.
''',
            ),

            // Contact Information
            _buildSection(
              title: '11. Contact Us',
              content: '''
If you have questions, concerns, or requests regarding this Privacy Policy or our data practices, please contact us:

Email: privacy@bridgeapp.com
Support: support@bridgeapp.com

We will respond to your inquiry within a reasonable timeframe.
''',
            ),

            const SizedBox(height: 32),

            // Acknowledgment
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'By using Bridge App, you acknowledge that you have read and understood this Privacy Policy.',
                      style: TextStyle(fontSize: 14, color: Colors.blue[900]),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required String content}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00897B),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  static const String _lastUpdatedDate = 'January 2024';
}
