package exercise

import (
	"crypto/rand"
	"fmt"
	"os"
	"syscall"
)

// Limitations:
// 	Modern file systems, and physical storage types aren't intended for shred to be used, due to their recovery designs.
//	Journaling file systems are designed to keep original blocks for recovery, and SSDs (flash memory)
//	use a technique called wear leveling for prolonged service life.

// Thoughts:
// 	From research I've done, it looks like gnu shred has gotten more performant over the years,
//	due to algorithms changing, so performance isn't as bad as it used to be. However,
//	given all the modern advancements that have been made, shred doesn't seem as useful as it once was.

func Shred(path string) error {
	// Open file to shred.
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("failed to open path: %w", err)
	}

	finfo, err := f.Stat()
	if err != nil {
		return fmt.Errorf("failed to stat path: %w", err)
	}

	// If it's a directory, bail early.
	if finfo.IsDir() {
		return nil
	}

	// Assume a default of 4096 block size, in case syscall stat
	// fails below.
	blockSize := 4096

	var stat syscall.Stat_t

	if err := syscall.Stat(os.DevNull, &stat); err == nil {
		blockSize = int(stat.Blksize)
	}

	// Make sure to free up file to avoid resource leak.
	defer f.Close()

	for i := 0; i < 3; i++ {
		b := make([]byte, blockSize)
		// Using the kernels entropy, we generate random bytes we then
		// write to the file.
		if _, err := rand.Read(b); err != nil {
			return fmt.Errorf("failed to get random bytes: %w", err)
		}

		_, _ = f.Write(b)
		// Flush mem-copy back to disk before next write.
		_ = f.Sync()
	}

	return os.Remove(path)
}
