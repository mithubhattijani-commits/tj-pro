/// MOTION GRAPHICS STUDIO — prompt-matching keywords (Build
/// M4, v1.26.0).
///
/// Search metadata lives APART from the template scenes on
/// purpose (CHECK #7 integration note): scene data is geometry
/// and timing; keywords are words. Repricing a template never
/// touches this file, and improving search never touches a
/// scene.
///
/// Every [MotionTemplates.all] id MUST have an entry here —
/// a template without keywords can never be found by the
/// prompt matcher (only by browsing), and a guard test fails
/// the build if an entry goes missing.
///
/// Keyword-writing rule (from the CHECK #7 findings): prefer
/// TWO-WORD phrases ('breaking news', 'logo intro'). The
/// matcher's phrase rule is a raw substring, so a one-word
/// keyword fires inside unrelated words too ('news' inside
/// 'newsletter'); a single word is used only where the word
/// alone is unambiguous ('countdown', 'subscribe').
library;

import 'motion_my_templates.dart';
import 'motion_prompt_matcher.dart';
import 'motion_templates.dart';

/// One template's search words, per language, plus tags
/// (half-weight in the matcher).
class MotionKeywords {
  const MotionKeywords({
    this.en = const [],
    this.roman = const [],
    this.urdu = const [],
    this.tags = const [],
  });

  final List<String> en;
  final List<String> roman;
  final List<String> urdu;
  final List<String> tags;
}

/// The keyword table — one entry per template id in
/// [MotionTemplates.all] (guard-tested).
const Map<String, MotionKeywords> kMotionTemplateKeywords = {
  'kinetic_headline': MotionKeywords(
    en: ['kinetic headline', 'moving headline', 'animated title'],
    roman: ['chalti headline', 'bara title'],
    urdu: ['بڑی ہیڈ لائن', 'حرکت والی سرخی'],
    tags: ['title', 'headline'],
  ),
  'typewriter_title': MotionKeywords(
    en: ['typewriter title', 'typing text', 'typed title'],
    roman: ['typewriter wala title', 'likhai wala title'],
    urdu: ['ٹائپ رائٹر ٹائٹل', 'لکھائی والا عنوان'],
    tags: ['title', 'typing'],
  ),
  'zoom_title': MotionKeywords(
    en: ['zoom title', 'big title', 'zooming text'],
    roman: ['zoom title', 'bara title'],
    urdu: ['زوم ٹائٹل', 'بڑا عنوان'],
    tags: ['title', 'zoom'],
  ),
  'logo_reveal': MotionKeywords(
    en: ['logo reveal', 'logo intro', 'logo animation'],
    roman: ['logo intro', 'logo wala'],
    urdu: ['لوگو انٹرو', 'لوگو ریویل'],
    tags: ['logo', 'intro'],
  ),
  'logo_pop_shine': MotionKeywords(
    en: ['logo pop', 'logo shine', 'shiny logo'],
    roman: ['logo pop', 'chamakta logo'],
    urdu: ['لوگو پاپ', 'چمکتا لوگو'],
    tags: ['logo'],
  ),
  'naam_strip_classic': MotionKeywords(
    en: ['name strip', 'lower third', 'naam strip'],
    roman: ['naam wali strip', 'naam strip'],
    urdu: ['نام کی پٹی', 'نام اسٹرپ'],
    tags: ['naam', 'strip', 'lower third'],
  ),
  'naam_strip_glass': MotionKeywords(
    en: ['glass name strip', 'premium name strip', 'naam strip'],
    roman: ['glass naam strip', 'sheshay wali strip'],
    urdu: ['شیشہ نام پٹی', 'نام اسٹرپ'],
    tags: ['naam', 'strip', 'glass'],
  ),
  'channel_intro': MotionKeywords(
    en: ['channel intro', 'intro video', 'channel opening'],
    roman: ['channel ka intro', 'intro wala'],
    urdu: ['چینل انٹرو', 'چینل کا آغاز'],
    tags: ['intro', 'channel'],
  ),
  'thanks_outro': MotionKeywords(
    en: ['thanks outro', 'thank you ending', 'video outro'],
    roman: ['shukriya wala end', 'akhir wala'],
    urdu: ['شکریہ آؤٹرو', 'اختتامی ویڈیو'],
    tags: ['outro', 'thanks'],
  ),
  'points_list': MotionKeywords(
    en: ['points list', 'numbered points', 'top points'],
    roman: ['points wali list', 'number wale points'],
    urdu: ['نکات کی فہرست', 'اہم نکات'],
    tags: ['points', 'list'],
  ),
  'points_cards': MotionKeywords(
    en: ['points cards', 'point cards', 'key points'],
    roman: ['points wale cards', 'cards wali list'],
    urdu: ['نکات کارڈز', 'اہم نکات'],
    tags: ['points', 'cards'],
  ),
  'counter_ginti': MotionKeywords(
    en: ['counter', 'number counter', 'ginti counter'],
    roman: ['ginti wala counter', 'number ginna'],
    urdu: ['گنتی کاؤنٹر', 'نمبر کاؤنٹر'],
    tags: ['counter', 'numbers'],
  ),
  'chart_bars': MotionKeywords(
    en: ['chart bars', 'bar chart', 'sales chart'],
    roman: ['chart wale bars', 'graph wala'],
    urdu: ['چارٹ بارز', 'گراف چارٹ'],
    tags: ['chart', 'bars'],
  ),
  'rate_ticker': MotionKeywords(
    en: ['rate ticker', 'gold rate', 'rates today'],
    roman: ['rate wala ticker', 'sona rate', 'aaj ke rates'],
    urdu: ['ریٹ ٹکر', 'سونے کا ریٹ', 'آج کے ریٹس'],
    tags: ['rates', 'ticker', 'gold'],
  ),
  'subscribe_pop': MotionKeywords(
    en: ['subscribe button', 'subscribe pop', 'subscribe animation'],
    roman: ['subscribe wala button', 'subscribe karwao'],
    urdu: ['سبسکرائب بٹن', 'سبسکرائب پاپ'],
    tags: ['subscribe'],
  ),
  'social_post_card': MotionKeywords(
    en: ['social post', 'post card', 'social card'],
    roman: ['social post card', 'post wala card'],
    urdu: ['سوشل پوسٹ کارڈ', 'پوسٹ کارڈ'],
    tags: ['social', 'post', 'card'],
  ),
  'quote_card': MotionKeywords(
    en: ['quote card', 'urdu quote', 'quote design'],
    roman: ['quote wala card', 'aqwal card'],
    urdu: ['اقوال کارڈ', 'قول کارڈ'],
    tags: ['quote', 'card'],
  ),
  'countdown_3_2_1': MotionKeywords(
    en: ['countdown', 'count down', 'countdown timer'],
    roman: ['countdown wala', 'ulti ginti'],
    urdu: ['الٹی گنتی', 'کاؤنٹ ڈاؤن'],
    tags: ['countdown'],
  ),
  'highlight_mark': MotionKeywords(
    en: ['highlight circle', 'look here', 'marker circle'],
    roman: ['nishan wala circle', 'highlight wala'],
    urdu: ['نشانی دائرہ', 'ہائی لائٹ دائرہ'],
    tags: ['highlight', 'effects'],
  ),
  'breaking_news_intro': MotionKeywords(
    en: ['breaking news', 'news intro', 'breaking intro'],
    roman: ['breaking news wala intro', 'taza khabar'],
    urdu: ['بریکنگ نیوز', 'تازہ خبر'],
    tags: ['intro', 'news'],
  ),
  'live_news_intro': MotionKeywords(
    en: ['live intro', 'live news', 'live broadcast'],
    roman: ['live wala intro', 'live khabar'],
    urdu: ['لائیو انٹرو', 'براہ راست'],
    tags: ['live', 'news', 'intro'],
  ),
  'headline_lower_third': MotionKeywords(
    en: ['lower third', 'headline strip', 'news lower third'],
    roman: ['neeche wali patti', 'headline wali strip'],
    urdu: ['لوئر تھرڈ', 'سرخی کی پٹی'],
    tags: ['news', 'lower third', 'strip'],
  ),
  'reporter_name_strip': MotionKeywords(
    en: ['reporter strip', 'reporter name', 'mic strip'],
    roman: ['reporter ki strip', 'numainda naam'],
    urdu: ['رپورٹر پٹی', 'نمائندہ نام پٹی'],
    tags: ['news', 'naam', 'reporter'],
  ),
  'channel_logo_reveal_news': MotionKeywords(
    en: ['news logo reveal', 'channel logo', 'logo reveal'],
    roman: ['news logo intro', 'channel logo wala'],
    urdu: ['نیوز لوگو انٹرو', 'چینل لوگو'],
    tags: ['logo', 'news'],
  ),
  'news_ticker': MotionKeywords(
    en: ['news ticker', 'headline ticker', 'scrolling ticker'],
    roman: ['news wala ticker', 'chalti khabar patti'],
    urdu: ['نیوز ٹکر', 'خبری پٹی'],
    tags: ['ticker', 'news'],
  ),
  'weather_forecast_card': MotionKeywords(
    en: ['weather card', 'weather forecast', 'forecast card'],
    roman: ['mausam wala card', 'weather wala'],
    urdu: ['موسم کارڈ', 'موسم کی پیشگوئی'],
    tags: ['weather', 'news', 'card'],
  ),
  'election_results_bars': MotionKeywords(
    en: ['election results', 'results chart', 'election bars'],
    roman: ['election nataij', 'intikhab results'],
    urdu: ['انتخابی نتائج', 'الیکشن رزلٹ'],
    tags: ['election', 'news', 'chart'],
  ),
  'news_countdown': MotionKeywords(
    en: ['news countdown', 'bulletin countdown', 'starting soon'],
    roman: ['news countdown', 'bulletin shuru'],
    urdu: ['نیوز کاؤنٹ ڈاؤن', 'بلیٹن آغاز'],
    tags: ['countdown', 'news'],
  ),
  'location_name_graphic': MotionKeywords(
    en: ['location graphic', 'place name', 'location pin'],
    roman: ['jagah ka naam', 'location wala'],
    urdu: ['مقام کا نام', 'جگہ کی پٹی'],
    tags: ['location', 'news'],
  ),
  'exclusive_animation': MotionKeywords(
    en: ['exclusive', 'exclusive animation', 'exclusive news'],
    roman: ['exclusive wala', 'khas khabar'],
    urdu: ['ایکسکلوسو', 'خاص خبر'],
    tags: ['exclusive', 'news'],
  ),
  'special_report_intro': MotionKeywords(
    en: ['special report', 'report intro', 'special intro'],
    roman: ['special report wala', 'khas report'],
    urdu: ['خصوصی رپورٹ', 'اسپیشل رپورٹ'],
    tags: ['report', 'news', 'intro'],
  ),
  'news_bulletin_opening': MotionKeywords(
    en: ['bulletin opening', 'news bulletin', 'bulletin intro'],
    roman: ['bulletin ka aghaz', 'bulletin intro'],
    urdu: ['بلیٹن آغاز', 'خبری بلیٹن'],
    tags: ['bulletin', 'news', 'intro'],
  ),
  'social_media_news_card': MotionKeywords(
    en: ['social news card', 'news card', 'social media news'],
    roman: ['social news card', 'khabar wala card'],
    urdu: ['سوشل نیوز کارڈ', 'خبر کارڈ'],
    tags: ['social', 'news', 'card'],
  ),
  'headline_flash': MotionKeywords(
    en: ['headline flash', 'flash news', 'short headline'],
    roman: ['flash khabar', 'chhoti khabar'],
    urdu: ['فلیش خبر', 'چھوٹی خبر'],
    tags: ['flash', 'news', 'headline'],
  ),
};

/// Adapter (CHECK #7 note §1): a registry template as matcher
/// input. The category is the DISPLAY LABEL, not the key —
/// the matcher normalizes before comparing, so multi-word
/// labels ('Naam Strip', 'Ginti / Charts') can match a prompt.
MotionTemplateInfo motionInfoFor(MotionTemplate t) {
  final kw = kMotionTemplateKeywords[t.id] ?? const MotionKeywords();
  return MotionTemplateInfo(
    id: t.id,
    name: t.name,
    category: MotionCategories.labels[t.category] ?? t.category,
    keywordsEn: kw.en,
    keywordsRomanUrdu: kw.roman,
    keywordsUrdu: kw.urdu,
    tags: kw.tags,
  );
}

/// A saved My Template as matcher input: it has only a name,
/// so it matches on name terms alone (the note's §1 rule) —
/// still enough to find it by typing its name.
MotionTemplateInfo motionInfoForSaved(MotionMyTemplate saved) {
  return MotionTemplateInfo(
    id: 'mine:${saved.id}',
    name: saved.name,
    category:
        MotionCategories.labels[saved.category] ?? saved.category,
    keywordsEn: const [],
    keywordsRomanUrdu: const [],
    keywordsUrdu: const [],
    tags: const [],
  );
}

/// The full searchable catalogue: every built-in template
/// (with keywords) plus the user's saved templates (name-only).
/// Built fresh per search — at this size the cost is
/// negligible (CHECK #7 measured ~83 ms for 100 templates × a
/// 160-term prompt; real prompts are far smaller).
List<MotionTemplateInfo> motionCatalogue({
  List<MotionMyTemplate> mine = const [],
}) {
  return [
    for (final t in MotionTemplates.all) motionInfoFor(t),
    for (final s in mine) motionInfoForSaved(s),
  ];
}
