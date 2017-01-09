#!/bin/bash

# build assets bindata.go file
go-bindata ./assets/... index.html

# build executable for linux, osx and windows
GOOS=linux GOARCH=amd64 go build -o timesheet-linux64
GOOS=darwin GOARCH=amd64 go build -o timesheet-osx64
GOOS=windows GOARCH=amd64 go build -o timesheet-win64.exe
