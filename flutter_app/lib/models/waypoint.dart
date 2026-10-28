/// waypoint.dart
/// Model dữ liệu điểm mốc dẫn đường GPS

class Waypoint {
  final double lat;
  final double lng;
  final String name;
  final String instruction;
  final String actionText;

  Waypoint({
    required this.lat,
    required this.lng,
    required this.name,
    required this.instruction,
    required this.actionText,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'name': name,
        'instruction': instruction,
        'actionText': actionText,
      };

  factory Waypoint.fromJson(Map<String, dynamic> json) => Waypoint(
        lat: json['lat'],
        lng: json['lng'],
        name: json['name'],
        instruction: json['instruction'],
        actionText: json['actionText'],
      );
}
