# The product is "Bit Perfect" to a user and `BitPerfect` to the toolchain: the bundle folder
# carries the spaced name because that's what Finder shows, while the executable, SPM target
# and paths stay unspaced. Anything holding APP_BUNDLE therefore has to be quoted.
EXECUTABLE    = BitPerfect
APP_NAME      = Bit Perfect
BUNDLE_ID     = com.booloo.BitPerfect
CONFIG        = release
BUILD_DIR     = .build/release
APP_BUNDLE    = .build/$(APP_NAME).app
SIGN_IDENTITY = Bit Perfect Dev

.PHONY: build bundle sign run stop clean icon

build:
	swift build -c $(CONFIG)

# Regenerates the icon from the design. Checked-in output means a normal build needs neither
# this step nor a Swift run, but the mark stays reproducible from source.
icon:
	swift Packaging/GenerateIcon.swift Packaging/AppIcon.iconset
	iconutil -c icns Packaging/AppIcon.iconset -o Packaging/AppIcon.icns

bundle: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp Packaging/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp Packaging/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/"
	cp $(BUILD_DIR)/$(EXECUTABLE) "$(APP_BUNDLE)/Contents/MacOS/"
	@for dylib in $(BUILD_DIR)/*.dylib; do \
		[ -e "$$dylib" ] && cp "$$dylib" "$(APP_BUNDLE)/Contents/MacOS/" || true; \
	done
	@for res in $(BUILD_DIR)/*.bundle; do \
		[ -e "$$res" ] && cp -R "$$res" "$(APP_BUNDLE)/Contents/Resources/" || true; \
	done

sign: bundle
	@for dylib in "$(APP_BUNDLE)"/Contents/MacOS/*.dylib; do \
		[ -e "$$dylib" ] && codesign --force --sign "$(SIGN_IDENTITY)" "$$dylib" || true; \
	done
	@for res in "$(APP_BUNDLE)"/Contents/Resources/*.bundle; do \
		[ -e "$$res" ] && codesign --force --sign "$(SIGN_IDENTITY)" "$$res" || true; \
	done
	codesign --force --sign "$(SIGN_IDENTITY)" --identifier $(BUNDLE_ID) "$(APP_BUNDLE)"
	codesign -dv --verbose=2 "$(APP_BUNDLE)"

# Both helper processes outlive a plain kill of the app, so they're named explicitly.
stop:
	@pkill -f "$(APP_BUNDLE)/Contents/MacOS/$(EXECUTABLE)" 2>/dev/null || true
	@pkill -f "run.pl.*$(EXECUTABLE)" 2>/dev/null || true
	@pkill -f 'log stream --predicate .*ACAppleLosslessDecoder' 2>/dev/null || true
	@sleep 0.3

run: stop sign
	open "$(APP_BUNDLE)"

clean:
	rm -rf .build
