package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"text/template"

	"gopkg.in/yaml.v3"
)

var version = "dev"

type Workflow struct {
	Name string `yaml:"name"`
	File string
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

	// Get current working directory (where the script is being run from)
	scriptDir, _ := os.Getwd()

	// Determine root directory based on current location
	var rootDir string
	if filepath.Base(scriptDir) == "src" {
		// We're in the src directory, parent is root
		rootDir = filepath.Dir(scriptDir)
	} else {
		// We might be running from root already
		rootDir = scriptDir
	}

	readmeMD := filepath.Join(rootDir, "README.md")
	readmeMDJ2 := filepath.Join(rootDir, "README.md.j2")
	workflowDir := filepath.Join(rootDir, ".github", "workflows")

	if _, err := os.Stat(readmeMDJ2); errors.Is(err, os.ErrNotExist) {
		log.Fatalf("Error: Template file %s does not exist", readmeMDJ2)
	} else if _, err := os.Stat(workflowDir); errors.Is(err, os.ErrNotExist) {
		log.Fatalf("Error: Workflow directory %s does not exist", workflowDir)
	}
	workflows := detectReusableWorkflows(workflowDir)
	if len(workflows) == 0 {
		log.Fatal("Error: No reusable workflows found")
	}
	renderMD(workflows, readmeMDJ2, readmeMD)
}

func mustAbsPath(path string) string {
	absPath, err := filepath.Abs(path)
	if err != nil {
		log.Fatalf("Failed to get absolute path: %v", err)
	}
	return absPath
}

func setLogLevel(debug, info bool) {
	if debug {
		log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
	} else if info {
		log.SetFlags(log.Ldate | log.Ltime)
	} else {
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
			log.Printf("Read YAML: %s", filePath)

			data, err := os.ReadFile(filePath)
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

	templateContent, err := os.ReadFile(templatePath)
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

	// Remove trailing newlines
	content := bytes.TrimRight(buf.Bytes(), "\n")

	if err := os.WriteFile(outputPath, content, 0644); err != nil {
		log.Fatalf("Failed to write output file: %v", err)
	}
}

func printLog(message string) {
	fmt.Printf(">>\t%s\n", message)
	os.Stdout.Sync()
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
