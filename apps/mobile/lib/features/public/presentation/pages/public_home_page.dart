import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/l10n/locale_controller.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../shared/widgets/app_logo.dart';
import '../../../../shared/widgets/module_placeholder_page.dart';
import '../../data/content_repository.dart';
import '../../domain/content_models.dart';
import '../widgets/content_widgets.dart';
import 'news_detail_page.dart';
import 'news_list_page.dart';

/// Public landing page for Sickler's Warriors (FINALIZE public home).
///
/// A full public brand experience: pinned header with mega-menus, the admin
/// top-ticker, an editorial news hub (latest + featured), the seven core
/// service areas, trust/privacy/consent, a final CTA and a real footer.
/// Everything the visitor can tap navigates somewhere real.
class PublicHomePage extends StatefulWidget {
  const PublicHomePage({super.key, ContentRepository? content})
      : _content = content;

  static const String routeName = '/';

  final ContentRepository? _content;

  @override
  State<PublicHomePage> createState() => _PublicHomePageState();
}

class _PublicHomePageState extends State<PublicHomePage> {
  late final ContentRepository _content =
      widget._content ?? ContentRepository();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 1024;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _PublicHeader(isDesktop: isDesktop),
          _TopTickerBanner(content: _content),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroSection(isDesktop: isDesktop, theme: theme),
                NewsSections(
                  content: _content,
                  onOpenArticle: _openArticle,
                ),
                _SectionStrip(
                  children: [
                    _ServiceSection(
                      title: s.tr('srv.healthTitle'),
                      subtitle: s.tr('srv.healthSubtitle'),
                      icon: Icons.health_and_safety_outlined,
                      actions: const [
                        _SectionAction(labelKey: 'act.healthDashboard', route: '/health'),
                        _SectionAction(labelKey: 'act.manageMedication', route: '/medication'),
                      ],
                    ),
                    _ServiceSection(
                      title: s.tr('srv.doctorTitle'),
                      subtitle: s.tr('srv.doctorSubtitle'),
                      icon: Icons.medical_services_outlined,
                      actions: const [
                        _SectionAction(labelKey: 'act.findDoctor', route: '/doctors'),
                        _SectionAction(labelKey: 'act.visitClinic', route: '/clinic'),
                      ],
                    ),
                    _ServiceSection(
                      title: s.tr('srv.bloodTitle'),
                      subtitle: s.tr('srv.bloodSubtitle'),
                      icon: Icons.bloodtype_outlined,
                      emergencyAccent: true,
                      actions: const [
                        _SectionAction(labelKey: 'act.bloodNetwork', route: '/blood-donation'),
                        _SectionAction(labelKey: 'act.donateBlood', route: '/donor-home'),
                      ],
                    ),
                    _ServiceSection(
                      title: s.tr('srv.emergencyTitle'),
                      subtitle: s.tr('srv.emergencySubtitle'),
                      icon: Icons.emergency_outlined,
                      emergencyAccent: true,
                      actions: const [
                        _SectionAction(labelKey: 'act.emergencySos', route: '/emergency'),
                      ],
                    ),
                    _ServiceSection(
                      title: s.tr('srv.educationTitle'),
                      subtitle: s.tr('srv.educationSubtitle'),
                      icon: Icons.school_outlined,
                      actions: const [
                        _SectionAction(labelKey: 'act.openAcademy', route: '/education'),
                      ],
                    ),
                    _ServiceSection(
                      title: s.tr('srv.communityTitle'),
                      subtitle: s.tr('srv.communitySubtitle'),
                      icon: Icons.forum_outlined,
                      actions: const [
                        _SectionAction(labelKey: 'act.joinCommunity', route: '/community'),
                        _SectionAction(labelKey: 'act.messages', route: '/messages'),
                        _SectionAction(labelKey: 'act.aiCoach', route: '/ai-assistant'),
                      ],
                    ),
                    _ServiceSection(
                      title: s.tr('srv.donateTitle'),
                      subtitle: s.tr('srv.donateSubtitle'),
                      icon: Icons.volunteer_activism_outlined,
                      actions: const [
                        _SectionAction(labelKey: 'act.makeDonation', route: '/donations'),
                        _SectionAction(labelKey: 'act.changiaHub', route: '/changia'),
                      ],
                    ),
                  ],
                ),
                _TrustSection(theme: theme),
                _FinalCTASection(theme: theme),
                _Footer(theme: theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openArticle(PublicNewsArticle article) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewsDetailPage(uid: article.uid, intro: article),
      ),
    );
  }
}

// ===================================================================== header

class _PublicHeader extends StatelessWidget {
  const _PublicHeader({required this.isDesktop});

  final bool isDesktop;

  void _go(BuildContext context, _MenuLink link) {
    if (link.route.isNotEmpty) {
      goTo(context, link.route);
    } else if (link.page != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => link.page!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final menus = _megaMenusFor(s);
    return SliverAppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 2,
      pinned: true,
      centerTitle: false,
      toolbarHeight: isDesktop ? 72 : 60,
      titleSpacing: AppSpacing.lg,
      title: AppBrand(markHeight: isDesktop ? 36 : 30, onTap: null),
      actions: isDesktop
          ? [
              for (final (index, entry) in menus.entries.indexed) ...[
                if (index > 0) const SizedBox(width: AppSpacing.sm),
                _HeaderMenuButton(
                  label: entry.key,
                  links: entry.value,
                  onSelected: (l) => _go(context, l),
                ),
              ],
              const SizedBox(width: AppSpacing.md),
              const _PublicThemeToggle(),
              const _PublicLanguageToggle(),
              const SizedBox(width: AppSpacing.xs),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: Text(s.tr('common.signIn')),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.lg),
                child: FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/signup'),
                  child: Text(s.tr('common.signUp')),
                ),
              ),
            ]
          : [
              const _PublicThemeToggle(),
              const _PublicLanguageToggle(),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: Text(s.tr('common.signIn')),
              ),
              IconButton(
                tooltip: s.tr('home.explore'),
                onPressed: () => _showMobileMenu(context),
                icon: const Icon(Icons.menu),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
    );
  }

  void _showMobileMenu(BuildContext context) {
    final s = AppLocalizations.of(context);
    final entries = _megaMenusFor(s).entries.toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in entries) ...[
                  _MobileMenuCategory(
                    title: entry.key,
                    links: entry.value,
                    onSelected: (link) {
                      Navigator.of(sheetContext).pop();
                      _go(context, link);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const Divider(color: AppColors.border),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1),
                  title: Text(s.tr('common.createAccount')),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.pushNamed(context, '/signup');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PublicThemeToggle extends StatelessWidget {
  const _PublicThemeToggle();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.maybeOf(context);
    if (theme == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      key: const ValueKey('public-theme-toggle'),
      tooltip: dark ? 'Light mode' : 'Dark mode',
      onPressed: () =>
          theme.setMode(dark ? ThemeMode.light : ThemeMode.dark),
      icon: Icon(
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 20,
      ),
    );
  }
}

class _PublicLanguageToggle extends StatelessWidget {
  const _PublicLanguageToggle();

  @override
  Widget build(BuildContext context) {
    final locale = LocaleScope.maybeOf(context);
    if (locale == null) return const SizedBox.shrink();
    final swahili = locale.isSwahili;
    return TextButton(
      key: const ValueKey('public-language-toggle'),
      onPressed: () => locale.setLanguage(swahili ? 'en' : 'sw'),
      child: Text(
        swahili ? 'EN' : 'SW',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _HeaderMenuButton extends StatelessWidget {
  const _HeaderMenuButton({
    required this.label,
    required this.links,
    required this.onSelected,
  });

  final String label;
  final List<_MenuLink> links;
  final ValueChanged<_MenuLink> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuLink>(
      key: Key('mega-$label'),
      tooltip: '$label menu',
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final link in links)
          PopupMenuItem<_MenuLink>(
            value: link,
            height: 44,
            child: Row(
              children: [
                Icon(link.icon, size: 18, color: AppColors.navy),
                const SizedBox(width: AppSpacing.sm),
                Text(link.label),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _MobileMenuCategory extends StatelessWidget {
  const _MobileMenuCategory({
    required this.title,
    required this.links,
    required this.onSelected,
  });

  final String title;
  final List<_MenuLink> links;
  final ValueChanged<_MenuLink> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
            color: AppColors.blue,
          ),
        ),
        for (final link in links)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(link.icon, size: 20, color: AppColors.navy),
            title: Text(link.label),
            onTap: () => onSelected(link),
          ),
      ],
    );
  }
}

// ============================================================== admin ticker

/// The admin top-ticker: every active announcement plays as a continuous
/// scrolling marquee so the band is always visibly alive, even with a single
/// announcement. Hidden entirely when the platform has no active announcement
/// so no empty band ever appears.
class _TopTickerBanner extends StatefulWidget {
  const _TopTickerBanner({required this.content});

  final ContentRepository content;

  @override
  State<_TopTickerBanner> createState() => _TopTickerBannerState();
}

class _TopTickerBannerState extends State<_TopTickerBanner> {
  List<TickerAnnouncement> _items = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<TickerAnnouncement> items;
    try {
      items = await widget.content.listTicker();
    } catch (_) {
      items = const [];
    }
    if (!mounted) return;
        setState(() {
      _items = items;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
        if (!_loaded || _items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final urgent = _items.first.isUrgent;
    final text = _items.map((e) => e.message).join('        •        ');
    return SliverToBoxAdapter(
      child: Material(
        color: urgent ? AppColors.emergency : AppColors.navy,
        child: SafeArea(
          bottom: false,
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  urgent ? Icons.emergency : Icons.campaign_outlined,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _TickerMarquee(
                    text: text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (_items.first.linkUrl.isNotEmpty)
                  const Icon(Icons.open_in_new, size: 14, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Seamless horizontal crawl used by the top ticker band.
///
/// The message always crawls (short messages are repeated enough to fill the
/// band edge to edge) so the ticker never sits still, and the loop has no
/// visible jump. Respects the platform "disable animations" setting.
class _TickerMarquee extends StatefulWidget {
  const _TickerMarquee({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_TickerMarquee> createState() => _TickerMarqueeState();
}

class _TickerMarqueeState extends State<_TickerMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _controller.repeat();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gap = 80.0;
    const speed = 42.0;

    Widget staticText() => Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.style,
        );

    if (MediaQuery.disableAnimationsOf(context)) return staticText();

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final contentWidth = painter.width;
        if (contentWidth <= 0) return staticText();

        final loopDistance = contentWidth + gap;
        // Repeat the message until the band is always covered edge to edge,
        // so even a one-word ticker crawls instead of sitting still.
        final copies = math.max(
          2,
          (constraints.maxWidth / loopDistance).ceil() + 1,
        );
        final durationMs = (loopDistance / speed * 1000).round();
        if (_controller.duration?.inMilliseconds != durationMs) {
          _controller.duration = Duration(milliseconds: durationMs);
        }
        if (!_started) {
          _started = true;
          _controller.forward();
        }
        return SizedBox(
          height: 22,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Transform.translate(
                  offset: Offset(-(_controller.value * loopDistance), 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < copies; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        Text(widget.text, maxLines: 1, style: widget.style),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ====================================================================== hero

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.isDesktop, required this.theme});

  final bool isDesktop;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final headline = s.tr('home.heroTitle');
    final subtitle = s.tr('home.heroSubtitle');
    final body = s.tr('home.heroBody');

    final content = Column(
      crossAxisAlignment: isDesktop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          headline,
          textAlign: isDesktop ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          subtitle,
          textAlign: isDesktop ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: const Color(0xFFFDECEF),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          body,
          textAlign: isDesktop ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: .85),
            height: 1.55,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          alignment: isDesktop ? WrapAlignment.start : WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: () => Navigator.pushNamed(context, '/signup'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emergency,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
              child: Text(s.tr('common.createAccount')),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
              child: Text(s.tr('common.signIn')),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, NewsListPage.routeName),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(s.tr('home.readLatest')),
            ),
          ],
        ),
      ],
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, Color(0xFF0E2A4F), AppColors.blue],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: isDesktop ? AppSpacing.xxxl : AppSpacing.xxl,
            horizontal: isDesktop ? AppSpacing.xxxl : AppSpacing.lg,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (isDesktop) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: content),
                    const SizedBox(width: AppSpacing.xxxl),
                    const Expanded(flex: 2, child: _HeroBrandPanel()),
                  ],
                );
              }
              return Column(
                children: [
                  const _HeroBrandPanel(),
                  const SizedBox(height: AppSpacing.xl),
                  content,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroBrandPanel extends StatelessWidget {
  const _HeroBrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(height: 128),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppStrings.appName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppLocalizations.of(context).tr('home.tagline'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ==================================================================== news

/// Live news hub: latest article hero card + featured rows + archive link.
/// Degrades gracefully to a compact "updates" band when the content service
/// is unavailable, keeping the layout truthful and the CTAs functional.
class NewsSections extends StatefulWidget {
  const NewsSections({
    super.key,
    required this.content,
    required this.onOpenArticle,
  });

  final ContentRepository content;
  final ValueChanged<PublicNewsArticle> onOpenArticle;

  @override
  State<NewsSections> createState() => _NewsSectionsState();
}

class _NewsSectionsState extends State<NewsSections> {
  PublicNewsDetail? _latest;
  List<PublicNewsArticle> _featured = const [];
  List<PublicNewsArticle> _recent = const [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final latest = await widget.content.latestArticle();
      final featured = await widget.content.listNews(featured: true);
      final recent = await widget.content.listNews(page: 1);
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _featured = featured.items;
        _recent = recent.items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    if (_loading) {
      return _Band(
        background: Colors.white,
        child: _BandHeader(
          title: s.tr('home.newsLatest'),
          theme: theme,
          trailing: _GhostButton(label: s.tr('home.newsViewAll')),
        ),
      );
    }
    if (_error || (_latest == null && _featured.isEmpty && _recent.isEmpty)) {
      return _Band(
        background: Colors.white,
        child: _BandHeader(
          title: s.tr('home.newsLatest'),
          theme: theme,
          subtitle: s.tr('home.newsEmpty'),
          trailing: FilledButton.tonal(
            onPressed: () => Navigator.pushNamed(context, NewsListPage.routeName),
            child: Text(s.tr('home.newsViewAll')),
          ),
        ),
      );
    }

    final latest = _latest;
    final slides = <PublicNewsArticle>[];
    final seen = <String>{};
    for (final a in [if (latest != null) latest, ..._featured, ..._recent]) {
      if (seen.add(a.uid)) slides.add(a);
      if (slides.length >= 5) break;
    }
    return _Band(
      background: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BandHeader(
            title: s.tr('home.newsLatest'),
            theme: theme,
            subtitle: s.tr('home.newsSubtitle'),
            trailing: FilledButton.tonal(
              onPressed: () => Navigator.pushNamed(context, NewsListPage.routeName),
              child: Text(s.tr('home.newsViewAll')),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (slides.isNotEmpty) ...[
            _NewsCarousel(
              articles: slides,
              onSelect: widget.onOpenArticle,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (_featured.isNotEmpty) ...[
            Text(
              s.tr('home.newsFeatured'),
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.lg,
                  children: [
                    for (final article in _featured.take(4))
                      SizedBox(
                        width: width > 900
                            ? (width - AppSpacing.lg * 3) / 4
                            : width > 560
                                ? (width - AppSpacing.lg) / 2
                                : width,
                        child: _CompactNewsCard(
                          article: article,
                          onTap: () => widget.onOpenArticle(article),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (_recent.isNotEmpty) ...[
            for (final article in _recent.where((a) => a.uid != latest?.uid).take(3))
              _CompactNewsRow(
                article: article,
                onTap: () => widget.onOpenArticle(article),
              ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

/// Auto-rotating editorial slideshow: the top news stories play as full-width
/// slides with a 5 s autoplay, pausing while the visitor drags, and a dot
/// indicator. Tapping a slide opens the article.
class _NewsCarousel extends StatefulWidget {
  const _NewsCarousel({required this.articles, required this.onSelect});

  final List<PublicNewsArticle> articles;
  final ValueChanged<PublicNewsArticle> onSelect;

  @override
  State<_NewsCarousel> createState() => _NewsCarouselState();
}

class _NewsCarouselState extends State<_NewsCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    _timer?.cancel();
    if (widget.articles.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final next = (_page + 1) % widget.articles.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.articles.length;
    if (count == 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 720;
        final height = wide ? 240.0 : 340.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: PageView.builder(
                controller: _controller,
                itemCount: count,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: _CarouselCard(
                    article: widget.articles[index],
                    onTap: () => widget.onSelect(widget.articles[index]),
                  ),
                ),
              ),
            ),
            if (count > 1) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < count; i++)
                    AnimatedContainer(
                      key: ValueKey(
                        'carousel-dot-${i == _page ? 'active' : 'inactive'}-$i',
                      ),
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? AppColors.blue : AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Single carousel slide: the top story with cover art, category, title and
/// metadata, laid out as a two-column "wide" row on desktop and a stacked
/// cover-over-text column on narrow screens.
class _CarouselCard extends StatelessWidget {
  const _CarouselCard({required this.article, required this.onTap});

  final PublicNewsArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    return Material(
      color: const Color(0xFFFDECEF),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 720;
            final title = Text(
              article.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.darkRed,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            );
            final meta = PublicNewsMetaRow(
              publishedAt: article.publishedAt,
              author: article.authorName,
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PublicNewsCover(
                    url: article.coverUrl,
                    alt: article.coverAlt,
                    height: 130,
                    borderRadius: 0,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PublicNewsCategoryChip(
                            label: s.tr('home.newsLatestUpdate'),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          title,
                          const Spacer(),
                          meta,
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(
                  width: 280,
                  child: PublicNewsCover(
                    url: article.coverUrl,
                    alt: article.coverAlt,
                    height: 180,
                    borderRadius: 20,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PublicNewsCategoryChip(
                          label: s.tr('home.newsLatestUpdate'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        title,
                        if (article.excerpt.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              article.excerpt,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                        meta,
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompactNewsCard extends StatelessWidget {
  const _CompactNewsCard({required this.article, required this.onTap});

  final PublicNewsArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PublicNewsCover(url: article.coverUrl, alt: article.coverAlt, height: 96, borderRadius: 0),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (article.categoryLabel.isNotEmpty)
                    PublicNewsCategoryChip(label: article.categoryLabel),
                  if (article.categoryLabel.isNotEmpty) const SizedBox(height: AppSpacing.sm),
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  PublicNewsMetaRow(publishedAt: article.publishedAt),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactNewsRow extends StatelessWidget {
  const _CompactNewsRow({required this.article, required this.onTap});

  final PublicNewsArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              SizedBox(
                width: 74,
                child: PublicNewsCover(
                  url: article.coverUrl,
                  alt: article.coverAlt,
                  height: 60,
                  borderRadius: 12,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (article.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        article.excerpt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.chevron_right, color: AppColors.blue, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================================================== service area sections

class _SectionStrip extends StatelessWidget {
  const _SectionStrip({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 1024;
    return Container(
      color: AppColors.background,
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.xxxl,
        horizontal: isDesktop ? AppSpacing.xxxl : AppSpacing.lg,
      ),
      child: Column(
        children: [
          Text(
            s.tr('home.sectionsTitle'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            s.tr('home.sectionsSubtitle'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final (index, child) in children.indexed) ...[
            child,
            if (index < children.length - 1) const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _ServiceSection extends StatelessWidget {
  const _ServiceSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    this.emergencyAccent = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<_SectionAction> actions;
  final bool emergencyAccent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    final accent = emergencyAccent ? AppColors.emergency : AppColors.blue;
    final ok = actions.where((a) => a.route.isNotEmpty).isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final action in actions)
                if (action.route.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => goTo(context, action.route),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: .5)),
                    ),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: Text(s.tr(action.labelKey)),
                  ),
            ],
          ),
          if (!ok)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                s.tr('home.signedInOnly'),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionAction {
  const _SectionAction({required this.labelKey, required this.route});

  final String labelKey;
  final String route;
}

// ==================================================================== trust

class _TrustSection extends StatelessWidget {
  const _TrustSection({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Container(
      color: AppColors.navy,
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.xxxl,
        horizontal: AppSpacing.xl,
      ),
      child: Column(
        children: [
          Text(
            s.tr('home.trustTitle'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            s.tr('home.trustBody'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: .85),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            alignment: WrapAlignment.center,
            children: [
              _TrustItem(icon: Icons.lock_outline, label: s.tr('home.trustEncrypted')),
              _TrustItem(icon: Icons.verified_user_outlined, label: s.tr('home.trustConsent')),
              _TrustItem(icon: Icons.privacy_tip_outlined, label: s.tr('home.trustPrivacy')),
              _TrustItem(icon: Icons.shield_outlined, label: s.tr('home.trustAccess')),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 26, color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: .9),
          ),
        ),
      ],
    );
  }
}

// ============================================================== final CTA

class _FinalCTASection extends StatelessWidget {
  const _FinalCTASection({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.xxxl,
        horizontal: AppSpacing.xl,
      ),
      child: Column(
        children: [
          Text(
            s.tr('home.finalCtaTitle'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: AppColors.darkRed,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            s.tr('home.finalCtaBody'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: () => Navigator.pushNamed(context, '/signup'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emergency,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
            ),
            child: Text(s.tr('common.createAccount')),
          ),
        ],
      ),
    );
  }
}

// =================================================================== footer

class _Footer extends StatelessWidget {
  const _Footer({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Container(
      color: AppColors.background,
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.xl,
      ),
      child: Column(
        children: [
          const AppBrand(markHeight: 40, showSubtitle: true),
          const SizedBox(height: AppSpacing.md),
          Text(
            s.tr('home.footerRights'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (final link in <_MenuLink>[
                _MenuLink('Privacy', icon: Icons.privacy_tip_outlined,
                    page: _infoPage('Privacy & Data Protection',
                        'How Sickler\'s Warriors handles your personal and health information with care, transparency and your consent.')),
                _MenuLink('Terms', icon: Icons.description_outlined,
                    page: _infoPage('Terms of Service',
                        'The rules and responsibilities that keep the community safe and fair for everyone.')),
                _MenuLink('Consent', icon: Icons.how_to_reg_outlined,
                    page: _infoPage('Consent & Control',
                        'Choose what you share, who can see it, and withdraw consent at any time.')),
                _MenuLink('Contact', icon: Icons.mail_outline,
                    page: _infoPage('Contact the Team',
                        'Reach out for support, partnership or feedback — the Warrior community is listening.')),
              ])
                _FooterLink(link: link),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            s.tr('home.sosFooter'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.link});

  final _MenuLink link;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        if (link.route.isNotEmpty) {
          Navigator.pushNamed(context, link.route);
        } else if (link.page != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => link.page!),
          );
        }
      },
      child: Text(
        link.label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
      ),
    );
  }
}

// ==================================================================== band

class _Band extends StatelessWidget {
  const _Band({required this.background, required this.child});

  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 1024;
    return Container(
      color: background,
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.xxxl,
        horizontal: isDesktop ? AppSpacing.xxxl : AppSpacing.lg,
      ),
      child: child,
    );
  }
}

class _BandHeader extends StatelessWidget {
  const _BandHeader({
    required this.title,
    required this.theme,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final ThemeData theme;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: null,
      child: Text(label),
    );
  }
}

// ========================================================= mega menu model

class _MenuLink {
  const _MenuLink(this.label, {this.icon = Icons.arrow_forward_ios, this.route = '', this.page});

  final String label;
  final IconData icon;
  final String route;

  /// Page for destinations without a named route (About/footer info pages).
  final Widget? page;
}

Widget _infoPage(String title, String description) => ModulePlaceholderPage(
      title: title,
      description: description,
      icon: Icons.info_outline,
    );

Map<String, List<_MenuLink>> _megaMenusFor(AppLocalizations s) {
  return {
    s.tr('nav.about'): [
      _MenuLink(s.tr('about.about'), icon: Icons.volunteer_activism_outlined,
          page: _infoPage(s.tr('about.about'),
              'A community-led platform supporting people living with sickle cell disease and their families.')),
      _MenuLink(s.tr('about.mission'), icon: Icons.track_changes_outlined,
          page: _infoPage(s.tr('about.mission'),
              'Care, connection, education and urgent support — in reach for every warrior.')),
      _MenuLink(s.tr('about.howItWorks'), icon: Icons.account_tree_outlined,
          page: _infoPage(s.tr('about.howItWorks'),
              'From sign-up to care: four simple steps into the Warrior community.')),
      _MenuLink(s.tr('about.team'), icon: Icons.groups_outlined,
          page: _infoPage(s.tr('about.team'),
              'The people and organizations behind the platform.')),
      _MenuLink(s.tr('about.contact'), icon: Icons.mail_outline,
          page: _infoPage(s.tr('about.contact'),
              'Reach out for support, partnership or feedback — the Warrior community is listening.')),
    ],
    s.tr('nav.health'): [
      _MenuLink(s.tr('act.healthDashboard'), icon: Icons.monitor_heart_outlined, route: '/health'),
      _MenuLink(s.tr('act.manageMedication'), icon: Icons.medication_outlined, route: '/medication'),
      _MenuLink(s.tr('nav.records'), icon: Icons.folder_shared_outlined, route: '/records'),
      _MenuLink(s.tr('nav.timeline'), icon: Icons.timeline_outlined, route: '/health'),
      _MenuLink(s.tr('nav.appointments'), icon: Icons.event_available_outlined, route: '/clinic'),
    ],
    s.tr('nav.blood'): [
      _MenuLink(s.tr('act.bloodNetwork'), icon: Icons.bloodtype_outlined, route: '/blood-donation'),
      _MenuLink(s.tr('act.donateBlood'), icon: Icons.water_drop_outlined, route: '/donor-home'),
      _MenuLink(s.tr('nav.supportDonations'), icon: Icons.volunteer_activism_outlined, route: '/donations'),
    ],
    s.tr('nav.community'): [
      _MenuLink(s.tr('act.joinCommunity'), icon: Icons.forum_outlined, route: '/community'),
      _MenuLink(s.tr('act.messages'), icon: Icons.chat_bubble_outline, route: '/messages'),
      _MenuLink(s.tr('act.openAcademy'), icon: Icons.school_outlined, route: '/education'),
      _MenuLink(s.tr('act.aiCoach'), icon: Icons.smart_toy_outlined, route: '/ai-assistant'),
    ],
    s.tr('nav.resources'): [
      _MenuLink(s.tr('nav.education'), icon: Icons.menu_book_outlined, route: '/education'),
      _MenuLink(s.tr('act.emergencySos'), icon: Icons.emergency_outlined, route: '/emergency'),
      _MenuLink(s.tr('nav.records'), icon: Icons.event_note_outlined, route: '/records'),
      _MenuLink(s.tr('nav.supportDonations'), icon: Icons.volunteer_activism_outlined, route: '/donations'),
    ],
    s.tr('nav.news'): [
      _MenuLink(s.tr('home.newsLatest'), icon: Icons.article_outlined, route: '/news'),
      _MenuLink(s.tr('news.readMore'), icon: Icons.newspaper_outlined, route: '/news'),
    ],
  };
}