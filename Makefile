# chargelimit: a daemon that keeps the battery between two levels, plus its Settings page (PreferenceLoader bundle).
# `make deb` for rootful jailbreaks (armv7 + arm64), `make deb ROOTLESS=1` for rootless ones (arm64, /var/jb): that
# package also carries the helper loaded into accessoryd, which iOS 15 needs.

NAME     := chargelimitd
PACKAGE  := com.lonsdaleite.chargelimit
VERSION  := 1.0.0
MIN_IOS  := 9.3
ARCHS    := armv7 arm64
SDK      ?= $(HOME)/theos/sdks/iPhoneOS9.3.sdk

ifdef ROOTLESS
PREFIX   := /var/jb
DEB_ARCH := iphoneos-arm64
ARCHS    := arm64
OUT      := build/rootless
else
PREFIX   :=
DEB_ARCH := iphoneos-arm
OUT      := build/rootful
endif

BIN   := $(OUT)/bin
STAGE := $(OUT)/stage
ROOT  := $(STAGE)$(PREFIX)
DEB   := $(OUT)/$(PACKAGE)_$(VERSION)_$(DEB_ARCH).deb
SUBST := sed -e 's|@PREFIX@|$(PREFIX)|g' -e 's/@VERSION@/$(VERSION)/' -e 's/@PACKAGE@/$(PACKAGE)/' -e 's/@DEB_ARCH@/$(DEB_ARCH)/'

# armv7 is built as ARM, not Thumb: the current ld drops the Thumb bit from function addresses.
CFLAGS := -isysroot $(SDK) -fobjc-arc -fno-objc-convert-messages-to-runtime-calls -fobjc-runtime=ios-$(MIN_IOS) \
          -O2 -Wall -Wextra -Wno-unused-parameter -Werror=unguarded-availability

.PHONY: all deb sdk clean

all: deb

sdk:
	scripts/fetch-sdk.sh

$(SDK):
	@echo "Missing $(SDK); run 'make sdk'" && exit 1

$(BIN)/$(NAME)-%: src/chargelimitd.m src/Port.h | $(SDK)
	@mkdir -p $(dir $@)
	xcrun clang -target $*-apple-ios$(MIN_IOS) $(CFLAGS) $(EXTRA_CFLAGS) $(if $(filter armv7,$*),-marm) \
	    -DJB_ROOT='"$(PREFIX)"' -Isrc $< -framework Foundation -framework IOKit -lIOAccessoryManager -o $@

$(BIN)/$(NAME): $(foreach arch,$(ARCHS),$(BIN)/$(NAME)-$(arch))
	lipo -create $^ -output $@

$(BIN)/ChargeLimit-%: src/ChargeLimitController.m | $(SDK)
	@mkdir -p $(dir $@)
	xcrun clang -target $*-apple-ios$(MIN_IOS) $(CFLAGS) $(if $(filter armv7,$*),-marm) -bundle $< \
	    -F$(SDK)/System/Library/PrivateFrameworks -framework Foundation -framework UIKit -framework Preferences -o $@

$(BIN)/ChargeLimit: $(foreach arch,$(ARCHS),$(BIN)/ChargeLimit-$(arch))
	lipo -create $^ -output $@

$(BIN)/ChargeLimitHelper.dylib: src/AccessorydHelper.c src/Port.h | $(SDK)
	@mkdir -p $(dir $@)
	xcrun clang -target arm64-apple-ios$(MIN_IOS) -isysroot $(SDK) -O2 -fblocks -Wall -Wextra -Wno-unused-parameter -Isrc \
	    -dynamiclib $< -framework CoreFoundation -framework IOKit -lIOAccessoryManager -o $@

deb: $(BIN)/$(NAME) $(BIN)/ChargeLimit $(if $(ROOTLESS),$(BIN)/ChargeLimitHelper.dylib) packaging/*
	rm -rf $(STAGE)
	mkdir -p $(STAGE)/DEBIAN $(ROOT)/usr/libexec $(ROOT)/Library/LaunchDaemons
	cp -R layout/ $(ROOT)/
	cp $(BIN)/$(NAME) $(ROOT)/usr/libexec/
	ldid -Spackaging/entitlements.plist $(ROOT)/usr/libexec/$(NAME)
	cp $(BIN)/ChargeLimit $(ROOT)/Library/PreferenceBundles/ChargeLimit.bundle/
	ldid -S $(ROOT)/Library/PreferenceBundles/ChargeLimit.bundle/ChargeLimit
	$(SUBST) packaging/com.lonsdaleite.chargelimit.plist > $(ROOT)/Library/LaunchDaemons/com.lonsdaleite.chargelimit.plist
ifdef ROOTLESS
	mkdir -p $(ROOT)/Library/MobileSubstrate/DynamicLibraries
	cp $(BIN)/ChargeLimitHelper.dylib packaging/ChargeLimitHelper.plist $(ROOT)/Library/MobileSubstrate/DynamicLibraries/
	ldid -S $(ROOT)/Library/MobileSubstrate/DynamicLibraries/ChargeLimitHelper.dylib
endif
	$(SUBST) packaging/control > $(STAGE)/DEBIAN/control
	for f in postinst prerm; do $(SUBST) packaging/$$f > $(STAGE)/DEBIAN/$$f && chmod 755 $(STAGE)/DEBIAN/$$f; done
	dpkg-deb -Zgzip --root-owner-group -b $(STAGE) $(DEB)
	@echo "Built $(DEB)"

clean:
	rm -rf build
