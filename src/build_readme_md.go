// Package main builds README.md files from templates by detecting reusable GitHub Actions workflows.
package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"text/template"

	"gopkg.in/yaml.v3"
)

var (
	version      = "dev"
	execCommand  = exec.Command
	execLookPath = exec.LookPath
)

type Workflow struct {
	Name string `yaml:"name"`
	File string
}

type projectPaths struct {
	rootDir string
}

func main() {
	var debug, info, version bool
	flag.BoolVar(&debug, "debug", false, "log with DEBUG level")
	flag.BoolVar(&info, "info", false, "log with INFO level")
	flag.BoolVar(&version, "version", false, "show version")
	flag.Parse()

	if version {
		fmt.Printf("build_readme_md.go %s\n", getVersion())
		return
	}

	setLogLevel(debug, info)

	paths := resolveProjectPaths()
	readmeMD := filepath.Join(paths.rootDir, "README.md")
	readmeMDJ2 := filepath.Join(paths.rootDir, "README.md.j2")
	workflowDir := filepath.Join(paths.rootDir, ".github", "workflows")

	workflows := detectReusableWorkflows(workflowDir)
	if len(workflows) == 0 {
		log.Fatal("Error: No reusable workflows found")
	}
	renderMD(workflows, readmeMDJ2, readmeMD)
}

func resolveProjectPaths() projectPaths {
	cwd, err := os.Getwd()
	if err != nil {
		log.Fatalf("Failed to determine current working directory: %v", err)
	}

	candidates := []projectPaths{
		{
			rootDir: cwd,
		},
		{
			rootDir: filepath.Dir(cwd),
		},
	}

	for _, paths := range candidates {
		if isProjectPathCandidate(paths) {
			return paths
		}
	}

	log.Fatalf("Failed to resolve repository paths from working directory: %s", cwd)
	return projectPaths{}
}

func isProjectPathCandidate(paths projectPaths) bool {
	return pathExists(filepath.Join(paths.rootDir, "README.md.j2")) &&
		pathExists(filepath.Join(paths.rootDir, ".github", "workflows"))
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func setLogLevel(debug, info bool) {
	switch {
	case debug:
		log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
	case info:
		log.SetFlags(log.Ldate | log.Ltime)
	default:
		log.SetOutput(io.Discard)
	}
}

func detectReusableWorkflows(workflowDir string) []Workflow {
	printLog(fmt.Sprintf("Detect reusable workflows: %s", workflowDir))

	entries, err := os.ReadDir(workflowDir)
	if err != nil {
		log.Fatalf("Failed to read workflow directory: %v", err)
	}

	var workflows []Workflow

	// Create a copy of entries to avoid side effects
	sortedEntries := make([]os.DirEntry, len(entries))
	copy(sortedEntries, entries)

	// Sort the copy by name
	sort.Slice(sortedEntries, func(i, j int) bool {
		return sortedEntries[i].Name() < sortedEntries[j].Name()
	})

	for _, entry := range sortedEntries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), ".yml") {
			filePath := filepath.Join(workflowDir, entry.Name())
			// Clean the path to prevent directory traversal
			filePath = filepath.Clean(filePath)

			// Ensure the file is within the workflow directory
			if !strings.HasPrefix(filePath, filepath.Clean(workflowDir)) {
				log.Printf("Skipping file outside workflow directory: %s", filePath)
				continue
			}

			log.Printf("Read YAML: %s", filePath)

			data, err := os.ReadFile(filePath) // #nosec G304 -- path is validated
			if err != nil {
				log.Printf("Failed to read file %s: %v", filePath, err)
				continue
			}

			var workflowData map[string]interface{}
			if err := yaml.Unmarshal(data, &workflowData); err != nil {
				log.Printf("Failed to parse YAML %s: %v", filePath, err)
				continue
			}

			log.Printf("YAML: %v", workflowData)

			// Check if it's a reusable workflow
			if name, hasName := workflowData["name"].(string); hasName {
				if onMap, hasOn := workflowData["on"].(map[string]interface{}); hasOn {
					if _, hasWorkflowCall := onMap["workflow_call"]; hasWorkflowCall {
						fmt.Printf("  - %s\n", filePath)
						workflows = append(workflows, Workflow{
							Name: name,
							File: entry.Name(),
						})
					}
				} else if onValue, hasOn := workflowData["on"].(string); hasOn && onValue == "workflow_call" {
					fmt.Printf("  - %s\n", filePath)
					workflows = append(workflows, Workflow{
						Name: name,
						File: entry.Name(),
					})
				}
			}
		}
	}

	return workflows
}

func renderMD(workflows []Workflow, templatePath, outputPath string) {
	printLog(fmt.Sprintf("Render a Markdown file: %s", outputPath))

	// Clean and validate the template path
	templatePath = filepath.Clean(templatePath)
	if strings.Contains(templatePath, "..") {
		log.Fatalf("Invalid template path: %s", templatePath)
	}

	templateContent, err := os.ReadFile(templatePath) // #nosec G304 -- path is validated
	if err != nil {
		log.Fatalf("Failed to read template file: %v", err)
	}

	// Convert Jinja2 syntax to Go template syntax
	templateStr := convertJinja2ToGoTemplate(string(templateContent))

	tmpl, err := template.New("readme").Parse(templateStr)
	if err != nil {
		log.Fatalf("Failed to parse template: %v", err)
	}

	var buf bytes.Buffer
	data := struct {
		Workflows []Workflow
	}{
		Workflows: workflows,
	}

	if err := tmpl.Execute(&buf, data); err != nil {
		log.Fatalf("Failed to execute template: %v", err)
	}

	content := buf.Bytes()
	content, err = formatMarkdownWithPrettier(outputPath, content)
	if err != nil {
		log.Fatalf("Failed to format output file: %v", err)
	}

	if err := os.WriteFile(outputPath, content, 0o600); err != nil {
		log.Fatalf("Failed to write output file: %v", err)
	}
}

func formatMarkdownWithPrettier(outputPath string, content []byte) ([]byte, error) {
	printLog(fmt.Sprintf("Format a Markdown file with prettier: %s", outputPath))

	if _, err := execLookPath("npx"); err != nil {
		if errors.Is(err, exec.ErrNotFound) {
			log.Printf("npx is not installed; skip formatting: %s", outputPath)
			return content, nil
		}
		return nil, fmt.Errorf("failed to locate npx: %w", err)
	}

	// Let prettier infer the markdown parser from the target path while formatting in memory.
	cmd := execCommand("npx", "-y", "prettier", "--stdin-filepath", outputPath)
	cmd.Stdin = bytes.NewReader(content)

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if stderr.Len() > 0 {
			return nil, fmt.Errorf("prettier failed: %w: %s", err, strings.TrimSpace(stderr.String()))
		}
		return nil, fmt.Errorf("prettier failed: %w", err)
	}

	return stdout.Bytes(), nil
}

func printLog(message string) {
	fmt.Printf(">>\t%s\n", message)
	_ = os.Stdout.Sync()
}

func convertJinja2ToGoTemplate(template string) string {
	result := template
	result = strings.ReplaceAll(result, "{% for f in workflows %}", "{{range .Workflows}}")
	result = strings.ReplaceAll(result, "{% endfor %}", "{{end}}")
	result = strings.ReplaceAll(result, "{{ f.file }}", "{{.File}}")
	result = strings.ReplaceAll(result, "{{ f.name }}", "{{.Name}}")
	return result
}

func getVersion() string {
	return version
}
