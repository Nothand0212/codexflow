# Android APK Build and Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a signed Android APK that includes the history-list fix, foreground background monitoring, sound alerts for manual actions and turn results, persistent status notification, and version metadata.

**Architecture:** Keep the Flutter UI responsible for screens, settings, lifecycle signals, and notification tap routing. Implement Android foreground monitoring in native Kotlin so service type, notification ids, permission handling, and `startForeground()` timing are explicit. Put dashboard filtering, snapshot deduplication, batching, and adaptive polling into small Kotlin classes with JVM tests so the foreground service stays thin.

**Tech Stack:** Flutter/Dart, Android Kotlin, Android foreground service `specialUse`, SharedPreferences snapshot JSON, MethodChannel, shell rollout script.

---

## File Map

- Modify: `flutter/codexflow/pubspec.yaml` for version `0.2.0+2`.
- Modify: `.gitignore` and `flutter/codexflow/android/.gitignore` for release key safety.
- Modify: `flutter/codexflow/android/app/build.gradle.kts` for SDK 35, release signing, and unit test dependencies.
- Modify: `flutter/codexflow/android/app/src/main/AndroidManifest.xml` for permissions, service, and launch mode.
- Modify: `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/MainActivity.kt` for MethodChannel and notification intents.
- Create: `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/MonitorModels.kt`.
- Create: `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/MonitorStateMachine.kt`.
- Create: `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/MonitorSnapshotStore.kt`.
- Create: `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/DashboardClient.kt`.
- Create: `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/CodexFlowNotifications.kt`.
- Create: `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/CodexFlowMonitorService.kt`.
- Create: `flutter/codexflow/android/app/src/test/kotlin/com/example/codexflow_flutter/monitor/MonitorStateMachineTest.kt`.
- Create: `flutter/codexflow/lib/domain/session_groups.dart`.
- Create: `flutter/codexflow/lib/services/android_monitor_bridge.dart`.
- Create: `flutter/codexflow/lib/navigation/notification_target.dart`.
- Modify: `flutter/codexflow/lib/main.dart` for lifecycle forwarding and notification routing.
- Modify: `flutter/codexflow/lib/state/app_model.dart` for monitor status, manual-stop marker, and notification target handling.
- Modify: `flutter/codexflow/lib/screens/dashboard_screen.dart` to consume shared session grouping.
- Modify: `flutter/codexflow/lib/screens/settings_screen.dart` for monitor controls, notification permission status, and version display.
- Create: `flutter/codexflow/test/session_groups_test.dart`.
- Create: `flutter/codexflow/test/android_monitor_bridge_test.dart`.
- Create: `flutter/codexflow/test/notification_target_test.dart`.
- Create: `scripts/build-codexflow-android.sh`.

Before editing, run `git status --short` and preserve existing unrelated changes. Several files are already dirty from earlier work; do not revert them.

---

## Task 1: Toolchain Setup

**Files:**
- Local only: `/home/lin/.local/share/flutter`
- Local only: `/home/lin/Android/Sdk/cmdline-tools/latest`
- Local only: `flutter/codexflow/android/local.properties`

- [ ] **Step 1: Check current toolchain state**

Run:

```bash
ls -la /home/lin/.local/share/flutter || true
ls -la /home/lin/Android/Sdk || true
find /home/lin/Android/Sdk/platforms -maxdepth 1 -type d 2>/dev/null | sort || true
find /home/lin/Android/Sdk -maxdepth 4 -type f -name sdkmanager -print
```

Expected current state: Flutter is absent, Android SDK exists, only `platforms/android-36.1` is present, and `sdkmanager` may be absent.

- [ ] **Step 2: Install Flutter stable if absent**

Run:

```bash
mkdir -p /home/lin/.local/share
cd /home/lin/.local/share
if [ ! -d flutter ]; then
  git clone https://github.com/flutter/flutter.git -b stable flutter
fi
/home/lin/.local/share/flutter/bin/flutter --version
```

Expected: Flutter prints a stable version and exits 0.

- [ ] **Step 3: Install Android command-line tools if `sdkmanager` is absent**

Run:

```bash
mkdir -p /home/lin/Android/Sdk/cmdline-tools
cd /tmp
curl -L -o commandlinetools-linux.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
rm -rf /tmp/android-cmdline-tools
mkdir -p /tmp/android-cmdline-tools
unzip -q commandlinetools-linux.zip -d /tmp/android-cmdline-tools
rm -rf /home/lin/Android/Sdk/cmdline-tools/latest
mv /tmp/android-cmdline-tools/cmdline-tools /home/lin/Android/Sdk/cmdline-tools/latest
```

Then verify:

```bash
/home/lin/Android/Sdk/cmdline-tools/latest/bin/sdkmanager --version
```

Expected: `sdkmanager` prints a version.

- [ ] **Step 4: Install Android 35 platform and accept licenses**

Run:

```bash
yes | /home/lin/Android/Sdk/cmdline-tools/latest/bin/sdkmanager --licenses
/home/lin/Android/Sdk/cmdline-tools/latest/bin/sdkmanager \
  "platforms;android-35" \
  "build-tools;35.0.0" \
  "platform-tools"
```

Expected:

```bash
test -d /home/lin/Android/Sdk/platforms/android-35
test -x /home/lin/Android/Sdk/platform-tools/adb
```

- [ ] **Step 5: Create Flutter Android local properties**

Run:

```bash
cat > flutter/codexflow/android/local.properties <<'EOF'
sdk.dir=/home/lin/Android/Sdk
flutter.sdk=/home/lin/.local/share/flutter
EOF
```

This file is ignored by `flutter/codexflow/android/.gitignore`; do not commit it.

- [ ] **Step 6: Run Flutter doctor for Android**

Run:

```bash
/home/lin/.local/share/flutter/bin/flutter doctor -v
```

Expected: Android toolchain is detected. If doctor reports only missing Chrome/Linux desktop tooling, continue because this APK work only needs Android.

---

## Task 2: Release Versioning, Signing, and Publish Script

**Files:**
- Modify: `flutter/codexflow/pubspec.yaml`
- Modify: `flutter/codexflow/android/app/build.gradle.kts`
- Modify: `.gitignore`
- Modify: `flutter/codexflow/android/.gitignore`
- Local only: `/home/lin/.local/share/codexflow-keys/release.jks`
- Local only: `flutter/codexflow/android/key.properties`
- Create: `scripts/build-codexflow-android.sh`

- [ ] **Step 1: Bump Flutter app version**

Edit `flutter/codexflow/pubspec.yaml`:

```yaml
version: 0.2.0+2
```

- [ ] **Step 2: Add root key ignore rules**

Append these lines to `.gitignore` if they are absent:

```gitignore
# Android release signing
flutter/codexflow/android/key.properties
*.jks
*.keystore
```

Keep existing Flutter Android ignore rules for `key.properties`, `**/*.keystore`, and `**/*.jks`.

- [ ] **Step 3: Create the release keystore if absent**

Run:

```bash
mkdir -p /home/lin/.local/share/codexflow-keys
if [ ! -f /home/lin/.local/share/codexflow-keys/release.jks ]; then
  keytool -genkeypair \
    -v \
    -keystore /home/lin/.local/share/codexflow-keys/release.jks \
    -alias codexflow \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "CN=CodexFlow, O=Local, L=Local, C=US"
fi
```

Use a local password when prompted. Reuse this same keystore for later builds.

- [ ] **Step 4: Create `key.properties`**

Create `flutter/codexflow/android/key.properties`:

```properties
storeFile=/home/lin/.local/share/codexflow-keys/release.jks
storePassword=<the local keystore password>
keyAlias=codexflow
keyPassword=<the local key password>
```

Do not commit this file.

- [ ] **Step 5: Configure release signing and SDK 35**

Update the signing-related parts of `flutter/codexflow/android/app/build.gradle.kts` to this shape, preserving existing plugin declarations:

```kotlin
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.codexflow_flutter"
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.codexflow_flutter"
        minSdk = 21
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    testImplementation("junit:junit:4.13.2")
}
```

- [ ] **Step 6: Create the APK publish script**

Create `scripts/build-codexflow-android.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="/home/lin/.local/share/flutter/bin/flutter"
APP_DIR="$ROOT_DIR/flutter/codexflow"
WEB_DIR="/home/lin/.local/share/codexflow-web/web"
VERSION="0.2.0"
BUILD_NUMBER="2"
VERSIONED_APK="codexflow-android-v${VERSION}.apk"
LATEST_APK="codexflow-android-latest.apk"
META_JSON="codexflow-android-latest.json"

cd "$APP_DIR"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" test
"$FLUTTER_BIN" build apk --release

mkdir -p "$WEB_DIR"
cp "$APP_DIR/build/app/outputs/flutter-apk/app-release.apk" "$WEB_DIR/$VERSIONED_APK"
cp "$WEB_DIR/$VERSIONED_APK" "$WEB_DIR/$LATEST_APK"

SHA256="$(sha256sum "$WEB_DIR/$VERSIONED_APK" | awk '{print $1}')"
BUILT_AT="$(date -Iseconds)"
cat > "$WEB_DIR/$META_JSON" <<JSON
{
  "version": "$VERSION",
  "buildNumber": $BUILD_NUMBER,
  "artifact": "$VERSIONED_APK",
  "latestArtifact": "$LATEST_APK",
  "sha256": "$SHA256",
  "builtAt": "$BUILT_AT"
}
JSON

echo "$WEB_DIR/$VERSIONED_APK"
echo "$SHA256"
```

Run:

```bash
chmod +x scripts/build-codexflow-android.sh
```

- [ ] **Step 7: Commit versioning and signing config**

Run:

```bash
git diff --check flutter/codexflow/pubspec.yaml flutter/codexflow/android/app/build.gradle.kts .gitignore scripts/build-codexflow-android.sh
git add flutter/codexflow/pubspec.yaml flutter/codexflow/android/app/build.gradle.kts .gitignore scripts/build-codexflow-android.sh
git commit -m "build: configure android release apk"
```

---

## Task 3: History Session Grouping Fix

**Files:**
- Create: `flutter/codexflow/lib/domain/session_groups.dart`
- Modify: `flutter/codexflow/lib/screens/dashboard_screen.dart`
- Test: `flutter/codexflow/test/session_groups_test.dart`

- [ ] **Step 1: Write the failing grouping test**

Create `flutter/codexflow/test/session_groups_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codexflow_flutter/domain/session_groups.dart';
import 'package:codexflow_flutter/models/app_models.dart';

void main() {
  test('discovered sessions are included in history group', () {
    final groups = groupSessionsForAgent(
      sessions: <SessionSummary>[
        _session(id: 'managed-1', stage: 'managed'),
        _session(id: 'history-1', stage: 'history_only'),
        _session(id: 'discovered-1', stage: 'discovered'),
      ],
      approvals: const <PendingRequestView>[],
      selectedAgentId: 'codex',
    );

    expect(groups.managed.map((item) => item.id), <String>['managed-1']);
    expect(
      groups.history.map((item) => item.id),
      <String>['history-1', 'discovered-1'],
    );
  });

  test('pending approval count uses approval threadId filter', () {
    final groups = groupSessionsForAgent(
      sessions: <SessionSummary>[
        _session(id: 'managed-1', stage: 'managed', pendingApprovals: 99),
        _session(id: 'history-1', stage: 'history_only'),
      ],
      approvals: <PendingRequestView>[
        _approval(id: 'req-1', threadId: 'managed-1'),
        _approval(id: 'req-2', threadId: 'history-1'),
      ],
      selectedAgentId: 'codex',
    );

    expect(groups.pendingApprovals, hasLength(1));
    expect(groups.pendingApprovals.single.id, 'req-1');
    expect(groups.pendingApprovalCount, 1);
  });
}

SessionSummary _session({
  required String id,
  required String stage,
  int pendingApprovals = 0,
}) {
  return SessionSummary(
    id: id,
    agentId: 'codex',
    name: '',
    preview: '',
    cwd: '/tmp/$id',
    source: '',
    status: stage == 'ended' ? 'ended' : 'active',
    activeFlags: const <String>[],
    loaded: true,
    updatedAt: 1,
    createdAt: 1,
    modelProvider: '',
    branch: '',
    pendingApprovals: pendingApprovals,
    lastTurnId: '',
    lastTurnStatus: '',
    agentNickname: '',
    agentRole: '',
    lifecycleStage: stage,
    historyAvailable: stage == 'history_only' || stage == 'discovered',
    runtimeAvailable: stage == 'runtime_available',
    runtimeAttachMode: '',
    resumeAvailable: true,
    resumeBlockedReason: '',
    ended: stage == 'ended',
  );
}

PendingRequestView _approval({required String id, required String threadId}) {
  return PendingRequestView(
    id: id,
    method: 'codex/approval',
    kind: 'command',
    threadId: threadId,
    turnId: '',
    itemId: '',
    reason: '',
    summary: '',
    choices: const <String>[],
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    params: const <String, dynamic>{},
  );
}
```

- [ ] **Step 2: Run the test and confirm failure**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test test/session_groups_test.dart
```

Expected before implementation: import or function missing.

- [ ] **Step 3: Add shared grouping implementation**

Create `flutter/codexflow/lib/domain/session_groups.dart`:

```dart
import '../models/app_models.dart';

class SessionGroups {
  const SessionGroups({
    required this.filteredSessions,
    required this.pendingApprovals,
    required this.managed,
    required this.ended,
    required this.runtimeAvailable,
    required this.history,
  });

  final List<SessionSummary> filteredSessions;
  final List<PendingRequestView> pendingApprovals;
  final List<SessionSummary> managed;
  final List<SessionSummary> ended;
  final List<SessionSummary> runtimeAvailable;
  final List<SessionSummary> history;

  int get loadedCount =>
      filteredSessions.where((session) => session.loaded).length;

  int get activeCount => filteredSessions
      .where((session) => session.status == 'active' && !session.isEnded)
      .length;

  int get pendingApprovalCount => pendingApprovals.length;
}

SessionGroups groupSessionsForAgent({
  required List<SessionSummary> sessions,
  required List<PendingRequestView> approvals,
  required String selectedAgentId,
}) {
  final filteredSessions = sessions
      .where((session) => session.agentId == selectedAgentId)
      .toList();
  final allowedSessionIds = filteredSessions.map((item) => item.id).toSet();
  final filteredApprovals = approvals
      .where((approval) => allowedSessionIds.contains(approval.threadId))
      .toList();

  return SessionGroups(
    filteredSessions: filteredSessions,
    pendingApprovals: filteredApprovals,
    managed: filteredSessions
        .where((session) => session.lifecycleStage == 'managed')
        .toList(),
    ended: filteredSessions
        .where((session) => session.lifecycleStage == 'ended')
        .toList(),
    runtimeAvailable: filteredSessions
        .where((session) => session.lifecycleStage == 'runtime_available')
        .toList(),
    history: filteredSessions
        .where(
          (session) =>
              session.lifecycleStage == 'history_only' ||
              session.lifecycleStage == 'discovered',
        )
        .toList(),
  );
}
```

- [ ] **Step 4: Use the shared grouping in `DashboardScreen`**

In `flutter/codexflow/lib/screens/dashboard_screen.dart`, import:

```dart
import '../domain/session_groups.dart';
```

Replace the local filtering block at the top of `build` with:

```dart
final groups = groupSessionsForAgent(
  sessions: model.dashboard.sessions,
  approvals: model.dashboard.approvals,
  selectedAgentId: selectedAgentId,
);
final filteredSessions = groups.filteredSessions;
final loadedCount = groups.loadedCount;
final activeCount = groups.activeCount;
final pendingApprovalCount = groups.pendingApprovalCount;
final managedSessions = groups.managed;
final endedSessions = groups.ended;
final runtimeSessions = groups.runtimeAvailable;
final historySessions = groups.history;
```

- [ ] **Step 5: Verify and commit**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test test/session_groups_test.dart
/home/lin/.local/share/flutter/bin/flutter test
cd ../..
git diff --check flutter/codexflow/lib/domain/session_groups.dart flutter/codexflow/lib/screens/dashboard_screen.dart flutter/codexflow/test/session_groups_test.dart
git add flutter/codexflow/lib/domain/session_groups.dart flutter/codexflow/lib/screens/dashboard_screen.dart flutter/codexflow/test/session_groups_test.dart
git commit -m "fix: include discovered sessions in android history"
```

---

## Task 4: Kotlin Monitor State Machine

**Files:**
- Create: `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/MonitorModels.kt`
- Create: `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/MonitorStateMachine.kt`
- Test: `flutter/codexflow/android/app/src/test/kotlin/com/example/codexflow_flutter/monitor/MonitorStateMachineTest.kt`

- [ ] **Step 1: Add state machine tests**

Create `MonitorStateMachineTest.kt` with these test cases:

```kotlin
package com.example.codexflow_flutter.monitor

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorStateMachineTest {
    private val machine = MonitorStateMachine()

    @Test
    fun baselineEmitsNoAlertsAndRecordsManagedTurnState() {
        val result = machine.evaluate(
            url = "http://100.91.5.116:4318",
            previous = MonitorSnapshot.empty(),
            dashboard = dashboard(
                sessions = listOf(session("s1", "managed", "t1", "inProgress")),
                approvals = listOf(approval("req1", "s1")),
            ),
            nowEpochSeconds = 100,
            forceFreshBaseline = true,
        )

        assertTrue(result.manualActions.isEmpty())
        assertTrue(result.turnResults.isEmpty())
        assertEquals("t1", result.snapshot.urlState("http://100.91.5.116:4318").managedTurnState["s1"]?.lastTurnId)
        assertTrue(result.snapshot.urlState("http://100.91.5.116:4318").seenApprovals.containsKey("req1"))
    }

    @Test
    fun approvalAlertsOnlyForManagedSessionsAndTrustsFilteredApprovals() {
        val previous = machine.evaluate(
            url = URL,
            previous = MonitorSnapshot.empty(),
            dashboard = dashboard(sessions = listOf(session("s1", "managed", "", ""))),
            nowEpochSeconds = 100,
            forceFreshBaseline = true,
        ).snapshot

        val result = machine.evaluate(
            url = URL,
            previous = previous,
            dashboard = dashboard(
                sessions = listOf(
                    session("s1", "managed", "", "", pendingApprovals = 99),
                    session("s2", "history_only", "", ""),
                ),
                approvals = listOf(approval("req-managed", "s1"), approval("req-history", "s2")),
            ),
            nowEpochSeconds = 110,
            forceFreshBaseline = false,
        )

        assertEquals(listOf("req-managed"), result.manualActions.map { it.approvalId })
        assertEquals(1, result.status.pendingManualActionCount)
    }

    @Test
    fun transitionFinalAndManagedTurnResultsBatchTogetherOnce() {
        val previous = machine.evaluate(
            url = URL,
            previous = MonitorSnapshot.empty(),
            dashboard = dashboard(
                sessions = listOf(
                    session("leaving", "managed", "turn-a", "inProgress"),
                    session("staying", "managed", "turn-b", "inProgress"),
                ),
            ),
            nowEpochSeconds = 100,
            forceFreshBaseline = true,
        ).snapshot

        val result = machine.evaluate(
            url = URL,
            previous = previous,
            dashboard = dashboard(
                sessions = listOf(
                    session("leaving", "ended", "turn-a", "completed"),
                    session("staying", "managed", "turn-b", "interrupted"),
                ),
            ),
            nowEpochSeconds = 110,
            forceFreshBaseline = false,
        )

        assertEquals(2, result.turnResults.size)
        assertEquals(setOf("leaving", "staying"), result.turnResults.map { it.sessionId }.toSet())
        assertTrue(result.snapshot.urlState(URL).seenTurnResults.containsKey("leaving:turn-a:completed"))
        assertFalse(result.snapshot.urlState(URL).managedTurnState.containsKey("leaving"))
        assertEquals(setOf("staying"), result.snapshot.urlState(URL).managedTurnState.keys)
    }

    @Test
    fun sessionDisappearingEntirelyDoesNotEmitFinalTurnResult() {
        val previous = machine.evaluate(
            url = URL,
            previous = MonitorSnapshot.empty(),
            dashboard = dashboard(sessions = listOf(session("gone", "managed", "t1", "inProgress"))),
            nowEpochSeconds = 100,
            forceFreshBaseline = true,
        ).snapshot

        val result = machine.evaluate(
            url = URL,
            previous = previous,
            dashboard = dashboard(sessions = emptyList()),
            nowEpochSeconds = 110,
            forceFreshBaseline = false,
        )

        assertTrue(result.turnResults.isEmpty())
        assertFalse(result.snapshot.urlState(URL).managedTurnState.containsKey("gone"))
    }

    @Test
    fun duplicatePollDoesNotRealertAndOldKeysArePruned() {
        val previous = MonitorSnapshot(
            version = 1,
            urls = mapOf(
                URL to UrlMonitorSnapshot(
                    initialized = true,
                    manuallyStopped = false,
                    lastUsedAt = 1,
                    lastSuccessAt = 1,
                    seenApprovals = mapOf("old-approval" to 1),
                    seenTurnResults = mapOf("old-session:old-turn:completed" to 1),
                    managedTurnState = mapOf("s1" to ManagedTurnState("t1", "completed")),
                    lastRunningManagedCount = 1,
                    lastPendingManualActionCount = 0,
                ),
            ),
        )

        val result = machine.evaluate(
            url = URL,
            previous = previous,
            dashboard = dashboard(sessions = listOf(session("s1", "managed", "t1", "completed"))),
            nowEpochSeconds = 8 * 24 * 60 * 60,
            forceFreshBaseline = false,
        )

        assertTrue(result.turnResults.isEmpty())
        assertFalse(result.snapshot.urlState(URL).seenApprovals.containsKey("old-approval"))
        assertFalse(result.snapshot.urlState(URL).seenTurnResults.containsKey("old-session:old-turn:completed"))
    }

    private fun dashboard(
        sessions: List<SessionSnapshot> = emptyList(),
        approvals: List<ApprovalSnapshot> = emptyList(),
    ) = DashboardSnapshot(agentConnected = true, sessions = sessions, approvals = approvals)

    private fun session(
        id: String,
        stage: String,
        turnId: String,
        turnStatus: String,
        pendingApprovals: Int = 0,
    ) = SessionSnapshot(
        id = id,
        displayName = id,
        lifecycleStage = stage,
        lastTurnId = turnId,
        lastTurnStatus = turnStatus,
        pendingApprovals = pendingApprovals,
    )

    private fun approval(id: String, threadId: String) = ApprovalSnapshot(
        id = id,
        threadId = threadId,
        summary = id,
        createdAtEpochSeconds = 1,
    )

    private companion object {
        const val URL = "http://100.91.5.116:4318"
    }
}
```

- [ ] **Step 2: Run the JVM test and confirm failure**

If a Gradle wrapper is available, run:

```bash
cd flutter/codexflow/android
./gradlew :app:testDebugUnitTest --tests '*MonitorStateMachineTest'
```

If `./gradlew` is absent, run the Flutter build verification after Step 4 and keep this unit test in place for the restored wrapper. Do not remove the test because native compile still needs the same production classes.

- [ ] **Step 3: Add monitor model classes**

Create `MonitorModels.kt`:

```kotlin
package com.example.codexflow_flutter.monitor

data class DashboardSnapshot(
    val agentConnected: Boolean,
    val sessions: List<SessionSnapshot>,
    val approvals: List<ApprovalSnapshot>,
)

data class SessionSnapshot(
    val id: String,
    val displayName: String,
    val lifecycleStage: String,
    val lastTurnId: String,
    val lastTurnStatus: String,
    val pendingApprovals: Int = 0,
)

data class ApprovalSnapshot(
    val id: String,
    val threadId: String,
    val summary: String,
    val createdAtEpochSeconds: Long,
)

data class ManagedTurnState(
    val lastTurnId: String,
    val lastTurnStatus: String,
)

data class UrlMonitorSnapshot(
    val initialized: Boolean,
    val manuallyStopped: Boolean,
    val lastUsedAt: Long,
    val lastSuccessAt: Long,
    val seenApprovals: Map<String, Long>,
    val seenTurnResults: Map<String, Long>,
    val managedTurnState: Map<String, ManagedTurnState>,
    val lastRunningManagedCount: Int,
    val lastPendingManualActionCount: Int,
)

data class MonitorSnapshot(
    val version: Int,
    val urls: Map<String, UrlMonitorSnapshot>,
) {
    fun urlState(url: String): UrlMonitorSnapshot = urls[url] ?: emptyUrlState()

    companion object {
        fun empty(): MonitorSnapshot = MonitorSnapshot(version = 1, urls = emptyMap())
        fun emptyUrlState(): UrlMonitorSnapshot = UrlMonitorSnapshot(
            initialized = false,
            manuallyStopped = false,
            lastUsedAt = 0,
            lastSuccessAt = 0,
            seenApprovals = emptyMap(),
            seenTurnResults = emptyMap(),
            managedTurnState = emptyMap(),
            lastRunningManagedCount = 0,
            lastPendingManualActionCount = 0,
        )
    }
}

data class ManualActionEvent(
    val approvalId: String,
    val sessionId: String,
    val sessionLabel: String,
    val summary: String,
)

data class TurnResultEvent(
    val sessionId: String,
    val sessionLabel: String,
    val turnId: String,
    val status: String,
)

data class MonitorStatus(
    val online: Boolean,
    val runningManagedCount: Int,
    val pendingManualActionCount: Int,
    val hostPort: String,
)

data class MonitorDecision(
    val snapshot: MonitorSnapshot,
    val status: MonitorStatus,
    val manualActions: List<ManualActionEvent>,
    val turnResults: List<TurnResultEvent>,
)
```

- [ ] **Step 4: Implement state machine**

Create `MonitorStateMachine.kt`:

```kotlin
package com.example.codexflow_flutter.monitor

import java.net.URI

class MonitorStateMachine {
    fun evaluate(
        url: String,
        previous: MonitorSnapshot,
        dashboard: DashboardSnapshot,
        nowEpochSeconds: Long,
        forceFreshBaseline: Boolean,
    ): MonitorDecision {
        val previousUrlState = previous.urlState(url)
        val managedSessions = dashboard.sessions.filter { it.lifecycleStage == "managed" }
        val managedIds = managedSessions.map { it.id }.toSet()
        val sessionsById = dashboard.sessions.associateBy { it.id }
        val filteredApprovals = dashboard.approvals.filter { managedIds.contains(it.threadId) }
        val currentManagedTurnState = managedSessions.associate { session ->
            session.id to ManagedTurnState(session.lastTurnId, session.lastTurnStatus)
        }

        val baseline = forceFreshBaseline || !previousUrlState.initialized || previousUrlState.manuallyStopped
        val mutableSeenApprovals = previousUrlState.seenApprovals.toMutableMap()
        val mutableSeenTurns = previousUrlState.seenTurnResults.toMutableMap()
        val newManualActions = mutableListOf<ManualActionEvent>()
        val newTurnResults = mutableListOf<TurnResultEvent>()

        pruneSeen(mutableSeenApprovals, nowEpochSeconds, SEVEN_DAYS_SECONDS)
        pruneSeen(mutableSeenTurns, nowEpochSeconds, SEVEN_DAYS_SECONDS)

        if (baseline) {
            filteredApprovals.forEach { mutableSeenApprovals[it.id] = nowEpochSeconds }
            managedSessions.forEach { session ->
                val key = turnResultKey(session)
                if (key != null && isTerminal(session.lastTurnStatus)) {
                    mutableSeenTurns[key] = nowEpochSeconds
                }
            }
        } else {
            val leavingManagedIds = previousUrlState.managedTurnState.keys - managedIds
            for (sessionId in leavingManagedIds) {
                val session = sessionsById[sessionId] ?: continue
                if (!isTerminal(session.lastTurnStatus)) continue
                val key = turnResultKey(session) ?: continue
                if (mutableSeenTurns.containsKey(key)) continue
                mutableSeenTurns[key] = nowEpochSeconds
                newTurnResults += TurnResultEvent(
                    sessionId = session.id,
                    sessionLabel = session.displayName,
                    turnId = session.lastTurnId,
                    status = session.lastTurnStatus,
                )
            }

            for (approval in filteredApprovals) {
                if (mutableSeenApprovals.containsKey(approval.id)) continue
                mutableSeenApprovals[approval.id] = nowEpochSeconds
                val session = sessionsById[approval.threadId]
                newManualActions += ManualActionEvent(
                    approvalId = approval.id,
                    sessionId = approval.threadId,
                    sessionLabel = session?.displayName ?: shortId(approval.threadId),
                    summary = approval.summary,
                )
            }

            for (session in managedSessions) {
                if (!isTerminal(session.lastTurnStatus)) continue
                val key = turnResultKey(session) ?: continue
                if (mutableSeenTurns.containsKey(key)) continue
                mutableSeenTurns[key] = nowEpochSeconds
                newTurnResults += TurnResultEvent(
                    sessionId = session.id,
                    sessionLabel = session.displayName,
                    turnId = session.lastTurnId,
                    status = session.lastTurnStatus,
                )
            }
        }

        val nextUrlState = UrlMonitorSnapshot(
            initialized = true,
            manuallyStopped = false,
            lastUsedAt = nowEpochSeconds,
            lastSuccessAt = nowEpochSeconds,
            seenApprovals = mutableSeenApprovals.toMap(),
            seenTurnResults = mutableSeenTurns.toMap(),
            managedTurnState = currentManagedTurnState,
            lastRunningManagedCount = managedSessions.size,
            lastPendingManualActionCount = filteredApprovals.size,
        )
        val prunedUrls = previous.urls.filterValues {
            nowEpochSeconds - it.lastUsedAt <= THIRTY_DAYS_SECONDS
        }.toMutableMap()
        prunedUrls[url] = nextUrlState

        return MonitorDecision(
            snapshot = MonitorSnapshot(version = 1, urls = prunedUrls),
            status = MonitorStatus(
                online = dashboard.agentConnected,
                runningManagedCount = managedSessions.size,
                pendingManualActionCount = filteredApprovals.size,
                hostPort = hostPort(url),
            ),
            manualActions = newManualActions,
            turnResults = newTurnResults,
        )
    }

    private fun turnResultKey(session: SessionSnapshot): String? {
        if (session.id.isBlank() || session.lastTurnId.isBlank() || session.lastTurnStatus.isBlank()) return null
        return "${session.id}:${session.lastTurnId}:${session.lastTurnStatus}"
    }

    private fun isTerminal(status: String): Boolean = status == "completed" || status == "interrupted"

    private fun pruneSeen(values: MutableMap<String, Long>, now: Long, maxAgeSeconds: Long) {
        values.entries.removeIf { now - it.value > maxAgeSeconds }
    }

    private fun hostPort(url: String): String {
        return runCatching {
            val uri = URI(url)
            if (uri.port > 0) "${uri.host}:${uri.port}" else uri.host.orEmpty()
        }.getOrDefault(url)
    }

    private fun shortId(value: String): String = if (value.length <= 8) value else value.substring(0, 8)

    private companion object {
        const val SEVEN_DAYS_SECONDS = 7L * 24L * 60L * 60L
        const val THIRTY_DAYS_SECONDS = 30L * 24L * 60L * 60L
    }
}
```

- [ ] **Step 5: Verify and commit**

Run:

```bash
cd flutter/codexflow/android
if [ -x ./gradlew ]; then ./gradlew :app:testDebugUnitTest --tests '*MonitorStateMachineTest'; fi
cd ../../..
git diff --check flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor flutter/codexflow/android/app/src/test/kotlin/com/example/codexflow_flutter/monitor
git add flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/MonitorModels.kt flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/MonitorStateMachine.kt flutter/codexflow/android/app/src/test/kotlin/com/example/codexflow_flutter/monitor/MonitorStateMachineTest.kt
git commit -m "feat: add android monitor state machine"
```

---

## Task 5: Android Foreground Service and Notifications

**Files:**
- Create: `CodexFlowMonitorService.kt`
- Create: `DashboardClient.kt`
- Create: `MonitorSnapshotStore.kt`
- Create: `CodexFlowNotifications.kt`
- Modify: `AndroidManifest.xml`

- [ ] **Step 1: Update manifest permissions and service**

Add permissions near the existing `INTERNET` permission:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
```

Ensure `MainActivity` keeps:

```xml
android:launchMode="singleTop"
```

Add the service inside `<application>`:

```xml
<service
    android:name=".monitor.CodexFlowMonitorService"
    android:exported="false"
    android:foregroundServiceType="specialUse">
    <property
        android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
        android:value="monitor_codexflow_agent_over_user_configured_tailscale_or_lan_url" />
</service>
```

- [ ] **Step 2: Add notification channel and builder helper**

Create `CodexFlowNotifications.kt` with:

```kotlin
package com.example.codexflow_flutter.monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import androidx.core.app.NotificationCompat
import com.example.codexflow_flutter.MainActivity
import com.example.codexflow_flutter.R

class CodexFlowNotifications(private val context: Context) {
    fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL_MANUAL, "Manual action", NotificationManager.IMPORTANCE_HIGH).apply {
            enableVibration(true)
            setSound(android.provider.Settings.System.DEFAULT_NOTIFICATION_URI, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
        })
        manager.createNotificationChannel(NotificationChannel(CHANNEL_TURN, "Task result", NotificationManager.IMPORTANCE_DEFAULT).apply {
            setSound(android.provider.Settings.System.DEFAULT_NOTIFICATION_URI, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
        })
        manager.createNotificationChannel(NotificationChannel(CHANNEL_STATUS, "CodexFlow status", NotificationManager.IMPORTANCE_LOW).apply {
            setSound(null, null)
        })
    }

    fun persistent(status: MonitorStatus?): Notification {
        val title = if (status == null) "CodexFlow starting · pending --" else "CodexFlow ${if (status.online) "online" else "offline"} · running ${status.runningManagedCount} · pending ${status.pendingManualActionCount}"
        val text = status?.hostPort?.ifBlank { "Loading Agent status" } ?: "Loading Agent status"
        return NotificationCompat.Builder(context, CHANNEL_STATUS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(routeIntent(NotificationTarget.dashboard()))
            .build()
    }

    fun manualAction(events: List<ManualActionEvent>): Notification {
        val target = if (events.size == 1) NotificationTarget.approval(events.single().approvalId, events.single().sessionId) else NotificationTarget.approvals()
        val text = if (events.size == 1) "${events.single().sessionLabel} has a pending approval" else "${events.size} pending approvals need review"
        return NotificationCompat.Builder(context, CHANNEL_MANUAL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("CodexFlow needs your action")
            .setContentText(text)
            .setOnlyAlertOnce(false)
            .setAutoCancel(true)
            .setContentIntent(routeIntent(target))
            .build()
    }

    fun turnResult(events: List<TurnResultEvent>): Notification {
        val sameSession = events.map { it.sessionId }.toSet().size == 1
        val target = if (events.size == 1 || sameSession) {
            val first = events.first()
            NotificationTarget.session(first.sessionId, first.turnId, first.status)
        } else {
            NotificationTarget.dashboard()
        }
        val title = if (events.size == 1 && events.single().status == "interrupted") "CodexFlow task interrupted" else if (events.size == 1) "CodexFlow task completed" else "CodexFlow tasks updated"
        val text = if (events.size == 1) {
            val event = events.single()
            if (event.status == "interrupted") "${event.sessionLabel} was interrupted" else "${event.sessionLabel} finished a turn"
        } else {
            val completed = events.count { it.status == "completed" }
            val interrupted = events.count { it.status == "interrupted" }
            listOfNotNull(
                if (completed > 0) "$completed completed" else null,
                if (interrupted > 0) "$interrupted interrupted" else null,
            ).joinToString(" · ")
        }
        return NotificationCompat.Builder(context, CHANNEL_TURN)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setOnlyAlertOnce(false)
            .setAutoCancel(true)
            .setContentIntent(routeIntent(target))
            .build()
    }

    private fun routeIntent(target: NotificationTarget): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(MainActivity.ACTION_NOTIFICATION_ROUTE)
            .putExtra(MainActivity.EXTRA_NOTIFICATION_TARGET, target.encode())
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, target.requestCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    companion object {
        const val CHANNEL_MANUAL = "manual_action"
        const val CHANNEL_TURN = "turn_result"
        const val CHANNEL_STATUS = "persistent_status"
        const val ID_PERSISTENT = 1000
        const val ID_MANUAL = 2000
        const val ID_TURN = 3000
    }
}
```

Add this data holder below `CodexFlowNotifications` or in `NotificationTarget.kt`:

```kotlin
data class NotificationTarget(
    val target: String,
    val approvalId: String = "",
    val sessionId: String = "",
    val turnId: String = "",
    val status: String = "",
) {
    fun encode(): String {
        val json = org.json.JSONObject()
            .put("target", target)
            .put("approvalId", approvalId)
            .put("sessionId", sessionId)
            .put("turnId", turnId)
            .put("status", status)
        return json.toString()
    }

    fun requestCode(): Int {
        return when (target) {
            "approvals" -> CodexFlowNotifications.ID_MANUAL
            "sessionDetail" -> CodexFlowNotifications.ID_TURN
            else -> CodexFlowNotifications.ID_PERSISTENT
        }
    }

    companion object {
        fun dashboard() = NotificationTarget(target = "dashboard")
        fun approvals() = NotificationTarget(target = "approvals")
        fun approval(approvalId: String, sessionId: String) =
            NotificationTarget(target = "approvals", approvalId = approvalId, sessionId = sessionId)
        fun session(sessionId: String, turnId: String, status: String) =
            NotificationTarget(target = "sessionDetail", sessionId = sessionId, turnId = turnId, status = status)
    }
}
```

- [ ] **Step 3: Add dashboard HTTP client**

Create `DashboardClient.kt` using `HttpURLConnection` with connect/read timeout 15 seconds. Parse `/api/v1/dashboard` into `DashboardSnapshot` with `org.json.JSONObject` and `JSONArray`. Use `PendingRequestView.threadId` as the approval session key and `SessionSummary.id` as the session id.

The parser must read:

```kotlin
agent.connected
sessions[].id
sessions[].name
sessions[].agentNickname
sessions[].cwd
sessions[].preview
sessions[].lifecycleStage
sessions[].lastTurnId
sessions[].lastTurnStatus
sessions[].pendingApprovals
approvals[].id
approvals[].threadId
approvals[].summary
approvals[].createdAt
```

Session label fallback order must match Flutter display behavior: name, agent nickname, directory name, preview title, then short id.

- [ ] **Step 4: Add snapshot store**

Create `MonitorSnapshotStore.kt` using Android `SharedPreferences` key `codexflow.monitor.snapshot.v1`.

Required methods:

```kotlin
class MonitorSnapshotStore(context: Context) {
    fun load(): MonitorSnapshot
    fun save(snapshot: MonitorSnapshot): Boolean
    fun markManuallyStopped(url: String): Boolean
}
```

Implementation constraints:

- Unknown or missing version returns `MonitorSnapshot.empty()`.
- `save` and `markManuallyStopped` use `commit()`, not `apply()`.
- JSON shape matches the spec: top-level `version`, `urls`, per-URL `initialized`, `manuallyStopped`, `lastUsedAt`, `lastSuccessAt`, `seenApprovals`, `seenTurnResults`, `managedTurnState`, counts.

- [ ] **Step 5: Add the foreground service**

Create `CodexFlowMonitorService.kt` with these behaviors:

- `onStartCommand` calls `startForeground()` immediately with `CodexFlowNotifications.persistent(null)`.
- Then it loads preferences, snapshot store, notification helper, and starts a single coroutine/handler loop.
- It reads `codexflow.baseURL` before every poll.
- If URL changes, the first successful dashboard response for the new URL is a fresh baseline.
- It uses success interval 10 seconds when Flutter says visible, 30 seconds when background.
- It uses failure backoff 30, 60, then 120 seconds.
- It updates persistent notification id `1000` every poll.
- It posts at most one manual action notification id `2000` and one turn result notification id `3000` per poll.
- It does not alert for network failures.

Use these actions:

```kotlin
const val ACTION_START = "com.example.codexflow_flutter.monitor.START"
const val ACTION_STOP = "com.example.codexflow_flutter.monitor.STOP"
const val ACTION_SET_VISIBILITY = "com.example.codexflow_flutter.monitor.SET_VISIBILITY"
const val EXTRA_VISIBLE = "visible"
```

- [ ] **Step 6: Verify native build surface**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter build apk --debug
```

Expected: Kotlin compiles and manifest merges.

- [ ] **Step 7: Commit service implementation**

Run:

```bash
git diff --check flutter/codexflow/android/app/src/main/AndroidManifest.xml flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor flutter/codexflow/android/app/build.gradle.kts
git add flutter/codexflow/android/app/src/main/AndroidManifest.xml flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor flutter/codexflow/android/app/build.gradle.kts
git commit -m "feat: add android foreground monitor service"
```

---

## Task 6: Flutter Bridge, Lifecycle, and Settings Controls

**Files:**
- Create: `flutter/codexflow/lib/services/android_monitor_bridge.dart`
- Modify: `flutter/codexflow/lib/main.dart`
- Modify: `flutter/codexflow/lib/state/app_model.dart`
- Modify: `flutter/codexflow/lib/screens/settings_screen.dart`
- Modify: `MainActivity.kt`
- Test: `flutter/codexflow/test/android_monitor_bridge_test.dart`

- [ ] **Step 1: Add bridge interface and fakeable implementation**

Create `android_monitor_bridge.dart`:

```dart
import 'dart:async';
import 'package:flutter/services.dart';

class AndroidMonitorStatus {
  const AndroidMonitorStatus({
    required this.supported,
    required this.running,
    required this.notificationPermissionGranted,
    required this.versionName,
    required this.buildNumber,
  });

  final bool supported;
  final bool running;
  final bool notificationPermissionGranted;
  final String versionName;
  final int buildNumber;
}

class AndroidMonitorBridge {
  AndroidMonitorBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('codexflow/monitor');

  final MethodChannel _channel;

  Future<void> start() => _channel.invokeMethod<void>('startMonitor');
  Future<void> stop() => _channel.invokeMethod<void>('stopMonitor');
  Future<void> setVisible(bool visible) =>
      _channel.invokeMethod<void>('setAppVisible', <String, Object?>{'visible': visible});
  Future<void> agentUrlChanged(String url) =>
      _channel.invokeMethod<void>('agentUrlChanged', <String, Object?>{'url': url});
  Future<bool> requestNotificationPermission() async =>
      await _channel.invokeMethod<bool>('requestNotificationPermission') ?? false;
  Future<AndroidMonitorStatus> getStatus() async {
    final value = await _channel.invokeMapMethod<String, Object?>('getMonitorStatus') ??
        const <String, Object?>{};
    return AndroidMonitorStatus(
      supported: value['supported'] == true,
      running: value['running'] == true,
      notificationPermissionGranted: value['notificationPermissionGranted'] == true,
      versionName: value['versionName']?.toString() ?? '0.2.0',
      buildNumber: value['buildNumber'] is int ? value['buildNumber'] as int : 2,
    );
  }
}
```

- [ ] **Step 2: Add Flutter unit test for bridge payloads**

Create `android_monitor_bridge_test.dart` using `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` and assert:

- `setVisible(true)` sends method `setAppVisible` with `visible: true`.
- `agentUrlChanged(url)` sends the new URL.
- `getStatus()` maps missing fields to safe defaults.

- [ ] **Step 3: Add MethodChannel handling in `MainActivity.kt`**

Change `MainActivity` from a plain `FlutterActivity` to an override of `configureFlutterEngine`. Register channel `codexflow/monitor` with methods:

- `startMonitor`: start `CodexFlowMonitorService` through `ContextCompat.startForegroundService`.
- `stopMonitor`: stop service.
- `setAppVisible`: send service action `ACTION_SET_VISIBILITY`.
- `agentUrlChanged`: start service if running and let it pick up the new URL.
- `requestNotificationPermission`: on Android 13+, request `POST_NOTIFICATIONS`; otherwise return true.
- `getMonitorStatus`: return supported/running/permission/version.

Also override `onNewIntent` and `onCreate` to forward notification route JSON through an event channel or cached method call for Flutter to consume after startup.

- [ ] **Step 4: Wire lifecycle forwarding**

Modify `HomeShell` in `main.dart` so `_HomeShellState` mixes in `WidgetsBindingObserver`.

In `initState`:

```dart
WidgetsBinding.instance.addObserver(this);
unawaited(context.read<AppModel>().startMonitorIfAllowed());
```

Add:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  final visible = state == AppLifecycleState.resumed;
  unawaited(context.read<AppModel>().setMonitorVisible(visible));
}
```

In `dispose`, remove the observer.

- [ ] **Step 5: Add AppModel monitor methods**

In `AppModel`, add fields:

```dart
static const _monitorEnabledKey = 'codexflow.monitor.enabled';
final AndroidMonitorBridge monitorBridge;
bool backgroundMonitoringEnabled = true;
bool foregroundServiceRunning = false;
bool notificationPermissionGranted = false;
String appVersionName = '0.2.0';
int appBuildNumber = 2;
```

Update the constructor to accept an optional bridge for tests:

```dart
AppModel(this._prefs, {AndroidMonitorBridge? monitorBridge})
    : monitorBridge = monitorBridge ?? AndroidMonitorBridge(),
      baseUrlString = _prefs.getString(_baseUrlKey) ?? 'http://127.0.0.1:4318';
```

In `bootstrap`, load the preference before the first monitor start:

```dart
backgroundMonitoringEnabled = _prefs.getBool(_monitorEnabledKey) ?? true;
```

Add methods with this control flow:

```dart
Future<void> refreshMonitorStatus() async {
  final status = await monitorBridge.getStatus();
  foregroundServiceRunning = status.running;
  notificationPermissionGranted = status.notificationPermissionGranted;
  appVersionName = status.versionName;
  appBuildNumber = status.buildNumber;
  notifyListeners();
}

Future<void> startMonitorIfAllowed() async {
  if (!backgroundMonitoringEnabled) {
    return;
  }
  await monitorBridge.start();
  await refreshMonitorStatus();
}

Future<void> stopMonitorFromSettings() async {
  backgroundMonitoringEnabled = false;
  await _prefs.setBool(_monitorEnabledKey, false);
  await monitorBridge.stop();
  await refreshMonitorStatus();
}

Future<void> enableMonitorFromSettings() async {
  backgroundMonitoringEnabled = true;
  await _prefs.setBool(_monitorEnabledKey, true);
  await monitorBridge.start();
  await refreshMonitorStatus();
}

Future<void> setMonitorVisible(bool visible) async {
  await monitorBridge.setVisible(visible);
}

Future<void> notifyMonitorAgentUrlChanged() async {
  await monitorBridge.agentUrlChanged(baseUrlString);
}

Future<void> requestMonitorNotifications() async {
  notificationPermissionGranted =
      await monitorBridge.requestNotificationPermission();
  await refreshMonitorStatus();
}
```

`stopMonitorFromSettings` must write the manual-stop marker through the MethodChannel before stopping the service. If native exposes it as part of `stopMonitor`, document in the method name and call order that marker write happens before service stop.

- [ ] **Step 6: Update settings UI**

In `SettingsScreen`, add a panel showing:

- `CodexFlow 0.2.0 (2)` from `AppModel`.
- background monitoring enabled/disabled.
- foreground service running/not running.
- notification permission granted/disabled.
- buttons for start, stop, and request notification permission.

When saving Agent URL, call:

```dart
await model.saveBaseUrl();
await model.notifyMonitorAgentUrlChanged();
await model.refreshDashboard();
```

- [ ] **Step 7: Verify and commit**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test test/android_monitor_bridge_test.dart
/home/lin/.local/share/flutter/bin/flutter test
/home/lin/.local/share/flutter/bin/flutter build apk --debug
cd ../..
git diff --check flutter/codexflow/lib flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/MainActivity.kt
git add flutter/codexflow/lib flutter/codexflow/test/android_monitor_bridge_test.dart flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/MainActivity.kt
git commit -m "feat: connect flutter app to android monitor"
```

---

## Task 7: Notification Tap Routing

**Files:**
- Create: `flutter/codexflow/lib/navigation/notification_target.dart`
- Modify: `flutter/codexflow/lib/main.dart`
- Modify: `flutter/codexflow/lib/state/app_model.dart`
- Test: `flutter/codexflow/test/notification_target_test.dart`

- [ ] **Step 1: Add route parser tests**

Create `notification_target_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codexflow_flutter/navigation/notification_target.dart';

void main() {
  test('parses manual approval target', () {
    final target = NotificationTarget.fromJsonString(
      '{"target":"approvals","approvalId":"req-1","sessionId":"s1"}',
    );

    expect(target.target, NotificationTargetKind.approvals);
    expect(target.approvalId, 'req-1');
    expect(target.sessionId, 's1');
  });

  test('invalid route falls back to dashboard', () {
    final target = NotificationTarget.fromJsonString('{bad json');
    expect(target.target, NotificationTargetKind.dashboard);
  });
}
```

- [ ] **Step 2: Add route model**

Create `notification_target.dart`:

```dart
import 'dart:convert';

enum NotificationTargetKind { dashboard, approvals, sessionDetail }

class NotificationTarget {
  const NotificationTarget({
    required this.target,
    this.approvalId = '',
    this.sessionId = '',
    this.turnId = '',
    this.status = '',
  });

  final NotificationTargetKind target;
  final String approvalId;
  final String sessionId;
  final String turnId;
  final String status;

  factory NotificationTarget.dashboard() =>
      const NotificationTarget(target: NotificationTargetKind.dashboard);

  static NotificationTarget fromJsonString(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) {
        return NotificationTarget.dashboard();
      }
      final rawTarget = decoded['target']?.toString() ?? 'dashboard';
      final kind = switch (rawTarget) {
        'approvals' => NotificationTargetKind.approvals,
        'sessionDetail' => NotificationTargetKind.sessionDetail,
        _ => NotificationTargetKind.dashboard,
      };
      return NotificationTarget(
        target: kind,
        approvalId: decoded['approvalId']?.toString() ?? '',
        sessionId: decoded['sessionId']?.toString() ?? '',
        turnId: decoded['turnId']?.toString() ?? '',
        status: decoded['status']?.toString() ?? '',
      );
    } catch (_) {
      return NotificationTarget.dashboard();
    }
  }
}
```

- [ ] **Step 3: Apply routes in app shell**

Add to `AppModel`:

```dart
NotificationTarget pendingNotificationTarget = NotificationTarget.dashboard();
int notificationRouteVersion = 0;

void applyNotificationTarget(NotificationTarget target) {
  pendingNotificationTarget = target;
  notificationRouteVersion += 1;
  notifyListeners();
}
```

In `HomeShell`, listen for route version changes and set `_index`:

- dashboard -> `0`
- approvals -> `1`
- sessionDetail -> `0`, then call `loadSession(sessionId)` and open existing session detail flow or show a notice if missing

Cold-start and warm-start use the same `applyNotificationTarget` method.

- [ ] **Step 4: Forward native notification intents to Flutter**

In `MainActivity.kt`, when receiving `ACTION_NOTIFICATION_ROUTE`, call:

```kotlin
methodChannel.invokeMethod("notificationRoute", routeJson)
```

If Flutter is not attached yet, cache the latest route string and return it from method `takeInitialNotificationRoute`.

In Flutter bridge, add:

```dart
void setNotificationRouteHandler(ValueChanged<NotificationTarget> handler)
Future<NotificationTarget?> takeInitialNotificationRoute()
```

- [ ] **Step 5: Verify and commit**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test test/notification_target_test.dart
/home/lin/.local/share/flutter/bin/flutter test
/home/lin/.local/share/flutter/bin/flutter build apk --debug
cd ../..
git diff --check flutter/codexflow/lib/navigation/notification_target.dart flutter/codexflow/lib/main.dart flutter/codexflow/lib/state/app_model.dart flutter/codexflow/test/notification_target_test.dart flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/MainActivity.kt
git add flutter/codexflow/lib/navigation/notification_target.dart flutter/codexflow/lib/main.dart flutter/codexflow/lib/state/app_model.dart flutter/codexflow/test/notification_target_test.dart flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/MainActivity.kt
git commit -m "feat: route android notification taps"
```

---

## Task 8: Release Build, Manifest Verification, and APK Publish

**Files:**
- Uses: `scripts/build-codexflow-android.sh`
- Output: `/home/lin/.local/share/codexflow-web/web/codexflow-android-v0.2.0.apk`
- Output: `/home/lin/.local/share/codexflow-web/web/codexflow-android-latest.apk`
- Output: `/home/lin/.local/share/codexflow-web/web/codexflow-android-latest.json`

- [ ] **Step 1: Run full Flutter verification**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter pub get
/home/lin/.local/share/flutter/bin/flutter test
/home/lin/.local/share/flutter/bin/flutter build apk --release
```

Expected: release APK builds at `flutter/codexflow/build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 2: Verify release signature**

Run:

```bash
/home/lin/Android/Sdk/build-tools/35.0.0/apksigner verify --print-certs flutter/codexflow/build/app/outputs/flutter-apk/app-release.apk
```

Expected: signer certificate subject contains `CN=CodexFlow, O=Local, L=Local, C=US`, not Android debug.

- [ ] **Step 3: Verify packaged manifest**

Run:

```bash
/home/lin/Android/Sdk/build-tools/35.0.0/aapt dump xmltree flutter/codexflow/build/app/outputs/flutter-apk/app-release.apk AndroidManifest.xml | \
  rg "POST_NOTIFICATIONS|FOREGROUND_SERVICE|FOREGROUND_SERVICE_SPECIAL_USE|specialUse|PROPERTY_SPECIAL_USE_FGS_SUBTYPE|singleTop|CodexFlowMonitorService"
```

Expected: all searched terms appear; no `dataSync` appears for `CodexFlowMonitorService`.

- [ ] **Step 4: Publish APK and metadata**

Run:

```bash
./scripts/build-codexflow-android.sh
ls -lh /home/lin/.local/share/codexflow-web/web/codexflow-android-v0.2.0.apk
ls -lh /home/lin/.local/share/codexflow-web/web/codexflow-android-latest.apk
cat /home/lin/.local/share/codexflow-web/web/codexflow-android-latest.json
sha256sum /home/lin/.local/share/codexflow-web/web/codexflow-android-v0.2.0.apk
```

Expected: JSON `sha256` matches the `sha256sum` output.

- [ ] **Step 5: Install on connected Android device**

Run:

```bash
/home/lin/Android/Sdk/platform-tools/adb devices
/home/lin/Android/Sdk/platform-tools/adb install -r /home/lin/.local/share/codexflow-web/web/codexflow-android-v0.2.0.apk
```

Expected: `Success`.

- [ ] **Step 6: Commit publish script or build fixes**

Generated APKs and JSON in `/home/lin/.local/share/codexflow-web/web` are local deployment artifacts and do not need to be committed. Commit only source changes:

```bash
git status --short
git diff --check
git add scripts/build-codexflow-android.sh flutter/codexflow
git commit -m "chore: publish signed android apk build"
```

---

## Task 9: Device Verification

**Files:**
- No source edits unless a verification failure identifies a bug.

- [ ] **Step 1: Verify Tailscale Agent URL**

On Android, set Agent URL:

```text
http://100.91.5.116:4318
```

Expected:

- settings shows Agent online
- dashboard shows total sessions and history list
- discovered sessions appear under history, not only in the total count

- [ ] **Step 2: Verify monitoring service controls**

In settings:

- start monitoring and confirm persistent notification appears
- stop monitoring and confirm persistent notification disappears
- start monitoring again and confirm first successful response is a fresh baseline with no backfill alerts

- [ ] **Step 3: Verify manual action alert**

Create or resume a managed Codex session that needs user approval. Expected:

- Android posts notification id `2000`
- notification has sound/vibration if permission is granted
- tapping opens approval screen
- if approval was already handled in Web, tapping opens approvals list with an in-app notice

- [ ] **Step 4: Verify turn result alert**

Run a managed task to completion and interrupt another managed turn. Expected:

- Android posts notification id `3000`
- notification has sound
- single-session alert opens session detail
- mixed-session batch alert opens dashboard
- same-session batch alert opens session detail

- [ ] **Step 5: Verify network failure backoff**

Temporarily set Agent URL to an unreachable host. Expected:

- persistent notification changes to offline
- no alert notification is emitted for connection failure
- poll attempts back off through 30, 60, 120 seconds
- restoring URL returns to online and success interval resets

- [ ] **Step 6: Verify permission-denied behavior**

Deny Android notification permission. Expected:

- foreground service still starts
- settings shows alert notifications disabled
- app does not crash
- alert notifications may not be visible until permission is granted

- [ ] **Step 7: Final source verification**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test
/home/lin/.local/share/flutter/bin/flutter build apk --release
cd ../..
git status --short
```

Expected: tests pass, release build succeeds, and remaining untracked files are known local artifacts only.

---

## Self-Review Checklist

- Spec goals covered: Flutter setup, signed APK, history list, foreground service, manual action alerts, turn result alerts, tap routing, version metadata.
- Android platform constraints covered: target SDK 35, min SDK 21, `specialUse`, immediate `startForeground()`, notification permission distinction, `singleTop`.
- State machine edge cases covered: fresh baseline fills `managedTurnState`, manual stop does not backfill, URL switch baselines, transition-final turn results batch with managed turn results, disappeared sessions do not alert, snapshot pruning.
- Rollout covered: release keystore, SHA256 metadata, latest APK alias, install command.
