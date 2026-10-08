#import "JizaTorrent.h"
#include <libtorrent/session.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/settings_pack.hpp>
#include <vector>
namespace lt = libtorrent;
@implementation JizaTorrent {
    std::unique_ptr<lt::session> _session;
    std::vector<lt::torrent_handle> _handles;
}
- (instancetype)init {
    if ((self = [super init])) {
        lt::settings_pack settings;
        settings.set_int(lt::settings_pack::connections_limit, 80);
        settings.set_int(lt::settings_pack::upload_rate_limit, 256 * 1024);
        settings.set_bool(lt::settings_pack::enable_upnp, false);
        settings.set_bool(lt::settings_pack::enable_natpmp, false);
        _session = std::make_unique<lt::session>(settings);
    }
    return self;
}
- (NSString *)addSource:(NSString *)source folder:(NSString *)folder {
    try {
        lt::error_code ec;
        lt::add_torrent_params params;
        if ([source hasPrefix:@"magnet:"]) params = lt::parse_magnet_uri(source.UTF8String, ec);
        else params.ti = std::make_shared<lt::torrent_info>(source.UTF8String, ec);
        if (ec) return [NSString stringWithUTF8String:ec.message().c_str()];
        params.save_path = folder.UTF8String;
        params.flags &= ~lt::torrent_flags::auto_managed;
        params.flags &= ~lt::torrent_flags::paused;
        auto handle = _session->add_torrent(params, ec);
        if (ec) return [NSString stringWithUTF8String:ec.message().c_str()];
        if (std::find(_handles.begin(), _handles.end(), handle) == _handles.end()) _handles.push_back(handle);
        return @"";
    } catch (std::exception const& e) { return [NSString stringWithUTF8String:e.what()]; }
}
- (NSArray<NSDictionary *> *)snapshots {
    NSMutableArray *rows = [NSMutableArray array];
    for (size_t i = 0; i < _handles.size(); ++i) {
        auto s = _handles[i].status();
        NSString *name = [NSString stringWithUTF8String:s.name.c_str()] ?: @"Torrent";
        BOOL paused = bool(s.flags & lt::torrent_flags::paused);
        NSString *state = s.errc ? [NSString stringWithUTF8String:s.errc.message().c_str()] : paused ? @"Paused" : s.is_seeding ? @"Complete · seeding" : s.has_metadata ? @"Downloading" : @"Finding peers and metadata";
        [rows addObject:@{@"id": @(i), @"name":name, @"progress":@(s.progress), @"peers":@(s.num_peers), @"seeds":@(s.num_seeds), @"rate":@(s.download_rate), @"paused":@(paused), @"state":state}];
    }
    return rows;
}
- (void)setPaused:(BOOL)paused index:(NSInteger)index {
    if (index < 0 || size_t(index) >= _handles.size()) return;
    if (paused) _handles[index].pause(); else _handles[index].resume();
}
@end
