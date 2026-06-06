<div align="center">
    <img width="200" height="200" src="https://github.com/guozhigq/pilipala/blob/main/assets/images/logo/logo_android.png">
</div>

<div align="center">
    <h1>PiliPala HD+</h1>
    <p>基于 PiliPala 的平板横屏适配版本</p>
</div>

## 改动说明

基于 [guozhigq/pilipala](https://github.com/guozhigq/pilipala) v1.0.25 开源代码。

### 平板适配
- 移除竖屏锁定，允许自由旋转
- 推荐/直播/番剧等网格页面：根据屏幕宽度动态调整列数
- 视频详情页：横屏时左右分栏（播放器 + 评论/简介）
- 设置/登录/关于等窄页面：居中限宽 600px
- 手势区域自动适配播放器实际宽度

### 网络优化
- mpv 播放器增加超时、缓存、断线重连参数
- CDN 规则扩展覆盖 B站原始存储节点
- 播放缓冲区 5MB → 32MB（直播 64MB）
- 缓冲不足时自动暂停等待（cache-pause）

### Bug 修复
- 修复内存泄漏（StreamSubscription 未 cancel）
- 修复 ScrollController / TabController 未正确释放
- 修复 build() 中的副作用导致潜在无限循环
- 修复横屏分栏时 ScrollController 未 attach 崩溃
- 修复合集面板/评论面板横屏时弹出高度异常
- 修复 floating (PiP) 双重 dispose 崩溃
- 修复 episodes 未初始化红屏错误
- 自定义倍速列表自动排序

### 已知问题
- >2x 倍速时可能音画不同步（mpv 架构限制：音频永远不等视频）
- 评论区显示"还没有评论"（B站 API 格式变更，需要更新解析逻辑）
- 一键三连接口 B 站风控（单独点赞/投币/收藏正常）

## 编译要求

- Flutter 3.22.3（不支持 3.41+）
- JDK 17（`gradle.properties` 中配置 `org.gradle.java.home`）
- Android SDK Build Tools 34.0.0+
- 需删除损坏的 Build Tools 30.0.3（如有）

## 编译命令

```bash
flutter build apk --release
```

APK 输出：`build/app/outputs/flutter-apk/app-release.apk`

## 功能

目前着重移动端 (Android、iOS)，暂时没有适配桌面端、Pad 端、手表端等

现有功能及[开发计划](https://github.com/users/guozhigq/projects/5)

- [x] 推荐视频列表 (app 端)
- [x] 最热视频列表
- [x] 热门直播
- [x] 番剧列表
- [x] 屏蔽黑名单内用户视频
- [x] 排行榜

- [x] 用户相关
  - [x] 粉丝、关注用户、拉黑用户查看
  - [x] 用户主页查看
  - [x] 关注/取关用户
  - [ ] 离线缓存
  - [x] 稍后再看
  - [x] 观看记录
  - [x] 我的收藏
  - [x] 黑名单管理 
  
- [x] 动态相关
  - [x] 全部、投稿、番剧分类查看
  - [x] 动态评论查看
  - [x] 动态评论回复功能
  - [x] 动态未读标记 

- [x] 视频播放相关
  - [x] 双击快进/快退
  - [x] 双击播放/暂停
  - [x] 垂直方向调节亮度/音量
  - [x] 垂直方向上滑全屏、下滑退出全屏
  - [x] 水平方向手势快进/快退
  - [x] 全屏方向设置
  - [x] 倍速选择/长按 2 倍速
  - [x] 硬件加速 (视机型而定)
  - [x] 画质选择 (高清画质未解锁)
  - [x] 音质选择 (视视频而定)
  - [x] 解码格式选择 (视视频而定)
  - [x] 弹幕
  - [x] 字幕
  - [x] 记忆播放
  - [x] 视频比例：高度/宽度适应、填充、包含等
  - [x] 视频快照
  - [x] 直播弹幕
     
- [x] 搜索相关
  - [x] 热搜
  - [x] 搜索历史
  - [x] 默认搜索词
  - [x] 投稿、番剧、直播间、用户搜索
  - [x] 视频搜索排序、按时长筛选
    
- [x] 视频详情页相关
  - [x] 视频选集 (分 p) 切换
  - [x] 点赞、投币、收藏/取消收藏
  - [x] 相关视频查看
  - [x] 评论用户身份标识
  - [x] 评论 (排序) 查看、二楼评论查看
  - [x] 主楼、二楼评论/表情回复功能
  - [x] 评论点赞
  - [x] 评论笔记图片查看、保存

- [x] 设置相关
  - [x] 画质、音质、解码方式预设      
  - [x] 图片质量设定
  - [x] 主题模式：亮色/暗色/跟随系统
  - [x] 震动反馈 (可选)
  - [x] 高帧率
  - [x] 自动全屏
- [ ] 等等

## 下载

可以通过右侧 Releases 进行下载或拉取代码到本地进行编译

### 从 F-Droid 安装

<a href="https://f-droid.org/packages/com.guozhigq.pilipala">
    <img src="https://fdroid.gitlab.io/artwork/badge/get-it-on-zh-cn.png"
    alt="Get it on F-Droid"
    height="80">
</a>

## 声明

此项目 (PiliPala) 是个人为了兴趣而开发, 仅用于学习和测试。
所用 API 皆从官方网站收集, 不提供任何破解内容。

感谢使用

## 致谢

- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)
- [media-kit](https://github.com/media-kit/media-kit)
- [dio](https://pub.dev/packages/dio)
- 等等
