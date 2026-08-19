// Copyright © 2024 sealos.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

package label

type AppKey = string

const (
	AppName      AppKey = "app.kubernetes.io/name"
	AppInstance  AppKey = "app.kubernetes.io/instance"
	AppVersion   AppKey = "app.kubernetes.io/version"
	AppComponent AppKey = "app.kubernetes.io/component"
	AppPartOf    AppKey = "app.kubernetes.io/part-of"
	AppManagedBy AppKey = "app.kubernetes.io/managed-by"
)

const DefaultManagedBy = "sealos"
