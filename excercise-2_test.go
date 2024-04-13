package exercise

import (
	"os"
	"testing"
)

const (
	s = `
	This is a test string in a test file for the
	shred function.
	`

	testDataDir = "testdata"
)

func TestShred(t *testing.T) {
	// Case #1: Shred path is a directory, should return nil
	if err := Shred(testDataDir); err != nil {
		t.Fatalf("unexpected error, got %v, expected: nil", err)
	}

	// Case #2: Shred path is a file, should return nil.
	filePath := helperNewFile(t, testDataDir)

	if err := Shred(filePath); err != nil {
		t.Fatalf("unexpected error, got %v, expected: nil", err)
	}

	// Case #3: Shred path is invalid, should return os.ErrNotExist error.
	if err := Shred(""); err == nil {
		t.Fatalf("expected error, got nil, expected: path not exist")
	}

	// Case 4: Shred path is a block type device
	// NOT IMPLEMENTED
}

func helperNewFile(t *testing.T, dir string) string {
	// Setup test file for shred function.
	f, err := os.CreateTemp(dir, "file")
	if err != nil {
		t.Fatalf("failed to setup test file: %v", err)
	}

	defer f.Close()

	if _, err := f.Write([]byte(s)); err != nil {
		t.Fatalf("failed to write test data to file: %v", err)
	}

	return f.Name()
}
