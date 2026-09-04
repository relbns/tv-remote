import 'device.dart';

/// What the remote is pointed at: either a set, or a single device.
///
/// The screens never ask which — they send a command and the routing decides
/// which half of a set should carry it.
class Target {
  const Target({
    required this.id,
    required this.name,
    this.room,
    this.display,
    this.source,
  });

  final String id;
  final String name;

  /// Set when this target is a set rather than a lone device.
  final Room? room;

  /// The television, if there is one.
  final Device? display;

  /// The box producing the picture, if there is one.
  final Device? source;

  bool get isRoom => room != null;

  /// The box first: most commands belong to it, and order decides fallback.
  List<Device> get devices => [?source, ?display];

  factory Target.forDevice(Device device) => Target(
    id: device.id,
    name: device.name,
    display: device.kind.isDisplay ? device : null,
    source: device.kind.isDisplay ? null : device,
  );

  factory Target.forRoom(Room room, {Device? display, Device? source}) =>
      Target(
        id: room.id,
        name: room.name,
        room: room,
        display: display,
        source: source,
      );
}
