// Sources/SwiftProtobuf/Message.swift - Message support
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// -----------------------------------------------------------------------------
///
/// All messages implement some of these protocols:  Generated messages output
/// by protoc implement ProtobufGeneratedMessageType, hand-coded messages often
/// implement ProtobufAbstractMessage.  The protocol heirarchy here is
/// a little involved due to the variety of requirements and the need to
/// mix in JSON and binary support (see ProtobufBinaryTypes and
/// ProtobufJSONTypes for extensions that support binary and JSON coding).
///
// -----------------------------------------------------------------------------

import Swift

///
/// See ProtobufBinaryTypes and ProtobufJSONTypes for extensions
/// to these protocols for supporting binary and JSON coding.
///

///
/// ProtobufMessage is the protocol type you should use whenever
/// you need an argument or variable which holds "some message".
///
/// In particular, this has no associated types or self references so can be
/// used as a variable or argument type.
///
public protocol Message: CustomDebugStringConvertible, CustomReflectable {
  init()

  // Metadata
  // Basic facts about this class and the proto message it was generated from
  // Used by various encoders and decoders
  var swiftClassName: String { get }
  var protoMessageName: String { get }
  var protoPackageName: String { get }
  var anyTypePrefix: String { get }
  var anyTypeURL: String { get }

  //
  // General serialization machinery
  //

  /// Decode a field identified by a field number (as given in the .proto file).
  ///
  /// This is the core method used by the deserialization machinery.
  ///
  /// Note that this is not specific to protobuf encoding; formats that use
  /// textual identifiers translate those to protoFieldNumbers and then invoke
  /// this to decode the field value.
  mutating func decodeField(setter: inout FieldDecoder,
                            protoFieldNumber: Int) throws

  /// Support for traversing the object tree.
  ///
  /// This is used by:
  /// = Protobuf serialization
  /// = JSON serialization (with some twists to account for specialty JSON encodings)
  /// = hashValue computation
  /// = mirror generation
  ///
  /// Conceptually, serializers create visitor objects that are
  /// then passed recursively to every message and field via generated
  /// 'traverse' methods.  The details get a little involved due to
  /// the need to allow particular messages to override particular
  /// behaviors for specific encodings, but the general idea is quite simple.
  func traverse(visitor: inout Visitor) throws

  //
  // Protobuf Binary decoding
  //
  mutating func decodeIntoSelf(protobuf: UnsafeBufferPointer<UInt8>, extensions: ExtensionSet?) throws

  // Protobuf Text decoding
  init(scanner: TextScanner) throws

  //
  // google.protobuf.Any support
  //

  // Decode from an `Any` (which might itself have been decoded from JSON,
  // protobuf, or another `Any`).
  init(any: Google_Protobuf_Any) throws

  /// Serialize as an `Any` object in JSON format.
  ///
  /// For generated message types, this generates the same JSON object as
  /// `serializeJSON()` except it adds an additional `@type` field.
  func serializeAnyJSON() throws -> String

  //
  // JSON encoding/decoding support
  //

  /// Serialize to JSON
  /// Overridden by well-known-types with custom JSON requirements.
  func serializeJSON() throws -> String
  /// Value, NullValue override this to decode themselves from a JSON "null".
  /// Default just returns nil.
  static func decodeFromJSONNull() throws -> Self?
  /// Duration, Timestamp, FieldMask override this to
  /// update themselves from a single JSON token.
  /// Default always throws an error.
  mutating func decodeFromJSONToken(token: JSONToken) throws
  /// Value, Struct, Any override this to update themselves from a JSON object.
  /// Default decodes keys and feeds them to decodeField()
  mutating func decodeFromJSONObject(jsonDecoder: inout JSONDecoder) throws
  /// Value, ListValue override this to update themselves from a JSON array.
  /// Default always throws an error
  mutating func decodeFromJSONArray(jsonDecoder: inout JSONDecoder) throws

  // Standard utility properties and methods.
  // Most of these are simple wrappers on top of the visitor machinery.
  // They are implemented in the protocol, not in the generated structs,
  // so can be overridden in user code by defining custom extensions to
  // the generated struct.
  var hashValue: Int { get }
  var debugDescription: String { get }
  var customMirror: Mirror { get }
}

public extension Message {
  var hashValue: Int { return HashVisitor(message: self).hashValue }

  var debugDescription: String {
    return DebugDescriptionVisitor(message: self).description
  }

  var customMirror: Mirror {
    return MirrorVisitor(message: self).mirror
  }

  // TODO:  Add an option to the generator to override this in particular messages.
  // TODO:  It would be nice if this could default to "" instead; that would save ~20
  // bytes on every serialized Any.
  var anyTypePrefix: String { return "type.googleapis.com" }

  var anyTypeURL: String {
    var url = anyTypePrefix
    if anyTypePrefix == "" || anyTypePrefix.characters.last! != "/" {
      url += "/"
    }
    if protoPackageName != "" {
      url += protoPackageName
      url += "."
    }
    url += protoMessageName
    return url
  }

  /// Creates an instance of the message type on which this method is called,
  /// executes the given block passing the message in as its sole `inout`
  /// argument, and then returns the message.
  ///
  /// This method acts essentially as a "builder" in that the initialization of
  /// the message is captured within the block, allowing the returned value to
  /// be set in an immutable variable. For example,
  ///
  ///     let msg = MyMessage.with { $0.myField = "foo" }
  ///     msg.myOtherField = 5  // error: msg is immutable
  ///
  /// - Parameter populator: A block or function that populates the new message,
  ///   which is passed into the block as an `inout` argument.
  /// - Returns: The message after execution of the block.
  public static func with(populator: (inout Self) -> ()) -> Self {
    var message = Self()
    populator(&message)
    return message
  }
}

///
/// Marker type that specifies the message was generated from
/// a proto2 source file.
///
public protocol Proto2Message: Message {
  var unknown: UnknownStorage { get set }
}

///
/// Marker type that specifies the message was generated from
/// a proto3 source file.
///
public protocol Proto3Message: Message {
}

///
/// Implementation base for all messages.
///
/// All messages (whether hand-implemented or generated)
/// should conform to this type.  It is very rarely
/// used for any other purpose.
///
/// Generally, you should use `SwiftProtobuf.Message` instead
/// when you need a variable or argument that holds a message,
/// or occasionally `SwiftProtobuf.Message & Equatable` or even
/// `SwiftProtobuf.Message & Hashable` if you need to use equality
/// tests or put it in a `Set<>`.
///
public protocol _MessageImplementationBase: Message, Hashable, MapValueType {
    func isEqualTo(other: Self) -> Bool

    // The compiler actually generates the following methods. Default
    // implementations below redirect the standard names. This allows developers
    // to override the standard names to customize the behavior.
    mutating func _protoc_generated_decodeField(
        setter: inout FieldDecoder,
        protoFieldNumber: Int) throws

    func _protoc_generated_traverse(visitor: inout Visitor) throws

    func _protoc_generated_isEqualTo(other: Self) -> Bool
}

public extension _MessageImplementationBase {
  // Default implementations simply redirect to the generated versions.
  public func traverse(visitor: inout Visitor) throws {
    try _protoc_generated_traverse(visitor: &visitor)
  }

  mutating func decodeField(setter: inout FieldDecoder,
                            protoFieldNumber: Int) throws {
      try _protoc_generated_decodeField(setter: &setter,
                                        protoFieldNumber: protoFieldNumber)
  }

  func isEqualTo(other: Self) -> Bool {
    return _protoc_generated_isEqualTo(other: other)
  }
}

public func ==<M: _MessageImplementationBase>(lhs: M, rhs: M) -> Bool {
  return lhs.isEqualTo(other: rhs)
}
