# Custom IPSW JSON catalog

Target Mac DFU can read firmware metadata from an internal HTTPS endpoint or a local JSON file. This is useful when IPSW files are hosted on an internal server, NAS, or another controlled location.

Start with [`examples/custom-catalog.json`](../examples/custom-catalog.json). A machine-readable schema is available at [`custom-catalog.schema.json`](custom-catalog.schema.json).

## Recommended structure

```json
{
  "schemaVersion": 1,
  "devices": [
    {
      "name": "MacBook Pro 14-inch",
      "identifier": "Mac14,7",
      "firmwares": [
        {
          "version": "15.5",
          "build": "24F74",
          "date": "2026-05-20",
          "size": 16543210987,
          "url": "https://firmware.example.com/UniversalMac_15.5_24F74_Restore.ipsw",
          "filename": "UniversalMac_15.5_24F74_Restore.ipsw",
          "sha256": "REPLACE_WITH_64_HEXADECIMAL_CHARACTERS",
          "signed": true,
          "beta": false
        }
      ]
    }
  ]
}
```

Add one object to `devices` for each supported model. The app selects the object whose `identifier` exactly matches the detected Mac.

## Firmware fields

| Field | Required | Purpose |
| --- | --- | --- |
| `version` | yes | macOS version, such as `15.5` or `26.0 beta 2`. |
| `build` | yes | Apple build number, such as `24F74`. |
| `url` | yes | Direct HTTPS URL of the `.ipsw` file. |
| `signed` | yes | Only `true` entries are displayed. This is catalog metadata and does not bypass Apple verification. |
| `date` | no | Release date in `YYYY-MM-DD` format. |
| `size` | no | Exact file size in bytes. Use `0` to skip the size comparison. |
| `filename` | no | Saved filename. It is inferred from the URL when omitted. |
| `sha256` | recommended | A 64-character hexadecimal SHA-256 digest. |
| `sha1` | no | A 40-character SHA-1 digest for older catalogs. |
| `beta` | no | Set to `true` for beta/RC entries. Prerelease display must also be enabled in settings. |

When both hashes are present, SHA-256 is used. The app also reads `BuildManifest.plist` from the IPSW and checks the detected Model Identifier. Apple tools always make the final Restore eligibility decision.

## Calculate size and SHA-256

Run on a Mac:

```bash
stat -f%z "/path/to/file.ipsw"
shasum -a 256 "/path/to/file.ipsw"
```

Put the first result in `size` and the second in `sha256`. Replace the zero digest from the example file with the real value.

## Connect an HTTPS catalog

1. Host the JSON and IPSW files on a server with a valid HTTPS certificate.
2. Confirm that the catalog URL is directly accessible from the host Mac without an interactive login.
3. Open **Settings → IPSW Source** in Target Mac DFU.
4. Select **Custom HTTPS JSON**.
5. Enter the full URL, for example `https://firmware.example.com/catalog.json`.
6. Choose **Apply and Refresh Catalog**.
7. Put the target Mac in DFU. The library will display entries matching its exact identifier.

The remote response is cached and may be used when the server is temporarily unavailable.

## Connect a local catalog

1. Save the catalog with a `.json` extension.
2. Open **Settings → IPSW Source**.
3. Select **Local JSON Catalog**.
4. Choose **Choose JSON…** and select the file.
5. Choose **Apply and Refresh Catalog**.

The catalog itself may be local, but every firmware `url` must still be a direct HTTPS URL. To use an IPSW already stored on disk, select its catalog entry and use **Import IPSW**.

## Common problems

- **Empty list:** verify the exact `identifier` and `"signed": true`.
- **Beta entry is hidden:** enable beta/RC versions in settings.
- **Secure download error:** only `https://` URLs are accepted.
- **Size or hash mismatch:** recalculate values from the actual IPSW.
- **Wrong model:** verify the IPSW `BuildManifest.plist`; moving metadata to another device object does not make an IPSW compatible.
- **Internal endpoint is unavailable:** its certificate must be trusted by the host Mac and access must not depend on browser cookies or an interactive login.

Test a new catalog with a non-critical Mac before using it in a real Restore workflow.
