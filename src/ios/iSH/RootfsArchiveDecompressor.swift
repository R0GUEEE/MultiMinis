//
//  RootfsArchiveDecompressor.swift
//  MinisApp
//
//  Detects and transparently decompresses a tar archive based on the magic
//  bytes of the supplied file, independent of its filename extension. Used by
//  RootfsManager to import .tar.gz / .tgz mini-rootfs tarballs.
//
//  Supported containers:
//    - gzip (RFC 1952)   -> decompressed via the Compression framework
//    - plain .tar        -> passed through
//
//  Apple's Compression framework's COMPRESSION_ZLIB decoder handles RAW
//  DEFLATE (as used by zip entries) — it does NOT understand the gzip
//  wrapper, so gzip members are parsed here and their DEFLATE payloads are
//  decoded directly.
//

import Foundation
import Compression

enum RootfsArchiveError: Error, LocalizedError {
    case unsupportedFormat
    case readFailed
    case inflateFailed
    case emptyInput
    case decompressFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Unsupported archive format (only .tar, .tar.gz, .tar.xz supported)."
        case .readFailed: return "Could not read the archive file."
        case .inflateFailed: return "Failed to decompress the archive."
        case .emptyInput: return "The archive is empty."
        case .decompressFailed(let m): return "Decompression failed: \(m)"
        }
    }
}

/// Result of decompressing a rootfs container.
final class DecompressedTarData {
    let data: Data
    let wasCompressed: Bool
    init(data: Data, wasCompressed: Bool) {
        self.data = data
        self.wasCompressed = wasCompressed
    }
}

enum RootfsArchiveDecompressor {

    /// Decompress (if needed) the supplied archive into raw tar bytes.
    static func decompress(url: URL) throws -> DecompressedTarData {
        let raw: Data
        do { raw = try Data(contentsOf: url) }
        catch { throw RootfsArchiveError.readFailed }
        guard !raw.isEmpty else { throw RootfsArchiveError.emptyInput }

        // gzip magic 1f 8b
        if raw.count >= 2, raw[0] == 0x1f, raw[1] == 0x8b {
            return DecompressedTarData(data: try gunzip(raw), wasCompressed: true)
        }
        // xz magic FD 37 7A 58 5A 00
        if raw.count >= 6, raw[0] == 0xFD, raw[1] == 0x37, raw[2] == 0x7A,
           raw.count >= 6, raw[3] == 0x58, raw[4] == 0x5A, raw[5] == 0x00 {
            return DecompressedTarData(data: try xzDecompress(raw), wasCompressed: true)
        }
        return DecompressedTarData(data: raw, wasCompressed: false)
    }

    /// Decompress a .tar.xz stream via liblzma (see LZMAWrapper).
    /// LZMAWrapper.decompressXZ is imported as throwing (its NSError** param
    /// becomes Swift `throws`), so we `try` and re-wrap any error here.
    private static func xzDecompress(_ data: Data) throws -> Data {
        do {
            // Imported as throwing: on failure it throws (NSError** -> throws),
            // on success returns a non-optional Data.
            let out = try LZMAWrapper.decompressXZ(data)
            guard !out.isEmpty else {
                throw RootfsArchiveError.decompressFailed("empty result")
            }
            return out
        } catch let e as NSError {
            throw RootfsArchiveError.decompressFailed(e.localizedDescription)
        }
    }

    /// Decompress a gzip member. Apple's Compression framework COMPRESSION_ZLIB
    /// decoder expects a RAW DEFLATE stream (the zip extractor proves this) —
    /// it does NOT understand the gzip wrapper. Feeding it the whole gzip
    /// file (as the previous implementation did) always fails with
    /// "Failed to decompress the archive". So we parse the gzip header
    /// ourselves, locate the DEFLATE payload, and decode that.
    private static func gunzip(_ data: Data) throws -> Data {
        guard data.count >= 18,
              data[0] == 0x1f, data[1] == 0x8b, data[2] == 0x08 else {
            throw RootfsArchiveError.decompressFailed("Not a gzip stream")
        }

        // gzip member header: magic(2) CM(1) FLG(1) MTIME(4) XFL(1) OS(1) = 10 bytes
        let flg = data[3]
        var p = 10

        if flg & 0x04 != 0 { // FEXTRA — 2-byte length + extra field
            guard p + 2 <= data.count else {
                throw RootfsArchiveError.decompressFailed("Truncated gzip header")
            }
            let xlen = Int(data[p]) | (Int(data[p + 1]) << 8)
            p += 2 + xlen
        }
        if flg & 0x08 != 0 { // FNAME — NUL-terminated
            while p < data.count, data[p] != 0 { p += 1 }
            p += 1
        }
        if flg & 0x10 != 0 { // FCOMMENT — NUL-terminated
            while p < data.count, data[p] != 0 { p += 1 }
            p += 1
        }
        if flg & 0x02 != 0 { p += 2 } // FHCRC — 2 bytes

        guard p < data.count else {
            throw RootfsArchiveError.decompressFailed("Truncated gzip stream")
        }
        // The 8-byte trailer (CRC32 + ISIZE) is not part of the deflate stream.
        let trailer = min(8, data.count - p)
        let payload = data.subdata(in: p ..< (data.count - trailer))

        var capacity = max(payload.count * 4, 1 << 20) // start generously
        var output = Data(count: capacity)
        var produced = -1

        // Grow the destination buffer until the deflate stream fits. Rootfs
        // archives can expand many times, so don't assume a fixed size.
        for _ in 0..<24 {
            let r = output.withUnsafeMutableBytes { dstPtr -> Int in
                payload.withUnsafeBytes { srcPtr -> Int in
                    compression_decode_buffer(
                        dstPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        capacity,
                        srcPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        payload.count,
                        nil,
                        COMPRESSION_ZLIB)
                }
            }
            if r > 0 {
                produced = r
                break
            }
            if capacity > (1 << 30) { break }
            output = Data(count: capacity * 2)
            capacity *= 2
        }

        guard produced > 0 else { throw RootfsArchiveError.inflateFailed }
        output.count = produced
        return output
    }
}
