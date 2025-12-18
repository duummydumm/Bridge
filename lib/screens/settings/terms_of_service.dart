import 'package:flutter/material.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Terms of Service'),
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
                  Icon(Icons.description, color: Colors.white, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'Terms of Service',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Last Updated: $_lastUpdatedDate',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Introduction
            _buildSection(
              title: '1. Acceptance of Terms',
              content: '''
By accessing and using Bridge App, you accept and agree to be bound by the terms and provision of this agreement. If you do not agree to abide by the above, please do not use this service.

These Terms of Service ("Terms") govern your access to and use of Bridge App's mobile application and services. By creating an account, accessing, or using our services, you agree to be bound by these Terms.
''',
            ),

            // Eligibility
            _buildSection(
              title: '2. Eligibility and Account Registration',
              content: '''
2.1 Age Requirement
• You must be at least 18 years old to use Bridge App
• By using our services, you represent and warrant that you are at least 18 years of age

2.2 Account Registration
• You must provide accurate, current, and complete information during registration
• You are responsible for maintaining the confidentiality of your account credentials
• You must notify us immediately of any unauthorized use of your account
• You are responsible for all activities that occur under your account

2.3 Account Verification
• We may require identity verification before you can list items or complete transactions
• Verification may include submitting government-issued identification
• We reserve the right to reject or suspend accounts that fail verification
''',
            ),

            // Use of Service
            _buildSection(
              title: '3. Use of Service',
              content: '''
3.1 Permitted Uses
You may use Bridge App to:
• List items for borrowing, renting, trading, or donating
• Browse and search for items
• Communicate with other users regarding transactions
• Complete transactions in accordance with these Terms

3.2 Prohibited Activities
You agree NOT to:
• Post false, misleading, or fraudulent information
• List illegal, stolen, or prohibited items
• Harass, abuse, or harm other users
• Violate any applicable laws or regulations
• Interfere with or disrupt the service
• Use automated systems to access the service without permission
• Impersonate any person or entity
• Collect user information without consent
• Post content that is defamatory, obscene, or violates intellectual property rights
• Engage in any fraudulent or deceptive practices
''',
            ),

            // User Content
            _buildSection(
              title: '4. User Content and Listings',
              content: '''
4.1 Content Responsibility
• You are solely responsible for all content you post, including item descriptions, photos, and communications
• You represent that you own or have the right to use all content you post
• You grant Bridge App a license to use, display, and distribute your content on the platform

4.2 Listing Requirements
• Item descriptions must be accurate and complete
• Photos must accurately represent the item's condition
• You must disclose any defects, damages, or limitations
• Pricing must be clearly stated and reasonable

4.3 Content Moderation
• We reserve the right to review, edit, or remove any content that violates these Terms
• We may suspend or terminate accounts that repeatedly violate our policies
• We are not obligated to monitor all user content but may do so at our discretion
''',
            ),

            // Transactions
            _buildSection(
              title: '5. Transactions and Payments',
              content: '''
5.1 Transaction Terms
• All transactions are agreements between users
• Bridge App facilitates connections but is not a party to transactions
• Users are responsible for negotiating terms, conditions, and pricing
• We recommend documenting agreements in the app's messaging system

5.2 Payment Processing
• Payments may be processed through third-party payment services
• You agree to comply with the terms of any payment service provider
• We are not responsible for payment disputes between users
• Refunds are subject to the agreement between users

5.3 Rental and Borrowing Terms
• Rental periods and fees must be clearly agreed upon by both parties
• Late returns may incur additional fees as agreed
• Items must be returned in the same condition as received (normal wear excepted)
• Borrowers are responsible for any damage or loss during the rental period

5.4 Trading Terms
• Trades are final once both parties confirm acceptance
• Items must be accurately described and match the listing
• Both parties are responsible for shipping or delivery arrangements
''',
            ),

            // Disputes
            _buildSection(
              title: '6. Disputes and Resolution',
              content: '''
6.1 User Disputes
• Users are encouraged to resolve disputes directly
• Bridge App may provide dispute resolution tools and support
• We are not obligated to resolve disputes but may assist at our discretion

6.2 Dispute Resolution Process
• Report disputes through the app's support system
• Provide documentation and evidence of the issue
• We may investigate and take appropriate action, including:
  - Mediating between parties
  - Issuing warnings or suspensions
  - Removing listings or content
  - Terminating accounts for serious violations

6.3 Limitation of Liability
• Bridge App is not liable for disputes between users
• We are not responsible for the quality, safety, or legality of items listed
• Users transact at their own risk
''',
            ),

            // Prohibited Items
            _buildSection(
              title: '7. Prohibited Items and Services',
              content: '''
You may NOT list or transact the following items:
• Illegal items or items that violate applicable laws
• Stolen property or items obtained illegally
• Weapons, firearms, or dangerous items
• Drugs, controlled substances, or prescription medications
• Counterfeit or pirated goods
• Items that infringe on intellectual property rights
• Live animals (except as permitted by local laws)
• Perishable food items (unless specifically allowed)
• Items that promote hate, violence, or discrimination
• Personal information or data
• Any item that violates our community standards
''',
            ),

            // User Conduct
            _buildSection(
              title: '8. User Conduct and Community Standards',
              content: '''
8.1 Respectful Behavior
• Treat all users with respect and courtesy
• Use appropriate language in communications
• Do not engage in discriminatory or harassing behavior
• Report inappropriate conduct to our support team

8.2 Communication Guidelines
• Keep communications relevant to transactions
• Do not spam or send unsolicited messages
• Respect other users' privacy and boundaries
• Use the app's messaging system for transaction-related communications

8.3 Reviews and Ratings
• Provide honest and accurate reviews
• Reviews must be based on actual transaction experiences
• Do not post false, defamatory, or malicious reviews
• Reviews may be removed if they violate our policies
''',
            ),

            // Intellectual Property
            _buildSection(
              title: '9. Intellectual Property',
              content: '''
9.1 Bridge App's Rights
• All content, features, and functionality of Bridge App are owned by us
• Our trademarks, logos, and brand names are our property
• You may not use our intellectual property without written permission

9.2 User Content License
• By posting content, you grant us a worldwide, non-exclusive license to use it
• This license allows us to display, distribute, and promote your content on the platform
• You retain ownership of your content

9.3 Copyright Infringement
• We respect intellectual property rights
• If you believe your copyright has been infringed, contact us with:
  - Description of the copyrighted work
  - Location of the infringing material
  - Your contact information
  - A statement of good faith belief
''',
            ),

            // Termination
            _buildSection(
              title: '10. Account Termination',
              content: '''
10.1 Termination by You
• You may delete your account at any time through app settings
• Upon termination, your access to the service will cease
• Some information may be retained as required by law

10.2 Termination by Us
We may suspend or terminate your account if:
• You violate these Terms or our policies
• You engage in fraudulent or illegal activities
• You fail to pay required fees
• You create risk or legal exposure for us
• You abuse other users or our services

10.3 Effect of Termination
• Upon termination, your right to use the service immediately ceases
• We may delete your account and content
• Outstanding transactions must be completed or resolved
• We are not liable for any loss resulting from termination
''',
            ),

            // Disclaimers
            _buildSection(
              title: '11. Disclaimers and Limitations',
              content: '''
11.1 Service Availability
• We strive to provide reliable service but do not guarantee uninterrupted access
• The service is provided "as is" without warranties of any kind
• We may modify, suspend, or discontinue features at any time

11.2 Third-Party Services
• Our app may integrate with third-party services (payments, maps, etc.)
• We are not responsible for third-party service availability or performance
• Your use of third-party services is subject to their terms

11.3 Limitation of Liability
• Bridge App is a platform connecting users; we are not a party to transactions
• We are not liable for:
  - User disputes or transaction issues
  - Item quality, safety, or condition
  - Loss or damage to items
  - Personal injury or property damage
  - Indirect, incidental, or consequential damages

11.4 Maximum Liability
• Our total liability shall not exceed the amount you paid us in the 12 months preceding the claim
• Some jurisdictions do not allow limitations of liability, so some limitations may not apply
''',
            ),

            // Indemnification
            _buildSection(
              title: '12. Indemnification',
              content: '''
You agree to indemnify, defend, and hold harmless Bridge App, its officers, directors, employees, and agents from and against any claims, damages, obligations, losses, liabilities, costs, or expenses (including attorney's fees) arising from:
• Your use of the service
• Your violation of these Terms
• Your violation of any rights of another user or third party
• Your content or listings
• Your transactions with other users
''',
            ),

            // Changes to Terms
            _buildSection(
              title: '13. Changes to Terms',
              content: '''
We reserve the right to modify these Terms at any time. We will notify you of material changes by:
• Posting the updated Terms in the app
• Updating the "Last Updated" date
• Sending you a notification (for significant changes)

Your continued use of the service after changes become effective constitutes acceptance of the updated Terms. If you do not agree to the changes, you must stop using the service and delete your account.
''',
            ),

            // Governing Law
            _buildSection(
              title: '14. Governing Law and Jurisdiction',
              content: '''
These Terms shall be governed by and construed in accordance with the laws of the jurisdiction in which Bridge App operates, without regard to its conflict of law provisions.

Any disputes arising from these Terms or your use of the service shall be resolved in the appropriate courts of that jurisdiction.
''',
            ),

            // Contact Information
            _buildSection(
              title: '15. Contact Information',
              content: '''
If you have questions about these Terms of Service, please contact us:

Email: legal@bridgeapp.com
Support: support@bridgeapp.com

We will respond to your inquiry within a reasonable timeframe.
''',
            ),

            const SizedBox(height: 32),

            // Acknowledgment
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'By using Bridge App, you acknowledge that you have read, understood, and agree to be bound by these Terms of Service.',
                      style: TextStyle(fontSize: 14, color: Colors.orange[900]),
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
