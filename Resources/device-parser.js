ObjC.import('Foundation');

function read(path) {
    const data = $.NSData.dataWithContentsOfFile(path);
    return data ? ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)) : '';
}
function json(path) { try { return JSON.parse(read(path)); } catch (_) { return null; } }
function usbFile(path) {
    const value = json(path);
    if (value) return value;
    try {
        const data = $.NSData.dataWithContentsOfFile(path);
        if (!data) return null;
        return ObjC.deepUnwrap($.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data, 0, null, null));
    } catch (_) { return null; }
}
function field(o, names) {
    for (const name of names) {
        let value = o[name];
        if (value && typeof value === 'object') value = value.Value !== undefined ? value.Value : value.value;
        if (typeof value === 'number' && !Number.isSafeInteger(value)) return '';
        if (value !== undefined && value !== null) return String(value);
    }
    return '';
}
function ecidKey(value, usb) {
    let s = String(value).trim();
    if (!/^(?:0x)?[0-9a-f]+$/i.test(s)) return '';
    if (usb || /^0x/i.test(s) || /[a-f]/i.test(s)) return s.replace(/^0x/i, '').replace(/^0+/, '').toUpperCase() || '0';
    // Decimal ECIDs can exceed Number's exact integer range. Convert as strings.
    let hex = '';
    while (s !== '0' && s !== '') {
        let quotient = '', remainder = 0;
        for (const digit of s) {
            const value = remainder * 10 + Number(digit);
            quotient += Math.floor(value / 16);
            remainder = value % 16;
        }
        hex = '0123456789ABCDEF'[remainder] + hex;
        s = quotient.replace(/^0+/, '') || '0';
    }
    return hex || '0';
}
function mode(value) {
    if (!value || /^unknown$/i.test(value)) return 'Unknown';
    if (/\bDFU\b/i.test(value)) return 'DFU';
    if (/recovery/i.test(value)) return 'Recovery';
    return value ? 'Other' : 'Unknown';
}
function macRecords(root) {
    const found = {};
    function walk(v, inheritedECID) {
        if (!v || typeof v !== 'object') return;
        if (!Array.isArray(v)) {
            const type = field(v, ['deviceType', 'DeviceType', 'device_type', 'ProductType', 'productType', 'type']);
            const ecid = field(v, ['ECID', 'ecid', 'EcID']) || inheritedECID || '';
            if (/^(Mac|MacBookPro|MacBookAir|Macmini|iMac|iMacPro|MacPro)[0-9]+,[0-9]+$/.test(type) && ecidKey(ecid)) {
                const key = ecidKey(ecid);
                const state = mode(field(v, ['mode', 'Mode', 'bootedState', 'BootedState', 'state', 'State']));
                if (found[key] && found[key].type !== type) {
                    // Conflicting identity for one ECID is not a safe target either.
                    found[key + ':' + type] = {type: type, ecid: ecid, mode: state};
                } else {
                    found[key] = {type: type, ecid: ecid, mode: state};
                }
            }
        }
        for (const key in v) {
            walk(v[key], /^(?:0x[0-9a-f]+|[0-9]+)$/i.test(key) ? key : inheritedECID);
        }
    }
    walk(root, '');
    return Object.keys(found).map(function (key) { return found[key]; });
}
function textRecords(source) {
    const records = [];
    // Never pair the model on one line with the ECID of a different record.
    for (const line of source.split(/\r?\n/)) {
        const type = line.match(/\b(?:Mac|MacBookPro|MacBookAir|Macmini|iMac|iMacPro|MacPro)[0-9]+,[0-9]+\b/);
        const ecid = line.match(/ECID:\s*((?:0x)?[0-9a-f]+)/i);
        if (type && ecid) records.push({type: type[0], ecid: ecid[1], mode: /\bDFU\b/i.test(line) ? 'DFU' : 'Unknown'});
    }
    return macRecords(records);
}
function usbMacs(root) {
    const result = [];
    function walk(v) {
        if (!v || typeof v !== 'object') return;
        const name = field(v, ['USB Product Name', 'IORegistryEntryName']);
        const vendor = Number(v.idVendor);
        const product = Number(v.idProduct);
        const serial = field(v, ['USB Serial Number', 'USBSerialNumber']);
        const macName = /^Mac DFU Mode$/i.test(name);
        const t2 = /DFU/i.test(name) && /\bCPID:\s*8012\b/i.test(serial);
        if (vendor === 0x05ac && (product === 0x1227 || (macName && product === 0x1222)) && (macName || t2)) {
            const ecid = serial.match(/\bECID:\s*(?:0x)?([0-9a-f]+)/i);
            result.push({ecid: ecid ? ecidKey(ecid[1], true) : ''});
        }
        for (const key in v) walk(v[key]);
    }
    walk(root);
    return result;
}
function resolve(records, usb) {
    if (records.length > 1 || usb.length > 1) return {detected: false, ambiguous: true, via: 'none'};
    const device = records[0];
    if (!device) return {detected: false, ambiguous: false, identified: false, via: 'none'};
    if (device.mode === 'Recovery' || device.mode === 'Other') return {detected: false, ambiguous: false, identified: true, via: 'none'};
    if (usb.length === 1 && usb[0].ecid && usb[0].ecid !== ecidKey(device.ecid)) {
        return {detected: false, ambiguous: true, via: 'none'};
    }
    if (device.mode === 'DFU' || (usb.length === 1 && usb[0].ecid && usb[0].ecid === ecidKey(device.ecid))) {
        return {detected: true, ambiguous: false, identified: true, via: 'cfgutil', type: device.type, ecid: '0x' + ecidKey(device.ecid), mode: 'DFU'};
    }
    return {detected: false, ambiguous: false, identified: true, via: 'none'};
}
function run(args) {
    const usb = usbMacs(usbFile(args[2]));
    if (args[0] === 'presence') {
        return JSON.stringify({detected: usb.length === 1, ambiguous: usb.length > 1, via: usb.length === 1 ? 'usb' : 'none'});
    }
    let records = macRecords(json(args[1]));
    if (!records.length && args[3]) records = textRecords(read(args[3]));
    return JSON.stringify(resolve(records, usb));
}
