#include "device.h"

#include "json.h"
#include "server.h"
#include "session.h"

#include <qtpokit/pokitdevice.h>
#include <qtpokit/pokitdiscoveryagent.h>
#include <qtpokit/pokitpro.h>
#include <qtpokit/pokitproducts.h>

#include <QBluetoothAddress>
#include <QDateTime>
#include <QLoggingCategory>
#include <QTimer>
#include <QLowEnergyController>

Q_LOGGING_CATEGORY(lcDev, "pokitd.device")

// ──────────────────────────────────────────────────────────────────────────
// Construction / destruction

Device::Device(Server *server, QObject *parent)
    : QObject(parent), m_server(server)
{
}

Device::~Device() = default;

QJsonObject Device::toJson() const
{
    QJsonObject obj;
    obj.insert(QStringLiteral("state"), m_state);
    if (m_currentInfo.isValid())
        obj.insert(QStringLiteral("device"), infoToJson(m_currentInfo));
    else
        obj.insert(QStringLiteral("device"), QJsonValue(QJsonValue::Null));
    QJsonObject settings;
    settings.insert(QStringLiteral("mode"), modeToString(m_currentMode));
    settings.insert(QStringLiteral("range"),
                    rangeToString(m_currentRange, m_currentMode));
    settings.insert(QStringLiteral("intervalMs"),
                    static_cast<qint64>(m_updateInterval));
    obj.insert(QStringLiteral("settings"), settings);
    obj.insert(QStringLiteral("subscribed"), !m_subscribers.isEmpty());

    if (m_haveReading) {
        QJsonObject r;
        r.insert(QStringLiteral("value"), m_lastReading.value);
        r.insert(QStringLiteral("unit"), unitForMode(m_lastReading.mode));
        r.insert(QStringLiteral("mode"), modeToString(m_lastReading.mode));
        r.insert(QStringLiteral("range"),
                 rangeToString(m_lastReading.range, m_lastReading.mode));
        r.insert(QStringLiteral("status"),
                 readingStatusToString(m_lastReading.status, m_lastReading.mode));
        obj.insert(QStringLiteral("reading"), r);
    } else {
        obj.insert(QStringLiteral("reading"), QJsonValue::Null);
    }

    if (m_haveStatus) {
        QJsonObject s;
        s.insert(QStringLiteral("batteryVoltage"), m_lastStatus.batteryVoltage);
        s.insert(QStringLiteral("deviceStatus"),
                 StatusService::toString(m_lastStatus.deviceStatus));
        s.insert(QStringLiteral("firmware"),
                 m_lastChars.firmwareVersion.toString());
        s.insert(QStringLiteral("name"), m_deviceName);
        obj.insert(QStringLiteral("status"), s);
    } else {
        obj.insert(QStringLiteral("status"), QJsonValue::Null);
    }

    return obj;
}

QJsonObject Device::infoToJson(const QBluetoothDeviceInfo &info) const
{
    QJsonObject obj;
    obj.insert(QStringLiteral("mac"), info.address().toString());
    obj.insert(QStringLiteral("name"), info.name());
    obj.insert(QStringLiteral("rssi"), info.rssi());
    obj.insert(QStringLiteral("isPokit"), isPokitProduct(info));
    return obj;
}

// ──────────────────────────────────────────────────────────────────────────
// State helpers

void Device::setState(const QString &next)
{
    if (m_state == next) return;
    qCInfo(lcDev) << "state:" << m_state << "→" << next;
    m_state = next;

    QJsonObject ev = makeEvent("deviceState");
    ev.insert(QStringLiteral("state"), m_state);
    m_server->broadcast(ev);
}

// ──────────────────────────────────────────────────────────────────────────
// Scan

void Device::ensureAgent()
{
    if (m_agent) return;
    m_agent = new PokitDiscoveryAgent(this);
    connect(m_agent, &PokitDiscoveryAgent::pokitDeviceDiscovered,
            this, &Device::onPokitDiscovered);
    connect(m_agent, &QBluetoothDeviceDiscoveryAgent::finished,
            this, &Device::onScanFinished);
    connect(m_agent, &QBluetoothDeviceDiscoveryAgent::errorOccurred,
            this, [this]() {
                qCWarning(lcDev) << "scan error:" << m_agent->errorString();
                finishScan();
            });
}

void Device::cmdScan(const QString &opId, Session *sender)
{
    // If we already know the device (ready/connecting), just return the
    // cached info synthetically. A real rescan would tear down the live
    // BLE link — exactly what we're trying to avoid.
    if (m_pokit && m_currentInfo.isValid()) {
        QJsonObject ev = makeEvent("scanResult");
        QJsonArray arr; arr.append(infoToJson(m_currentInfo));
        ev.insert(QStringLiteral("devices"), arr);
        if (!opId.isEmpty()) ev.insert(QStringLiteral("opId"), opId);
        m_server->broadcast(ev);
        replyAck(opId, sender, true);
        return;
    }

    ensureAgent();

    // If a scan is already running, DO NOT wipe m_scanBatch — that would
    // drop devices discovered so far. Just note the latest requester so
    // they receive the scanResult ack.
    if (m_agent->isActive()) {
        if (!opId.isEmpty()) {
            m_scanOpId = opId;
            m_scanSender = sender;
        }
        return;
    }

    m_scanBatch = {};
    m_scanOpId = opId;
    m_scanSender = sender;
    startScanInternal();
}

void Device::startScanInternal()
{
    setState(QStringLiteral("scanning"));
    m_agent->setLowEnergyDiscoveryTimeout(3000);
    m_agent->start(QBluetoothDeviceDiscoveryAgent::LowEnergyMethod);
}

void Device::onPokitDiscovered(const QBluetoothDeviceInfo &info)
{
    qCInfo(lcDev) << "discovered:" << info.address().toString() << info.name();
    m_scanBatch.append(infoToJson(info));

    QJsonObject ev = makeEvent("deviceDiscovered");
    ev.insert(QStringLiteral("mac"), info.address().toString());
    ev.insert(QStringLiteral("name"), info.name());
    ev.insert(QStringLiteral("rssi"), info.rssi());
    m_server->broadcast(ev);

    if (!m_currentInfo.isValid()) m_currentInfo = info;
}

void Device::onScanFinished()
{
    finishScan();
    if (m_pokit) return;
    if (!m_currentInfo.isValid() || m_scanBatch.isEmpty()) {
        setState(QStringLiteral("idle"));
        return;
    }
    setState(QStringLiteral("discovered"));
    beginConnectInternal(m_currentInfo);
}

void Device::finishScan()
{
    QJsonObject ev = makeEvent("scanResult");
    ev.insert(QStringLiteral("devices"), m_scanBatch);
    if (!m_scanOpId.isEmpty()) {
        ev.insert(QStringLiteral("opId"), m_scanOpId);
    }
    m_server->broadcast(ev);

    if (m_scanSender && !m_scanOpId.isEmpty()) {
        replyAck(m_scanOpId, m_scanSender, true);
    }
    m_scanOpId.clear();
    m_scanSender.clear();
}

// ──────────────────────────────────────────────────────────────────────────
// Connect / disconnect

void Device::cmdConnect(const QString &mac, const QString &opId, Session *sender)
{
    m_connectOpId = opId;
    m_connectSender = sender;

    if (!mac.isEmpty()) {
        QBluetoothAddress addr(mac);
        if (addr.isNull()) {
            replyAck(opId, sender, false,
                     QStringLiteral("bad_mac"), QStringLiteral("invalid MAC"));
            m_connectOpId.clear(); m_connectSender.clear();
            return;
        }
        m_currentInfo = QBluetoothDeviceInfo(addr, QStringLiteral("Pokit"), 0);
    }

    if (!m_currentInfo.isValid()) {
        cmdScan(opId, sender);
        return;
    }
    if (m_pokit) {
        replyAck(opId, sender, true);
        m_connectOpId.clear(); m_connectSender.clear();
        return;
    }
    beginConnectInternal(m_currentInfo);
}

void Device::beginConnectInternal(const QBluetoothDeviceInfo &info)
{
    Q_ASSERT(!m_pokit);
    setState(QStringLiteral("connecting"));
    m_multimeterReady = m_statusReady = false;

    m_pokit = new PokitDevice(info, this);
    auto *controller = m_pokit->controller();
    connect(controller, &QLowEnergyController::connected,
            this, &Device::onControllerConnected);
    connect(controller, &QLowEnergyController::disconnected,
            this, &Device::onControllerDisconnected);
    connect(controller, &QLowEnergyController::errorOccurred,
            this, &Device::onControllerError);

    // Follow the dokit CLI pattern: create services BEFORE connecting.
    // Their internal `AbstractPokitServicePrivate` listens for the
    // controller's serviceDiscovered/discoveryFinished events to trigger
    // discoverDetails() — if we create services AFTER discovery finishes,
    // those signals are already gone and the services never wire up.
    const auto product = pokitProduct(info);

    m_multimeter = m_pokit->multimeter();
    m_multimeter->setPokitProduct(product);
    connect(m_multimeter, &AbstractPokitService::serviceDetailsDiscovered,
            this, &Device::onMultimeterServiceReady);
    connect(m_multimeter, &MultimeterService::readingRead,
            this, &Device::onMultimeterReading);
    connect(m_multimeter, &MultimeterService::settingsWritten,
            this, &Device::onMultimeterSettingsWritten);

    m_status = m_pokit->status();
    m_status->setPokitProduct(product);
    connect(m_status, &AbstractPokitService::serviceDetailsDiscovered,
            this, &Device::onStatusServiceReady);
    connect(m_status, &StatusService::deviceCharacteristicsRead,
            this, &Device::onDeviceCharacteristicsRead);
    connect(m_status, &StatusService::deviceStatusRead,
            this, &Device::onDeviceStatusRead);
    connect(m_status, &StatusService::deviceNameRead,
            this, &Device::onDeviceNameRead);
    connect(m_status, &StatusService::deviceNameWritten,
            this, &Device::onDeviceNameWritten);
    connect(m_status, &StatusService::torchStatusWritten,
            this, &Device::onTorchWritten);
    connect(m_status, &StatusService::deviceLedFlashed,
            this, &Device::onLedFlashed);

    m_logger = m_pokit->dataLogger();
    m_logger->setPokitProduct(product);
    connect(m_logger, &AbstractPokitService::serviceDetailsDiscovered,
            this, &Device::onLoggerServiceReady);
    connect(m_logger, &DataLoggerService::settingsWritten,
            this, &Device::onLoggerSettingsWritten);
    connect(m_logger, &DataLoggerService::metadataRead,
            this, &Device::onLoggerMetadataRead);
    connect(m_logger, &DataLoggerService::samplesRead,
            this, &Device::onLoggerSamplesRead);

    m_dso = m_pokit->dso();
    m_dso->setPokitProduct(product);
    connect(m_dso, &AbstractPokitService::serviceDetailsDiscovered,
            this, &Device::onDsoServiceReady);
    connect(m_dso, &DsoService::settingsWritten,
            this, &Device::onDsoSettingsWritten);
    connect(m_dso, &DsoService::metadataRead,
            this, &Device::onDsoMetadataRead);
    connect(m_dso, &DsoService::samplesRead,
            this, &Device::onDsoSamplesRead);

    controller->connectToDevice();
}

void Device::onControllerConnected()
{
    qCInfo(lcDev) << "BLE connected";
    QJsonObject ev = makeEvent("deviceConnected");
    ev.insert(QStringLiteral("mac"), m_currentInfo.address().toString());
    ev.insert(QStringLiteral("name"), m_currentInfo.name());
    m_server->broadcast(ev);

    if (!m_connectOpId.isEmpty()) {
        replyAck(m_connectOpId, m_connectSender, true);
        m_connectOpId.clear(); m_connectSender.clear();
    }

    setState(QStringLiteral("discoveringServices"));

    // Services were created before connectToDevice(); QtPokit's internal
    // machinery will now finish discovery for each and emit
    // serviceDetailsDiscovered independently.
    m_pokit->controller()->discoverServices();
}

void Device::onControllerDisconnected()
{
    qCInfo(lcDev) << "BLE disconnected";
    QJsonObject ev = makeEvent("deviceDisconnected");
    ev.insert(QStringLiteral("reason"), QStringLiteral("remote_closed"));
    m_server->broadcast(ev);

    if (m_pokit) {
        m_pokit->deleteLater();
        m_pokit = nullptr;
        m_multimeter = nullptr;
        m_status = nullptr;
        m_logger = nullptr;
        m_dso = nullptr;
    }
    m_multimeterReady = m_statusReady = m_loggerReady = m_dsoReady = false;
    m_haveReading = false;
    m_haveStatus = false;
    m_haveLoggerMeta = false;
    m_loggerRunning = false;
    m_deviceName.clear();
    m_currentInfo = {};
    setState(QStringLiteral("idle"));

    // If a logger fetch was deferred across this reconnect, kick a scan
    // to re-establish the BLE link and retry once services come up.
    if (m_pendingFetchAfterReconnect) {
        qCInfo(lcDev) << "post-disconnect: rescanning to retry logger fetch";
        cmdScan(QString(), nullptr);
    }
}

void Device::onControllerError()
{
    if (!m_pokit) return;
    const QString msg = m_pokit->controller()->errorString();
    qCWarning(lcDev) << "BLE controller error:" << msg;

    QJsonObject ev = makeEvent("error");
    ev.insert(QStringLiteral("code"), QStringLiteral("ble_error"));
    ev.insert(QStringLiteral("message"), msg);
    m_server->broadcast(ev);

    if (!m_connectOpId.isEmpty()) {
        replyAck(m_connectOpId, m_connectSender, false,
                 QStringLiteral("ble_error"), msg);
        m_connectOpId.clear(); m_connectSender.clear();
    }
    teardownAsync(QStringLiteral("ble_error"));
}

void Device::cmdDisconnect(const QString &opId, Session *sender)
{
    if (m_pokit) m_pokit->controller()->disconnectFromDevice();
    else setState(QStringLiteral("idle"));
    replyAck(opId, sender, true);
}

void Device::teardownAsync(const QString &reason)
{
    setState(QStringLiteral("disconnecting"));
    if (m_pokit) m_pokit->controller()->disconnectFromDevice();
    else setState(QStringLiteral("idle"));
}

// ──────────────────────────────────────────────────────────────────────────
// Service-discovery → ready

void Device::onMultimeterServiceReady()
{
    qCInfo(lcDev) << "multimeter service ready";
    m_multimeterReady = true;
    transitionToReadyIfBothServicesUp();
}

void Device::onStatusServiceReady()
{
    qCInfo(lcDev) << "status service ready";
    m_statusReady = true;
    if (m_status) {
        m_status->readDeviceCharacteristics();
        m_status->readStatusCharacteristic();
        m_status->readNameCharacteristic();
    }
    transitionToReadyIfBothServicesUp();
}

void Device::transitionToReadyIfBothServicesUp()
{
    // Treat "ready" as soon as multimeter is up (streaming is the critical
    // path). Status may arrive slightly later and populate battery/fw.
    if (!m_multimeterReady) return;
    setState(QStringLiteral("ready"));
    if (!m_subscribers.isEmpty() && m_multimeter) {
        applyCurrentSettings();
        m_multimeter->enableReadingNotifications();
    }

}

void Device::applyCurrentSettings()
{
    if (!m_multimeter) return;
    MultimeterService::Settings s;
    s.mode = m_currentMode;
    s.range = m_currentRange;
    s.updateInterval = m_updateInterval;
    m_multimeter->setSettings(s);
}

bool Device::ensureReady(const QString &opId, Session *sender)
{
    if (m_state == QLatin1String("ready")) return true;
    replyAck(opId, sender, false, QStringLiteral("not_ready"),
             QStringLiteral("device state: ") + m_state);
    return false;
}

// ──────────────────────────────────────────────────────────────────────────
// Subscribe / unsubscribe

void Device::cmdSubscribe(const QString &opId, Session *sender)
{
    const bool wasEmpty = m_subscribers.isEmpty();
    if (sender) m_subscribers.insert(sender);

    // If we're idle and nobody's scanning, kick a scan+connect so the
    // subscription eventually delivers readings.
    if (m_state == QLatin1String("idle") && !m_agent) {
        cmdScan(QString(), nullptr); // no-opId passive scan; will auto-connect
    } else if (m_state == QLatin1String("idle")) {
        cmdScan(QString(), nullptr);
    }

    if (wasEmpty && m_multimeterReady && m_multimeter) {
        applyCurrentSettings();
        m_multimeter->enableReadingNotifications();
    }
    replyAck(opId, sender, true);
}

void Device::cmdUnsubscribe(const QString &opId, Session *sender)
{
    if (sender) m_subscribers.remove(sender);
    if (m_subscribers.isEmpty() && m_multimeter && m_multimeterReady) {
        m_multimeter->disableReadingNotifications();
    }
    replyAck(opId, sender, true);
}

void Device::sessionGone(Session *s)
{
    m_subscribers.remove(s);
    if (m_subscribers.isEmpty() && m_multimeter && m_multimeterReady) {
        m_multimeter->disableReadingNotifications();
    }
}

// ──────────────────────────────────────────────────────────────────────────
// Multimeter settings (mode / range / interval)

void Device::cmdSetMode(const QString &mode, const QString &range,
                        const QString &opId, Session *sender)
{
    if (!ensureReady(opId, sender)) return;
    bool ok;
    auto m = parseMode(mode, &ok);
    if (!ok) {
        replyAck(opId, sender, false,
                 QStringLiteral("bad_mode"),
                 QStringLiteral("unknown mode: ") + mode);
        return;
    }
    m_currentMode = m;
    m_currentRange = parseRangeForMode(range, m);
    // User explicitly wants live readings now — reclaim the ADC.
    if (m_multimeterSuspendedForLogger) m_multimeterSuspendedForLogger = false;
    m_settingsOpId = opId;
    m_settingsSender = sender;
    applyCurrentSettings();
}

void Device::cmdSetRange(const QString &range, const QString &opId,
                         Session *sender)
{
    if (!ensureReady(opId, sender)) return;
    m_currentRange = parseRangeForMode(range, m_currentMode);
    m_settingsOpId = opId;
    m_settingsSender = sender;
    applyCurrentSettings();
}

void Device::cmdSetInterval(int intervalMs, const QString &opId,
                            Session *sender)
{
    if (!ensureReady(opId, sender)) return;
    if (intervalMs < 50 || intervalMs > 60000) {
        replyAck(opId, sender, false, QStringLiteral("bad_interval"),
                 QStringLiteral("interval out of range 50..60000 ms"));
        return;
    }
    m_updateInterval = static_cast<quint32>(intervalMs);
    m_settingsOpId = opId;
    m_settingsSender = sender;
    applyCurrentSettings();
}

void Device::onMultimeterSettingsWritten()
{
    if (!m_settingsOpId.isEmpty()) {
        replyAck(m_settingsOpId, m_settingsSender, true);
        m_settingsOpId.clear();
        m_settingsSender.clear();
    }
    // Broadcast authoritative settings.
    QJsonObject ev = makeEvent("settings");
    ev.insert(QStringLiteral("mode"), modeToString(m_currentMode));
    ev.insert(QStringLiteral("range"),
              rangeToString(m_currentRange, m_currentMode));
    ev.insert(QStringLiteral("intervalMs"),
              static_cast<qint64>(m_updateInterval));
    m_server->broadcast(ev);
}

void Device::onMultimeterReading(const MultimeterService::Reading &reading)
{
    m_lastReading = reading;
    m_haveReading = true;
    emitReading(reading);
}

void Device::emitReading(const MultimeterService::Reading &r)
{
    QJsonObject ev = makeEvent("reading");
    ev.insert(QStringLiteral("value"), r.value);
    ev.insert(QStringLiteral("unit"), unitForMode(r.mode));
    ev.insert(QStringLiteral("mode"), modeToString(r.mode));
    ev.insert(QStringLiteral("range"), rangeToString(r.range, r.mode));
    ev.insert(QStringLiteral("status"),
              readingStatusToString(r.status, r.mode));
    m_server->broadcast(ev);
}

// ──────────────────────────────────────────────────────────────────────────
// Control ops: torch / flash / rename

void Device::cmdSetTorch(bool on, const QString &opId, Session *sender)
{
    if (!ensureReady(opId, sender) || !m_status) return;
    m_torchOpId = opId;
    m_torchSender = sender;
    m_status->setTorchStatus(on ? StatusService::TorchStatus::On
                                : StatusService::TorchStatus::Off);
}

void Device::cmdFlashLed(const QString &opId, Session *sender)
{
    if (!ensureReady(opId, sender) || !m_status) return;
    m_flashOpId = opId;
    m_flashSender = sender;
    m_status->flashLed();
}

void Device::cmdRename(const QString &name, const QString &opId, Session *sender)
{
    if (!ensureReady(opId, sender) || !m_status) return;
    if (name.isEmpty() || name.toUtf8().size() > 11) {
        replyAck(opId, sender, false, QStringLiteral("bad_name"),
                 QStringLiteral("name must be 1-11 UTF-8 bytes"));
        return;
    }
    m_renameOpId = opId;
    m_renameSender = sender;
    m_status->setDeviceName(name);
}

void Device::onTorchWritten()
{
    if (!m_torchOpId.isEmpty()) {
        replyAck(m_torchOpId, m_torchSender, true);
        m_torchOpId.clear(); m_torchSender.clear();
    }
}

void Device::onLedFlashed()
{
    if (!m_flashOpId.isEmpty()) {
        replyAck(m_flashOpId, m_flashSender, true);
        m_flashOpId.clear(); m_flashSender.clear();
    }
}

void Device::onDeviceNameWritten()
{
    if (!m_renameOpId.isEmpty()) {
        replyAck(m_renameOpId, m_renameSender, true);
        m_renameOpId.clear(); m_renameSender.clear();
    }
}

// ──────────────────────────────────────────────────────────────────────────
// Data logger

static DataLoggerService::Mode loggerModeFromString(const QString &s, bool *ok)
{
    *ok = true;
    if (s == QLatin1String("DcVoltage"))   return DataLoggerService::Mode::DcVoltage;
    if (s == QLatin1String("AcVoltage"))   return DataLoggerService::Mode::AcVoltage;
    if (s == QLatin1String("DcCurrent"))   return DataLoggerService::Mode::DcCurrent;
    if (s == QLatin1String("AcCurrent"))   return DataLoggerService::Mode::AcCurrent;
    if (s == QLatin1String("Temperature")) return DataLoggerService::Mode::Temperature;
    *ok = false;
    return DataLoggerService::Mode::Idle;
}

static QString loggerModeToString(DataLoggerService::Mode m)
{
    switch (m) {
    case DataLoggerService::Mode::DcVoltage:   return QStringLiteral("DcVoltage");
    case DataLoggerService::Mode::AcVoltage:   return QStringLiteral("AcVoltage");
    case DataLoggerService::Mode::DcCurrent:   return QStringLiteral("DcCurrent");
    case DataLoggerService::Mode::AcCurrent:   return QStringLiteral("AcCurrent");
    case DataLoggerService::Mode::Temperature: return QStringLiteral("Temperature");
    case DataLoggerService::Mode::Idle:        return QStringLiteral("Idle");
    }
    return QStringLiteral("Idle");
}

static QString loggerUnitForMode(DataLoggerService::Mode m)
{
    switch (m) {
    case DataLoggerService::Mode::DcVoltage:
    case DataLoggerService::Mode::AcVoltage:   return QStringLiteral("V");
    case DataLoggerService::Mode::DcCurrent:
    case DataLoggerService::Mode::AcCurrent:   return QStringLiteral("A");
    case DataLoggerService::Mode::Temperature: return QStringLiteral("°C");
    case DataLoggerService::Mode::Idle:        return QString();
    }
    return QString();
}

void Device::onLoggerServiceReady()
{
    qCInfo(lcDev) << "logger service ready";
    m_loggerReady = true;

    // If a logger fetch was deferred across a reconnect, retry it now
    // that the new (clean) logger service is ready.
    if (m_pendingFetchAfterReconnect && m_logger) {
        m_pendingFetchAfterReconnect = false;
        m_logger->enableMetadataNotifications();
        m_logger->enableReadingNotifications();
        QTimer::singleShot(200, this, [this]() {
            if (!m_logger) return;
            const bool ok = m_logger->fetchSamples();
            qCInfo(lcDev) << "logger fetchSamples (post-reconnect) returned" << ok;
            if (!ok && !m_loggerFetchOpId.isEmpty()) {
                replyAck(m_loggerFetchOpId, m_loggerFetchSender, false,
                         QStringLiteral("write_failed"),
                         QStringLiteral("fetchSamples failed after reconnect"));
                m_loggerFetchOpId.clear(); m_loggerFetchSender.clear();
            }
        });
    }
}

void Device::suspendMultimeterForLogger()
{
    if (m_multimeterSuspendedForLogger || !m_multimeter || !m_multimeterReady)
        return;
    qCInfo(lcDev) << "suspending multimeter for logger ADC use";
    m_multimeter->disableReadingNotifications();
    MultimeterService::Settings idle;
    idle.mode = MultimeterService::Mode::Idle;
    idle.range = 0;
    idle.updateInterval = 1000;
    m_multimeter->setSettings(idle);
    m_multimeterSuspendedForLogger = true;
}

void Device::resumeMultimeterFromLogger()
{
    if (!m_multimeterSuspendedForLogger || !m_multimeter || !m_multimeterReady)
        return;
    qCInfo(lcDev) << "resuming multimeter from logger";
    m_multimeterSuspendedForLogger = false;
    if (!m_subscribers.isEmpty()) {
        applyCurrentSettings();
        m_multimeter->enableReadingNotifications();
    }
}

void Device::cmdLoggerStart(const QString &mode, const QString &range,
                            int intervalMs, const QString &opId, Session *sender)
{
    if (!ensureReady(opId, sender) || !m_logger || !m_loggerReady) {
        replyAck(opId, sender, false, QStringLiteral("not_ready"),
                 QStringLiteral("logger service not yet discovered"));
        return;
    }
    bool ok = false;
    DataLoggerService::Mode m = loggerModeFromString(mode, &ok);
    if (!ok) {
        replyAck(opId, sender, false, QStringLiteral("bad_mode"),
                 QStringLiteral("logger mode must be DcVoltage/AcVoltage/"
                                "DcCurrent/AcCurrent/Temperature: ") + mode);
        return;
    }
    // Pokit Pro has ONE ADC. If multimeter is actively measuring, the
    // logger-Start write will be rejected by the device (ATT error 0x80).
    suspendMultimeterForLogger();

    DataLoggerService::Settings s;
    s.command = DataLoggerService::Command::Start;
    s.arguments = 0;
    s.mode = m;
    // Pokit Pro logger does NOT accept AutoRange (255). Pick a sensible
    // default: for voltage modes use _10V (range index 2); for current
    // _3A (5); resistance not supported by logger anyway. User can
    // refine via the protocol if/when we add range arg parsing.
    Q_UNUSED(range);
    switch (m) {
    case DataLoggerService::Mode::DcVoltage:
    case DataLoggerService::Mode::AcVoltage:   s.range = 2; break; // _10V
    case DataLoggerService::Mode::DcCurrent:
    case DataLoggerService::Mode::AcCurrent:   s.range = 5; break; // _3A
    case DataLoggerService::Mode::Temperature: s.range = 0; break;
    default:                                    s.range = 0; break;
    }
    s.updateInterval = (intervalMs > 0 ? intervalMs : 1000);
    s.timestamp = static_cast<quint32>(QDateTime::currentSecsSinceEpoch());

    m_loggerOpId = opId;
    m_loggerSender = sender;
    if (!m_logger->startLogger(s)) {
        replyAck(opId, sender, false, QStringLiteral("write_failed"),
                 QStringLiteral("logger start write failed"));
        m_loggerOpId.clear(); m_loggerSender.clear();
        return;
    }
    // Optimistically mark as running; confirmed by settingsWritten + fetch.
    m_loggerRunning = true;
}

void Device::cmdLoggerStop(const QString &opId, Session *sender)
{
    if (!ensureReady(opId, sender) || !m_logger || !m_loggerReady) {
        replyAck(opId, sender, false, QStringLiteral("not_ready"), QString());
        return;
    }
    m_loggerOpId = opId;
    m_loggerSender = sender;
    if (!m_logger->stopLogger()) {
        replyAck(opId, sender, false, QStringLiteral("write_failed"),
                 QStringLiteral("logger stop write failed"));
        m_loggerOpId.clear(); m_loggerSender.clear();
        return;
    }
    m_loggerRunning = false;
    // Multimeter can use the ADC again; resume on Stop ack via
    // onLoggerSettingsWritten.
}

void Device::cmdLoggerFetch(const QString &opId, Session *sender)
{
    if (!ensureReady(opId, sender) || !m_logger || !m_loggerReady) {
        replyAck(opId, sender, false, QStringLiteral("not_ready"), QString());
        return;
    }
    // Same ADC contention applies to fetch: device needs to focus on the
    // logger-buffer transfer, not on running a measurement.
    suspendMultimeterForLogger();
    m_loggerFetchOpId = opId;
    m_loggerFetchSender = sender;
    // Both metadata AND reading (samples) notifications must be enabled
    // before fetch — otherwise the device ACKs with nothing. Matches the
    // sequence in dokit's own loggerfetchcommand.cpp.
    // QLowEnergyService::error() is a sticky flag — once Settings writes
    // (e.g. loggerStart) set CharacteristicWriteError, subsequent writes
    // return false even when BLE would accept them. QtPokit exposes no
    // way to clear this state except by creating a new service object,
    // which requires destroying the whole PokitDevice. The pragmatic fix
    // is to reconnect transparently on fetch.
    auto *svc = m_logger->service();
    const bool hasStickyError = svc
        && svc->error() == QLowEnergyService::ServiceError::CharacteristicWriteError;

    if (hasStickyError) {
        qCInfo(lcDev) << "logger service has sticky CharacteristicWriteError; "
                         "reconnecting to clear state then retrying fetch";
        m_pendingFetchAfterReconnect = true;
        // Drop BLE link; onControllerDisconnected will set state=idle,
        // after which we need to explicitly trigger a new scan.
        // onControllerDisconnected will set state=idle. We hook a one-shot
        // scan trigger inside that handler via m_pendingFetchAfterReconnect.
        m_pokit->controller()->disconnectFromDevice();
        return;
    }

    m_logger->enableMetadataNotifications();
    m_logger->enableReadingNotifications();
    QTimer::singleShot(200, this, [this]() {
        if (!m_logger) return;
        const bool ok = m_logger->fetchSamples();
        qCInfo(lcDev) << "logger fetchSamples returned" << ok;
        if (!ok && !m_loggerFetchOpId.isEmpty()) {
            replyAck(m_loggerFetchOpId, m_loggerFetchSender, false,
                     QStringLiteral("write_failed"),
                     QStringLiteral("fetchSamples returned false"));
            m_loggerFetchOpId.clear(); m_loggerFetchSender.clear();
        }
    });
    // ack fires after metadataRead (once device responds).
}

void Device::onLoggerSettingsWritten()
{
    if (!m_loggerOpId.isEmpty()) {
        replyAck(m_loggerOpId, m_loggerSender, true);
        m_loggerOpId.clear(); m_loggerSender.clear();
    }
    QJsonObject ev = makeEvent("loggerState");
    ev.insert(QStringLiteral("running"), m_loggerRunning);
    m_server->broadcast(ev);
    // If the logger just stopped, hand the ADC back to the multimeter.
    if (!m_loggerRunning) resumeMultimeterFromLogger();
}

void Device::onLoggerMetadataRead(const DataLoggerService::Metadata &meta)
{
    m_lastLoggerMeta = meta;
    m_haveLoggerMeta = true;
    m_loggerRunning = (meta.status == DataLoggerService::LoggerStatus::Sampling);

    // Ack the fetch op now that we have the metadata.
    if (!m_loggerFetchOpId.isEmpty()) {
        replyAck(m_loggerFetchOpId, m_loggerFetchSender, true);
        m_loggerFetchOpId.clear(); m_loggerFetchSender.clear();
    }

    QJsonObject ev = makeEvent("loggerMetadata");
    ev.insert(QStringLiteral("status"),
              meta.status == DataLoggerService::LoggerStatus::Sampling ? "Sampling"
              : meta.status == DataLoggerService::LoggerStatus::Done   ? "Done"
              : meta.status == DataLoggerService::LoggerStatus::BufferFull ? "BufferFull"
              : "Error");
    ev.insert(QStringLiteral("mode"), loggerModeToString(meta.mode));
    ev.insert(QStringLiteral("unit"), loggerUnitForMode(meta.mode));
    ev.insert(QStringLiteral("range"), static_cast<int>(meta.range));
    ev.insert(QStringLiteral("scale"), meta.scale);
    ev.insert(QStringLiteral("intervalMs"), static_cast<qint64>(meta.updateInterval));
    ev.insert(QStringLiteral("numberOfSamples"), static_cast<int>(meta.numberOfSamples));
    ev.insert(QStringLiteral("startTimestamp"), static_cast<qint64>(meta.timestamp));
    m_server->broadcast(ev);
}

// ──────────────────────────────────────────────────────────────────────────
// DSO (oscilloscope)

static DsoService::Mode dsoModeFromString(const QString &s, bool *ok)
{
    *ok = true;
    if (s == QLatin1String("DcVoltage")) return DsoService::Mode::DcVoltage;
    if (s == QLatin1String("AcVoltage")) return DsoService::Mode::AcVoltage;
    if (s == QLatin1String("DcCurrent")) return DsoService::Mode::DcCurrent;
    if (s == QLatin1String("AcCurrent")) return DsoService::Mode::AcCurrent;
    *ok = false;
    return DsoService::Mode::Idle;
}

static QString dsoModeToString(DsoService::Mode m)
{
    switch (m) {
    case DsoService::Mode::DcVoltage: return QStringLiteral("DcVoltage");
    case DsoService::Mode::AcVoltage: return QStringLiteral("AcVoltage");
    case DsoService::Mode::DcCurrent: return QStringLiteral("DcCurrent");
    case DsoService::Mode::AcCurrent: return QStringLiteral("AcCurrent");
    case DsoService::Mode::Idle:      return QStringLiteral("Idle");
    }
    return QStringLiteral("Idle");
}

static QString dsoUnitForMode(DsoService::Mode m)
{
    switch (m) {
    case DsoService::Mode::DcVoltage:
    case DsoService::Mode::AcVoltage: return QStringLiteral("V");
    case DsoService::Mode::DcCurrent:
    case DsoService::Mode::AcCurrent: return QStringLiteral("A");
    case DsoService::Mode::Idle:      return QString();
    }
    return QString();
}

void Device::onDsoServiceReady()
{
    qCInfo(lcDev) << "dso service ready";
    m_dsoReady = true;
}

void Device::cmdDsoCapture(const QString &mode, double sampleRateHz,
                           int samples, const QString &opId, Session *sender)
{
    if (!ensureReady(opId, sender) || !m_dso || !m_dsoReady) {
        replyAck(opId, sender, false, QStringLiteral("not_ready"),
                 QStringLiteral("DSO service not yet discovered"));
        return;
    }
    bool ok = false;
    DsoService::Mode m = dsoModeFromString(mode, &ok);
    if (!ok) {
        replyAck(opId, sender, false, QStringLiteral("bad_mode"),
                 QStringLiteral("DSO mode must be DcVoltage/AcVoltage/"
                                "DcCurrent/AcCurrent: ") + mode);
        return;
    }
    if (sampleRateHz < 1 || sampleRateHz > 1'000'000) {
        replyAck(opId, sender, false, QStringLiteral("bad_rate"),
                 QStringLiteral("sample rate must be 1 Hz – 1 MHz"));
        return;
    }
    if (samples < 1 || samples > 16384) {
        replyAck(opId, sender, false, QStringLiteral("bad_samples"),
                 QStringLiteral("numberOfSamples must be 1 – 16384"));
        return;
    }

    // Same ADC contention as logger.
    suspendMultimeterForLogger();

    DsoService::Settings s;
    s.command = DsoService::Command::FreeRunning;
    s.triggerLevel = 0.0f;
    s.mode = m;
    // Pokit Pro DSO does NOT accept AutoRange. Pick a sensible default
    // matching the suspended multimeter's range conventions.
    switch (m) {
    case DsoService::Mode::DcVoltage:
    case DsoService::Mode::AcVoltage: s.range = 2; break;  // 10 V
    case DsoService::Mode::DcCurrent:
    case DsoService::Mode::AcCurrent: s.range = 5; break;  // 3 A
    default:                          s.range = 0; break;
    }
    // samplingWindow is in microseconds; window = samples / rate
    s.samplingWindow = static_cast<quint32>(
        std::llround(static_cast<double>(samples) * 1'000'000.0 / sampleRateHz));
    s.numberOfSamples = static_cast<quint16>(samples);

    m_dsoBuffer.clear();
    m_dsoBuffer.reserve(samples);
    m_dsoExpectedSamples = samples;
    m_haveDsoMeta = false;
    m_dsoOpId = opId;
    m_dsoSender = sender;

    m_dso->enableMetadataNotifications();
    m_dso->enableReadingNotifications();
    QTimer::singleShot(200, this, [this, s]() {
        if (!m_dso) return;
        const bool ok = m_dso->startDso(s);
        qCInfo(lcDev) << "DSO startDso returned" << ok
                      << "samples=" << s.numberOfSamples
                      << "window_us=" << s.samplingWindow;
        if (!ok && !m_dsoOpId.isEmpty()) {
            replyAck(m_dsoOpId, m_dsoSender, false,
                     QStringLiteral("write_failed"),
                     QStringLiteral("DSO startDso returned false"));
            m_dsoOpId.clear(); m_dsoSender.clear();
        }
    });
}

void Device::onDsoSettingsWritten()
{
    // Settings ack only; metadata + samples streaming follows.
}

void Device::onDsoMetadataRead(const DsoService::Metadata &meta)
{
    m_lastDsoMeta = meta;
    m_haveDsoMeta = true;
    m_dsoExpectedSamples = meta.numberOfSamples;
    m_dsoBuffer.clear();
    m_dsoBuffer.reserve(meta.numberOfSamples);
    qCInfo(lcDev) << "DSO metadata: samples=" << meta.numberOfSamples
                  << "rate=" << meta.samplingRate << "Hz scale=" << meta.scale;
}

void Device::onDsoSamplesRead(const DsoService::Samples &samples)
{
    for (qint16 v : samples) m_dsoBuffer.append(v);
    qCInfo(lcDev) << "DSO samples batch size=" << samples.size()
                  << "total=" << m_dsoBuffer.size()
                  << "expected=" << m_dsoExpectedSamples;

    // Emit progressive event (lets UI show progress for big captures).
    QJsonObject ev = makeEvent("dsoProgress");
    ev.insert(QStringLiteral("collected"), m_dsoBuffer.size());
    ev.insert(QStringLiteral("total"), m_dsoExpectedSamples);
    m_server->broadcast(ev);

    if (m_haveDsoMeta && m_dsoBuffer.size() >= m_dsoExpectedSamples) {
        // Trace complete — emit dsoTrace and ack.
        QJsonArray vals;
        const float scale = m_lastDsoMeta.scale;
        for (qint16 raw : m_dsoBuffer) vals.append(raw * scale);

        QJsonObject trace = makeEvent("dsoTrace");
        trace.insert(QStringLiteral("count"), vals.size());
        trace.insert(QStringLiteral("values"), vals);
        trace.insert(QStringLiteral("mode"), dsoModeToString(m_lastDsoMeta.mode));
        trace.insert(QStringLiteral("unit"), dsoUnitForMode(m_lastDsoMeta.mode));
        trace.insert(QStringLiteral("range"),
                     static_cast<int>(m_lastDsoMeta.range));
        trace.insert(QStringLiteral("samplingRate"),
                     static_cast<qint64>(m_lastDsoMeta.samplingRate));
        trace.insert(QStringLiteral("samplingWindowUs"),
                     static_cast<qint64>(m_lastDsoMeta.samplingWindow));
        m_server->broadcast(trace);

        if (!m_dsoOpId.isEmpty()) {
            replyAck(m_dsoOpId, m_dsoSender, true);
            m_dsoOpId.clear(); m_dsoSender.clear();
        }

        // Capture is one-shot — release ADC for live readings.
        m_dsoBuffer.clear();
        m_dsoExpectedSamples = 0;
        QTimer::singleShot(500, this, [this]() {
            if (!m_loggerRunning) resumeMultimeterFromLogger();
        });
    }
}

void Device::onLoggerSamplesRead(const DataLoggerService::Samples &samples)
{
    QJsonArray vals;
    const float scale = m_haveLoggerMeta ? m_lastLoggerMeta.scale : 1.0f;
    for (const qint16 raw : samples) vals.append(raw * scale);

    QJsonObject ev = makeEvent("loggerBatch");
    ev.insert(QStringLiteral("count"), vals.size());
    ev.insert(QStringLiteral("values"), vals);
    if (m_haveLoggerMeta) {
        ev.insert(QStringLiteral("mode"),
                  loggerModeToString(m_lastLoggerMeta.mode));
        ev.insert(QStringLiteral("unit"),
                  loggerUnitForMode(m_lastLoggerMeta.mode));
        ev.insert(QStringLiteral("intervalMs"),
                  static_cast<qint64>(m_lastLoggerMeta.updateInterval));
    }
    m_server->broadcast(ev);

    // No explicit "end of samples" signal — debounce 1.5s of silence as
    // "fetch done" and hand the ADC back to the multimeter.
    static QTimer *fetchDoneTimer = nullptr;
    if (!fetchDoneTimer) {
        fetchDoneTimer = new QTimer(this);
        fetchDoneTimer->setSingleShot(true);
        connect(fetchDoneTimer, &QTimer::timeout, this, [this]() {
            if (!m_loggerRunning) resumeMultimeterFromLogger();
        });
    }
    fetchDoneTimer->start(1500);
}

// ──────────────────────────────────────────────────────────────────────────
// Status cache

void Device::onDeviceCharacteristicsRead(
    const StatusService::DeviceCharacteristics &chars)
{
    m_lastChars = chars;
    emitStatus();
}

void Device::onDeviceStatusRead(const StatusService::Status &s)
{
    m_lastStatus = s;
    m_haveStatus = true;
    emitStatus();
}

void Device::onDeviceNameRead(const QString &name)
{
    m_deviceName = name;
    emitStatus();
}

void Device::emitStatus()
{
    QJsonObject ev = makeEvent("status");
    ev.insert(QStringLiteral("batteryVoltage"), m_lastStatus.batteryVoltage);
    ev.insert(QStringLiteral("deviceStatus"),
              StatusService::toString(m_lastStatus.deviceStatus));
    ev.insert(QStringLiteral("firmware"), m_lastChars.firmwareVersion.toString());
    ev.insert(QStringLiteral("name"), m_deviceName);
    m_server->broadcast(ev);
}

// ──────────────────────────────────────────────────────────────────────────
// Reply helper

void Device::replyAck(const QString &opId, QPointer<Session> sender, bool ok,
                      const QString &code, const QString &message)
{
    if (opId.isEmpty() || !sender) return;
    QJsonObject ev = makeEvent(ok ? "ack" : "error");
    ev.insert(QStringLiteral("opId"), opId);
    if (ok) {
        ev.insert(QStringLiteral("ok"), true);
    } else {
        ev.insert(QStringLiteral("code"), code);
        ev.insert(QStringLiteral("message"), message);
    }
    sender->sendEvent(ev);
}

// ──────────────────────────────────────────────────────────────────────────
// Enum conversions

MultimeterService::Mode Device::parseMode(const QString &s, bool *ok)
{
    *ok = true;
    if (s == QLatin1String("DcVoltage"))   return MultimeterService::Mode::DcVoltage;
    if (s == QLatin1String("AcVoltage"))   return MultimeterService::Mode::AcVoltage;
    if (s == QLatin1String("DcCurrent"))   return MultimeterService::Mode::DcCurrent;
    if (s == QLatin1String("AcCurrent"))   return MultimeterService::Mode::AcCurrent;
    if (s == QLatin1String("Resistance"))  return MultimeterService::Mode::Resistance;
    if (s == QLatin1String("Diode"))       return MultimeterService::Mode::Diode;
    if (s == QLatin1String("Continuity"))  return MultimeterService::Mode::Continuity;
    if (s == QLatin1String("Temperature")) return MultimeterService::Mode::Temperature;
    if (s == QLatin1String("Capacitance")) return MultimeterService::Mode::Capacitance;
    if (s == QLatin1String("ExternalTemperature"))
        return MultimeterService::Mode::ExternalTemperature;
    *ok = false;
    return MultimeterService::Mode::Idle;
}

QString Device::modeToString(MultimeterService::Mode m)
{
    switch (m) {
    case MultimeterService::Mode::DcVoltage:           return QStringLiteral("DcVoltage");
    case MultimeterService::Mode::AcVoltage:           return QStringLiteral("AcVoltage");
    case MultimeterService::Mode::DcCurrent:           return QStringLiteral("DcCurrent");
    case MultimeterService::Mode::AcCurrent:           return QStringLiteral("AcCurrent");
    case MultimeterService::Mode::Resistance:          return QStringLiteral("Resistance");
    case MultimeterService::Mode::Diode:               return QStringLiteral("Diode");
    case MultimeterService::Mode::Continuity:          return QStringLiteral("Continuity");
    case MultimeterService::Mode::Temperature:         return QStringLiteral("Temperature");
    case MultimeterService::Mode::Capacitance:         return QStringLiteral("Capacitance");
    case MultimeterService::Mode::ExternalTemperature: return QStringLiteral("ExternalTemperature");
    case MultimeterService::Mode::Idle:                return QStringLiteral("Idle");
    }
    return QStringLiteral("Idle");
}

QString Device::unitForMode(MultimeterService::Mode m)
{
    switch (m) {
    case MultimeterService::Mode::DcVoltage:
    case MultimeterService::Mode::AcVoltage:           return QStringLiteral("V");
    case MultimeterService::Mode::DcCurrent:
    case MultimeterService::Mode::AcCurrent:           return QStringLiteral("A");
    case MultimeterService::Mode::Resistance:          return QStringLiteral("Ω");
    case MultimeterService::Mode::Diode:               return QStringLiteral("V");
    case MultimeterService::Mode::Continuity:          return QString();
    case MultimeterService::Mode::Temperature:
    case MultimeterService::Mode::ExternalTemperature: return QStringLiteral("°C");
    case MultimeterService::Mode::Capacitance:         return QStringLiteral("F");
    case MultimeterService::Mode::Idle:                return QString();
    }
    return QString();
}

QString Device::readingStatusToString(MultimeterService::MeterStatus st,
                                      MultimeterService::Mode m)
{
    // Status semantics depend on mode (per QtPokit docs).
    switch (m) {
    case MultimeterService::Mode::DcVoltage:
    case MultimeterService::Mode::AcVoltage:
    case MultimeterService::Mode::DcCurrent:
    case MultimeterService::Mode::AcCurrent:
    case MultimeterService::Mode::Resistance:
        return st == MultimeterService::MeterStatus::AutoRangeOn
            ? QStringLiteral("AutoRangeOn")
            : st == MultimeterService::MeterStatus::AutoRangeOff
              ? QStringLiteral("AutoRangeOff")
              : QStringLiteral("Error");
    case MultimeterService::Mode::Continuity:
        return st == MultimeterService::MeterStatus::Continuity
            ? QStringLiteral("Continuity")
            : QStringLiteral("NoContinuity");
    case MultimeterService::Mode::Diode:
    case MultimeterService::Mode::Temperature:
    case MultimeterService::Mode::ExternalTemperature:
    case MultimeterService::Mode::Capacitance:
        return st == MultimeterService::MeterStatus::Ok
            ? QStringLiteral("Ok") : QStringLiteral("Error");
    case MultimeterService::Mode::Idle:
        return QStringLiteral("Idle");
    }
    return QString();
}

quint8 Device::parseRangeForMode(const QString &s,
                                 MultimeterService::Mode /*m*/)
{
    // v1 only supports "auto" (255). Explicit ranges can be added later.
    if (s.compare(QLatin1String("auto"), Qt::CaseInsensitive) == 0
        || s.isEmpty()) {
        return 255;
    }
    // Unknown literal: fall back to auto rather than erroring.
    return 255;
}

QString Device::rangeToString(quint8 r, MultimeterService::Mode /*m*/)
{
    if (r == 255) return QStringLiteral("auto");
    // Detail per-mode strings can come later; for v1 just return the
    // numeric index so clients can display something useful.
    return QString::number(r);
}
