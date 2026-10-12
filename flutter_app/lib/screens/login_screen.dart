// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/app_providers.dart';

/// TextInputFormatter for the 12-character group code:
/// - Converts Persian (۰-۹) and Arabic-Indic (٠-٩) digits to Latin (0-9)
/// - Uppercases all letters
/// - Ignores spaces and hyphens when parsing
/// - Formats visual output as XXXX-XXXX-XXXX
class GroupCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = AppConfig.formatGroupCodeDisplay(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _codeController = TextEditingController();
  final _roleController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final normalizedCode = AppConfig.normalizeGroupCode(_codeController.text);
    final role = _roleController.text.trim();
    if (normalizedCode.isEmpty || role.isEmpty) return;

    await ref.read(appControllerProvider.notifier).joinGroup(
          code: normalizedCode,
          displayName: role,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(appControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('app_title')),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.tr('login_title'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.tr('login_subtitle'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              if (state.errorCode != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.onSurface),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    l10n.translateErrorCode(state.errorCode),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              // Group Code field (always LTR for XXXX-XXXX-XXXX readability)
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [
                    GroupCodeInputFormatter(),
                  ],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.tr('code_label'),
                    hintText: l10n.tr('code_hint'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _roleController,
                decoration: InputDecoration(
                  labelText: l10n.tr('role_label'),
                  hintText: l10n.tr('role_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: state.isLoading ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  state.isLoading
                      ? l10n.tr('joining')
                      : l10n.tr('join_button'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
