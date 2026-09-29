// ===== 类型漂移安全转换（B站字段 String<->num 漂移防御） =====
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

class FollowUpModel {
  FollowUpModel({
    this.liveUsers,
    this.upList,
    this.liveList,
    this.myInfo,
  });

  LiveUsers? liveUsers;
  List<UpItem>? upList;
  List<LiveUserItem>? liveList;
  MyInfo? myInfo;

  FollowUpModel.fromJson(Map<String, dynamic> json) {
    liveUsers = json['live_users'] != null
        ? LiveUsers.fromJson(json['live_users'])
        : null;
    liveList = json['live_users'] != null
        ? json['live_users']['items']
            .map<LiveUserItem>((e) => LiveUserItem.fromJson(e))
            .toList()
        : [];
    upList = json['up_list'] != null
        ? json['up_list'].map<UpItem>((e) => UpItem.fromJson(e)).toList()
        : [];
    myInfo = json['my_info'] != null ? MyInfo.fromJson(json['my_info']) : null;
  }
}

class LiveUsers {
  LiveUsers({
    this.count,
    this.group,
    this.items,
  });

  int? count;
  String? group;
  List<LiveUserItem>? items;

  LiveUsers.fromJson(Map<String, dynamic> json) {
    count = asInt(json['count']);
    group = asStr(json['group']);
    items = json['items']
        .map<LiveUserItem>((e) => LiveUserItem.fromJson(e))
        .toList();
  }
}

class LiveUserItem {
  LiveUserItem({
    this.face,
    this.isReserveRecall,
    this.jumpUrl,
    this.mid,
    this.roomId,
    this.title,
    this.uname,
  });

  String? face;
  bool? isReserveRecall;
  String? jumpUrl;
  int? mid;
  int? roomId;
  String? title;
  String? uname;
  bool hasUpdate = false;
  String type = 'live';

  LiveUserItem.fromJson(Map<String, dynamic> json) {
    face = asStr(json['face']);
    isReserveRecall = asBool(json['is_reserve_recall']);
    jumpUrl = asStr(json['jump_url']);
    mid = asInt(json['mid']);
    roomId = asInt(json['room_id']);
    title = asStr(json['title']);
    uname = asStr(json['uname']);
  }
}

class UpItem {
  UpItem({
    this.face,
    this.hasUpdate,
    this.isReserveRecall,
    this.mid,
    this.uname,
  });

  String? face;
  bool? hasUpdate;
  bool? isReserveRecall;
  int? mid;
  String? uname;
  String type = 'up';

  UpItem.fromJson(Map<String, dynamic> json) {
    face = asStr(json['face']);
    hasUpdate = asBool(json['has_update']);
    isReserveRecall = asBool(json['is_reserve_recall']);
    mid = asInt(json['mid']);
    uname = asStr(json['uname']);
  }
}

class MyInfo {
  MyInfo({
    this.face,
    this.mid,
    this.name,
  });

  String? face;
  int? mid;
  String? name;

  MyInfo.fromJson(Map<String, dynamic> json) {
    face = asStr(json['face']);
    mid = asInt(json['mid']);
    name = asStr(json['name']);
  }
}