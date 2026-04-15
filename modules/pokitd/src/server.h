#pragma once

#include <QLocalServer>
#include <QObject>
#include <QSet>
#include <QString>

class QJsonObject;
class Session;
class Device;

class Server : public QObject {
    Q_OBJECT
public:
    Server(const QString &socketPath, QObject *parent = nullptr);

    // Binds to the configured socket path. Unlinks a stale socket file
    // when no other daemon is listening there. Returns false on failure.
    bool start();

    // Fan an event out to every connected session.
    void broadcast(const QJsonObject &event);

    int sessionCount() const { return m_sessions.size(); }

signals:
    void sessionCountChanged(int count);

private slots:
    void onNewConnection();
    void onSessionDestroyed(QObject *obj);

private:
    QLocalServer m_server;
    QString m_path;
    Device *m_device;
    QSet<Session *> m_sessions;
};
