#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QObject>

class QLocalSocket;
class Device;

class Session : public QObject {
    Q_OBJECT
public:
    Session(QLocalSocket *socket, Device *device, QObject *parent = nullptr);

    // Send a pre-built JSON event to this one client.
    void sendEvent(const QJsonObject &event);

private slots:
    void onReadyRead();
    void onDisconnected();

private:
    void handleFrame(const QByteArray &frame);
    void handleCommand(const QJsonObject &cmd);
    void sendHello();

    QLocalSocket *m_socket;
    Device *m_device;
    QByteArray m_buffer;
};
