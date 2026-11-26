#include "desktopmedia.h"
#include "soundcloud.h"
#include <QPointer>
#include <QCoreApplication>
#include <QUrl>
#include <cmath>
#include <limits>
#import <AppKit/AppKit.h>
#import <MediaPlayer/MediaPlayer.h>

struct DesktopMedia::Platform {
    NSMutableArray *commands = [[NSMutableArray alloc] init];
    NSMutableArray *tokens = [[NSMutableArray alloc] init];
    QString artworkPath;
    MPMediaItemArtwork *artwork = nil;
    qint64 positionSecond = -1;
    qint64 duration = -1;

    void updateArtwork(const QString &path) {
        if (artworkPath == path) return;
        artworkPath = path;
        [artwork release];
        artwork = nil;
        if (path.isEmpty()) return;
        const auto file = QUrl(path).toLocalFile().toUtf8();
        NSImage *cover = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:file.constData()]];
        if (cover) {
            artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:cover.size requestHandler:^NSImage *(CGSize) {
                return cover;
            }];
            [cover release];
        }
    }
    ~Platform() {
        [artwork release];
        for (NSUInteger i = 0; i < commands.count; ++i)
            [(MPRemoteCommand *)commands[i] removeTarget:tokens[i]];
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
        [MPNowPlayingInfoCenter defaultCenter].playbackState = MPNowPlayingPlaybackStateStopped;
        [commands release]; [tokens release];
    }
};

DesktopMedia::DesktopMedia(SoundCloud *controller, QWindow *window, QObject *parent)
    : QObject(parent), m_controller(controller), m_window(window) {
    initializePlatform();
    connect(controller, &SoundCloud::catalogChanged, this, &DesktopMedia::updated);
    connect(controller, &SoundCloud::progressChanged, this, [this] {
        if (m_controller->position() / 1000 != m_platform->positionSecond
            || m_controller->duration() != m_platform->duration) emit updated();
    });
    connect(controller, &SoundCloud::playbackSeeked, this, [this] {
        emit seeked(m_controller->position() * 1000);
        emit updated();
    });
    auto refresh = [this] {
        @autoreleasepool {
            const auto s = snapshot();
            m_platform->positionSecond = m_controller->position() / 1000;
            m_platform->duration = m_controller->duration();
            m_platform->updateArtwork(s.value("artwork").toString());
            auto *center = [MPNowPlayingInfoCenter defaultCenter];
            if (!s.value("hasTrack").toBool()) {
                center.nowPlayingInfo = nil;
                center.playbackState = MPNowPlayingPlaybackStateStopped;
            } else {
                const auto title = s.value("title").toString().toUtf8();
                const auto artist = s.value("artist").toString().toUtf8();
                const bool playing = s.value("status").toString() == "Playing";
                NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
                    MPMediaItemPropertyTitle: [NSString stringWithUTF8String:title.constData()],
                    MPMediaItemPropertyArtist: [NSString stringWithUTF8String:artist.constData()],
                    MPMediaItemPropertyPlaybackDuration: @(s.value("duration").toLongLong() / 1000.0),
                    MPNowPlayingInfoPropertyElapsedPlaybackTime: @(s.value("position").toLongLong() / 1000.0),
                    MPNowPlayingInfoPropertyPlaybackRate: @(playing ? 1.0 : 0.0)
                }];
                if (m_platform->artwork) info[MPMediaItemPropertyArtwork] = m_platform->artwork;
                center.nowPlayingInfo = info;
                center.playbackState = playing ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;
            }
            auto *remote = [MPRemoteCommandCenter sharedCommandCenter];
            remote.playCommand.enabled = s.value("canPlay").toBool();
            remote.togglePlayPauseCommand.enabled = s.value("canPlay").toBool();
            remote.pauseCommand.enabled = s.value("hasTrack").toBool();
            remote.stopCommand.enabled = s.value("hasTrack").toBool();
            remote.nextTrackCommand.enabled = s.value("canNext").toBool();
            remote.previousTrackCommand.enabled = s.value("canPrevious").toBool();
            remote.changePlaybackPositionCommand.enabled = s.value("canSeek").toBool();
        }
    };
    connect(this, &DesktopMedia::updated, this, refresh);
    refresh();
}
void DesktopMedia::initializePlatform() {
    m_platform = std::make_unique<Platform>();
    auto *remote = [MPRemoteCommandCenter sharedCommandCenter];
    const QPointer<DesktopMedia> guard(this);
    auto bind = [&](MPRemoteCommand *remoteCommand, const QString &action) {
        id token = [remoteCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *) {
            // Apple may invoke handlers outside Qt's GUI thread.
            QMetaObject::invokeMethod(qApp, [guard, action] { if (guard) guard->command(action); }, Qt::QueuedConnection);
            return MPRemoteCommandHandlerStatusSuccess;
        }];
        [m_platform->commands addObject:remoteCommand];
        [m_platform->tokens addObject:token];
    };
    bind(remote.playCommand, "play"); bind(remote.pauseCommand, "pause");
    bind(remote.togglePlayPauseCommand, "toggle"); bind(remote.stopCommand, "stop");
    bind(remote.nextTrackCommand, "next"); bind(remote.previousTrackCommand, "previous");
    id token = [remote.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        const double seconds = [(MPChangePlaybackPositionCommandEvent *)event positionTime];
        if (!std::isfinite(seconds) || seconds < 0 || seconds > double(std::numeric_limits<qint64>::max() / 1000))
            return MPRemoteCommandHandlerStatusCommandFailed;
        const qint64 position = qint64(seconds * 1000);
        QMetaObject::invokeMethod(qApp, [guard, position] { if (guard) guard->command("seek", position); }, Qt::QueuedConnection);
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [m_platform->commands addObject:remote.changePlaybackPositionCommand];
    [m_platform->tokens addObject:token];
}
DesktopMedia::~DesktopMedia() = default;
