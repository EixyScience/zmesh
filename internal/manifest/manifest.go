package manifest

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"time"

	"gopkg.in/ini.v1"
)

type Scalefs struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	ShortID string `json:"shortid"`
}

type Paths struct {
	Body      string `json:"body"`
	Main      string `json:"main"`
	State     string `json:"state"`
	GlobalD   string `json:"global_d"`
	LocalD    string `json:"local_d"`
	RuntimeD  string `json:"runtime_d"`
}

type ZFS struct {
	Enabled            bool   `json:"enabled"`
	Pool               string `json:"pool,omitempty"`
	Dataset            string `json:"dataset,omitempty"`
	DriveletterMode    string `json:"driveletter_mode,omitempty"`      // off|on|auto
	Driveletter        string `json:"driveletter,omitempty"`           // optional
	DriveletterOffForce bool  `json:"driveletter_off_force,omitempty"` // orchestration policy
}

type Manifest struct {
	OK           bool   `json:"ok"`
	GeneratedUnix int64 `json:"generated_unix"`
	OS           string `json:"os"`
	Path         string `json:"path"`

	Scalefs Scalefs `json:"scalefs"`
	Paths  Paths   `json:"paths"`

	// echo of config values (relative paths as written in ini)
	Config struct {
		StateDir  string `json:"state_dir"`
		WatchRoot string `json:"watch_root"`
	} `json:"config"`

	ZFS ZFS `json:"zfs"`
}

func LoadFromBodyDir(bodyDir string) (*Manifest, error) {
	bodyDir, err := filepath.Abs(bodyDir)
	if err != nil {
		return nil, err
	}
	iniPath := filepath.Join(bodyDir, "scalefs.ini")
	if _, err := os.Stat(iniPath); err != nil {
		return nil, errors.New("missing scalefs.ini: " + iniPath)
	}

	cfg, err := ini.Load(iniPath)
	if err != nil {
		return nil, err
	}

	m := &Manifest{
		OK:            true,
		GeneratedUnix: time.Now().Unix(),
		OS:            runtime.GOOS,
		Path:          bodyDir,
	}

	m.Scalefs.ID = cfg.Section("scalefs").Key("id").String()
	m.Scalefs.Name = cfg.Section("scalefs").Key("name").String()
	m.Scalefs.ShortID = cfg.Section("scalefs").Key("shortid").String()

	stateDir := cfg.Section("paths").Key("state_dir").MustString("./scalefs.state")
	watchRoot := cfg.Section("paths").Key("watch_root").MustString("./main")
	m.Config.StateDir = stateDir
	m.Config.WatchRoot = watchRoot

	m.Paths.Body = bodyDir
	m.Paths.Main = filepath.Join(bodyDir, "main")
	m.Paths.State = filepath.Join(bodyDir, "scalefs.state")
	m.Paths.GlobalD = filepath.Join(bodyDir, "scalefs.global.d")
	m.Paths.LocalD = filepath.Join(bodyDir, "scalefs.local.d")
	m.Paths.RuntimeD = filepath.Join(bodyDir, "scalefs.runtime.d")

	// zfs section (optional)
	zsec := cfg.Section("zfs")
	m.ZFS.Enabled = zsec.Key("enabled").MustBool(false)
	m.ZFS.Pool = zsec.Key("pool").String()
	m.ZFS.Dataset = zsec.Key("dataset").String()
	m.ZFS.DriveletterMode = zsec.Key("driveletter_mode").String()
	m.ZFS.Driveletter = zsec.Key("driveletter").String()
	m.ZFS.DriveletterOffForce = zsec.Key("driveletter_off_force").MustBool(false)

	return m, nil
}

func (m *Manifest) JSON() ([]byte, error) {
	return json.MarshalIndent(m, "", "  ")
}