import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_info.dart';
import '../../models/manual_topic.dart';
import '../../theme/app_theme.dart';
import 'user_manual_data.dart';

/// Modal dialog providing a master-detail in-app user manual, knowledge base,
/// and contextual help center with real-time search filtering.
class UserManualDialog extends StatefulWidget {
  final String? initialTopicId;

  const UserManualDialog({super.key, this.initialTopicId});

  /// Displays the [UserManualDialog], optionally deep-linking directly to
  /// a specific [initialTopicId].
  static Future<void> show(BuildContext context, {String? initialTopicId}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => UserManualDialog(initialTopicId: initialTopicId),
    );
  }

  @override
  State<UserManualDialog> createState() => _UserManualDialogState();
}

class _UserManualDialogState extends State<UserManualDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _detailScrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();

  late ManualTopic _selectedTopic;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final initialId = widget.initialTopicId;
    if (initialId != null) {
      _selectedTopic =
          UserManualData.getTopicById(initialId) ?? UserManualData.topics.first;
    } else {
      _selectedTopic = UserManualData.topics.first;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _detailScrollController.dispose();
    _sidebarScrollController.dispose();
    super.dispose();
  }

  List<ManualTopic> get _filteredTopics {
    if (_searchQuery.isEmpty) return UserManualData.topics;
    return UserManualData.topics
        .where((topic) => topic.matches(_searchQuery))
        .toList();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim();
      final filtered = _filteredTopics;
      if (filtered.isNotEmpty && !filtered.contains(_selectedTopic)) {
        _selectedTopic = filtered.first;
        if (_detailScrollController.hasClients) {
          _detailScrollController.jumpTo(0);
        }
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
    _searchFocusNode.requestFocus();
  }

  void _selectTopic(ManualTopic topic) {
    if (_selectedTopic.id == topic.id) return;
    setState(() {
      _selectedTopic = topic;
    });
    if (_detailScrollController.hasClients) {
      _detailScrollController.jumpTo(0);
    }
  }

  void _jumpToShortcuts() {
    final shortcutsTopic = UserManualData.getTopicById('shortcuts');
    if (shortcutsTopic != null) {
      if (_searchQuery.isNotEmpty) {
        _searchController.clear();
        _searchQuery = '';
      }
      _selectTopic(shortcutsTopic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 1040,
          maxHeight: 760,
          minWidth: 480,
          minHeight: 380,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.scaffoldBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: colors.isDark ? 0.5 : 0.15),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                _buildHeader(colors),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 290,
                        child: _buildSidebar(colors),
                      ),
                      Container(
                        width: 1,
                        color: colors.border,
                      ),
                      Expanded(
                        child: _buildDetailPanel(colors),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: colors.border,
                ),
                _buildFooter(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(AppColors colors) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors.isDark
                    ? [const Color(0xFF0284C7), const Color(0xFF06B6D4)]
                    : [const Color(0xFFB4402C), const Color(0xFF8E3122)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'User Manual & Knowledge Base',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: colors.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: colors.accent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'v${AppInfo.appVersion}',
                        style: GoogleFonts.firaCode(
                          color: colors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Offline Documentation, Step-by-Step Guides & Hotkeys',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: colors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          _buildKbdPill(colors, 'F1'),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Close Manual (Esc)',
            icon: Icon(Icons.close, color: colors.textSecondary, size: 20),
            splashRadius: 18,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sidebar (Master)
  // ---------------------------------------------------------------------------

  Widget _buildSidebar(AppColors colors) {
    final filtered = _filteredTopics;

    return Container(
      color: colors.panelBg,
      child: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              style: GoogleFonts.inter(
                color: colors.textPrimary,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search topics, tags, hotkeys...',
                hintStyle: GoogleFonts.inter(
                  color: colors.inputHint,
                  fontSize: 12.5,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: colors.textMuted,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        color: colors.textMuted,
                        splashRadius: 14,
                        onPressed: _clearSearch,
                      )
                    : null,
                filled: true,
                fillColor: colors.inputBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: colors.inputFocusBorder,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TOPICS',
                  style: GoogleFonts.inter(
                    color: colors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  '${filtered.length} ${filtered.length == 1 ? 'topic' : 'topics'}',
                  style: GoogleFonts.firaCode(
                    color: colors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Topic list or empty state
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptySearch(colors)
                : Scrollbar(
                    controller: _sidebarScrollController,
                    child: ListView.builder(
                      controller: _sidebarScrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final topic = filtered[index];
                        final isSelected = topic.id == _selectedTopic.id;
                        return _buildTopicListItem(colors, topic, isSelected);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicListItem(
    AppColors colors,
    ManualTopic topic,
    bool isSelected,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.5),
      child: Material(
        color: isSelected ? colors.selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _selectTopic(topic),
          borderRadius: BorderRadius.circular(8),
          hoverColor: colors.hoverBg,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? colors.selectedBorder : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  topic.icon,
                  size: 20,
                  color: isSelected ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              topic.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: isSelected
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (topic.badge != null) ...[
                            const SizedBox(width: 6),
                            _buildBadgePill(colors, topic.badge!, isSelected),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        topic.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: colors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadgePill(AppColors colors, String badge, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: isSelected
            ? colors.accent.withValues(alpha: 0.18)
            : colors.chipBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected
              ? colors.accent.withValues(alpha: 0.35)
              : colors.border,
        ),
      ),
      child: Text(
        badge,
        style: GoogleFonts.inter(
          color: isSelected ? colors.accent : colors.textMuted,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmptySearch(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 40,
            color: colors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            'No matching topics',
            style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try searching for a different keyword, shortcut, or feature name.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: colors.textMuted,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _clearSearch,
            icon: const Icon(Icons.backspace_outlined, size: 14),
            label: Text('Clear Search', style: GoogleFonts.inter(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.accent,
              side: BorderSide(color: colors.border),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Detail Panel (Right)
  // ---------------------------------------------------------------------------

  Widget _buildDetailPanel(AppColors colors) {
    final topic = _selectedTopic;

    return Container(
      color: colors.cardBg,
      child: Scrollbar(
        controller: _detailScrollController,
        child: SingleChildScrollView(
          controller: _detailScrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Topic Header Card
              _buildTopicHeader(colors, topic),
              const SizedBox(height: 20),

              // Sections
              ...topic.sections.map((sec) => _buildSectionCard(colors, sec)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopicHeader(AppColors colors, ManualTopic topic) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
            ),
            child: Icon(
              topic.icon,
              size: 24,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        topic.title,
                        style: GoogleFonts.outfit(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (topic.badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: colors.accent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          topic.badge!,
                          style: GoogleFonts.inter(
                            color: colors.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  topic.subtitle,
                  style: GoogleFonts.inter(
                    color: colors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                if (topic.keywords.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: topic.keywords.map((kw) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: colors.chipBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.borderSubtle),
                        ),
                        child: Text(
                          '#$kw',
                          style: GoogleFonts.firaCode(
                            color: colors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(AppColors colors, ManualSection section) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.scaffoldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 3.5,
                height: 16,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.title,
                  style: GoogleFonts.outfit(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          // Section Tags
          if (section.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: section.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.panelBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    tag,
                    style: GoogleFonts.inter(
                      color: colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 10),

          // Description
          Text(
            section.description,
            style: GoogleFonts.inter(
              color: colors.textSecondary,
              fontSize: 12.5,
              height: 1.48,
            ),
          ),

          // Steps list
          if (section.steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...section.steps.asMap().entries.map((entry) {
              final stepIndex = entry.key + 1;
              final stepText = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 7.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.accent.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '$stepIndex',
                        style: GoogleFonts.firaCode(
                          color: colors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        stepText,
                        style: GoogleFonts.inter(
                          color: colors.textPrimary,
                          fontSize: 12,
                          height: 1.42,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],

          // Tip Callout Banner
          if (section.tip != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.accent.withValues(
                  alpha: colors.isDark ? 0.1 : 0.06,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      section.tip!,
                      style: GoogleFonts.inter(
                        color: colors.textPrimary,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Keyboard Shortcuts
          if (section.shortcuts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Icon(
                    Icons.keyboard_outlined,
                    size: 15,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 1.0),
                  child: Text(
                    'Shortcuts:',
                    style: GoogleFonts.inter(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: section.shortcuts.map((sc) {
                      return _buildKbdPill(colors, sc);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKbdPill(AppColors colors, String shortcut) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.codeBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.3 : 0.06),
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      child: Text(
        shortcut,
        style: GoogleFonts.firaCode(
          color: colors.textPrimary,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Footer
  // ---------------------------------------------------------------------------

  Widget _buildFooter(AppColors colors) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colors.headerBg,
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _jumpToShortcuts,
            icon: Icon(Icons.keyboard_outlined, size: 16, color: colors.accent),
            label: Text(
              'Keyboard Shortcuts',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colors.accent.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Tip: Press F1 or Cmd+? anywhere in the app to toggle this manual.',
              style: GoogleFonts.inter(
                color: colors.textMuted,
                fontSize: 11.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.textOnAccent,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'Close',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
