import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class SettingsSwitchListTile extends StatefulWidget {
  final AppSettings<bool> setting;
  final String title;
  final String? subtitle;
  final Function(bool)? onChanged;

  const SettingsSwitchListTile.adaptive({
    super.key,
    required this.setting,
    required this.title,
    this.subtitle,
    this.onChanged,
  });

  @override
  SettingsSwitchListTileState createState() => SettingsSwitchListTileState();
}

class SettingsSwitchListTileState extends State<SettingsSwitchListTile> {
  @override
  Widget build(BuildContext context) {
    final subtitle = widget.subtitle;
    return TCell(
      title: widget.title,
      description: subtitle,
      showBottomBorder: true,
      rightIconWidget: TSwitch(
        isOn: widget.setting.value,
        onChanged: (bool newValue) {
          widget.onChanged?.call(newValue);
          widget.setting.setItem(newValue).then((_) {
            if (mounted) {
              setState(() {});
            }
          });
          return true;
        },
      ),
    );
  }
}
