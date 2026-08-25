//
//  FakefsImporter.m
//  MinisApp
//
//  Thin Objective-C bridge to the kernel's fakefsify import tool
//  (tools/fakefs.c in the pinned deps/ish submodule). The tool is compiled
//  into the app and linked against libfakefs (fs/fake-db.c etc.), sqlite3
//  and libarchive — the same components iSH-AOK links.
//

#import "FakefsImporter.h"
#include "tools/fakefs.h"

@implementation FakefsImporter

/// fakefsify progress callback: forwards to the Swift-provided block.
static void importer_progress(void *cookie, double progress, const char *message, bool *cancel_out) {
    (void)cancel_out; // cancellation is not surfaced to Swift (yet)
    void (^block)(double, NSString *) = (__bridge void (^)(double, NSString *))cookie;
    if (block == nil)
        return;
    NSString *msg = message != NULL ? [NSString stringWithUTF8String:message] : nil;
    block(progress, msg);
}

+ (BOOL)importArchiveAtPath:(NSString *)archivePath
                     toPath:(NSString *)destination
                      error:(NSError **)error
                   progress:(void (^)(double, NSString *))progress {
    // libarchive needs a UTF-8 locale to read tarballs whose path/link
    // fields carry UTF-8 (Debian/Devuan/Ubuntu ship such entries).
    fakefs_ensure_utf8_locale();

    struct fakefsify_error fs_err = {0};
    struct progress p = {0};
    void (^block)(double, NSString *) = progress;
    if (block != nil) {
        // The callback fires synchronously on this thread during the import,
        // so a plain __bridge of the caller's block is safe — the caller's
        // closure is retained for the duration of this call.
        p.cookie = (__bridge void *)block;
        p.callback = importer_progress;
    }

    if (!fakefs_import(archivePath.fileSystemRepresentation,
                       destination.fileSystemRepresentation,
                       &fs_err, p)) {
        if (error != NULL) {
            NSString *domain = fs_err.type == ERR_SQLITE ? @"SQLite" : NSPOSIXErrorDomain;
            NSString *message = fs_err.message != NULL
                ? [NSString stringWithUTF8String:fs_err.message]
                : @"unknown import error";
            *error = [NSError errorWithDomain:domain
                                         code:fs_err.code
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        if (fs_err.message != NULL)
            free(fs_err.message);
        return NO;
    }
    return YES;
}

@end
