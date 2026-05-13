import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/httpdns/httpdns_domain_helper.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/dialog_text_field.dart';
import 'package:flutter/material.dart';

class HttpDnsDomainListsDialogResult {
  final List<String> keepAliveDomains;
  final List<String> preloadDomains;

  const HttpDnsDomainListsDialogResult({
    required this.keepAliveDomains,
    required this.preloadDomains,
  });
}

/// Shows a dialog for editing user-managed HTTPDNS keep-alive and preload lists.
Future<HttpDnsDomainListsDialogResult?> showHttpDnsDomainListsDialog({
  required BuildContext context,
  required List<String> keepAliveDomains,
  required List<String> preloadDomains,
  required List<String> autoAddedDomains,
}) {
  final keepAliveController = TextEditingController(
    text: HttpDnsDomainHelper.toEditableInput(keepAliveDomains),
  );
  final preloadController = TextEditingController(
    text: HttpDnsDomainHelper.toEditableInput(preloadDomains),
  );

  return showAdaptiveDialog<HttpDnsDomainListsDialogResult>(
    context: context,
    useRootNavigator: false,
    builder: (context) {
      final keepAliveError = ValueNotifier<String?>(null);
      final autoAddedDomainText = autoAddedDomains.isEmpty
          ? 'Homeserver domains will be added automatically after Matrix accounts are configured.'
          : 'Auto-added homeserver domains:\n${autoAddedDomains.join('\n')}';

      return AlertDialog.adaptive(
        title: const Text('HTTPDNS domain lists'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  autoAddedDomainText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<String?>(
                  valueListenable: keepAliveError,
                  builder: (context, errorText, _) {
                    return DialogTextField(
                      controller: keepAliveController,
                      errorText: errorText,
                      labelText: 'Keep-alive domains',
                      hintText: 'matrix.example.com\ncdn.example.com',
                      minLines: 4,
                      maxLines: 6,
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Some native SDKs cap keep-alive domains at ${HttpDnsDomainHelper.maxKeepAliveDomains} entries. Homeserver domains are prioritized first.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                DialogTextField(
                  controller: preloadController,
                  labelText: 'Preload domains',
                  hintText: 'matrix.example.com\nmedia.example.com',
                  minLines: 4,
                  maxLines: 6,
                ),
              ],
            ),
          ),
        ),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.of(context).cancel),
          ),
          AdaptiveDialogAction(
            autofocus: true,
            onPressed: () {
              final normalizedKeepAliveDomains =
                  HttpDnsDomainHelper.parseEditableInput(
                    keepAliveController.text,
                  );
              if (normalizedKeepAliveDomains.length >
                  HttpDnsDomainHelper.maxKeepAliveDomains) {
                keepAliveError.value =
                    'Keep-alive domains cannot exceed ${HttpDnsDomainHelper.maxKeepAliveDomains} entries.';
                return;
              }

              Navigator.of(context).pop(
                HttpDnsDomainListsDialogResult(
                  keepAliveDomains: normalizedKeepAliveDomains,
                  preloadDomains: HttpDnsDomainHelper.parseEditableInput(
                    preloadController.text,
                  ),
                ),
              );
            },
            child: Text(L10n.of(context).ok),
          ),
        ],
      );
    },
  );
}
