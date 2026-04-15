#include "session.h"

#include "device.h"
#include "json.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocalSocket>

Session::Session(QLocalSocket *socket, Device *device, QObject *parent)
    : QObject(parent), m_socket(socket), m_device(device)
{
    m_socket->setParent(this);
    connect(m_socket, &QLocalSocket::readyRead, this, &Session::onReadyRead);
    connect(m_socket, &QLocalSocket::disconnected, this, &Session::onDisconnected);

    // Defer hello to the next event loop tick so the caller has finished
    // wiring up signals before we start emitting.
    QMetaObject::invokeMethod(this, &Session::sendHello, Qt::QueuedConnection);
}

void Session::sendEvent(const QJsonObject &event)
{
    if (m_socket->state() != QLocalSocket::ConnectedState) return;
    QByteArray data = QJsonDocument(event).toJson(QJsonDocument::Compact);
    data.append('\n');
    m_socket->write(data);
}

void Session::sendHello()
{
    QJsonObject ev = makeEvent("hello");
    ev.insert(QStringLiteral("protocolVersion"), 1);
    ev.insert(QStringLiteral("daemonVersion"),
              QCoreApplication::applicationVersion());
    // Merge the device snapshot so a newly connected client sees
    // state/device/reading/status without round-tripping.
    if (m_device) {
        const QJsonObject snap = m_device->toJson();
        for (auto it = snap.begin(); it != snap.end(); ++it) {
            ev.insert(QStringLiteral("device_") + it.key(), it.value());
        }
        // Back-compat flat top-level fields for the planned protocol.
        ev.insert(QStringLiteral("deviceState"),
                  snap.value(QStringLiteral("state")).toString());
        ev.insert(QStringLiteral("device"), snap.value(QStringLiteral("device")));
        ev.insert(QStringLiteral("reading"), snap.value(QStringLiteral("reading")));
        ev.insert(QStringLiteral("settings"), snap.value(QStringLiteral("settings")));
        ev.insert(QStringLiteral("subscribed"), snap.value(QStringLiteral("subscribed")));
    }
    ev.insert(QStringLiteral("loggerRunning"), false);
    sendEvent(ev);
}

void Session::onReadyRead()
{
    m_buffer.append(m_socket->readAll());
    while (true) {
        const int nl = m_buffer.indexOf('\n');
        if (nl < 0) break;
        const QByteArray frame = m_buffer.left(nl);
        m_buffer.remove(0, nl + 1);
        if (frame.isEmpty()) continue;
        handleFrame(frame);
    }
}

void Session::handleFrame(const QByteArray &frame)
{
    QJsonParseError err {};
    const QJsonDocument doc = QJsonDocument::fromJson(frame, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        QJsonObject ev = makeEvent("error");
        ev.insert(QStringLiteral("code"), QStringLiteral("invalid_json"));
        ev.insert(QStringLiteral("message"), err.errorString());
        sendEvent(ev);
        return;
    }
    handleCommand(doc.object());
}

void Session::handleCommand(const QJsonObject &cmd)
{
    const QString type = cmd.value(QStringLiteral("type")).toString();
    const QString opId = cmd.value(QStringLiteral("opId")).toString();

    if (type == QLatin1String("ping")) {
        QJsonObject ev = makeEvent("pong");
        if (!opId.isEmpty()) ev.insert(QStringLiteral("opId"), opId);
        sendEvent(ev);
        return;
    }
    if (type == QLatin1String("scan")) {
        m_device->cmdScan(opId, this);
        return;
    }
    if (type == QLatin1String("connect")) {
        const QString mac = cmd.value(QStringLiteral("mac")).toString();
        m_device->cmdConnect(mac, opId, this);
        return;
    }
    if (type == QLatin1String("disconnect")) {
        m_device->cmdDisconnect(opId, this);
        return;
    }
    if (type == QLatin1String("subscribe")) {
        m_device->cmdSubscribe(opId, this);
        return;
    }
    if (type == QLatin1String("unsubscribe")) {
        m_device->cmdUnsubscribe(opId, this);
        return;
    }
    if (type == QLatin1String("setMode")) {
        m_device->cmdSetMode(cmd.value(QStringLiteral("mode")).toString(),
                             cmd.value(QStringLiteral("range")).toString(
                                 QStringLiteral("auto")),
                             opId, this);
        return;
    }
    if (type == QLatin1String("setRange")) {
        m_device->cmdSetRange(cmd.value(QStringLiteral("range")).toString(),
                              opId, this);
        return;
    }
    if (type == QLatin1String("setInterval")) {
        m_device->cmdSetInterval(
            cmd.value(QStringLiteral("intervalMs")).toInt(500), opId, this);
        return;
    }
    if (type == QLatin1String("setTorch")) {
        m_device->cmdSetTorch(cmd.value(QStringLiteral("on")).toBool(false),
                              opId, this);
        return;
    }
    if (type == QLatin1String("flashLed")) {
        m_device->cmdFlashLed(opId, this);
        return;
    }
    if (type == QLatin1String("rename")) {
        m_device->cmdRename(cmd.value(QStringLiteral("name")).toString(),
                            opId, this);
        return;
    }
    if (type == QLatin1String("loggerStart")) {
        m_device->cmdLoggerStart(
            cmd.value(QStringLiteral("mode")).toString(),
            cmd.value(QStringLiteral("range")).toString(QStringLiteral("auto")),
            cmd.value(QStringLiteral("intervalMs")).toInt(1000),
            opId, this);
        return;
    }
    if (type == QLatin1String("loggerStop")) {
        m_device->cmdLoggerStop(opId, this);
        return;
    }
    if (type == QLatin1String("loggerFetch")) {
        m_device->cmdLoggerFetch(opId, this);
        return;
    }
    if (type == QLatin1String("dsoCapture")) {
        m_device->cmdDsoCapture(
            cmd.value(QStringLiteral("mode")).toString(QStringLiteral("DcVoltage")),
            cmd.value(QStringLiteral("sampleRateHz")).toDouble(1000),
            cmd.value(QStringLiteral("samples")).toInt(1024),
            opId, this);
        return;
    }

    QJsonObject ev = makeEvent("error");
    if (!opId.isEmpty()) ev.insert(QStringLiteral("opId"), opId);
    ev.insert(QStringLiteral("code"), QStringLiteral("unknown_type"));
    ev.insert(QStringLiteral("message"),
              QStringLiteral("unknown command: ") + type);
    sendEvent(ev);
}

void Session::onDisconnected()
{
    if (m_device) m_device->sessionGone(this);
    deleteLater();
}
