#pragma once

#include <QBluetoothDeviceInfo>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>

#include <qtpokit/dataloggerservice.h>
#include <qtpokit/dsoservice.h>
#include <qtpokit/multimeterservice.h>
#include <qtpokit/statusservice.h>

QT_BEGIN_NAMESPACE
class QLowEnergyController;
QT_END_NAMESPACE

class PokitDevice;
class PokitDiscoveryAgent;

class Server;
class Session;

class Device : public QObject {
    Q_OBJECT
public:
    explicit Device(Server *server, QObject *parent = nullptr);
    ~Device() override;

    QString state() const { return m_state; }
    QJsonObject toJson() const;

    // ─── Command handlers ──────────────────────────────────────────────

    void cmdScan(const QString &opId, Session *sender);
    void cmdConnect(const QString &mac, const QString &opId, Session *sender);
    void cmdDisconnect(const QString &opId, Session *sender);

    void cmdSubscribe(const QString &opId, Session *sender);
    void cmdUnsubscribe(const QString &opId, Session *sender);

    void cmdSetMode(const QString &mode, const QString &range,
                    const QString &opId, Session *sender);
    void cmdSetRange(const QString &range, const QString &opId, Session *sender);
    void cmdSetInterval(int intervalMs, const QString &opId, Session *sender);

    void cmdSetTorch(bool on, const QString &opId, Session *sender);
    void cmdFlashLed(const QString &opId, Session *sender);
    void cmdRename(const QString &name, const QString &opId, Session *sender);

    void cmdLoggerStart(const QString &mode, const QString &range,
                        int intervalMs, const QString &opId, Session *sender);
    void cmdLoggerStop(const QString &opId, Session *sender);
    void cmdLoggerFetch(const QString &opId, Session *sender);

    void cmdDsoCapture(const QString &mode, double sampleRateHz, int samples,
                       const QString &opId, Session *sender);

    void suspendMultimeterForLogger();
    void resumeMultimeterFromLogger();

    // Called when a session disconnects so subscriber accounting stays honest.
    void sessionGone(Session *s);

private slots:
    // Scan
    void onPokitDiscovered(const QBluetoothDeviceInfo &info);
    void onScanFinished();
    // Controller
    void onControllerConnected();
    void onControllerDisconnected();
    void onControllerError();
    // Multimeter service
    void onMultimeterServiceReady();
    void onMultimeterReading(const MultimeterService::Reading &reading);
    void onMultimeterSettingsWritten();
    // Status service
    void onStatusServiceReady();
    void onDeviceCharacteristicsRead(
        const StatusService::DeviceCharacteristics &chars);
    void onDeviceStatusRead(const StatusService::Status &s);
    void onDeviceNameRead(const QString &name);
    void onDeviceNameWritten();
    void onTorchWritten();
    void onLedFlashed();
    // Data logger
    void onLoggerServiceReady();
    void onLoggerSettingsWritten();
    void onLoggerMetadataRead(const DataLoggerService::Metadata &meta);
    void onLoggerSamplesRead(const DataLoggerService::Samples &samples);
    // DSO
    void onDsoServiceReady();
    void onDsoSettingsWritten();
    void onDsoMetadataRead(const DsoService::Metadata &meta);
    void onDsoSamplesRead(const DsoService::Samples &samples);

private:
    void setState(const QString &next);
    void startScanInternal();
    void beginConnectInternal(const QBluetoothDeviceInfo &info);
    void beginStatusDiscovery();
    void teardownAsync(const QString &reason);
    void ensureAgent();
    void finishScan();
    void transitionToReadyIfBothServicesUp();
    void applyCurrentSettings();
    bool ensureReady(const QString &opId, Session *sender);
    void emitReading(const MultimeterService::Reading &r);
    void emitStatus();
    static MultimeterService::Mode parseMode(const QString &s, bool *ok);
    static QString modeToString(MultimeterService::Mode m);
    static QString readingStatusToString(MultimeterService::MeterStatus st,
                                         MultimeterService::Mode m);
    static quint8 parseRangeForMode(const QString &s, MultimeterService::Mode m);
    static QString rangeToString(quint8 r, MultimeterService::Mode m);
    static QString unitForMode(MultimeterService::Mode m);

    QJsonObject infoToJson(const QBluetoothDeviceInfo &info) const;
    void replyAck(const QString &opId, QPointer<Session> sender, bool ok,
                  const QString &code = {}, const QString &message = {});

    Server *m_server;
    QString m_state {"idle"};

    PokitDiscoveryAgent *m_agent {nullptr};
    PokitDevice *m_pokit {nullptr};
    MultimeterService *m_multimeter {nullptr};  // owned by m_pokit
    StatusService *m_status {nullptr};          // owned by m_pokit
    DataLoggerService *m_logger {nullptr};      // owned by m_pokit
    DsoService *m_dso {nullptr};                // owned by m_pokit
    QBluetoothDeviceInfo m_currentInfo;

    // service-discovery tracking
    bool m_multimeterReady {false};
    bool m_statusReady {false};
    bool m_loggerReady {false};
    bool m_dsoReady {false};

    // DSO capture state
    DsoService::Metadata m_lastDsoMeta {};
    bool m_haveDsoMeta {false};
    QVector<qint16> m_dsoBuffer;          // accumulates raw samples until full
    int m_dsoExpectedSamples {0};

    // Logger state
    bool m_loggerRunning {false};
    DataLoggerService::Metadata m_lastLoggerMeta {};
    bool m_haveLoggerMeta {false};

    // Current applied settings
    MultimeterService::Mode m_currentMode {MultimeterService::Mode::DcVoltage};
    quint8 m_currentRange {255}; // AutoRange
    quint32 m_updateInterval {500};

    // Subscribers: set of Sessions that asked for meter readings.
    QSet<Session *> m_subscribers;

    // Cached state (served via hello / status events)
    bool m_haveReading {false};
    MultimeterService::Reading m_lastReading {};
    bool m_haveStatus {false};
    StatusService::Status m_lastStatus {};
    StatusService::DeviceCharacteristics m_lastChars {};
    QString m_deviceName;

    // Scan bookkeeping
    QJsonArray m_scanBatch;
    QString m_scanOpId;
    QPointer<Session> m_scanSender;

    // Pending op trackers (for ack correlation). One slot per op-kind
    // since each op uses a distinct QtPokit completion signal.
    QString m_connectOpId;        QPointer<Session> m_connectSender;
    QString m_settingsOpId;       QPointer<Session> m_settingsSender;
    QString m_torchOpId;          QPointer<Session> m_torchSender;
    QString m_renameOpId;         QPointer<Session> m_renameSender;
    QString m_flashOpId;          QPointer<Session> m_flashSender;
    QString m_loggerOpId;         QPointer<Session> m_loggerSender;
    QString m_loggerFetchOpId;    QPointer<Session> m_loggerFetchSender;
    QString m_dsoOpId;            QPointer<Session> m_dsoSender;
    bool m_pendingFetchAfterReconnect {false};

    // Multimeter is suspended (set to Idle mode + notifications off) while
    // the logger holds the ADC. Restored on logger Stop ack or on next
    // user setMode call.
    bool m_multimeterSuspendedForLogger {false};
};
