import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/tdesign/tdesign_scope.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../widgets/mxc_image_viewer.dart';
import 'settings.dart';

class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  Widget _buildProfileCard(BuildContext context) {
    return FutureBuilder<Profile>(
      future: controller.profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final avatar = profile?.avatarUrl;
        final mxid = Matrix.of(context).client.userID ?? L10n.of(context).user;
        final displayname = profile?.displayName ?? mxid;
        final theme = Theme.of(context);
        return TDesignSectionCard(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Avatar(
                      mxContent: avatar,
                      name: displayname,
                      size: Avatar.defaultSize * 2.4,
                      onTap: avatar != null
                          ? () => showDialog(
                              context: context,
                              builder: (_) => MxcImageViewer(avatar),
                            )
                          : null,
                    ),
                    if (profile != null)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: TButton(
                          width: 38,
                          height: 38,
                          shape: TButtonShape.circle,
                          theme: TButtonTheme.primary,
                          icon: TIcons.camera,
                          onTap: controller.setAvatarAction,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        mxid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TButton(
                            text: L10n.of(context).editDisplayname,
                            type: TButtonType.outline,
                            icon: TIcons.edit_1,
                            onTap: controller.setDisplaynameAction,
                          ),
                          TButton(
                            text: L10n.of(context).inviteContact,
                            type: TButtonType.text,
                            icon: TIcons.share,
                            onTap: () => FluffyShare.share(
                              AppConfig.inviteLinkPrefix,
                              context,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  TCell _menuCell({
    required BuildContext context,
    required String title,
    required IconData icon,
    String? subtitle,
    VoidCallback? onTap,
    bool selected = false,
    Color? iconColor,
  }) {
    return TCell(
      title: title,
      description: subtitle,
      showBottomBorder: true,
      leftIconWidget: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? Theme.of(context).colorScheme.primary)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: iconColor),
      ),
      noteWidget: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
            )
          : null,
      arrow: true,
      onClick: (_) => onTap?.call(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeRoute = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: ListView(
          key: const Key('SettingsListViewContent'),
          children: <Widget>[
            TNavBar(
              title: L10n.of(context).settings,
              useDefaultBack: false,
              leftBarItems: [
                TNavBarItem(
                  customWidget: TButton(
                    width: 40,
                    height: 40,
                    shape: TButtonShape.circle,
                    type: TButtonType.ghost,
                    icon: TIcons.chevron_left,
                    onTap: () => context.go('/rooms'),
                  ),
                ),
              ],
            ),
            _buildProfileCard(context),
            const TDesignSectionTitle('Workspace'),
            TDesignSectionCard(
              child: Column(
                children: [
                  _menuCell(
                    context: context,
                    title: L10n.of(context).changeTheme,
                    subtitle: L10n.of(context).setColorTheme,
                    icon: TIcons.brush,
                    selected: activeRoute.startsWith('/rooms/settings/style'),
                    onTap: () => context.go('/rooms/settings/style'),
                  ),
                  _menuCell(
                    context: context,
                    title: L10n.of(context).notifications,
                    subtitle: L10n.of(context).devices,
                    icon: TIcons.notification,
                    selected: activeRoute.startsWith(
                      '/rooms/settings/notifications',
                    ),
                    onTap: () => context.go('/rooms/settings/notifications'),
                  ),
                  _menuCell(
                    context: context,
                    title: L10n.of(context).devices,
                    icon: TIcons.mobile,
                    selected: activeRoute.startsWith('/rooms/settings/devices'),
                    onTap: () => context.go('/rooms/settings/devices'),
                  ),
                  _menuCell(
                    context: context,
                    title: L10n.of(context).chat,
                    icon: TIcons.chat_bubble,
                    selected: activeRoute.startsWith('/rooms/settings/chat'),
                    onTap: () => context.go('/rooms/settings/chat'),
                  ),
                  _menuCell(
                    context: context,
                    title: L10n.of(context).security,
                    icon: TIcons.secured,
                    selected: activeRoute.startsWith(
                      '/rooms/settings/security',
                    ),
                    onTap: () => context.go('/rooms/settings/security'),
                  ),
                ],
              ),
            ),
            TDesignSectionTitle(L10n.of(context).about),
            TDesignSectionCard(
              child: Column(
                children: [
                  _menuCell(
                    context: context,
                    title: L10n.of(context).aboutHomeserver(
                      Matrix.of(context).client.userID?.domain ?? 'homeserver',
                    ),
                    icon: TIcons.internet,
                    selected: activeRoute.startsWith(
                      '/rooms/settings/homeserver',
                    ),
                    onTap: () => context.go('/rooms/settings/homeserver'),
                  ),
                  _menuCell(
                    context: context,
                    title: L10n.of(context).privacy,
                    icon: TIcons.lock_on,
                    onTap: () =>
                        launchUrlString(AppSettings.privacyPolicy.value),
                  ),
                  _menuCell(
                    context: context,
                    title: L10n.of(context).about,
                    icon: TIcons.info_circle,
                    subtitle: PlatformInfos.clientName,
                    onTap: () => PlatformInfos.showDialog(context),
                  ),
                ],
              ),
            ),
            TDesignSectionTitle(L10n.of(context).account),
            TDesignSectionCard(
              child: Column(
                children: [
                  TCell(
                    title: L10n.of(context).chatBackup,
                    description: L10n.of(context).chatBackupDescription,
                    showBottomBorder: true,
                    leftIconWidget: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(TIcons.secured, size: 20),
                    ),
                    rightIconWidget: TSwitch(
                      isOn: controller.cryptoIdentityConnected == true,
                      onChanged: (value) {
                        controller.firstRunBootstrapAction(value);
                        return true;
                      },
                    ),
                  ),
                  TCell(
                    title: L10n.of(context).logout,
                    showBottomBorder: true,
                    leftIconWidget: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        TIcons.logout,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    titleWidget: Text(
                      L10n.of(context).logout,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onClick: (_) => controller.logoutAction(),
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
}
