//
//  LZMAWrapper.h
//  MinisApp
//
//  Thin Objective-C wrapper around liblzma (xz-utils) so Swift can
//  decompress .tar.xz mini-rootfs archives without bridging the whole
//  lzma.h C API. Bridges libzma's one-shot `lzma_stream_buffer_decode`.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LZMAWrapper : NSObject

/// Decompress a complete .xz (or .lzma?) stream into raw bytes.
/// Returns nil (and sets `error` if non-nil) on failure.
+ (nullable NSData *)decompressXZ:(NSData *)xzData error:(NSError * _Nullable *)error;

@end

NS_ASSUME_NONNULL_END
