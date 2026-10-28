fn main() {
    let files = [
        "../native/crypto_core/sp_error.c",
        "../native/crypto_core/sp_stream.c",
        "../native/crypto_core/mp4_cenc.c",
        "../native/crypto_core/sp_aes.c",
        "../native/third_party/tiny_aes/aes.c",
    ];
    let mut build = cc::Build::new();
    build
        .std("c11")
        .define("CBC", "0")
        .define("CTR", "0")
        .define("ECB", "1")
        .include("../native/crypto_core");
    if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
        build.flag_if_supported("/experimental:c11atomics");
    }
    for file in files {
        build.file(file);
        println!("cargo:rerun-if-changed={file}");
    }
    println!("cargo:rerun-if-changed=../native/crypto_core/sp_crypto.h");
    build.compile("fq_cenc");
}
