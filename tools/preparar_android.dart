// Completa o android/app/build.gradle(.kts) gerado pelo "flutter create" com:
//   - o ID do app na Play Store (applicationId)
//   - versão mínima do Android
//   - assinatura de release usando android/key.properties (se existir)
//
// Uso:  dart run tools/preparar_android.dart [id.do.app]
// Exemplo: dart run tools/preparar_android.dart br.com.seunome.pontegt1
import 'dart:io';

const marker = '// --- Ponte GT-1: configuração extra ---';

void main(List<String> args) {
  final appId = args.isNotEmpty ? args.first : 'app.pontegt1';
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$').hasMatch(appId)) {
    stderr.writeln('ID inválido: $appId (use algo como br.com.seunome.pontegt1)');
    exit(1);
  }

  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final file = kts.existsSync() ? kts : groovy;
  if (!file.existsSync()) {
    stderr.writeln('Não achei android/app/build.gradle(.kts). Rode antes: flutter create --org app --project-name pontegt1 --platforms android .');
    exit(1);
  }

  var text = file.readAsStringSync();
  final i = text.indexOf(marker);
  if (i >= 0) text = text.substring(0, i).trimRight();

  if (file == kts && !text.contains('import java.util.Properties')) {
    text = 'import java.util.Properties\n\n$text';
  }
  final block = file == kts ? _ktsBlock(appId) : _groovyBlock(appId);
  file.writeAsStringSync('$text\n\n$block\n');
  stdout.writeln('OK: ${file.path} configurado (applicationId = $appId).');
}

String _ktsBlock(String id) => '''
$marker
val ponteKeyFile = rootProject.file("key.properties")
android {
    defaultConfig {
        applicationId = "$id"
        minSdk = maxOf(24, flutter.minSdkVersion)
    }
    if (ponteKeyFile.exists()) {
        val p = Properties()
        ponteKeyFile.inputStream().use { p.load(it) }
        signingConfigs {
            create("upload") {
                storeFile = file(p.getProperty("storeFile"))
                storePassword = p.getProperty("storePassword")
                keyAlias = p.getProperty("keyAlias")
                keyPassword = p.getProperty("keyPassword")
            }
        }
        buildTypes {
            getByName("release") {
                signingConfig = signingConfigs.getByName("upload")
            }
        }
    }
}''';

String _groovyBlock(String id) => '''
$marker
def ponteKeyFile = rootProject.file("key.properties")
android {
    defaultConfig {
        applicationId "$id"
        minSdkVersion Math.max(24, flutter.minSdkVersion)
    }
    if (ponteKeyFile.exists()) {
        def p = new Properties()
        ponteKeyFile.withInputStream { p.load(it) }
        signingConfigs {
            upload {
                storeFile file(p.getProperty("storeFile"))
                storePassword p.getProperty("storePassword")
                keyAlias p.getProperty("keyAlias")
                keyPassword p.getProperty("keyPassword")
            }
        }
        buildTypes {
            release {
                signingConfig signingConfigs.upload
            }
        }
    }
}''';
