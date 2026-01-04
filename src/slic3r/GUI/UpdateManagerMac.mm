#include "UpdateManager.hpp"
#include "libslic3r/libslic3r.h"

#ifdef __APPLE__

#ifdef ORCA_HAS_SPARKLE
#import <Sparkle/Sparkle.h>
#endif

#include <boost/log/trivial.hpp>

// ============================================================================
// macOS Implementation (Sparkle 2)
// ============================================================================

#ifdef ORCA_HAS_SPARKLE

// Sparkle updater delegate for custom behavior
// NOTE: Objective-C declarations must be at global scope (outside C++ namespaces)
@interface OrcaSparkleDelegate : NSObject <SPUUpdaterDelegate>
@end

@implementation OrcaSparkleDelegate

// Optional: Add custom parameters to the appcast request
- (NSArray<NSDictionary<NSString *, NSString *> *> *)feedParametersForUpdater:(SPUUpdater *)updater
                                                         sendingSystemProfile:(BOOL)sendingProfile
{
    // Add OrcaSlicer-specific parameters to the update check request
    NSString *version = [NSString stringWithUTF8String:SLIC3R_VERSION];
    NSString *osVersion = [[NSProcessInfo processInfo] operatingSystemVersionString];

    return @[
        @{@"key": @"app_version", @"value": version ?: @"unknown"},
        @{@"key": @"os_version", @"value": osVersion ?: @"unknown"}
    ];
}

// Optional: Handle update errors
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error
{
    BOOST_LOG_TRIVIAL(error) << "UpdateManager: Sparkle update aborted with error: "
                             << [[error localizedDescription] UTF8String];
}

// Optional: Called when an update is found
- (void)updater:(SPUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)item
{
    BOOST_LOG_TRIVIAL(info) << "UpdateManager: Found update to version "
                            << [[item displayVersionString] UTF8String];
}

// Optional: Called when no update is available
- (void)updaterDidNotFindUpdate:(SPUUpdater *)updater
{
    BOOST_LOG_TRIVIAL(info) << "UpdateManager: No update available";
}

@end

// Static Sparkle controller and delegate instances
static SPUStandardUpdaterController *s_updater_controller = nil;
static OrcaSparkleDelegate *s_updater_delegate = nil;

#endif // ORCA_HAS_SPARKLE

namespace Slic3r {
namespace GUI {

// Static member definitions (defined in UpdateManager.cpp for other platforms)
// For macOS, we need to define them here since UpdateManagerMac.mm is compiled instead
bool UpdateManager::s_initialized = false;
std::string UpdateManager::s_appcast_url;
std::string UpdateManager::s_public_key;

#ifdef ORCA_HAS_SPARKLE

void UpdateManager::init(const std::string& appcast_url, const std::string& public_key)
{
    if (s_initialized) {
        BOOST_LOG_TRIVIAL(warning) << "UpdateManager::init called multiple times";
        return;
    }

    s_appcast_url = appcast_url;
    s_public_key = public_key;

    BOOST_LOG_TRIVIAL(info) << "UpdateManager: Initializing Sparkle 2";

    @autoreleasepool {
        // Create the delegate
        s_updater_delegate = [[OrcaSparkleDelegate alloc] init];

        // Create the standard updater controller
        // This reads SUFeedURL and SUPublicEDKey from Info.plist
        s_updater_controller = [[SPUStandardUpdaterController alloc]
            initWithStartingUpdater:YES
                    updaterDelegate:s_updater_delegate
                 userDriverDelegate:nil];

        if (s_updater_controller) {
            s_initialized = true;
            BOOST_LOG_TRIVIAL(info) << "UpdateManager: Sparkle 2 initialized successfully";
        } else {
            BOOST_LOG_TRIVIAL(error) << "UpdateManager: Failed to initialize Sparkle 2";
        }
    }
}

void UpdateManager::check_for_updates_interactive()
{
    if (!s_initialized || !s_updater_controller) {
        BOOST_LOG_TRIVIAL(warning) << "UpdateManager::check_for_updates_interactive called before init";
        return;
    }

    BOOST_LOG_TRIVIAL(info) << "UpdateManager: User-triggered update check (Sparkle)";

    @autoreleasepool {
        [s_updater_controller checkForUpdates:nil];
    }
}

void UpdateManager::check_for_updates_background()
{
    if (!s_initialized || !s_updater_controller) {
        BOOST_LOG_TRIVIAL(warning) << "UpdateManager::check_for_updates_background called before init";
        return;
    }

    BOOST_LOG_TRIVIAL(info) << "UpdateManager: Background update check (Sparkle)";

    @autoreleasepool {
        SPUUpdater *updater = s_updater_controller.updater;
        if (updater) {
            [updater checkForUpdatesInBackground];
        }
    }
}

void UpdateManager::shutdown()
{
    if (!s_initialized) {
        return;
    }

    BOOST_LOG_TRIVIAL(info) << "UpdateManager: Shutting down Sparkle";

    @autoreleasepool {
        // Sparkle handles cleanup automatically when the controller is released
        s_updater_controller = nil;
        s_updater_delegate = nil;
    }

    s_initialized = false;
}

void UpdateManager::set_automatic_check_enabled(bool enabled)
{
    if (!s_initialized || !s_updater_controller) {
        return;
    }

    @autoreleasepool {
        SPUUpdater *updater = s_updater_controller.updater;
        if (updater) {
            updater.automaticallyChecksForUpdates = enabled;
            BOOST_LOG_TRIVIAL(info) << "UpdateManager: Automatic check enabled: " << enabled;
        }
    }
}

#else // !ORCA_HAS_SPARKLE

// Stub implementation when Sparkle is not available

void UpdateManager::init(const std::string& appcast_url, const std::string& public_key)
{
    s_appcast_url = appcast_url;
    s_public_key = public_key;
    s_initialized = true;
    BOOST_LOG_TRIVIAL(info) << "UpdateManager: Sparkle not available (stub)";
}

void UpdateManager::check_for_updates_interactive()
{
    BOOST_LOG_TRIVIAL(info) << "UpdateManager: Interactive update check not available (no Sparkle)";
}

void UpdateManager::check_for_updates_background()
{
    BOOST_LOG_TRIVIAL(info) << "UpdateManager: Background update check not available (no Sparkle)";
}

void UpdateManager::shutdown()
{
    s_initialized = false;
}

void UpdateManager::set_automatic_check_enabled(bool enabled)
{
    // No-op
}

#endif // ORCA_HAS_SPARKLE

} // namespace GUI
} // namespace Slic3r

#endif // __APPLE__
