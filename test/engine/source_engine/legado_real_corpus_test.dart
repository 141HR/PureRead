import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/engine/source_engine/legado_compat/legado_compat.dart';
import 'package:pureread/engine/source_engine/source_registry.dart';
import 'package:pureread/infrastructure/network/source_http_client.dart';

const String _corpusFile1 = r'd:\QQ\Downloads\超级精品书源1031个10月10日.json';
const String _corpusFile2 = r'd:\QQ\Downloads\精品书源合集.json';

void main() {
  final hasCorpus1 = File(_corpusFile1).existsSync();
  final hasCorpus2 = File(_corpusFile2).existsSync();

  test(
    'parses and classifies all 2,693 real Legado sources with 0 crashes',
    () async {
      if (!hasCorpus1 || !hasCorpus2) {
        markTestSkipped(
          'Real Legado corpus files not present in d:\\QQ\\Downloads; skipping on CI.',
        );
        return;
      }

      final raw1 = await File(_corpusFile1).readAsString();
      final raw2 = await File(_corpusFile2).readAsString();

      final res1 = await LegadoSourceParser.parseBatch(raw1, useIsolate: true);
      final res2 = await LegadoSourceParser.parseBatch(raw2, useIsolate: true);

      expect(res1.parseErrors, isEmpty);
      expect(res2.parseErrors, isEmpty);
      expect(res1.totalCount, 1031);
      expect(res2.totalCount, 1662);
      expect(res1.totalCount + res2.totalCount, 2693);

      // File 1 has 1,031 text sources; File 2 has 1,534 text + 128 non-text.
      expect(res1.unsupportedTypeCount, 0);
      expect(res2.unsupportedTypeCount, 128);

      // Verify fragment-tagged and non-HTTP URLs classify cleanly without crash.
      expect(res1.fragmentTaggedCount, greaterThan(0));
      expect(res2.malformedBaseUrlCount, greaterThan(0));

      // Verify BookProviderFactory instantiates every supported source cleanly.
      final httpClient = SourceHttpClient();
      try {
        final factory = BookProviderFactory(httpClient: httpClient);
        final allSupported = <LegadoParsedSource>[
          ...res1.items.where((i) => i.isSupported),
          ...res2.items.where((i) => i.isSupported),
        ];
        expect(allSupported.length, greaterThan(2000));
        for (final item in allSupported) {
          final provider = factory.createProvider(item.domainSource);
          expect(provider.providerId, item.domainSource.id);
        }
      } finally {
        httpClient.close();
      }
    },
  );
}
