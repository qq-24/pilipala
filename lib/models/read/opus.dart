// ===== 类型漂移安全转换（B站字段 String<->num 漂移防御） =====
// 与 lib/models/dynamics/result.dart 同一套：opus 接口的 basic.uid 实际是 String，
// 而字段声明是 int?，直接赋值会在 fromJson 里抛 'is not a subtype of'，整页空白。
int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double asDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

String? asStr(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

bool? asBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return null;
}

Map<String, dynamic>? asMap(dynamic v) => v is Map
    ? Map<String, dynamic>.from(v)
    : null;

List<Map<String, dynamic>> asMapList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

class OpusDataModel {
  OpusDataModel({
    this.id,
    this.detail,
    this.type,
    this.theme,
    this.themeMode,
  });

  String? id;
  OpusDetailDataModel? detail;
  int? type;
  String? theme;
  String? themeMode;

  OpusDataModel.fromJson(Map<String, dynamic> json) {
    id = asStr(json['id'] ?? json['id_str']);
    final detailJson = asMap(json['detail']);
    detail = detailJson != null ? OpusDetailDataModel.fromJson(detailJson) : null;
    type = asInt(json['type']);
    theme = asStr(json['theme']);
    themeMode = asStr(json['themeMode']);
  }
}

class OpusDetailDataModel {
  OpusDetailDataModel({
    this.basic,
    this.idStr,
    this.modules,
    this.type,
  });

  Basic? basic;
  String? idStr;
  List<OpusModuleDataModel>? modules;
  int? type;

  OpusDetailDataModel.fromJson(Map<String, dynamic> json) {
    final basicJson = asMap(json['basic']);
    basic = basicJson != null ? Basic.fromJson(basicJson) : null;
    idStr = asStr(json['id_str']);
    final list = asMapList(json['modules']);
    if (list.isNotEmpty) {
      modules = list.map((v) => OpusModuleDataModel.fromJson(v)).toList();
    }
    type = asInt(json['type']);
  }
}

class Basic {
  Basic({
    this.commentIdStr,
    this.commentType,
    this.ridStr,
    this.title,
    this.uid,
  });

  String? commentIdStr;
  int? commentType;
  String? ridStr;
  String? title;
  int? uid;

  Basic.fromJson(Map<String, dynamic> json) {
    commentIdStr = asStr(json['comment_id_str']);
    commentType = asInt(json['comment_type']);
    ridStr = asStr(json['rid_str']);
    title = asStr(json['title']);
    uid = asInt(json['uid']);
  }
}

class OpusModuleDataModel {
  OpusModuleDataModel({
    this.moduleTitle,
    this.moduleAuthor,
    this.moduleContent,
    this.moduleExtend,
    this.moduleBottom,
    this.moduleStat,
  });

  ModuleTop? moduleTop;
  ModuleTitle? moduleTitle;
  ModuleAuthor? moduleAuthor;
  ModuleContent? moduleContent;
  ModuleExtend? moduleExtend;
  ModuleBottom? moduleBottom;
  ModuleStat? moduleStat;

  OpusModuleDataModel.fromJson(Map<String, dynamic> json) {
    final topJson = asMap(json['module_top']);
    moduleTop = topJson != null ? ModuleTop.fromJson(topJson) : null;
    final titleJson = asMap(json['module_title']);
    moduleTitle =
        titleJson != null ? ModuleTitle.fromJson(titleJson) : null;
    final authorJson = asMap(json['module_author']);
    moduleAuthor =
        authorJson != null ? ModuleAuthor.fromJson(authorJson) : null;
    final contentJson = asMap(json['module_content']);
    moduleContent =
        contentJson != null ? ModuleContent.fromJson(contentJson) : null;
    final extendJson = asMap(json['module_extend']);
    moduleExtend =
        extendJson != null ? ModuleExtend.fromJson(extendJson) : null;
    final bottomJson = asMap(json['module_bottom']);
    moduleBottom =
        bottomJson != null ? ModuleBottom.fromJson(bottomJson) : null;
    final statJson = asMap(json['module_stat']);
    moduleStat = statJson != null ? ModuleStat.fromJson(statJson) : null;
  }
}

class ModuleTop {
  ModuleTop({
    this.type,
    this.video,
  });

  int? type;
  Map? video;

  ModuleTop.fromJson(Map<String, dynamic> json) {
    type = asInt(json['type']);
    video = json['video'] is Map ? json['video'] as Map : null;
  }
}

class ModuleTitle {
  ModuleTitle({
    this.text,
  });

  String? text;

  ModuleTitle.fromJson(Map<String, dynamic> json) {
    text = asStr(json['text']);
  }
}

class ModuleAuthor {
  ModuleAuthor({
    this.face,
    this.mid,
    this.name,
    this.pubTime,
  });

  String? face;
  int? mid;
  String? name;
  String? pubTime;

  ModuleAuthor.fromJson(Map<String, dynamic> json) {
    final avatar = asMap(json['avatar']);
    face = asStr(json['face'] ?? avatar?['face_url'] ?? avatar?['src']);
    mid = asInt(json['mid'] ?? avatar?['mid']);
    name = asStr(json['name'] ?? avatar?['name']);
    pubTime = asStr(json['pub_time']);
  }
}

class ModuleContent {
  ModuleContent({
    this.paragraphs,
    this.moduleType,
  });

  List<ModuleParagraph>? paragraphs;
  String? moduleType;

  ModuleContent.fromJson(Map<String, dynamic> json) {
    final list = asMapList(json['paragraphs']);
    if (list.isNotEmpty) {
      paragraphs = list.map((v) => ModuleParagraph.fromJson(v)).toList();
    }
    moduleType = asStr(json['module_type']);
  }
}

class ModuleParagraph {
  ModuleParagraph({
    this.align,
    this.paraType,
    this.pic,
    this.text,
  });

  // 0 左对齐  1 居中  2 右对齐
  int? align;
  int? paraType;
  Pics? pic;
  ModuleParagraphText? text;
  LinkCard? linkCard;

  ModuleParagraph.fromJson(Map<String, dynamic> json) {
    align = asInt(json['align']);
    paraType = json['para_type'] == null && json['link_card'] != null
        ? 3
        : asInt(json['para_type']);
    final picJson = asMap(json['pic']);
    pic = picJson != null ? Pics.fromJson(picJson) : null;
    final textJson = asMap(json['text']);
    text = textJson != null ? ModuleParagraphText.fromJson(textJson) : null;
    final cardJson = asMap(json['link_card']);
    linkCard = cardJson != null ? LinkCard.fromJson(cardJson) : null;
  }
}

class Pics {
  Pics({
    this.pics,
    this.style,
  });

  List<Pic>? pics;
  int? style;

  Pics.fromJson(Map<String, dynamic> json) {
    final list = asMapList(json['pics']);
    if (list.isNotEmpty) {
      pics = list.map((v) => Pic.fromJson(v)).toList();
    }
    style = asInt(json['style']);
  }
}

class Pic {
  Pic({
    this.height,
    this.size,
    this.url,
    this.width,
    this.aspectRatio,
    this.scale,
  });

  int? height;
  double? size;
  String? url;
  int? width;
  double? aspectRatio;
  double? scale;

  Pic.fromJson(Map<String, dynamic> json) {
    height = asInt(json['height']);
    size = asDouble(json['size']);
    url = asStr(json['url']);
    width = asInt(json['width']);
    // 宽高缺失或为 0 时不做除法，否则整个详情解析会直接抛异常
    if (height != null && width != null && height! > 0) {
      aspectRatio = width! / height!;
      scale = customDivision(width!, height);
    } else {
      aspectRatio = 0;
      scale = 0;
    }
  }
}

class LinkCard {
  LinkCard({
    this.cover,
    this.descSecond,
    this.duration,
    this.jumpUrl,
    this.title,
  });

  String? cover;
  String? descSecond;
  String? duration;
  String? jumpUrl;
  String? title;

  LinkCard.fromJson(Map<String, dynamic> json) {
    final card = asMap(json['card']) ?? json;
    cover = asStr(card['cover']);
    descSecond = asStr(card['desc_second']);
    duration = asStr(card['duration']);
    jumpUrl = asStr(card['jump_url']);
    title = asStr(card['title']);
  }
}

class ModuleParagraphText {
  ModuleParagraphText({
    this.nodes,
  });

  List<ModuleParagraphTextNode>? nodes;

  ModuleParagraphText.fromJson(Map<String, dynamic> json) {
    final list = asMapList(json['nodes']);
    if (list.isNotEmpty) {
      nodes = list.map((v) => ModuleParagraphTextNode.fromJson(v)).toList();
    }
  }
}

class ModuleParagraphTextNode {
  ModuleParagraphTextNode({
    this.type,
    this.nodeType,
    this.word,
  });

  String? type;
  int? nodeType;
  ModuleParagraphTextNodeWord? word;

  ModuleParagraphTextNode.fromJson(Map<String, dynamic> json) {
    type = asStr(json['type']);
    nodeType = asInt(json['node_type']);
    final wordJson = asMap(json['word']);
    word = wordJson != null
        ? ModuleParagraphTextNodeWord.fromJson(wordJson)
        : null;
  }
}

class ModuleParagraphTextNodeWord {
  ModuleParagraphTextNodeWord({
    this.color,
    this.fontSize,
    this.style,
    this.words,
  });

  String? color;
  int? fontSize;
  ModuleParagraphTextNodeWordStyle? style;
  String? words;

  ModuleParagraphTextNodeWord.fromJson(Map<String, dynamic> json) {
    color = asStr(json['color']);
    fontSize = asInt(json['font_size']);
    final styleJson = asMap(json['style']);
    style = styleJson != null
        ? ModuleParagraphTextNodeWordStyle.fromJson(styleJson)
        : null;
    words = asStr(json['words']);
  }
}

class ModuleParagraphTextNodeWordStyle {
  ModuleParagraphTextNodeWordStyle({
    this.bold,
  });

  bool? bold;

  ModuleParagraphTextNodeWordStyle.fromJson(Map<String, dynamic> json) {
    bold = asBool(json['bold']);
  }
}

class ModuleExtend {
  ModuleExtend({
    this.items,
  });

  List<ModuleExtendItem>? items;

  ModuleExtend.fromJson(Map<String, dynamic> json) {
    final list = asMapList(json['items']);
    if (list.isNotEmpty) {
      items = list.map((v) => ModuleExtendItem.fromJson(v)).toList();
    }
  }
}

class ModuleExtendItem {
  ModuleExtendItem({
    this.bizId,
    this.bizType,
    this.icon,
    this.jumpUrl,
    this.text,
  });

  dynamic bizId;
  int? bizType;
  dynamic icon;
  String? jumpUrl;
  String? text;

  ModuleExtendItem.fromJson(Map<String, dynamic> json) {
    bizId = json['biz_id'];
    bizType = asInt(json['biz_type']);
    icon = json['icon'];
    jumpUrl = asStr(json['jump_url']);
    text = asStr(json['text']);
  }
}

class ModuleBottom {
  ModuleBottom({
    this.shareInfo,
  });

  ShareInfo? shareInfo;

  ModuleBottom.fromJson(Map<String, dynamic> json) {
    final shareJson = asMap(json['share_info']);
    shareInfo = shareJson != null ? ShareInfo.fromJson(shareJson) : null;
  }
}

class ShareInfo {
  ShareInfo({
    this.pic,
    this.summary,
    this.title,
  });

  String? pic;
  String? summary;
  String? title;

  ShareInfo.fromJson(Map<String, dynamic> json) {
    pic = asStr(json['pic']);
    summary = asStr(json['summary']);
    title = asStr(json['title']);
  }
}

class ModuleStat {
  ModuleStat({
    this.coin,
    this.comment,
    this.favorite,
    this.forward,
    this.like,
  });

  StatItem? coin;
  StatItem? comment;
  StatItem? favorite;
  StatItem? forward;
  StatItem? like;

  ModuleStat.fromJson(Map<String, dynamic> json) {
    final coinJson = asMap(json['coin']);
    coin = coinJson != null ? StatItem.fromJson(coinJson) : null;
    final commentJson = asMap(json['comment']);
    comment = commentJson != null ? StatItem.fromJson(commentJson) : null;
    final favoriteJson = asMap(json['favorite']);
    favorite = favoriteJson != null ? StatItem.fromJson(favoriteJson) : null;
    final forwardJson = asMap(json['forward']);
    forward = forwardJson != null ? StatItem.fromJson(forwardJson) : null;
    final likeJson = asMap(json['like']);
    like = likeJson != null ? StatItem.fromJson(likeJson) : null;
  }
}

class StatItem {
  StatItem({
    this.count,
    this.forbidden,
    this.status,
  });

  int? count;
  bool? forbidden;
  bool? status;

  StatItem.fromJson(Map<String, dynamic> json) {
    count = asInt(json['count']);
    forbidden = asBool(json['forbidden']);
    status = asBool(json['status']);
  }
}

double customDivision(dynamic a, dynamic b) {
  final num x = a is num ? a : num.tryParse('$a') ?? 0;
  final num y = b is num ? b : num.tryParse('$b') ?? 0;
  if (y == 0) return 0;
  final double result = x / y;
  return result < 1 ? result : 1.0;
}
