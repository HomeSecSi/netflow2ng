EXTENSION ?=
DIST_DIR ?= dist/
GOOS ?= $(shell uname -s | tr "[:upper:]" "[:lower:]")
ARCH ?= $(shell uname -m)
BUILDINFOSDET ?=

# find golangci-lint
GOLANGCI_LINT ?= $(shell go env GOPATH)/bin/golangci-lint
ifneq ($(shell test -e $(GOLANGCI_LINT) && echo -n yes),yes)
    GOLANGCI_LINT = $(shell which golangci-lint)
endif

DOCKER_REPO        := synfinatic/
NETFLOW2NG_NAME    := netflow2ng
NETFLOW2NG_VERSION := $(shell git describe --tags 2>/dev/null $(git rev-list --tags --max-count=1))
VERSION_PKG        := $(shell echo $(NETFLOW2NG_VERSION) | sed 's/^v//g')
ARCH               := x86_64
LICENSE            := MIT
URL                := https://github.com/synfinatic/netflow2ng
DESCRIPTION        := NetFlow2ng: a NetFlow v9 collector to ntopng
BUILDINFOS         := ($(shell date +%FT%T%z)$(BUILDINFOSDET))
LDFLAGS            := '-X main.version=$(NETFLOW2NG_VERSION) -X main.buildinfos=$(BUILDINFOS)'

OUTPUT_NETFLOW2NG  := $(DIST_DIR)netflow2ng-$(NETFLOW2NG_VERSION)-$(GOOS)-$(ARCH)$(EXTENSION)

ALL: netflow2ng

test: test-race vet unittest

ci: test ci-tests

.PHONY: ci-tests
ci-tests:
	@echo $(GOLANGCI_LINT)
	$(GOLANGCI_LINT) run

install-golangci-lint:
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(shell go env GOPATH)/bin v1.23.3

clean:
	rm -rf dist

clean-docker:
	docker-compose -f docker-compose-pkg.yml rm -f
	docker image rm netflow2ng_packager:latest
	docker image rm synfinatic/netflow2ng:latest

netflow2ng: $(OUTPUT_NETFLOW2NG)

$(OUTPUT_NETFLOW2NG): prepare
	go build -ldflags $(LDFLAGS) -o $(OUTPUT_NETFLOW2NG) cmd/netflow2ng/netflow2ng.go

PHONY: docker-run
docker-run:
	docker run -it --rm -p 5556:5556/tcp -p 8080:8080/tcp -p 2055:2055/udp synfinatic/netflow2ng:latest

PHONY: docker-build
docker-build:
	docker build -t synfinatic/netflow2ng:latest .

.PHONY: unittest
unittest:
	@echo running unit tests...
	go test ./...

.PHONY: vet
vet:
	@echo checking code is vetted...
	go vet $(shell go list ./...)

.PHONY: test-race
test-race:
	@echo testing code for races...
	go test -race ./...

.PHONY: prepare
prepare:
	mkdir -p $(DIST_DIR)

.PHONY: package
package:
	docker-compose -f docker-compose-pkg.yml up

# These targets aren't for you.
.PHONY: .package-deb
.package-deb: $(OUTPUT_NETFLOW2NG)
	fpm -s dir -t deb -n $(NETFLOW2NG_NAME) -v $(VERSION_PKG) \
        --description "$(DESCRIPTION)"  \
        --url "$(URL)" \
        --architecture $(ARCH) \
        --license "$(LICENSE)" \
       	--deb-no-default-config-files \
        --package $(DIST_DIR) \
        $(OUTPUT_NETFLOW2NG)=/usr/bin/netflow2ng \
        package/netflow2ng.service=/lib/systemd/system/netflow2ng.service \
        package/netflow2ng.env=/etc/default/netflow2ng

.PHONY: .package-rpm
.package-rpm: $(OUTPUT_NETFLOW2NG)
	fpm -s dir -t rpm -n $(NETFLOW2NG_NAME) -v $(VERSION_PKG) \
        --description "$(DESCRIPTION)" \
        --url "$(URL)" \
        --architecture $(ARCH) \
        --license "$(LICENSE) "\
        --package $(DIST_DIR) \
        $(OUTPUT_NETFLOW2NG)=/usr/bin/netflow2ng \
        package/netflow2ng.service=/lib/systemd/system/netflow2ng.service \
        package/netflow2ng.env=/etc/default/netflow2ng
