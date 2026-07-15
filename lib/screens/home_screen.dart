import 'package:flutter/material.dart';
import 'package:tiles_ai/screens/project_detail_screen.dart';
import '../models/catalogue_item.dart';
import '../models/profile.dart';
import '../models/project.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/catalogue_widgets.dart';
import '../widgets/shimmer_loading.dart';
import 'capture_screen.dart';
import 'catalogue_item_form_screen.dart';
import 'full_image_viewer.dart';
import 'subscription_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Provided by [MainShell] so a scan started from a step card goes through
  /// the same flow as the nav bar's scan button (and refreshes every tab).
  final VoidCallback? onScan;

  const HomeScreen({super.key, this.onScan});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  Profile? _profile;
  DashboardStats? _stats;
  List<Project> _projects = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Re-fetch everything. Called on init, pull-to-refresh, and after a scan.
  Future<void> refresh() async {
    if (mounted) setState(() => _error = null);
    try {
      final results = await Future.wait([
        SupabaseService.instance.fetchProfile(),
        SupabaseService.instance.stats(),
        SupabaseService.instance.recentProjects(limit: 6),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as Profile;
        _stats = results[1] as DashboardStats;
        _projects = results[2] as List<Project>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your dashboard.\n$e';
        _loading = false;
      });
    }
  }

  Future<void> _startScan() async {
    // Prefer the shell handler so all tabs refresh; fall back to a local push.
    if (widget.onScan != null) {
      widget.onScan!();
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CaptureScreen()));
    // A new visualization may have been saved — refresh stats & list.
    refresh();
  }

  Future<void> _openSubscription() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
    // Plan / renders may have changed after an upgrade or top-up.
    refresh();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'GOOD MORNING';
    if (h < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.85),
          radius: 1.1,
          colors: [AppColors.bgGlow, AppColors.bg],
          stops: [0.0, 0.7],
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.cream,
          backgroundColor: AppColors.card,
          onRefresh: refresh,
          child: _loading
              ? const _LoadingView()
              : _error != null
              ? _ErrorView(message: _error!, onRetry: refresh)
              : _content(),
        ),
      ),
    );
  }

  Widget _content() {
    final email = SupabaseService.instance.currentEmail;
    final name = _profile?.displayName(email) ?? 'there';
    final firstName = name.split(' ').first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        _TopBar(initial: _avatarInitial(name)),
        const SizedBox(height: 28),

        Text(
          _greeting,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Faster decisions.\nBetter sales.',
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(fontSize: 34),
        ),
        const SizedBox(height: 12),
        Text(
          'Welcome back, $firstName - walk a customer from doubt to '
          'decision in under three minutes.',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),

        // Step cards — horizontal scroll on mobile.
        SizedBox(
          height: 188,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              // _StepCard(
              //   step: 'STEP 1',
              //   title: 'Scan Space',
              //   subtitle: "Capture the customer's wall or floor",
              //   icon: Icons.center_focus_strong_rounded,
              //   onTap: _startScan,
              // ),
              // const SizedBox(width: 14),
              // _StepCard(
              //   step: 'STEP 2',
              //   title: 'Scan Product',
              //   subtitle: 'Choose the tile or marble sample',
              //   icon: Icons.view_in_ar_rounded,
              //   onTap: _startScan,
              // ),
              // const SizedBox(width: 14),
              _StepCard(
                step: 'STEP 3',
                title: 'Generate Preview',
                subtitle: 'Render the room in seconds',
                icon: Icons.auto_awesome_rounded,
                onTap: _startScan,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Live stats
        Row(
          children: [
            Expanded(
              child: _StatCard(
                eyebrow: 'TODAY',
                value: '${_stats?.today ?? 0}',
                label: 'Visualizations created',
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _StatCard(
                eyebrow: 'THIS WEEK',
                value: '${_stats?.thisWeek ?? 0}',
                label: 'Visualizations created',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        _RendersCard(
          value: '${_profile?.totalRendersLeft ?? 0}',
          plan: '${_profile?.plan ?? 'Free'} plan',
          onUpgrade: _openSubscription,
        ),
        const SizedBox(height: 28),

        const _CatalogueSection(),
        const SizedBox(height: 28),

        // Recent projects
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent projects',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 17),
            ),
            // if (_projects.isNotEmpty)
            //   const Text(
            //     'View all  →',
            //     style: TextStyle(
            //       color: AppColors.textSecondary,
            //       fontSize: 13,
            //       fontWeight: FontWeight.w500,
            //     ),
            //   ),
          ],
        ),
        const SizedBox(height: 14),
        if (_projects.isEmpty)
          _EmptyProjects(onScan: _startScan)
        else
          ..._projects.map((p) => _ProjectTile(project: p)),
      ],
    );
  }

  String _avatarInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }
}

/// Shimmer skeleton mirroring the dashboard layout while it loads.
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView(
        // Needs to scroll for RefreshIndicator to work.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          // Top bar: avatar + icon chips.
          const Row(
            children: [
              ShimmerBox(width: 40, height: 40, radius: 20),
              Spacer(),
              ShimmerBox(width: 40, height: 40),
              SizedBox(width: 10),
              ShimmerBox(width: 40, height: 40),
            ],
          ),
          const SizedBox(height: 28),
          // Greeting eyebrow + headline + welcome copy.
          const ShimmerBox(width: 130, height: 12, radius: 6),
          const SizedBox(height: 16),
          const ShimmerBox(width: 250, height: 32, radius: 8),
          const SizedBox(height: 10),
          const ShimmerBox(width: 190, height: 32, radius: 8),
          const SizedBox(height: 16),
          const ShimmerBox(height: 14, radius: 6),
          const SizedBox(height: 8),
          const ShimmerBox(width: 230, height: 14, radius: 6),
          const SizedBox(height: 28),
          // Step card.
          const Align(
            alignment: Alignment.centerLeft,
            child: ShimmerBox(width: 220, height: 188, radius: 20),
          ),
          const SizedBox(height: 24),
          // Stat cards.
          const Row(
            children: [
              Expanded(child: ShimmerBox(height: 118, radius: 20)),
              SizedBox(width: 14),
              Expanded(child: ShimmerBox(height: 118, radius: 20)),
            ],
          ),
          const SizedBox(height: 14),
          // Renders card.
          const ShimmerBox(height: 108, radius: 20),
          const SizedBox(height: 28),
          // Catalogue header + cards.
          const ShimmerBox(width: 140, height: 18, radius: 6),
          const SizedBox(height: 14),
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) =>
                  const ShimmerBox(width: 158, height: 176, radius: 18),
            ),
          ),
          const SizedBox(height: 28),
          // Recent projects header + tiles.
          const ShimmerBox(width: 160, height: 18, radius: 6),
          const SizedBox(height: 14),
          for (var i = 0; i < 3; i++) ...const [
            ShimmerBox(height: 68, radius: 16),
            SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    print('ErrorView: $message');
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 200),
        const Icon(
          Icons.cloud_off_rounded,
          size: 48,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
            ),
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final String initial;
  const _TopBar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.cream,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              color: AppColors.onCream,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
        const Spacer(),
        _IconChip(icon: Icons.notifications_none_rounded, onTap: () {}),
        const SizedBox(width: 10),
        _IconChip(icon: Icons.grid_view_rounded, onTap: () {}),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconChip({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 19, color: AppColors.textSecondary),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _StepCard({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: AppColors.textPrimary),
                ),
                const Icon(
                  Icons.north_east_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ],
            ),
            const Spacer(),
            // Text(
            //   step,
            //   style: const TextStyle(
            //     color: AppColors.textMuted,
            //     fontSize: 10,
            //     fontWeight: FontWeight.w600,
            //     letterSpacing: 1.6,
            //   ),
            // ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String eyebrow;
  final String value;
  final String label;

  const _StatCard({
    required this.eyebrow,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RendersCard extends StatelessWidget {
  final String value;
  final String plan;
  final VoidCallback onUpgrade;

  const _RendersCard({
    required this.value,
    required this.plan,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RENDERS LEFT',
                style: TextStyle(
                  color: AppColors.onCream.withValues(alpha: 0.55),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.onCream,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                plan,
                style: TextStyle(
                  color: AppColors.onCream.withValues(alpha: 0.65),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: onUpgrade,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.onCream,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Upgrade',
                style: TextStyle(
                  color: AppColors.cream,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyProjects({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onScan,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.auto_awesome_outlined,
              size: 30,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              'No projects yet',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap to scan your first space and create a visualization.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final Project project;
  const _ProjectTile({required this.project});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(project: project),
        ),
      ),

      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 40,
                height: 40,
                child: project.resultImageUrl != null
                    ? Image.network(
                        project.resultImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _TileThumbFallback(),
                      )
                    : const _TileThumbFallback(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    project.surface,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  project.timeAgo,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TileThumbFallback extends StatelessWidget {
  const _TileThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: const Icon(
        Icons.grid_view_rounded,
        size: 18,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// The merchant's product catalogue, split into Tiles and Marbles sections.
/// Anything saved here becomes selectable on the tile screen — so a rep can
/// preview a product for a customer without taking a fresh photo. Manages its
/// own load so it refreshes independently after an add / edit.
class _CatalogueSection extends StatefulWidget {
  const _CatalogueSection();

  @override
  State<_CatalogueSection> createState() => _CatalogueSectionState();
}

class _CatalogueSectionState extends State<_CatalogueSection> {
  List<CatalogueItem> _items = const [];
  TileCategory _category = TileCategory.tiles;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await SupabaseService.instance.listCatalogueItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openForm({CatalogueItem? item}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CatalogueItemFormScreen(category: _category, item: item),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items.where((i) => i.category == _category).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Catalogue',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 17),
            ),
            GestureDetector(
              onTap: () => _openForm(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: AppColors.onCream,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Save tiles & marbles to reuse without a photo.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 14),
        CategorySelector(
          selected: _category,
          onChanged: (c) => setState(() => _category = c),
        ),
        const SizedBox(height: 16),
        if (_loading)
          SizedBox(
            height: 176,
            child: AppShimmer(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, _) =>
                    const ShimmerBox(width: 158, height: 176, radius: 18),
              ),
            ),
          )
        else if (visible.isEmpty)
          _EmptyCatalogueCard(category: _category, onAdd: () => _openForm())
        else
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: visible.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                if (i == visible.length) {
                  return _AddCatalogueCard(
                    category: _category,
                    onTap: () => _openForm(),
                  );
                }
                return _CatalogueCard(
                  item: visible[i],
                  onTap: () => _openForm(item: visible[i]),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _CatalogueCard extends StatelessWidget {
  final CatalogueItem item;
  final VoidCallback onTap;

  const _CatalogueCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 158,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 104,
                  width: double.infinity,
                  child: item.imageUrl.isEmpty
                      ? const ColoredBox(
                          color: AppColors.surface,
                          child: Icon(
                            Icons.grid_view_rounded,
                            color: AppColors.textSecondary,
                          ),
                        )
                      : Image.network(
                          item.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: AppColors.surface,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                ),
                if (item.tags.isNotEmpty)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: TagChip(item.tags.first, small: true),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.detailLine.isEmpty
                        ? item.category.label
                        : item.detailLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCatalogueCard extends StatelessWidget {
  final TileCategory category;
  final VoidCallback onTap;

  const _AddCatalogueCard({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 128,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add ${category.label.toLowerCase()}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCatalogueCard extends StatelessWidget {
  final TileCategory category;
  final VoidCallback onAdd;

  const _EmptyCatalogueCard({required this.category, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final label = category.label.toLowerCase();
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.grid_view_rounded,
              size: 28,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No $label yet',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap to add your first $label and reuse it without a photo.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
