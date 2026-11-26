import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/net/api_client.dart';
import '../../core/net/api_error.dart';
import '../billing/paywall_sheet.dart';

/// Tutor choices for Pro / Contributor (`GET /ai/options`, outsie `lib/ai_options.py`): the model, the
/// thinking level and bring-your-own-key. The key is kept in the Android keystore and only sent with
/// the student's own tutor prompts; the server never stores it.

class AIModelChoice {
  const AIModelChoice(this.id, this.label, this.plan, this.available);
  final String id;
  final String label;
  final String plan;
  final bool available;
  String get short => label.split(' · ').first;
}

class ByokProvider {
  const ByokProvider(this.id, this.apiType, this.label, this.baseUrl, this.hint);
  final String id;
  final String apiType;
  final String label;
  final String baseUrl;
  final String hint;
}

class AIOptions {
  const AIOptions({
    required this.plan,
    required this.allowed,
    required this.models,
    required this.efforts,
    required this.providers,
    required this.byokPerHour,
    required this.passages,
    required this.historyTurns,
    this.upgradeMessage,
  });

  factory AIOptions.fromJson(Map<String, dynamic> j) {
    final b = Map<String, dynamic>.from((j['byok'] as Map?) ?? const {});
    final ctx = Map<String, dynamic>.from((j['context'] as Map?) ?? const {});
    return AIOptions(
      plan: '${j['plan'] ?? 'free'}',
      allowed: j['allowed'] == true,
      models: [
        for (final m in (j['models'] as List? ?? const []))
          if (m is Map) AIModelChoice('${m['id']}', '${m['label']}', '${m['plan']}', m['available'] == true),
      ],
      efforts: [for (final e in (j['efforts'] as List? ?? const ['auto'])) '$e'],
      providers: [
        for (final p in (b['providers'] as List? ?? const []))
          if (p is Map) ByokProvider('${p['id']}', '${p['api_type']}', '${p['label']}', '${p['base_url'] ?? ''}', '${p['models_hint'] ?? ''}'),
      ],
      byokPerHour: (b['per_hour'] as num?)?.toInt() ?? 0,
      passages: (ctx['passages'] as num?)?.toInt() ?? 8,
      historyTurns: (ctx['history_turns'] as num?)?.toInt() ?? 12,
      upgradeMessage: (j['upgrade'] as Map?)?['message'] as String?,
    );
  }

  final String plan;
  final bool allowed;
  final List<AIModelChoice> models;
  final List<String> efforts;
  final List<ByokProvider> providers;
  final int byokPerHour;
  final int passages;
  final int historyTurns;
  final String? upgradeMessage;
}

final aiOptionsProvider = FutureProvider<AIOptions?>((ref) async {
  try {
    return AIOptions.fromJson(await ref.watch(apiProvider).get<Map<String, dynamic>>('/ai/options'));
  } catch (_) {
    return null;
  }
});

class TutorPrefs {
  const TutorPrefs({
    this.model,
    this.effort = 'auto',
    this.useByok = false,
    this.provider = 'openai',
    this.apiType = 'openai',
    this.baseUrl = '',
    this.apiKey = '',
    this.byokModel = '',
  });

  final String? model;
  final String effort;
  final bool useByok;
  final String provider;
  final String apiType;
  final String baseUrl;
  final String apiKey;
  final String byokModel;

  TutorPrefs copyWith({
    Object? model = _keep,
    String? effort,
    bool? useByok,
    String? provider,
    String? apiType,
    String? baseUrl,
    String? apiKey,
    String? byokModel,
  }) => TutorPrefs(
    model: identical(model, _keep) ? this.model : model as String?,
    effort: effort ?? this.effort,
    useByok: useByok ?? this.useByok,
    provider: provider ?? this.provider,
    apiType: apiType ?? this.apiType,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    byokModel: byokModel ?? this.byokModel,
  );

  /// The extra body fields of a tutor prompt, or null for the defaults / free users.
  Map<String, dynamic>? choice(AIOptions? o) {
    if (o == null || !o.allowed) return null;
    final eff = effort == 'auto' ? null : effort;
    if (useByok && apiKey.isNotEmpty && byokModel.isNotEmpty) {
      final p = o.providers.where((x) => x.id == provider).firstOrNull;
      return {
        'effort': ?eff,
        'byok': {
          'api_type': apiType,
          'base_url': baseUrl.isNotEmpty ? baseUrl : p?.baseUrl,
          'api_key': apiKey,
          'model': byokModel,
          'label': p?.label,
        },
      };
    }
    final m = model != null && o.models.any((x) => x.id == model && x.available) ? model : null;
    if (m == null && eff == null) return null;
    return {'model': ?m, 'effort': ?eff};
  }

  /// "Gemini Flash · high thinking", or null for the defaults.
  String? label(AIOptions? o) {
    final c = choice(o);
    if (c == null) return null;
    final who = c['byok'] != null
        ? 'Your key · $byokModel'
        : (o!.models.where((x) => x.id == c['model']).firstOrNull?.short ?? 'Default model');
    return c['effort'] != null ? '$who · ${c['effort']} thinking' : who;
  }
}

const _keep = Object();

final tutorPrefsProvider = NotifierProvider<TutorPrefsNotifier, TutorPrefs>(TutorPrefsNotifier.new);

class TutorPrefsNotifier extends Notifier<TutorPrefs> {
  static const _prefs = 'tutor_prefs_v1_';
  static const _keyName = 'tutor_byok_key_v1';
  static const _secure = FlutterSecureStorage();

  @override
  TutorPrefs build() {
    _load();
    return const TutorPrefs();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    String? key;
    try {
      key = await _secure.read(key: _keyName);
    } catch (_) {}
    state = TutorPrefs(
      model: p.getString('${_prefs}model'),
      effort: p.getString('${_prefs}effort') ?? 'auto',
      useByok: p.getBool('${_prefs}byok') ?? false,
      provider: p.getString('${_prefs}provider') ?? 'openai',
      apiType: p.getString('${_prefs}api_type') ?? 'openai',
      baseUrl: p.getString('${_prefs}base_url') ?? '',
      apiKey: key ?? '',
      byokModel: p.getString('${_prefs}byok_model') ?? '',
    );
  }

  Future<void> set(TutorPrefs v) async {
    final keyChanged = v.apiKey != state.apiKey;
    state = v;
    final p = await SharedPreferences.getInstance();
    if (v.model == null) {
      await p.remove('${_prefs}model');
    } else {
      await p.setString('${_prefs}model', v.model!);
    }
    await p.setString('${_prefs}effort', v.effort);
    await p.setBool('${_prefs}byok', v.useByok);
    await p.setString('${_prefs}provider', v.provider);
    await p.setString('${_prefs}api_type', v.apiType);
    await p.setString('${_prefs}base_url', v.baseUrl);
    await p.setString('${_prefs}byok_model', v.byokModel);
    if (keyChanged) {
      try {
        v.apiKey.isEmpty ? await _secure.delete(key: _keyName) : await _secure.write(key: _keyName, value: v.apiKey);
      } catch (_) {}
    }
  }
}

Future<void> showTutorSettings(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _TutorSettingsSheet(),
);

class _TutorSettingsSheet extends ConsumerStatefulWidget {
  const _TutorSettingsSheet();

  @override
  ConsumerState<_TutorSettingsSheet> createState() => _TutorSettingsSheetState();
}

class _TutorSettingsSheetState extends ConsumerState<_TutorSettingsSheet> {
  late final _key = TextEditingController(text: ref.read(tutorPrefsProvider).apiKey);
  late final _model = TextEditingController(text: ref.read(tutorPrefsProvider).byokModel);
  late final _base = TextEditingController(text: ref.read(tutorPrefsProvider).baseUrl);
  var _models = <String>[];
  var _checking = false;
  var _hideKey = true;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _base.dispose();
    super.dispose();
  }

  TutorPrefs get _p => ref.read(tutorPrefsProvider);
  void _set(TutorPrefs v) => ref.read(tutorPrefsProvider.notifier).set(v);

  Future<void> _check(ByokProvider? prov) async {
    setState(() => _checking = true);
    try {
      final d = await ref.read(apiProvider).post<Map<String, dynamic>>('/ai/byok/models', data: {
        'byok': {
          'api_type': _p.apiType,
          'base_url': _base.text.trim().isNotEmpty ? _base.text.trim() : prov?.baseUrl,
          'api_key': _key.text.trim(),
          'model': '',
        },
      });
      setState(() => _models = [for (final m in (d['models'] as List? ?? const [])) '$m']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Key works · ${_models.length} models')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final opts = ref.watch(aiOptionsProvider);
    final p = ref.watch(tutorPrefsProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: opts.when(
        loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
        error: (_, _) => const SizedBox(height: 120, child: Center(child: Text('Could not load the options'))),
        data: (o) {
          if (o == null) return const SizedBox(height: 120, child: Center(child: Text('Could not load the options')));
          final locked = !o.allowed;
          final prov = o.providers.where((x) => x.id == p.provider).firstOrNull ?? o.providers.firstOrNull;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tutor settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                if (locked)
                  Card(
                    color: cs.primaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.lock_outline_rounded),
                      title: const Text('Pro and Contributor'),
                      subtitle: Text(o.upgradeMessage ??
                          'Pick the model, the thinking level and use your own API key. Paid answers also read more textbook passages.'),
                      onTap: () => showPaywall(context),
                    ),
                  ),
                IgnorePointer(
                  ignoring: locked,
                  child: Opacity(
                    opacity: locked ? 0.5 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Model', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          ChoiceChip(
                            label: const Text('Default'),
                            selected: p.model == null,
                            onSelected: p.useByok ? null : (_) => _set(p.copyWith(model: null)),
                          ),
                          for (final m in o.models)
                            ChoiceChip(
                              avatar: m.available ? null : const Icon(Icons.lock_outline_rounded, size: 16),
                              label: Text(m.label),
                              selected: p.model == m.id,
                              onSelected: p.useByok
                                  ? null
                                  : (_) => m.available ? _set(p.copyWith(model: m.id)) : showPaywall(context),
                            ),
                        ]),
                        const SizedBox(height: 16),
                        Text('Thinking', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            for (final e in o.efforts) ButtonSegment(value: e, label: Text(e[0].toUpperCase() + e.substring(1))),
                          ],
                          selected: {p.effort},
                          onSelectionChanged: (s) => _set(p.copyWith(effort: s.first)),
                        ),
                        const SizedBox(height: 4),
                        Text('More thinking is slower but better on hard derivations.',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.key_rounded),
                          title: const Text('Use my own API key'),
                          value: p.useByok,
                          onChanged: (v) => _set(p.copyWith(useByok: v)),
                        ),
                        if (p.useByok) ...[
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final x in o.providers)
                              ChoiceChip(
                                label: Text(x.label),
                                selected: p.provider == x.id,
                                onSelected: (_) {
                                  _base.text = x.baseUrl;
                                  setState(() => _models = []);
                                  _set(p.copyWith(provider: x.id, apiType: x.apiType, baseUrl: x.baseUrl));
                                },
                              ),
                          ]),
                          const SizedBox(height: 10),
                          if (prov?.id == 'custom')
                            TextField(
                              controller: _base,
                              keyboardType: TextInputType.url,
                              decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://api.example.com/v1'),
                              onChanged: (v) => _set(_p.copyWith(baseUrl: v.trim())),
                            ),
                          TextField(
                            controller: _key,
                            obscureText: _hideKey,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: 'API key',
                              suffixIcon: IconButton(
                                icon: Icon(_hideKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _hideKey = !_hideKey),
                              ),
                            ),
                            onChanged: (v) => _set(_p.copyWith(apiKey: v.trim())),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: _model,
                                decoration: InputDecoration(labelText: 'Model', hintText: prov?.hint),
                                onChanged: (v) => _set(_p.copyWith(byokModel: v.trim())),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _checking || _key.text.trim().length < 8 ? null : () => _check(prov),
                              child: _checking
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Check'),
                            ),
                          ]),
                          if (_models.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 40,
                              child: ListView(scrollDirection: Axis.horizontal, children: [
                                for (final m in _models.take(60))
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ActionChip(
                                      label: Text(m),
                                      onPressed: () {
                                        _model.text = m;
                                        _set(_p.copyWith(byokModel: m));
                                      },
                                    ),
                                  ),
                              ]),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Your key stays on this phone (Android keystore) and is sent only with your own tutor prompts. '
                            'Textbook search still runs on Outstagram. Up to ${o.byokPerHour} prompts an hour, not counted in your AI limit.',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                        if (!locked) ...[
                          const SizedBox(height: 12),
                          Text('Your plan: answers read up to ${o.passages} textbook passages and the last ${o.historyTurns} messages.',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
