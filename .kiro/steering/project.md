---
inclusion: always
---

# PiliPala HD+ 平板横屏适配

## 项目目标
基于 guozhigq/pilipala v1.0.25 开源代码（Flutter/Dart），做平板横屏响应式适配 + 网络优化 + 稳定性修复。
分支：`tablet-adaptive`
Fork：https://github.com/qq-24/pilipala/tree/tablet-adaptive

## 技术栈
- Flutter 3.22.3, Dart 3.4.4
- 状态管理：GetX
- 网络：Dio
- 播放器：media_kit (git master) + auto_orientation
- 存储：Hive
- 编译环境：JDK 17 (D:\jdk17\jdk-17.0.13+11), Gradle 7.5, AGP 7.2.0

## 编译要点
- gradle.properties 中 `org.gradle.java.home=D:\\jdk17\\jdk-17.0.13+11`
- android-36 平台与 JDK 17 不兼容，通过 afterEvaluate 强制子项目 compileSdk 34
- app/build.gradle compileSdkVersion 34
- `flutter build apk --release` 约 45-100 秒
- debug 签名用于 release（signingConfig signingConfigs.debug）

## 已完成的改动

### 平板横屏适配
- [x] lib/utils/adaptive.dart — 断点工具 + AdaptiveContainer
- [x] main.dart — 移除竖屏锁定
- [x] C类网格页面动态列数：rcmd, live, bangumi, member子页, search_panel
- [x] B类视频详情页横屏分栏：Row(flex:3 播放器 + flex:2 评论/简介)
- [x] D类页面限宽：setting, login, about, mine

### 网络优化
- [x] mpv: cache-pause + cache-pause-wait（缓冲不足暂停）
- [x] mpv: demuxer-max-bytes 50MiB, cache-secs 30, reconnect
- [x] bufferSize: 32MB（原5MB）, 直播 64MB
- [x] CDN 规则扩展覆盖 upos-sz-est* 节点
- [x] scaletempo2=max-speed=8（倍速音频拉伸）

### Bug 修复
- [x] _extendNestCtr 横屏未 attach 时 hasClients 检查
- [x] floating double-dispose 移除
- [x] tabCtr listener 正确 removeListener + dispose
- [x] StreamSubscription 全部保存并 cancel
- [x] fullScreenStatusListener 在 handlePlay 后补注册
- [x] build() 中副作用移除（enterFullScreen/exitFullScreen）
- [x] season_panel episodes 空列表 0/0 显示修复
- [x] late episodes 未初始化改为默认空列表
- [x] action_item 按钮固定宽度 56px（原用 Get.size.width 在分栏下溢出）
- [x] effectiveSheetHeight 横屏时返回正确高度
- [x] debugShowCheckedModeBanner: false
- [x] 自定义倍速列表排序（去重+sort）

### 手势修复
- [x] pl_player 双击/滑动区域用 LayoutBuilder 获取实际 widget 宽度
- [x] 亮度/音量灵敏度用 playerHeight 替代 screenWidth*9/16

## 待解决

### 高优先级
- [ ] 音画同步（>2x倍速）：MPD 方案失败已禁用，需调试 mpv 对本地 MPD+远程 URL 的 headers 传递。备选方案 A（轮询 avsync + seek）未实施
- [ ] 直播间横屏=全屏问题（应该像视频页一样做分栏）
- [ ] header_control 返回按钮强制竖屏（平板不该强制）

### 中优先级
- [ ] mainAxisExtent 用全屏宽度（rcmd/live/bangumi 卡片高度偏大 5-10%）
- [ ] 评论区/合集面板在分栏模式下的完整验证
- [ ] member 页面 B 类分栏改造
- [ ] mine 页面 NeverScrollableScrollPhysics 内容截断

### 低优先级/已知限制
- [ ] 一键三连接口 B 站风控（非代码问题）
- [ ] 评论区"还没有评论"（B站 API 返回格式变更，闭源版已修）
- [ ] widget 树旋转时评论滚动位置丢失

## 踩过的坑
- Flutter 3.41 与项目旧插件（floating, auto_orientation）不兼容，必须用 3.22.x
- Java 23 与 Gradle 7.5 不兼容，必须用 JDK 17
- android-36 的 android.jar 与 JDK 17 不兼容（java.lang 找不到）
- media_kit_libs_android_video 硬编码 compileSdk 36，需 afterEvaluate 覆盖
- Build Tools 30.0.3 损坏需删除
- dynamic_color 1.8.1 和 font_awesome_flutter 10.9.0 需锁定到兼容 3.22 的版本
- Flutter release 模式下 print 被 tree-shaken，调试需用 debug 或 developer.log
- mpv 的 cache-pause 对解码跟不上无效（只对网络缓冲不足有效）
- mpv 设计：音频永远不等视频，高倍速时视频丢帧音频继续走
- DASH MPD 本地文件方案：mpv 加载 MPD 内的远程 URL 时不继承 http-header-fields（需进一步调试）
