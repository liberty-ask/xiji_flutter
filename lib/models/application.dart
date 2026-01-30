class Application {
  final String id;
  final String name;
  final String time;
  final String? note;
  final bool? isNew;
  final String? avatar;

  Application({
    required this.id,
    required this.name,
    required this.time,
    this.note,
    this.isNew,
    this.avatar,
  });

  factory Application.fromJson(Map<String, dynamic> json) => Application(
        id: json['id'] as String,
        name: json['name'] as String,
        time: json['time'] as String,
        note: json['note'] as String?,
        isNew: json['isNew'] as bool?,
        avatar: json['avatar'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'time': time,
        'note': note,
        'isNew': isNew,
        'avatar': avatar,
      };
}

