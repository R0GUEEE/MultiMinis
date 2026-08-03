//
//  LZMAWrapper.m
//  MinisApp
//
//  Thin Objective-C wrapper around liblzma (xz-utils) for .tar.xz rootfs
//  decompression. Uses liblzma's `lzma_stream_buffer_decode` which inflates
//  a complete .xz stream to a memory buffer.
//

#import "LZMAWrapper.h"
#include <lzma.h>

@implementation LZMAWrapper

+ (NSData *)decompressXZ:(NSData *)xzData error:(NSError *__autoreleasing *)error {
    if (!xzData || xzData.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"LZMAWrapper" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty XZ input."}];
        }
        return nil;
    }

    // First pass: ask liblzma how big the output needs to be by decoding with
    // memlimit and a single call. lzma_stream_buffer_decode needs a known
    // output buffer; use a growing approach:
    //   1. Decode to get the uncompressed size via a large memlimit single pass.

    const uint8_t *in = (const uint8_t *)xzData.bytes;
    size_t in_pos = 0;
    size_t in_size = xzData.length;
    uint64_t memlimit = UINT64_MAX;

    // Probe the size. lzma's single-call decode requires the full output to
    // fit; we decode into a buffer that grows until the call succeeds.
    const size_t initial = 1 << 20; // 1 MB
    size_t out_capacity = initial;

    // We cannot know the exact size in advance, so grow until success.
    for (int i = 0; i < 32; i++) {
        NSMutableData *out = [NSMutableData dataWithLength:out_capacity];
        uint8_t *out_ptr = (uint8_t *)out.mutableBytes;
        size_t out_pos = 0;
        size_t out_size = out_capacity;
        in_pos = 0;

        lzma_ret ret = lzma_stream_buffer_decode(&memlimit, 0, NULL,
                                                  in, &in_pos, in_size,
                                                  out_ptr, &out_pos, out_size);
        if (ret == LZMA_OK || ret == LZMA_STREAM_END) {
            // Decoded; trim to produced bytes.
            out.length = out_pos;
            return out;
        }
        if (ret == LZMA_BUF_ERROR) {
            // Output buffer too small; double and retry.
            out_capacity *= 2;
            if (out_capacity > (1u << 30)) break; // >1 GB cap
            continue;
        }
        // Real error.
        if (error) {
            *error = [NSError errorWithDomain:@"LZMAWrapper" code:(int)ret
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"XZ decode failed (code %d).", (int)ret]}];
        }
        return nil;
    }

    if (error) {
        *error = [NSError errorWithDomain:@"LZMAWrapper" code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"XZ buffer too large to decode."}];
    }
    return nil;
}

@end
