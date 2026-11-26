import 'package:tj_pro/motion/motion_prompt_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

MotionTemplateInfo tpl({
  required String id,
  String name = 'Generic Pack',
  String category = 'Misc',
  List<String> en = const [],
  List<String> roman = const [],
  List<String> urdu = const [],
  List<String> tags = const [],
}) {
  return MotionTemplateInfo(
    id: id,
    name: name,
    category: category,
    keywordsEn: en,
    keywordsRomanUrdu: roman,
    keywordsUrdu: urdu,
    tags: tags,
  );
}

/// A normal news/logo catalogue, used by several spec examples.
List<MotionTemplateInfo> normalCatalogue() => [
      tpl(
        id: 'breaking_news_intro',
        name: 'Breaking News Intro',
        category: 'News',
        en: ['breaking news', 'news intro'],
        roman: ['breaking news wala intro'],
        urdu: ['بریکنگ نیوز'],
      ),
      tpl(
        id: 'logo_reveal',
        name: 'Logo Reveal',
        category: 'Logos',
        en: ['logo reveal', 'logo intro'],
        roman: ['logo intro', 'logo wala'],
        urdu: ['لوگو انٹرو'],
      ),
      tpl(
        id: 'sports_sting',
        name: 'Sports Sting',
        category: 'Sports',
        en: ['sports sting', 'cricket intro'],
        roman: ['khel ka intro'],
        urdu: ['کھیل'],
      ),
      tpl(
        id: 'weather_alert',
        name: 'Weather Alert',
        category: 'Weather',
        en: ['weather alert', 'rain update'],
        roman: ['mausam ki khabar'],
        urdu: ['موسم'],
      ),
    ];

void main() {
  group('SPEC EXAMPLES (lafz-ba-lafz)', () {
    test('(a) "breaking news intro" -> Breaking News Intro top, >= 0.9', () {
      final results = MotionPromptMatcher.match(
        prompt: 'breaking news intro',
        catalogue: normalCatalogue(),
      );
      expect(results, isNotEmpty);
      expect(results.first.templateId, 'breaking_news_intro');
      expect(results.first.score, greaterThanOrEqualTo(0.9));
      // Full arithmetic against this catalogue entry: keywordsEn best
      // phrase 0.55 + keywordsRomanUrdu partial (3 of 4 terms) 0.20
      // + name 2 terms capped 0.24 + category "news" contained 0.15
      // = 1.14 -> clamped to 1.0. (Test (a2) pins the clean 0.79 for
      // name + keywordsEn alone, which is all the spec example names.)
      expect(results.first.score, closeTo(1.0, 1e-9));
    });

    test('(a2) name+keywords only (no category hit) pins 0.79', () {
      final results = MotionPromptMatcher.match(
        prompt: 'breaking news intro',
        catalogue: [
          tpl(
            id: 'bni',
            name: 'Breaking News Intro',
            category: 'Studio', // not contained in the prompt
            en: ['breaking news', 'news intro'],
          ),
        ],
      );
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.79, 1e-9)); // 0.55 + 0.24
    });

    test('(b) Roman Urdu "logo wala intro chahiye" matches, >= 0.4', () {
      final results = MotionPromptMatcher.match(
        prompt: 'logo wala intro chahiye',
        catalogue: normalCatalogue(),
      );
      expect(results, isNotEmpty);
      expect(results.first.templateId, 'logo_reveal');
      expect(results.first.score, greaterThanOrEqualTo(0.4));
    });

    test('(c) Urdu script prompt matches keywordsUrdu template', () {
      final results = MotionPromptMatcher.match(
        prompt: 'لوگو انٹرو',
        catalogue: normalCatalogue(),
      );
      expect(results, isNotEmpty);
      expect(results.first.templateId, 'logo_reveal');
      expect(results.first.score, greaterThanOrEqualTo(0.55));
    });

    test('(d) "underwater banana dance" -> empty (no fake matches)', () {
      final results = MotionPromptMatcher.match(
        prompt: 'underwater banana dance',
        catalogue: normalCatalogue(),
      );
      expect(results, isEmpty);
    });

    test('(e) empty prompt -> empty; empty catalogue -> empty', () {
      expect(
        MotionPromptMatcher.match(prompt: '', catalogue: normalCatalogue()),
        isEmpty,
      );
      expect(
        MotionPromptMatcher.match(prompt: '   \t\n ', catalogue: normalCatalogue()),
        isEmpty,
      );
      expect(
        MotionPromptMatcher.match(prompt: 'breaking news', catalogue: const []),
        isEmpty,
      );
    });
  });

  group('value equality', () {
    test('MotionTemplateInfo ==/hashCode incl. list equality', () {
      final a = tpl(id: 'x', en: ['a', 'b'], tags: ['t']);
      final b = tpl(id: 'x', en: ['a', 'b'], tags: ['t']);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(tpl(id: 'x', en: ['a', 'c'], tags: ['t']))));
      expect(a, isNot(equals(tpl(id: 'x', en: ['a', 'b'], tags: ['u']))));
      expect(a, isNot(equals(tpl(id: 'y', en: ['a', 'b'], tags: ['t']))));
    });

    test('tags default == explicit empty list', () {
      const a = MotionTemplateInfo(
        id: 'x',
        name: 'n',
        category: 'c',
        keywordsEn: [],
        keywordsRomanUrdu: [],
        keywordsUrdu: [],
      );
      final b = tpl(id: 'x', name: 'n', category: 'c');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('MotionMatch ==/hashCode incl. matchedTerms list', () {
      const a = MotionMatch(templateId: 'x', score: 0.5, matchedTerms: ['a']);
      const b = MotionMatch(templateId: 'x', score: 0.5, matchedTerms: ['a']);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(equals(
          const MotionMatch(templateId: 'x', score: 0.5, matchedTerms: ['b']),
        )),
      );
    });

    test('const constructor is usable', () {
      const info = MotionTemplateInfo(
        id: 'c',
        name: 'Const',
        category: 'Misc',
        keywordsEn: ['x'],
        keywordsRomanUrdu: [],
        keywordsUrdu: [],
        tags: ['y'],
      );
      expect(info.id, 'c');
    });
  });

  group('normalization', () {
    test('punctuation removed, case folded, whitespace collapsed', () {
      final results = MotionPromptMatcher.match(
        prompt: '  BREAKING---News!!   intro\t\n',
        catalogue: normalCatalogue(),
      );
      expect(results, isNotEmpty);
      expect(results.first.templateId, 'breaking_news_intro');
    });

    test('Urdu diacritics (fatha/sukun) in prompt still match plain keyword',
        () {
      // ل + fatha + و + sukun + گو  -> normalized لوگو
      final withDiacritics = 'ل\u064Eو\u0652گو انٹرو';
      final results = MotionPromptMatcher.match(
        prompt: withDiacritics,
        catalogue: normalCatalogue(),
      );
      expect(results, isNotEmpty);
      expect(results.first.templateId, 'logo_reveal');
    });

    test('Urdu tatweel in prompt still matches plain keyword', () {
      final withTatweel = 'لو\u0640گو انٹرو';
      final results = MotionPromptMatcher.match(
        prompt: withTatweel,
        catalogue: normalCatalogue(),
      );
      expect(results, isNotEmpty);
      expect(results.first.templateId, 'logo_reveal');
    });

    test('diacritics inside the KEYWORD are stripped too', () {
      final results = MotionPromptMatcher.match(
        prompt: 'لوگو انٹرو',
        catalogue: [
          tpl(id: 'u', urdu: ['ل\u064Eوگو انٹرو']),
        ],
      );
      expect(results, hasLength(1));
    });
  });

  group('scoring rules', () {
    test('threshold: exactly 0.2 (partial phrase only) is included', () {
      final results = MotionPromptMatcher.match(
        prompt: 'alpha beta',
        catalogue: [tpl(id: 'p', en: ['alpha beta gamma'])],
      );
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.2, 1e-9));
    });

    test('threshold: 0.15 (category only) is excluded', () {
      final results = MotionPromptMatcher.match(
        prompt: 'news bulletin today',
        catalogue: [
          tpl(id: 'c', name: 'Weather Update', category: 'News', en: ['weather update']),
        ],
      );
      expect(results, isEmpty);
    });

    test('threshold: 0.12 (single name term only) is excluded', () {
      final results = MotionPromptMatcher.match(
        prompt: 'zephyr winds',
        catalogue: [tpl(id: 'n', name: 'Zephyr Pack', en: ['mountain storm'])],
      );
      expect(results, isEmpty);
    });

    test('all-terms (non-substring) phrase scores 0.4', () {
      final results = MotionPromptMatcher.match(
        prompt: 'intro of the breaking news kind',
        catalogue: [
          tpl(id: 'at', name: 'Promo Pack', en: ['breaking intro']),
        ],
      );
      // "breaking intro" is not a substring, but both terms are present.
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.4, 1e-9));
    });

    test('only the single best phrase per keyword list counts', () {
      final results = MotionPromptMatcher.match(
        prompt: 'breaking news intro',
        catalogue: [
          tpl(
            id: 'bp',
            name: 'Studio Pack',
            en: ['breaking news', 'news intro'], // both substring-match
          ),
        ],
      );
      // NOT 0.55 + 0.55; only the best phrase of the list: 0.55.
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.55, 1e-9));
    });

    test('three keyword lists each contribute their own best phrase', () {
      final results = MotionPromptMatcher.match(
        prompt: 'breaking news logo wala لوگو انٹرو',
        catalogue: [
          tpl(
            id: 'tri',
            name: 'Studio Pack',
            en: ['breaking news'],
            roman: ['logo wala'],
            urdu: ['لوگو انٹرو'],
          ),
        ],
      );
      // 0.55 x 3 = 1.65 -> clamped to 1.0.
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(1.0, 1e-9));
    });

    test('tags count at half weight, best tag only', () {
      final results = MotionPromptMatcher.match(
        prompt: 'alpha beta',
        catalogue: [tpl(id: 'tg', tags: ['alpha beta', 'alpha'])],
      );
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.275, 1e-9));
    });

    test('prefix bonus: "break" earns +0.05 against keyword "breaking"', () {
      final results = MotionPromptMatcher.match(
        prompt: 'break news',
        catalogue: [tpl(id: 'px', name: 'Promo Pack', en: ['breaking news'])],
      );
      // partial phrase 0.2 (news) + prefix 0.05 (break->breaking) = 0.25
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.25, 1e-9));
      expect(results.single.matchedTerms, containsAll(['break', 'news']));
    });

    test('prefix bonus: reverse direction (prompt term starts with keyword term)',
        () {
      final results = MotionPromptMatcher.match(
        prompt: 'breakingx news',
        catalogue: [tpl(id: 'px2', name: 'Promo Pack', en: ['breaking news'])],
      );
      // partial phrase 0.2 (news) + prefix 0.05 (breakingx starts with breaking)
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.25, 1e-9));
    });

    test('prefix bonus: short prompt terms (< 4) earn nothing', () {
      final results = MotionPromptMatcher.match(
        prompt: 'new news',
        catalogue: [tpl(id: 'px3', name: 'Promo Pack', en: ['breaking news'])],
      );
      // phrase: "news" term present -> 1 of 2 terms -> partial 0.2.
      // "new" (len 3) must NOT earn a prefix bonus against "news".
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.2, 1e-9));
    });

    test('score is clamped to 1.0', () {
      final results = MotionPromptMatcher.match(
        prompt: 'breaking news intro',
        catalogue: normalCatalogue(),
        limit: 10,
      );
      for (final r in results) {
        expect(r.score, lessThanOrEqualTo(1.0));
        expect(r.score, greaterThanOrEqualTo(0.2));
      }
    });
  });

  group('duplicate prompt terms (bug hunt)', () {
    test('same name term typed twice must NOT earn the name bonus twice', () {
      // Prompt repeats "news". Distinct-term reading: name +0.12 once,
      // category "today" +0.15 -> 0.27. Buggy reading: +0.12 twice -> 0.39.
      final results = MotionPromptMatcher.match(
        prompt: 'news news today',
        catalogue: [tpl(id: 'dup', name: 'News', category: 'Today')],
      );
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.27, 1e-9));
    });

    test('duplicated single name term alone stays below threshold', () {
      // Distinct reading: 0.12 -> excluded. Buggy reading: 0.24 -> included.
      final results = MotionPromptMatcher.match(
        prompt: 'news news',
        catalogue: [tpl(id: 'dup2', name: 'Daily News')],
      );
      expect(results, isEmpty);
    });

    test('same prompt term must NOT earn the prefix bonus twice', () {
      // partial phrase 0.2 (news) + prefix once 0.05 = 0.25.
      // Buggy reading: prefix twice = 0.30.
      final results = MotionPromptMatcher.match(
        prompt: 'break break news',
        catalogue: [tpl(id: 'dup3', name: 'Promo Pack', en: ['breaking news'])],
      );
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.25, 1e-9));
    });
  });

  group('single-term keyword substring effect (spec-literal, pinned)', () {
    test('keyword "news" fires inside prompt word "newsletter"', () {
      // The spec defines the full-phrase rule as raw substring containment,
      // so a 1-term keyword matches inside a longer unrelated word (+0.55),
      // and the same long prompt term ALSO earns the reverse prefix bonus
      // against the keyword term "news" (+0.05) -> 0.60 total.
      // This test PINS that spec-literal behaviour (documented effect).
      final results = MotionPromptMatcher.match(
        prompt: 'newsletter',
        catalogue: [tpl(id: 'sub', name: 'Daily Bulletin', en: ['news'])],
      );
      expect(results, hasLength(1));
      expect(results.single.score, closeTo(0.60, 1e-9));
    });
  });

  group('limit', () {
    List<MotionTemplateInfo> many() => [
          for (var i = 0; i < 7; i++)
            tpl(id: 'm$i', name: 'News Pack $i', en: ['breaking news']),
        ];

    test('limit 2 returns at most 2', () {
      final results = MotionPromptMatcher.match(
        prompt: 'breaking news',
        catalogue: many(),
        limit: 2,
      );
      expect(results, hasLength(2));
    });

    test('default limit is 6', () {
      final results = MotionPromptMatcher.match(
        prompt: 'breaking news',
        catalogue: many(),
      );
      expect(results, hasLength(6));
    });

    test('limit 0 and negative limit return empty', () {
      expect(
        MotionPromptMatcher.match(prompt: 'breaking news', catalogue: many(), limit: 0),
        isEmpty,
      );
      expect(
        MotionPromptMatcher.match(prompt: 'breaking news', catalogue: many(), limit: -3),
        isEmpty,
      );
    });
  });

  group('ordering + determinism', () {
    test('ties keep catalogue order', () {
      final cat = [
        tpl(id: 'first', name: 'News One', en: ['breaking news']),
        tpl(id: 'second', name: 'News Two', en: ['breaking news']),
        tpl(id: 'third', name: 'News Three', en: ['breaking news']),
      ];
      final results = MotionPromptMatcher.match(prompt: 'breaking news', catalogue: cat);
      expect(results.map((r) => r.templateId).toList(),
          ['first', 'second', 'third']);
    });

    test('higher score beats catalogue order', () {
      final cat = [
        // partial phrase only -> 0.2
        tpl(id: 'weak', name: 'Promo', en: ['breaking news flash']),
        // full substring phrase -> 0.55
        tpl(id: 'strong', name: 'Promo', en: ['breaking news']),
      ];
      final results = MotionPromptMatcher.match(prompt: 'breaking news', catalogue: cat);
      expect(results.first.templateId, 'strong');
    });

    test('50 identical runs produce identical results', () {
      final cat = normalCatalogue();
      final first = MotionPromptMatcher.match(prompt: 'logo wala intro', catalogue: cat);
      for (var i = 0; i < 50; i++) {
        final again = MotionPromptMatcher.match(prompt: 'logo wala intro', catalogue: cat);
        expect(again, equals(first));
      }
    });

    test('matchedTerms are in prompt order with no duplicates', () {
      final results = MotionPromptMatcher.match(
        prompt: 'intro breaking news intro',
        catalogue: [
          tpl(id: 'mt', name: 'News Intro', en: ['breaking news']),
        ],
      );
      expect(results, hasLength(1));
      expect(results.single.matchedTerms, ['intro', 'breaking', 'news']);
    });
  });

  group('suggestCategories', () {
    test('orders by best template score, distinct categories', () {
      final cats = MotionPromptMatcher.suggestCategories(
        prompt: 'breaking news intro',
        catalogue: normalCatalogue(),
      );
      expect(cats, isNotEmpty);
      expect(cats.first, 'News');
      expect(cats.toSet().length, cats.length); // distinct
    });

    test('includes categories scoring > 0 but below the 0.2 match threshold',
        () {
      // Category-only hit scores 0.15: no match() result, but the category
      // must still be suggested (that is the fallback's whole purpose).
      final cat = [
        tpl(id: 'c', name: 'Weather Update', category: 'News', en: ['weather update']),
      ];
      expect(MotionPromptMatcher.match(prompt: 'news today', catalogue: cat), isEmpty);
      expect(
        MotionPromptMatcher.suggestCategories(prompt: 'news today', catalogue: cat),
        ['News'],
      );
    });

    test('tie between categories -> first appearance in catalogue wins', () {
      final cat = [
        tpl(id: 'a', name: 'Promo A', category: 'Zeta', en: ['breaking news']),
        tpl(id: 'b', name: 'Promo B', category: 'Alpha', en: ['breaking news']),
      ];
      final cats = MotionPromptMatcher.suggestCategories(
        prompt: 'breaking news',
        catalogue: cat,
      );
      expect(cats, ['Zeta', 'Alpha']);
    });

    test('empty when nothing scores; empty prompt/catalogue safe', () {
      expect(
        MotionPromptMatcher.suggestCategories(
            prompt: 'underwater banana dance', catalogue: normalCatalogue()),
        isEmpty,
      );
      expect(
        MotionPromptMatcher.suggestCategories(prompt: '', catalogue: normalCatalogue()),
        isEmpty,
      );
      expect(
        MotionPromptMatcher.suggestCategories(prompt: 'news', catalogue: const []),
        isEmpty,
      );
    });

    test('categories differing only by case are kept distinct (pinned)', () {
      final cat = [
        tpl(id: 'a', name: 'Promo A', category: 'News', en: ['breaking news']),
        tpl(id: 'b', name: 'Promo B', category: 'news', en: ['breaking news']),
      ];
      final cats = MotionPromptMatcher.suggestCategories(
        prompt: 'breaking news',
        catalogue: cat,
      );
      expect(cats, containsAll(['News', 'news']));
      expect(cats, hasLength(2));
    });
  });

  group('looksLikeUrduScript', () {
    test('Urdu/Arabic true, Latin false, mixed true, empty false', () {
      expect(MotionPromptMatcher.looksLikeUrduScript('لوگو انٹرو'), isTrue);
      expect(MotionPromptMatcher.looksLikeUrduScript('سلام'), isTrue);
      expect(MotionPromptMatcher.looksLikeUrduScript('hello world'), isFalse);
      expect(MotionPromptMatcher.looksLikeUrduScript('hello لوگو'), isTrue);
      expect(MotionPromptMatcher.looksLikeUrduScript(''), isFalse);
      expect(MotionPromptMatcher.looksLikeUrduScript('12345'), isFalse);
      expect(MotionPromptMatcher.looksLikeUrduScript('١٢٣'), isTrue);
    });
  });

  group('robustness (never throws)', () {
    test('weird unicode, emoji, punctuation-only, lone diacritics', () {
      final cat = normalCatalogue();
      expect(MotionPromptMatcher.match(prompt: '🎉🎉🎉', catalogue: cat), isEmpty);
      expect(MotionPromptMatcher.match(prompt: '!!!???...', catalogue: cat), isEmpty);
      expect(MotionPromptMatcher.match(prompt: '\u064E\u0652', catalogue: cat), isEmpty);
      expect(
        MotionPromptMatcher.match(prompt: 'news 🎉 breaking', catalogue: cat),
        isNotEmpty,
      );
      expect(MotionPromptMatcher.looksLikeUrduScript('🎉'), isFalse);
    });

    test('very long prompt does not throw', () {
      final long = List.filled(1000, 'news').join(' ');
      final results = MotionPromptMatcher.match(prompt: long, catalogue: normalCatalogue());
      expect(results, isNotEmpty);
    });

    test('templates with empty/garbage fields do not throw', () {
      final cat = [
        tpl(id: 'g', name: '', category: '', en: ['', ' '], roman: [''], urdu: [], tags: ['']),
      ];
      expect(MotionPromptMatcher.match(prompt: 'news', catalogue: cat), isEmpty);
      expect(MotionPromptMatcher.suggestCategories(prompt: 'news', catalogue: cat), isEmpty);
    });
  });

  group('performance sanity', () {
    test('100 templates x 40-term prompt is fast', () {
      final cat = <MotionTemplateInfo>[
        for (var i = 0; i < 100; i++)
          tpl(
            id: 't$i',
            name: 'Template Number $i News',
            category: 'Cat${i % 10}',
            en: ['breaking news', 'template $i special', 'common phrase here'],
            roman: ['logo wala intro', 'khabar $i'],
            urdu: ['لوگو انٹرو', 'خبر'],
            tags: ['tag$i', 'news'],
          ),
      ];
      final prompt = List.generate(40, (i) => 'term$i news logo breaking').join(' ');
      final sw = Stopwatch()..start();
      final results = MotionPromptMatcher.match(prompt: prompt, catalogue: cat, limit: 10);
      final cats = MotionPromptMatcher.suggestCategories(prompt: prompt, catalogue: cat);
      sw.stop();
      // ignore: avoid_print
      print('perf: 100 templates x 40 terms took ${sw.elapsedMilliseconds} ms');
      expect(results, isNotEmpty);
      expect(cats, isNotEmpty);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });
  });
}
