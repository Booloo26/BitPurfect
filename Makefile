APP_NAME      = BitPurfect
BUNDLE_ID     = com.booloo.BitPurfect
CONFIG        = release
BUILD_DIR     = .build/release
APP_BUNDLE    = .build/$(APP_NAME).app
VERSION       = $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Packaging/Info.plist)

# Local development signing: a self-signed certificate in the login keychain. Fine on the
# machine that built the app, rejected by Gatekeeper anywhere else.
SIGN_IDENTITY = BitPurfect Dev

# Distribution signing. Override on the command line once you're enrolled in the Apple
# Developer Program, e.g.
#   make dist DIST_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=notary
DIST_IDENTITY ?= Developer ID Application
NOTARY_PROFILE ?= notary

DIST_DIR      = .build/dist
DMG           = $(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg

.PHONY: build bundle sign run stop clean icon dist dist-adhoc dmg notarize

build:
	swift build -c $(CONFIG)

# Regenerates the icon from the design. Checked-in output means a normal build needs neither
# this step nor a Swift run, but the mark stays reproducible from source.
icon:
	swift Packaging/GenerateIcon.swift Packaging/AppIcon.iconset
	iconutil -c icns Packaging/AppIcon.iconset -o Packaging/AppIcon.icns

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp Packaging/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Packaging/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@for dylib in $(BUILD_DIR)/*.dylib; do \
		[ -e "$$dylib" ] && cp "$$dylib" $(APP_BUNDLE)/Contents/MacOS/ || true; \
	done
	@for res in $(BUILD_DIR)/*.bundle; do \
		[ -e "$$res" ] && cp -R "$$res" $(APP_BUNDLE)/Contents/Resources/ || true; \
	done

sign: bundle
	@for dylib in $(APP_BUNDLE)/Contents/MacOS/*.dylib; do \
		[ -e "$$dylib" ] && codesign --force --sign "$(SIGN_IDENTITY)" "$$dylib" || true; \
	done
	@for res in $(APP_BUNDLE)/Contents/Resources/*.bundle; do \
		[ -e "$$res" ] && codesign --force --sign "$(SIGN_IDENTITY)" "$$res" || true; \
	done
	codesign --force --sign "$(SIGN_IDENTITY)" --identifier $(BUNDLE_ID) $(APP_BUNDLE)
	codesign -dv --verbose=2 $(APP_BUNDLE)

# Both helper processes outlive a plain kill of the app, so they're named explicitly.
stop:
	@pkill -f "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@pkill -f "run.pl.*$(APP_NAME)" 2>/dev/null || true
	@pkill -f 'log stream --predicate .*ACAppleLosslessDecoder' 2>/dev/null || true
	@sleep 0.3

run: stop sign
	open $(APP_BUNDLE)

# ---------------------------------------------------------------------------------------------
# Distribution
#
# `dist` is the path that produces something other people can actually open: signed with a
# Developer ID, hardened runtime on (notarization refuses without it), notarized, and stapled so
# it verifies with no network. Requires Apple Developer Program enrolment.
#
# `dist-adhoc` is the free fallback. It cannot avoid Gatekeeper — recipients have to approve the
# app once in System Settings — so it's for people you can give instructions to, not strangers.
# ---------------------------------------------------------------------------------------------

dist: bundle
	@echo "==> signing for distribution with '$(DIST_IDENTITY)'"
	@for dylib in $(APP_BUNDLE)/Contents/MacOS/*.dylib; do \
		[ -e "$$dylib" ] && codesign --force --timestamp --options runtime \
			--sign "$(DIST_IDENTITY)" "$$dylib" || true; \
	done
	@for res in $(APP_BUNDLE)/Contents/Resources/*.bundle; do \
		[ -e "$$res" ] && codesign --force --timestamp --options runtime \
			--sign "$(DIST_IDENTITY)" "$$res" || true; \
	done
	codesign --force --timestamp --options runtime --identifier $(BUNDLE_ID) \
		--sign "$(DIST_IDENTITY)" $(APP_BUNDLE)
	codesign --verify --deep --strict --verbose=2 $(APP_BUNDLE)
	@$(MAKE) dmg
	@$(MAKE) notarize
	@echo "==> stapling the ticket into the disk image"
	xcrun stapler staple $(DMG)
	spctl -a -vv -t install $(DMG)
	@echo "==> done: $(DMG)"

# The staging folder holds exactly what a recipient should get: the app, the licence, and the
# third-party notices those licences require to accompany a binary.
dmg:
	rm -rf $(DIST_DIR)/root "$(DMG)"
	mkdir -p $(DIST_DIR)/root
	cp -R $(APP_BUNDLE) $(DIST_DIR)/root/
	cp LICENSE $(DIST_DIR)/root/
	cp THIRD-PARTY-NOTICES.md $(DIST_DIR)/root/
	ln -s /Applications $(DIST_DIR)/root/Applications
	hdiutil create -volname "$(APP_NAME) $(VERSION)" -srcfolder $(DIST_DIR)/root \
		-ov -format UDZO "$(DMG)"

notarize:
	@echo "==> submitting to Apple (this waits for the result)"
	xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait

dist-adhoc: bundle
	@echo "==> ad-hoc signing (anonymous but valid; Gatekeeper still prompts the recipient)"
	@for dylib in $(APP_BUNDLE)/Contents/MacOS/*.dylib; do \
		[ -e "$$dylib" ] && codesign --force --sign - "$$dylib" || true; \
	done
	@for res in $(APP_BUNDLE)/Contents/Resources/*.bundle; do \
		[ -e "$$res" ] && codesign --force --sign - "$$res" || true; \
	done
	codesign --force --sign - --identifier $(BUNDLE_ID) $(APP_BUNDLE)
	@$(MAKE) dmg
	@echo "==> done: $(DMG)"
	@echo "    Recipients must approve it once: System Settings > Privacy & Security > Open Anyway."
	@echo "    See the 'Sharing it' section of README.md."

clean:
	rm -rf .build
