import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:glfos_welcome_screen/Api/localization_api.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

class SharedMarkdownView extends StatefulWidget {
  const SharedMarkdownView(
      {super.key,
      required this.titleKey,
      required this.bodyKey,
      required this.image,
      required this.command});

  final String titleKey;
  final String bodyKey;
  final String image;
  final String command;

  @override
  State<SharedMarkdownView> createState() => _SharedMarkdownViewState();
}

class _SharedMarkdownViewState extends State<SharedMarkdownView> {
  String? bodyText;

  @override
  void initState() {
    super.initState();
    _loadMarkdown();
  }

  Future<void> _loadMarkdown() async {
    final newBodyText = await LocalizationApi().markdown(widget.bodyKey);
    if (mounted) {
      setState(() => bodyText = newBodyText);
    }
  }

  Future<void> _onTapLink(String text, String? href, String title) async {
    if (href != null) {
      if (href.startsWith('flatpak://')) {
        String command = href.replaceAll('flatpak://', '');
        await Process.run('flatpak', ['run', command]);
        return;
      } else if (href.startsWith('bash://')) {
        String command = href.replaceAll('bash://', '');
        await Process.run(command, []);
        return;
      } else if (href.startsWith('bashWithPrivilege://')) {
        String command = href.replaceAll('bashWithPrivilege://', '');
        await Process.run('pkexec', [command]);
        return;
      }

      final env = Map<String, String>.from(Platform.environment);

      // Blacklist of env vars that commonly break browsers (AppImage/Nix runners)
      const bad = [
        'LD_LIBRARY_PATH',
        'LD_PRELOAD',
        'GIO_MODULE_DIR',
        'GTK_PATH',
        'GTK_EXE_PREFIX',
        'MOZ_PLUGIN_PATH',
        'MOZ_LAUNCHER',
        'MOZ_LIBDIR',
        'QT_PLUGIN_PATH',
      ];
      for (final k in bad) {
        env.remove(k);
      }

      // Ensure essentials are present (X11 or Wayland)
      void ensure(String k, String? v) {
        if (v != null && v.isNotEmpty) env[k] = v;
      }

      ensure('HOME', Platform.environment['HOME']);
      ensure(
          'PATH',
          Platform.environment['PATH'] ??
              '/run/current-system/sw/bin:/usr/bin:/bin');
      ensure('LANG', Platform.environment['LANG'] ?? 'C.UTF-8');
      ensure('LC_ALL', Platform.environment['LC_ALL']);
      ensure('DBUS_SESSION_BUS_ADDRESS',
          Platform.environment['DBUS_SESSION_BUS_ADDRESS']);

      // X11 auth/display
      ensure('DISPLAY', Platform.environment['DISPLAY']);
      ensure('XAUTHORITY', Platform.environment['XAUTHORITY']);

      // Wayland bits
      ensure('WAYLAND_DISPLAY', Platform.environment['WAYLAND_DISPLAY']);
      ensure('XDG_RUNTIME_DIR', Platform.environment['XDG_RUNTIME_DIR']);
      ensure(
          'XDG_CURRENT_DESKTOP', Platform.environment['XDG_CURRENT_DESKTOP']);
      ensure('XDG_SESSION_TYPE', Platform.environment['XDG_SESSION_TYPE']);

      Future<bool> tryRun(List<String> cmd) async {
        try {
          final r =
              await Process.run(cmd.first, cmd.sublist(1), environment: env);
          return r.exitCode == 0;
        } catch (_) {
          return false;
        }
      }

      // GNOME prefers gio; xdg-open is fine too
      if (await tryRun(['gio', 'open', href])) return;
      if (await tryRun(['xdg-open', href])) return;
      if (await tryRun(['kde-open5', href])) return;
      if (await tryRun(['gnome-open', href])) return;

      return;

/*
      final uri = Uri.parse(href);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        debugPrint('Could not launch $href');
      }
      */
    }
  }

  Future<void> launchCommand(String commandName) async {
    print('ask to launch ' + commandName);
    if (commandName.startsWith('flatpak://')) {
      String command = commandName.replaceAll('flatpak://', '');
      await Process.run('flatpak', ['run', command]);
      return;
    } else if (commandName.startsWith('bash://')) {
      String command = commandName.replaceAll('bash://', '');
      print('try to launch "$command"');

      var result =
          await Process.run('bash', ['-lc', 'env -u LD_LIBRARY_PATH $command']);
      print(result.stdout);
      print(result.stderr);

      return;
    } else if (commandName.startsWith('bashWithPrivilege://')) {
      String command = commandName.replaceAll('bashWithPrivilege://', '');
      await Process.run('pkexec', [command]);
      return;
    } else {
      print('unexpected command : ' + commandName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (bodyText == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              maxWidth: constraints.maxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.image != '')
                  const SizedBox(
                    height: 30,
                  ),
                if (widget.image != '')
                  Center(
                    child: InkWell(
                        onTap: widget.command != ''
                            ? () {
                                launchCommand(widget.command);
                              }
                            : null,
                        child: Image.asset(widget.image)),
                  ),
                if (widget.titleKey != '') const SizedBox(height: 30),
                if (widget.titleKey != '')
                  Center(
                    child: Text(
                      context.translate(widget.titleKey),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (widget.titleKey != '') const SizedBox(height: 20),
                Center(
                    child: MarkdownBody(
                  fitContent: true,
                  shrinkWrap: true,
                  //imageDirectory: 'assets/images/',
                  data: bodyText!,
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(overflow: TextOverflow.visible),
                  ),
                  onTapLink: _onTapLink,
                  builders: {
                    'img': MarkdownElementBuilderImageDebug(),
                  },
                ))
              ],
            ),
          ),
        );
      },
    );
  }
}

class MarkdownElementBuilderImageDebug extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final imageUrl = element.attributes['src'] ?? '';
    debugPrint('🔍 Attempting to load: $imageUrl');

    return Center(
        child: Image.asset(
      'assets/images/$imageUrl',
      errorBuilder: (context, error, stackTrace) {
        debugPrint('❌ Failed to load image: $imageUrl');
        return const Text('🚫 Image failed');
      },
    ));
  }
}
