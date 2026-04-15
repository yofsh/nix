#include "server.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QLoggingCategory>

#include <csignal>

static constexpr const char *kVersion = "0.1.0";

Q_LOGGING_CATEGORY(lcMain, "pokitd")

static QString resolveSocketPath(const QString &override)
{
    if (!override.isEmpty()) return override;
    const QByteArray xdg = qgetenv("XDG_RUNTIME_DIR");
    if (!xdg.isEmpty()) {
        return QString::fromUtf8(xdg) + QStringLiteral("/pokitd/sock");
    }
    // Fallback: per-uid path under /tmp. Uses getuid() indirectly via
    // environment since Qt doesn't bind getuid() directly; good enough for
    // a development fallback.
    const QByteArray uid = qgetenv("UID");
    return QStringLiteral("/tmp/pokitd-%1.sock")
        .arg(uid.isEmpty() ? QStringLiteral("unknown")
                           : QString::fromUtf8(uid));
}

static void handleSignal(int /*signum*/)
{
    // QCoreApplication::quit is documented as thread-safe / signal-safe.
    QCoreApplication::quit();
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("pokitd"));
    QCoreApplication::setApplicationVersion(QString::fromLatin1(kVersion));

    QCommandLineParser parser;
    parser.setApplicationDescription(
        QStringLiteral("Persistent BLE daemon for Pokit multimeters"));
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption socketOpt(
        QStringList{QStringLiteral("s"), QStringLiteral("socket-path")},
        QStringLiteral("Unix socket path to listen on "
                       "(default $XDG_RUNTIME_DIR/pokitd/sock)"),
        QStringLiteral("path"),
        QString());
    parser.addOption(socketOpt);
    parser.process(app);

    const QString path = resolveSocketPath(parser.value(socketOpt));

    Server server(path);
    if (!server.start()) {
        qCCritical(lcMain) << "Failed to start listening on" << path;
        return 1;
    }

    std::signal(SIGTERM, handleSignal);
    std::signal(SIGINT, handleSignal);

    return QCoreApplication::exec();
}
