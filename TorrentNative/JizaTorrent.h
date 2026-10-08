#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface JizaTorrent : NSObject
- (NSString *)addSource:(NSString *)source folder:(NSString *)folder;
- (NSArray<NSDictionary *> *)snapshots;
- (void)setPaused:(BOOL)paused index:(NSInteger)index;
@end
NS_ASSUME_NONNULL_END
