//! Capability-protected, bounded CENC -> clear MP4 stream for API 23 AVPlayer.
//! The original C parser/decrypter is linked into the Rust core. No complete
//! decrypted movie is materialized on disk or in memory.
use crate::static_files::{parse_range, ByteRange};
use axum::{
    body::{Body, Bytes},
    http::{header, Method, StatusCode},
    response::{IntoResponse, Response},
};
use rand::RngCore;
use serde::Deserialize;
use serde_json::json;
use std::{
    collections::{HashMap, VecDeque},
    ffi::c_void,
    fs::File,
    io::{Read, Seek, SeekFrom},
    path::PathBuf,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};
use tokio_util::sync::CancellationToken;

const BLOCK: usize = 64 * 1024;
const MAX_SESSIONS: usize = 8;
#[repr(C)]
struct SpError {
    code: i32,
    message: [i8; 192],
}
#[repr(C)]
struct SpIo {
    user: *mut c_void,
    size: unsafe extern "C" fn(*mut c_void) -> i64,
    read_at: unsafe extern "C" fn(*mut c_void, u64, *mut u8, usize) -> isize,
    cancel: unsafe extern "C" fn(*mut c_void),
    close: unsafe extern "C" fn(*mut c_void),
}

#[cfg(test)]
mod tests {
    use super::*;
    const CENC: &[u8] = include_bytes!("../testdata/harmony/cenc.bin");
    const CLEAR: &[u8] = include_bytes!("../testdata/harmony/clear.bin");

    fn temp_root() -> PathBuf {
        let mut entropy = [0u8; 8];
        rand::rngs::OsRng.fill_bytes(&mut entropy);
        let path = std::env::temp_dir().join(format!("fq-cenc-{}", hex::encode(entropy)));
        std::fs::create_dir_all(&path).unwrap();
        path
    }
    fn local_context(path: &std::path::Path, cancel: CancellationToken) -> IoContext {
        IoContext {
            source: Source::Local(File::open(path).unwrap()),
            size: CENC.len() as u64,
            runtime: tokio::runtime::Handle::current(),
            cancel,
            cache: VecDeque::new(),
            stats: Arc::new(IoStats::default()),
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn cenc_sequential_and_600_random_seeks_match_independent_clear_bytes() {
        let root = temp_root();
        let path = root.join("sample.bin");
        std::fs::write(&path, CENC).unwrap();
        let context = local_context(&path, CancellationToken::new());
        let stats = context.stats.clone();
        tokio::task::spawn_blocking(move || {
            let key = hex::decode("00112233445566778899aabbccddeeff").unwrap();
            let mut stream = NativeStream::open(context, &key)
                .map_err(|_| "open CENC")
                .unwrap();
            let actual = stream.read(0, CENC.len()).unwrap();
            assert_eq!(actual, CLEAR);
            for i in 0..600usize {
                let at = (i * 997 + 31) % CLEAR.len();
                let size = (i * 43 % 512 + 1).min(CLEAR.len() - at);
                assert_eq!(stream.read(at as u64, size).unwrap(), &CLEAR[at..at + size]);
            }
        })
        .await
        .unwrap();
        assert!(stats.peak_cache.load(Ordering::Relaxed) <= 4 * BLOCK as u64);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn cancellation_stops_reads_without_replacing_source() {
        let root = temp_root();
        let path = root.join("sample.bin");
        std::fs::write(&path, CENC).unwrap();
        let cancel = CancellationToken::new();
        let context = local_context(&path, cancel.clone());
        tokio::task::spawn_blocking(move || {
            let key = hex::decode("00112233445566778899aabbccddeeff").unwrap();
            let mut stream = NativeStream::open(context, &key)
                .map_err(|_| "open CENC")
                .unwrap();
            cancel.cancel();
            assert!(stream.read(0, 32).is_err());
        })
        .await
        .unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), CENC);
        std::fs::remove_dir_all(root).unwrap();
    }

    async fn remote_fixture(ignore_range: bool) -> (String, tokio::task::JoinHandle<()>) {
        use axum::routing::get;
        let app = axum::Router::new().route(
            "/fixture",
            get(move |headers: axum::http::HeaderMap| async move {
                let range = if ignore_range {
                    ByteRange::Full
                } else {
                    parse_range(
                        headers.get(header::RANGE).and_then(|v| v.to_str().ok()),
                        CENC.len() as u64,
                    )
                };
                match range {
                    ByteRange::Partial { start, end } => Response::builder()
                        .status(206)
                        .header(
                            header::CONTENT_RANGE,
                            format!("bytes {start}-{end}/{}", CENC.len()),
                        )
                        .body(Body::from(CENC[start as usize..=end as usize].to_vec()))
                        .unwrap(),
                    _ => Response::builder()
                        .status(200)
                        .body(Body::from(CENC))
                        .unwrap(),
                }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}/fixture", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        (url, task)
    }
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    #[cfg_attr(target_env = "ohos", ignore = "HDC shell has no INTERNET permission; exercise HTTP Range inside the installed HAP")]
    async fn remote_range_decrypts_and_ignored_range_is_rejected() {
        let root = temp_root();
        let manager = MediaManager::new(root.clone()).unwrap();
        let (url, server) = remote_fixture(false).await;
        let id = manager
            .open(OpenSource {
                url,
                key_hex: "00112233445566778899aabbccddeeff".into(),
            })
            .await
            .unwrap();
        let session = manager.sessions.lock().unwrap().get(&id).unwrap().clone();
        tokio::task::spawn_blocking(move || {
            assert_eq!(
                session.stream.lock().unwrap().read(0, CLEAR.len()).unwrap(),
                CLEAR
            )
        })
        .await
        .unwrap();
        assert!(manager.stats()["maxCacheBytes"].as_u64().unwrap() <= 4 * BLOCK as u64);
        manager.cancel.cancel();
        server.abort();
        let manager = MediaManager::new(root.clone()).unwrap();
        let (url, server) = remote_fixture(true).await;
        assert!(manager
            .open(OpenSource {
                url,
                key_hex: "00112233445566778899aabbccddeeff".into()
            })
            .await
            .is_err());
        server.abort();
        std::fs::remove_dir_all(root).unwrap();
    }
}
unsafe extern "C" {
    fn sp_stream_open(io: *const SpIo, key: *const u8, error: *mut SpError) -> *mut c_void;
    fn sp_stream_read(
        stream: *mut c_void,
        buffer: *mut u8,
        length: usize,
        error: *mut SpError,
    ) -> isize;
    fn sp_stream_seek(stream: *mut c_void, position: i64, error: *mut SpError) -> i64;
    fn sp_stream_close(stream: *mut c_void);
}

#[derive(Default)]
struct IoStats {
    requests: AtomicU64,
    fetched: AtomicU64,
    peak_cache: AtomicU64,
}
enum Source {
    Remote {
        client: reqwest::Client,
        url: String,
    },
    Local(File),
}
struct IoContext {
    source: Source,
    size: u64,
    runtime: tokio::runtime::Handle,
    cancel: CancellationToken,
    cache: VecDeque<(u64, Vec<u8>)>,
    stats: Arc<IoStats>,
}
impl IoContext {
    fn block(&mut self, start: u64) -> Result<Vec<u8>, ()> {
        if self.cancel.is_cancelled() {
            return Err(());
        }
        let length = (self.size - start).min(BLOCK as u64) as usize;
        let bytes = match &mut self.source {
            Source::Local(file) => {
                file.seek(SeekFrom::Start(start)).map_err(|_| ())?;
                let mut bytes = vec![0; length];
                file.read_exact(&mut bytes).map_err(|_| ())?;
                bytes
            }
            Source::Remote { client, url } => {
                let end = start + length as u64 - 1;
                self.runtime.block_on(async {
                    let work = async {
                        let mut response = client
                            .get(url.as_str())
                            .header(header::RANGE, format!("bytes={start}-{end}"))
                            .header(header::ACCEPT_ENCODING, "identity")
                            .send()
                            .await
                            .map_err(|_| ())?;
                        if response.status() != StatusCode::PARTIAL_CONTENT {
                            return Err(());
                        }
                        let expected = format!("bytes {start}-{end}/{}", self.size);
                        if response
                            .headers()
                            .get(header::CONTENT_RANGE)
                            .and_then(|v| v.to_str().ok())
                            != Some(expected.as_str())
                        {
                            return Err(());
                        }
                        let mut data = Vec::with_capacity(length);
                        while let Some(chunk) = response.chunk().await.map_err(|_| ())? {
                            if data.len() + chunk.len() > length {
                                return Err(());
                            }
                            data.extend_from_slice(&chunk);
                        }
                        if data.len() != length {
                            return Err(());
                        }
                        Ok(data)
                    };
                    tokio::select! { _ = self.cancel.cancelled() => Err(()), value = work => value }
                })?
            }
        };
        self.stats.requests.fetch_add(1, Ordering::Relaxed);
        self.stats
            .fetched
            .fetch_add(bytes.len() as u64, Ordering::Relaxed);
        Ok(bytes)
    }
    fn read_at(&mut self, position: u64, out: &mut [u8]) -> Result<usize, ()> {
        if position >= self.size {
            return Ok(0);
        }
        let length = out.len().min((self.size - position) as usize);
        let mut copied = 0;
        while copied < length {
            if self.cancel.is_cancelled() {
                return Err(());
            }
            let position = position + copied as u64;
            let start = position / BLOCK as u64 * BLOCK as u64;
            if !self.cache.iter().any(|(at, _)| *at == start) {
                let data = self.block(start)?;
                if self.cache.len() == 4 {
                    self.cache.pop_front();
                }
                self.cache.push_back((start, data));
                let cache_bytes: usize = self.cache.iter().map(|(_, data)| data.len()).sum();
                self.stats
                    .peak_cache
                    .fetch_max(cache_bytes as u64, Ordering::Relaxed);
            }
            let (_, block) = self.cache.iter().find(|(at, _)| *at == start).ok_or(())?;
            let offset = (position - start) as usize;
            let count = (block.len() - offset).min(length - copied);
            if count == 0 {
                return Err(());
            }
            out[copied..copied + count].copy_from_slice(&block[offset..offset + count]);
            copied += count;
        }
        Ok(copied)
    }
}
unsafe extern "C" fn io_size(user: *mut c_void) -> i64 {
    unsafe { (*(user as *mut IoContext)).size as i64 }
}
unsafe extern "C" fn io_read(user: *mut c_void, at: u64, data: *mut u8, length: usize) -> isize {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        if data.is_null() || length > BLOCK {
            return -1;
        }
        let io = &mut *(user as *mut IoContext);
        io.read_at(at, std::slice::from_raw_parts_mut(data, length))
            .map(|n| n as isize)
            .unwrap_or(-1)
    }))
    .unwrap_or(-1)
}
// All seeks occur between serialized reads, so no request is in flight here.
// Session disposal/core shutdown cancel the separate token, interrupting HTTP.
unsafe extern "C" fn io_cancel(_user: *mut c_void) {}
unsafe extern "C" fn io_close(user: *mut c_void) {
    unsafe {
        drop(Box::from_raw(user as *mut IoContext));
    }
}

struct NativeStream(*mut c_void);
// C calls are made only while holding MediaSession.stream; cancellation uses
// a separately cloned CancellationToken, never an unsynchronized C pointer.
unsafe impl Send for NativeStream {}
impl Drop for NativeStream {
    fn drop(&mut self) {
        unsafe {
            sp_stream_close(self.0);
        }
    }
}
impl NativeStream {
    fn open(context: IoContext, key: &[u8]) -> Result<Self, ()> {
        let user = Box::into_raw(Box::new(context)) as *mut c_void;
        let io = SpIo {
            user,
            size: io_size,
            read_at: io_read,
            cancel: io_cancel,
            close: io_close,
        };
        let mut error = SpError {
            code: 0,
            message: [0; 192],
        };
        let ptr = unsafe { sp_stream_open(&io, key.as_ptr(), &mut error) };
        if ptr.is_null() {
            unsafe { io_close(user) };
            return Err(());
        }
        Ok(Self(ptr))
    }
    fn read(&mut self, offset: u64, length: usize) -> Result<Vec<u8>, ()> {
        let mut error = SpError {
            code: 0,
            message: [0; 192],
        };
        let mut out = vec![0; length];
        if unsafe { sp_stream_seek(self.0, offset as i64, &mut error) } < 0 {
            return Err(());
        }
        // The C stream can return at an MP4 atom boundary. Accumulate bounded
        // chunks to satisfy the exact range promised by the HTTP response.
        let mut filled = 0;
        while filled < length {
            let remaining = length - filled;
            let n = unsafe {
                sp_stream_read(self.0, out.as_mut_ptr().add(filled), remaining, &mut error)
            };
            if n <= 0 || n as usize > remaining {
                return Err(());
            }
            filled += n as usize;
        }
        Ok(out)
    }
}
struct MediaSession {
    stream: Mutex<NativeStream>,
    size: u64,
    cancel: CancellationToken,
    stats: Arc<IoStats>,
    _slot: tokio::sync::OwnedSemaphorePermit,
}
impl Drop for MediaSession {
    fn drop(&mut self) {
        self.cancel.cancel();
    }
}
pub struct MediaManager {
    sessions: Mutex<HashMap<String, Arc<MediaSession>>>,
    client: reqwest::Client,
    sandbox: PathBuf,
    pub cancel: CancellationToken,
    slots: Arc<tokio::sync::Semaphore>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct OpenSource {
    #[serde(rename = "cdnUrl")]
    url: String,
    #[serde(rename = "keyHex")]
    key_hex: String,
}
impl MediaManager {
    pub fn new(sandbox: PathBuf) -> Result<Self, String> {
        let client = reqwest::Client::builder()
            .tls_backend_preconfigured(crate::upstream::http::build_tls_config()?)
            .connect_timeout(Duration::from_secs(8))
            .timeout(Duration::from_secs(15))
            .build()
            .map_err(|_| "media HTTP client unavailable")?;
        Ok(Self {
            sessions: Mutex::new(HashMap::new()),
            client,
            sandbox,
            cancel: CancellationToken::new(),
            slots: Arc::new(tokio::sync::Semaphore::new(MAX_SESSIONS)),
        })
    }
    async fn open(&self, input: OpenSource) -> Result<String, ()> {
        if self.cancel.is_cancelled() {
            return Err(());
        }
        let slot = self.slots.clone().try_acquire_owned().map_err(|_| ())?;
        if self.sessions.lock().map_err(|_| ())?.len() >= MAX_SESSIONS {
            return Err(());
        }
        let mut key = hex::decode(input.key_hex).map_err(|_| ())?;
        if key.len() != 16 {
            return Err(());
        }
        let cancel = self.cancel.child_token();
        let stats = Arc::new(IoStats::default());
        let (source, size) =
            if input.url.starts_with("https://") || input.url.starts_with("http://") {
                let response = self
                    .client
                    .get(&input.url)
                    .header(header::RANGE, "bytes=0-0")
                    .header(header::ACCEPT_ENCODING, "identity")
                    .send()
                    .await
                    .map_err(|_| ())?;
                if response.status() != StatusCode::PARTIAL_CONTENT {
                    return Err(());
                }
                let value = response
                    .headers()
                    .get(header::CONTENT_RANGE)
                    .and_then(|v| v.to_str().ok())
                    .ok_or(())?;
                let size = value
                    .strip_prefix("bytes 0-0/")
                    .and_then(|v| v.parse::<u64>().ok())
                    .ok_or(())?;
                (
                    Source::Remote {
                        client: self.client.clone(),
                        url: input.url,
                    },
                    size,
                )
            } else {
                let path = if input.url.starts_with("file://") {
                    url::Url::parse(&input.url)
                        .map_err(|_| ())?
                        .to_file_path()
                        .map_err(|_| ())?
                } else {
                    PathBuf::from(input.url)
                };
                let path = std::fs::canonicalize(path).map_err(|_| ())?;
                let root = std::fs::canonicalize(&self.sandbox).map_err(|_| ())?;
                if !path.starts_with(root) {
                    return Err(());
                }
                let file = File::open(path).map_err(|_| ())?;
                let size = file.metadata().map_err(|_| ())?.len();
                (Source::Local(file), size)
            };
        if size < 8 || size > i64::MAX as u64 {
            return Err(());
        }
        let context = IoContext {
            source,
            size,
            runtime: tokio::runtime::Handle::current(),
            cancel: cancel.clone(),
            cache: VecDeque::new(),
            stats: stats.clone(),
        };
        let stream = tokio::task::spawn_blocking(move || {
            let result = NativeStream::open(context, &key);
            use zeroize::Zeroize;
            key.zeroize();
            result
        })
        .await
        .map_err(|_| ())??;
        if cancel.is_cancelled() {
            return Err(());
        }
        let mut entropy = [0; 16];
        rand::rngs::OsRng
            .try_fill_bytes(&mut entropy)
            .map_err(|_| ())?;
        let id = hex::encode(entropy);
        let mut sessions = self.sessions.lock().map_err(|_| ())?;
        if sessions.len() >= MAX_SESSIONS {
            return Err(());
        }
        sessions.insert(
            id.clone(),
            Arc::new(MediaSession {
                stream: Mutex::new(stream),
                size,
                cancel,
                stats,
                _slot: slot,
            }),
        );
        Ok(id)
    }
    pub async fn handle(
        self: &Arc<Self>,
        path: &str,
        req: axum::extract::Request,
        prefix: &str,
    ) -> Response {
        if self.cancel.is_cancelled() {
            return StatusCode::SERVICE_UNAVAILABLE.into_response();
        }
        if path == "/harmony-media/open" && req.method() == Method::POST {
            let bytes = match axum::body::to_bytes(req.into_body(), 4096).await {
                Ok(v) => v,
                Err(_) => return StatusCode::PAYLOAD_TOO_LARGE.into_response(),
            };
            let input = match serde_json::from_slice::<OpenSource>(&bytes) {
                Ok(v) => v,
                Err(_) => return StatusCode::BAD_REQUEST.into_response(),
            };
            return match self.open(input).await {
                Ok(id) => axum::Json(json!({"id":id,"url":format!("{prefix}/harmony-media/{id}")}))
                    .into_response(),
                Err(_) => StatusCode::UNPROCESSABLE_ENTITY.into_response(),
            };
        }
        let Some(id) = path.strip_prefix("/harmony-media/") else {
            return StatusCode::NOT_FOUND.into_response();
        };
        if req.method() == Method::DELETE {
            if let Ok(mut all) = self.sessions.lock() {
                if let Some(session) = all.remove(id) {
                    session.cancel.cancel();
                }
            }
            return StatusCode::NO_CONTENT.into_response();
        }
        let session = match self
            .sessions
            .lock()
            .ok()
            .and_then(|all| all.get(id).cloned())
        {
            Some(v) => v,
            None => return StatusCode::NOT_FOUND.into_response(),
        };
        if req.method() != Method::GET && req.method() != Method::HEAD {
            return StatusCode::METHOD_NOT_ALLOWED.into_response();
        }
        let (offset, length, status) = match parse_range(
            req.headers()
                .get(header::RANGE)
                .and_then(|v| v.to_str().ok()),
            session.size,
        ) {
            ByteRange::Full => (0, session.size, StatusCode::OK),
            ByteRange::Partial { start, end } => {
                (start, end - start + 1, StatusCode::PARTIAL_CONTENT)
            }
            ByteRange::Unsatisfiable => {
                return Response::builder()
                    .status(416)
                    .header(header::CONTENT_RANGE, format!("bytes */{}", session.size))
                    .body(Body::empty())
                    .unwrap()
            }
        };
        let mut builder = Response::builder()
            .status(status)
            .header(header::CONTENT_TYPE, "video/mp4")
            .header(header::ACCEPT_RANGES, "bytes")
            .header(header::CONTENT_LENGTH, length)
            .header(header::CACHE_CONTROL, "no-store")
            .header(header::REFERRER_POLICY, "no-referrer");
        if status == StatusCode::PARTIAL_CONTENT {
            builder = builder.header(
                header::CONTENT_RANGE,
                format!("bytes {offset}-{}/{}", offset + length - 1, session.size),
            );
        }
        if req.method() == Method::HEAD {
            return builder.body(Body::empty()).unwrap();
        }
        let (tx, rx) = tokio::sync::mpsc::channel::<Result<Bytes, std::io::Error>>(2);
        tokio::spawn(async move {
            let mut at = offset;
            let end = offset + length;
            while at < end && !session.cancel.is_cancelled() && !tx.is_closed() {
                let count = (end - at).min(BLOCK as u64) as usize;
                let copy = session.clone();
                let data = tokio::task::spawn_blocking(move || {
                    copy.stream.lock().map_err(|_| ())?.read(at, count)
                })
                .await;
                match data {
                    Ok(Ok(bytes)) => {
                        at += bytes.len() as u64;
                        if tx.send(Ok(Bytes::from(bytes))).await.is_err() {
                            break;
                        }
                    }
                    _ => {
                        let _ = tx
                            .send(Err(std::io::Error::other("media read failed")))
                            .await;
                        break;
                    }
                }
            }
        });
        let stream = futures::stream::unfold(rx, |mut rx| async {
            rx.recv().await.map(|item| (item, rx))
        });
        builder.body(Body::from_stream(stream)).unwrap()
    }
    pub fn stats(&self) -> serde_json::Value {
        let Ok(all) = self.sessions.lock() else {
            return json!({"active":0});
        };
        json!({"active":all.len(),"requests":all.values().map(|s|s.stats.requests.load(Ordering::Relaxed)).sum::<u64>(),
            "fetched":all.values().map(|s|s.stats.fetched.load(Ordering::Relaxed)).sum::<u64>(),
            "maxCacheBytes":all.values().map(|s|s.stats.peak_cache.load(Ordering::Relaxed)).max().unwrap_or(0)})
    }
}
