#+build !darwin
package engine

texture_cache_native_bytes :: proc(_: ^Texture_Cache) -> u64 { return 0 }
