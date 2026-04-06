package main

import (
	"bytes"
	"os/exec"
	"strings"
	"testing"
)

func TestFormatMarkdownWithPrettier(t *testing.T) {
	restoreExecFuncs := stubExecFuncs()
	defer restoreExecFuncs()

	execLookPath = func(file string) (string, error) {
		if file != "npx" {
			t.Fatalf("unexpected lookup target: %s", file)
		}
		return "/opt/homebrew/bin/npx", nil
	}
	execCommand = func(name string, args ...string) *exec.Cmd {
		if name != "npx" {
			t.Fatalf("unexpected command: %s", name)
		}
		if len(args) != 4 || args[0] != "-y" || args[1] != "prettier" || args[2] != "--stdin-filepath" || args[3] != "/tmp/README.md" {
			t.Fatalf("unexpected prettier args: %v", args)
		}
		return exec.Command(
			"/bin/sh",
			"-c",
			"cat >/dev/null; printf '%s\n%s\n%s\n%s\n' '-y' 'prettier' '--stdin-filepath' '/tmp/README.md'",
		)
	}

	input := []byte("# title\n")
	output, err := formatMarkdownWithPrettier("/tmp/README.md", input)
	if err != nil {
		t.Fatalf("formatMarkdownWithPrettier returned error: %v", err)
	}
	want := []byte("-y\nprettier\n--stdin-filepath\n/tmp/README.md\n")
	if !bytes.Equal(output, want) {
		t.Fatalf("unexpected formatted output: %q", string(output))
	}
}

func TestFormatMarkdownWithPrettierSkipsWhenPrettierIsMissing(t *testing.T) {
	restoreExecFuncs := stubExecFuncs()
	defer restoreExecFuncs()

	commandCalled := false
	execLookPath = func(string) (string, error) {
		return "", exec.ErrNotFound
	}
	execCommand = func(_ string, _ ...string) *exec.Cmd {
		commandCalled = true
		return exec.Command("/bin/sh", "-c", "exit 0")
	}

	input := []byte("# title\n")
	output, err := formatMarkdownWithPrettier("/tmp/README.md", input)
	if err != nil {
		t.Fatalf("formatMarkdownWithPrettier returned error: %v", err)
	}
	if commandCalled {
		t.Fatal("expected prettier command not to run")
	}
	if !bytes.Equal(output, input) {
		t.Fatalf("unexpected formatted output: %q", string(output))
	}
}

func TestFormatMarkdownWithPrettierReturnsCommandErrors(t *testing.T) {
	restoreExecFuncs := stubExecFuncs()
	defer restoreExecFuncs()

	execLookPath = func(string) (string, error) {
		return "/opt/homebrew/bin/npx", nil
	}
	execCommand = func(_ string, _ ...string) *exec.Cmd {
		return exec.Command("/bin/sh", "-c", "echo 'parse error' >&2; exit 1")
	}

	_, err := formatMarkdownWithPrettier("/tmp/README.md", []byte("# title\n"))
	if err == nil {
		t.Fatal("expected an error")
	}
	if !strings.Contains(err.Error(), "parse error") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func stubExecFuncs() func() {
	originalExecCommand := execCommand
	originalExecLookPath := execLookPath
	return func() {
		execCommand = originalExecCommand
		execLookPath = originalExecLookPath
	}
}
