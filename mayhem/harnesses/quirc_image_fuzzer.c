/*
 * quirc_image_fuzzer — the whole public recognition pipeline on an 8-bit
 * grayscale image: quirc_resize/quirc_begin/quirc_end (identify.c:
 * thresholding, flood fill, capstone/grid/alignment search, perspective),
 * then quirc_extract + quirc_decode (decode.c) on every grid found, and the
 * ISO 18004 mirror retry (quirc_flip + quirc_decode) on a data-ECC failure.
 *
 * Input layout:
 *   bytes 0..1  image width, big-endian, mapped onto 1..1024
 *   bytes 2..   row-major grayscale pixels; height = len / width, at most
 *               1024 rows (both bounds keep one exec cheap: the flood fill
 *               and alignment search are per pixel). Leftover bytes that do
 *               not fill a row are ignored.
 *
 * A fresh recognizer per input: nothing is kept across iterations.
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "quirc.h"

#define MAX_DIM 1024

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (size < 2)
		return 0;

	int w = (((int)data[0] << 8) | data[1]) % MAX_DIM + 1;
	data += 2;
	size -= 2;
	size_t rows = size / (size_t)w;
	int h = rows > MAX_DIM ? MAX_DIM : (int)rows;

	struct quirc *q = quirc_new();
	if (!q)
		return 0;
	if (quirc_resize(q, w, h) < 0) {
		quirc_destroy(q);
		return 0;
	}

	int bw = 0, bh = 0;
	uint8_t *img = quirc_begin(q, &bw, &bh);
	memcpy(img, data, (size_t)w * (size_t)h);
	quirc_end(q);

	int n = quirc_count(q);
	for (int i = 0; i < n; i++) {
		struct quirc_code code;
		struct quirc_data out;

		quirc_extract(q, i, &code);
		/* Mirror retry exactly as README.md documents it. */
		if (quirc_decode(&code, &out) == QUIRC_ERROR_DATA_ECC) {
			quirc_flip(&code);
			quirc_decode(&code, &out);
		}
	}

	quirc_destroy(q);
	return 0;
}
