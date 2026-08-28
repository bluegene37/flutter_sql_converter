import 'package:flutter/material.dart';

/// A discrete section within a user manual topic, featuring structured steps,
/// tips, associated shortcuts, and indexing tags.
class ManualSection {
  final String title;
  final String description;
  final List<String> steps;
  final String? tip;
  final List<String> shortcuts;
  final List<String> tags;

  const ManualSection({
    required this.title,
    required this.description,
    this.steps = const [],
    this.tip,
    this.shortcuts = const [],
    this.tags = const [],
  });

  ManualSection copyWith({
    String? title,
    String? description,
    List<String>? steps,
    String? tip,
    List<String>? shortcuts,
    List<String>? tags,
  }) {
    return ManualSection(
      title: title ?? this.title,
      description: description ?? this.description,
      steps: steps ?? this.steps,
      tip: tip ?? this.tip,
      shortcuts: shortcuts ?? this.shortcuts,
      tags: tags ?? this.tags,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ManualSection &&
        other.title == title &&
        other.description == description &&
        _listEquals(other.steps, steps) &&
        other.tip == tip &&
        _listEquals(other.shortcuts, shortcuts) &&
        _listEquals(other.tags, tags);
  }

  @override
  int get hashCode => Object.hash(
        title,
        description,
        Object.hashAll(steps),
        tip,
        Object.hashAll(shortcuts),
        Object.hashAll(tags),
      );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A top-level user manual topic containing one or more [ManualSection]s.
class ManualTopic {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final List<String> keywords;
  final List<ManualSection> sections;

  const ManualTopic({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.badge,
    this.keywords = const [],
    required this.sections,
  });

  /// Evaluates whether this topic matches a user-entered search query across
  /// its id, title, subtitle, badge, keywords, and all nested section contents.
  bool matches(String query) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return true;

    if (id.toLowerCase().contains(cleanQuery)) return true;
    if (title.toLowerCase().contains(cleanQuery)) return true;
    if (subtitle.toLowerCase().contains(cleanQuery)) return true;
    if (badge != null && badge!.toLowerCase().contains(cleanQuery)) return true;

    for (final kw in keywords) {
      if (kw.toLowerCase().contains(cleanQuery)) return true;
    }

    for (final section in sections) {
      if (section.title.toLowerCase().contains(cleanQuery)) return true;
      if (section.description.toLowerCase().contains(cleanQuery)) return true;
      if (section.tip != null &&
          section.tip!.toLowerCase().contains(cleanQuery)) {
        return true;
      }
      for (final step in section.steps) {
        if (step.toLowerCase().contains(cleanQuery)) return true;
      }
      for (final tag in section.tags) {
        if (tag.toLowerCase().contains(cleanQuery)) return true;
      }
      for (final sc in section.shortcuts) {
        if (sc.toLowerCase().contains(cleanQuery)) return true;
      }
    }

    return false;
  }

  ManualTopic copyWith({
    String? id,
    String? title,
    String? subtitle,
    IconData? icon,
    String? badge,
    List<String>? keywords,
    List<ManualSection>? sections,
  }) {
    return ManualTopic(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      badge: badge ?? this.badge,
      keywords: keywords ?? this.keywords,
      sections: sections ?? this.sections,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ManualTopic &&
        other.id == id &&
        other.title == title &&
        other.subtitle == subtitle &&
        other.icon == icon &&
        other.badge == badge &&
        _listEquals(other.keywords, keywords) &&
        _listEquals(other.sections, sections);
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        subtitle,
        icon,
        badge,
        Object.hashAll(keywords),
        Object.hashAll(sections),
      );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
