class BillPlatform {
  final String code;
  final String name;
  final List<String> supportedFormats;
  final String? sampleFileName;

  BillPlatform({
    required this.code,
    required this.name,
    required this.supportedFormats,
    this.sampleFileName,
  });

  factory BillPlatform.fromJson(Map<String, dynamic> json) => BillPlatform(
        code: json['code'] as String,
        name: json['name'] as String,
        supportedFormats: (json['supportedFormats'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        sampleFileName: json['sampleFileName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'supportedFormats': supportedFormats,
        'sampleFileName': sampleFileName,
      };
}


