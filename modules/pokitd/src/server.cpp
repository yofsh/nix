#include "server.h"

#include "device.h"
#include "session.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QLoggingCategory>

Q_LOGGING_CATEGORY(lcServer, "pokitd.server")

Server::Server(const QString &socketPath, QObject *parent)
    : QObject(parent), m_path(socketPath), m_device(new Device(this, this))
{
    connect(&m_server, &QLocalServer::newConnection,
            this, &Server::onNewConnection);
}

bool Server::start()
{
    // If a socket file already exists, probe whether another daemon is
    // listening. If not, unlink the stale file and continue.
    if (QFile::exists(m_path)) {
        QLocalSocket probe;
        probe.connectToServer(m_path);
        if (probe.waitForConnected(50)) {
            qCCritical(lcServer)
                << "Another pokitd is already listening on" << m_path;
            probe.disconnectFromServer();
            return false;
        }
        QFile::remove(m_path);
    }

    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server.listen(m_path)) {
        qCCritical(lcServer) << "listen() failed:" << m_server.errorString();
        return false;
    }
    qCInfo(lcServer) << "listening on" << m_path;
    return true;
}

void Server::onNewConnection()
{
    while (QLocalSocket *sock = m_server.nextPendingConnection()) {
        auto *session = new Session(sock, m_device, this);
        m_sessions.insert(session);
        connect(session, &QObject::destroyed,
                this, &Server::onSessionDestroyed);
        qCInfo(lcServer) << "client connected; total =" << m_sessions.size();
        emit sessionCountChanged(m_sessions.size());
    }
}

void Server::onSessionDestroyed(QObject *obj)
{
    m_sessions.remove(static_cast<Session *>(obj));
    qCInfo(lcServer) << "client disconnected; total =" << m_sessions.size();
    emit sessionCountChanged(m_sessions.size());
}

void Server::broadcast(const QJsonObject &event)
{
    QByteArray data = QJsonDocument(event).toJson(QJsonDocument::Compact);
    data.append('\n');
    for (Session *s : std::as_const(m_sessions)) {
        s->sendEvent(event);
    }
}
