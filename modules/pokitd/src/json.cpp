#include "json.h"

#include <QDateTime>

QJsonObject makeEvent(const char *type)
{
    QJsonObject ev;
    ev.insert(QStringLiteral("type"), QString::fromLatin1(type));
    ev.insert(QStringLiteral("ts"), QDateTime::currentMSecsSinceEpoch());
    return ev;
}
