/*
 * quirc_selftest — known-answer driver for mayhem/test.sh.
 *
 * For each binary PGM (P5, maxval 255) named on the command line, runs the
 * public quirc pipeline (resize/begin/end/count/extract/decode, with the
 * README's quirc_flip retry on a data-ECC failure) and prints one line per
 * code found:
 *
 *   <file> #<i> size=<n> version=<v> ecc=<e> mask=<m> type=<t> eci=<x> flipped=<0|1> payload=<hex>
 *
 * or "<file> codes=0" / "<file> #<i> error=<quirc_strerror>". test.sh diffs
 * this against a golden file whose payloads were produced by an independent
 * QR encoder.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "quirc.h"

static unsigned char *load_pgm(const char *path, int *w, int *h)
{
	FILE *f = fopen(path, "rb");
	int maxval;
	unsigned char *buf;

	if (!f)
		return NULL;
	if (fscanf(f, "P5 %d %d %d", w, h, &maxval) != 3 || maxval != 255 ||
	    *w <= 0 || *h <= 0 || fgetc(f) == EOF) {
		fclose(f);
		return NULL;
	}
	buf = malloc((size_t)*w * (size_t)*h);
	if (buf && fread(buf, 1, (size_t)*w * (size_t)*h, f) !=
	    (size_t)*w * (size_t)*h) {
		free(buf);
		buf = NULL;
	}
	fclose(f);
	return buf;
}

int main(int argc, char **argv)
{
	int status = 0;

	for (int a = 1; a < argc; a++) {
		const char *name = strrchr(argv[a], '/');
		int w, h;
		unsigned char *pix = load_pgm(argv[a], &w, &h);
		struct quirc *q;

		name = name ? name + 1 : argv[a];
		if (!pix) {
			printf("%s load-failed\n", name);
			status = 1;
			continue;
		}
		q = quirc_new();
		if (!q || quirc_resize(q, w, h) < 0) {
			printf("%s alloc-failed\n", name);
			return 2;
		}
		memcpy(quirc_begin(q, NULL, NULL), pix, (size_t)w * h);
		quirc_end(q);

		int n = quirc_count(q);
		if (n == 0)
			printf("%s codes=0\n", name);
		for (int i = 0; i < n; i++) {
			static struct quirc_code code;
			static struct quirc_data data;
			int flipped = 0;
			quirc_decode_error_t err;

			quirc_extract(q, i, &code);
			err = quirc_decode(&code, &data);
			if (err == QUIRC_ERROR_DATA_ECC) {
				quirc_flip(&code);
				err = quirc_decode(&code, &data);
				flipped = 1;
			}
			if (err) {
				printf("%s #%d error=%s\n", name, i,
				       quirc_strerror(err));
				continue;
			}
			printf("%s #%d size=%d version=%d ecc=%d mask=%d type=%d eci=%u flipped=%d payload=",
			       name, i, code.size, data.version, data.ecc_level,
			       data.mask, data.data_type, (unsigned)data.eci,
			       flipped);
			for (int k = 0; k < data.payload_len; k++)
				printf("%02x", data.payload[k]);
			printf("\n");
		}
		quirc_destroy(q);
		free(pix);
	}
	return status;
}
