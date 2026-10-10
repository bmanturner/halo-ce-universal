/* Mirrors the tvOS saves to the user's private CloudKit database. tvOS may empty
   Caches at any time, so the saves and config.toml live as HaloFile records in
   the zone HaloSaves, one record per file, named after the hash of the file's
   path relative to the documents folder. At start the missing local files are
   restored from the zone (bounded wait, existing files are never touched). After
   that a serial queue scans the files every 30 s and when the app goes inactive,
   and uploads those whose content changed. Server records are never deleted, so
   a purged Caches cannot erase the cloud copy. */
#import <CloudKit/CloudKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <sys/stat.h>
#include "host.h"
#include "tvos_host.h"

#define CLOUD_ZONE @"HaloSaves"
#define CLOUD_TYPE @"HaloFile"
#define CLOUD_RESTORE_SECONDS 20
#define CLOUD_SCAN_SECONDS 30
#define CLOUD_SETTLE_SECONDS 2
#define CLOUD_TEMP_PREFIX @".halo-restore-"

static NSString *cloud_documents, *cloud_save_root;
static CKDatabase *cloud_db;
static CKRecordZoneID *cloud_zone;
static dispatch_queue_t cloud_queue;
static dispatch_source_t cloud_timer;
/* everything below is touched on cloud_queue only */
static NSMutableDictionary<NSString *, NSString *> *cloud_uploaded; /* path -> sha256 on the server */
static NSMutableDictionary<NSString *, NSString *> *cloud_seen; /* path -> "size:mtime" at the last scan */
static NSMutableArray<void (^)(void)> *cloud_waiters;
static BOOL cloud_busy, cloud_restoring, cloud_stopped;
static int cloud_restored, cloud_total;

static NSString *cloud_hex(const unsigned char *d, size_t n) {
  NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
  for (size_t i = 0; i < n; i++) [s appendFormat:@"%02x", d[i]];
  return s;
}

static NSString *cloud_sha256(NSData *data) {
  unsigned char d[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, d);
  return cloud_hex(d, sizeof d);
}

static BOOL cloud_path_valid(NSString *path) {
  if (![path isKindOfClass:NSString.class] || !path.length || [path hasPrefix:@"/"]) return NO;
  NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
  for (NSString *p in parts)
    if (!p.length || [p isEqualToString:@".."] || [p isEqualToString:@"."]) return NO;
  if ([path isEqualToString:@"config.toml"]) return YES;
  /* z:\cacheNNN.map is the Xbox utility drive's copy of map data (up to
     several hundred MB each), which the game rebuilds; it is not a save */
  NSString *name = parts.lastObject;
  if (name.length == 12 && [name hasPrefix:@"cache"] && [name hasSuffix:@".map"] &&
      [[name substringWithRange:NSMakeRange(5, 3)] rangeOfCharacterFromSet:
        NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound) return NO;
  return parts.count > 1 && [parts[0] isEqualToString:@"save"];
}

static NSString *cloud_full_path(NSString *path) { return [cloud_documents stringByAppendingPathComponent:path]; }

static CKRecordID *cloud_record_id(NSString *path) {
  NSData *p = [path dataUsingEncoding:NSUTF8StringEncoding];
  return [[CKRecordID alloc] initWithRecordName:[@"file-" stringByAppendingString:cloud_sha256(p)] zoneID:cloud_zone];
}

/* Restore one fetched record. compressed is the asset's bytes read inside the fetch callback. */
static void cloud_restore_record(NSDictionary *info) {
  if (!cloud_restoring) return;
  NSString *path = info[@"path"], *hash = info[@"sha256"];
  NSData *compressed = info[@"data"];
  if (!cloud_path_valid(path) || ![hash isKindOfClass:NSString.class]) return;
  cloud_total++;
  cloud_uploaded[path] = hash;
  NSString *full = cloud_full_path(path);
  NSFileManager *fm = NSFileManager.defaultManager;
  if ([fm fileExistsAtPath:full] || !compressed) return;
  NSError *error = nil;
  NSData *data = [compressed decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:&error];
  if (!data || data.length != [info[@"size"] unsignedLongLongValue] || ![cloud_sha256(data) isEqualToString:hash]) {
    host_logf(HOST_LOG_WARN, "iCloud saves: skipped corrupt record for %s", path.UTF8String);
    return;
  }
  NSString *dir = full.stringByDeletingLastPathComponent;
  NSString *temp = [dir stringByAppendingPathComponent:
    [CLOUD_TEMP_PREFIX stringByAppendingString:NSUUID.UUID.UUIDString]];
  if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error] ||
      ![data writeToFile:temp options:0 error:&error]) {
    host_logf(HOST_LOG_WARN, "iCloud saves: cannot write %s: %s", path.UTF8String,
      error.localizedDescription.UTF8String);
    return;
  }
  /* link fails when the game created the file meanwhile, which keeps the local one */
  if (link(temp.fileSystemRepresentation, full.fileSystemRepresentation) == 0) cloud_restored++;
  unlink(temp.fileSystemRepresentation);
}

/* One page of the zone's records; follows moreComing with the returned token. */
static void cloud_fetch_page(CKServerChangeToken *token, dispatch_semaphore_t done) {
  CKFetchRecordZoneChangesConfiguration *cfg = [CKFetchRecordZoneChangesConfiguration new];
  cfg.previousServerChangeToken = token;
  CKFetchRecordZoneChangesOperation *op = [[CKFetchRecordZoneChangesOperation alloc]
    initWithRecordZoneIDs:@[cloud_zone] configurationsByRecordZoneID:@{cloud_zone: cfg}];
  __block CKServerChangeToken *next = nil;
  __block BOOL more = NO;
  op.recordWasChangedBlock = ^(CKRecordID *rid, CKRecord *record, NSError *error) {
    if (!record || ![record.recordType isEqualToString:CLOUD_TYPE]) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (record[@"path"]) info[@"path"] = record[@"path"];
    if (record[@"sha256"]) info[@"sha256"] = record[@"sha256"];
    if (record[@"size"]) info[@"size"] = record[@"size"];
    CKAsset *asset = record[@"data"];
    NSData *bytes = asset.fileURL ? [NSData dataWithContentsOfURL:asset.fileURL] : nil;
    if (bytes) info[@"data"] = bytes;
    dispatch_async(cloud_queue, ^{ cloud_restore_record(info); });
  };
  op.recordZoneFetchCompletionBlock = ^(CKRecordZoneID *zid, CKServerChangeToken *tok, NSData *client,
      BOOL moreComing, NSError *error) {
    next = tok;
    more = moreComing;
    if (error) host_logf(HOST_LOG_WARN, "iCloud saves: fetch failed: %s", error.localizedDescription.UTF8String);
  };
  op.fetchRecordZoneChangesCompletionBlock = ^(NSError *error) {
    if (error) host_logf(HOST_LOG_WARN, "iCloud saves: fetch failed: %s", error.localizedDescription.UTF8String);
    if (!error && more && next) { cloud_fetch_page(next, done); return; }
    dispatch_async(cloud_queue, ^{ dispatch_semaphore_signal(done); });
  };
  [cloud_db addOperation:op];
}

static void cloud_finish_upload(void) {
  NSArray *list = [cloud_waiters copy];
  [cloud_waiters removeAllObjects];
  cloud_busy = NO;
  for (void (^w)(void) in list) w();
}

/* a partial failure carries the item's own error */
static NSError *cloud_cause(NSError *error) {
  return [error.userInfo[CKPartialErrorsByItemIDKey] allValues].firstObject ?: error;
}

/* errors no retry fixes in this run: the container, entitlement or account is wrong */
static BOOL cloud_fatal(NSError *cause) {
  return [cause.domain isEqualToString:CKErrorDomain] && (cause.code == CKErrorPermissionFailure ||
    cause.code == CKErrorBadContainer || cause.code == CKErrorNotAuthenticated || cause.code == CKErrorMissingEntitlement);
}

static void cloud_stop(NSError *cause) {
  if (cloud_stopped) return;
  cloud_stopped = YES;
  if (cloud_timer) dispatch_source_cancel(cloud_timer);
  host_logf(HOST_LOG_WARN, "iCloud saves: stopped for this run: %s (%s %ld)", cause.localizedDescription.UTF8String,
    cause.domain.UTF8String, (long)cause.code);
}

/* Upload the mirrored files that changed. completion runs on cloud_queue once nothing is in flight. */
static void cloud_scan(void (^completion)(void)) {
  dispatch_async(cloud_queue, ^{
    if (completion) [cloud_waiters addObject:completion];
    if (cloud_busy) return;
    if (cloud_stopped) { cloud_finish_upload(); return; }
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    if ([fm fileExistsAtPath:cloud_full_path(@"config.toml")]) [paths addObject:@"config.toml"];
    NSString *save_rel = cloud_save_root.lastPathComponent;
    if ([cloud_save_root hasPrefix:[cloud_documents stringByAppendingString:@"/"]])
      save_rel = [cloud_save_root substringFromIndex:cloud_documents.length + 1];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:cloud_save_root];
    for (NSString *rel in en) {
      if ([rel.lastPathComponent hasPrefix:CLOUD_TEMP_PREFIX]) continue;
      NSDictionary *attrs = en.fileAttributes;
      if ([attrs.fileType isEqualToString:NSFileTypeRegular])
        [paths addObject:[save_rel stringByAppendingPathComponent:rel]];
    }
    NSMutableArray<CKRecord *> *records = [NSMutableArray array];
    NSMutableArray<NSString *> *rec_paths = [NSMutableArray array], *rec_hashes = [NSMutableArray array];
    NSMutableArray<NSNumber *> *rec_sizes = [NSMutableArray array];
    NSMutableArray<NSURL *> *temps = [NSMutableArray array];
    time_t now = time(NULL);
    for (NSString *path in paths) {
      if (!cloud_path_valid(path)) continue;
      const char *full = cloud_full_path(path).fileSystemRepresentation;
      struct stat st;
      if (stat(full, &st) != 0 || !S_ISREG(st.st_mode)) continue;
      NSString *sig = [NSString stringWithFormat:@"%lld:%lld", (long long)st.st_size, (long long)st.st_mtimespec.tv_sec];
      if ([cloud_seen[path] isEqualToString:sig]) continue;
      if (now - st.st_mtimespec.tv_sec < CLOUD_SETTLE_SECONDS) continue;
      NSData *data = [NSData dataWithContentsOfFile:@(full)];
      struct stat st2;
      if (!data || stat(full, &st2) != 0 || st2.st_size != st.st_size ||
          st2.st_mtimespec.tv_sec != st.st_mtimespec.tv_sec || st2.st_mtimespec.tv_nsec != st.st_mtimespec.tv_nsec ||
          (off_t)data.length != st.st_size) continue;
      NSString *hash = cloud_sha256(data);
      if ([cloud_uploaded[path] isEqualToString:hash]) { cloud_seen[path] = sig; continue; }
      NSError *error = nil;
      NSData *packed = [data compressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:&error];
      NSURL *temp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [@"halo-cloud-" stringByAppendingString:NSUUID.UUID.UUIDString]]];
      if (!packed || ![packed writeToURL:temp options:0 error:&error]) {
        host_logf(HOST_LOG_WARN, "iCloud saves: cannot pack %s", path.UTF8String);
        continue;
      }
      [temps addObject:temp];
      CKRecord *record = [[CKRecord alloc] initWithRecordType:CLOUD_TYPE recordID:cloud_record_id(path)];
      record[@"path"] = path;
      record[@"data"] = [[CKAsset alloc] initWithFileURL:temp];
      record[@"size"] = @(data.length);
      record[@"sha256"] = hash;
      record[@"modified"] = [NSDate dateWithTimeIntervalSince1970:st.st_mtimespec.tv_sec];
      [records addObject:record];
      [rec_paths addObject:path];
      [rec_hashes addObject:hash];
      [rec_sizes addObject:@(data.length)];
      cloud_seen[path] = sig;
    }
    if (!records.count) { cloud_finish_upload(); return; }
    cloud_busy = YES;
    CKModifyRecordsOperation *op = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:records recordIDsToDelete:nil];
    op.savePolicy = CKRecordSaveAllKeys;
    NSMutableSet<NSString *> *saved = [NSMutableSet set]; /* touched on the CloudKit callback queue until the result block */
    op.perRecordSaveBlock = ^(CKRecordID *rid, CKRecord *record, NSError *error) {
      NSString *path = nil;
      for (NSUInteger i = 0; i < records.count; i++)
        if ([records[i].recordID isEqual:rid]) path = rec_paths[i];
      if (path && !error) @synchronized(saved) { [saved addObject:path]; }
    };
    op.modifyRecordsCompletionBlock = ^(NSArray<CKRecord *> *saved_records, NSArray<CKRecordID *> *deleted, NSError *error) {
      for (NSURL *t in temps) [NSFileManager.defaultManager removeItemAtURL:t error:nil];
      if (error) {
        NSError *cause = cloud_cause(error);
        host_logf(HOST_LOG_WARN, "iCloud saves: upload of %lu files failed: %s (%s %ld)", (unsigned long)records.count,
          cause.localizedDescription.UTF8String, cause.domain.UTF8String, (long)cause.code);
        if (cloud_fatal(cause)) dispatch_async(cloud_queue, ^{ cloud_stop(cause); });
      }
      dispatch_async(cloud_queue, ^{
        for (NSUInteger i = 0; i < rec_paths.count; i++) {
          NSString *path = rec_paths[i];
          BOOL ok;
          @synchronized(saved) { ok = [saved containsObject:path]; }
          if (ok) {
            cloud_uploaded[path] = rec_hashes[i];
            host_logf(HOST_LOG_INFO, "iCloud saves: uploaded %s (%llu bytes)", path.UTF8String,
              rec_sizes[i].unsignedLongLongValue);
          } else [cloud_seen removeObjectForKey:path]; /* retry at the next scan */
        }
        cloud_finish_upload();
      });
    };
    [cloud_db addOperation:op];
  });
}

static void cloud_begin_uploads(void) {
  cloud_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, cloud_queue);
  dispatch_source_set_timer(cloud_timer, dispatch_time(DISPATCH_TIME_NOW, CLOUD_SCAN_SECONDS * NSEC_PER_SEC),
    CLOUD_SCAN_SECONDS * NSEC_PER_SEC, NSEC_PER_SEC);
  dispatch_source_set_event_handler(cloud_timer, ^{ cloud_scan(nil); });
  dispatch_resume(cloud_timer);
  NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
  [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
    usingBlock:^(NSNotification *n) { cloud_scan(nil); }];
  [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil
    usingBlock:^(NSNotification *n) {
      __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
      task = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"HaloCloudSaves" expirationHandler:^{
        UIBackgroundTaskIdentifier t = task;
        task = UIBackgroundTaskInvalid;
        if (t != UIBackgroundTaskInvalid) [UIApplication.sharedApplication endBackgroundTask:t];
      }];
      cloud_scan(^{
        dispatch_async(dispatch_get_main_queue(), ^{
          UIBackgroundTaskIdentifier t = task;
          task = UIBackgroundTaskInvalid;
          if (t != UIBackgroundTaskInvalid) [UIApplication.sharedApplication endBackgroundTask:t];
        });
      });
    }];
}

void host_cloud_saves_start(const char *documents, const char *save_root) {
  NSString *container = [NSBundle.mainBundle objectForInfoDictionaryKey:@"HaloCloudContainer"];
  if (![container isKindOfClass:NSString.class] || !container.length || [container containsString:@"$("]) {
    host_logf(HOST_LOG_INFO, "iCloud saves: disabled, no iCloud container in this build");
    return;
  }
  cloud_documents = @(documents);
  cloud_save_root = @(save_root);
  cloud_db = [CKContainer containerWithIdentifier:container].privateCloudDatabase;
  cloud_zone = [[CKRecordZoneID alloc] initWithZoneName:CLOUD_ZONE ownerName:CKCurrentUserDefaultName];
  cloud_queue = dispatch_queue_create("halo.cloud-saves", DISPATCH_QUEUE_SERIAL);
  cloud_uploaded = [NSMutableDictionary dictionary];
  cloud_seen = [NSMutableDictionary dictionary];
  cloud_waiters = [NSMutableArray array];
  dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, CLOUD_RESTORE_SECONDS * NSEC_PER_SEC);

  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  __block CKAccountStatus status = CKAccountStatusCouldNotDetermine;
  __block NSError *status_error = nil;
  [[CKContainer containerWithIdentifier:container] accountStatusWithCompletionHandler:
    ^(CKAccountStatus s, NSError *error) {
      status = s;
      status_error = error;
      dispatch_semaphore_signal(sem);
    }];
  if (dispatch_semaphore_wait(sem, deadline) != 0 || status != CKAccountStatusAvailable) {
    host_logf(HOST_LOG_INFO, "iCloud saves: disabled, account status %ld%s%s", (long)status,
      status_error ? ": " : "", status_error ? status_error.localizedDescription.UTF8String : "");
    return;
  }

  dispatch_semaphore_t zone_sem = dispatch_semaphore_create(0);
  __block NSError *zone_error = nil;
  CKModifyRecordZonesOperation *zone_op = [[CKModifyRecordZonesOperation alloc]
    initWithRecordZonesToSave:@[[[CKRecordZone alloc] initWithZoneID:cloud_zone]] recordZoneIDsToDelete:nil];
  zone_op.modifyRecordZonesCompletionBlock = ^(NSArray<CKRecordZone *> *zones, NSArray<CKRecordZoneID *> *deleted, NSError *error) {
    zone_error = error;
    dispatch_semaphore_signal(zone_sem);
  };
  [cloud_db addOperation:zone_op];
  BOOL zone_ready = dispatch_semaphore_wait(zone_sem, deadline) == 0 && !zone_error;
  if (!zone_ready) {
    NSError *cause = zone_error ? cloud_cause(zone_error) : nil;
    if (cause && cloud_fatal(cause)) {
      dispatch_sync(cloud_queue, ^{ cloud_stop(cause); });
      return;
    }
    host_logf(HOST_LOG_WARN, "iCloud saves: zone not ready%s%s (%s %ld), restore skipped", cause ? ": " : "",
      cause ? cause.localizedDescription.UTF8String : "", cause ? cause.domain.UTF8String : "timeout", (long)cause.code);
  } else {
    dispatch_semaphore_t fetch_sem = dispatch_semaphore_create(0);
    dispatch_sync(cloud_queue, ^{ cloud_restoring = YES; });
    cloud_fetch_page(nil, fetch_sem);
    BOOL finished = dispatch_semaphore_wait(fetch_sem, deadline) == 0;
    dispatch_sync(cloud_queue, ^{
      cloud_restoring = NO; /* later arrivals are ignored, the game may be writing */
      if (!finished) host_logf(HOST_LOG_WARN, "iCloud saves: restore timed out after %d s", CLOUD_RESTORE_SECONDS);
      host_logf(HOST_LOG_INFO, "iCloud saves: restored %d of %d files", cloud_restored, cloud_total);
    });
  }
  cloud_begin_uploads();
}
