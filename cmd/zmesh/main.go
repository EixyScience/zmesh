package main

import (
"flag"
"fmt"
"os"
"strings"
"time"

"github.com/EixyScience/zmesh/internal/agent"
"github.com/EixyScience/zmesh/internal/config"
"github.com/EixyScience/zmesh/internal/version"
)

func main() {
if len(os.Args) < 2 {
usage()
os.Exit(2)
}

switch os.Args[1] {
case "agent":
agentCmd(os.Args[2:])
case "ping":
pingCmd(os.Args[2:])
case "version":
fmt.Println(version.String())
default:
usage()
os.Exit(2)
}
}

func usage() {
fmt.Fprintf(os.Stderr, \zmesh (bootstrap)

Usage:
  zmesh agent   -c <config.ini>
  zmesh ping    -url <http(s)://host:port> [-timeout 3s]
  zmesh version
\)
}

func agentCmd(args []string) {
fs := flag.NewFlagSet("agent", flag.ExitOnError)
cfgPath := fs.String("c", "zmesh.conf", "path to config ini")
fs.Parse(args)

cfg, err := config.Load(*cfgPath)
if err != nil {
fmt.Fprintf(os.Stderr, "config load error: %v\n", err)
os.Exit(1)
}

a := agent.New(cfg)
if err := a.Run(); err != nil {
fmt.Fprintf(os.Stderr, "agent error: %v\n", err)
os.Exit(1)
}
}

func pingCmd(args []string) {
fs := flag.NewFlagSet("ping", flag.ExitOnError)
url := fs.String("url", "", "target URL like http://host:port")
timeout := fs.Duration("timeout", 3*time.Second, "timeout")
fs.Parse(args)

if strings.TrimSpace(*url) == "" {
fmt.Fprintln(os.Stderr, "ping: -url is required")
os.Exit(2)
}

ok, msg, err := agent.PingHTTP(*url, *timeout)
if err != nil {
fmt.Fprintf(os.Stderr, "ping error: %v\n", err)
os.Exit(1)
}
if !ok {
fmt.Printf("NG: %s\n", msg)
os.Exit(1)
}
fmt.Printf("OK: %s\n", msg)
}
