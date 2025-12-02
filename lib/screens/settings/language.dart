import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/locale_provider.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final currentLocale = localeProvider.locale ?? const Locale('en');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Language'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        children: [
          _buildLanguageTile(
            context: context,
            title: 'English',
            subtitle: 'Default',
            locale: const Locale('en'),
            groupValue: currentLocale,
            onSelected: () {
              localeProvider.setLocale(const Locale('en'));
              Navigator.pop(context);
            },
          ),
          const Divider(height: 1),
          _buildLanguageTile(
            context: context,
            title: 'Filipino',
            subtitle: 'Pilipino',
            locale: const Locale('fil'),
            groupValue: currentLocale,
            onSelected: () {
              localeProvider.setLocale(const Locale('fil'));
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Locale locale,
    required Locale groupValue,
    required VoidCallback onSelected,
  }) {
    final isSelected = locale.languageCode == groupValue.languageCode;

    return ListTile(
      onTap: onSelected,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Radio<Locale>(
        value: locale,
        groupValue: groupValue,
        onChanged: (_) => onSelected(),
      ),
      selected: isSelected,
    );
  }
}
