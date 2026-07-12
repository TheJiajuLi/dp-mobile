# Firebase Crashlytics 激活清单

> 代码脚手架已在 `main.dart` 接好（`_initCrashlytics()`），依赖已在 `pubspec.yaml`。
> 现在缺的只是 **Firebase 项目 + 配置文件**。以下步骤做完，崩溃上报即自动生效，
> 除第 4 步动一行 `main.dart` 外，其余都是配置/命令，不改业务代码。
>
> 需要：一台能登录 Firebase 账号的机器（有 Console 权限）。

---

## 0. 装 CLI（一次性）

```bash
# Firebase CLI
npm install -g firebase-tools
firebase login

# FlutterFire CLI
dart pub global activate flutterfire_cli
# 确保 ~/.pub-cache/bin 在 PATH 里（zsh）：
# echo 'export PATH="$PATH":"$HOME/.pub-cache/bin"' >> ~/.zshrc && source ~/.zshrc
```

## 1. 建 Firebase 项目

- 打开 https://console.firebase.google.com → 「添加项目」
- 项目名随意（例如 `dreamingpolar`）；Google Analytics 可开可关（Crashlytics 不强依赖）

## 2. 用 flutterfire 一键接入（生成 firebase_options.dart + 注册 App）

```bash
cd ~/Desktop/dp-flutter-2
flutterfire configure
```

交互里：
- 选上一步建的 Firebase 项目
- 平台勾选 **ios** 和 **android**（这个仓库是 iPhone 版 Runner；iPad 版
  `RunnerHD` 如果也要上报，另跑一次或手动加对应 App）
- iOS bundle id / Android applicationId 用它自动探测的即可

产物：
- `lib/firebase_options.dart`（**新增**，`DefaultFirebaseOptions.currentPlatform`）
- `ios/Runner/GoogleService-Info.plist`（自动放好）
- `android/app/google-services.json`（自动放好）
- 自动改好 Android 的 gradle 插件声明

## 3. 确认原生配置文件到位

```bash
ls ios/Runner/GoogleService-Info.plist
ls android/app/google-services.json
```

两个都在就对了。若 iOS 的 plist 没被加进 Xcode target，用 Xcode 打开
`ios/Runner.xcworkspace`，把 `GoogleService-Info.plist` 拖进 Runner target
（勾选 "Copy items if needed"）。

## 4. 改 main.dart 一行：用生成的 options 初始化

当前（脚手架，无 options，缺配置会被 catch）：

```dart
// lib/main.dart，_initCrashlytics() 里
await Firebase.initializeApp();
```

改成：

```dart
// 文件顶部加一行 import：
import 'firebase_options.dart';

// _initCrashlytics() 里：
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

> `try/catch` 保留不动 —— 配置齐了就走成功分支接管错误上报，出问题也不崩启动。

然后：

```bash
flutter pub get
```

## 5.（发布构建符号化，推荐）Crashlytics Gradle / dSYM

Debug 下 Dart 层崩溃已能上报；**release/混淆构建**要拿到可读堆栈还需符号上传：

**Android** — `flutterfire configure` 通常已加 `com.google.gms.google-services`；
再补 Crashlytics 插件：

- `android/settings.gradle`（plugins 块）加：
  ```gradle
  id "com.google.firebase.crashlytics" version "3.0.2" apply false
  ```
- `android/app/build.gradle`（plugins 块）加：
  ```gradle
  id "com.google.firebase.crashlytics"
  ```

**iOS** — 在 Xcode → Runner target → Build Phases 加一个 Run Script（放在
"Thin Binary" 之后）上传 dSYM：
```
"${PODS_ROOT}/FirebaseCrashlytics/run"
```
Input Files 里加：
```
${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}
$(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)
```
并把 Build Settings 的 `Debug Information Format` 设为 `DWARF with dSYM File`
（Debug 和 Release 都设）。

## 6. 验证上报

在任意按钮临时塞一行强制崩溃，跑 **release/profile**（debug 有时被 Crashlytics
延迟收集）：

```dart
FirebaseCrashlytics.instance.crash(); // 测试用，验证完删掉
```

崩溃后**重启一次 App**（Crashlytics 是下次启动时上报的），几分钟内到
Firebase Console → Crashlytics 看是否出现这条崩溃。看到即接入成功。

## 7. 清理

- 删掉第 6 步的 `FirebaseCrashlytics.instance.crash();`
- 可选：`main.dart` 里那段"临时诊断用 FlutterError.onError"（打印 semantics
  断言堆栈那段）排查完后可删；删了之后 `_initCrashlytics()` 成功分支会成为
  唯一的 `FlutterError.onError`

---

## 附：文件清单（做完后应有的改动）

| 文件 | 状态 | 说明 |
|---|---|---|
| `lib/firebase_options.dart` | 新增 | flutterfire 生成 |
| `ios/Runner/GoogleService-Info.plist` | 新增 | iOS 配置 |
| `android/app/google-services.json` | 新增 | Android 配置 |
| `lib/main.dart` | 改 | `initializeApp(options: ...)` + import |
| `android/settings.gradle` / `android/app/build.gradle` | 改 | Crashlytics 插件（第 5 步，可选） |
| `ios/Runner.xcodeproj` | 改 | dSYM 上传 Run Script（第 5 步，可选） |
