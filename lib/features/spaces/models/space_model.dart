class SpaceMember {
  final String xameId, role, displayName, avatar;
  final bool isRegistered;
  SpaceMember({required this.xameId, required this.role, required this.displayName, required this.avatar, required this.isRegistered});
  factory SpaceMember.fromJson(Map<String, dynamic> j) => SpaceMember(
    xameId: j['xameId'] ?? '', role: j['role'] ?? 'MEMBER',
    displayName: j['displayName'] ?? '', avatar: j['avatar'] ?? '',
    isRegistered: j['isRegistered'] ?? true);
}

class SpaceModel {
  final String spaceSlug, name, description, avatar, coverImage, archetype, creatorId, visibility;
  final bool allowGuestPosting;
  final int memberCount, messageCount;
  final List<SpaceMember> members;
  final String? pinnedMessageId;
  SpaceModel({required this.spaceSlug, required this.name, required this.description,
    required this.avatar, required this.coverImage, required this.archetype,
    required this.creatorId, required this.visibility, required this.allowGuestPosting,
    required this.memberCount, required this.messageCount, required this.members,
    this.pinnedMessageId});
  factory SpaceModel.fromJson(Map<String, dynamic> j) => SpaceModel(
    spaceSlug: j['spaceSlug'] ?? '', name: j['name'] ?? '',
    description: j['description'] ?? '', avatar: j['avatar'] ?? '',
    coverImage: j['coverImage'] ?? '', archetype: j['archetype'] ?? 'community',
    creatorId: j['creatorId'] ?? '',
    visibility: j['accessControl']?['visibility'] ?? 'public_link',
    allowGuestPosting: j['accessControl']?['allowGuestPosting'] ?? true,
    memberCount: j['stats']?['memberCount'] ?? 0,
    messageCount: j['stats']?['messageCount'] ?? 0,
    members: (j['members'] as List? ?? []).map((m) => SpaceMember.fromJson(m)).toList(),
    pinnedMessageId: j['pinnedMessageId']);
}

class SpaceMessage {
  final String id, spaceSlug, senderId, senderName, senderAvatar, text, mediaUrl, mediaType, fileName;
  final bool isGuest, deleted;
  final String? replyToId, replyToText;
  final List<Map<String, dynamic>> reactions;
  final DateTime createdAt;
  SpaceMessage({required this.id, required this.spaceSlug, required this.senderId,
    required this.senderName, required this.senderAvatar, required this.isGuest,
    required this.text, required this.mediaUrl, required this.mediaType,
    required this.fileName, this.replyToId, this.replyToText,
    required this.reactions, required this.createdAt, required this.deleted});
  factory SpaceMessage.fromJson(Map<String, dynamic> j) => SpaceMessage(
    id: j['_id'] ?? '', spaceSlug: j['spaceSlug'] ?? '',
    senderId: j['senderId'] ?? '', senderName: j['senderName'] ?? 'Guest',
    senderAvatar: j['senderAvatar'] ?? '', isGuest: j['isGuest'] ?? false,
    text: j['text'] ?? '', mediaUrl: j['mediaUrl'] ?? '',
    mediaType: j['mediaType'] ?? '', fileName: j['fileName'] ?? '',
    replyToId: j['replyToId'], replyToText: j['replyToText'],
    reactions: List<Map<String, dynamic>>.from(j['reactions'] ?? []),
    createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
    deleted: j['deleted'] ?? false);
}
