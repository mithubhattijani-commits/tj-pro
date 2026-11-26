class MotionTemplateInfo {
  final String id;
  final String name;
  final String category;
  final List<String> keywordsEn;
  final List<String> keywordsRomanUrdu;
  final List<String> keywordsUrdu;
  final List<String> tags;

  const MotionTemplateInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.keywordsEn,
    required this.keywordsRomanUrdu,
    required this.keywordsUrdu,
    this.tags = const [],
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MotionTemplateInfo &&
            id == other.id &&
            name == other.name &&
            category == other.category &&
            _listEquals(keywordsEn, other.keywordsEn) &&
            _listEquals(keywordsRomanUrdu, other.keywordsRomanUrdu) &&
            _listEquals(keywordsUrdu, other.keywordsUrdu) &&
            _listEquals(tags, other.tags);
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        category,
        Object.hashAll(keywordsEn),
        Object.hashAll(keywordsRomanUrdu),
        Object.hashAll(keywordsUrdu),
        Object.hashAll(tags),
      );
}

class MotionMatch {
  final String templateId;
  final double score;
  final List<String> matchedTerms;

  const MotionMatch({
    required this.templateId,
    required this.score,
    required this.matchedTerms,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MotionMatch &&
            templateId == other.templateId &&
            score == other.score &&
            _listEquals(matchedTerms, other.matchedTerms);
  }

  @override
  int get hashCode => Object.hash(
        templateId,
        score,
        Object.hashAll(matchedTerms),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;

  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }

  return true;
}

class MotionPromptMatcher {
  MotionPromptMatcher._();

  static const Set<int> _removedPunctuation = {
    0x002E, // .
    0x002C, // ,
    0x0021, // !
    0x003F, // ?
    0x003B, // ;
    0x003A, // :
    0x0022, // "
    0x0027, // '
    0x0028, // (
    0x0029, // )
    0x005B, // [
    0x005D, // ]
    0x007B, // {
    0x007D, // }
    0x002D, // -
    0x005F, // _
    0x002F, // /
    0x005C, // \
    0x007C, // |
    0x0040, // @
    0x0023, // #
    0x0024, // $
    0x0025, // %
    0x0026, // &
    0x002A, // *
    0x002B, // +
    0x003D, // =
    0x007E, // ~
    0x0060, // `
  };

  static String _normalize(String input) {
    try {
      final lower = input.toLowerCase();
      final buffer = StringBuffer();

      bool previousWhitespace = true;

      for (final rune in lower.runes) {
        // Remove Arabic diacritics and tatweel.
        if ((rune >= 0x064B && rune <= 0x0652) ||
            rune == 0x0640) {
          continue;
        }

        if (_removedPunctuation.contains(rune)) {
          continue;
        }

        final isWhitespace =
            rune == 0x20 ||
            rune == 0x09 ||
            rune == 0x0A ||
            rune == 0x0D ||
            rune == 0x0B ||
            rune == 0x0C ||
            rune == 0x00A0 ||
            rune == 0x1680 ||
            (rune >= 0x2000 && rune <= 0x200A) ||
            rune == 0x2028 ||
            rune == 0x2029 ||
            rune == 0x202F ||
            rune == 0x205F ||
            rune == 0x3000;

        if (isWhitespace) {
          if (!previousWhitespace) {
            buffer.write(' ');
            previousWhitespace = true;
          }
        } else {
          buffer.writeCharCode(rune);
          previousWhitespace = false;
        }
      }

      return buffer.toString().trim();
    } catch (_) {
      return '';
    }
  }

  static List<String> _tokens(String normalized) {
    if (normalized.isEmpty) return const [];

    return normalized
        .split(' ')
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
  }

  static bool looksLikeUrduScript(String text) {
    try {
      for (final rune in text.runes) {
        if (rune >= 0x0600 && rune <= 0x06FF) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }

    return false;
  }

  static List<MotionMatch> match({
    required String prompt,
    required List<MotionTemplateInfo> catalogue,
    int limit = 6,
  }) {
    try {
      if (limit <= 0 || catalogue.isEmpty) {
        return const [];
      }

      final normalizedPrompt = _normalize(prompt);

      if (normalizedPrompt.isEmpty) {
        return const [];
      }

      final promptTerms = _tokens(normalizedPrompt);

      if (promptTerms.isEmpty) {
        return const [];
      }

      final promptTermSet = promptTerms.toSet();

      final scored = <_ScoredTemplate>[];

      for (var index = 0; index < catalogue.length; index++) {
        final template = catalogue[index];

        final result = _scoreTemplate(
          template: template,
          normalizedPrompt: normalizedPrompt,
          promptTerms: promptTerms,
          promptTermSet: promptTermSet,
        );

        if (result.score >= 0.2) {
          scored.add(
            _ScoredTemplate(
              index: index,
              match: MotionMatch(
                templateId: template.id,
                score: result.score,
                matchedTerms: result.matchedTerms,
              ),
            ),
          );
        }
      }

      // Stable deterministic sorting.
      scored.sort((a, b) {
        final scoreComparison =
            b.match.score.compareTo(a.match.score);

        if (scoreComparison != 0) {
          return scoreComparison;
        }

        return a.index.compareTo(b.index);
      });

      final count =
          scored.length < limit ? scored.length : limit;

      return List<MotionMatch>.unmodifiable(
        scored
            .take(count)
            .map((item) => item.match),
      );
    } catch (_) {
      return const [];
    }
  }

  static List<String> suggestCategories({
    required String prompt,
    required List<MotionTemplateInfo> catalogue,
  }) {
    try {
      final normalizedPrompt = _normalize(prompt);

      if (normalizedPrompt.isEmpty || catalogue.isEmpty) {
        return const [];
      }

      final promptTerms = _tokens(normalizedPrompt);

      if (promptTerms.isEmpty) {
        return const [];
      }

      final promptTermSet = promptTerms.toSet();

      final bestCategoryScores = <String, double>{};
      final categoryOrder = <String>[];

      for (final template in catalogue) {
        final category = template.category.trim();

        if (category.isEmpty) continue;

        final result = _scoreTemplate(
          template: template,
          normalizedPrompt: normalizedPrompt,
          promptTerms: promptTerms,
          promptTermSet: promptTermSet,
        );

        if (result.score <= 0) continue;

        if (!bestCategoryScores.containsKey(category)) {
          bestCategoryScores[category] = result.score;
          categoryOrder.add(category);
        } else if (result.score >
            bestCategoryScores[category]!) {
          bestCategoryScores[category] = result.score;
        }
      }

      categoryOrder.sort((a, b) {
        final comparison =
            bestCategoryScores[b]!.compareTo(
          bestCategoryScores[a]!,
        );

        if (comparison != 0) return comparison;

        return catalogue.indexWhere(
              (template) => template.category.trim() == a,
            ).compareTo(
              catalogue.indexWhere(
                (template) => template.category.trim() == b,
              ),
            );
      });

      return List<String>.unmodifiable(categoryOrder);
    } catch (_) {
      return const [];
    }
  }

  static _TemplateScore _scoreTemplate({
    required MotionTemplateInfo template,
    required String normalizedPrompt,
    required List<String> promptTerms,
    required Set<String> promptTermSet,
  }) {
    double score = 0;

    final matched = <String>{};

    // Three independent keyword lists.
    final keywordLists = [
      template.keywordsEn,
      template.keywordsRomanUrdu,
      template.keywordsUrdu,
    ];

    for (final keywordList in keywordLists) {
      final result = _bestPhraseMatch(
        phrases: keywordList,
        normalizedPrompt: normalizedPrompt,
        promptTerms: promptTerms,
        promptTermSet: promptTermSet,
        fullWeight: 0.55,
        allWeight: 0.4,
        partialWeight: 0.2,
      );

      score += result.score;
      matched.addAll(result.matchedTerms);
    }

    // Template name matching.
    // CHECK #7 FIX: each DISTINCT prompt term earns the name bonus at most
    // once. As received, a duplicated prompt word (e.g. "news news") earned
    // +0.12 twice from a single name term, reaching the +0.24 cap alone.
    final nameTerms = _tokens(_normalize(template.name));

    var nameMatches = 0;
    final countedNameTerms = <String>{};

    for (final term in promptTerms) {
      if (countedNameTerms.contains(term)) continue;
      if (nameTerms.contains(term)) {
        countedNameTerms.add(term);
        score += 0.12;
        matched.add(term);
        nameMatches++;

        if (nameMatches >= 2) break;
      }
    }

    // Category matching.
    final normalizedCategory =
        _normalize(template.category);

    if (normalizedCategory.isNotEmpty &&
        normalizedPrompt.contains(normalizedCategory)) {
      score += 0.15;
    }

    // Tags: half-weight phrase matching.
    final tagResult = _bestPhraseMatch(
      phrases: template.tags,
      normalizedPrompt: normalizedPrompt,
      promptTerms: promptTerms,
      promptTermSet: promptTermSet,
      fullWeight: 0.275,
      allWeight: 0.2,
      partialWeight: 0.1,
    );

    score += tagResult.score;
    matched.addAll(tagResult.matchedTerms);

    // Prefix matching.
    var prefixBonuses = 0;

    final keywordTerms = <String>{};

    for (final list in keywordLists) {
      for (final phrase in list) {
        keywordTerms.addAll(_tokens(_normalize(phrase)));
      }
    }

    // CHECK #7 FIX: each DISTINCT prompt term earns the prefix bonus at
    // most once. As received, a duplicated prompt word (e.g. "break break")
    // earned +0.05 twice against the same keyword term.
    final countedPrefixTerms = <String>{};

    for (final promptTerm in promptTerms) {
      if (promptTerm.length < 4) continue;
      if (countedPrefixTerms.contains(promptTerm)) continue;

      var found = false;

      for (final keywordTerm in keywordTerms) {
        if (keywordTerm == promptTerm) continue;

        if (keywordTerm.startsWith(promptTerm) ||
            promptTerm.startsWith(keywordTerm)) {
          countedPrefixTerms.add(promptTerm);
          score += 0.05;
          matched.add(promptTerm);
          prefixBonuses++;
          found = true;
          break;
        }
      }

      if (found && prefixBonuses >= 2) break;
    }

    final clampedScore = score.clamp(0.0, 1.0).toDouble();

    // Preserve prompt order and remove duplicates.
    final orderedMatches = <String>[];

    for (final term in promptTerms) {
      if (matched.contains(term) &&
          !orderedMatches.contains(term)) {
        orderedMatches.add(term);
      }
    }

    return _TemplateScore(
      score: clampedScore,
      matchedTerms: List<String>.unmodifiable(orderedMatches),
    );
  }

  static _PhraseScore _bestPhraseMatch({
    required List<String> phrases,
    required String normalizedPrompt,
    required List<String> promptTerms,
    required Set<String> promptTermSet,
    required double fullWeight,
    required double allWeight,
    required double partialWeight,
  }) {
    double bestScore = 0;
    Set<String> bestTerms = {};

    for (final rawPhrase in phrases) {
      final phrase = _normalize(rawPhrase);

      if (phrase.isEmpty) continue;

      final phraseTerms = _tokens(phrase);

      if (phraseTerms.isEmpty) continue;

      final matchedPhraseTerms = <String>{};

      for (final term in phraseTerms) {
        if (promptTermSet.contains(term)) {
          matchedPhraseTerms.add(term);
        }
      }

      double phraseScore = 0;

      if (normalizedPrompt.contains(phrase)) {
        phraseScore = fullWeight;
      } else if (matchedPhraseTerms.length ==
          phraseTerms.length) {
        phraseScore = allWeight;
      } else if (phraseTerms.length >= 2 &&
          matchedPhraseTerms.length >=
              (phraseTerms.length + 1) ~/ 2) {
        phraseScore = partialWeight;
      }

      if (phraseScore > bestScore) {
        bestScore = phraseScore;
        bestTerms = matchedPhraseTerms;
      }
    }

    return _PhraseScore(
      score: bestScore,
      matchedTerms: bestTerms,
    );
  }
}

class _PhraseScore {
  final double score;
  final Set<String> matchedTerms;

  const _PhraseScore({
    required this.score,
    required this.matchedTerms,
  });
}

class _TemplateScore {
  final double score;
  final List<String> matchedTerms;

  const _TemplateScore({
    required this.score,
    required this.matchedTerms,
  });
}

class _ScoredTemplate {
  final int index;
  final MotionMatch match;

  const _ScoredTemplate({
    required this.index,
    required this.match,
  });
}
