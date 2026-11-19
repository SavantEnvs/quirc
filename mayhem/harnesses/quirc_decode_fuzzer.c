/*
 * quirc_decode_fuzzer — quirc_decode() on a caller-filled public
 * struct quirc_code, the second stage of the public API (decode.c: format
 * BCH correction, version_db lookup, Reed-Solomon block correction, data
 * stream de-interleaving, numeric/alnum/byte/kanji/ECI payload parsing),
 * then, on a data-ECC failure, quirc_flip() + quirc_decode() again (the
 * mirrored-code retry README.md documents).
 *
 * Random images almost never get through capstone detection, so this is the
 * practical way to drive decode.c in depth.
 *
 * Input layout:
 *   bytes 0..1  code.size as a little-endian int16 — deliberately NOT
 *               clamped: callers may hand quirc_decode any size, and the
 *               library must reject invalid ones itself.
 *   bytes 2..   code.cell_bitmap (QUIRC_MAX_BITMAP bytes, zero-padded;
 *               extra bytes ignored)
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "quirc.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	struct quirc_code code;
	struct quirc_data out;

	if (size < 2)
		return 0;

	memset(&code, 0, sizeof(code));
	code.size = (int16_t)(data[0] | (data[1] << 8));
	data += 2;
	size -= 2;
	if (size > sizeof(code.cell_bitmap))
		size = sizeof(code.cell_bitmap);
	memcpy(code.cell_bitmap, data, size);

	/* The documented mirror retry (README.md): flip and decode again on a
	 * data-ECC failure. That error implies a valid grid size, which is the
	 * precondition of quirc_flip() (it has no size check of its own). */
	if (quirc_decode(&code, &out) == QUIRC_ERROR_DATA_ECC) {
		quirc_flip(&code);
		quirc_decode(&code, &out);
	}
	return 0;
}
