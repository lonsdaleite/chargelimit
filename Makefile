# chargelimit: a daemon that keeps the battery between two levels, plus its Settings page (PreferenceLoader bundle).
# Rootful jailbreaks only.

NAME     := chargelimitd
PACKAGE  := com.lonsdaleite.chargelimit
VERSION  := 1.0.0
MIN_IOS  := 9.3
ARCHS    := armv7 arm64
SDK      ?= $(HOME)/theos/sdks/iPhoneOS9.3.sdk

BIN   := build/bin
STAGE := build/stage
DEB   := build/$(PACKAGE)_$(VERSION)_iphoneos-arm.deb

# armv7 is built as ARM, not Thumb: the current ld drops the Thumb bit from function addresses.
CFLAGS := -isysroot $(SDK) -fobjc-arc -fno-objc-convert-messages-to-runtime-calls -fobjc-runtime=ios-$(MIN_IOS) \
          -O2 -Wall -Wextra -Wno-unused-parameter -Werror=unguarded-availability

.PHONY: all deb sdk clean

all: deb

sdk:
	scripts/fetch-sdk.sh

$(SDK):
	@echo "Missing $(SDK); run 'make sdk'" && exit 1

$(BIN)/$(NAME)-%: src/chargelimitd.m | $(SDK)
	@mkdir -p $(dir $@)
	xcrun clang -target $*-apple-ios$(MIN_IOS) $(CFLAGS) $(EXTRA_CFLAGS) $(if $(filter armv7,$*),-marm) $< \
	    -framework Foundation -framework IOKit -lIOAccessoryManager -o $@

$(BIN)/$(NAME): $(foreach arch,$(ARCHS),$(BIN)/$(NAME)-$(arch))
	lipo -create $^ -output $@

$(BIN)/ChargeLimit-%: src/ChargeLimitController.m | $(SDK)
	@mkdir -p $(dir $@)
	xcrun clang -target $*-apple-ios$(MIN_IOS) $(CFLAGS) $(if $(filter armv7,$*),-marm) -bundle $< \
	    -F$(SDK)/System/Library/PrivateFrameworks -framework Foundation -framework UIKit -framework Preferences -o $@

$(BIN)/ChargeLimit: $(foreach arch,$(ARCHS),$(BIN)/ChargeLimit-$(arch))
	lipo -create $^ -output $@

deb: $(BIN)/$(NAME) $(BIN)/ChargeLimit packaging/control packaging/postinst packaging/prerm packaging/entitlements.plist
	rm -rf $(STAGE)
	mkdir -p $(STAGE)/DEBIAN $(STAGE)/usr/libexec
	cp -R layout/ $(STAGE)/
	cp $(BIN)/$(NAME) $(STAGE)/usr/libexec/
	cp $(BIN)/ChargeLimit $(STAGE)/Library/PreferenceBundles/ChargeLimit.bundle/
	ldid -S $(STAGE)/Library/PreferenceBundles/ChargeLimit.bundle/ChargeLimit
	ldid -Spackaging/entitlements.plist $(STAGE)/usr/libexec/$(NAME)
	sed -e 's/@VERSION@/$(VERSION)/' -e 's/@PACKAGE@/$(PACKAGE)/' packaging/control > $(STAGE)/DEBIAN/control
	install -m 755 packaging/postinst packaging/prerm $(STAGE)/DEBIAN/
	dpkg-deb -Zgzip --root-owner-group -b $(STAGE) $(DEB)
	@echo "Built $(DEB)"

clean:
	rm -rf build
