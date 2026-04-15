#pragma once

#include <QJsonObject>

// Constructs a base event JSON object with {type, ts} prefilled.
// ts is unix-millis.
QJsonObject makeEvent(const char *type);
