ObjC.import('Foundation');

function run(args) {
    const data = $.NSData.dataWithContentsOfFile(args[0]);
    const source = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
    const parser = new Function(source + '\nreturn {macRecords, textRecords, usbMacs, resolve, ecidKey, usbFile};')();
    let tests = 0;
    function expect(value, name) { tests++; if (!value) throw new Error('Failed: ' + name); }
    const mac = {deviceType: 'Mac14,7', ECID: '0x1234'};
    const silicon = {'USB Product Name': 'Mac DFU Mode', idVendor: 1452, idProduct: 0x1227, 'USB Serial Number': 'CPID:8103 ECID:0000000000001234'};
    const usb = parser.usbMacs([silicon]);
    expect(usb.length === 1 && usb[0].ecid === '1234', 'Apple silicon USB identity');
    expect(parser.resolve(parser.macRecords({Output: {target: mac}}), usb).detected, 'Mac identity plus matching USB confirms DFU');
    expect(!parser.resolve(parser.macRecords(mac), []).detected, 'Mac identity alone does not imply DFU');
    expect(parser.resolve(parser.macRecords({deviceType: 'Mac14,7', ECID: '0x1234', mode: 'DFU'}), []).detected, 'explicit cfgutil DFU state');
    expect(!parser.resolve(parser.macRecords({deviceType: 'Mac14,7', ECID: '0x1234', bootedState: 'Recovery'}), usb).detected, 'Recovery is not DFU');
    expect(!parser.resolve(parser.macRecords({deviceType: 'Mac14,7', ECID: '0x1234', bootedState: 'Booted'}), usb).detected, 'booted Mac is not DFU');
    expect(parser.resolve(parser.macRecords([mac, {deviceType: 'Mac15,3', ECID: '0x5678'}]), usb).ambiguous, 'two Macs are blocked');
    expect(parser.resolve(parser.macRecords(mac), parser.usbMacs([silicon, silicon])).ambiguous, 'two USB Macs are blocked');
    expect(parser.resolve(parser.macRecords({deviceType: 'Mac14,7', ECID: '0x5678'}), usb).ambiguous, 'USB and cfgutil ECIDs must agree');
    expect(!parser.resolve(parser.macRecords(mac), [{ecid: ''}]).detected, 'unknown mode requires matching USB ECID');
    const phone = {'USB Product Name': 'Apple Mobile Device (DFU Mode)', idVendor: 1452, idProduct: 0x1227, 'USB Serial Number': 'CPID:8015 ECID:1234'};
    expect(parser.usbMacs([phone]).length === 0, 'iPhone DFU is not Mac DFU');
    expect(parser.usbMacs([{'USB Product Name': 'Mac DFU Mode', idVendor: 123, idProduct: 0x1227}]).length === 0, 'Apple vendor is required');
    const t2 = {'USB Product Name': 'Apple Mobile Device (DFU Mode)', idVendor: 1452, idProduct: 0x1227, 'USB Serial Number': 'CPID:8012 ECID:1234'};
    expect(parser.usbMacs([t2]).length === 1, 'T2 DFU identity');
    expect(parser.macRecords([{deviceType: 'iPhone15,2', ECID: '0x7777'}, mac]).length === 1, 'non-Mac cfgutil records are ignored');
    expect(parser.macRecords({Output: {'0x1234': {deviceType: 'Mac14,7'}}}).length === 1, 'ECID-keyed cfgutil JSON');
    expect(parser.textRecords('ECID: 0x1111 iPhone15,2\nECID: 0x1234 Mac14,7').length === 1, 'text records keep model and ECID together');
    expect(parser.textRecords('ECID: 0x1111 iPhone15,2\nMac14,7').length === 0, 'split unrelated text records cannot be paired');
    expect(parser.ecidKey('4660') === parser.ecidKey('0x1234'), 'decimal and hex ECIDs agree');
    expect(parser.ecidKey('18446744073709551615') === 'FFFFFFFFFFFFFFFF', '64-bit decimal ECID has no rounding');
    expect(parser.macRecords({deviceType: 'Mac14,7', ECID: 18446744073709551615}).length === 0, 'rounded numeric ECID is rejected');
    const path = ObjC.unwrap($.NSTemporaryDirectory()) + 'TargetMacDFU-USB-' + ObjC.unwrap($.NSUUID.UUID.UUIDString) + '.plist';
    const record = $.NSMutableDictionary.dictionaryWithDictionary(silicon);
    record.setObjectForKey($.NSData.data, 'USBData');
    const tree = $.NSArray.arrayWithObject(record);
    const plist = $.NSPropertyListSerialization.dataWithPropertyListFormatOptionsError(tree, $.NSPropertyListXMLFormat_v1_0, 0, null);
    try {
        expect(plist.writeToFileAtomically(path, true), 'USB fixture saved');
        expect(parser.usbMacs(parser.usbFile(path)).length === 1, 'ioreg plist with NSData is supported');
    } finally { $.NSFileManager.defaultManager.removeItemAtPathError(path, null); }
    return 'Device parser tests passed (' + tests + ')';
}
