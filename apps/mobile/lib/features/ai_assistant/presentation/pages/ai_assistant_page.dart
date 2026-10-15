import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../emergency/presentation/pages/emergency_page.dart';
import '../../data/ai_repository.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// AI coach (FR-AI-001/002/006) — a real chat surface over `POST /api/ai/chat/`.
///
/// Replaces the module placeholder: every turn is a live request, and the
/// screen renders the backend's own safety and provenance fields rather than
/// inventing any — emergency blocks open the SOS pathway, refusals are shown
/// as refusals, approved-knowledge citations are listed, and the non-diagnosis
/// disclaimer stays pinned above the composer.
class AiAssistantPage extends StatelessWidget {
  const AiAssistantPage({super.key, this.authController, this.repository});

  static const String routeName = '/ai-assistant';

  final AuthController? authController;
  final AiRepository? repository;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final session = authController ?? SessionScope.controllerOf(context);
    final token = session.accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    return Scaffold(
      appBar: AppTopBar(
        title: s.tr('act.aiCoach'),
        avatarName: session.displayName,
      ),
      body: SafeArea(
        child: AiAssistantView(
          accessToken: token,
          repository: repository ?? AiRepository(),
        ),
      ),
    );
  }
}

/// One use-case the API accepts; the label is localised, the code is not.
class _UseCase {
  const _UseCase(this.code, this.labelKey);

  final String code;
  final String labelKey;
}

const List<_UseCase> _useCases = [
  _UseCase('education', 'ai.useEducation'),
  _UseCase('medication_education', 'ai.useMedication'),
  _UseCase('health_questions', 'ai.useHealth'),
  _UseCase('appointment_preparation', 'ai.useAppointments'),
  _UseCase('health_summary', 'ai.useSummary'),
  _UseCase('symptom_assistance', 'ai.useSymptoms'),
  _UseCase('insight_explanation', 'ai.useInsight'),
];

enum _EntryKind { user, assistant, error }

class _ChatEntry {
  const _ChatEntry.user(this.text) : kind = _EntryKind.user, turn = null;
  const _ChatEntry.assistant(this.turn)
      : kind = _EntryKind.assistant,
        text = '';
  const _ChatEntry.error(this.text) : kind = _EntryKind.error, turn = null;

  final _EntryKind kind;
  final String text;
  final AiChatTurn? turn;
}

class AiAssistantView extends StatefulWidget {
  const AiAssistantView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final AiRepository repository;

  @override
  State<AiAssistantView> createState() => _AiAssistantViewState();
}

class _AiAssistantViewState extends State<AiAssistantView> {
  final TextEditingController _input = TextEditingController();
  final List<_ChatEntry> _entries = [];
  bool _sending = false;
  String _useCase = 'education';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send({String? preset}) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    final s = AppLocalizations.of(context);
    setState(() {
      _entries.add(_ChatEntry.user(text));
      _input.clear();
      _sending = true;
    });
    try {
      final turn = await widget.repository.sendChat(
        access: widget.accessToken,
        message: text,
        useCase: _useCase,
        metric: _useCase == 'insight_explanation' ? 'medication_adherence' : null,
      );
      if (!mounted) return;
      setState(() {
        _entries.add(_ChatEntry.assistant(turn));
        _sending = false;
      });
    } on AiRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _entries.add(_ChatEntry.error(e.isThrottled ? s.tr('ai.throttled') : e.message));
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries.add(_ChatEntry.error(s.tr('err.generic')));
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _entries.isEmpty ? _welcome(context) : _thread(context)),
        if (_sending) const LinearProgressIndicator(minHeight: 2),
        _disclaimer(context),
        _composer(context),
      ],
    );
  }

  // ------------------------------------------------------------- welcome

  Widget _welcome(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text(s.tr('ai.welcomeTitle'), style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.tr('ai.welcomeBody'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (final key in const [
              'ai.suggestCrisis',
              'ai.suggestMeds',
              'ai.suggestAppt',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: OutlinedButton.icon(
                  onPressed: () => _send(preset: s.tr(key)),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(s.tr(key)),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- thread

  Widget _thread(BuildContext context) {
    final count = _entries.length;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: count,
      itemBuilder: (context, i) => _bubble(context, _entries[count - 1 - i]),
    );
  }

  Widget _bubble(BuildContext context, _ChatEntry entry) {
    switch (entry.kind) {
      case _EntryKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: AppShapes.card,
            ),
            child: Text(
              entry.text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textOnDark, height: 1.4),
            ),
          ),
        );
      case _EntryKind.error:
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.lightRed,
            borderRadius: AppShapes.card,
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.emergency),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  entry.text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      case _EntryKind.assistant:
        return _assistantBubble(context, entry.turn!);
    }
  }

  Widget _assistantBubble(BuildContext context, AiChatTurn turn) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: AppShapes.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy_outlined,
                  size: 18, color: AppColors.blue),
              const SizedBox(width: AppSpacing.xs),
              Text(
                s.tr('ai.coach'),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.blue),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(turn.message,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
          if (turn.emergencyAction) ...[
            const SizedBox(height: AppSpacing.lg),
            _emergencyCallout(context),
          ] else if (turn.safetyBlocked) ...[
            const SizedBox(height: AppSpacing.lg),
            _refusalCallout(context),
          ],
          if (turn.sources.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.tr('ai.sources'),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final src in turn.sources)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.menu_book_outlined,
                        size: 16, color: AppColors.blue),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(src.title,
                              style: theme.textTheme.labelMedium),
                          if (src.snippet.isNotEmpty)
                            Text(
                              src.snippet,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (turn.limitation != null && turn.limitation!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.tr('ai.limitationNote'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emergencyCallout(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.emergencyContainer,
        borderRadius: AppShapes.tile,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.emergency),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  s.tr('ai.emergencyTitle'),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: AppColors.darkRed),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(s.tr('ai.emergencyBody'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () => Navigator.pushNamed(
                context, EmergencyPage.routeName),
            icon: const Icon(Icons.emergency, size: 18),
            label: Text(s.tr('ai.openEmergency')),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emergency,
            ),
          ),
        ],
      ),
    );
  }

  Widget _refusalCallout(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.lightAmber,
        borderRadius: AppShapes.tile,
      ),
      child: Row(
        children: [
          const Icon(Icons.block, size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              s.tr('ai.blockedTitle'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ composer

  Widget _disclaimer(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      color: AppColors.surfaceMuted,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Text(
        '${s.tr('ai.disclaimerLabel')}: ${s.tr('ai.disclaimer')}',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final uc in _useCases)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ChoiceChip(
                      label: Text(s.tr(uc.labelKey)),
                      selected: _useCase == uc.code,
                      onSelected: (_) => setState(() => _useCase = uc.code),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: s.tr('ai.placeholder'),
                    prefixIcon: const Icon(Icons.chat_bubble_outline),
                    border: OutlineInputBorder(
                      borderRadius: AppShapes.hero,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                tooltip: s.tr('ai.send'),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
