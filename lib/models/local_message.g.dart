// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalMessageAdapter extends TypeAdapter<LocalMessage> {
  @override
  final int typeId = 0;

  @override
  LocalMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalMessage(
      messageId: fields[0] as String,
      chatId: fields[1] as String,
      chatType: fields[2] as String,
      senderId: fields[3] as String,
      senderName: fields[4] as String,
      messageText: fields[5] as String?,
      timestamp: fields[6] as int,
      attachmentUrl: fields[7] as String?,
      attachmentType: fields[8] as String?,
      pollData: (fields[9] as Map?)?.cast<String, dynamic>(),
      isDeleted: fields[10] as bool,
      replyToMessageId: fields[11] as String?,
      multipleMedia: (fields[12] as List?)?.cast<dynamic>(),
      isPending: fields[13] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, LocalMessage obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.messageId)
      ..writeByte(1)
      ..write(obj.chatId)
      ..writeByte(2)
      ..write(obj.chatType)
      ..writeByte(3)
      ..write(obj.senderId)
      ..writeByte(4)
      ..write(obj.senderName)
      ..writeByte(5)
      ..write(obj.messageText)
      ..writeByte(6)
      ..write(obj.timestamp)
      ..writeByte(7)
      ..write(obj.attachmentUrl)
      ..writeByte(8)
      ..write(obj.attachmentType)
      ..writeByte(9)
      ..write(obj.pollData)
      ..writeByte(10)
      ..write(obj.isDeleted)
      ..writeByte(11)
      ..write(obj.replyToMessageId)
      ..writeByte(12)
      ..write(obj.multipleMedia)
      ..writeByte(13)
      ..write(obj.isPending);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
