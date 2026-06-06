---
inclusion: always
---

# PiliPala 平板横屏适配

## 项目目标
基于 guozhigq/pilipala v1.0.25 开源代码（Flutter/Dart），做平板横屏响应式适配。
分支：`tablet-adaptive`

## 技术栈
- Flutter 3.19.6, Dart >=3.0 <4.0
- 状态管理：GetX
- 网络：Dio
- 播放器：media_kit + auto_orientation
- 存储：Hive

## 关键设计决策
- 断点：compact(<600), medium(600-900), expanded(>900)
- C类网格页面：crossAxisCount 根据屏幕宽度动态计算
- B类视频页：横屏非全屏时左播放器+右评论分栏（Row flex:3+2）
- D类窄页面：maxWidth 600 居中限宽
- 移除 main.dart 竖屏锁定，允许自由旋转
- 视频全屏播放时保持现有逻辑不动

## 页面分类
- A(全屏播放): video/detail全屏, live_room全屏
- B(分栏): video/detail非全屏, member
- C(增列): rcmd, hot, live, rank, bangumi, dynamics, search_panel, history, later, member子页, fav, subscription
- D(限宽): setting, login, about, mine, search, blacklist, follow, fan, message, whisper, emote, danmaku, media

## 当前进度
- [x] 创建分支 tablet-adaptive
- [ ] 创建 adaptive.dart 工具
- [ ] 移除竖屏锁定
- [ ] C类改造
- [ ] B类分栏
- [ ] D类限宽
