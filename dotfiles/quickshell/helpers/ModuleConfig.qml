pragma Singleton
import QtQuick

QtObject {
    readonly property var values: ({
        network: {
            intervalMs: 3000,
            trafficIntervalMs: 2000,
            fastWhenExpanded: true
        },
        ping: {
            defaultActive: false,
            interval: 2
        },
        "ping-gw": {
            defaultActive: false,
            interval: 2
        },
        cpu: {
            intervalMs: 2000,
            freqIntervalMs: 5000
        },
        "privacy-indicators": {
            intervalMs: 5000
        },
        media: {
            activeIntervalMs: 2000,
            idleIntervalMs: 10000
        }
    })

    function defaults(moduleId) {
        return values[moduleId] || {};
    }

    function has(moduleId) {
        return values[moduleId] !== undefined;
    }

    function normalize(defaultValue, value) {
        if (value === undefined || value === null)
            return defaultValue;

        if (typeof defaultValue === "number") {
            var n = Number(value);
            return isNaN(n) ? defaultValue : n;
        }

        if (typeof defaultValue === "boolean") {
            if (typeof value === "string")
                return value.toLowerCase() === "true";
            return value === true;
        }

        if (typeof defaultValue !== typeof value)
            return defaultValue;

        return value;
    }

    function resolve(moduleId, overrides) {
        var base = defaults(moduleId);
        var user = overrides || {};
        var result = {};

        for (var key in base)
            result[key] = normalize(base[key], user[key]);

        for (var extra in user) {
            if (result[extra] === undefined)
                result[extra] = user[extra];
        }

        return result;
    }
}
