//
//  FakefsImporter.h
//  MinisApp
//
//  Wraps the kernel's fakefsify `fakefs_import` (deps/ish/tools/fakefs.c) so
//  Swift can build a bootable fakefs — data/ + meta.db in the exact format
//  the iSH kernel expects (user_version=5, escaped host names, full stat
//  blobs) — directly from a tar archive. This is the same import pipeline
//  iSH-AOK uses for its alternative rootfs.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FakefsImporter : NSObject

/// Import a rootfs archive into a NEW fakefs at `destination`.
///
/// libarchive auto-detects the container: .tar, .tar.gz / .tgz, .tar.xz, …
/// The destination directory must not already exist (the tool creates
/// `data/` and `meta.db` inside it). On success the result is a complete,
/// kernel-bootable fakefs.
///
/// @param archivePath Path to the rootfs archive (tar / tar.gz / tar.xz).
/// @param destination Path where the fakefs will be created.
/// @param progress    Optional progress callback (fraction 0–1, message).
///                    Invoked on the calling thread.
/// @return YES on success; NO with `error` set on failure.
+ (BOOL)importArchiveAtPath:(NSString *)archivePath
                     toPath:(NSString *)destination
                      error:(NSError **)error
                   progress:(void (^ _Nullable)(double fraction, NSString * _Nullable message))progress;

@end

NS_ASSUME_NONNULL_END
