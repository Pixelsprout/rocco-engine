package engine

import "core:encoding/endian"
import "core:hash"

PNG_GRAY :: 0
PNG_RGB :: 2
PNG_RGBA :: 6
PNG_SIGNATURE :: [8]byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}
// The most bytes that one stored deflate block can hold.
PNG_STORED_BLOCK :: 65_535

// A PNG whose one IDAT holds the rows uncompressed, in stored deflate blocks,
// so the host needs no compressor. A 16-bit pixel takes two big-endian bytes
// per channel.
png_encode :: proc(width, height: int, pixels: []byte, color_type := PNG_RGBA, depth := 8, allocator := context.allocator) -> []byte {
	channels := 1 if color_type == PNG_GRAY else (3 if color_type == PNG_RGB else 4)
	row := width * channels * depth / 8
	raw := make([]byte, (row + 1) * height, context.temp_allocator)
	for y in 0 ..< height {
		// Filter type 0: the row as it is.
		raw[y * (row + 1)] = 0
		copy(raw[y * (row + 1) + 1:][:row], pixels[y * row:][:row])
	}

	blocks := max(1, (len(raw) + PNG_STORED_BLOCK - 1) / PNG_STORED_BLOCK)
	zlib_size := 2 + len(raw) + 5 * blocks + 4
	out := make([dynamic]byte, 0, len(PNG_SIGNATURE) + 25 + 12 + zlib_size + 12, allocator)
	signature := PNG_SIGNATURE
	append(&out, ..signature[:])

	ihdr: [13]byte
	endian.put_u32(ihdr[0:], .Big, u32(width))
	endian.put_u32(ihdr[4:], .Big, u32(height))
	ihdr[8] = byte(depth)
	ihdr[9] = byte(color_type)
	png_chunk(&out, "IHDR", ihdr[:])

	// The IDAT data is written in place, so its length goes first.
	be_put(&out, u32(zlib_size))
	idat := len(out)
	append(&out, "IDAT")
	// CMF 0x78 is deflate with a 32 KiB window. FLG 0x01 makes the pair a
	// multiple of 31.
	append(&out, 0x78, 0x01)
	rest := raw
	for {
		n := min(len(rest), PNG_STORED_BLOCK)
		final := byte(1) if n == len(rest) else 0
		append(&out, final, byte(n), byte(n >> 8), byte(~n), byte(~n >> 8))
		append(&out, ..rest[:n])
		rest = rest[n:]
		if final == 1 {
			break
		}
	}
	be_put(&out, hash.adler32(raw))
	be_put(&out, hash.crc32(out[idat:]))

	png_chunk(&out, "IEND", nil)
	return out[:]
}

png_chunk :: proc(out: ^[dynamic]byte, kind: string, data: []byte) {
	be_put(out, u32(len(data)))
	start := len(out)
	append(out, kind)
	append(out, ..data)
	be_put(out, hash.crc32(out[start:]))
}

be_put :: proc(out: ^[dynamic]byte, v: u32) {
	b: [4]byte
	endian.put_u32(b[:], .Big, v)
	append(out, ..b[:])
}
