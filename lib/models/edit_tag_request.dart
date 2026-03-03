import 'tag_record.dart';

class EditTagRequest {
  EditTagRequest({required this.id, required this.tag});

  final String id;
  final TagRecord tag;
}
