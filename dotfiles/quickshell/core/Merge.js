function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function clone(value) {
    if (Array.isArray(value))
        return value.map(clone);
    if (!isObject(value))
        return value;

    var result = {};
    for (var key in value)
        result[key] = clone(value[key]);
    return result;
}

function deepMerge(base, override) {
    if (override === undefined)
        return clone(base);
    if (base === undefined)
        return clone(override);

    if (Array.isArray(base) || Array.isArray(override))
        return clone(override);

    if (!isObject(base) || !isObject(override))
        return clone(override);

    var result = {};
    var key = "";

    for (key in base)
        result[key] = clone(base[key]);
    for (key in override) {
        if (key in result)
            result[key] = deepMerge(result[key], override[key]);
        else
            result[key] = clone(override[key]);
    }

    return result;
}
