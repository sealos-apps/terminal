// Copyright © 2024 sealos.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

package config

import (
	"os"

	"gopkg.in/yaml.v3"
)

type Global struct {
	CloudDomain    string `yaml:"cloudDomain"`
	CloudPort      string `yaml:"cloudPort"`
	HTTPPort       string `yaml:"httpPort"`
	DisableHTTPS   bool   `yaml:"disableHttps"`
	RegionUID      string `yaml:"regionUID"`
	CertSecretName string `yaml:"certSecretName"`
}

func LoadConfig(path string, target any) error {
	configData, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return yaml.Unmarshal(configData, target)
}
