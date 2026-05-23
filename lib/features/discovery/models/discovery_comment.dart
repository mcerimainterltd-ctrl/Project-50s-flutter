class DiscoveryComment {
  final String commentId;
  final String postId;
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String text;
  final DateTime ts;

  const DiscoveryComment({
    required this.commentId,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    required this.text,
    required this.ts,
  });

  factory DiscoveryComment.fromJson(Map<String, dynamic> j) => DiscoveryComment(
    commentId:    j['commentId']    as String,
    postId:       j['postId']       as String,
    authorId:     j['authorId']     as String,
    authorName:   j['authorName']   as String,
    authorAvatar: j['authorAvatar'] as String? ?? '',
    text:         j['text']         as String,
    ts:           DateTime.parse(j['ts'] as String),
  );
}
