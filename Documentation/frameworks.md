# 音频引擎框架集成与更新指南

OpenMeow 当前依赖两个本地语音引擎：**sherpa-onnx**（C++ 库，提供 ASR + TTS）和 **speech-swift**（Swift Package，提供 Qwen3 ASR/TTS）。两者集成方式完全不同，更新方式也不同。

> 备注：仓库里另有 `opus.xcframework` 和 `lame.xcframework` 两个音频**编解码器**——它们由 `Scripts/download-opus.sh`、`Scripts/download-lame.sh` 从源码本地构建（不是下载 release），与本文档讨论的两个**引擎**性质不同，不在本文范围内。

---

## 速查对比

| 维度 | sherpa-onnx | speech-swift |
|---|---|---|
| 类型 | C/C++ 静态库（含 onnxruntime） | Swift Package |
| 集成方式 | 手动 xcframework + Xcode `OTHER_LDFLAGS` 链接 | Swift Package Manager（Xcode 自动管理） |
| 当前钉版 | `v1.12.34` | `0.0.7`（`upToNextMinorVersion`） |
| 仓库位置 | `Frameworks/sherpa-onnx.xcframework`（94 MB） | `~/Library/Developer/Xcode/DerivedData/...`（Xcode 缓存） |
| 锁定文件 | `Scripts/download-sherpa-onnx.sh` 第 5 行 | `openmeow.xcodeproj/.../Package.resolved` |
| 更新方式 | 编辑脚本 → 删旧 xcframework → 重跑脚本 | Xcode 菜单 / `xcodebuild -resolvePackageDependencies` |
| 是否下载预编译包 | ✅ 是（GitHub releases） | ❌ 否（SPM 拉源码 + 本机编译） |

---

## sherpa-onnx：下载预编译 xcframework

### 来源

[`k2-fsa/sherpa-onnx`](https://github.com/k2-fsa/sherpa-onnx) 在每个 release 都会发布预编译产物。本项目用到两个 asset（以 v1.12.34 为例）：

- `sherpa-onnx-v1.12.34-macos-xcframework-static.tar.bz2` — **xcframework 主体**（含 `libsherpa-onnx.a` 静态库 + 头文件）
- `sherpa-onnx-v1.12.34-osx-arm64-static-lib.tar.bz2` — 仅取其中的 `libonnxruntime.a`，复制进上述 xcframework 内

合并后形成 `Frameworks/sherpa-onnx.xcframework/macos-arm64_x86_64/` 目录，里面同时包含两个静态库。

### 自动化脚本

`Scripts/download-sherpa-onnx.sh` 已封装完整流程：

```bash
./Scripts/download-sherpa-onnx.sh
```

脚本逻辑：
1. 如果 `Frameworks/sherpa-onnx.xcframework` 已存在 → 直接退出（幂等）
2. 否则：到临时目录下载两个 tarball → 解压 → 复制 xcframework 到 `Frameworks/` → 把 `libonnxruntime.a` 塞进 xcframework 内 → 清理临时目录

### 更新到新版本

假设要升级到 `v1.12.40`：

```bash
# 1. 编辑脚本顶部的版本号
sed -i '' 's/SHERPA_VERSION="v1.12.34"/SHERPA_VERSION="v1.12.40"/' Scripts/download-sherpa-onnx.sh

# 2. 删除旧 xcframework（脚本是幂等的，必须先删）
rm -rf Frameworks/sherpa-onnx.xcframework

# 3. 跑脚本下载新版本
./Scripts/download-sherpa-onnx.sh

# 4. 编译验证
xcodebuild -project openmeow/openmeow.xcodeproj -scheme openmeow \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

### 升级前先确认 release 资产存在

新版本可能改动资产命名约定，升级前用 `gh` CLI 验证：

```bash
gh release view v1.12.40 --repo k2-fsa/sherpa-onnx --json assets \
  | python3 -c "import sys, json; [print(a['name']) for a in json.load(sys.stdin)['assets'] if 'macos' in a['name'].lower() or 'osx' in a['name'].lower()]"
```

应该看到上面提到的两个文件名（仅版本号变化）。如果命名约定变了，需同步修改脚本里的 `XCFW_TAR` / `STATIC_TAR` 模板。

### Xcode 工程的硬编码引用

`openmeow.xcodeproj/project.pbxproj` 里：
- `HEADER_SEARCH_PATHS`：`$(PROJECT_DIR)/../Frameworks/sherpa-onnx.xcframework/macos-arm64_x86_64/Headers`
- `LIBRARY_SEARCH_PATHS`：`$(PROJECT_DIR)/../Frameworks/sherpa-onnx.xcframework/macos-arm64_x86_64`
- `OTHER_LDFLAGS`：`-lsherpa-onnx -lonnxruntime`
- 编译条件宏：`SHERPA_ONNX_AVAILABLE`（Swift 端 `#if SHERPA_ONNX_AVAILABLE` 用到）

**只要保持目录结构 `Frameworks/sherpa-onnx.xcframework/macos-arm64_x86_64/`，升版无需改 Xcode 工程**——上述路径都是相对、版本无关的。

---

## speech-swift：Swift Package Manager

### 集成方式

通过 SPM 引入 [`soniqo/speech-swift`](https://github.com/soniqo/speech-swift)，提供 `Qwen3TTS` 和 `Qwen3ASR` 两个 product。Xcode 工程里的声明：

```
repositoryURL = "https://github.com/soniqo/speech-swift.git"
requirement.kind = upToNextMinorVersion
requirement.minimumVersion = 0.0.7
```

实际钉扎在 `openmeow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`：

```json
{
  "identity": "speech-swift",
  "version": "0.0.7",
  "revision": "433b9106b49083fdf4adacf2314dcdeebd767b8b"
}
```

源码会被 SPM 拉到 `~/Library/Developer/Xcode/DerivedData/openmeow-*/SourcePackages/checkouts/speech-swift/`，由 Xcode 自动编译。仓库里**不存在** speech-swift 的二进制产物。

### 更新到新版本

#### 方式 A：放宽版本约束（自动升级到下一版本）

由于 `requirement.kind = upToNextMinorVersion` 从 `0.0.7` 起，**Xcode 不会自动跨小版本**（0.0.x 内升 patch 都要改约束，因为 SemVer 在 0.x 时 minor 等同于 major）。要升到 `0.0.8` 或 `0.1.0`，先改 pbxproj 的 `minimumVersion`，再让 SPM 重解析：

```bash
# 命令行触发解析
xcodebuild -resolvePackageDependencies \
  -project openmeow/openmeow.xcodeproj -scheme openmeow
```

#### 方式 B：通过 Xcode UI

`File → Packages → Update to Latest Package Versions`，让 Xcode 在当前约束范围内拉最新版。

#### 方式 C：彻底清缓存（最稳）

如果 Package.resolved 与源不一致或解析失败：

```bash
# 清 Xcode 包缓存
rm -rf ~/Library/Developer/Xcode/DerivedData/openmeow-*
rm -rf ~/Library/Caches/org.swift.swiftpm

# 重新解析
xcodebuild -resolvePackageDependencies \
  -project openmeow/openmeow.xcodeproj -scheme openmeow
```

### 锁定到特定提交

如需绕开 release 标签直接钉某个提交（比如临时打补丁），把 pbxproj 里的 `XCRemoteSwiftPackageReference` 配置改为：

```
requirement.kind = revision
requirement.revision = "<commit-sha>"
```

注意：这会让 `Package.resolved` 失去版本号语义，长期使用会让排错变难。

---

## 通用诊断

### 验证当前实际生效的版本

```bash
# sherpa-onnx 钉扎版本
grep '^SHERPA_VERSION=' Scripts/download-sherpa-onnx.sh

# speech-swift 实际解析版本
grep -A 5 'speech-swift' \
  openmeow/openmeow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

### 一次性重建全部依赖（常用于换机器或 CI）

```bash
# 1. 拉 sherpa-onnx xcframework（幂等，已存在则跳过）
./Scripts/download-sherpa-onnx.sh

# 2. 拉编解码器（仅在缺失时本地构建）
./Scripts/download-opus.sh
./Scripts/download-lame.sh

# 3. SPM 解析（含 speech-swift 与 Hummingbird 等）
xcodebuild -resolvePackageDependencies \
  -project openmeow/openmeow.xcodeproj -scheme openmeow

# 4. 完整构建
xcodebuild -project openmeow/openmeow.xcodeproj -scheme openmeow \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

### 体积参考

| Framework | 体积 | 类型 |
|---|---:|---|
| `sherpa-onnx.xcframework` | 94 MB | 静态库（含 onnxruntime 59 MB） |
| `opus.xcframework` | 1.6 MB | 静态库（libopus + libogg） |
| `lame.xcframework` | 416 KB | 动态库（LGPL，必须动态链接） |

speech-swift 不计入仓库体积（SPM 缓存在用户目录）。
