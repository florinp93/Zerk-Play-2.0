import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef MpvHandle = Pointer<Void>;

abstract final class MpvFormat {
  static const none = 0;
  static const string = 1;
  static const flag = 3;
  static const int64 = 4;
  static const double_ = 5;
  static const node = 6;
  static const nodeArray = 7;
  static const nodeMap = 8;
}

abstract final class MpvEventId {
  static const none = 0;
  static const shutdown = 1;
  static const logMessage = 2;
  static const startFile = 6;
  static const endFile = 7;
  static const fileLoaded = 8;
  static const clientMessage = 16;
  static const videoReconfig = 17;
  static const audioReconfig = 18;
  static const seek = 20;
  static const playbackRestart = 21;
  static const propertyChange = 22;
}

abstract final class MpvEndFileReason {
  static const eof = 0;
  static const stop = 2;
  static const quit = 3;
  static const error = 4;
  static const redirect = 5;
}

final class MpvEventStruct extends Struct {
  @Int32()
  external int eventId;
  @Int32()
  external int error;
  @Uint64()
  external int replyUserdata;
  external Pointer<Void> data;
}

final class MpvEventProperty extends Struct {
  external Pointer<Utf8> name;
  @Int32()
  external int format;
  external Pointer<Void> data;
}

final class MpvEventEndFile extends Struct {
  @Int32()
  external int reason;
  @Int32()
  external int error;
  @Int64()
  external int playlistEntryId;
  @Int64()
  external int playlistInsertId;
  @Int32()
  external int playlistInsertNumEntries;
}

final class MpvEventClientMessage extends Struct {
  @Int32()
  external int numArgs;
  external Pointer<Pointer<Utf8>> args;
}

final class MpvEventLogMessage extends Struct {
  external Pointer<Utf8> prefix;
  external Pointer<Utf8> level;
  external Pointer<Utf8> text;
  @Int32()
  external int logLevel;
}

final class MpvNodeUnion extends Union {
  external Pointer<Utf8> string;
  @Int32()
  external int flag;
  @Int64()
  external int int64;
  @Double()
  external double double_;
  external Pointer<MpvNodeList> list;
  external Pointer<Void> ba;
}

final class MpvNode extends Struct {
  external MpvNodeUnion u;
  @Int32()
  external int format;
}

final class MpvNodeList extends Struct {
  @Int32()
  external int num;
  external Pointer<MpvNode> values;
  external Pointer<Pointer<Utf8>> keys;
}

Object? mpvNodeToDart(Pointer<MpvNode> node) {
  final n = node.ref;
  switch (n.format) {
    case MpvFormat.string:
      return n.u.string.toDartString();
    case MpvFormat.flag:
      return n.u.flag != 0;
    case MpvFormat.int64:
      return n.u.int64;
    case MpvFormat.double_:
      return n.u.double_;
    case MpvFormat.nodeArray:
      final list = n.u.list.ref;
      return [for (var i = 0; i < list.num; i++) mpvNodeToDart(list.values + i)];
    case MpvFormat.nodeMap:
      final list = n.u.list.ref;
      return {
        for (var i = 0; i < list.num; i++)
          (list.keys + i).value.toDartString(): mpvNodeToDart(list.values + i),
      };
    default:
      return null;
  }
}

typedef MpvWakeupNative = Void Function(Pointer<Void>);

final class LibMpv {
  LibMpv._(DynamicLibrary lib)
      : create = lib.lookupFunction<MpvHandle Function(), MpvHandle Function()>('mpv_create'),
        initialize = lib.lookupFunction<Int32 Function(MpvHandle), int Function(MpvHandle)>(
            'mpv_initialize'),
        terminateDestroy = lib.lookupFunction<Void Function(MpvHandle), void Function(MpvHandle)>(
            'mpv_terminate_destroy'),
        setOptionString = lib.lookupFunction<
            Int32 Function(MpvHandle, Pointer<Utf8>, Pointer<Utf8>),
            int Function(MpvHandle, Pointer<Utf8>, Pointer<Utf8>)>('mpv_set_option_string'),
        setPropertyString = lib.lookupFunction<
            Int32 Function(MpvHandle, Pointer<Utf8>, Pointer<Utf8>),
            int Function(MpvHandle, Pointer<Utf8>, Pointer<Utf8>)>('mpv_set_property_string'),
        getPropertyString = lib.lookupFunction<
            Pointer<Utf8> Function(MpvHandle, Pointer<Utf8>),
            Pointer<Utf8> Function(MpvHandle, Pointer<Utf8>)>('mpv_get_property_string'),
        getProperty = lib.lookupFunction<
            Int32 Function(MpvHandle, Pointer<Utf8>, Int32, Pointer<Void>),
            int Function(MpvHandle, Pointer<Utf8>, int, Pointer<Void>)>('mpv_get_property'),
        command = lib.lookupFunction<
            Int32 Function(MpvHandle, Pointer<Pointer<Utf8>>),
            int Function(MpvHandle, Pointer<Pointer<Utf8>>)>('mpv_command'),
        commandAsync = lib.lookupFunction<
            Int32 Function(MpvHandle, Uint64, Pointer<Pointer<Utf8>>),
            int Function(MpvHandle, int, Pointer<Pointer<Utf8>>)>('mpv_command_async'),
        observeProperty = lib.lookupFunction<
            Int32 Function(MpvHandle, Uint64, Pointer<Utf8>, Int32),
            int Function(MpvHandle, int, Pointer<Utf8>, int)>('mpv_observe_property'),
        waitEvent = lib.lookupFunction<
            Pointer<MpvEventStruct> Function(MpvHandle, Double),
            Pointer<MpvEventStruct> Function(MpvHandle, double)>('mpv_wait_event'),
        setWakeupCallback = lib.lookupFunction<
            Void Function(MpvHandle, Pointer<NativeFunction<MpvWakeupNative>>, Pointer<Void>),
            void Function(MpvHandle, Pointer<NativeFunction<MpvWakeupNative>>, Pointer<Void>)>(
            'mpv_set_wakeup_callback'),
        requestLogMessages = lib.lookupFunction<
            Int32 Function(MpvHandle, Pointer<Utf8>),
            int Function(MpvHandle, Pointer<Utf8>)>('mpv_request_log_messages'),
        free = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
            'mpv_free'),
        freeNodeContents = lib.lookupFunction<Void Function(Pointer<MpvNode>),
            void Function(Pointer<MpvNode>)>('mpv_free_node_contents'),
        errorString = lib.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>(
            'mpv_error_string');

  static LibMpv? _instance;

  static LibMpv get instance => _instance ??= LibMpv._(DynamicLibrary.open('libmpv-2.dll'));

  final MpvHandle Function() create;
  final int Function(MpvHandle) initialize;
  final void Function(MpvHandle) terminateDestroy;
  final int Function(MpvHandle, Pointer<Utf8>, Pointer<Utf8>) setOptionString;
  final int Function(MpvHandle, Pointer<Utf8>, Pointer<Utf8>) setPropertyString;
  final Pointer<Utf8> Function(MpvHandle, Pointer<Utf8>) getPropertyString;
  final int Function(MpvHandle, Pointer<Utf8>, int, Pointer<Void>) getProperty;
  final int Function(MpvHandle, Pointer<Pointer<Utf8>>) command;
  final int Function(MpvHandle, int, Pointer<Pointer<Utf8>>) commandAsync;
  final int Function(MpvHandle, int, Pointer<Utf8>, int) observeProperty;
  final Pointer<MpvEventStruct> Function(MpvHandle, double) waitEvent;
  final void Function(MpvHandle, Pointer<NativeFunction<MpvWakeupNative>>, Pointer<Void>)
      setWakeupCallback;
  final int Function(MpvHandle, Pointer<Utf8>) requestLogMessages;
  final void Function(Pointer<Void>) free;
  final void Function(Pointer<MpvNode>) freeNodeContents;
  final Pointer<Utf8> Function(int) errorString;
}
