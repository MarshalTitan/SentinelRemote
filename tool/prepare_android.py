"""Configure a platform shell generated with the pinned Flutter SDK; never handles credentials."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent.parent
app = root / '.platform'
for directory in ('lib', 'test'):
    target = app / directory
    if target.exists():
        # The generated target is fixed beneath this repository's .platform folder.
        assert target.resolve().is_relative_to(app.resolve())
        shutil.rmtree(target)
    shutil.copytree(root / directory, target)
for name in ('pubspec.yaml', 'analysis_options.yaml'):
    shutil.copyfile(root / name, app / name)
if (root / 'pubspec.lock').exists():
    shutil.copyfile(root / 'pubspec.lock', app / 'pubspec.lock')
manifest = app / 'android/app/src/main/AndroidManifest.xml'
text = manifest.read_text()
text = text.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application android:allowBackup="false" android:usesCleartextTraffic="false"')
text = text.replace('android:label="sentinel_remote"', 'android:label="Sentinel Remote"')
manifest.write_text(text)
activity = app / 'android/app/src/main/kotlin/dev/marshaltitan/sentinel_remote/MainActivity.kt'
activity.write_text('''package dev.marshaltitan.sentinel_remote
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }
}
''')
gradle = app / 'android/app/build.gradle.kts'
text = gradle.read_text().replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
gradle.write_text(text)
