import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/lang.dart';

void main() {
  test('normalizes player language tags', () {
    expect(normalizeLang('ara'), 'ar');
    expect(normalizeLang('AR'), 'ar');
    expect(normalizeLang('ar-EG'), 'ar');
    expect(normalizeLang('pob'), 'pt-BR');
    expect(normalizeLang('und'), isNull);
    expect(normalizeLang(null), isNull);
  });

  test('compares and names', () {
    expect(sameLang('ara', 'ar'), isTrue);
    expect(sameLang('pt-BR', 'por'), isTrue);
    expect(sameLang('eng', 'ar'), isFalse);
    expect(langName('ger'), 'German');
    expect(mpvLangCodes('ar'), containsAll(['ar', 'ara']));
  });
}
