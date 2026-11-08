# HearthFrame — Source Providers

HearthFrame has one source abstraction with three implementations. This
document specifies their path semantics, metadata, caching and failure
behavior.

## 1. Contract

```dart
abstract class PhotoSource {
  Future<List<MediaItem>> list();
  Future<void> discover(void Function(List<MediaItem> batch) onBatch);
}

abstract class NetworkSource implements PhotoSource {
  Future<MediaItem> prepare(MediaItem item); // download into the cache
  Future<void> close();
}
```

`MediaItem` carries `path`, `isVideo`, and optional remote `size` and
`mtime`. `path` is always what the provider uses for listing. For network
sources, `prepare` returns a new `MediaItem` pointing at the local cached
file.

## 2. Shared media rules

### Extensions

| Type | Extensions |
| --- | --- |
| Image | `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.heic`, `.heif`, `.bmp` |
| Video | `.mp4`, `.mov`, `.m4v`, `.mkv`, `.avi` |

Extensions are matched case-insensitively. Unknown files are ignored.

### Skipped entries

Any entry whose name starts with `.`, or that is named `@eaDir`, `#recycle`,
`#snapshot` or `@tmp`, is skipped. These are NAS thumbnail, recycle and
snapshot directories and never contain user media.

### Ordering

`list()` sorts by path. `discover()` emits in directory-walk order; the
slideshow shuffles when configured.

## 3. Local folder

- **Field:** `source_folder`.
- **Path:** absolute path on the device, e.g.
  `/storage/emulated/0/Pictures`.
- **Permission:** Android requires all-files access
  (`MANAGE_EXTERNAL_STORAGE`), requested on Start.
- **Traversal:** recursive depth-first; symbolic links are not followed.
- **Metadata:** none; the cache is not used.
- **Missing folder:** returns an empty list, which surfaces the "no photos"
  state.
- **Notes:** on iOS the app sandbox limits reachable paths; iOS is not a
  validated platform.

## 4. WebDAV

- **Fields:** `webdav_url`, `webdav_user`, `webdav_pass`, `webdav_path`.
- **URL:** base URL including scheme and port, e.g.
  `https://nas.local:5006` or `http://nas.local:5005`.
- **Path:** absolute collection path on the server, e.g. `/photo/family`.
- **Client:** `webdav_client`, HTTP Basic authentication.
- **Discovery:** `PROPFIND` per directory; `isDir` distinguishes folders.
  Remote `size` and `mTime` (milliseconds since epoch) are stored in the
  index and used in cache keys.
- **Download:** `read2File` into a `.part` file, then rename.
- **Transport:** HTTPS is recommended. Plain HTTP works on trusted LANs.

## 5. SMB / CIFS

- **Fields:** `smb_host`, `smb_domain`, `smb_user`, `smb_pass`, `smb_path`.
- **Host:** hostname or IP, optionally `host:port`. The vendored client is
  patched to honor a non-standard port (see ADR-008).
- **Share path:** **must include the share name**, e.g. `/photo/family`
  for the `photo` share. A bare `/` is not enough.
- **Domain:** optional; leave empty for local NAS accounts.
- **Client:** vendored `smb_connect` (Apache-2.0), SMB 1/2.0/2.1.
- **Connection:** one connection is reused per `SmbSource` instance and
  closed when the slideshow is disposed.
- **Metadata:** `size` and `lastModified` are stored in the index and used in
  cache keys. Values are treated as opaque integers.
- **Download:** `openRead` streamed into a `.part` file, then renamed.

## 6. Cache and prefetch

Both network sources share the cache implementation:

- Directory: `<temporaryDirectory>/hearthframe_cache`.
- File name:
  `<path hash>_<size or 0>_<mtime or 0>_<sanitized base name>`.
- SMB hashes a prefixed `smb_<path>` key.
- A non-empty existing file is reused.
- Downloads are written to `<name>.part` and renamed only on success.
- Old generations with the same hash prefix are deleted after success.
- The next queue item is prefetched after the current item is ready.
- A failed prepare is skipped by the slideshow; a decode failure deletes the
  cached file.

## 7. Configuration examples

WebDAV:

| Field | Example |
| --- | --- |
| Server URL | `https://nas.local:5006` |
| Username | `frame` |
| Password | *(your password)* |
| Folder path | `/photo/family` |

SMB:

| Field | Example |
| --- | --- |
| Host | `nas.local` or `nas.local:4455` |
| Username | `frame` |
| Password | *(your password)* |
| Domain | *(empty)* |
| Share path | `/photo/family` |

Local:

| Field | Example |
| --- | --- |
| Folder path | `/storage/emulated/0/Pictures` |

Never commit real hostnames or credentials. Use placeholders in issues and
pull requests.

## 8. Troubleshooting

| Symptom | Likely cause | Check |
| --- | --- | --- |
| WebDAV 401/403 | Wrong credentials or path not shared for the account | Test the same URL/path with another WebDAV client. |
| WebDAV "Could not load" | URL missing scheme/port, TLS problem | Use `https://host:port` and verify the certificate chain. |
| SMB hangs or refuses | Port blocked, share name missing | Confirm the share exists and the path starts with `/share`. |
| SMB auth failure | Domain or username format | Try leaving the domain empty; use the NAS account name. |
| Empty album | Only skipped dirs or unsupported extensions | Put a JPEG/MP4 directly in the chosen folder. |
| Some videos won't play | Codec/container unsupported by the device | Convert to H.264/AAC MP4. |
| Broken image icon flashes | Cached file was truncated before the atomic-write fix | Refresh the frame; the item is skipped and the cache is dropped. |
